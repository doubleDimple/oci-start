<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, defineAsyncComponent, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { mobileRecordSelection } from '@/composables/useMobileRecords'
import type { VpsRow, VpsOperationKind } from '@/api/vps'
import { fetchNetworkQualityOverview, networkQualityError, type NetworkQualityApiError, type NetworkQualityOverview, type NetworkQualityResult, type NetworkQualityTask } from '@/api/networkQuality'
import { useVpsPage } from './useVpsPage'
import { useVpsLive } from './useVpsLive'
import { useVpsLatency } from './useVpsLatency'
import VpsRowActions from './VpsRowActions.vue'
import VpsCarrierQuality from './VpsCarrierQuality.vue'
import './vps.scss'

const VpsOperationDialog = defineAsyncComponent(() => import('./VpsOperationDialog.vue'))
const VpsResourceDetails = defineAsyncComponent(() => import('./VpsResourceDetails.vue'))
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const compactViewport = useCompactViewport()
const {
  rows, loading, loaded, readProblem, lastUpdated, tenantId, contextValid, refresh,
  operation, operationPending, operationOutcome, operationResult, operationProblem,
  openOperation, submitOperation, closeOperation, contextLocked, canOperate,
  requiresReview, reviewTenantId, reviewReady, acknowledgeReview,
} = useVpsPage()
const paused = computed(() => loading.value || contextLocked.value || !loaded.value || !contextValid.value)
const ready = computed(() => loaded.value && !readProblem.value && contextValid.value)
const { connection, metricsFor, agentStatus, reconnect } = useVpsLive(rows, paused)
const { running: latencyRunning, runState: latencyState, resultFor, counts: latencyCounts, start: startLatency, stop: stopLatency } = useVpsLatency(rows, ready, paused)
const query = ref('')
const offlineOnly = ref(false)
const initialMobilePage = Number(route.query.mobilePage)
const page = ref(Number.isSafeInteger(initialMobilePage) && initialMobilePage > 0 ? initialMobilePage : 1)
const size = ref([10, 20, 30, 50].includes(Number(route.query.mobileSize)) ? Number(route.query.mobileSize) : 20)
const pageSizes = [10, 20, 30, 50]
const globalIps = ref(false)
const globalTenants = ref(false)
const visibleIps = ref(new Set<string>())
const visibleTenants = ref(new Set<string>())
const carriers = ['telecom', 'unicom', 'mobile'] as const
const columns = ['server', 'placement', 'health', 'cpu', 'memory', 'disk', 'latency', ...carriers, 'actions']
const detailId = ref<string | null>(null)
// Keep the drawer after its first opening so its close transition and focus
// restoration still run when the selected row becomes null.
const detailsMounted = ref(false)
const detailRow = computed(() => rows.value.find(row => row.id === detailId.value) ?? null)
const qualityOverview = shallowRef<NetworkQualityOverview | null>(null)
const qualityProblem = shallowRef<NetworkQualityApiError | null>(null)
const qualityLoading = ref(false)
const qualityReceivedAt = ref(0)
const qualityNow = ref(Date.now())
const qualitySnapshotStale = computed(() => !!qualityOverview.value
  && (contextLocked.value || !!qualityProblem.value || qualityNow.value - qualityReceivedAt.value > 30000))
const qualityAgents = computed(() => new Map(qualityOverview.value?.agents.map(agent => [agent.id, agent]) ?? []))
const qualityEntries = computed(() => {
  const groups = new Map<string, Array<{ task: NetworkQualityTask; result: NetworkQualityResult | null }>>()
  const samples = new Map((qualityOverview.value?.latest ?? []).map(result => [`${result.instanceId}:${result.taskId}`, result]))
  for (const task of qualityOverview.value?.tasks ?? []) {
    for (const id of task.instanceIds) {
      const entries = groups.get(id) ?? []
      const sample = samples.get(`${id}:${task.id}`)
      entries.push({ task, result: sample?.revision === task.version ? sample : null })
      groups.set(id, entries)
    }
  }
  return groups
})
let qualityDisposed = false
let qualityMounted = false
let qualitySequence = 0
let qualityController: AbortController | undefined
let qualityTimer: ReturnType<typeof setTimeout> | undefined
function stopQualityRead() {
  ++qualitySequence
  qualityController?.abort()
  qualityController = undefined
  qualityLoading.value = false
  if (qualityTimer !== undefined) clearTimeout(qualityTimer)
  qualityTimer = undefined
}
function scheduleQuality() {
  if (qualityTimer !== undefined) clearTimeout(qualityTimer)
  qualityTimer = undefined
  if (!qualityMounted || qualityDisposed || document.hidden || contextLocked.value || !contextValid.value) return
  qualityTimer = setTimeout(() => { qualityTimer = undefined; void refreshQuality() }, 10000)
}
async function refreshQuality() {
  if (!qualityMounted || qualityDisposed || document.hidden || contextLocked.value || !contextValid.value || qualityLoading.value) return
  stopQualityRead()
  const sequence = qualitySequence
  const controller = new AbortController()
  qualityController = controller
  qualityLoading.value = true
  qualityNow.value = Date.now()
  const current = () => !qualityDisposed && sequence === qualitySequence && controller === qualityController && !controller.signal.aborted
  try {
    const data = await fetchNetworkQualityOverview(controller.signal)
    if (!current()) return
    qualityOverview.value = data
    qualityProblem.value = null
    qualityReceivedAt.value = Date.now()
    qualityNow.value = qualityReceivedAt.value
  } catch (cause) {
    if (current()) qualityProblem.value = networkQualityError(cause)
  } finally {
    if (current()) { qualityController = undefined; qualityLoading.value = false; scheduleQuality() }
  }
}
function qualityVisibility() {
  qualityNow.value = Date.now()
  if (document.hidden) stopQualityRead()
  else void refreshQuality()
}
const pingCounts = computed(() => ({
  online: rows.value.filter(row => row.onLineEnable === 1).length,
  offline: rows.value.filter(row => row.onLineEnable === 0).length,
  unknown: rows.value.filter(row => row.onLineEnable == null).length,
}))
const filtered = computed(() => {
  const needle = query.value.trim().toLowerCase()
  return rows.value.filter(row => (!offlineOnly.value || row.onLineEnable === 0)
    && (!needle || [row.displayName, row.publicIps, row.tenancyName, row.regionName, row.regionCode,
      row.architecture, provider(row.cloudType), spec(row)].some(value => value.toLowerCase().includes(needle))))
})
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / size.value)))
const visibleRows = computed(() => filtered.value.slice((page.value - 1) * size.value, page.value * size.value)
  .map(row => ({ row, metrics: metricsFor(row), agentState: agentStatus(row), latency: resultFor(row) })))
const emptyText = computed(() => !loaded.value
  ? t(loading.value ? 'vps.loading' : readProblem.value ? 'vps.failed' : 'vps.notLoaded')
  : t(rows.value.length ? 'vps.noMatches' : 'vps.empty'))
const latencyDone = computed(() => latencyCounts.value.total - latencyCounts.value.queued - latencyCounts.value.running)

function number(value: number, digits = 1) { return new Intl.NumberFormat(locale.value, { maximumFractionDigits: digits }).format(value) }
function percentage(value: number | null | undefined) { return value == null ? '—' : `${number(value)}%` }
function provider(value: number | null) {
  return value === 1 ? 'Oracle Cloud' : value === 2 ? 'Google Cloud' : value === 3 ? 'Azure' : value === 4 ? 'AWS' : value == null ? '—' : 'VPS'
}
function region(row: VpsRow) { return row.regionName || row.regionCode || '—' }
function spec(row: VpsRow) {
  return [row.ocpus == null ? '—' : t('vps.cores', { count: number(row.ocpus) }),
    row.memoryInGBs == null ? '—' : t('vps.memoryGb', { count: number(row.memoryInGBs) })].join(' / ')
}
function flagLabel(value: 0 | 1 | null) { return t(value === 1 ? 'vps.online' : value === 0 ? 'vps.offline' : 'vps.unknown') }
function ipText(row: VpsRow) { return row.publicIps ? visibleIps.value.has(row.id) ? row.publicIps : '••••••' : '—' }
function toggleIp(row: VpsRow) { visibleIps.value.has(row.id) ? visibleIps.value.delete(row.id) : visibleIps.value.add(row.id) }
function toggleTenant(row: VpsRow) { visibleTenants.value.has(row.id) ? visibleTenants.value.delete(row.id) : visibleTenants.value.add(row.id) }
function toggleIps() { globalIps.value = !globalIps.value; visibleIps.value = new Set(globalIps.value ? rows.value.map(row => row.id) : []) }
function toggleTenants() { globalTenants.value = !globalTenants.value; visibleTenants.value = new Set(globalTenants.value ? rows.value.map(row => row.id) : []) }
function formatTime(value: Date | number | null) {
  if (value == null) return '—'
  const date = value instanceof Date ? value : new Date(value)
  if (!Number.isFinite(date.getTime())) return '—'
  return new Intl.DateTimeFormat(locale.value, { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(date)
}
function openDetails(row: VpsRow) {
  if (contextLocked.value) return
  detailsMounted.value = true
  detailId.value = row.id
}
function closeDetails() { detailId.value = null }
function detailIp() { if (detailRow.value) toggleIp(detailRow.value) }
function detailTenant() { if (detailRow.value) toggleTenant(detailRow.value) }
function detailQuality() { if (detailRow.value) qualityDetails(detailRow.value) }
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/oci/list')
}
function ssh(row: VpsRow) { if (!contextLocked.value) void router.push({ path: '/oci/terminal', query: { instanceId: row.id } }) }
function manageOci(row: VpsRow) {
  if (contextLocked.value || row.cloudType !== 1 || !row.tenantId) return
  void router.push({ path: '/oci/list', query: { tenantId: row.tenantId, cloudType: '1' } })
}
function qualityDetails(row?: VpsRow) {
  if (!contextLocked.value) void router.push({ path: '/system/ipSettings', query: row ? { instanceId: row.id } : {} })
}
function command(value: unknown) {
  if (contextLocked.value) return
  if (value === 'enablePing' || value === 'disablePing' || value === 'ping') openOperation(value as VpsOperationKind)
  else if (value === 'quality') qualityDetails()
  else if (value === 'ips') toggleIps()
  else if (value === 'tenants') toggleTenants()
}
function clearSearch() { query.value = ''; offlineOnly.value = false }
function allTenants() { if (!contextLocked.value) { const next = { ...route.query }; delete next.tenantId; void router.push({ path: route.path, query: next }) } }
function changeSize(value: number) { if (!contextLocked.value) { size.value = value; page.value = 1 } }
function changePage(value: number) { if (!contextLocked.value && value >= 1 && value <= totalPages.value) page.value = value }
watch([query, offlineOnly], () => { page.value = 1 })
watch(totalPages, value => { if (page.value > value) page.value = value })
// Keep direct mobile detail links usable even when the row is on another page.
watch([() => mobileRecordSelection(route.query, 'vps-instances'), filtered, loading], () => {
  const value = mobileRecordSelection(route.query, 'vps-instances')
  if (loading.value || !value) return
  const index = filtered.value.findIndex(row => String(row.id) === value)
  if (index >= 0) page.value = Math.floor(index / size.value) + 1
}, { flush: 'sync' })
watch([rows, () => route.query.mobileRecord, () => route.query.mobileRecordParents], () => {
  if (detailId.value || contextLocked.value) return
  const row = rows.value.find(item => ['telecom', 'unicom', 'mobile', 'custom'].some(operator => mobileRecordSelection(route.query, `vps-carrier-${item.id}-${operator}`)))
  if (row) openDetails(row)
})
watch([page, size], () => {
  if (!compactViewport.value || contextLocked.value) return
  if (route.query.mobilePage === String(page.value) && route.query.mobileSize === String(size.value)) return
  void router.replace({ query: { ...route.query, mobilePage: String(page.value), mobileSize: String(size.value) } })
}, { flush: 'post' })
watch(tenantId, () => { closeDetails(); clearSearch(); page.value = 1; globalIps.value = globalTenants.value = false; visibleIps.value.clear(); visibleTenants.value.clear() })
watch(detailRow, row => { if (!row) closeDetails() })
watch(rows, (current, previous) => {
  const previousById = new Map(previous.map(row => [row.id, row]))
  visibleIps.value = new Set(current.filter(row => globalIps.value || (visibleIps.value.has(row.id) && previousById.get(row.id)?.publicIps === row.publicIps)).map(row => row.id))
  visibleTenants.value = new Set(current.filter(row => globalTenants.value || (visibleTenants.value.has(row.id)
    && previousById.get(row.id)?.tenancyName === row.tenancyName
    && previousById.get(row.id)?.tenantId === row.tenantId)).map(row => row.id))
})
watch([contextLocked, contextValid], ([locked, valid]) => {
  qualityNow.value = Date.now()
  if (locked || !valid) stopQualityRead()
  else void refreshQuality()
})
onMounted(() => {
  qualityMounted = true
  document.addEventListener('visibilitychange', qualityVisibility)
  void refreshQuality()
})
onBeforeUnmount(() => {
  qualityDisposed = true
  stopQualityRead()
  document.removeEventListener('visibilitychange', qualityVisibility)
  qualityOverview.value = null
})
</script>

<template>
  <section class="vps-page" :aria-label="t('vps.title')">
    <header class="vps-toolbar">
      <PageBackButton :disabled="operationPending" @click="back" />
      <label class="vps-search"><i class="i-mdi-magnify" aria-hidden="true" /><input v-model="query" type="search" :placeholder="t('vps.search')" :aria-label="t('vps.search')" :disabled="contextLocked" autocomplete="off" /><button v-if="query || offlineOnly" type="button" :disabled="contextLocked" :title="t('vps.clear')" :aria-label="t('vps.clear')" @click="clearSearch"><i class="i-mdi-close" aria-hidden="true" /></button></label>
      <div class="vps-toolbar-actions" data-page-error-anchor>
        <GhostBtn v-if="latencyRunning" @click="stopLatency"><i class="i-mdi-stop" aria-hidden="true" />{{ t('vps.stopLatency') }}</GhostBtn>
        <PrimaryBtn v-else :disabled="!ready || paused || !rows.length" :title="t('vps.latencyHint')" @click="startLatency"><i class="i-mdi-timer-outline" aria-hidden="true" />{{ t('vps.testLatency') }}</PrimaryBtn>
        <GhostBtn :loading="loading" :disabled="contextLocked" :title="t('vps.refresh')" :aria-label="t('vps.refresh')" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn>
        <el-dropdown trigger="click" :disabled="contextLocked" placement="bottom-end" popper-class="vps-menu" @command="command">
          <GhostBtn :disabled="contextLocked" :title="t('vps.more')" :aria-label="t('vps.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></GhostBtn>
          <template #dropdown><el-dropdown-menu>
            <el-dropdown-item command="quality"><i class="i-mdi-chart-line" aria-hidden="true" />{{ t('networkQuality.title') }}</el-dropdown-item>
            <el-dropdown-item command="ips" divided><i :class="globalIps ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />{{ t(globalIps ? 'vps.hideIps' : 'vps.showIps') }}</el-dropdown-item>
            <el-dropdown-item command="tenants"><i :class="globalTenants ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />{{ t(globalTenants ? 'vps.hideTenants' : 'vps.showTenants') }}</el-dropdown-item>
            <el-dropdown-item command="enablePing" :disabled="!canOperate" divided><i class="i-mdi-play-outline" aria-hidden="true" />{{ t('vps.enablePing') }}</el-dropdown-item>
            <el-dropdown-item command="disablePing" :disabled="!canOperate"><i class="i-mdi-stop" aria-hidden="true" />{{ t('vps.disablePing') }}</el-dropdown-item>
            <el-dropdown-item command="ping" :disabled="!canOperate"><i class="i-mdi-access-point-network" aria-hidden="true" />{{ t('vps.ping') }}</el-dropdown-item>
          </el-dropdown-menu></template>
        </el-dropdown>
      </div>
    </header>
    <div class="vps-statusbar">
      <label class="vps-offline-filter"><input v-model="offlineOnly" type="checkbox" :disabled="contextLocked" />{{ t('vps.offlineOnly') }}</label>
      <span v-if="loaded" :title="t('vps.pingHint')">{{ t('vps.pingCounts', { online: number(pingCounts.online, 0), offline: number(pingCounts.offline, 0), unknown: number(pingCounts.unknown, 0) }) }}</span>
      <div class="vps-live-status" role="status" :title="t('vps.agentHint')"><span class="vps-dot" :class="{ 'is-online': connection === 'connected' }" />{{ t('vps.connectionLabel') }} · {{ t(`vps.connections.${connection}`) }}<button v-if="connection === 'disconnected' || connection === 'reconnecting'" type="button" class="vps-text-button" :disabled="paused" @click="reconnect">{{ t('vps.reconnect') }}</button></div>
    </div>
    <div v-if="tenantId" class="vps-notice"><span>{{ t('vps.tenantScope', { id: tenantId }) }}</span><GhostBtn :disabled="contextLocked" @click="allTenants"><i class="i-mdi-filter-remove-outline" aria-hidden="true" />{{ t('vps.allTenants') }}</GhostBtn></div>
    <PageErrorNotice v-if="readProblem"><span>{{ t(`vps.errors.${readProblem.key}`) }} {{ readProblem.detail }} {{ loaded ? t('vps.retained') : '' }}</span><GhostBtn :loading="loading" :disabled="contextLocked" @click="refresh">{{ t('vps.refresh') }}</GhostBtn></PageErrorNotice>
    <PageErrorNotice v-if="qualityProblem"><span>{{ t('networkQuality.title') }} · {{ t(`networkQuality.errors.${qualityProblem.key}`) }} {{ qualityOverview ? t('networkQuality.snapshotStale') : '' }}</span><button type="button" :disabled="qualityLoading || contextLocked" @click="refreshQuality">{{ t('networkQuality.refresh') }}</button></PageErrorNotice>
    <div v-if="requiresReview && !operation" class="vps-notice is-warning" role="alert"><span>{{ t('vps.unknownResult') }} {{ t('vps.reviewTarget', { id: reviewTenantId || t('vps.globalTenant') }) }}</span><GhostBtn :loading="loading" :disabled="contextLocked" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('vps.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady || contextLocked" @click="acknowledgeReview"><i class="i-mdi-check" aria-hidden="true" />{{ t('vps.reviewed') }}</GhostBtn></div>
    <div class="vps-table-body" :aria-busy="loading">
      <MobileRecordList v-if="compactViewport" drilldown list-id="vps-instances" :record-keys="visibleRows.map(({ row }) => String(row.id))" :loading="loading" class="vps-mobile-list">
        <MobileRecordCard v-for="{ row, metrics, agentState, latency } in visibleRows" :key="row.id" :record-key="String(row.id)" :summary-title="row.displayName || t('vps.unnamed')" :summary-meta="`${region(row)} · ${provider(row.cloudType)}`" :summary-status="flagLabel(row.onLineEnable)" :summary-tone="row.onLineEnable === 1 ? 'success' : row.onLineEnable === 0 ? 'danger' : 'neutral'" class="vps-mobile-card">
          <template #identity>
            <button type="button" class="mobile-record-title vps-mobile-name" :disabled="contextLocked" @click="openDetails(row)">{{ row.displayName || t('vps.unnamed') }}</button>
            <span class="mobile-record-subtitle">{{ region(row) }} · {{ provider(row.cloudType) }}</span>
          </template>
          <template #actions>
            <VpsRowActions :disabled="contextLocked" :can-operate="canOperate" :show-install="row.monitorInstalled !== true && agentState !== 'online'" :row-name="row.displayName || t('vps.unnamed')" @ssh="ssh(row)" @details="openDetails(row)" @quality="qualityDetails(row)" @install="openOperation('install', row)" @uninstall="openOperation('uninstall', row)" />
          </template>
          <dl class="mobile-record-fields vps-mobile-fields">
            <div class="mobile-record-wide">
              <dt>{{ t('vps.server') }}</dt>
              <dd><button type="button" class="vps-reveal" :disabled="!row.publicIps" :title="ipText(row)" :aria-label="t(visibleIps.has(row.id) ? 'vps.hideIp' : 'vps.showIp')" @click="toggleIp(row)"><span>{{ ipText(row) }}</span><i v-if="row.publicIps" :class="visibleIps.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></dd>
            </div>
            <div><dt>{{ t('vps.tenant') }}</dt><dd><button type="button" class="vps-reveal" :disabled="!row.tenancyName" :aria-label="t(visibleTenants.has(row.id) ? 'vps.hideTenant' : 'vps.showTenant')" @click="toggleTenant(row)"><span>{{ row.tenancyName ? visibleTenants.has(row.id) ? row.tenancyName : '••••••' : '—' }}</span><i v-if="row.tenancyName" :class="visibleTenants.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></dd></div>
            <div><dt>{{ t('vps.spec') }}</dt><dd>{{ spec(row) }}</dd></div>
            <div><dt :title="t('vps.pingHint')">{{ t('vps.pingStatus') }}</dt><dd><span class="vps-badge" :class="row.onLineEnable === 1 ? 'is-online' : row.onLineEnable === 0 ? 'is-offline' : ''">{{ flagLabel(row.onLineEnable) }}</span></dd></div>
            <div><dt :title="t('vps.agentHint')">{{ t('vps.agent') }}</dt><dd><span class="vps-badge" :class="agentState === 'online' ? 'is-online' : agentState === 'offline' ? 'is-warning' : ''">{{ t(`vps.agents.${agentState}`) }}</span></dd></div>
          </dl>
          <dl class="vps-mobile-metrics">
            <div v-for="metric in [{ key: 'cpu', value: metrics?.cpuUsage }, { key: 'memory', value: metrics?.memoryPercent }, { key: 'disk', value: metrics?.diskPercent }]" :key="metric.key">
              <dt>{{ t(`vps.${metric.key}`) }}</dt>
              <dd><span class="vps-metric" :class="{ 'is-stale': metrics?.stale, 'is-high': metric.value != null && metric.value >= 90 }">{{ percentage(metric.value) }}</span><i v-if="metrics?.stale" class="i-mdi-clock-outline vps-stale-icon" :title="t('vps.stale')" role="img" :aria-label="t('vps.stale')" /></dd>
              <span class="vps-usage-track" aria-hidden="true"><span v-if="metric.value != null" :class="{ 'is-warning': metric.value >= 90 }" :style="{ width: `${Math.max(0, Math.min(100, metric.value))}%` }" /></span>
            </div>
          </dl>
          <div class="vps-mobile-latency" :title="visibleIps.has(row.id) && latency?.target ? t('vps.latencyTarget', { target: latency.target }) : t('vps.latencyHint')"><span>{{ t('vps.browserLatency') }}</span><strong>{{ latency?.status === 'success' && latency.latencyMs != null ? t('vps.latencyMs', { count: number(latency.latencyMs, 0) }) : latency ? t(`vps.latencyStates.${latency.status}`) : '—' }}</strong></div>
          <details class="vps-mobile-quality">
            <summary>{{ t('vps.table.quality') }}<i class="i-mdi-chevron-down" aria-hidden="true" /></summary>
            <div v-for="carrier in carriers" :key="carrier" class="vps-mobile-carrier"><span>{{ t(`vps.table.${carrier}`) }}</span><VpsCarrierQuality :instance-id="row.id" :operator="carrier" :agent="qualityAgents.get(row.id) ?? null" :entries="qualityEntries.get(row.id) ?? []" :loaded="!!qualityOverview" :loading="qualityLoading" :stale="qualitySnapshotStale" :server-time="qualityOverview?.serverTime ?? null" :ip-visible="visibleIps.has(row.id)" :disabled="contextLocked" @details="openDetails(row)" /></div>
          </details>
          <template #footer>
            <button type="button" class="mobile-record-button" :disabled="contextLocked" @click="openDetails(row)"><i class="i-mdi-information-outline" aria-hidden="true" />{{ t('vpsDetails.title') }}</button>
            <button v-if="row.cloudType === 1" type="button" class="mobile-record-button" :disabled="contextLocked || !row.tenantId" @click="manageOci(row)"><i class="i-mdi-server-outline" aria-hidden="true" />{{ t('vps.manageOci') }}</button>
          </template>
        </MobileRecordCard>
      </MobileRecordList>
      <table v-else-if="!compactViewport" class="vps-table" :aria-label="t('vps.title')">
        <thead><tr><th v-for="column in columns" :key="column" scope="col" :class="`vps-col-${column}`" :title="column === 'latency' ? t('vps.latencyHint') : undefined">{{ t(`vps.table.${column}`) }}</th></tr></thead>
        <tbody>
          <tr v-for="{ row, metrics, agentState, latency } in visibleRows" :key="row.id">
            <td class="vps-cell-server"><button type="button" class="vps-resource-name" :disabled="contextLocked" :title="row.displayName || '—'" @click="openDetails(row)">{{ row.displayName || '—' }}</button><button type="button" class="vps-reveal is-secondary" :disabled="!row.publicIps" :title="ipText(row)" :aria-label="t(visibleIps.has(row.id) ? 'vps.hideIp' : 'vps.showIp')" @click="toggleIp(row)"><span class="vps-truncate">{{ ipText(row) }}</span><i v-if="row.publicIps" :class="visibleIps.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></td>
            <td><span class="vps-truncate" :title="region(row)">{{ region(row) }}</span><small class="vps-truncate" :title="spec(row)">{{ spec(row) }}</small></td>
            <td><div class="vps-health-line" :title="t('vps.pingHint')"><span>Ping</span><strong :class="row.onLineEnable === 1 ? 'is-online' : row.onLineEnable === 0 ? 'is-offline' : ''">{{ flagLabel(row.onLineEnable) }}</strong></div><div class="vps-health-line" :title="t('vps.agentHint')"><span>{{ t('vps.agentShort') }}</span><strong :class="agentState === 'online' ? 'is-online' : agentState === 'offline' ? 'is-warning' : ''">{{ t(`vps.agents.${agentState}`) }}</strong></div></td>
            <td v-for="metric in [{ key: 'cpu', value: metrics?.cpuUsage }, { key: 'memory', value: metrics?.memoryPercent }, { key: 'disk', value: metrics?.diskPercent }]" :key="metric.key" class="vps-metric-cell"><span class="vps-metric" :class="{ 'is-stale': metrics?.stale, 'is-high': metric.value != null && metric.value >= 90 }" :title="metrics?.stale ? t('vps.stale') : t(`vps.${metric.key}`)">{{ percentage(metric.value) }}</span><i v-if="metrics?.stale" class="i-mdi-clock-outline vps-stale-icon" :title="t('vps.stale')" role="img" :aria-label="t('vps.stale')" /></td>
            <td><span class="vps-truncate" :title="visibleIps.has(row.id) && latency?.target ? t('vps.latencyTarget', { target: latency.target }) : t('vps.latencyHint')">{{ latency?.status === 'success' && latency.latencyMs != null ? t('vps.latencyMs', { count: number(latency.latencyMs, 0) }) : latency ? t(`vps.latencyStates.${latency.status}`) : '—' }}</span></td>
            <td v-for="carrier in carriers" :key="carrier"><VpsCarrierQuality :instance-id="row.id" :operator="carrier" :agent="qualityAgents.get(row.id) ?? null" :entries="qualityEntries.get(row.id) ?? []" :loaded="!!qualityOverview" :loading="qualityLoading" :stale="qualitySnapshotStale" :server-time="qualityOverview?.serverTime ?? null" :ip-visible="visibleIps.has(row.id)" :disabled="contextLocked" @details="openDetails(row)" /></td>
            <td class="vps-cell-actions"><VpsRowActions :disabled="contextLocked" :can-operate="canOperate" :show-install="row.monitorInstalled !== true && agentState !== 'online'" :row-name="row.displayName || t('vps.unnamed')" @ssh="ssh(row)" @details="openDetails(row)" @quality="qualityDetails(row)" @install="openOperation('install', row)" @uninstall="openOperation('uninstall', row)" /></td>
          </tr>
        </tbody>
      </table>
      <div v-if="!visibleRows.length" class="vps-empty" role="status"><i class="i-mdi-server-outline" aria-hidden="true" /><p>{{ emptyText }}</p><GhostBtn v-if="readProblem" :loading="loading" :disabled="contextLocked" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('vps.refresh') }}</GhostBtn></div>
    </div>
    <PagePagination :current-page="page" :page-size="size" :total="filtered.length" :page-sizes="pageSizes" :disabled="contextLocked" @current-change="changePage" @size-change="changeSize">
      <span>{{ loaded ? t('vps.count', { count: number(rows.length, 0) }) : t('vps.notLoaded') }}<template v-if="loaded && filtered.length !== rows.length"> · {{ t('vps.filteredCount', { count: number(filtered.length, 0) }) }}</template></span>
    </PagePagination>
    <div class="vps-footnote"><span>{{ lastUpdated ? t('vps.lastUpdated', { time: formatTime(lastUpdated) }) : t('vps.notLoaded') }}</span><span :title="t('vps.latencyHint')">{{ t('vps.browserLatency') }} · {{ t(`vps.latencyRun.${latencyState}`) }}<template v-if="latencyCounts.total"> · {{ t('vps.latencyProgress', { done: number(latencyDone, 0), total: number(latencyCounts.total, 0) }) }}</template></span></div>
    <VpsOperationDialog v-if="operation" :operation="operation" :pending="operationPending" :outcome="operationOutcome" :result="operationResult" :problem="operationProblem" :read-problem="readProblem" @close="closeOperation" @submit="submitOperation" />
    <VpsResourceDetails v-if="detailsMounted" :row="detailRow" :metrics="detailRow ? metricsFor(detailRow) : null" :agent-state="detailRow ? agentStatus(detailRow) : 'unknown'" :latency="detailRow ? resultFor(detailRow) : null" :quality-agent="detailRow ? qualityAgents.get(detailRow.id) ?? null : null" :quality-entries="detailRow ? qualityEntries.get(detailRow.id) ?? [] : []" :quality-loaded="!!qualityOverview" :quality-loading="qualityLoading" :quality-stale="qualitySnapshotStale" :quality-server-time="qualityOverview?.serverTime ?? null" :ip-visible="!!detailRow && visibleIps.has(detailRow.id)" :tenant-visible="!!detailRow && visibleTenants.has(detailRow.id)" :disabled="contextLocked" @close="closeDetails" @toggle-ip="detailIp" @toggle-tenant="detailTenant" @quality="detailQuality" />
  </section>
</template>
