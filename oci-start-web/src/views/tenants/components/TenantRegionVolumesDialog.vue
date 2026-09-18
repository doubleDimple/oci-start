<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { isAxiosError } from 'axios'
import { ElMessage, ElMessageBox, type TableInstance } from 'element-plus'
import { tenantCsrfToken, tenantGet, tenantPut, type TenantRow } from '@/api/tenant'
import request from '@/api/request'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'

interface BootVolume {
  id: string
  displayName: string
  instanceName?: string | null
  sizeInGBs?: number | null
  vpusPerGB?: number | null
}

const { t, locale } = useI18n()
const compact = useCompactViewport()
const route = useRoute()
const numberFormat = computed(() => new Intl.NumberFormat(locale.value))
function number(value: number | null | undefined) { return value == null ? '—' : numberFormat.value.format(value) }
function message(value: string) {
  return value.startsWith('tenantRegions.') ? t(value, { min: number(minimumVpus.value) }) : value
}
function requestError(cause: unknown) {
  if (isAxiosError(cause)) return cause.response?.data?.message || 'tenantRegions.common.requestFailed'
  const value = cause as { message?: string; msg?: string }
  return value?.message || value?.msg || 'tenantRegions.common.requestFailed'
}
const props = defineProps<{ tenant: TenantRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const tenantId = computed(() => String(props.tenant.id))
const tenantName = computed(() => props.tenant.defName || t('tenantRegions.common.currentTenant'))
const heading = ref<HTMLElement>()
const table = ref<TableInstance>()
const volumes = ref<BootVolume[]>([])
const loading = ref(false)
const busy = ref<'save' | 'delete' | ''>('')
const deletingId = ref('')
const error = ref('')
const keyword = ref('')
const page = ref(1)
const pageSize = ref(10)
const editing = ref<BootVolume | null>(null)
const editName = ref('')
const editVpus = ref(10)
const originalVpus = ref(10)
const editError = ref('')
const filteredVolumes = computed(() => {
  const search = keyword.value.trim().toLowerCase()
  return search ? volumes.value.filter(volume => `${volume.displayName || ''} ${volume.instanceName || ''}`.toLowerCase().includes(search)) : volumes.value
})
const pageVolumes = computed(() => filteredVolumes.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
const mobileListId = computed(() => `region-volumes-${tenantId.value}`)
const mobileVolumes = computed(() => typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith(`${mobileListId.value}:`) ? filteredVolumes.value : pageVolumes.value)
const orphanCount = computed(() => volumes.value.filter(volume => !volume.instanceName).length)
const minimumVpus = computed(() => Math.min(10, originalVpus.value))
let generation = 0
let readController = new AbortController()

function close() {
  if (busy.value) return
  generation++
  readController.abort()
  emit('close')
}

function resetSize() {
  const dialog = heading.value?.closest<HTMLElement>('.tenant-region-volumes-dialog')
  if (!dialog) return
  dialog.style.removeProperty('width')
  dialog.style.removeProperty('height')
}

function clampPage() {
  page.value = Math.max(1, Math.min(page.value, Math.ceil(filteredVolumes.value.length / pageSize.value)))
}

async function loadVolumes() {
  if (loading.value || busy.value) return
  const current = generation
  const id = tenantId.value
  loading.value = true
  error.value = ''
  try {
    const result = await tenantGet<BootVolume[]>('/tenants/boot-volumes', { tenantId: id }, { signal: readController.signal, timeout: 120000 })
    if (current !== generation) return
    if (!Array.isArray(result)) throw new Error('tenantRegions.volumes.invalidResponse')
    volumes.value = result
    clampPage()
  } catch (cause) {
    if (current === generation) error.value = requestError(cause)
  } finally {
    if (current === generation) loading.value = false
  }
}

function startEditing(volume: BootVolume) {
  if (busy.value || loading.value) return
  editing.value = volume
  editName.value = volume.displayName || ''
  const performance = Number(volume.vpusPerGB ?? 10)
  originalVpus.value = Number.isFinite(performance) ? performance : 10
  // Retain a server-provided zero; changing only the name must not increase performance.
  editVpus.value = originalVpus.value
  editError.value = ''
}

function cancelEditing() {
  if (!busy.value) editing.value = null
}

async function saveVolume() {
  const volume = editing.value
  if (!volume || busy.value) return
  editError.value = ''
  const name = editName.value.trim()
  if (!name) { editError.value = 'tenantRegions.volumes.nameRequired'; return }
  const displayName = name === volume.displayName ? '' : name
  const vpusPerGB = editVpus.value === originalVpus.value ? -1 : editVpus.value
  if (vpusPerGB !== -1 && (!Number.isInteger(vpusPerGB) || vpusPerGB < minimumVpus.value || vpusPerGB > 120 || vpusPerGB % 10 !== 0)) {
    editError.value = 'tenantRegions.volumes.invalidPerformance'
    return
  }
  if (!displayName && vpusPerGB === -1) { editing.value = null; return }
  const current = generation
  const id = tenantId.value
  busy.value = 'save'
  try {
    const result = await tenantPut<{ success: boolean; message?: string }>(`/tenants/update-volumes/${encodeURIComponent(volume.id)}`, {
      tenantId: id, displayName, vpusPerGB,
    }, { timeout: 120000 })
    if (current !== generation) return
    if (!result?.success) throw new Error(result?.message || 'tenantRegions.volumes.updateFailed')
    if (displayName) volume.displayName = displayName
    if (vpusPerGB !== -1) volume.vpusPerGB = vpusPerGB
    editing.value = null
    clampPage()
    ElMessage.success(t('tenantRegions.volumes.updated'))
    emit('changed')
  } catch (cause) {
    if (current === generation) editError.value = requestError(cause)
  } finally {
    if (current === generation) busy.value = ''
  }
}

async function deleteVolume(volume: BootVolume) {
  if (volume.instanceName || busy.value || loading.value) return
  const current = generation
  const id = tenantId.value
  const volumeId = volume.id
  busy.value = 'delete'
  deletingId.value = volumeId
  error.value = ''
  try {
    await ElMessageBox.confirm(t('tenantRegions.volumes.deleteMessage', { name: volume.displayName || volumeId }), t('tenantRegions.volumes.deleteTitle'), {
      type: 'warning', confirmButtonText: t('tenantRegions.common.confirmDelete'), cancelButtonText: t('tenantRegions.common.cancel'), closeOnClickModal: false,
      customClass: 'tenant-region-volume-confirm',
      confirmButtonClass: 'tenant-region-volume-delete-confirm',
    })
    if (current !== generation) return
    const csrfHeader = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
    const result: unknown = await request.request({
      method: 'DELETE', url: `/tenants/delete-volume/${encodeURIComponent(volumeId)}`,
      data: { tenantId: id }, headers: { 'Content-Type': 'application/json', [csrfHeader]: tenantCsrfToken() },
      timeout: 120000, silent: true,
    })
    if (current !== generation) return
    const response = result as { success?: boolean; message?: string }
    if (!response?.success) throw new Error(response?.message || 'tenantRegions.volumes.deleteFailed')
    volumes.value = volumes.value.filter(item => item.id !== volumeId)
    clampPage()
    ElMessage.success(t('tenantRegions.volumes.deleted'))
    emit('changed')
  } catch (cause) {
    if (current === generation && cause !== 'cancel' && cause !== 'close') error.value = requestError(cause)
  } finally {
    if (current === generation) { busy.value = ''; deletingId.value = '' }
  }
}

watch([keyword, pageSize], () => { page.value = 1 })
watch(page, async () => { await nextTick(); table.value?.setScrollTop(0) })
watch(tenantId, () => {
  generation++
  readController.abort()
  readController = new AbortController()
  loading.value = false
  busy.value = ''
  deletingId.value = ''
  error.value = ''
  editing.value = null
  keyword.value = ''
  page.value = 1
  volumes.value = []
  void loadVolumes()
}, { immediate: true })
onBeforeUnmount(() => { generation++; readController.abort() })

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<BootVolume>
</script>

<template>
  <el-dialog :model-value="true" :title="t('tenantRegions.volumes.title')" width="min(960px, calc(100vw - 32px))" class="tenant-region-volumes-dialog" align-center append-to-body :close-on-click-modal="false" :close-on-press-escape="!busy" :show-close="!busy" @close="close">
    <template #header="{ titleId }">
      <div ref="heading" class="volume-heading"><span :id="titleId" class="volume-title">{{ t('tenantRegions.volumes.title') }}</span><span class="volume-context">{{ tenantName }}<span v-if="tenant.region"> · {{ tenant.region }}</span></span></div>
    </template>

    <Transition name="region-volume-switch" mode="out-in">
      <section v-if="!editing" key="list" class="volume-list" :aria-busy="loading || !!busy">
        <div class="volume-toolbar">
          <el-input v-model="keyword" class="volume-search" :placeholder="t('tenantRegions.volumes.search')" clearable :disabled="loading || !!busy" :aria-label="t('tenantRegions.volumes.search')"><template #prefix><span class="i-mdi-magnify" aria-hidden="true" /></template></el-input>
          <div class="volume-toolbar-actions"><span v-if="!loading" class="volume-count">{{ t('tenantRegions.volumes.count', { count: number(volumes.length) }) }}<span v-if="orphanCount">{{ t('tenantRegions.volumes.orphanCount', { count: number(orphanCount) }) }}</span></span><GhostBtn :loading="loading" :disabled="!!busy" @click="loadVolumes"><span class="i-mdi-refresh" aria-hidden="true" />{{ t('tenantRegions.common.refresh') }}</GhostBtn></div>
        </div>
        <PageErrorNotice v-if="error">{{ message(error) }}</PageErrorNotice>
      <MobileRecordList v-if="compact" drilldown :list-id="mobileListId" :record-keys="filteredVolumes.map(volume => volume.id)" :loading="loading" class="volume-mobile-list">
        <MobileRecordCard v-for="volume in mobileVolumes" :key="volume.id" :record-key="volume.id" :summary-title="volume.displayName || '—'" :summary-meta="volume.instanceName || t('tenantRegions.volumes.unattached')" :summary-status="volume.sizeInGBs == null ? undefined : `${number(volume.sizeInGBs)} GB`">
            <template #identity><h3 class="mobile-record-title">{{ volume.displayName || '—' }}</h3></template>
            <dl class="mobile-record-fields">
              <div class="mobile-record-wide"><dt>{{ t('tenantRegions.volumes.instance') }}</dt><dd>{{ volume.instanceName || t('tenantRegions.volumes.unattached') }}</dd></div>
              <div><dt>{{ t('tenantRegions.volumes.capacity') }}</dt><dd class="volume-number">{{ number(volume.sizeInGBs) }}</dd></div>
              <div><dt>{{ t('tenantRegions.volumes.performanceUnit') }}</dt><dd class="volume-number">{{ number(volume.vpusPerGB) }}</dd></div>
            </dl>
            <template #footer>
              <GhostBtn :disabled="loading || !!busy" @click="startEditing(volume)">{{ t('tenantRegions.common.edit') }}</GhostBtn>
              <GhostBtn v-if="!volume.instanceName" danger :loading="busy === 'delete' && deletingId === volume.id" :disabled="loading || !!busy" @click="deleteVolume(volume)">{{ t('tenantRegions.common.delete') }}</GhostBtn>
            </template>
          </MobileRecordCard>
          <p v-if="loading || !pageVolumes.length" class="volume-mobile-empty" role="status">{{ t(loading ? 'tenantRegions.volumes.loading' : error ? 'tenantRegions.volumes.failed' : keyword ? 'tenantRegions.volumes.noMatch' : 'tenantRegions.volumes.empty') }}</p>
        </MobileRecordList>
        <div v-else class="volume-table-wrap">
          <el-table ref="table" v-loading="loading" :data="pageVolumes" row-key="id" height="100%" class="volume-table" :empty-text="loading ? t('tenantRegions.volumes.loading') : error ? t('tenantRegions.volumes.failed') : keyword ? t('tenantRegions.volumes.noMatch') : t('tenantRegions.volumes.empty')">
            <el-table-column :label="t('tenantRegions.volumes.instance')" min-width="165" show-overflow-tooltip><template #default="{ row }"><span v-if="row.instanceName">{{ row.instanceName }}</span><span v-else class="unattached"><span />{{ t('tenantRegions.volumes.unattached') }}</span></template></el-table-column>
            <el-table-column prop="displayName" :label="t('tenantRegions.volumes.name')" min-width="225" show-overflow-tooltip />
            <el-table-column :label="t('tenantRegions.volumes.capacity')" width="116" align="right"><template #default="{ row }"><span class="volume-number">{{ number(row.sizeInGBs) }}</span></template></el-table-column>
            <el-table-column :label="t('tenantRegions.volumes.performanceUnit')" width="110" align="right"><template #default="{ row }"><span class="volume-number">{{ number(row.vpusPerGB) }}</span></template></el-table-column>
            <el-table-column :label="t('tenantRegions.common.actions')" width="144" fixed="right"><template #default="{ row }"><div class="volume-row-actions"><el-button link :disabled="loading || !!busy" @click="startEditing(row)">{{ t('tenantRegions.common.edit') }}</el-button><el-button v-if="!row.instanceName" link type="danger" :loading="busy === 'delete' && deletingId === row.id" :disabled="loading || !!busy" @click="deleteVolume(row)">{{ t('tenantRegions.common.delete') }}</el-button></div></template></el-table-column>
          </el-table>
        </div>
        <PagePagination embedded class="volume-pagination" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50]" :total="filteredVolumes.length" :disabled="loading || !!busy"><span class="volume-count">{{ t('tenantRegions.volumes.total', { count: number(filteredVolumes.length) }) }}</span></PagePagination>
      </section>

      <section v-else key="editor" class="volume-editor" :aria-label="t('tenantRegions.volumes.editTitle')">
        <button class="volume-back" type="button" :disabled="!!busy" @click="cancelEditing"><span aria-hidden="true">←</span> {{ t('tenantRegions.volumes.back') }}</button>
        <div class="volume-editor-intro"><h3>{{ t('tenantRegions.volumes.editHeading') }}</h3><p>{{ editing.instanceName || t('tenantRegions.volumes.unattached') }}<span> · {{ number(editing.sizeInGBs) }} GB</span></p></div>
        <el-form label-position="top" :disabled="!!busy" @submit.prevent="saveVolume">
          <el-form-item :label="t('tenantRegions.volumes.name')" required><el-input v-model="editName" :placeholder="t('tenantRegions.volumes.namePlaceholder')" /></el-form-item>
          <div class="volume-performance"><div class="performance-heading"><label id="region-volume-performance-label">{{ t('tenantRegions.volumes.performance') }}</label><strong>{{ number(editVpus) }}</strong></div><el-slider v-model="editVpus" :min="minimumVpus" :max="120" :step="10" aria-labelledby="region-volume-performance-label" /><div class="performance-scale"><span>{{ number(minimumVpus) }} VPUs/GB</span><span>{{ number(120) }} VPUs/GB</span></div></div>
          <el-alert v-if="['tenantRegions.volumes.nameRequired', 'tenantRegions.volumes.invalidPerformance'].includes(editError)" :title="message(editError)" type="error" :closable="false" show-icon class="volume-alert" />
          <PageErrorNotice v-else-if="editError">{{ message(editError) }}</PageErrorNotice>
          <div class="volume-edit-actions"><GhostBtn :disabled="!!busy" @click="cancelEditing">{{ t('tenantRegions.common.cancel') }}</GhostBtn><PrimaryBtn :loading="busy === 'save'" :disabled="!!busy && busy !== 'save'" @click="saveVolume">{{ t('tenantRegions.volumes.save') }}</PrimaryBtn></div>
        </el-form>
      </section>
    </Transition>

    <template #footer><div class="volume-footer"><button v-if="!compact" type="button" class="volume-reset" :disabled="!!busy" @click="resetSize"><span class="i-mdi-arrow-expand-all" aria-hidden="true" />{{ t('tenantRegions.volumes.resetSize') }}</button><GhostBtn :disabled="!!busy" @click="close">{{ t('tenantRegions.common.close') }}</GhostBtn></div></template>
  </el-dialog>
</template>

<style scoped>
:global(.tenant-region-volumes-dialog) { font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
:global(.tenant-region-volumes-dialog .el-button), :global(.tenant-region-volumes-dialog .el-input__inner), :global(.tenant-region-volumes-dialog .el-select__wrapper), :global(.tenant-region-volumes-dialog .el-form-item__label), :global(.tenant-region-volumes-dialog .el-table) { font-size: var(--font-size-body); }
:global(.tenant-region-volumes-dialog .el-alert__title) { font-size: var(--font-size-body); }
:global(.tenant-region-volumes-dialog .el-alert__description), :global(.tenant-region-volumes-dialog .el-form-item__error), :global(.tenant-region-volumes-dialog .el-empty__description p) { font-size: var(--font-size-secondary); }
:global(.tenant-region-volumes-dialog) { display: flex; flex-direction: column; height: min(80dvh, 760px); min-height: min(480px, calc(100dvh - 32px)); min-width: min(360px, calc(100vw - 32px)); max-height: calc(100dvh - 32px); max-width: calc(100vw - 32px); overflow: hidden; resize: both; padding: 26px; }
:global(.tenant-region-volumes-dialog .el-dialog__body) { display: flex; flex-direction: column; flex: 1; min-height: 0; overflow: auto; }
:global(.tenant-region-volumes-dialog .el-dialog__header) { padding-bottom: 12px; }
:global(.tenant-region-volumes-dialog .el-dialog__footer) { flex-shrink: 0; padding-top: 18px; }
:global(.tenant-region-volume-confirm) { font-family: var(--sans); --el-messagebox-title-color: var(--text-primary); --el-messagebox-content-color: var(--text-primary); --el-messagebox-font-size: var(--font-size-dialog-title); --el-messagebox-content-font-size: var(--font-size-body); }
:global(.tenant-region-volume-confirm .el-message-box__title) { font-weight: 600; }
:global(.tenant-region-volume-confirm .tenant-region-volume-delete-confirm) { --el-button-bg-color: var(--status-danger); --el-button-border-color: var(--status-danger); --el-button-hover-bg-color: var(--status-danger); --el-button-hover-border-color: var(--status-danger); }
.volume-heading { display: flex; align-items: baseline; gap: 12px; padding-right: 28px; }
.volume-title { flex-shrink: 0; font-size: var(--font-size-dialog-title); font-weight: 600; line-height: 1.4; color: var(--text-primary); }
.volume-context { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: var(--font-size-secondary); color: var(--text-secondary); }
.volume-list { display: flex; flex-direction: column; flex: 1; min-height: 240px; }
.volume-toolbar, .volume-toolbar-actions, .volume-footer, .volume-row-actions { display: flex; align-items: center; }
.volume-toolbar { gap: 12px; justify-content: space-between; margin-bottom: 12px; }
.volume-search { width: 270px; max-width: 100%; }
.volume-toolbar-actions { gap: 14px; }
.volume-count { color: var(--text-secondary); font-size: var(--font-size-secondary); white-space: nowrap; }
.volume-table-wrap { flex: 1; min-height: 150px; overflow: hidden; border: 1px solid var(--border); border-radius: 14px; }
.volume-table { font-family: var(--sans); }
.volume-table :deep(th.el-table__cell) { background: var(--bg-search); color: var(--text-secondary); font-size: var(--font-size-body); font-weight: 600; }
.volume-table :deep(td.el-table__cell) { height: 52px; padding-block: 8px; font-size: var(--font-size-body); }
.volume-table :deep(.el-table__inner-wrapper::before) { display: none; }
.volume-row-actions { gap: 16px; }
.volume-row-actions :deep(.el-button + .el-button) { margin-left: 0; }
.volume-number { font-variant-numeric: tabular-nums; }
.unattached { display: inline-flex; align-items: center; gap: 6px; font-size: var(--font-size-body); color: var(--text-secondary); }
.unattached > span { width: 5px; height: 5px; border-radius: 50%; background: var(--status-warn); }
.volume-pagination { margin-top: 18px; }
.volume-alert { margin-bottom: 16px; flex-shrink: 0; }
.volume-editor { width: min(100%, 580px); margin: 0 auto; padding: 4px 0 16px; color: var(--text-primary); }
.volume-back, .volume-reset { display: inline-flex; align-items: center; gap: 7px; border: 0; padding: 0; background: transparent; font: inherit; font-size: var(--font-size-body); color: var(--text-primary); cursor: pointer; }
.volume-back { padding: 8px 0; }
.volume-back:hover, .volume-reset:hover { color: var(--brand); }
.volume-back:focus-visible, .volume-reset:focus-visible { outline: 2px solid var(--brand); outline-offset: 4px; border-radius: 4px; }
.volume-back:disabled, .volume-reset:disabled { opacity: .5; cursor: default; }
.volume-editor-intro { margin: 18px 0 24px; }
.volume-editor-intro h3 { margin: 0 0 8px; font-size: var(--font-size-section); font-weight: 600; }
.volume-editor-intro p { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.volume-editor :deep(.el-form-item__label) { font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
.volume-editor :deep(.el-input__wrapper) { min-height: 42px; border-radius: 12px; }
.volume-performance { padding: 20px 24px; margin: 22px 0; background: var(--bg-search); border-radius: 16px; }
.performance-heading { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.performance-heading label { font-size: var(--font-size-body); color: var(--text-primary); }
.performance-heading strong { font-size: var(--font-size-body); font-weight: 600; color: var(--text-primary); font-variant-numeric: tabular-nums; }
.performance-scale { display: flex; justify-content: space-between; margin-top: 2px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.volume-edit-actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; }
.volume-footer { justify-content: space-between; gap: 16px; }
.region-volume-switch-enter-active { transition: opacity .18s ease, transform .22s cubic-bezier(.22, 1, .36, 1); }
.region-volume-switch-leave-active { transition: opacity .12s ease; }
.region-volume-switch-enter-from { opacity: 0; transform: translateY(6px); }
.region-volume-switch-leave-to { opacity: 0; }
@media (max-width: 760px) {
  :global(.tenant-region-volumes-dialog) { padding: 18px; resize: none; height: auto !important; min-height: 0; min-width: 0; }
  .volume-list { min-height: 0; }
  .volume-heading { flex-wrap: wrap; gap: 6px; }
  .volume-context { flex-basis: 100%; white-space: normal; overflow-wrap: anywhere; }
  .volume-mobile-list { padding: 0; max-height: 48dvh; overflow-y: auto; overscroll-behavior: contain; }
  .volume-mobile-empty { display: grid; place-items: center; min-height: 88px; padding: 16px; margin: 0; text-align: center; line-height: 1.6; }
  .volume-mobile-list :deep(.btn) { min-height: 44px; }
  .volume-pagination { margin-top: 12px; }
  .volume-footer { justify-content: flex-end; }
  .volume-toolbar { align-items: stretch; flex-direction: column; gap: 12px; }
  .volume-search { width: 100%; }
  .volume-toolbar-actions { justify-content: space-between; flex-wrap: wrap; gap: 10px; }
  .volume-count { white-space: normal; overflow-wrap: anywhere; }
}
@media (prefers-reduced-motion: reduce) {
  .region-volume-switch-enter-active, .region-volume-switch-leave-active { transition: none; }
  .region-volume-switch-enter-from { transform: none; }
}
</style>
