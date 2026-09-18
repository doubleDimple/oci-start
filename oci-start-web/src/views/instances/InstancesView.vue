<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import { computed, defineAsyncComponent, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { isCancel } from 'axios'
import { ElMessage } from 'element-plus'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { usePageMotion } from '@/composables/usePageMotion'
import { getInstances, getInstanceTenants, getInstanceRegions, getInstanceParent, instanceError, isInstanceTenantId, type InstanceRow, type InstanceTenant } from '@/api/instances'
import '../tenants/tenants.scss'
import './instances.scss'

const InstanceOperationDialog = defineAsyncComponent(() => import('./components/InstanceOperationDialog.vue'))
const InstanceExportDialog = defineAsyncComponent(() => import('./components/InstanceExportDialog.vue'))
const InstanceNetworkDialog = defineAsyncComponent(() => import('./components/InstanceNetworkDialog.vue'))
const InstanceReinstallDialog = defineAsyncComponent(() => import('./components/InstanceReinstallDialog.vue'))
type Operation = 'start' | 'stop' | 'terminate' | 'remark' | 'name' | 'config' | 'volume' | 'vpu' | 'delete'
type Action = Operation | 'ip' | 'ipv6' | 'copy4' | 'copy6' | 'ssh' | 'console' | 'network' | 'reinstall'
interface MenuItem { id: Action; label: string; icon: string; danger?: boolean; disabled?: boolean }
const { t, locale } = useI18n()
const compact = useCompactViewport()
const route = useRoute()
const router = useRouter()
const root = ref<HTMLElement | null>(null)
const tableScroll = ref<HTMLElement | null>(null)
const { revealRows } = usePageMotion(root)
const rows = ref<InstanceRow[]>([])
const total = ref(0)
const loading = ref(false)
const loaded = ref(false)
const listError = ref<unknown>(null)
const parents = ref<InstanceTenant[]>([])
const regions = ref<InstanceTenant[]>([])
const parentsLoading = ref(false)
const parentsLoaded = ref(false)
const regionsLoading = ref(false)
const parentError = ref<unknown>(null)
const regionError = ref<unknown>(null)
const selectedParent = ref('')
const selectedRegion = ref('')
const showAllNames = ref(false)
const revealedNames = ref(new Set<string>())
const selected = ref<InstanceRow | null>(null)
const operation = ref<Operation | ''>('')
const networkAction = ref<'ip' | 'ipv6' | ''>('')
const reinstallOpen = ref(false)
const exportOpen = ref(false)
const updatedAt = ref<Date | null>(null)
const pageSizes = [10, 20, 30, 50]
let disposed = false
let listSequence = 0
let regionSequence = 0
let listController: AbortController | undefined
let parentController: AbortController | undefined
let regionController: AbortController | undefined
let displayedQuery = ''
let restoreFocus: HTMLElement | null = null
const rawTenantId = computed(() => route.query.tenantId)
const tenantId = computed(() => typeof rawTenantId.value === 'string' ? rawTenantId.value : '')
const invalidFilter = computed(() => rawTenantId.value != null && (!tenantId.value || !isInstanceTenantId(tenantId.value)))
const pageIndex = computed(() => {
  const value = Number(route.query.page ?? 0)
  return Number.isSafeInteger(value) && value >= 0 && value <= 2147483646 ? value : 0
})
const size = computed(() => pageSizes.includes(Number(route.query.size)) ? Number(route.query.size) : 10)
const queryKey = computed(() => JSON.stringify([route.path, rawTenantId.value, pageIndex.value, size.value]))
const parentOptions = computed(() => [...parents.value].sort((a, b) => tenantName(a).localeCompare(tenantName(b), locale.value)))
const regionOptions = computed(() => [...regions.value].sort((a, b) => a.region.localeCompare(b.region, locale.value)))
const lastRefresh = computed(() => updatedAt.value ? t('instances.refreshed', { time: new Intl.DateTimeFormat(locale.value, { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(updatedAt.value) }) : t('instances.refresh'))
const scopeLabel = computed(() => {
  if (!tenantId.value) return ''
  const region = regions.value.find(value => value.id === tenantId.value)
  return region?.region || t('instances.scoped', { id: tenantId.value })
})
const rangeLabel = computed(() => t('instances.range', {
  start: number(rows.value.length ? pageIndex.value * size.value + 1 : 0),
  end: number(rows.value.length ? pageIndex.value * size.value + rows.value.length : 0), total: number(total.value),
}))

function number(value: number | null) { return value == null ? '—' : new Intl.NumberFormat(locale.value).format(value) }
function tenantName(value: InstanceTenant) { return value.userName || value.tenancyName || t('instances.unnamed') }
function nameVisible(row: InstanceRow) { return showAllNames.value !== revealedNames.value.has(row.id) }
function maskedName(row: InstanceRow) {
  const value = row.tenancyName || row.userName
  if (!value) return t('instances.unnamed')
  if (nameVisible(row)) return value
  return value.length > 2 ? `${value[0]}***${value.at(-1)}` : '***'
}
function toggleName(row: InstanceRow) {
  const next = new Set(revealedNames.value)
  if (next.has(row.id)) next.delete(row.id)
  else next.add(row.id)
  revealedNames.value = next
}
function toggleNames() { showAllNames.value = !showAllNames.value; revealedNames.value = new Set() }
function stateCode(row: InstanceRow) { return row.state.toUpperCase() }
function stateLabel(row: InstanceRow) {
  const code = stateCode(row)
  return ['RUNNING', 'STOPPED', 'STARTING', 'STOPPING', 'TERMINATING', 'TERMINATED', 'PROVISIONING'].includes(code)
    ? t(`instances.states.${code}`) : row.state || t('instances.states.UNKNOWN')
}
function createdAt(value: InstanceRow['createTime']) {
  if (value == null || value === '') return '—'
  const parsed = new Date(typeof value === 'string' ? value.replace(' ', 'T') : value)
  return Number.isNaN(parsed.getTime()) ? String(value) : new Intl.DateTimeFormat(locale.value, { year: 'numeric', month: '2-digit', day: '2-digit' }).format(parsed)
}
function remark(row: InstanceRow) { return row.remark && row.remark !== '未设置' ? row.remark : t('instances.noRemark') }
function rowActions(row: InstanceRow): MenuItem[] {
  // Keep complete utility names in source so UnoCSS can extract every icon,
  // including entries that only appear for a particular instance state.
  const item = (id: Action, key: string, icon: string, extra: Partial<MenuItem> = {}): MenuItem => ({ id, label: t(`instances.${key}`), icon, ...extra })
  return [
    ...(stateCode(row) === 'STOPPED' ? [item('start', 'start', 'i-mdi-play-outline')] : []),
    ...(stateCode(row) === 'RUNNING' ? [item('stop', 'stop', 'i-mdi-stop-circle-outline')] : []),
    item('terminate', 'terminate', 'i-mdi-power', { danger: true }),
    item('remark', 'remark', 'i-mdi-note-edit-outline'), item('name', 'rename', 'i-mdi-pencil-outline'),
    item('config', 'config', 'i-mdi-chip'), item('volume', 'resize', 'i-mdi-harddisk'),
    item('vpu', 'vpu', 'i-mdi-tune-vertical', { disabled: !row.bootVolumeId || row.bootVolumeId === '-1' }),
    item('copy4', 'copyIpv4', 'i-mdi-content-copy', { disabled: !row.publicIps }), item('ip', 'changeIp', 'i-mdi-ip-network-outline'),
    ...(row.ipv6Addresses.trim() ? [item('copy6', 'copyIpv6', 'i-mdi-content-copy')] : []),
    item('ipv6', row.ipv6Addresses.trim() ? 'manageIpv6' : 'enableIpv6', 'i-mdi-web'),
    item('ssh', 'ssh', 'i-mdi-console'), item('console', 'console', 'i-mdi-monitor'),
    item('network', 'network', 'i-mdi-lan', { disabled: !row.instanceId }),
    item('reinstall', 'reinstall', 'i-mdi-restore'), item('delete', 'delete', 'i-mdi-trash-can-outline', { danger: true }),
  ]
}
async function copyAddress(value: string) {
  try { await navigator.clipboard.writeText(value); if (!disposed) ElMessage.success(t('instances.copied')) }
  catch { if (!disposed) ElMessage.error(t('instances.copyFailed')) }
}
function runAction(item: MenuItem, row: InstanceRow) {
  if (item.disabled || loading.value) return
  const id = item.id
  if (id === 'copy4' || id === 'copy6') { void copyAddress(id === 'copy4' ? row.publicIps : row.ipv6Addresses); return }
  if (id === 'ssh') { void router.push({ path: '/oci/terminal', query: { instanceId: row.id } }); return }
  if (id === 'console') { void router.push(`/oci/console/terminal/${encodeURIComponent(row.id)}`); return }
  if (id === 'network') { void router.push({ path: '/oci/vnic/manage', query: { instanceId: row.instanceId } }); return }
  restoreFocus = root.value?.querySelector<HTMLElement>(`[data-instance-actions="${row.id}"]`) || null
  selected.value = row
  if (id === 'ip' || id === 'ipv6') networkAction.value = id
  else if (id === 'reinstall') reinstallOpen.value = true
  else operation.value = id
}
function openExport() { restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null; exportOpen.value = true }
function openTenantDetails() {
  if (!tenantId.value || invalidFilter.value) return
  void router.push({ path: '/instanceDetail/bootList', query: { tenantId: tenantId.value, page: String(pageIndex.value), size: String(size.value) } })
}
function closeDialog() {
  operation.value = ''; networkAction.value = ''; reinstallOpen.value = false; exportOpen.value = false; selected.value = null
  void nextTick(() => { if (!disposed && restoreFocus?.isConnected) restoreFocus.focus() })
}
function changed() { void loadRows() }
function goBack() {
  if (typeof window.history.state?.back === 'string') router.back()
  else void router.push('/tenants/list')
}
async function updateQuery(index: number, nextSize = size.value, scope = tenantId.value, replace = false) {
  const query = { ...route.query, page: String(index), size: String(nextSize), tenantId: scope || undefined }
  if (replace) await router.replace({ path: route.path, query })
  else await router.push({ path: route.path, query })
}
function changePage(value: number) { if (value - 1 !== pageIndex.value) void updateQuery(value - 1) }
function changeSize(value: number) { if (value !== size.value) void updateQuery(0, value) }
function applyFilter() {
  if (!selectedRegion.value || regionsLoading.value) return
  if (tenantId.value === selectedRegion.value && pageIndex.value === 0) void loadRows()
  else void updateQuery(0, size.value, selectedRegion.value)
}
function resetFilter() {
  regionSequence += 1; regionController?.abort(); regionsLoading.value = false
  selectedParent.value = ''; selectedRegion.value = ''; regions.value = []; regionError.value = null
  void updateQuery(0, size.value, '')
}
async function loadRows() {
  const sequence = ++listSequence
  listController?.abort()
  listController = new AbortController()
  const key = queryKey.value
  if (displayedQuery !== key) { rows.value = []; total.value = 0; loaded.value = false; updatedAt.value = null }
  listError.value = null
  if (invalidFilter.value) { loading.value = false; return }
  loading.value = true
  try {
    const result = await getInstances(pageIndex.value, size.value, tenantId.value, listController.signal)
    if (disposed || sequence !== listSequence) return
    if (pageIndex.value > 0 && pageIndex.value >= result.totalPages) {
      await updateQuery(Math.max(0, result.totalPages - 1), size.value, tenantId.value, true)
      return
    }
    rows.value = result.rows; total.value = result.total; loaded.value = true; displayedQuery = key
    showAllNames.value = false; revealedNames.value = new Set(); updatedAt.value = new Date()
    await nextTick()
    if (disposed || sequence !== listSequence) return
    if (tableScroll.value) tableScroll.value.scrollTop = 0
    revealRows()
  } catch (error) { if (!disposed && sequence === listSequence && !isCancel(error)) listError.value = error }
  finally { if (!disposed && sequence === listSequence) loading.value = false }
}
async function selectParent(value: string, scope = '') {
  const sequence = ++regionSequence
  regionController?.abort()
  regionController = new AbortController()
  selectedParent.value = value || ''; selectedRegion.value = ''; regions.value = []; regionError.value = null
  if (!value) { regionsLoading.value = false; return }
  regionsLoading.value = true
  try {
    const result = await getInstanceRegions(value, regionController.signal)
    if (disposed || sequence !== regionSequence) return
    regions.value = result
    selectedRegion.value = result.some(region => region.id === scope) ? scope : result.length === 1 ? result[0]!.id : ''
  } catch (error) { if (!disposed && sequence === regionSequence && !isCancel(error)) regionError.value = error }
  finally { if (!disposed && sequence === regionSequence) regionsLoading.value = false }
}
function parentChanged(value: string) { void selectParent(value) }
function retryRegions() { if (selectedParent.value) void selectParent(selectedParent.value, tenantId.value); else void hydrateScope() }
async function hydrateScope() {
  if (!parentsLoaded.value || invalidFilter.value) return
  const scope = tenantId.value
  if (!scope) { void selectParent(''); return }
  if (regions.value.some(region => region.id === scope)) { selectedRegion.value = scope; return }
  const sequence = ++regionSequence
  regionController?.abort(); regionController = new AbortController()
  const signal = regionController.signal
  regionError.value = null; regionsLoading.value = true; selectedParent.value = ''; selectedRegion.value = ''; regions.value = []
  try {
    const parent = await getInstanceParent(scope, parents.value, signal)
    if (disposed || sequence !== regionSequence) return
    if (parent) await selectParent(parent, scope)
  } catch (error) { if (!disposed && sequence === regionSequence && !isCancel(error)) regionError.value = error }
  finally { if (!disposed && sequence === regionSequence) regionsLoading.value = false }
}
async function loadParents() {
  parentController?.abort(); parentController = new AbortController()
  const signal = parentController.signal
  parentsLoading.value = true; parentError.value = null
  try {
    const result = await getInstanceTenants(signal)
    if (disposed || signal.aborted) return
    parents.value = result; parentsLoaded.value = true
    void hydrateScope()
  } catch (error) { if (!disposed && !signal.aborted && !isCancel(error)) parentError.value = error }
  finally { if (!disposed && !signal.aborted) parentsLoading.value = false }
}
watch(queryKey, loadRows, { immediate: true })
watch(tenantId, hydrateScope)
onMounted(loadParents)
onBeforeUnmount(() => {
  disposed = true; listSequence += 1; regionSequence += 1
  listController?.abort(); parentController?.abort(); regionController?.abort()
})
</script>

<template>
  <div ref="root" class="tenants-page instances-page">
    <section class="tenant-card" data-motion-enter>
      <div class="list-toolbar">
        <PageBackButton :title="t('instances.back')" @click="goBack" />
        <el-select :model-value="selectedParent" class="instance-filter" filterable clearable :placeholder="t('instances.selectTenant')" :aria-label="t('instances.selectTenant')" :loading="parentsLoading" :disabled="parentsLoading || !parentsLoaded" @change="parentChanged">
          <el-option v-for="parent in parentOptions" :key="parent.id" :label="tenantName(parent)" :value="parent.id" />
        </el-select>
        <el-select v-model="selectedRegion" class="instance-filter region-filter" filterable clearable :placeholder="t('instances.selectRegion')" :aria-label="t('instances.selectRegion')" :loading="regionsLoading" :disabled="!selectedParent || regionsLoading">
          <el-option v-for="region in regionOptions" :key="region.id" :label="region.region || region.id" :value="region.id" />
        </el-select>
        <PrimaryBtn class="filter-submit" :disabled="!selectedRegion || regionsLoading || loading" @click="applyFilter"><i class="i-mdi-magnify" aria-hidden="true" />{{ t('instances.view') }}</PrimaryBtn>
        <div class="toolbar-actions" data-page-error-anchor>
          <GhostBtn v-if="tenantId && !invalidFilter" class="tenant-details-entry" @click="openTenantDetails"><i class="i-mdi-view-list-outline" aria-hidden="true" />{{ t('tenantInstances.openDetails') }}</GhostBtn>
          <button v-if="tenantId || invalidFilter" class="toolbar-button" :title="t('instances.reset')" :aria-label="t('instances.reset')" @click="resetFilter"><i class="i-mdi-filter-remove-outline" aria-hidden="true" /></button>
          <button class="toolbar-button privacy-toggle" :aria-pressed="showAllNames" :title="t(showAllNames ? 'instances.hideNames' : 'instances.showNames')" :aria-label="t(showAllNames ? 'instances.hideNames' : 'instances.showNames')" @click="toggleNames"><i :class="showAllNames ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /></button>
          <button class="toolbar-button" :disabled="loading || invalidFilter" :title="lastRefresh" :aria-label="t('instances.refresh')" @click="loadRows"><i class="i-mdi-refresh" :class="{ 'instance-spin': loading }" aria-hidden="true" /></button>
          <button class="toolbar-button" :title="t('instances.export')" :aria-label="t('instances.export')" @click="openExport"><i class="i-mdi-download-outline" aria-hidden="true" /></button>
        </div>
      </div>
      <PageErrorNotice v-if="parentError" style="margin: 10px 18px"><div>{{ t('instances.tenantLoadFailed') }} · {{ instanceError(parentError) }}</div><GhostBtn @click="loadParents"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('instances.retry') }}</GhostBtn></PageErrorNotice>
      <PageErrorNotice v-if="regionError" style="margin: 10px 18px"><div>{{ t('instances.regionLoadFailed') }} · {{ instanceError(regionError) }}</div><GhostBtn @click="retryRegions"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('instances.retry') }}</GhostBtn></PageErrorNotice>
      <div v-if="invalidFilter" class="list-error" role="alert"><div>{{ t('instances.invalidFilter') }}</div><GhostBtn @click="resetFilter"><i class="i-mdi-filter-remove-outline" aria-hidden="true" />{{ t('instances.reset') }}</GhostBtn></div>
      <PageErrorNotice v-else-if="listError" style="margin: 10px 18px"><div>{{ t('instances.listLoadFailed') }} · {{ instanceError(listError) }}<p v-if="loaded">{{ t('instances.previousData') }}</p></div><GhostBtn :loading="loading" @click="loadRows"><i v-if="!loading" class="i-mdi-refresh" aria-hidden="true" />{{ t('instances.retry') }}</GhostBtn></PageErrorNotice>
      <div class="table-stage" :aria-busy="loading">
        <div v-if="loading" class="refresh-track" aria-hidden="true"><span /></div>
        <div ref="tableScroll" class="table-scroll" tabindex="0" role="region" :aria-label="t('instances.tableLabel')">
          <MobileRecordList v-if="compact" drilldown list-id="oci-instances" :record-keys="rows.map(row => String(row.id))" :loading="loading">
            <MobileRecordCard v-for="row in rows" :key="row.id" :record-key="String(row.id)" :summary-title="row.displayName || t('instances.unnamed')" :summary-meta="`${maskedName(row)} · ${row.regionName || row.regionCode || '—'}`" :summary-status="stateLabel(row)" :summary-tone="stateCode(row) === 'RUNNING' ? 'success' : ['STARTING', 'STOPPING', 'PROVISIONING'].includes(stateCode(row)) ? 'warning' : ['TERMINATING', 'TERMINATED'].includes(stateCode(row)) ? 'danger' : 'neutral'">
              <template #identity>
                <div class="instance-identity"><span class="instance-status" :class="`state-${stateCode(row).toLowerCase()}`" :title="stateLabel(row)" role="img" :aria-label="stateLabel(row)" /><span class="mobile-record-title">{{ row.displayName || t('instances.unnamed') }}</span></div>
                <button class="instance-tenant-name mobile-record-subtitle" :aria-pressed="nameVisible(row)" :aria-label="t(nameVisible(row) ? 'instances.hideName' : 'instances.showName')" @click="toggleName(row)">{{ maskedName(row) }}<i :class="nameVisible(row) ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /></button>
              </template>
              <template #actions>
                <el-dropdown trigger="click" placement="bottom-end" popper-class="tenant-action-menu instance-action-menu" @command="(item: MenuItem) => runAction(item, row)">
                  <button class="toolbar-button" :data-instance-actions="row.id" :disabled="loading" :aria-label="t('instances.menuLabel', { name: row.displayName || t('instances.unnamed') })"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
                  <template #dropdown><el-dropdown-menu><el-dropdown-item v-for="item in rowActions(row)" :key="item.id" :command="item" :disabled="item.disabled" :class="{ 'danger-item': item.danger }"><i class="instance-action-icon" :class="item.icon" aria-hidden="true" /><span>{{ item.label }}</span></el-dropdown-item></el-dropdown-menu></template>
                </el-dropdown>
              </template>
              <dl class="mobile-record-fields">
                <div><dt>{{ t('instances.region') }}</dt><dd>{{ row.regionName || row.regionCode || '—' }}</dd></div>
                <div><dt>{{ t('tenantInstances.instanceState') }}</dt><dd>{{ stateLabel(row) }}</dd></div>
                <div><dt>{{ t('instances.resources') }}</dt><dd>{{ number(row.ocpus) }} C / {{ number(row.memoryInGBs) }} GB</dd></div>
                <div><dt>{{ t('instances.volume') }}</dt><dd>{{ number(row.bootVolumeSizeInGBs) }} GB / {{ number(row.vpusPerGB) }}</dd></div>
                <div><dt>{{ t('instances.architecture') }}</dt><dd><span :title="row.processorDescription">{{ row.architecture && row.architecture !== 'NONE' ? row.architecture : '—' }}</span><span v-if="row.shape" class="mobile-record-subtitle">{{ row.shape }}</span></dd></div>
                <div><dt>{{ t('instances.created') }}</dt><dd>{{ createdAt(row.createTime) }}</dd></div>
                <div class="mobile-record-wide"><dt>{{ t('instances.ipv4') }}</dt><dd><button v-if="row.publicIps" class="instance-address" :aria-label="`${t('instances.copyIpv4')}: ${row.publicIps}`" @click="copyAddress(row.publicIps)">{{ row.publicIps }}<i class="i-mdi-content-copy" aria-hidden="true" /></button><span v-else>—</span></dd></div>
                <div class="mobile-record-wide"><dt>{{ t('instances.ipv6') }}</dt><dd><button v-if="row.ipv6Addresses.trim()" class="instance-address" :aria-label="`${t('instances.copyIpv6')}: ${row.ipv6Addresses}`" @click="copyAddress(row.ipv6Addresses)">{{ row.ipv6Addresses }}<i class="i-mdi-content-copy" aria-hidden="true" /></button><span v-else>{{ t('instances.disabled') }}</span></dd></div>
                <div v-if="row.remark && row.remark !== '未设置'" class="mobile-record-wide"><dt>{{ t('instances.remark') }}</dt><dd>{{ row.remark }}</dd></div>
              </dl>
              <template #footer>
                <button v-for="item in rowActions(row).filter(item => ['start', 'stop', 'ssh', 'network'].includes(item.id))" :key="item.id" class="mobile-record-button" :disabled="loading || item.disabled" @click="runAction(item, row)"><i :class="item.icon" aria-hidden="true" />{{ item.label }}</button>
              </template>
            </MobileRecordCard>
          </MobileRecordList>
          <table v-else class="tenant-table instance-table">
            <thead><tr>
              <th scope="col" class="index-column">#</th><th scope="col">{{ t('instances.tenant') }}</th><th scope="col">{{ t('instances.region') }}</th>
              <th scope="col">{{ t('instances.name') }}</th><th scope="col">{{ t('instances.resources') }}</th><th scope="col">{{ t('instances.architecture') }}</th>
              <th scope="col">{{ t('instances.volume') }}</th><th scope="col">{{ t('instances.ipv4') }}</th><th scope="col">{{ t('instances.ipv6') }}</th>
              <th scope="col">{{ t('instances.created') }}</th><th scope="col" class="instance-actions-column">{{ t('instances.actions') }}</th>
            </tr></thead>
            <tbody>
              <tr v-for="(row, index) in rows" :key="row.id" data-motion-row>
                <td class="index-column">{{ number(pageIndex * size + index + 1) }}</td>
                <td><button class="instance-tenant-name" :aria-pressed="nameVisible(row)" :aria-label="t(nameVisible(row) ? 'instances.hideName' : 'instances.showName')" :title="nameVisible(row) ? row.tenancyName || row.userName : undefined" @click="toggleName(row)">{{ maskedName(row) }}</button></td>
                <td><span class="instance-region">{{ row.regionName || row.regionCode || '—' }}</span></td>
                <td class="instance-name-column"><div class="instance-identity"><span class="instance-status" :class="`state-${stateCode(row).toLowerCase()}`" :title="stateLabel(row)" role="img" :aria-label="stateLabel(row)" /><span class="instance-name" :title="row.displayName">{{ row.displayName || t('instances.unnamed') }}</span></div><span class="instance-remark" :title="remark(row)">{{ remark(row) }}</span></td>
                <td class="instance-quantity">{{ number(row.ocpus) }} C / {{ number(row.memoryInGBs) }} GB</td>
                <td><span :title="row.processorDescription">{{ row.architecture && row.architecture !== 'NONE' ? row.architecture : '—' }}</span><span v-if="row.shape" class="instance-shape" :title="row.shape">{{ row.shape }}</span></td>
                <td class="instance-quantity">{{ number(row.bootVolumeSizeInGBs) }} GB / {{ number(row.vpusPerGB) }}</td>
                <td><button v-if="row.publicIps" class="instance-address" :title="`${t('instances.copyIpv4')}: ${row.publicIps}`" :aria-label="`${t('instances.copyIpv4')}: ${row.publicIps}`" @click="copyAddress(row.publicIps)">{{ row.publicIps }}</button><span v-else>—</span></td>
                <td><button v-if="row.ipv6Addresses.trim()" class="instance-ipv6" :title="row.ipv6Addresses" :aria-label="`${t('instances.copyIpv6')}: ${row.ipv6Addresses}`" @click="copyAddress(row.ipv6Addresses)"><i class="i-mdi-check-circle-outline" aria-hidden="true" />{{ t('instances.enabled') }}</button><span v-else class="instance-secondary">{{ t('instances.disabled') }}</span></td>
                <td class="instance-date">{{ createdAt(row.createTime) }}</td>
                <td class="instance-actions-column"><el-dropdown trigger="click" placement="bottom-end" popper-class="tenant-action-menu instance-action-menu" :show-timeout="0" :hide-timeout="80" @command="(item: MenuItem) => runAction(item, row)">
                  <button class="toolbar-button" :data-instance-actions="row.id" :disabled="loading" :aria-label="t('instances.menuLabel', { name: row.displayName || t('instances.unnamed') })"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
                  <template #dropdown><el-dropdown-menu><el-dropdown-item v-for="item in rowActions(row)" :key="item.id" :command="item" :disabled="item.disabled" :class="{ 'danger-item': item.danger }"><i class="instance-action-icon" :class="item.icon" aria-hidden="true" /><span>{{ item.label }}</span></el-dropdown-item></el-dropdown-menu></template>
                </el-dropdown></td>
              </tr>
            </tbody>
          </table>
          <div v-if="!rows.length" class="tenant-empty" role="status"><i class="empty-icon i-mdi-server-outline" aria-hidden="true" /><p>{{ loading ? t('instances.loading') : invalidFilter ? t('instances.invalidFilter') : listError ? t('instances.listLoadFailed') : t(tenantId ? 'instances.emptyFiltered' : 'instances.empty') }}</p></div>
        </div>
      </div>
      <PagePagination :disabled="loading || invalidFilter || !loaded" :current-page="pageIndex + 1" :page-size="size" :total="total" :page-sizes="pageSizes" @current-change="changePage" @size-change="changeSize">
        <div class="instance-footer-context"><span v-if="loaded">{{ rangeLabel }}</span><span v-if="scopeLabel" class="instance-scope" :title="scopeLabel">{{ scopeLabel }}</span></div>
      </PagePagination>
    </section>
    <InstanceOperationDialog v-if="selected && operation" :key="`${selected.id}-${operation}`" :row="selected" :action="operation" @close="closeDialog" @changed="changed" />
    <InstanceNetworkDialog v-if="selected && networkAction" :key="`${selected.id}-${networkAction}`" :row="selected" :action="networkAction" @close="closeDialog" @changed="changed" />
    <InstanceReinstallDialog v-if="selected && reinstallOpen" :key="selected.id" :row="selected" @close="closeDialog" @changed="changed" />
    <InstanceExportDialog v-if="exportOpen" @close="closeDialog" />
  </div>
</template>
