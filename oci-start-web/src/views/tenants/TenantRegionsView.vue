<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { mobileRecordSelection } from '@/composables/useMobileRecords'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import { computed, defineAsyncComponent, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { isAxiosError, isCancel } from 'axios'
import { useI18n } from 'vue-i18n'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { tenantGet, type TenantRow } from '@/api/tenant'
import { useShellStore } from '@/stores/shell'
import { usePageMotion } from '@/composables/usePageMotion'
import './tenants.scss'

const TenantRegionSecurityDialog = defineAsyncComponent(() => import('./components/TenantRegionSecurityDialog.vue'))
const TenantRegionVolumesDialog = defineAsyncComponent(() => import('./components/TenantRegionVolumesDialog.vue'))
const TenantRegionMysqlDialog = defineAsyncComponent(() => import('./components/TenantRegionMysqlDialog.vue'))
const { t, locale } = useI18n()
const compact = useCompactViewport()
const numberFormat = computed(() => new Intl.NumberFormat(locale.value))
function number(value: number) { return numberFormat.value.format(value) }
function message(value: string) { return value.startsWith('tenantRegions.') ? t(value) : value }
function requestError(cause: unknown) {
  if (isAxiosError(cause)) return cause.response?.data?.message || 'tenantRegions.common.requestFailed'
  const value = cause as { message?: string; msg?: string }
  return value?.message || value?.msg || 'tenantRegions.common.requestFailed'
}
const route = useRoute()
const router = useRouter()
const shell = useShellStore()
const root = ref<HTMLElement | null>(null)
const searchInput = ref<HTMLInputElement | null>(null)
const tableScroll = ref<HTMLElement | null>(null)
const { revealRows } = usePageMotion(root)
const tenantId = computed(() => {
  const value = String(route.query.tenantId || '')
  return /^[1-9]\d*$/.test(value) ? value : ''
})
const rows = ref<TenantRow[]>([])
const loading = ref(false)
const loaded = ref(false)
const error = ref('')
const keyword = ref('')
const initialMobilePage = Number(route.query.mobilePage)
const page = ref(Number.isSafeInteger(initialMobilePage) && initialMobilePage > 0 ? initialMobilePage : 1)
const pageSize = ref([10, 20, 50, 100].includes(Number(route.query.mobileSize)) ? Number(route.query.mobileSize) : 20)
const showAllNames = ref(false)
const revealedNames = ref(new Set<string>())
const expandedNames = ref(new Set<string>())
const selected = ref<TenantRow | null>(null)
const action = ref('')
const updatedAt = ref<Date | null>(null)
const updatedAtText = computed(() => updatedAt.value?.toLocaleTimeString(locale.value, { hour: '2-digit', minute: '2-digit' }) || '')
const syncTenant = ref<TenantRow | null>(null)
const syncState = ref<'idle' | 'running' | 'success' | 'error'>('idle')
const syncMessage = ref('')
let listRequest = 0
let syncRequest = 0
let listController: AbortController | undefined
let syncController: AbortController | undefined
let restoreFocus: HTMLElement | null = null
let disposed = false

const filteredRows = computed(() => {
  const query = keyword.value.trim().toLocaleLowerCase()
  if (!query) return rows.value
  return rows.value.filter((row) => [row.region, row.regionEn, row.defName, row.tenancyName]
    .some((value) => String(value || '').toLocaleLowerCase().includes(query)))
})
const visibleRows = computed(() => filteredRows.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
const rangeStart = computed(() => filteredRows.value.length ? (page.value - 1) * pageSize.value + 1 : 0)
const rangeEnd = computed(() => Math.min(page.value * pageSize.value, filteredRows.value.length))

function cloudType(row: TenantRow) {
  return Number(row.cloudType ?? route.query.cloudType ?? shell.cloudType)
}
function maskName(value?: string) {
  if (!value) return t('tenantRegions.common.unnamed')
  return value.length > 2 ? `${value[0]}***${value.at(-1)}` : '***'
}
function nameVisible(row: TenantRow) {
  return showAllNames.value !== revealedNames.value.has(row.id)
}
function toggleName(row: TenantRow) {
  const next = new Set(revealedNames.value)
  if (next.has(row.id)) next.delete(row.id)
  else next.add(row.id)
  revealedNames.value = next
}
function toggleNames() {
  showAllNames.value = !showAllNames.value
  revealedNames.value = new Set()
}
function toggleCustomName(row: TenantRow) {
  const next = new Set(expandedNames.value)
  if (next.has(row.id)) next.delete(row.id)
  else next.add(row.id)
  expandedNames.value = next
}
function createdAt(row: TenantRow) {
  const value = row.createdAtStr || row.createdAt
  if (!value) return '—'
  const date = Array.isArray(value)
    ? new Date(value[0], value[1] - 1, value[2], value[3] || 0, value[4] || 0, value[5] || 0)
    : new Date(String(value).replace(' ', 'T'))
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString(locale.value, {
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  })
}
function goBack() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && /^\/(?:tenants\/list|m\/tenants)(?:\?|$)/.test(previous)) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: String(route.query.cloudType || shell.cloudType) } })
}
function navigate(path: string, row?: TenantRow) {
  void router.push({ path, query: {
    cloudType: String(row ? cloudType(row) : route.query.cloudType || shell.cloudType),
    ...(row ? { tenantId: row.id } : {}),
  } })
}
function importApi() { navigate('/tenants/addSpeed') }
function viewInstances(row: TenantRow) { navigate(cloudType(row) === 2 ? '/other/instances/list' : '/oci/list', row) }
async function load() {
  const request = ++listRequest
  listController?.abort()
  error.value = ''
  if (!tenantId.value) {
    rows.value = []
    loading.value = false
    loaded.value = false
    error.value = 'tenantRegions.list.missingTenant'
    return
  }
  listController = new AbortController()
  loading.value = true
  try {
    const result = await tenantGet<Record<string, any>[]>('/tenants/regionList/json', { tenantId: tenantId.value }, { signal: listController.signal })
    if (disposed || request !== listRequest) return
    if (!Array.isArray(result)) throw new Error('tenantRegions.list.invalidResponse')
    rows.value = result.map((row) => {
      if (!row || typeof row !== 'object' || (!row.idStr && typeof row.id === 'number' && !Number.isSafeInteger(row.id))) {
        throw new Error('tenantRegions.list.unsafeId')
      }
      const id = String(row.idStr || row.id || '')
      if (!/^[1-9]\d*$/.test(id)) throw new Error('tenantRegions.list.invalidId')
      return { ...row, id } as TenantRow
    })
    loaded.value = true
    page.value = Math.min(page.value, Math.max(1, Math.ceil(filteredRows.value.length / pageSize.value)))
    updatedAt.value = new Date()
    await nextTick()
    if (!disposed && request === listRequest) revealRows()
  } catch (cause) {
    if (!disposed && request === listRequest && !isCancel(cause)) error.value = requestError(cause)
  } finally {
    if (!disposed && request === listRequest) loading.value = false
  }
}
function clearSearch() {
  keyword.value = ''
  searchInput.value?.focus()
}
function search() { page.value = 1 }
function changePage(value: number) { page.value = value }
function changePageSize(value: number) {
  pageSize.value = value
  page.value = 1
}

interface RegionAction { id: string; label: string; icon: string; path?: string }
function rowActions(row: TenantRow): RegionAction[] {
  if (cloudType(row) === 2) return [
    { id: 'boot', label: t('tenantRegions.actions.boot'), icon: 'i-mdi-plus-circle-outline', path: '/tenants/gcpBootPage' },
    { id: 'sync', label: t('tenantRegions.actions.sync'), icon: 'i-mdi-sync' },
  ]
  if (cloudType(row) !== 1) return []
  const items: RegionAction[] = []
  if (Number(row.supportAI) === 1) items.push({ id: 'chat', label: t('tenantRegions.actions.chat'), icon: 'i-mdi-brain', path: '/ai/chat' })
  items.push(
    { id: 'sync', label: t('tenantRegions.actions.sync'), icon: 'i-mdi-sync' },
    { id: 'boot', label: t('tenantRegions.actions.boot'), icon: 'i-mdi-plus-circle-outline', path: '/tenants/bootPage' },
    { id: 'tasks', label: t('tenantRegions.actions.tasks'), icon: 'i-mdi-play-circle-outline', path: '/boot/fullBootList' },
    { id: 'volumes', label: t('tenantRegions.actions.volumes'), icon: 'i-mdi-harddisk' },
    { id: 'security', label: t('tenantRegions.actions.security'), icon: 'i-mdi-shield-check-outline' },
    { id: 'instances', label: t('tenantRegions.actions.instances'), icon: 'i-mdi-server', path: '/oci/list' },
    { id: 'mysql', label: t('tenantRegions.actions.mysql'), icon: 'i-mdi-database-outline' },
  )
  return items
}
function runAction(item: RegionAction, row: TenantRow) {
  if (item.path) navigate(item.path, row)
  else if (item.id === 'sync') void startSync(row)
  else {
    restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
    selected.value = row
    action.value = item.id
  }
}
function restoreActionFocus() {
  void nextTick(() => {
    if (disposed) return
    if (restoreFocus?.isConnected) restoreFocus.focus({ preventScroll: true })
    else tableScroll.value?.focus({ preventScroll: true })
    restoreFocus = null
  })
}
function closeAction() {
  action.value = ''
  selected.value = null
  restoreActionFocus()
}
async function startSync(row: TenantRow) {
  if (syncState.value === 'running') return
  restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
  syncTenant.value = row
  syncState.value = 'running'
  syncMessage.value = 'tenantRegions.sync.progress'
  const request = ++syncRequest
  syncController?.abort()
  syncController = new AbortController()
  try {
    const result = await tenantGet<{ status: string; message?: string }>('/tenants/syncOci', { tenantId: row.id }, { signal: syncController.signal, timeout: 180000 })
    if (disposed || request !== syncRequest) return
    if (result?.status !== 'success') throw new Error(result?.message || 'tenantRegions.sync.invalidResponse')
    syncState.value = 'success'
    syncMessage.value = 'tenantRegions.sync.success'
    await load()
    if (!disposed && request === syncRequest && error.value) syncMessage.value = 'tenantRegions.sync.refreshFailed'
  } catch (cause) {
    if (disposed || request !== syncRequest || isCancel(cause)) return
    syncState.value = 'error'
    syncMessage.value = (cause as { code?: string }).code === 'ECONNABORTED'
      ? 'tenantRegions.sync.timeout'
      : requestError(cause)
  }
}
function closeSync() {
  if (syncState.value === 'running') return
  syncTenant.value = null
  syncState.value = 'idle'
  restoreActionFocus()
}
function handleShortcut(event: KeyboardEvent) {
  if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey || action.value || syncTenant.value) return
  const target = event.target as HTMLElement | null
  if (target?.closest('input, textarea, select, [contenteditable="true"], [role="dialog"]')) return
  event.preventDefault()
  searchInput.value?.focus()
}
watch(keyword, () => { page.value = 1 })
// A refreshed detail URL can refer to a region beyond the first local page.
watch([() => mobileRecordSelection(route.query, 'tenant-regions'), filteredRows, loading], () => {
  const value = mobileRecordSelection(route.query, 'tenant-regions')
  if (loading.value || !value) return
  const index = filteredRows.value.findIndex(row => String(row.id) === value)
  if (index >= 0) page.value = Math.floor(index / pageSize.value) + 1
}, { flush: 'sync' })
watch([page, pageSize], () => {
  if (!compact.value) return
  if (route.query.mobilePage === String(page.value) && route.query.mobileSize === String(pageSize.value)) return
  void router.replace({ query: { ...route.query, mobilePage: String(page.value), mobileSize: String(pageSize.value) } })
}, { flush: 'post' })
watch([page, pageSize, keyword], () => {
  if (tableScroll.value) tableScroll.value.scrollTop = 0
  revealRows()
}, { flush: 'post' })
watch(tenantId, () => {
  syncRequest++
  syncController?.abort()
  syncTenant.value = null
  syncState.value = 'idle'
  selected.value = null
  action.value = ''
  rows.value = []
  loaded.value = false
  keyword.value = ''
  page.value = 1
  showAllNames.value = false
  revealedNames.value = new Set()
  expandedNames.value = new Set()
  updatedAt.value = null
  void load()
})
onMounted(() => {
  void load()
  document.addEventListener('keydown', handleShortcut)
})
onBeforeUnmount(() => {
  disposed = true
  listRequest++
  syncRequest++
  listController?.abort()
  syncController?.abort()
  document.removeEventListener('keydown', handleShortcut)
})
</script>

<template>
  <div ref="root" class="tenants-page tenant-regions-page">
    <section class="tenant-card" :aria-label="t('tenantRegions.list.title')" :aria-busy="loading" data-motion-enter>
      <div class="list-toolbar">
        <PageBackButton :title="t('tenantRegions.list.back')" @click="goBack" />
        <form class="tenant-search" role="search" @submit.prevent="search">
          <i class="i-mdi-magnify" aria-hidden="true" />
          <input ref="searchInput" v-model="keyword" :aria-label="t('tenantRegions.list.search')" :placeholder="t('tenantRegions.list.searchPlaceholder')" autocomplete="off" @keydown.esc.prevent="clearSearch" />
          <button v-if="keyword" type="button" :aria-label="t('tenantRegions.list.clearSearch')" @click="clearSearch"><i class="i-mdi-close-circle" aria-hidden="true" /></button>
          <kbd v-else aria-hidden="true">/</kbd>
        </form>
        <div class="toolbar-actions" data-page-error-anchor>
          <button type="button" class="toolbar-button privacy-toggle" :aria-pressed="showAllNames" :title="showAllNames ? t('tenantRegions.list.hideAll') : t('tenantRegions.list.showAll')" :aria-label="showAllNames ? t('tenantRegions.list.hideAll') : t('tenantRegions.list.showAll')" @click="toggleNames"><i :class="showAllNames ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /></button>
          <button type="button" class="toolbar-button" :disabled="loading || !tenantId" :title="updatedAt ? t('tenantRegions.list.refreshAt', { time: updatedAtText }) : t('tenantRegions.list.refresh')" :aria-label="t('tenantRegions.list.refresh')" @click="load"><i class="i-mdi-refresh" :class="{ 'region-spinning': loading }" aria-hidden="true" /></button>
          <PrimaryBtn class="tenant-import" @click="importApi"><i class="i-mdi-plus" aria-hidden="true" />{{ t('tenantRegions.list.import') }}</PrimaryBtn>
        </div>
      </div>
      <PageErrorNotice v-if="error">
        <div>{{ message(error) }}</div>
        <GhostBtn v-if="tenantId" :disabled="loading" @click="load">{{ t('tenantRegions.common.retry') }}</GhostBtn>
      </PageErrorNotice>
      <div class="table-stage">
        <div v-if="loading && loaded" class="refresh-track" aria-hidden="true"><span /></div>
        <div ref="tableScroll" class="table-scroll" tabindex="0" :aria-label="t('tenantRegions.list.tableLabel')">
          <MobileRecordList v-if="compact" drilldown list-id="tenant-regions" :record-keys="visibleRows.map(row => String(row.id))" :loading="loading">
            <MobileRecordCard v-for="row in visibleRows" :key="row.id" :record-key="String(row.id)" :summary-title="row.defName || row.region || row.regionEn || t('tenantRegions.list.noName')" :summary-meta="`${nameVisible(row) ? row.tenancyName || t('tenantRegions.common.unnamed') : maskName(row.tenancyName)} · ${row.region || row.regionEn || t('tenantRegions.list.noRegion')}`" :summary-status="t(row.openBootFlag ? 'tenantRegions.list.booting' : row.apiSynced ? 'tenantRegions.list.synced' : 'tenantRegions.list.unsynced')" :summary-tone="row.openBootFlag || row.apiSynced ? 'success' : 'neutral'">
              <template #identity>
                <button type="button" class="edit-name region-custom-name mobile-record-title" :class="{ 'is-expanded': expandedNames.has(row.id) }" :title="row.defName || t('tenantRegions.list.noCustomName')" :aria-expanded="expandedNames.has(row.id)" @click="toggleCustomName(row)">{{ row.defName || t('tenantRegions.list.noName') }}</button>
                <button type="button" class="private-name" :aria-label="t(nameVisible(row) ? 'tenantRegions.list.hideName' : 'tenantRegions.list.showName')" @click="toggleName(row)"><i :class="nameVisible(row) ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /><span>{{ nameVisible(row) ? row.tenancyName || t('tenantRegions.common.unnamed') : maskName(row.tenancyName) }}</span></button>
              </template>
              <template v-if="rowActions(row).length" #actions>
                <el-dropdown trigger="click" placement="bottom-end" popper-class="tenant-action-menu" @command="(item: RegionAction) => runAction(item, row)">
                  <button type="button" class="more-button" :aria-label="t('tenantRegions.list.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
                  <template #dropdown><el-dropdown-menu><el-dropdown-item v-for="item in rowActions(row)" :key="item.id" :command="item"><i :class="item.icon" aria-hidden="true" /><span>{{ item.label }}</span></el-dropdown-item></el-dropdown-menu></template>
                </el-dropdown>
              </template>
              <dl class="mobile-record-fields">
                <div class="mobile-record-wide"><dt>{{ t('tenantRegions.list.region') }}</dt><dd><button v-if="[1, 2].includes(cloudType(row))" type="button" class="cell-link mobile-region-name" @click="viewInstances(row)">{{ row.region || row.regionEn || t('tenantRegions.list.noRegion') }}</button><span v-else>{{ row.region || row.regionEn || '—' }}</span><span v-if="row.regionEn && row.regionEn !== row.region" class="mobile-record-subtitle">{{ row.regionEn }}</span></dd></div>
                <div><dt>{{ t('tenantRegions.list.tasks') }}</dt><dd><span class="task-state" :class="{ 'task-running': row.openBootFlag }">{{ t(row.openBootFlag ? 'tenantRegions.list.booting' : 'tenantRegions.list.noTasks') }}</span></dd></div>
                <div><dt>{{ t('tenantRegions.list.syncState') }}</dt><dd><span class="region-sync-state" :class="{ 'is-synced': row.apiSynced }">{{ t(row.apiSynced ? 'tenantRegions.list.synced' : 'tenantRegions.list.unsynced') }}</span></dd></div>
                <div><dt>{{ t('tenantRegions.list.homeRegion') }}</dt><dd>{{ t(row.isHomeRegion ? 'tenantRegions.list.homeRegion' : 'tenantRegions.list.no') }}</dd></div>
                <div><dt>{{ t('tenantRegions.list.createdAt') }}</dt><dd>{{ createdAt(row) }}</dd></div>
              </dl>
              <template v-if="rowActions(row).length" #footer>
                <button v-for="item in rowActions(row).filter(item => ['boot', 'instances', 'volumes'].includes(item.id))" :key="item.id" type="button" class="mobile-record-button" @click="runAction(item, row)"><i :class="item.icon" aria-hidden="true" />{{ item.label }}</button>
                <button type="button" class="mobile-record-button" :disabled="syncState === 'running'" @click="startSync(row)"><i class="i-mdi-sync" aria-hidden="true" />{{ t('tenantRegions.actions.sync') }}</button>
              </template>
            </MobileRecordCard>
            <p v-if="loading && !loaded" class="mobile-record-loading" role="status">{{ t('tenantRegions.list.loading') }}</p>
          </MobileRecordList>
          <table v-else class="tenant-table">
            <thead><tr>
              <th scope="col" class="region-index">{{ t('tenantRegions.list.index') }}</th>
              <th scope="col" class="identity-column">{{ t('tenantRegions.list.name') }}</th>
              <th scope="col">{{ t('tenantRegions.list.region') }}</th>
              <th scope="col">{{ t('tenantRegions.list.tasks') }}</th>
              <th scope="col">{{ t('tenantRegions.list.homeRegion') }}</th>
              <th scope="col">{{ t('tenantRegions.list.syncState') }}</th>
              <th scope="col">{{ t('tenantRegions.list.createdAt') }}</th>
              <th scope="col" class="row-actions-column">{{ t('tenantRegions.common.actions') }}</th>
            </tr></thead>
            <tbody v-if="!loaded && loading" aria-hidden="true"><tr v-for="n in 6" :key="n" class="skeleton-row"><td v-for="column in 8" :key="column"><span class="skeleton" /></td></tr></tbody>
            <tbody v-else>
              <tr v-for="(row, index) in visibleRows" :key="`${row.id}-${index}`" data-motion-row>
                <td class="region-index">{{ number(rangeStart + index) }}</td>
                <td>
                  <button type="button" class="edit-name region-custom-name" :class="{ 'is-expanded': expandedNames.has(row.id) }" :title="row.defName || t('tenantRegions.list.noCustomName')" :aria-expanded="expandedNames.has(row.id)" @click="toggleCustomName(row)">{{ row.defName || t('tenantRegions.list.noName') }}</button>
                  <button type="button" class="private-name" :aria-label="nameVisible(row) ? t('tenantRegions.list.hideName') : t('tenantRegions.list.showName')" @click="toggleName(row)"><i :class="nameVisible(row) ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /><span>{{ nameVisible(row) ? row.tenancyName || t('tenantRegions.common.unnamed') : maskName(row.tenancyName) }}</span></button>
                </td>
                <td>
                  <button v-if="[1, 2].includes(cloudType(row))" type="button" class="cell-link region-name" :title="t('tenantRegions.list.instanceLink', { region: row.region || row.regionEn || t('tenantRegions.common.currentRegion') })" @click="viewInstances(row)">{{ row.region || row.regionEn || t('tenantRegions.list.noRegion') }}</button>
                  <span v-else class="region-name">{{ row.region || row.regionEn || '—' }}</span>
                  <span v-if="row.regionEn && row.regionEn !== row.region" class="cell-secondary">{{ row.regionEn }}</span>
                </td>
                <td><span class="task-state" :class="{ 'task-running': row.openBootFlag }"><i :class="row.openBootFlag ? 'i-mdi-play-circle-outline' : 'i-mdi-minus-circle-outline'" aria-hidden="true" />{{ row.openBootFlag ? t('tenantRegions.list.booting') : t('tenantRegions.list.noTasks') }}</span></td>
                <td><span :class="row.isHomeRegion ? 'region-home' : 'region-secondary'">{{ row.isHomeRegion ? t('tenantRegions.list.homeRegion') : t('tenantRegions.list.no') }}</span></td>
                <td><span class="region-sync-state" :class="{ 'is-synced': row.apiSynced }"><i :class="row.apiSynced ? 'i-mdi-check-circle-outline' : 'i-mdi-minus-circle-outline'" aria-hidden="true" />{{ row.apiSynced ? t('tenantRegions.list.synced') : t('tenantRegions.list.unsynced') }}</span></td>
                <td class="created-at">{{ createdAt(row) }}</td>
                <td class="row-actions-column">
                  <div v-if="rowActions(row).length" class="row-actions">
                    <button type="button" class="more-button" :title="t('tenantRegions.sync.title')" :aria-label="t('tenantRegions.sync.title')" :disabled="syncState === 'running'" @click="startSync(row)"><i class="i-mdi-sync" aria-hidden="true" /></button>
                    <el-dropdown trigger="click" placement="bottom-end" popper-class="tenant-action-menu" :show-timeout="0" :hide-timeout="80" @command="(item: RegionAction) => runAction(item, row)">
                      <button type="button" class="more-button" :title="t('tenantRegions.list.more')" :aria-label="t('tenantRegions.list.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
                      <template #dropdown><el-dropdown-menu><el-dropdown-item v-for="item in rowActions(row)" :key="item.id" :command="item"><i :class="item.icon" aria-hidden="true" /><span>{{ item.label }}</span></el-dropdown-item></el-dropdown-menu></template>
                    </el-dropdown>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
          <div v-if="!loading && !filteredRows.length && !error" class="tenant-empty" role="status">
            <span class="empty-icon"><i :class="keyword.trim() ? 'i-mdi-magnify' : 'i-mdi-earth'" aria-hidden="true" /></span>
            <h3>{{ keyword.trim() ? t('tenantRegions.list.noMatch') : t('tenantRegions.list.empty') }}</h3>
            <p>{{ keyword.trim() ? t('tenantRegions.list.noMatchHint') : t('tenantRegions.list.emptyHint') }}</p>
            <GhostBtn v-if="keyword.trim()" @click="clearSearch">{{ t('tenantRegions.list.clearSearch') }}</GhostBtn>
          </div>
        </div>
      </div>
      <PagePagination :current-page="page" :page-size="pageSize" :total="filteredRows.length" :page-sizes="[10, 20, 50, 100]" @current-change="changePage" @size-change="changePageSize">
        <span aria-live="polite">{{ loading && !loaded ? t('tenantRegions.list.loading') : t('tenantRegions.list.range', { start: number(rangeStart), end: number(rangeEnd), total: number(filteredRows.length) }) }}</span>
      </PagePagination>
    </section>
    <TenantRegionSecurityDialog v-if="action === 'security' && selected" :key="selected.id" :tenant="selected" @close="closeAction" @changed="load" />
    <TenantRegionVolumesDialog v-if="action === 'volumes' && selected" :key="selected.id" :tenant="selected" @close="closeAction" @changed="load" />
    <TenantRegionMysqlDialog v-if="action === 'mysql' && selected" :key="selected.id" :tenant="selected" @close="closeAction" @changed="load" />
    <el-dialog :model-value="Boolean(syncTenant)" :title="t('tenantRegions.sync.title')" width="min(420px, calc(100vw - 32px))" class="tenant-region-sync-dialog" :close-on-click-modal="false" :close-on-press-escape="syncState !== 'running'" :show-close="syncState !== 'running'" @close="closeSync">
      <PageErrorNotice v-if="syncState === 'error'"><strong>{{ syncTenant?.region || syncTenant?.regionEn || t('tenantRegions.common.currentRegion') }}</strong><p>{{ message(syncMessage) }}</p></PageErrorNotice>
      <div v-else class="region-sync-content" role="status" aria-live="polite">
        <i :class="syncState === 'running' ? 'i-mdi-loading region-spinning' : syncState === 'success' ? 'i-mdi-check-circle-outline' : 'i-mdi-alert-circle-outline'" class="sync-icon" aria-hidden="true" />
        <div><strong>{{ syncTenant?.region || syncTenant?.regionEn || t('tenantRegions.common.currentRegion') }}</strong><p>{{ message(syncMessage) }}</p></div>
      </div>
      <template #footer><GhostBtn :disabled="syncState === 'running'" @click="closeSync">{{ syncState === 'running' ? t('tenantRegions.sync.running') : t('tenantRegions.common.close') }}</GhostBtn></template>
    </el-dialog>
  </div>
</template>

<style scoped>
.tenant-regions-page .region-index { width: 60px; color: var(--text-secondary); font-variant-numeric: tabular-nums; }
.tenant-regions-page .task-state { font-size: var(--font-size-body); }
.tenant-regions-page .identity-column { width: 210px; min-width: 210px; }
.tenant-regions-page .region-custom-name.is-expanded { max-width: 260px; white-space: normal; overflow-wrap: anywhere; }
.region-home { color: var(--brand); font-size: var(--font-size-body); }
.region-secondary { color: var(--text-secondary); font-size: var(--font-size-body); }
.region-sync-state { display: inline-flex; align-items: center; gap: 5px; color: var(--text-secondary); font-size: var(--font-size-body); white-space: nowrap; }
.region-sync-state.is-synced { color: var(--brand); }
.region-sync-content { display: flex; align-items: flex-start; gap: 14px; padding: 8px 0; }
.region-sync-content .sync-icon { flex: none; margin-top: 2px; color: var(--brand); font-size: 25px; }
.region-sync-content strong { color: var(--text-primary); font-weight: 600; font-size: var(--font-size-body); }
.region-sync-content p { margin: 8px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.7; overflow-wrap: anywhere; }
.region-spinning { animation: region-spin 900ms linear infinite; }
@keyframes region-spin { to { transform: rotate(360deg); } }
@media (max-width: 760px) {
  .tenant-regions-page .tenant-search { flex: 1 1 160px; width: auto; }
  .tenant-regions-page .mobile-region-name { overflow-wrap: anywhere; }
  .tenant-regions-page .mobile-record-card .region-custom-name { max-width: 100%; }
}
@media (prefers-reduced-motion: reduce) { .region-spinning { animation: none; } }
</style>
