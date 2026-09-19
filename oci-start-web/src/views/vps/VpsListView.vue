<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, defineAsyncComponent, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import type { VpsRow, VpsOperationKind } from '@/api/vps'
import {
  type HistoryHours, type NetworkQualityAgent, type NetworkQualityResult,
  type NetworkQualityTask, type NetworkQualityTaskInput, type QualityOperator,
} from '@/api/networkQuality'
import { useVpsPage } from './useVpsPage'
import { useVpsLive } from './useVpsLive'
import { useVpsLatency } from './useVpsLatency'
import { useNetworkQuality } from '@/views/settings/network-quality/useNetworkQuality'
import VpsRowActions from './VpsRowActions.vue'
import VpsCarrierQuality from './VpsCarrierQuality.vue'
import './vps.scss'
import '@/views/settings/network-quality/network-quality.scss'

const VpsOperationDialog = defineAsyncComponent(() => import('./VpsOperationDialog.vue'))
const VpsResourceDetails = defineAsyncComponent(() => import('./VpsResourceDetails.vue'))
const NetworkQualityChart = defineAsyncComponent(() => import('@/views/settings/network-quality/NetworkQualityChart.vue'))
const NetworkQualityTaskDialog = defineAsyncComponent(() => import('@/views/settings/network-quality/NetworkQualityTaskDialog.vue'))

const { t, te, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const compactViewport = useCompactViewport()

// VPS page & live monitoring
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
const latencyDone = computed(() => latencyCounts.value.total - latencyCounts.value.queued - latencyCounts.value.running)

// Network Quality integration (Fully integrated into Resource Management)
const {
  tasks: nqTasks, agents: nqAgents, latest: nqLatest, loading: nqLoading, loaded: nqLoaded,
  problem: nqProblem, lastUpdated: nqLastUpdated, refresh: refreshNq, mutation: nqMutation,
  contextLocked: nqLocked, canMutate: nqCanMutate, requiresReview: nqRequiresReview,
  saveTask: nqSaveTask, deleteTask: nqDeleteTask, runTask: nqRunTask, installAgent: nqInstallAgent,
  clearMutation: nqClearMutation, historyLoading: nqHistoryLoading, historyData: nqHistoryData,
  historyProblem: nqHistoryProblem, readHistory: nqReadHistory, refreshHistory: nqRefreshHistory,
  closeHistory: nqCloseHistory,
} = useNetworkQuality()

// Dialog states for seamlessly integrated features
const qualityDialogOpen = ref(false)
const tasksDialogOpen = ref(false)

function openQualityDialog(row?: VpsRow | null) {
  if (row?.id) selectedInstanceId.value = row.id
  else if (!selectedInstanceId.value && rows.value.length > 0) {
    selectedInstanceId.value = rows.value[0].id
  }
  qualityDialogOpen.value = true
}

function openTasksDialog() {
  tasksDialogOpen.value = true
}

// Watch query triggers (from external links / redirects)
watch(() => route.query.tab, val => {
  if (val === 'tasks') tasksDialogOpen.value = true
  else if (val === 'analytics') qualityDialogOpen.value = true
}, { immediate: true })
watch(() => route.query.instanceId, id => {
  if (typeof id === 'string' && id) {
    selectedInstanceId.value = id
    qualityDialogOpen.value = true
  }
}, { immediate: true })

// Instances filtering & search
const query = ref('')
const statusFilter = ref<'all' | 'online' | 'offline'>('all')
const offlineOnly = ref(false)
watch(statusFilter, val => { offlineOnly.value = val === 'offline' })
watch(offlineOnly, val => {
  if (val && statusFilter.value !== 'offline') statusFilter.value = 'offline'
  else if (!val && statusFilter.value === 'offline') statusFilter.value = 'all'
})
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

// Drawer for resource details
const detailId = ref<string | null>(null)
const detailsMounted = ref(false)
const detailRow = computed(() => rows.value.find(row => row.id === detailId.value) ?? null)

// Quality mapping for table rows
const qualityAgents = computed(() => new Map(nqAgents.value.map(agent => [agent.id, agent])))
const qualityEntries = computed(() => {
  const groups = new Map<string, Array<{ task: NetworkQualityTask; result: NetworkQualityResult | null }>>()
  const samples = new Map(nqLatest.value.map(result => [`${result.instanceId}:${result.taskId}`, result]))
  for (const task of nqTasks.value) {
    for (const id of task.instanceIds) {
      const entries = groups.get(id) ?? []
      const sample = samples.get(`${id}:${task.id}`)
      entries.push({ task, result: sample?.revision === task.version ? sample : null })
      groups.set(id, entries)
    }
  }
  return groups
})
const qualitySnapshotStale = computed(() => !!nqProblem.value || nqLocked.value)
const nqOnlineAgentsCount = computed(() => nqAgents.value.filter(a => a.qualityStatus === 'online').length)

// Tasks Dialog filtering & CRUD
const taskQuery = ref('')
const taskOperator = ref<QualityOperator | ''>('')
const taskOperators: QualityOperator[] = ['telecom', 'unicom', 'mobile', 'custom']
const filteredTasks = computed(() => {
  const needle = taskQuery.value.trim().toLowerCase()
  return nqTasks.value.filter(task => (!taskOperator.value || task.operator === taskOperator.value)
    && (!needle || [task.name, task.target, task.region].some(v => v?.toLowerCase().includes(needle))))
})
const taskPage = ref(1)
const taskSize = ref(20)
const visibleTasks = computed(() => filteredTasks.value.slice((taskPage.value - 1) * taskSize.value, taskPage.value * taskSize.value))

const taskEditor = ref<{ task: NetworkQualityTask | null; instanceId?: string } | null>(null)
type NqConfirmation = { kind: 'run' | 'delete' | 'toggle'; task: NetworkQualityTask; instanceIds?: string[] } | { kind: 'install'; agent: NetworkQualityAgent }
const nqConfirmation = ref<NqConfirmation | null>(null)
const nqFinished = computed(() => nqMutation.value.outcome === 'success' || nqMutation.value.outcome === 'unknown')

function openTaskEditor(task: NetworkQualityTask | null = null) {
  if (!nqCanMutate.value || nqLocked.value) return
  nqClearMutation()
  taskEditor.value = { task: task ? { ...task, instanceIds: [...task.instanceIds] } : null, instanceId: selectedInstanceId.value }
}
function closeTaskEditor() {
  if (!nqLocked.value) taskEditor.value = null
}
function saveNqTask(input: NetworkQualityTaskInput) {
  if (taskEditor.value) void nqSaveTask(input, taskEditor.value.task || undefined)
}
function askNq(action: NqConfirmation) {
  if (!nqCanMutate.value || nqLocked.value) return
  nqClearMutation()
  nqConfirmation.value = action
}
function closeNqConfirmation() {
  if (!nqLocked.value) nqConfirmation.value = null
}
function confirmNq() {
  const action = nqConfirmation.value
  if (!action || nqLocked.value || nqFinished.value) return
  if (action.kind === 'install') void nqInstallAgent(action.agent)
  else if (action.kind === 'delete') void nqDeleteTask(action.task)
  else if (action.kind === 'run') void nqRunTask(action.task, action.instanceIds)
  else void nqSaveTask({ name: action.task.name, operator: action.task.operator, region: action.task.region, type: action.task.type, target: action.task.target, intervalSeconds: action.task.intervalSeconds, sampleCount: action.task.sampleCount, enabled: !action.task.enabled, instanceIds: [...action.task.instanceIds] }, action.task)
}
watch(() => nqMutation.value.pending, (pending, previous) => {
  if (pending || !previous) return
  if (nqMutation.value.outcome === 'success') {
    taskEditor.value = null
    nqConfirmation.value = null
  }
  if (qualityDialogOpen.value) loadNqHistory()
})

const confirmTitle = computed(() => nqConfirmation.value?.kind === 'toggle' ? t(nqConfirmation.value.task.enabled ? 'networkQuality.pause' : 'networkQuality.resume') : t(`networkQuality.${nqConfirmation.value?.kind || 'confirm'}`))
const confirmHint = computed(() => {
  const action = nqConfirmation.value
  if (!action) return ''
  if (action.kind === 'install') return t('networkQuality.installHint')
  if (action.kind === 'run') return t('networkQuality.runHint', { count: action.instanceIds?.length || action.task.instanceIds.length })
  return t(action.kind === 'delete' ? 'networkQuality.deleteHint' : action.task.enabled ? 'networkQuality.pauseHint' : 'networkQuality.resumeHint', { name: action.task.name })
})
const nqReceipt = computed(() => {
  const result = nqMutation.value.result
  if (!result) return ''
  if (result.kind === 'run') return t('networkQuality.queued', { queued: result.receipt.queued, running: result.receipt.alreadyRunning, waiting: result.receipt.alreadyQueued, requested: result.receipt.requested })
  return t(result.kind === 'save' ? 'networkQuality.saved' : result.kind === 'delete' ? 'networkQuality.deleted' : 'networkQuality.installed')
})

// Analytics state & historical data
const selectedInstanceId = ref<string>(typeof route.query.instanceId === 'string' ? route.query.instanceId : '')
watch(rows, list => {
  if (!selectedInstanceId.value && list.length > 0) {
    selectedInstanceId.value = list[0].id
  }
}, { immediate: true })

const selectedAgent = computed(() => nqAgents.value.find(a => a.id === selectedInstanceId.value) || null)
const selectedRow = computed(() => rows.value.find(r => r.id === selectedInstanceId.value) || null)
const assignedTasks = computed(() => nqTasks.value.filter(t => t.instanceIds.includes(selectedInstanceId.value)))
const selectedTaskId = ref('')
watch(assignedTasks, tasks => {
  if (!tasks.some(t => t.id === selectedTaskId.value)) {
    selectedTaskId.value = tasks[0]?.id || ''
  }
}, { immediate: true })
const selectedTask = computed(() => assignedTasks.value.find(t => t.id === selectedTaskId.value) || null)
const hours = ref<HistoryHours>(24)
const periods: HistoryHours[] = [1, 6, 24, 168]

function loadNqHistory() {
  if (selectedInstanceId.value && selectedTask.value) {
    void nqReadHistory({
      instanceId: selectedInstanceId.value,
      taskId: selectedTask.value.id,
      revision: selectedTask.value.version,
      hours: hours.value,
    })
  } else {
    nqCloseHistory()
  }
}

watch([selectedInstanceId, () => selectedTask.value?.id, () => selectedTask.value?.version, hours, qualityDialogOpen], () => {
  if (qualityDialogOpen.value) loadNqHistory()
})

const recentRecords = computed(() => [...(nqHistoryData.value?.points || [])].reverse().slice(0, 30))

// Formatters & helpers
function number(value: number | null | undefined, digits = 0): string {
  return value == null || !Number.isFinite(value) ? '—' : new Intl.NumberFormat(locale.value, { maximumFractionDigits: digits }).format(value)
}
function percentage(value: number | null | undefined): string {
  return value == null || !Number.isFinite(value) ? '—' : new Intl.NumberFormat(locale.value, { style: 'percent', maximumFractionDigits: 0 }).format(value / 100)
}
function latencyVal(value: number | null | undefined): string {
  return value == null ? '—' : t('networkQuality.ms', { value: number(value, 1) })
}
function formatTime(value: number | Date | null | undefined): string {
  if (value == null) return '—'
  const date = value instanceof Date ? value : new Date(value)
  if (!Number.isFinite(date.getTime())) return '—'
  return new Intl.DateTimeFormat(locale.value, {
    month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).format(date)
}
function reasonText(result: NetworkQualityResult) {
  const key = `networkQuality.reasons.${result.errorCode}`
  return [result.errorCode && te(key) ? t(key) : '', result.httpStatus != null ? `HTTP ${result.httpStatus}` : ''].filter(Boolean).join(' · ') || '—'
}

function provider(value: number | null | undefined) {
  return ({ 1: 'Oracle Cloud', 2: 'Google Cloud', 3: 'Azure', 4: 'AWS' } as Record<number, string>)[value ?? -1] ?? 'VPS'
}
function spec(row: VpsRow) {
  return [row.ocpus ? t('vps.cores', { count: row.ocpus }) : '', row.memoryInGBs ? t('vps.memoryGb', { count: row.memoryInGBs }) : '', row.bootVolumeSizeInGBs ? t('vps.diskGb', { count: row.bootVolumeSizeInGBs }) : ''].filter(Boolean).join(' · ') || '—'
}
function flagLabel(value: 0 | 1 | null | undefined) {
  return value === 1 ? t('vps.online') : value === 0 ? t('vps.offline') : t('vps.unknown')
}
function region(row: VpsRow) {
  return row.regionName || row.regionCode || '—'
}

const pingCounts = computed(() => ({
  online: rows.value.filter(row => row.onLineEnable === 1).length,
  offline: rows.value.filter(row => row.onLineEnable === 0).length,
  unknown: rows.value.filter(row => row.onLineEnable == null).length,
}))
const filtered = computed(() => {
  const needle = query.value.trim().toLowerCase()
  return rows.value.filter(row => {
    if (statusFilter.value === 'online' && row.onLineEnable !== 1) return false
    if (statusFilter.value === 'offline' && row.onLineEnable !== 0) return false
    if (!needle) return true
    return [row.displayName, row.publicIps, row.tenancyName, row.regionName, row.regionCode,
      row.architecture, provider(row.cloudType), spec(row)].some(value => value.toLowerCase().includes(needle))
  })
})
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / size.value)))
const visibleRows = computed(() => filtered.value.slice((page.value - 1) * size.value, page.value * size.value)
  .map(row => ({ row, metrics: metricsFor(row), agentState: agentStatus(row), latency: resultFor(row) })))
const emptyText = computed(() => !loaded.value
  ? t(loading.value ? 'vps.loading' : readProblem.value ? 'vps.failed' : 'vps.notLoaded')
  : t(rows.value.length ? 'vps.noMatches' : 'vps.empty'))

function openDetails(row: VpsRow) { detailsMounted.value = true; detailId.value = row.id }
function closeDetails() { detailId.value = null }
function detailIp() { if (detailRow.value) toggleIp(detailRow.value) }
function detailTenant() { if (detailRow.value) toggleTenant(detailRow.value) }
function toggleIp(row: VpsRow) { visibleIps.value.has(row.id) ? visibleIps.value.delete(row.id) : visibleIps.value.add(row.id) }
function toggleTenant(row: VpsRow) { visibleTenants.value.has(row.id) ? visibleTenants.value.delete(row.id) : visibleTenants.value.add(row.id) }
function toggleIps() {
  globalIps.value = !globalIps.value
  if (globalIps.value) for (const row of rows.value) visibleIps.value.add(row.id)
  else visibleIps.value.clear()
}
function toggleTenants() {
  globalTenants.value = !globalTenants.value
  if (globalTenants.value) for (const row of rows.value) visibleTenants.value.add(row.id)
  else visibleTenants.value.clear()
}
function allTenants() { if (!contextLocked.value) void router.push({ path: route.path, query: {} }) }
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/boot/dashboard')
}
function clearSearch() { query.value = ''; statusFilter.value = 'all'; offlineOnly.value = false; page.value = 1 }
function changePage(val: number) { if (!contextLocked.value && val >= 1 && val <= totalPages.value) page.value = val }
function changeSize(val: number) { if (!contextLocked.value && pageSizes.includes(val)) { size.value = val; page.value = 1 } }
function ssh(row: VpsRow) {
  if (!contextLocked.value) void router.push({ path: '/oci/terminal', query: { instanceId: row.id } })
}
function command(value: unknown) {
  if (contextLocked.value || nqLocked.value) return
  if (value === 'enablePing' || value === 'disablePing' || value === 'ping') openOperation(value as VpsOperationKind)
  else if (value === 'createTask') openTaskEditor()
  else if (value === 'tasks') openTasksDialog()
  else if (value === 'quality') openQualityDialog()
  else if (value === 'ips') toggleIps()
  else if (value === 'tenants') toggleTenants()
}
async function copyIp(value?: string | null) {
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
    ElMessage.success(t('vps.copied'))
  } catch {
    ElMessage.error(t('vps.copyFailed'))
  }
}

function tick() {
  if (document.hidden || contextLocked.value || nqLocked.value) return
  void refreshNq()
  if (qualityDialogOpen.value && !nqHistoryLoading.value) void nqRefreshHistory()
}
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  void refreshNq()
  timer = setInterval(tick, 10000)
  document.addEventListener('visibilitychange', tick)
})
onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
  document.removeEventListener('visibilitychange', tick)
})
</script>

<template>
  <section class="vps-page" :aria-label="t('vps.title')">
    <!-- Clean, Standard OCI Header Toolbar (No cluttering tabs) -->
    <header class="vps-toolbar">
      <PageBackButton :disabled="operationPending" @click="back" />
      <form class="vps-search" role="search" @submit.prevent>
        <i class="i-mdi-magnify" aria-hidden="true" />
        <input
          v-model="query"
          type="text"
          :placeholder="t('vps.search')"
          :aria-label="t('vps.search')"
          :disabled="contextLocked"
          autocomplete="off"
          @keydown.esc.prevent="clearSearch"
        />
        <button
          v-if="query || statusFilter !== 'all' || offlineOnly"
          type="button"
          :disabled="contextLocked"
          :title="t('vps.clear')"
          :aria-label="t('vps.clear')"
          @click="clearSearch"
        >
          <i class="i-mdi-close" aria-hidden="true" />
        </button>
      </form>
      <div class="oci-filter-tabs" role="radiogroup" :aria-label="t('vps.filterStatus')">
        <button type="button" class="oci-filter-tab" :class="{ 'is-active': statusFilter === 'all' }" :disabled="contextLocked" @click="statusFilter = 'all'">
          <span>{{ t('vps.all') }}</span>
          <span class="oci-tab-badge">{{ number(rows.length, 0) }}</span>
        </button>
        <button type="button" class="oci-filter-tab" :class="{ 'is-active': statusFilter === 'online' }" :disabled="contextLocked" @click="statusFilter = 'online'">
          <span class="oci-tab-dot is-online" />
          <span>{{ t('vps.online') }}</span>
          <span class="oci-tab-badge">{{ number(pingCounts.online, 0) }}</span>
        </button>
        <button type="button" class="oci-filter-tab" :class="{ 'is-active': statusFilter === 'offline' }" :disabled="contextLocked" @click="statusFilter = 'offline'">
          <span class="oci-tab-dot is-offline" />
          <span>{{ t('vps.offline') }}</span>
          <span class="oci-tab-badge">{{ number(pingCounts.offline, 0) }}</span>
        </button>
      </div>
      <div class="vps-toolbar-actions" data-page-error-anchor>
        <GhostBtn v-if="latencyRunning" @click="stopLatency"><i class="i-mdi-stop" aria-hidden="true" />{{ t('vps.stopLatency') }}</GhostBtn>
        <PrimaryBtn v-else :disabled="!ready || paused || !rows.length" :title="t('vps.latencyHint')" @click="startLatency"><i class="i-mdi-timer-outline" aria-hidden="true" />{{ t('vps.testLatency') }}</PrimaryBtn>
        <GhostBtn :loading="loading" :disabled="contextLocked" :title="t('vps.refresh')" :aria-label="t('vps.refresh')" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn>
        <el-dropdown trigger="click" :disabled="contextLocked" placement="bottom-end" popper-class="vps-menu" @command="command">
          <GhostBtn :disabled="contextLocked" :title="t('vps.more')" :aria-label="t('vps.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></GhostBtn>
          <template #dropdown><el-dropdown-menu>
            <el-dropdown-item command="quality"><i class="i-mdi-chart-line" aria-hidden="true" />{{ t('networkQuality.title') }}</el-dropdown-item>
            <el-dropdown-item command="tasks"><i class="i-mdi-format-list-checks" aria-hidden="true" />{{ t('networkQuality.tasks') }}</el-dropdown-item>
            <el-dropdown-item command="createTask"><i class="i-mdi-plus" aria-hidden="true" />{{ t('networkQuality.create') }}</el-dropdown-item>
            <el-dropdown-item command="ips" divided><i :class="globalIps ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />{{ t(globalIps ? 'vps.hideIps' : 'vps.showIps') }}</el-dropdown-item>
            <el-dropdown-item command="tenants"><i :class="globalTenants ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />{{ t(globalTenants ? 'vps.hideTenants' : 'vps.showTenants') }}</el-dropdown-item>
            <el-dropdown-item command="enablePing" :disabled="!canOperate" divided><i class="i-mdi-play-outline" aria-hidden="true" />{{ t('vps.enablePing') }}</el-dropdown-item>
            <el-dropdown-item command="disablePing" :disabled="!canOperate"><i class="i-mdi-stop" aria-hidden="true" />{{ t('vps.disablePing') }}</el-dropdown-item>
            <el-dropdown-item command="ping" :disabled="!canOperate"><i class="i-mdi-access-point-network" aria-hidden="true" />{{ t('vps.ping') }}</el-dropdown-item>
          </el-dropdown-menu></template>
        </el-dropdown>
      </div>
    </header>

    <!-- KPI Status Bar -->
    <div class="vps-statusbar">
      <input v-model="offlineOnly" type="checkbox" class="vps-sr-only" aria-hidden="true" tabindex="-1" />
      <span v-if="loaded" class="vps-ping-summary" :title="t('vps.pingHint')">
        <i class="i-mdi-access-point-network" aria-hidden="true" />
        {{ t('vps.pingCounts', { online: number(pingCounts.online, 0), offline: number(pingCounts.offline, 0), unknown: number(pingCounts.unknown, 0) }) }}
      </span>
      <div class="vps-live-status" role="status" :title="t('vps.agentHint')">
        <span class="vps-dot" :class="{ 'is-online': connection === 'connected' }" />
        {{ t('vps.connectionLabel') }} · {{ t(`vps.connections.${connection}`) }}
        <button v-if="connection === 'disconnected' || connection === 'reconnecting'" type="button" class="vps-text-button" :disabled="paused" @click="reconnect">
          {{ t('vps.reconnect') }}
        </button>
      </div>
      <div class="vps-nq-status-item">
        <span class="vps-dot is-online" />
        <span>{{ t('networkQuality.agents.online') }}:</span>
        <strong>{{ number(nqOnlineAgentsCount, 0) }}</strong>
      </div>
      <div class="vps-nq-status-item">
        <span>{{ t('networkQuality.tasks') }}:</span>
        <strong>{{ number(nqTasks.length, 0) }}</strong>
      </div>
    </div>

    <div v-if="tenantId" class="vps-notice"><span>{{ t('vps.tenantScope', { id: tenantId }) }}</span><GhostBtn :disabled="contextLocked" @click="allTenants"><i class="i-mdi-filter-remove-outline" aria-hidden="true" />{{ t('vps.allTenants') }}</GhostBtn></div>
    <PageErrorNotice v-if="readProblem"><span>{{ t(`vps.errors.${readProblem.key}`) }} {{ readProblem.detail }} {{ loaded ? t('vps.retained') : '' }}</span><GhostBtn :loading="loading" :disabled="contextLocked" @click="refresh">{{ t('vps.refresh') }}</GhostBtn></PageErrorNotice>
    <PageErrorNotice v-if="nqProblem"><span>{{ t('networkQuality.title') }} · {{ t(`networkQuality.errors.${nqProblem.key}`) }}</span><button type="button" :disabled="nqLoading || contextLocked" @click="refreshNq">{{ t('networkQuality.refresh') }}</button></PageErrorNotice>

    <!-- Main Table Body: Resource Inventory -->
    <div class="vps-table-body" :aria-busy="loading">
      <MobileRecordList v-if="compactViewport" drilldown list-id="vps-instances" :record-keys="visibleRows.map(({ row }) => String(row.id))" :loading="loading" class="vps-mobile-list">
        <MobileRecordCard v-for="{ row, metrics, agentState, latency } in visibleRows" :key="row.id" :record-key="String(row.id)" :summary-title="row.displayName || t('vps.unnamed')" :summary-meta="`${region(row)} · ${provider(row.cloudType)}`" :summary-status="flagLabel(row.onLineEnable)" :summary-tone="row.onLineEnable === 1 ? 'success' : row.onLineEnable === 0 ? 'danger' : 'neutral'" class="vps-mobile-card">
          <template #identity>
            <button type="button" class="mobile-record-title vps-mobile-name" :disabled="contextLocked" @click="openDetails(row)">{{ row.displayName || t('vps.unnamed') }}</button>
            <span class="mobile-record-subtitle">{{ region(row) }} · {{ provider(row.cloudType) }}</span>
          </template>
          <template #actions>
            <GhostBtn class="vps-compact-ssh" :disabled="contextLocked" @click="ssh(row)"><i class="i-mdi-console" aria-hidden="true" />{{ t('vps.ssh') }}</GhostBtn>
            <el-dropdown trigger="click" :disabled="contextLocked" placement="bottom-end" @command="command">
              <GhostBtn class="vps-compact-more" :disabled="contextLocked" :title="t('vps.more')" :aria-label="t('vps.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></GhostBtn>
              <template #dropdown><el-dropdown-menu>
                <el-dropdown-item command="quality" @click="openQualityDialog(row)"><i class="i-mdi-chart-line" aria-hidden="true" />{{ t('networkQuality.title') }}</el-dropdown-item>
                <el-dropdown-item command="details" @click="openDetails(row)"><i class="i-mdi-information-outline" aria-hidden="true" />{{ t('vpsDetails.title') }}</el-dropdown-item>
              </el-dropdown-menu></template>
            </el-dropdown>
          </template>
          <dl class="mobile-record-fields vps-mobile-fields">
            <div><dt>{{ t('vps.server') }}</dt><dd><button type="button" class="vps-reveal" :disabled="contextLocked" :aria-label="t(visibleIps.has(row.id) ? 'vps.hideIp' : 'vps.showIp')" @click="toggleIp(row)"><span>{{ visibleIps.has(row.id) ? (row.publicIps || t('vps.noIp')) : '••••••' }}</span><i :class="visibleIps.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></dd></div>
            <div><dt>{{ t('vps.pingStatus') }}</dt><dd><span class="vps-badge" :class="row.onLineEnable === 1 ? 'is-online' : row.onLineEnable === 0 ? 'is-offline' : ''">{{ flagLabel(row.onLineEnable) }}</span></dd></div>
          </dl>
        </MobileRecordCard>
      </MobileRecordList>
      <table v-else class="vps-table" :aria-label="t('vps.title')">
        <thead>
          <tr>
            <th v-for="col in columns" :key="col" scope="col" :class="`vps-col-${col}`">{{ t(`vps.table.${col}`) }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="{ row, metrics, agentState, latency } in visibleRows" :key="row.id">
            <td class="vps-cell-server">
              <div class="vps-instance-identity">
                <button type="button" class="vps-resource-name" :disabled="contextLocked" :title="row.displayName || t('vps.unnamed')" @click="openDetails(row)">
                  {{ row.displayName || t('vps.unnamed') }}
                </button>
                <div class="vps-ip-row">
                  <span class="vps-ip-text" :title="row.publicIps || t('vps.noIp')">
                    {{ visibleIps.has(row.id) ? (row.publicIps || t('vps.noIp')) : '••••••' }}
                  </span>
                  <button type="button" class="vps-inline-btn" :disabled="contextLocked" :title="t(visibleIps.has(row.id) ? 'vps.hideIp' : 'vps.showIp')" @click="toggleIp(row)">
                    <i :class="visibleIps.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />
                  </button>
                  <button v-if="row.publicIps" type="button" class="vps-inline-btn" :disabled="contextLocked" :title="t('vps.copyIp')" @click="copyIp(row.publicIps)">
                    <i class="i-mdi-content-copy" aria-hidden="true" />
                  </button>
                </div>
              </div>
            </td>
            <td class="vps-cell-placement">
              <div class="vps-placement-meta">
                <div class="vps-region-line">
                  <i class="i-mdi-earth placement-icon" aria-hidden="true" />
                  <span class="vps-region-name" :title="region(row)">{{ region(row) }}</span>
                  <span class="vps-provider-tag">{{ provider(row.cloudType) }}</span>
                </div>
                <div class="vps-shape-line">
                  <i class="i-mdi-chip shape-icon" aria-hidden="true" />
                  <span class="vps-spec-text" :title="spec(row)">{{ spec(row) }}</span>
                </div>
              </div>
            </td>
            <td class="vps-cell-health">
              <div class="vps-health-stack">
                <span class="oci-status-pill" :class="row.onLineEnable === 1 ? 'is-online' : row.onLineEnable === 0 ? 'is-offline' : 'is-unknown'">
                  <span class="oci-status-dot" />
                  <span>{{ flagLabel(row.onLineEnable) }}</span>
                </span>
                <div class="vps-agent-substatus">
                  <span class="agent-dot" :class="agentState === 'online' ? 'is-online' : agentState === 'offline' ? 'is-warning' : 'is-muted'" />
                  <span class="agent-label">{{ t(`vps.agents.${agentState}`) }}</span>
                </div>
              </div>
            </td>
            <td v-for="metric in [{ key: 'cpu', value: metrics?.cpuUsage }, { key: 'memory', value: metrics?.memoryPercent }, { key: 'disk', value: metrics?.diskPercent }]" :key="metric.key" :class="`vps-cell-${metric.key} vps-metric-cell`">
              <div class="vps-metric-box">
                <div class="vps-metric-val-row">
                  <span class="vps-metric" :class="{ 'is-stale': metrics?.stale, 'is-high': metric.value != null && metric.value >= 90 }">
                    {{ percentage(metric.value) }}
                  </span>
                  <i v-if="metrics?.stale" class="i-mdi-clock-outline vps-stale-icon" :title="t('vps.stale')" role="img" :aria-label="t('vps.stale')" />
                </div>
                <div class="vps-metric-track" aria-hidden="true">
                  <div class="vps-metric-bar" :class="{ 'is-warning': metric.value != null && metric.value >= 90, 'is-stale': metrics?.stale }" :style="{ width: metric.value != null ? `${Math.max(0, Math.min(100, metric.value))}%` : '0%' }" />
                </div>
              </div>
            </td>
            <td class="vps-cell-latency">
              <div class="vps-latency-chip" :title="visibleIps.has(row.id) && latency?.target ? t('vps.latencyTarget', { target: latency.target }) : t('vps.latencyHint')">
                <i class="i-mdi-timer-outline latency-icon" aria-hidden="true" />
                <span class="vps-truncate">{{ latency?.status === 'success' && latency.latencyMs != null ? t('vps.latencyMs', { count: number(latency.latencyMs, 0) }) : latency ? t(`vps.latencyStates.${latency.status}`) : '—' }}</span>
              </div>
            </td>
            <td v-for="carrier in carriers" :key="carrier" :class="`vps-cell-${carrier}`">
              <VpsCarrierQuality :instance-id="row.id" :operator="carrier" :agent="qualityAgents.get(row.id) ?? null" :entries="qualityEntries.get(row.id) ?? []" :loaded="nqLoaded" :loading="nqLoading" :stale="qualitySnapshotStale" :server-time="nqLastUpdated" :ip-visible="visibleIps.has(row.id)" :disabled="contextLocked" @details="openQualityDialog(row)" />
            </td>
            <td class="vps-cell-actions">
              <VpsRowActions :disabled="contextLocked" :can-operate="canOperate" :show-install="row.monitorInstalled !== true && agentState !== 'online'" :row-name="row.displayName || t('vps.unnamed')" @ssh="ssh(row)" @details="openDetails(row)" @quality="openQualityDialog(row)" @install="openOperation('install', row)" @uninstall="openOperation('uninstall', row)" />
            </td>
          </tr>
        </tbody>
      </table>
      <div v-if="!visibleRows.length" class="vps-empty" role="status"><i class="i-mdi-server-outline" aria-hidden="true" /><p>{{ emptyText }}</p><GhostBtn v-if="readProblem" :loading="loading" :disabled="contextLocked" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('vps.refresh') }}</GhostBtn></div>
    </div>
    <PagePagination :current-page="page" :page-size="size" :total="filtered.length" :page-sizes="pageSizes" :disabled="contextLocked" @current-change="changePage" @size-change="changeSize">
      <span>{{ loaded ? t('vps.count', { count: number(rows.length, 0) }) : t('vps.notLoaded') }}<template v-if="loaded && filtered.length !== rows.length"> · {{ t('vps.filteredCount', { count: number(filtered.length, 0) }) }}</template></span>
    </PagePagination>
    <div class="vps-footnote"><span>{{ lastUpdated ? t('vps.lastUpdated', { time: formatTime(lastUpdated) }) : t('vps.notLoaded') }}</span><span :title="t('vps.latencyHint')">{{ t('vps.browserLatency') }} · {{ t(`vps.latencyRun.${latencyState}`) }}<template v-if="latencyCounts.total"> · {{ t('vps.latencyProgress', { done: number(latencyDone, 0), total: number(latencyCounts.total, 0) }) }}</template></span></div>

    <!-- DIALOG 1: Integrated Network Quality Analytics Modal -->
    <el-dialog
      v-model="qualityDialogOpen"
      append-to-body
      width="min(1120px, calc(100vw - 32px))"
      class="nq-dialog"
      :title="t('networkQuality.title')"
      :close-on-click-modal="false"
      align-center
    >
      <div class="nq-toolbar nq-dialog-toolbar">
        <el-select v-model="selectedInstanceId" class="vps-analytics-instance-select" filterable :placeholder="t('networkQuality.instance')">
          <el-option v-for="row in rows" :key="row.id" :value="row.id" :label="row.displayName || row.publicIps || row.id" />
        </el-select>
        <el-select v-if="assignedTasks.length" v-model="selectedTaskId" class="vps-analytics-task-select" :teleported="true" :empty-values="[null, undefined]">
          <el-option v-for="task in assignedTasks" :key="task.id" :value="task.id" :label="`${task.name} · ${task.type.toUpperCase()}`" />
        </el-select>
        <div class="nq-periods" :aria-label="t('networkQuality.window')">
          <button v-for="p in periods" :key="p" type="button" :disabled="nqLocked" :aria-pressed="hours === p" @click="hours = p">
            {{ t(`networkQuality.hour${p}`) }}
          </button>
        </div>
        <div class="nq-toolbar-end">
          <GhostBtn v-if="selectedTask" :disabled="!nqCanMutate || nqLocked" @click="askNq({ kind: 'run', task: selectedTask, instanceIds: [selectedInstanceId] })">
            <i class="i-mdi-play-outline" aria-hidden="true" />{{ t('networkQuality.run') }}
          </GhostBtn>
          <GhostBtn v-if="selectedRow" :disabled="contextLocked" @click="ssh(selectedRow)">
            <i class="i-mdi-console" aria-hidden="true" />{{ t('networkQuality.ssh') }}
          </GhostBtn>
          <GhostBtn :loading="nqLoading" :disabled="nqLocked" @click="() => { refreshNq(); nqRefreshHistory(); }">
            <i class="i-mdi-refresh" aria-hidden="true" />
          </GhostBtn>
        </div>
      </div>

      <div v-if="!selectedInstanceId" class="nq-empty">
        <i class="i-mdi-server-network" aria-hidden="true" />
        <p>{{ t('networkQuality.missingInstance') }}</p>
      </div>
      <div v-else class="nq-detail-scroll">
        <div v-if="selectedAgent && selectedAgent.qualityStatus !== 'online'" class="nq-detail-agent">
          <span>{{ t(`networkQuality.agents.${selectedAgent.qualityStatus}`) }} · {{ t('networkQuality.lastUpdated', { time: formatTime(selectedAgent.lastSeen) }) }}</span>
          <GhostBtn :disabled="!nqCanMutate || nqLocked" @click="askNq({ kind: 'install', agent: selectedAgent })">
            <i class="i-mdi-download-outline" aria-hidden="true" />{{ t(selectedAgent.qualityStatus === 'not_installed' ? 'networkQuality.install' : 'networkQuality.upgrade') }}
          </GhostBtn>
        </div>
        <div v-if="selectedTask" class="nq-target-caption">
          <span class="nq-truncate" :title="selectedTask.target">{{ t(`networkQuality.operators.${selectedTask.operator}`) }} · {{ selectedTask.region || '—' }} · {{ selectedTask.target }}</span>
          <span v-if="!selectedTask.enabled">{{ t('networkQuality.stopped') }}</span>
        </div>
        <PageErrorNotice v-if="nqHistoryProblem">{{ nqHistoryData ? t('networkQuality.retained') : '' }}</PageErrorNotice>
        <div class="nq-history-content" :aria-busy="nqHistoryLoading">
          <dl class="nq-stats-grid">
            <div class="nq-kpi-card">
              <dt>{{ t('networkQuality.avg') }}</dt>
              <dd class="nq-kpi-num">{{ latencyVal(nqHistoryData?.stats.avgMs) }}</dd>
            </div>
            <div class="nq-kpi-card">
              <dt>{{ t('networkQuality.min') }}</dt>
              <dd class="nq-kpi-num">{{ latencyVal(nqHistoryData?.stats.minMs) }}</dd>
            </div>
            <div class="nq-kpi-card">
              <dt>{{ t('networkQuality.max') }}</dt>
              <dd class="nq-kpi-num">{{ latencyVal(nqHistoryData?.stats.maxMs) }}</dd>
            </div>
            <div class="nq-kpi-card" :class="{ 'is-loss': nqHistoryData?.stats.lossPercent != null && nqHistoryData.stats.lossPercent > 0 }">
              <dt>{{ t(selectedTask?.type === 'icmp' ? 'networkQuality.packetLoss' : 'networkQuality.failureRate') }}</dt>
              <dd class="nq-kpi-num">{{ nqHistoryData?.stats.lossPercent == null ? '—' : `${number(nqHistoryData.stats.lossPercent, 1)}%` }}</dd>
            </div>
            <div class="nq-kpi-card">
              <dt>{{ t('networkQuality.attempts') }}</dt>
              <dd class="nq-kpi-num">{{ number(nqHistoryData?.stats.successful, 0) }} / {{ number(nqHistoryData?.stats.attempts, 0) }}</dd>
            </div>
          </dl>
          <div class="nq-chart-wrapper">
            <NetworkQualityChart :history="nqHistoryData" :type="selectedTask?.type || 'icmp'" :operator="selectedTask?.operator" />
          </div>
          <p class="nq-chart-note">{{ t('networkQuality.protocolHint') }}</p>
        </div>
        <div class="nq-record-heading">
          <h2>{{ t('networkQuality.recent') }}</h2>
          <span v-if="nqHistoryLoading" role="status">{{ t('networkQuality.loading') }}</span>
        </div>
        <div class="nq-records">
          <table class="nq-table nq-history-table" :aria-label="t('networkQuality.recent')">
            <thead>
              <tr>
                <th scope="col">{{ t('networkQuality.time') }}</th>
                <th scope="col">{{ t('networkQuality.result') }}</th>
                <th scope="col">{{ t('networkQuality.avg') }}</th>
                <th scope="col">{{ t('networkQuality.attempts') }}</th>
                <th scope="col">{{ t('networkQuality.reason') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in recentRecords" :key="item.executionId">
                <td>{{ formatTime(item.updatedAt) }}</td>
                <td><span class="nq-badge" :class="`is-${item.status}`">{{ t(`networkQuality.statuses.${item.status}`) }}</span></td>
                <td>{{ latencyVal(item.avgMs) }}</td>
                <td>{{ number(item.successful, 0) }} / {{ number(item.attempts, 0) }}</td>
                <td>{{ reasonText(item) }}</td>
              </tr>
            </tbody>
          </table>
          <div v-if="!recentRecords.length" class="nq-empty nq-empty-small">{{ t('networkQuality.noData') }}</div>
        </div>
      </div>
      <template #footer>
        <GhostBtn @click="qualityDialogOpen = false">{{ t('vps.close') }}</GhostBtn>
      </template>
    </el-dialog>

    <!-- DIALOG 2: Integrated Probe Tasks Management Modal -->
    <el-dialog
      v-model="tasksDialogOpen"
      append-to-body
      width="min(1160px, calc(100vw - 32px))"
      class="nq-dialog"
      :title="t('networkQuality.tasks')"
      :close-on-click-modal="false"
      align-center
    >
      <div class="nq-toolbar nq-dialog-toolbar">
        <form class="nq-search" role="search" @submit.prevent>
          <i class="i-mdi-magnify" aria-hidden="true" />
          <input
            v-model="taskQuery"
            type="text"
            :placeholder="t('networkQuality.search')"
            :aria-label="t('networkQuality.search')"
            autocomplete="off"
            @keydown.esc.prevent="taskQuery = ''"
          />
          <button v-if="taskQuery" type="button" :title="t('networkQuality.clear')" :aria-label="t('networkQuality.clear')" @click="taskQuery = ''">
            <i class="i-mdi-close" aria-hidden="true" />
          </button>
        </form>
        <el-select v-model="taskOperator" class="nq-operator-select" :teleported="true" :empty-values="[null, undefined]">
          <el-option value="" :label="t('networkQuality.allOperators')" />
          <el-option v-for="op in taskOperators" :key="op" :value="op" :label="t(`networkQuality.operators.${op}`)" />
        </el-select>
        <div class="nq-toolbar-end">
          <GhostBtn :loading="nqLoading" :disabled="nqLocked" @click="refreshNq"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn>
          <PrimaryBtn :disabled="!nqCanMutate || nqLocked" @click="openTaskEditor()">
            <i class="i-mdi-plus" aria-hidden="true" />{{ t('networkQuality.create') }}
          </PrimaryBtn>
        </div>
      </div>
      <div class="nq-table-wrap" :aria-busy="nqLoading">
        <table class="nq-table nq-task-table" :aria-label="t('networkQuality.tasks')">
          <thead>
            <tr>
              <th scope="col" class="nq-col-task-name">{{ t('networkQuality.name') }}</th>
              <th scope="col" class="nq-col-task-op">{{ t('networkQuality.operator') }}</th>
              <th scope="col" class="nq-col-task-target">{{ t('networkQuality.target') }}</th>
              <th scope="col" class="nq-col-task-assigned">{{ t('networkQuality.assigned') }}</th>
              <th scope="col" class="nq-col-task-cadence">{{ t('networkQuality.cadence') }}</th>
              <th scope="col" class="nq-col-task-state">{{ t('networkQuality.taskState') }}</th>
              <th scope="col" class="nq-col-actions">{{ t('networkQuality.actions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="task in visibleTasks" :key="task.id">
              <td class="nq-cell-task-name">
                <div class="nq-task-title-box">
                  <strong class="nq-truncate" :title="task.name">{{ task.name }}</strong>
                  <span class="nq-proto-tag">{{ task.type.toUpperCase() }}</span>
                </div>
              </td>
              <td class="nq-cell-task-op">
                <div class="nq-operator-tag-row">
                  <span class="nq-operator-badge" :class="`is-${task.operator}`">{{ t(`networkQuality.operators.${task.operator}`) }}</span>
                  <small v-if="task.region" class="nq-truncate nq-region-text" :title="task.region">{{ task.region }}</small>
                </div>
              </td>
              <td class="nq-cell-target">
                <div class="nq-target-code-row">
                  <code class="nq-target-code nq-truncate" :title="task.target">{{ task.target }}</code>
                  <button type="button" class="nq-inline-btn" :title="t('networkQuality.copy')" @click="copyIp(task.target)">
                    <i class="i-mdi-content-copy" aria-hidden="true" />
                  </button>
                </div>
              </td>
              <td class="nq-cell-task-assigned">
                <span class="nq-pill-count">{{ t('networkQuality.selected', { count: task.instanceIds.length }) }}</span>
              </td>
              <td class="nq-cell-task-cadence">
                <span class="nq-cadence-text">{{ t('networkQuality.seconds', { count: task.intervalSeconds }) }}</span>
                <small class="nq-samples-text">{{ t('networkQuality.sampleCount', { count: task.sampleCount }) }}</small>
              </td>
              <td class="nq-cell-task-state">
                <span class="oci-status-pill" :class="task.enabled ? 'is-online' : 'is-unknown'">
                  <span class="oci-status-dot" />
                  <span>{{ t(task.enabled ? 'networkQuality.active' : 'networkQuality.paused') }}</span>
                </span>
              </td>
              <td class="nq-cell-actions">
                <div class="nq-row-actions">
                  <button type="button" class="nq-action-btn" :disabled="!nqCanMutate || nqLocked" :title="t('networkQuality.run')" :aria-label="t('networkQuality.run')" @click="askNq({ kind: 'run', task })">
                    <i class="i-mdi-play-outline" aria-hidden="true" />
                  </button>
                  <button type="button" class="nq-action-btn" :disabled="!nqCanMutate || nqLocked" :title="t('networkQuality.edit')" :aria-label="t('networkQuality.edit')" @click="openTaskEditor(task)">
                    <i class="i-mdi-pencil-outline" aria-hidden="true" />
                  </button>
                  <button type="button" class="nq-action-btn" :disabled="!nqCanMutate || nqLocked" :title="t(task.enabled ? 'networkQuality.pause' : 'networkQuality.resume')" :aria-label="t(task.enabled ? 'networkQuality.pause' : 'networkQuality.resume')" @click="askNq({ kind: 'toggle', task })">
                    <i :class="task.enabled ? 'i-mdi-pause' : 'i-mdi-play-circle-outline'" aria-hidden="true" />
                  </button>
                  <button type="button" class="nq-action-btn is-danger" :disabled="!nqCanMutate || nqLocked" :title="t('networkQuality.delete')" :aria-label="t('networkQuality.delete')" @click="askNq({ kind: 'delete', task })">
                    <i class="i-mdi-trash-can-outline" aria-hidden="true" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-if="!filteredTasks.length" class="nq-empty">
          <i class="i-mdi-access-point-network" aria-hidden="true" />
          <p>{{ taskQuery || taskOperator ? t('networkQuality.noMatches') : t('networkQuality.emptyTasks') }}</p>
        </div>
      </div>
      <PagePagination :current-page="taskPage" :page-size="taskSize" :total="filteredTasks.length" :page-sizes="pageSizes" :disabled="nqLocked" @current-change="v => taskPage = v">
        <span>{{ t('networkQuality.total', { count: number(filteredTasks.length, 0) }) }}</span>
      </PagePagination>
      <template #footer>
        <GhostBtn @click="tasksDialogOpen = false">{{ t('vps.close') }}</GhostBtn>
      </template>
    </el-dialog>

    <!-- Standard Existing Dialogs & Operation Handlers -->
    <VpsOperationDialog v-if="operation" :operation="operation" :pending="operationPending" :outcome="operationOutcome" :result="operationResult" :problem="operationProblem" :read-problem="readProblem" @close="closeOperation" @submit="submitOperation" />
    <VpsResourceDetails v-if="detailsMounted" :row="detailRow" :metrics="detailRow ? metricsFor(detailRow) : null" :agent-state="detailRow ? agentStatus(detailRow) : 'unknown'" :latency="detailRow ? resultFor(detailRow) : null" :quality-agent="detailRow ? qualityAgents.get(detailRow.id) ?? null : null" :quality-entries="detailRow ? qualityEntries.get(detailRow.id) ?? [] : []" :quality-loaded="nqLoaded" :quality-loading="nqLoading" :quality-stale="qualitySnapshotStale" :quality-server-time="nqLastUpdated" :ip-visible="!!detailRow && visibleIps.has(detailRow.id)" :tenant-visible="!!detailRow && visibleTenants.has(detailRow.id)" :disabled="contextLocked" @close="closeDetails" @toggle-ip="detailIp" @toggle-tenant="detailTenant" @quality="openQualityDialog(detailRow)" />
    <NetworkQualityTaskDialog v-if="taskEditor" :task="taskEditor.task" :agents="nqAgents" :pending="nqMutation.pending" :finished="nqFinished" :feedback="nqRequiresReview ? t('networkQuality.unknownResult') : (nqMutation.problem ? t(`networkQuality.errors.${nqMutation.problem.key}`) : '')" :initial-instance-id="taskEditor.instanceId" @close="closeTaskEditor" @save="saveNqTask" />
    <el-dialog v-if="nqConfirmation" :model-value="true" append-to-body width="560px" class="nq-dialog" :title="confirmTitle" :close-on-click-modal="false" :close-on-press-escape="!nqLocked" :show-close="!nqLocked" :before-close="closeNqConfirmation" @update:model-value="val => { if (!val) closeNqConfirmation() }">
      <p class="nq-confirm-target">{{ nqConfirmation.kind === 'install' ? nqConfirmation.agent.displayName || nqConfirmation.agent.id : nqConfirmation.task.name }}</p>
      <p>{{ confirmHint }}</p>
      <PageErrorNotice v-if="!nqMutation.pending && nqMutation.outcome === 'failed' && !nqRequiresReview">{{ nqReceipt || (nqMutation.problem ? t(`networkQuality.errors.${nqMutation.problem.key}`) : '') }}</PageErrorNotice>
      <div v-else-if="nqMutation.pending || nqMutation.outcome !== 'idle'" class="nq-notice" role="status">{{ nqMutation.pending ? t('networkQuality.submitting') : nqRequiresReview ? t('networkQuality.unknownResult') : nqReceipt || (nqMutation.problem ? t(`networkQuality.errors.${nqMutation.problem.key}`) : '') }}</div>
      <template #footer>
        <GhostBtn :disabled="nqLocked" @click="closeNqConfirmation">{{ t(nqFinished ? 'networkQuality.close' : 'networkQuality.cancel') }}</GhostBtn>
        <PrimaryBtn v-if="!nqFinished" :loading="nqLocked" :class="{ 'nq-danger': nqConfirmation.kind === 'delete' }" @click="confirmNq"><i :class="nqConfirmation.kind === 'delete' ? 'i-mdi-trash-can-outline' : 'i-mdi-check'" aria-hidden="true" />{{ t('networkQuality.confirm') }}</PrimaryBtn>
      </template>
    </el-dialog>
  </section>
</template>
