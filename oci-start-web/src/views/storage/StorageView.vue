<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { isMobileRecordNavigation, mobileRecordSelection } from '@/composables/useMobileRecords'
import StorageUploadDialog from './components/StorageUploadDialog.vue'
import StoragePreviewDialog from './components/StoragePreviewDialog.vue'
import { useStorageBrowser } from './useStorageBrowser'
import {
  createStorageBucket, deleteStorageBucket, deleteStorageObject, createStoragePresignedUrl,
  getStorageDownloadUrl, storageError, isStorageWriteUncertain,
  type StorageBucket, type StorageTenant, type StorageObject, type StorageBucketContext, type StorageObjectContext,
} from '@/api/objectStorage'

type AccessType = 'NoPublicAccess' | 'ObjectRead' | 'ObjectReadWithoutList'
type Action = { kind: 'create'; tenantId: string; tenantLabel: string }
  | { kind: 'deleteBucket'; target: StorageBucketContext }
  | { kind: 'deleteObject' | 'share'; target: StorageObjectContext }
const { t, locale } = useI18n()
const router = useRouter()
const route = useRoute()
const compact = useCompactViewport()
const { tenantId, selectedBucket, context, tenants, buckets, objects, resumable, loadTenants, loadBuckets, selectBucket,
  loadObjects, loadResumable, retryBuckets, retryObjects, afterObjectDelete, afterBucketDelete } = useStorageBrowser()
const mobileBucketListId = computed(() => `storage-buckets-${tenantId.value || 'none'}`)
const mobileObjectListId = computed(() => `storage-objects-${encodeURIComponent(JSON.stringify(context.value))}`)
function bucketKey(row: StorageBucket) { return JSON.stringify([row.namespace, row.name]) }
const savedTenant = typeof route.query.mobileStorageTenant === 'string' ? route.query.mobileStorageTenant : ''
const savedBucket = typeof route.query.mobileStorageBucket === 'string' ? route.query.mobileStorageBucket : ''
const savedNamespace = typeof route.query.mobileStorageNamespace === 'string' ? route.query.mobileStorageNamespace : ''
const savedBucketKey = savedBucket ? JSON.stringify([savedNamespace, savedBucket]) : mobileRecordSelection(route.query, `storage-buckets-${savedTenant}`)
const requestedObjectPage = Number(route.query.mobileStoragePage)
const savedObjectPage = Number.isSafeInteger(requestedObjectPage) && requestedObjectPage > 0 && requestedObjectPage <= 100 ? requestedObjectPage : 1
const restoringMobileContext = ref(!!savedTenant)
const keyword = ref('')
const sortedTenants = computed(() => [...tenants.rows].sort((a, b) => tenantLabel(a).localeCompare(tenantLabel(b), locale.value)))
const visibleBuckets = computed(() => {
  const query = keyword.value.trim().toLocaleLowerCase(locale.value)
  return buckets.rows.filter(row => !query || row.name.toLocaleLowerCase(locale.value).includes(query))
})
const uploadOpen = ref(false)
const uploadBusy = ref(false)
const previewOpen = ref(false)
const previewTarget = shallowRef<StorageObjectContext | null>(null)
const previewSize = ref<number | null>(null)
const action = shallowRef<Action | null>(null)
const actionState = ref<'idle' | 'pending' | 'uncertain' | 'done'>('idle')
const actionProblem = ref<ReturnType<typeof storageError> | null>(null)
const validation = ref('')
const bucketName = ref('')
const accessType = ref<AccessType>('NoPublicAccess')
const accessTypes: AccessType[] = ['NoPublicAccess', 'ObjectRead', 'ObjectReadWithoutList']
const shareUrl = ref('')
const copyFailed = ref(false)
const busy = computed(() => uploadBusy.value || actionState.value === 'pending')
const contextLocked = computed(() => busy.value || tenants.loading)
const actionTitle = computed(() => actionState.value === 'done' ? t('storageManagement.linkReady') : action.value ? t(`storageManagement.${action.value.kind}Title`) : '')
const actionHint = computed(() => {
  const current = action.value
  if (!current || current.kind === 'create') return ''
  if (current.kind === 'deleteBucket') return t('storageManagement.deleteBucketHint', { name: current.target.bucketName })
  if (current.kind === 'deleteObject') return t('storageManagement.deleteObjectHint', { name: current.target.objectName })
  return t(actionState.value === 'done' ? 'storageManagement.linkHint' : 'storageManagement.shareHint')
})
const bucketEmpty = computed(() => t(!tenantId.value ? 'storageManagement.chooseTenantHint' : buckets.loading ? 'storageManagement.loading'
  : buckets.problem ? 'storageManagement.loadFailed' : keyword.value.trim() ? 'storageManagement.noMatchingBuckets' : 'storageManagement.emptyBuckets'))
const objectEmpty = computed(() => t(!context.value ? 'storageManagement.chooseBucketHint' : objects.loading ? 'storageManagement.loading'
  : objects.problem ? 'storageManagement.loadFailed' : 'storageManagement.emptyObjects'))
let disposed = false
let actionSequence = 0

function tenantLabel(row: StorageTenant) { return row.userName || row.tenancyName || t('storageManagement.tenantId', { id: row.id }) }
function errorText(cause: unknown) { const error = storageError(cause); return error.detail || t(`storageManagement.errors.${error.key}`) }
function accessLabel(value: string) { return accessTypes.includes(value as AccessType) ? t(`storageManagement.accessTypes.${value}`) : value || t('storageManagement.unknown') }
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function fileSize(value: number | null) {
  if (value == null || !Number.isFinite(value) || value < 0) return '—'
  const unit = value === 0 ? 0 : Math.min(4, Math.floor(Math.log(value) / Math.log(1024)))
  return `${new Intl.NumberFormat(locale.value, { maximumFractionDigits: unit === 0 ? 0 : 1 }).format(value / 1024 ** unit)} ${['B', 'KiB', 'MiB', 'GiB', 'TiB'][unit]}`
}
function date(value: string | null) {
  if (!value) return '—'
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? value : new Intl.DateTimeFormat(locale.value, { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).format(parsed)
}
function bucketContext(row: StorageBucket): StorageBucketContext { return { tenantId: tenantId.value, namespace: row.namespace, bucketName: row.name } }
function objectContext(row: StorageObject): StorageObjectContext | null { return context.value ? { ...context.value, objectName: row.name } : null }
function isSelected(row: StorageBucket) { return selectedBucket.value?.name === row.name && selectedBucket.value.namespace === row.namespace }
function chooseBucket(row: StorageBucket) { if (!contextLocked.value && !isSelected(row)) { uploadOpen.value = false; previewOpen.value = false; selectBucket(row) } }
function isPreviewable(name: string) { return /\.(png|jpe?g|gif|webp|svg|pdf|txt|log|md|json|xml|html?)$/i.test(name) }
function preview(row: StorageObject) {
  if (contextLocked.value) return
  previewTarget.value = objectContext(row)
  previewSize.value = row.size
  previewOpen.value = !!previewTarget.value
}
function downloadUrl(row: StorageObject) { const target = objectContext(row); return target ? getStorageDownloadUrl(target) : undefined }
function openAction(value: Action) {
  if (contextLocked.value) return
  actionSequence++
  action.value = value
  actionState.value = 'idle'
  actionProblem.value = null
  validation.value = shareUrl.value = ''
  copyFailed.value = false
  bucketName.value = ''
  accessType.value = 'NoPublicAccess'
}
function openCreate() {
  const selected = tenants.rows.find(row => row.id === tenantId.value)
  if (selected) openAction({ kind: 'create', tenantId: selected.id, tenantLabel: tenantLabel(selected) })
}
function openObjectAction(kind: 'share' | 'deleteObject', row: StorageObject) {
  const target = objectContext(row)
  if (target) openAction({ kind, target })
}
function closeAction() {
  if (actionState.value === 'pending') return
  actionSequence++
  action.value = null
  shareUrl.value = ''
}
function inspectLatest() {
  const target = action.value
  closeAction()
  if (target?.kind === 'create' || target?.kind === 'deleteBucket') void loadBuckets()
  else if (target) void loadObjects()
}
function afterUploadChanged() { void loadObjects(1, true); void loadResumable() }
async function submitAction() {
  const target = action.value
  if (!target || busy.value || actionState.value !== 'idle') return
  validation.value = ''
  const name = bucketName.value.trim()
  if (target.kind === 'create' && !name) { validation.value = 'required'; return }
  const sequence = ++actionSequence
  actionState.value = 'pending'
  actionProblem.value = null
  try {
    if (target.kind === 'create') await createStorageBucket({ tenantId: target.tenantId, bucketName: name, publicAccessType: accessType.value })
    else if (target.kind === 'deleteBucket') await deleteStorageBucket(target.target)
    else if (target.kind === 'deleteObject') await deleteStorageObject(target.target)
    else {
      const url = await createStoragePresignedUrl(target.target, 3600)
      if (disposed || sequence !== actionSequence) return
      shareUrl.value = url
      actionState.value = 'done'
      return
    }
    if (disposed || sequence !== actionSequence) return
    actionState.value = 'idle'
    closeAction()
    ElMessage.success(t(target.kind === 'create' ? 'storageManagement.createdSuccess' : 'storageManagement.deletedSuccess'))
    if (target.kind === 'create') void loadBuckets()
    else if (target.kind === 'deleteBucket') afterBucketDelete(target.target)
    else await afterObjectDelete(target.target)
  } catch (cause) {
    if (disposed || sequence !== actionSequence) return
    actionProblem.value = storageError(cause)
    actionState.value = isStorageWriteUncertain(cause) || target.kind === 'share' ? 'uncertain' : 'idle'
  } finally {
    if (!disposed && sequence === actionSequence && actionState.value === 'pending') actionState.value = 'idle'
  }
}
async function copyLink() {
  const url = shareUrl.value
  if (!url) return
  try {
    await navigator.clipboard.writeText(url)
    if (!disposed && shareUrl.value === url) { copyFailed.value = false; ElMessage.success(t('storageManagement.copied')) }
  } catch { if (!disposed && shareUrl.value === url) copyFailed.value = true }
}
function guardLeaving() {
  if (!busy.value) return true
  ElMessage.warning(t('storageManagement.busyLeave'))
  return false
}
function back() {
  if (!guardLeaving()) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: '1' } })
}
function beforeUnload(event: BeforeUnloadEvent) { if (busy.value) { event.preventDefault(); event.returnValue = '' } }
watch(tenantId, () => { keyword.value = ''; uploadOpen.value = previewOpen.value = false })
watch([() => buckets.loading, () => buckets.rows, () => objects.loading, () => objects.page, tenantId], () => {
  if (!restoringMobileContext.value || tenants.loading || disposed) return
  if (tenantId.value !== savedTenant) { restoringMobileContext.value = false; return }
  if (buckets.loading) return
  if (!savedBucketKey || buckets.problem) { restoringMobileContext.value = false; return }
  if (!buckets.loaded) return
  const bucket = buckets.rows.find(row => bucketKey(row) === savedBucketKey)
  if (!bucket) {
    if (buckets.nextPage) void loadBuckets(true)
    else restoringMobileContext.value = false
    return
  }
  if (!savedBucket) { restoringMobileContext.value = false; return }
  if (!selectedBucket.value) { selectBucket(bucket); return }
  if (bucketKey(selectedBucket.value) !== savedBucketKey) { restoringMobileContext.value = false; return }
  if (objects.loading) return
  if (objects.problem) { restoringMobileContext.value = false; return }
  if (!objects.loaded) return
  if (!objects.problem && objects.next && objects.page < savedObjectPage) { void loadObjects(objects.page + 1); return }
  restoringMobileContext.value = false
})
watch([tenantId, context, () => objects.page, () => objects.loading, busy, compact, restoringMobileContext], () => {
  if (!compact.value || busy.value || tenants.loading || restoringMobileContext.value || objects.loading) return
  const values = { mobileStorageTenant: tenantId.value || undefined, mobileStorageNamespace: selectedBucket.value?.namespace, mobileStorageBucket: selectedBucket.value?.name, mobileStoragePage: context.value ? String(objects.page) : undefined }
  if (Object.entries(values).every(([key, value]) => route.query[key] === value)) return
  void router.replace({ query: { ...route.query, ...values } })
})
watch([context, () => route.query.mobileRecord, () => route.query.mobileRecordParents, compact], () => {
  const target = context.value
  if (!compact.value || !target || uploadOpen.value) return
  const key = encodeURIComponent(JSON.stringify([target.tenantId, target.namespace, target.bucketName]))
  if (mobileRecordSelection(route.query, `storage-upload-records-${key}`)
    || mobileRecordSelection(route.query, `storage-upload-tasks-${key}`)) uploadOpen.value = true
})
onBeforeRouteLeave(guardLeaving)
onBeforeRouteUpdate((to, from) => isMobileRecordNavigation(to, from) || guardLeaving())
onMounted(async () => {
  window.addEventListener('beforeunload', beforeUnload)
  await loadTenants()
  if (disposed) return
  if (savedTenant && tenants.rows.some(row => row.id === savedTenant)) tenantId.value = savedTenant
  else restoringMobileContext.value = false
})
onBeforeUnmount(() => { disposed = true; window.removeEventListener('beforeunload', beforeUnload) })

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<StorageObject>
</script>

<template>
  <section class="storage-page">
    <div class="storage-toolbar">
      <PageBackButton :disabled="busy" @click="back" />
      <label for="storage-tenant">{{ t('storageManagement.tenant') }}</label>
      <el-select id="storage-tenant" v-model="tenantId" class="storage-tenant" filterable clearable :loading="tenants.loading" :disabled="busy || tenants.loading" :placeholder="t('storageManagement.chooseTenant')" :no-data-text="t('storageManagement.noTenants')">
        <el-option v-for="row in sortedTenants" :key="row.id" :value="row.id" :label="tenantLabel(row)" />
      </el-select>
      <div class="storage-toolbar-actions" data-page-error-anchor>
        <GhostBtn :disabled="busy" :loading="buckets.loading || tenants.loading" @click="tenantId ? loadBuckets() : loadTenants()"><i class="i-mdi-refresh" aria-hidden="true" />{{ t(tenantId ? 'storageManagement.refreshBuckets' : 'storageManagement.reloadTenants') }}</GhostBtn>
        <PrimaryBtn :disabled="contextLocked || !tenantId" @click="openCreate"><i class="i-mdi-plus" aria-hidden="true" />{{ t('storageManagement.create') }}</PrimaryBtn>
      </div>
    </div>
    <PageErrorNotice v-if="tenants.problem" style="margin: 10px 12px"><span>{{ errorText(tenants.problem) }}</span><GhostBtn :disabled="busy" :loading="tenants.loading" @click="loadTenants">{{ t('storageManagement.reloadTenants') }}</GhostBtn></PageErrorNotice>
    <p v-if="tenants.rows.length >= 1000" class="storage-inline-warning" role="status">{{ t('storageManagement.tenantLimit') }}</p>
    <div class="storage-workspace">
      <aside class="storage-buckets" :aria-label="t('storageManagement.buckets')" :aria-busy="buckets.loading">
        <div class="storage-bucket-tools">
          <h2>{{ t('storageManagement.buckets') }}</h2>
          <el-input v-model="keyword" clearable :disabled="!tenantId" :placeholder="t('storageManagement.searchBuckets')" :aria-label="t('storageManagement.searchBuckets')" />
          <span class="storage-note">{{ t('storageManagement.loadedOnly') }}</span>
        </div>
        <PageErrorNotice v-if="buckets.problem" style="margin: 10px 12px"><span>{{ errorText(buckets.problem) }}</span><GhostBtn :disabled="busy" :loading="buckets.loading" @click="retryBuckets">{{ t('storageManagement.retry') }}</GhostBtn></PageErrorNotice>
        <p v-if="buckets.repeatedCursor" class="storage-inline-warning" role="alert">{{ t('storageManagement.cursorRepeated') }}</p>
        <div class="storage-bucket-list">
          <p v-if="!visibleBuckets.length" class="storage-empty" role="status">{{ bucketEmpty }}</p>
          <MobileRecordList v-if="compact" drilldown :list-id="mobileBucketListId" :record-keys="visibleBuckets.map(bucketKey)" :loading="buckets.loading || restoringMobileContext">
            <MobileRecordCard v-for="row in visibleBuckets" :key="bucketKey(row)" :record-key="bucketKey(row)" :summary-title="row.name" :summary-meta="row.namespace" :summary-status="accessLabel(row.publicAccess)">
              <template #identity><div class="mobile-record-title">{{ row.name }}</div><span class="mobile-record-subtitle">{{ row.namespace }}</span></template>
              <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('storageManagement.created') }}</dt><dd>{{ date(row.timeCreated) }}</dd></div><div class="mobile-record-wide"><dt>{{ t('storageManagement.access') }}</dt><dd>{{ accessLabel(row.publicAccess) }}<span class="mobile-record-subtitle">{{ t('storageManagement.accessHint') }}</span></dd></div></dl>
              <template #footer><button type="button" class="mobile-record-button" :disabled="contextLocked" :aria-pressed="isSelected(row)" @click="chooseBucket(row)">{{ t('storageManagement.objects') }}</button><button type="button" class="mobile-record-button" :disabled="contextLocked" @click="openAction({ kind: 'deleteBucket', target: bucketContext(row) })">{{ t('storageManagement.deleteBucketTitle') }}</button></template>
            </MobileRecordCard>
          </MobileRecordList>
          <template v-else><div v-for="row in visibleBuckets" :key="JSON.stringify([row.namespace, row.name])" class="storage-bucket-row" :class="{ selected: isSelected(row) }">
            <button type="button" class="storage-bucket-select" :disabled="contextLocked" :aria-pressed="isSelected(row)" @click="chooseBucket(row)">
              <span class="storage-bucket-name" :title="row.name">{{ row.name }}</span>
              <span class="storage-note storage-bucket-time" :title="`${t('storageManagement.created')}: ${date(row.timeCreated)}`">{{ date(row.timeCreated) }}</span>
              <span class="storage-access" :title="`${t('storageManagement.access')}: ${accessLabel(row.publicAccess)}. ${t('storageManagement.accessHint')}`">{{ accessLabel(row.publicAccess) }}</span>
            </button>
            <button type="button" class="storage-icon-button danger" :disabled="contextLocked" :title="t('storageManagement.deleteBucketTitle')" :aria-label="`${t('storageManagement.deleteBucketTitle')}: ${row.name}`" @click="openAction({ kind: 'deleteBucket', target: bucketContext(row) })"><i class="i-mdi-trash-can-outline" aria-hidden="true" /></button>
          </div></template>
        </div>
        <div class="storage-bucket-footer">
          <span class="storage-note">{{ t('storageManagement.loadedBuckets', { count: number(buckets.rows.length) }) }}</span>
          <GhostBtn v-if="buckets.nextPage" :disabled="busy" :loading="buckets.loading" @click="loadBuckets(true)">{{ t('storageManagement.loadMore') }}</GhostBtn>
        </div>
      </aside>
      <div class="storage-objects" :aria-busy="objects.loading">
        <div class="storage-object-tools">
          <div class="storage-object-context"><h2 :title="selectedBucket?.name">{{ selectedBucket?.name || t('storageManagement.objects') }}</h2><span v-if="selectedBucket" class="storage-note" :title="`${t('storageManagement.namespace')}: ${selectedBucket.namespace}`">{{ selectedBucket.namespace }}</span></div>
          <div class="storage-object-buttons"><GhostBtn :disabled="busy || !context" :loading="objects.loading" :title="t('storageManagement.refreshObjects')" :aria-label="t('storageManagement.refreshObjects')" @click="loadObjects()"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn><GhostBtn :disabled="contextLocked || !context" @click="uploadOpen = true"><i class="i-mdi-upload" aria-hidden="true" />{{ t('storageManagement.upload') }}</GhostBtn></div>
        </div>
        <PageErrorNotice v-if="objects.problem" style="margin: 10px 12px"><span>{{ errorText(objects.problem) }}</span><GhostBtn :disabled="busy" :loading="objects.loading" @click="retryObjects">{{ t('storageManagement.retry') }}</GhostBtn></PageErrorNotice>
        <PageErrorNotice v-if="resumable.problem" style="margin: 10px 12px"><span>{{ t('storageManagement.resumableFailed') }} {{ errorText(resumable.problem) }}</span><GhostBtn :disabled="busy" :loading="resumable.loading" @click="loadResumable">{{ t('storageManagement.retry') }}</GhostBtn></PageErrorNotice>
        <div v-else-if="resumable.loading || resumable.count" class="storage-resume-hint" role="status"><span>{{ resumable.loading ? t('storageManagement.checkingResumable') : t('storageManagement.resumableCount', { count: number(resumable.count || 0) }) }}</span><GhostBtn v-if="resumable.count && !resumable.loading" :disabled="contextLocked" @click="uploadOpen = true">{{ t('storageManagement.viewResumable') }}</GhostBtn></div>
        <p v-if="objects.repeatedCursor" class="storage-inline-warning" role="alert">{{ t('storageManagement.cursorRepeated') }}</p>
        <div class="storage-table-stage">
          <MobileRecordList v-if="compact" drilldown :list-id="mobileObjectListId" :record-keys="objects.rows.map(row => row.name)" :loading="objects.loading || restoringMobileContext">
            <MobileRecordCard v-for="row in objects.rows" :key="row.name" :record-key="row.name" :summary-title="row.name" :summary-meta="`${fileSize(row.size)} · ${date(row.timeModified)}`">
              <template #identity><div class="mobile-record-title">{{ row.name }}</div><span class="mobile-record-subtitle">{{ selectedBucket?.name }}</span></template>
              <dl class="mobile-record-fields"><div><dt>{{ t('storageManagement.size') }}</dt><dd>{{ fileSize(row.size) }}</dd></div><div><dt>{{ t('storageManagement.modified') }}</dt><dd>{{ date(row.timeModified) }}</dd></div></dl>
              <template #footer><button v-if="isPreviewable(row.name)" type="button" class="mobile-record-button" :disabled="contextLocked" @click="preview(row)">{{ t('storageManagement.preview') }}</button><a class="mobile-record-button storage-mobile-download" :href="busy ? undefined : downloadUrl(row)" :download="row.name.split('/').pop() || row.name" :aria-disabled="busy || undefined" :tabindex="busy ? -1 : 0" @click="busy && $event.preventDefault()">{{ t('storageManagement.download') }}</a><button type="button" class="mobile-record-button" :disabled="contextLocked" @click="openObjectAction('share', row)">{{ t('storageManagement.share') }}</button><button type="button" class="mobile-record-button" :disabled="contextLocked" @click="openObjectAction('deleteObject', row)">{{ t('storageManagement.delete') }}</button></template>
            </MobileRecordCard>
            <p v-if="!objects.rows.length" class="storage-empty" role="status">{{ objectEmpty }}</p>
          </MobileRecordList>
          <el-table v-else :data="objects.rows" row-key="name" height="100%" :empty-text="objectEmpty">
            <el-table-column prop="name" :label="t('storageManagement.name')" min-width="220" show-overflow-tooltip />
            <el-table-column :label="t('storageManagement.size')" width="106"><template #default="{ row }">{{ fileSize(row.size) }}</template></el-table-column>
            <el-table-column :label="t('storageManagement.modified')" min-width="172" show-overflow-tooltip><template #default="{ row }">{{ date(row.timeModified) }}</template></el-table-column>
            <el-table-column :label="t('storageManagement.actions')" width="174" fixed="right" align="center"><template #default="{ row }">
              <div class="storage-row-actions">
                <button v-if="isPreviewable(row.name)" type="button" class="storage-icon-button" :disabled="contextLocked" :title="t('storageManagement.preview')" :aria-label="`${t('storageManagement.preview')}: ${row.name}`" @click="preview(row)"><i class="i-mdi-eye-outline" aria-hidden="true" /></button>
                <span v-else class="storage-icon-placeholder" />
                <a class="storage-icon-button" :href="busy ? undefined : downloadUrl(row)" :download="row.name.split('/').pop() || row.name" :aria-disabled="busy || undefined" :tabindex="busy ? -1 : 0" :title="t('storageManagement.download')" :aria-label="`${t('storageManagement.download')}: ${row.name}`" @click="busy && $event.preventDefault()"><i class="i-mdi-download" aria-hidden="true" /></a>
                <button type="button" class="storage-icon-button" :disabled="contextLocked" :title="t('storageManagement.share')" :aria-label="`${t('storageManagement.share')}: ${row.name}`" @click="openObjectAction('share', row)"><i class="i-mdi-link-variant" aria-hidden="true" /></button>
                <button type="button" class="storage-icon-button danger" :disabled="contextLocked" :title="t('storageManagement.delete')" :aria-label="`${t('storageManagement.delete')}: ${row.name}`" @click="openObjectAction('deleteObject', row)"><i class="i-mdi-trash-can-outline" aria-hidden="true" /></button>
              </div>
            </template></el-table-column>
          </el-table>
        </div>
        <PagePagination cursor :current-page="objects.page" :has-next="!!objects.next" :has-previous="objects.page > 1" :disabled="busy || objects.loading || !context" @current-change="loadObjects">
          <span>{{ t('storageManagement.pageHint') }}</span>
        </PagePagination>
      </div>
    </div>

    <StorageUploadDialog v-model="uploadOpen" :context="context" @busy="uploadBusy = $event" @changed="afterUploadChanged" />
    <StoragePreviewDialog v-model="previewOpen" :target="previewTarget" :size="previewSize" />
    <el-dialog :model-value="!!action" :title="actionTitle" width="540px" class="storage-action-dialog" append-to-body :close-on-click-modal="false" :close-on-press-escape="actionState !== 'pending'" :show-close="actionState !== 'pending'" @update:model-value="!$event && closeAction()">
      <form v-if="action" id="storage-action-form" @submit.prevent="submitAction">
        <div class="storage-action-context">{{ action.kind === 'create' ? action.tenantLabel : action.target.bucketName }}<span v-if="action.kind === 'share' || action.kind === 'deleteObject'">{{ action.target.objectName }}</span></div>
        <p v-if="actionHint" class="storage-action-description">{{ actionHint }}</p>
        <div v-if="action.kind === 'create'" class="storage-action-fields">
          <label for="storage-bucket-name">{{ t('storageManagement.bucketName') }}</label><el-input id="storage-bucket-name" v-model="bucketName" :disabled="actionState !== 'idle'" autocomplete="off" />
          <label for="storage-access-type">{{ t('storageManagement.accessType') }}</label><el-select id="storage-access-type" v-model="accessType" :disabled="actionState !== 'idle'"><el-option v-for="value in accessTypes" :key="value" :value="value" :label="accessLabel(value)" /></el-select>
          <p v-if="accessType !== 'NoPublicAccess'" class="storage-action-warning">{{ t('storageManagement.publicHint') }}</p>
        </div>
        <div v-if="shareUrl" class="storage-action-fields"><label for="storage-share-url">{{ t('storageManagement.share') }}</label><el-input id="storage-share-url" :model-value="shareUrl" type="textarea" :rows="4" readonly /><PageErrorNotice v-if="copyFailed">{{ t('storageManagement.copyFailed') }}</PageErrorNotice></div>
        <p v-if="actionState === 'pending'" class="storage-action-note" role="status">{{ t('storageManagement.processingHint') }}</p>
        <p v-if="validation" class="storage-action-error" role="alert">{{ t(`storageManagement.${validation}`) }}</p>
        <PageErrorNotice v-else-if="actionProblem">{{ errorText(actionProblem) }}</PageErrorNotice>
        <p v-if="actionState === 'uncertain'" class="storage-action-warning" role="status">{{ t(action.kind === 'share' ? 'storageManagement.shareUncertain' : 'storageManagement.uncertain') }}</p>
      </form>
      <template #footer>
        <GhostBtn :disabled="actionState === 'pending'" @click="closeAction">{{ t(actionState === 'done' || actionState === 'uncertain' ? 'storageManagement.close' : 'storageManagement.cancel') }}</GhostBtn>
        <PrimaryBtn v-if="actionState === 'done'" @click="copyLink">{{ t('storageManagement.copy') }}</PrimaryBtn>
        <GhostBtn v-else-if="actionState === 'uncertain' && action?.kind !== 'share'" @click="inspectLatest">{{ t('storageManagement.inspect') }}</GhostBtn>
        <button v-else-if="actionState !== 'uncertain' && (action?.kind === 'deleteBucket' || action?.kind === 'deleteObject')" type="submit" form="storage-action-form" class="storage-confirm-danger" :disabled="actionState === 'pending'">{{ t(actionState === 'pending' ? 'storageManagement.processing' : 'storageManagement.confirm') }}</button>
        <PrimaryBtn v-else-if="actionState !== 'uncertain'" type="submit" form="storage-action-form" :loading="actionState === 'pending'">{{ t(action?.kind === 'create' ? 'storageManagement.create' : 'storageManagement.generate') }}</PrimaryBtn>
      </template>
    </el-dialog>
  </section>
</template>

<style lang="scss" src="./storage.scss" />
