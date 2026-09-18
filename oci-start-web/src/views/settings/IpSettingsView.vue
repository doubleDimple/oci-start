<script setup lang="ts">
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { computed, defineAsyncComponent, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { gsap } from 'gsap'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import { isNetworkQualityId, type HistoryHours, type NetworkQualityAgent, type NetworkQualityTask, type NetworkQualityTaskInput, type NetworkQualityResult, type QualityOperator } from '@/api/networkQuality'
import { useNetworkQuality } from './network-quality/useNetworkQuality'
import NetworkQualityTaskDialog from './network-quality/NetworkQualityTaskDialog.vue'
import './network-quality/network-quality.scss'

// This component is mounted only in the instance detail branch below.
const NetworkQualityChart = defineAsyncComponent(() => import('./network-quality/NetworkQualityChart.vue'))

const compact = useCompactViewport()
const { t, te, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const {
  tasks, agents, latest, loading, loaded, problem, lastUpdated, refresh,
  mutation, contextLocked, canMutate, requiresReview, reviewReady, acknowledgeReview, clearMutation,
  saveTask, deleteTask, runTask, installAgent, historyLoading, historyData, historyProblem, readHistory, refreshHistory, closeHistory,
} = useNetworkQuality()
const root = ref<HTMLElement | null>(null)
const tab = ref<'instances' | 'tasks'>(route.query.mobileQualityTab === 'tasks' ? 'tasks' : 'instances')
const query = ref('')
const operator = ref<QualityOperator | ''>('')
const status = ref('')
const operators: QualityOperator[] = ['telecom', 'unicom', 'mobile', 'custom']
const page = ref(1)
const size = ref(20)
const exposed = ref(new Set<string>())
const blocked = ref(false)
const editor = ref<{ task: NetworkQualityTask | null; instanceId?: string } | null>(null)
type Confirmation = { kind: 'run' | 'delete' | 'toggle'; task: NetworkQualityTask; instanceIds?: string[] } | { kind: 'install'; agent: NetworkQualityAgent }
const confirmation = ref<Confirmation | null>(null)
const modalOpen = computed(() => !!editor.value || !!confirmation.value)
const locked = computed(() => contextLocked.value || modalOpen.value)
const finished = computed(() => mutation.value.outcome === 'success' || mutation.value.outcome === 'unknown')
const instanceId = computed(() => typeof route.query.instanceId === 'string' && isNetworkQualityId(route.query.instanceId) ? route.query.instanceId : '')
const detailMode = computed(() => route.query.instanceId !== undefined)
const detail = computed(() => agents.value.find(agent => agent.id === instanceId.value) || null)
const assigned = computed(() => tasks.value.filter(task => task.instanceIds.includes(instanceId.value)))
const selectedTaskId = ref('')
const selectedTask = computed(() => assigned.value.find(task => task.id === selectedTaskId.value) || null)
const hours = ref<HistoryHours>(24)
const periods: HistoryHours[] = [1, 6, 24, 168]
const latestMap = computed(() => new Map(latest.value.map(result => [`${result.instanceId}:${result.taskId}`, result])))
const carrierTaskMap = computed(() => {
  const grouped = new Map<string, NetworkQualityTask[]>()
  for (const task of tasks.value) for (const id of task.instanceIds) {
    const key = `${id}:${task.operator}`
    const values = grouped.get(key)
    if (values) values.push(task)
    else grouped.set(key, [task])
  }
  return grouped
})
const filteredTasks = computed(() => {
  const needle = query.value.trim().toLowerCase()
  return tasks.value.filter(task => (!operator.value || task.operator === operator.value) && (!needle || [task.name, task.target, task.region].some(value => value.toLowerCase().includes(needle))))
})
const filteredAgents = computed(() => {
  const needle = query.value.trim().toLowerCase()
  return agents.value.filter(agent => (!status.value || agent.qualityStatus === status.value)
    && (!operator.value || tasks.value.some(task => task.operator === operator.value && task.instanceIds.includes(agent.id)))
    && (!needle || [agent.displayName, agent.publicIps, agent.regionName, agent.tenancyName].some(value => value?.toLowerCase().includes(needle))))
})
const total = computed(() => tab.value === 'instances' ? filteredAgents.value.length : filteredTasks.value.length)
const totalPages = computed(() => Math.max(1, Math.ceil(total.value / size.value)))
const visibleAgents = computed(() => filteredAgents.value.slice((page.value - 1) * size.value, page.value * size.value))
const visibleTasks = computed(() => filteredTasks.value.slice((page.value - 1) * size.value, page.value * size.value))
const mobileAgents = computed(() => String(route.query.mobileRecord || '').startsWith('quality-agents:') ? filteredAgents.value : visibleAgents.value)
const mobileTasks = computed(() => String(route.query.mobileRecord || '').startsWith('quality-tasks:') ? filteredTasks.value : visibleTasks.value)
watch(tab, value => { if (compact.value) void router.replace({ path: route.path, query: { ...route.query, mobileQualityTab: value, mobileRecord: undefined } }) })
const recent = computed(() => [...(historyData.value?.points || [])].reverse().slice(0, 30))
const onlineCount = computed(() => agents.value.filter(agent => agent.qualityStatus === 'online').length)
const confirmTitle = computed(() => confirmation.value?.kind === 'toggle' ? t(confirmation.value.task.enabled ? 'networkQuality.pause' : 'networkQuality.resume') : t(`networkQuality.${confirmation.value?.kind || 'confirm'}`))
const confirmHint = computed(() => {
  const action = confirmation.value
  if (!action) return ''
  if (action.kind === 'install') return t('networkQuality.installHint')
  if (action.kind === 'run') return t('networkQuality.runHint', { count: action.instanceIds?.length || action.task.instanceIds.length })
  return t(action.kind === 'delete' ? 'networkQuality.deleteHint' : action.task.enabled ? 'networkQuality.pauseHint' : 'networkQuality.resumeHint', { name: action.task.name })
})
const receipt = computed(() => {
  const result = mutation.value.result
  if (!result) return ''
  if (result.kind === 'run') return t('networkQuality.queued', { queued: result.receipt.queued, running: result.receipt.alreadyRunning, waiting: result.receipt.alreadyQueued, requested: result.receipt.requested })
  return t(result.kind === 'save' ? 'networkQuality.saved' : result.kind === 'delete' ? 'networkQuality.deleted' : 'networkQuality.installed')
})
function number(value: number | null | undefined, digits = 1) { return value == null ? '—' : new Intl.NumberFormat(locale.value, { maximumFractionDigits: digits }).format(value) }
function latency(value: number | null | undefined) { return value == null ? '—' : t('networkQuality.ms', { value: number(value) }) }
function time(value: number | null | undefined) { return value == null ? '—' : new Intl.DateTimeFormat(locale.value, { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(value) }
function errorText(value: { key: string } | null) { if (!value) return ''; const key = `networkQuality.errors.${value.key}`; return t(te(key) ? key : 'networkQuality.errors.request') }
function ip(agent: NetworkQualityAgent) { return agent.publicIps ? exposed.value.has(agent.id) ? agent.publicIps : '••••••' : '—' }
function toggleIp(agent: NetworkQualityAgent) { exposed.value.has(agent.id) ? exposed.value.delete(agent.id) : exposed.value.add(agent.id) }
function carrierTasks(id: string, carrier: QualityOperator) { return carrierTaskMap.value.get(`${id}:${carrier}`) || [] }
function resultFor(id: string, task: NetworkQualityTask) { const result = latestMap.value.get(`${id}:${task.id}`); return result?.revision === task.version ? result : undefined }
function resultText(result: NetworkQualityResult | undefined) {
  if (!result) return t('networkQuality.noData')
  if (result.avgMs == null) return t(`networkQuality.statuses.${result.status}`)
  return latency(result.avgMs) + (result.status !== 'success' ? ` · ${t(`networkQuality.statuses.${result.status}`)}` : '')
}
function reason(result: NetworkQualityResult) { const key = `networkQuality.reasons.${result.errorCode}`; return [result.errorCode && te(key) ? t(key) : '', result.httpStatus != null ? `HTTP ${result.httpStatus}` : ''].filter(Boolean).join(' · ') || '—' }
function oldSample(result: NetworkQualityResult | undefined, task: NetworkQualityTask) { return !!result && (!task.enabled || Date.now() - result.updatedAt > Math.max(90000, task.intervalSeconds * 2000)) }
function back() {
  if (locked.value) { blocked.value = true; return }
  if (detailMode.value) { const next = { ...route.query }; delete next.instanceId; void router.push({ path: route.path, query: next }); return }
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/vps/instances/list')
}
function openDetail(agent: NetworkQualityAgent) { if (!locked.value) void router.push({ path: '/system/ipSettings', query: { instanceId: agent.id } }) }
function ssh(agent: NetworkQualityAgent) { if (!locked.value) void router.push({ path: '/oci/terminal', query: { instanceId: agent.id } }) }
function openEditor(task: NetworkQualityTask | null = null) { if (!canMutate.value || locked.value) return; clearMutation(); blocked.value = false; editor.value = { task: task ? { ...task, instanceIds: [...task.instanceIds] } : null, instanceId: detail.value?.id } }
function closeEditor() { if (!contextLocked.value) { editor.value = null; blocked.value = false } }
function save(input: NetworkQualityTaskInput) { if (editor.value) void saveTask(input, editor.value.task || undefined) }
function ask(action: Confirmation) { if (!canMutate.value || locked.value) return; clearMutation(); blocked.value = false; confirmation.value = action }
function closeConfirmation() { if (!contextLocked.value) { confirmation.value = null; blocked.value = false } }
function confirmVisibility(value: boolean) { if (!value) closeConfirmation() }
function confirm() {
  const action = confirmation.value
  if (!action || contextLocked.value || finished.value) return
  if (action.kind === 'install') void installAgent(action.agent)
  else if (action.kind === 'delete') void deleteTask(action.task)
  else if (action.kind === 'run') void runTask(action.task, action.instanceIds)
  else void saveTask({ name: action.task.name, operator: action.task.operator, region: action.task.region, type: action.task.type, target: action.task.target, intervalSeconds: action.task.intervalSeconds, sampleCount: action.task.sampleCount, enabled: !action.task.enabled, instanceIds: [...action.task.instanceIds] }, action.task)
}
function changePage(value: number) { if (!locked.value && value >= 1 && value <= totalPages.value) page.value = value }
function loadHistory() {
  if (detail.value && selectedTask.value) void readHistory({ instanceId: detail.value.id, taskId: selectedTask.value.id, revision: selectedTask.value.version, hours: hours.value })
  else closeHistory()
}
function refreshAll() { if (!locked.value) { void refresh(); if (detailMode.value) void refreshHistory() } }
function guard() { if (!locked.value && !requiresReview.value) return true; blocked.value = true; return false }
function guardUpdate() { if (!locked.value) return true; blocked.value = true; return false }
function beforeUnload(event: BeforeUnloadEvent) { if (locked.value || requiresReview.value) { event.preventDefault(); event.returnValue = '' } }
let timer: ReturnType<typeof setInterval> | undefined
let motion: gsap.MatchMedia | undefined
let tween: gsap.core.Tween | undefined
let canAnimate = false
async function entrance() {
  await nextTick()
  if (!root.value || !canAnimate) return
  tween?.revert()
  const surface = root.value.querySelector('[data-nq-surface]')
  if (surface) tween = gsap.fromTo(surface, { opacity: 0, y: 5 }, { opacity: 1, y: 0, duration: .22, ease: 'power2.out', clearProps: 'opacity,transform' })
}
function tick() {
  if (document.hidden || locked.value || loading.value || requiresReview.value) return
  void refresh()
  if (detailMode.value && !historyLoading.value) void refreshHistory()
}
watch([query, operator, status, tab, size], () => { page.value = 1 })
watch(totalPages, value => { if (page.value > value) page.value = value })
watch([instanceId, () => assigned.value.map(task => task.id).join(','), () => route.query.qualityInstance, () => route.query.qualityTask, () => route.query.qualityHours], () => {
  const scoped = route.query.qualityInstance === instanceId.value
  const requestedTask = scoped && typeof route.query.qualityTask === 'string' ? route.query.qualityTask : ''
  if (requestedTask && assigned.value.some(task => task.id === requestedTask)) selectedTaskId.value = requestedTask
  else if (!assigned.value.some(task => task.id === selectedTaskId.value)) selectedTaskId.value = assigned.value[0]?.id || ''
  const requestedHours = Number(route.query.qualityHours)
  if (scoped && periods.includes(requestedHours as HistoryHours)) hours.value = requestedHours as HistoryHours
})
watch([selectedTaskId, hours, compact, loaded, locked], () => {
  if (!compact.value || !loaded.value || locked.value || !detailMode.value || !detail.value || !selectedTask.value) return
  const values = { qualityInstance: instanceId.value, qualityTask: selectedTaskId.value, qualityHours: String(hours.value) }
  if (Object.entries(values).every(([key, value]) => route.query[key] === value)) return
  void router.replace({ query: { ...route.query, ...values } })
}, { flush: 'post' })
watch([instanceId, () => selectedTask.value?.id, () => selectedTask.value?.version, hours], () => { closeHistory(); loadHistory() })
watch([tab, detailMode], entrance)
watch(() => mutation.value.pending, (pending, previous) => {
  if (pending || !previous) return
  if (mutation.value.outcome === 'success') { editor.value = null; confirmation.value = null; blocked.value = false }
  if (detailMode.value) loadHistory()
})
watch(agents, (current, previous) => { const prior = new Map(previous.map(agent => [agent.id, agent.publicIps])); exposed.value = new Set(current.filter(agent => exposed.value.has(agent.id) && prior.get(agent.id) === agent.publicIps).map(agent => agent.id)) })
onBeforeRouteLeave(guard)
onBeforeRouteUpdate(guardUpdate)
onMounted(() => {
  void refresh()
  motion = gsap.matchMedia()
  motion.add('(prefers-reduced-motion: no-preference)', () => { canAnimate = true; void entrance(); return () => { canAnimate = false; tween?.revert() } }, root.value || undefined)
  timer = setInterval(tick, 10000)
  document.addEventListener('visibilitychange', tick)
  window.addEventListener('beforeunload', beforeUnload)
})
onBeforeUnmount(() => { clearInterval(timer); tween?.revert(); motion?.revert(); document.removeEventListener('visibilitychange', tick); window.removeEventListener('beforeunload', beforeUnload) })
</script>

<template>
  <section ref="root" class="nq-page" :aria-label="t('networkQuality.title')">
    <header class="nq-toolbar">
      <PageBackButton :disabled="locked" @click="back" />
      <template v-if="!detailMode">
        <div class="nq-tabs" :aria-label="t('networkQuality.title')"><button type="button" :aria-pressed="tab === 'instances'" :disabled="locked" @click="tab = 'instances'"><i class="i-mdi-server-outline" aria-hidden="true" />{{ t('networkQuality.instances') }}</button><button type="button" :aria-pressed="tab === 'tasks'" :disabled="locked" @click="tab = 'tasks'"><i class="i-mdi-format-list-checks" aria-hidden="true" />{{ t('networkQuality.tasks') }}</button></div>
        <label class="nq-search"><i class="i-mdi-magnify" aria-hidden="true" /><input v-model="query" type="search" :disabled="locked" :placeholder="t('networkQuality.search')" :aria-label="t('networkQuality.search')" /></label>
        <el-select v-model="operator" class="nq-operator-select" :disabled="locked" :teleported="true" :empty-values="[null, undefined]" :aria-label="t('networkQuality.operator')"><el-option value="" :label="t('networkQuality.allOperators')" /><el-option v-for="value in operators" :key="value" :value="value" :label="t(`networkQuality.operators.${value}`)" /></el-select>
      </template>
      <template v-else-if="detail"><strong class="nq-detail-name nq-truncate" :title="detail.displayName || detail.id">{{ detail.displayName || detail.id }}</strong><button type="button" class="nq-link nq-ip" :aria-label="t(exposed.has(detail.id) ? 'networkQuality.hideIp' : 'networkQuality.showIp')" @click="toggleIp(detail)">{{ ip(detail) }}<i :class="exposed.has(detail.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button><span class="nq-badge" :class="`is-${detail.qualityStatus}`">{{ t(`networkQuality.agents.${detail.qualityStatus}`) }}</span></template>
      <div class="nq-toolbar-end" data-page-error-anchor><GhostBtn v-if="detail && detailMode" :disabled="locked" @click="ssh(detail)"><i class="i-mdi-console" aria-hidden="true" />{{ t('networkQuality.ssh') }}</GhostBtn><GhostBtn :loading="loading" :disabled="locked" :title="t('networkQuality.refresh')" :aria-label="t('networkQuality.refresh')" @click="refreshAll"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn><PrimaryBtn :disabled="!canMutate || locked" @click="openEditor()"><i class="i-mdi-plus" aria-hidden="true" />{{ t('networkQuality.create') }}</PrimaryBtn></div>
    </header>
    <PageErrorNotice v-if="problem">{{ errorText(problem) }} {{ loaded ? t('networkQuality.retained') : '' }}</PageErrorNotice>
    <div v-if="blocked" class="nq-notice is-warning" role="alert">{{ t('networkQuality.blocked') }}</div>
    <PageErrorNotice v-if="!mutation.pending && mutation.outcome === 'failed' && !requiresReview"><span>{{ receipt || errorText(mutation.problem) }}</span><GhostBtn v-if="!modalOpen" @click="clearMutation"><i class="i-mdi-check" aria-hidden="true" />{{ t('networkQuality.dismiss') }}</GhostBtn></PageErrorNotice>
    <div v-else-if="mutation.pending || mutation.outcome !== 'idle'" class="nq-notice" :class="{ 'is-success': mutation.outcome === 'success', 'is-warning': requiresReview }" role="status">
      <span>{{ mutation.pending ? t('networkQuality.submitting') : requiresReview ? t('networkQuality.unknownResult') : receipt || errorText(mutation.problem) }}</span>
      <template v-if="requiresReview"><GhostBtn :disabled="locked" :loading="loading" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('networkQuality.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady || locked" @click="acknowledgeReview"><i class="i-mdi-check" aria-hidden="true" />{{ t('networkQuality.reviewed') }}</GhostBtn></template>
      <GhostBtn v-else-if="!mutation.pending && !modalOpen" @click="clearMutation"><i class="i-mdi-check" aria-hidden="true" />{{ t('networkQuality.dismiss') }}</GhostBtn>
    </div>
    <template v-if="!detailMode">
      <div class="nq-statusbar"><span>{{ t('networkQuality.counts', { agents: number(agents.length, 0), tasks: number(tasks.length, 0) }) }}</span><span class="nq-online"><span class="nq-dot" />{{ t('networkQuality.onlineCount', { count: number(onlineCount, 0) }) }}</span><el-select v-if="tab === 'instances'" v-model="status" class="nq-status-select" :disabled="locked" :teleported="true" :empty-values="[null, undefined]" :aria-label="t('networkQuality.agent')"><el-option value="" :label="t('networkQuality.allStatuses')" /><el-option v-for="value in ['online', 'offline', 'upgrade_required', 'not_installed']" :key="value" :value="value" :label="t(`networkQuality.agents.${value}`)" /></el-select><span class="nq-status-end">{{ t('networkQuality.autoRefresh') }}</span></div>
      <div data-nq-surface class="nq-table-wrap" :aria-busy="loading">
        <MobileRecordList v-if="compact && tab === 'instances'" drilldown list-id="quality-agents" :record-keys="filteredAgents.map(agent => agent.id)" :loading="loading">
          <MobileRecordCard v-for="agent in mobileAgents" :key="agent.id" :record-key="agent.id" :summary-title="agent.displayName || agent.id" :summary-meta="agent.regionName || ip(agent)" :summary-status="t(`networkQuality.agents.${agent.qualityStatus}`)" :summary-tone="agent.qualityStatus === 'online' ? 'success' : 'neutral'">
            <template #identity><button type="button" class="nq-name nq-truncate" :disabled="locked" :title="agent.displayName || agent.id" @click="openDetail(agent)">{{ agent.displayName || agent.id }}</button><button type="button" class="nq-link nq-ip" :aria-label="t(exposed.has(agent.id) ? 'networkQuality.hideIp' : 'networkQuality.showIp')" @click="toggleIp(agent)"><span class="nq-truncate">{{ ip(agent) }}</span><i :class="exposed.has(agent.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('networkQuality.location') }}</dt><dd><span class="nq-truncate" :title="agent.regionName || undefined">{{ agent.regionName || '—' }}</span><small>{{ agent.cloudType === 1 ? 'Oracle Cloud' : agent.cloudType === 2 ? 'Google Cloud' : agent.cloudType === 3 ? 'Azure' : agent.cloudType === 4 ? 'AWS' : 'VPS' }}</small></dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.agent') }}</dt><dd><span class="nq-badge" :class="`is-${agent.qualityStatus}`">{{ t(`networkQuality.agents.${agent.qualityStatus}`) }}</span><small>{{ time(agent.lastSeen) }}</small></dd></div><div v-for="carrier in operators" :key="carrier" class="mobile-record-wide"><dt>{{ t(`networkQuality.operators.${carrier}`) }}</dt><dd><template v-if="carrierTasks(agent.id, carrier).length === 1"><template v-for="task in carrierTasks(agent.id, carrier)" :key="task.id"><span class="nq-value" :class="`is-${resultFor(agent.id, task)?.status || 'empty'}`">{{ resultText(resultFor(agent.id, task)) }}</span><small class="nq-truncate" :title="`${task.name} · ${task.type.toUpperCase()}`">{{ task.name }} · {{ task.type.toUpperCase() }}</small><small v-if="oldSample(resultFor(agent.id, task), task)">{{ t('networkQuality.stale') }}</small><small v-else-if="!task.enabled">{{ t('networkQuality.paused') }}</small></template></template><button v-else-if="carrierTasks(agent.id, carrier).length > 1" type="button" class="nq-link" :disabled="locked" @click="openDetail(agent)">{{ t('networkQuality.multipleTargets', { count: carrierTasks(agent.id, carrier).length }) }}<i class="i-mdi-chevron-right" aria-hidden="true" /></button><span v-else class="nq-empty-value">—</span></dd></div></dl>
            <template #footer><div class="nq-row-actions"><GhostBtn :disabled="locked" @click="openDetail(agent)"><i class="i-mdi-chart-timeline-variant" aria-hidden="true" />{{ t('networkQuality.history') }}</GhostBtn><GhostBtn v-if="agent.qualityStatus !== 'online'" :disabled="!canMutate || locked" @click="ask({ kind: 'install', agent })"><i class="i-mdi-download-outline" aria-hidden="true" />{{ t(agent.qualityStatus === 'not_installed' ? 'networkQuality.install' : 'networkQuality.upgrade') }}</GhostBtn></div></template>
          </MobileRecordCard>
        </MobileRecordList>
        <MobileRecordList v-else-if="compact" drilldown list-id="quality-tasks" :record-keys="filteredTasks.map(task => task.id)" :loading="loading">
          <MobileRecordCard v-for="task in mobileTasks" :key="task.id" :record-key="task.id" :summary-title="task.name" :summary-meta="task.target" :summary-status="t(task.enabled ? 'networkQuality.active' : 'networkQuality.paused')" :summary-tone="task.enabled ? 'success' : 'neutral'">
            <template #identity><h3 class="mobile-record-title">{{ task.name }}</h3></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('networkQuality.name') }}</dt><dd><strong class="nq-truncate" :title="task.name">{{ task.name }}</strong><small>{{ task.type.toUpperCase() }}</small></dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.operator') }}</dt><dd>{{ t(`networkQuality.operators.${task.operator}`) }}<small class="nq-truncate" :title="task.region">{{ task.region || '—' }}</small></dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.target') }}</dt><dd><span class="nq-truncate" :title="task.target">{{ task.target }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.assigned') }}</dt><dd>{{ t('networkQuality.selected', { count: task.instanceIds.length }) }}</dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.cadence') }}</dt><dd>{{ t('networkQuality.seconds', { count: task.intervalSeconds }) }}<small>{{ t('networkQuality.sampleCount', { count: task.sampleCount }) }}</small></dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.taskState') }}</dt><dd><span class="nq-badge" :class="task.enabled ? 'is-online' : ''">{{ t(task.enabled ? 'networkQuality.active' : 'networkQuality.paused') }}</span></dd></div></dl>
            <template #footer><div class="nq-row-actions"><GhostBtn :disabled="!canMutate || locked" @click="openEditor(task)"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('networkQuality.edit') }}</GhostBtn><GhostBtn :disabled="!canMutate || locked" @click="ask({ kind: 'run', task })"><i class="i-mdi-play-outline" aria-hidden="true" />{{ t('networkQuality.run') }}</GhostBtn><GhostBtn :disabled="!canMutate || locked" :aria-label="t(task.enabled ? 'networkQuality.pause' : 'networkQuality.resume')" :title="t(task.enabled ? 'networkQuality.pause' : 'networkQuality.resume')" @click="ask({ kind: 'toggle', task })"><i :class="task.enabled ? 'i-mdi-pause' : 'i-mdi-play-circle-outline'" aria-hidden="true" /></GhostBtn><GhostBtn danger :disabled="!canMutate || locked" :aria-label="t('networkQuality.delete')" :title="t('networkQuality.delete')" @click="ask({ kind: 'delete', task })"><i class="i-mdi-trash-can-outline" aria-hidden="true" /></GhostBtn></div></template>
          </MobileRecordCard>
        </MobileRecordList>
        <table v-else-if="tab === 'instances'" class="nq-table nq-instance-table" :aria-label="t('networkQuality.instances')"><thead><tr><th scope="col">{{ t('networkQuality.instance') }}</th><th scope="col">{{ t('networkQuality.location') }}</th><th scope="col">{{ t('networkQuality.agent') }}</th><th v-for="value in operators" :key="value" scope="col">{{ t(`networkQuality.operators.${value}`) }}</th><th scope="col">{{ t('networkQuality.actions') }}</th></tr></thead><tbody>
          <tr v-for="agent in visibleAgents" :key="agent.id"><td><button type="button" class="nq-name nq-truncate" :disabled="locked" :title="agent.displayName || agent.id" @click="openDetail(agent)">{{ agent.displayName || agent.id }}</button><button type="button" class="nq-link nq-ip" :aria-label="t(exposed.has(agent.id) ? 'networkQuality.hideIp' : 'networkQuality.showIp')" @click="toggleIp(agent)"><span class="nq-truncate">{{ ip(agent) }}</span><i :class="exposed.has(agent.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></td><td><span class="nq-truncate" :title="agent.regionName || undefined">{{ agent.regionName || '—' }}</span><small>{{ agent.cloudType === 1 ? 'Oracle Cloud' : agent.cloudType === 2 ? 'Google Cloud' : agent.cloudType === 3 ? 'Azure' : agent.cloudType === 4 ? 'AWS' : 'VPS' }}</small></td><td><span class="nq-badge" :class="`is-${agent.qualityStatus}`">{{ t(`networkQuality.agents.${agent.qualityStatus}`) }}</span><small>{{ time(agent.lastSeen) }}</small></td>
            <td v-for="carrier in operators" :key="carrier"><template v-if="carrierTasks(agent.id, carrier).length === 1"><template v-for="task in carrierTasks(agent.id, carrier)" :key="task.id"><span class="nq-value" :class="`is-${resultFor(agent.id, task)?.status || 'empty'}`">{{ resultText(resultFor(agent.id, task)) }}</span><small class="nq-truncate" :title="`${task.name} · ${task.type.toUpperCase()}`">{{ task.name }} · {{ task.type.toUpperCase() }}</small><small v-if="oldSample(resultFor(agent.id, task), task)">{{ t('networkQuality.stale') }}</small><small v-else-if="!task.enabled">{{ t('networkQuality.paused') }}</small></template></template><button v-else-if="carrierTasks(agent.id, carrier).length > 1" type="button" class="nq-link" :disabled="locked" @click="openDetail(agent)">{{ t('networkQuality.multipleTargets', { count: carrierTasks(agent.id, carrier).length }) }}<i class="i-mdi-chevron-right" aria-hidden="true" /></button><span v-else class="nq-empty-value">—</span></td>
            <td><div class="nq-row-actions"><GhostBtn :disabled="locked" @click="openDetail(agent)"><i class="i-mdi-chart-timeline-variant" aria-hidden="true" />{{ t('networkQuality.history') }}</GhostBtn><GhostBtn v-if="agent.qualityStatus !== 'online'" :disabled="!canMutate || locked" @click="ask({ kind: 'install', agent })"><i class="i-mdi-download-outline" aria-hidden="true" />{{ t(agent.qualityStatus === 'not_installed' ? 'networkQuality.install' : 'networkQuality.upgrade') }}</GhostBtn></div></td>
          </tr>
        </tbody></table>
        <table v-else class="nq-table nq-task-table" :aria-label="t('networkQuality.tasks')"><thead><tr><th scope="col">{{ t('networkQuality.name') }}</th><th scope="col">{{ t('networkQuality.operator') }}</th><th scope="col">{{ t('networkQuality.target') }}</th><th scope="col">{{ t('networkQuality.assigned') }}</th><th scope="col">{{ t('networkQuality.cadence') }}</th><th scope="col">{{ t('networkQuality.taskState') }}</th><th scope="col">{{ t('networkQuality.actions') }}</th></tr></thead><tbody><tr v-for="task in visibleTasks" :key="task.id"><td><strong class="nq-truncate" :title="task.name">{{ task.name }}</strong><small>{{ task.type.toUpperCase() }}</small></td><td>{{ t(`networkQuality.operators.${task.operator}`) }}<small class="nq-truncate" :title="task.region">{{ task.region || '—' }}</small></td><td><span class="nq-truncate" :title="task.target">{{ task.target }}</span></td><td>{{ t('networkQuality.selected', { count: task.instanceIds.length }) }}</td><td>{{ t('networkQuality.seconds', { count: task.intervalSeconds }) }}<small>{{ t('networkQuality.sampleCount', { count: task.sampleCount }) }}</small></td><td><span class="nq-badge" :class="task.enabled ? 'is-online' : ''">{{ t(task.enabled ? 'networkQuality.active' : 'networkQuality.paused') }}</span></td><td><div class="nq-row-actions"><GhostBtn :disabled="!canMutate || locked" @click="openEditor(task)"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('networkQuality.edit') }}</GhostBtn><GhostBtn :disabled="!canMutate || locked" @click="ask({ kind: 'run', task })"><i class="i-mdi-play-outline" aria-hidden="true" />{{ t('networkQuality.run') }}</GhostBtn><GhostBtn :disabled="!canMutate || locked" :aria-label="t(task.enabled ? 'networkQuality.pause' : 'networkQuality.resume')" :title="t(task.enabled ? 'networkQuality.pause' : 'networkQuality.resume')" @click="ask({ kind: 'toggle', task })"><i :class="task.enabled ? 'i-mdi-pause' : 'i-mdi-play-circle-outline'" aria-hidden="true" /></GhostBtn><GhostBtn danger :disabled="!canMutate || locked" :aria-label="t('networkQuality.delete')" :title="t('networkQuality.delete')" @click="ask({ kind: 'delete', task })"><i class="i-mdi-trash-can-outline" aria-hidden="true" /></GhostBtn></div></td></tr></tbody></table>
        <div v-if="!total" class="nq-empty" role="status"><i class="i-mdi-access-point-network" aria-hidden="true" /><p>{{ !loaded ? t(loading ? 'networkQuality.loading' : 'networkQuality.notLoaded') : query || operator || status ? t('networkQuality.noMatches') : t(tab === 'tasks' ? 'networkQuality.emptyTasks' : 'networkQuality.emptyInstances') }}</p><span v-if="loaded && !tasks.length">{{ t('networkQuality.emptyTasksHint') }}</span></div>
      </div>
      <PagePagination :current-page="page" v-model:page-size="size" :total="total" :page-sizes="[10, 20, 30, 50]" :disabled="locked" @current-change="changePage"><span>{{ t('networkQuality.total', { count: number(total, 0) }) }}</span></PagePagination>
    </template>
    <template v-else>
      <div v-if="!detail" class="nq-empty" role="status">{{ t(loading ? 'networkQuality.loading' : 'networkQuality.missingInstance') }}</div>
      <div v-else data-nq-surface class="nq-detail-scroll">
        <div v-if="detail.qualityStatus !== 'online'" class="nq-detail-agent"><span>{{ t(`networkQuality.agents.${detail.qualityStatus}`) }} · {{ t('networkQuality.lastUpdated', { time: time(detail.lastSeen) }) }}</span><GhostBtn :disabled="!canMutate || locked" @click="ask({ kind: 'install', agent: detail })"><i class="i-mdi-download-outline" aria-hidden="true" />{{ t(detail.qualityStatus === 'not_installed' ? 'networkQuality.install' : 'networkQuality.upgrade') }}</GhostBtn></div>
        <div class="nq-history-toolbar"><label><span class="nq-sr-only">{{ t('networkQuality.targetSelect') }}</span><el-select v-model="selectedTaskId" :disabled="locked || !assigned.length" :teleported="true" :empty-values="[null, undefined]" :aria-label="t('networkQuality.targetSelect')"><el-option v-if="!assigned.length" value="" :label="t('networkQuality.noAssigned')" /><el-option v-for="task in assigned" :key="task.id" :value="task.id" :label="`${task.name} · ${task.type.toUpperCase()}`" /></el-select></label><div class="nq-periods" :aria-label="t('networkQuality.window')"><button v-for="value in periods" :key="value" type="button" :disabled="locked" :aria-pressed="hours === value" @click="hours = value">{{ t(`networkQuality.hour${value}`) }}</button></div><GhostBtn v-if="selectedTask" :disabled="!canMutate || locked" @click="ask({ kind: 'run', task: selectedTask, instanceIds: [detail.id] })"><i class="i-mdi-play-outline" aria-hidden="true" />{{ t('networkQuality.run') }}</GhostBtn></div>
        <div v-if="selectedTask" class="nq-target-caption"><span class="nq-truncate" :title="selectedTask.target">{{ t(`networkQuality.operators.${selectedTask.operator}`) }} · {{ selectedTask.region || '—' }} · {{ selectedTask.target }}</span><span v-if="!selectedTask.enabled">{{ t('networkQuality.stopped') }}</span></div>
        <PageErrorNotice v-if="historyProblem">{{ errorText(historyProblem) }} {{ historyData ? t('networkQuality.retained') : '' }}</PageErrorNotice>
        <div class="nq-history-content" :aria-busy="historyLoading">
          <dl class="nq-stats"><div><dt>{{ t('networkQuality.avg') }}</dt><dd>{{ latency(historyData?.stats.avgMs) }}</dd></div><div><dt>{{ t('networkQuality.min') }}</dt><dd>{{ latency(historyData?.stats.minMs) }}</dd></div><div><dt>{{ t('networkQuality.max') }}</dt><dd>{{ latency(historyData?.stats.maxMs) }}</dd></div><div><dt>{{ t(selectedTask?.type === 'icmp' ? 'networkQuality.packetLoss' : 'networkQuality.failureRate') }}</dt><dd>{{ historyData?.stats.lossPercent == null ? '—' : `${number(historyData.stats.lossPercent)}%` }}</dd></div><div><dt>{{ t('networkQuality.attempts') }}</dt><dd>{{ number(historyData?.stats.successful, 0) }} / {{ number(historyData?.stats.attempts, 0) }}</dd></div></dl>
          <NetworkQualityChart :history="historyData" :type="selectedTask?.type || 'icmp'" :operator="selectedTask?.operator" />
          <p class="nq-chart-note">{{ t('networkQuality.protocolHint') }}</p><p class="nq-chart-note">{{ historyData?.truncated ? t('networkQuality.historyTrimmed', { count: historyData.points.length, total: historyData.totalPoints }) : t('networkQuality.historyHint') }}</p>
        </div>
        <div class="nq-record-heading"><h2>{{ t('networkQuality.recent') }}</h2><span v-if="historyLoading" role="status">{{ t('networkQuality.loading') }}</span></div>
        <div class="nq-records"><MobileRecordList v-if="compact" drilldown :list-id="`quality-history-${instanceId}-${selectedTaskId}`" :record-keys="recent.map(item => item.executionId)" :loading="historyLoading">
          <MobileRecordCard v-for="item in recent" :key="item.executionId" :record-key="item.executionId" :summary-title="time(item.updatedAt)" :summary-meta="latency(item.avgMs)" :summary-status="t(`networkQuality.statuses.${item.status}`)">
            <template #identity><h3 class="mobile-record-title">{{ time(item.updatedAt) }}</h3></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('networkQuality.time') }}</dt><dd>{{ time(item.updatedAt) }}</dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.result') }}</dt><dd><span class="nq-badge" :class="`is-${item.status}`">{{ t(`networkQuality.statuses.${item.status}`) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.avg') }}</dt><dd>{{ latency(item.avgMs) }}</dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.attempts') }}</dt><dd>{{ number(item.successful, 0) }} / {{ number(item.attempts, 0) }}</dd></div><div class="mobile-record-wide"><dt>{{ t('networkQuality.reason') }}</dt><dd>{{ reason(item) }}</dd></div></dl>
          </MobileRecordCard>
        </MobileRecordList><table v-else class="nq-table nq-history-table" :aria-label="t('networkQuality.recent')"><thead><tr><th scope="col">{{ t('networkQuality.time') }}</th><th scope="col">{{ t('networkQuality.result') }}</th><th scope="col">{{ t('networkQuality.avg') }}</th><th scope="col">{{ t('networkQuality.attempts') }}</th><th scope="col">{{ t('networkQuality.reason') }}</th></tr></thead><tbody><tr v-for="item in recent" :key="item.executionId"><td>{{ time(item.updatedAt) }}</td><td><span class="nq-badge" :class="`is-${item.status}`">{{ t(`networkQuality.statuses.${item.status}`) }}</span></td><td>{{ latency(item.avgMs) }}</td><td>{{ number(item.successful, 0) }} / {{ number(item.attempts, 0) }}</td><td>{{ reason(item) }}</td></tr></tbody></table><div v-if="!recent.length" class="nq-empty nq-empty-small">{{ t('networkQuality.noData') }}</div></div>
      </div>
    </template>
    <div class="nq-footnote"><span>{{ lastUpdated ? t('networkQuality.lastUpdated', { time: time(lastUpdated) }) : t('networkQuality.notLoaded') }}</span><span>{{ t('networkQuality.noAutomaticIpChange') }}</span></div>
    <NetworkQualityTaskDialog v-if="editor" :task="editor.task" :agents="agents" :pending="mutation.pending" :finished="finished" :feedback="requiresReview ? t('networkQuality.unknownResult') : errorText(mutation.problem)" :initial-instance-id="editor.instanceId" @close="closeEditor" @save="save" />
    <el-dialog v-if="confirmation" :model-value="true" append-to-body width="560px" class="nq-dialog" :title="confirmTitle" :close-on-click-modal="false" :close-on-press-escape="!contextLocked" :show-close="!contextLocked" :before-close="closeConfirmation" @update:model-value="confirmVisibility">
      <p class="nq-confirm-target">{{ confirmation.kind === 'install' ? confirmation.agent.displayName || confirmation.agent.id : confirmation.task.name }}</p><p>{{ confirmHint }}</p><PageErrorNotice v-if="!mutation.pending && mutation.outcome === 'failed' && !requiresReview">{{ receipt || errorText(mutation.problem) }}</PageErrorNotice><div v-else-if="mutation.pending || mutation.outcome !== 'idle'" class="nq-notice" role="status">{{ mutation.pending ? t('networkQuality.submitting') : requiresReview ? t('networkQuality.unknownResult') : receipt || errorText(mutation.problem) }}</div>
      <template #footer><GhostBtn :disabled="contextLocked" @click="closeConfirmation">{{ t(finished ? 'networkQuality.close' : 'networkQuality.cancel') }}</GhostBtn><PrimaryBtn v-if="!finished" :loading="contextLocked" :class="{ 'nq-danger': confirmation.kind === 'delete' }" @click="confirm"><i :class="confirmation.kind === 'delete' ? 'i-mdi-trash-can-outline' : 'i-mdi-check'" aria-hidden="true" />{{ t('networkQuality.confirm') }}</PrimaryBtn></template>
    </el-dialog>
  </section>
</template>

<style scoped>
.mobile-record-fields .nq-truncate { max-width: 100%; white-space: normal; overflow-wrap: anywhere; }
.mobile-record-fields small { display: block; margin-top: 4px; }
.mobile-record-card .nq-row-actions { flex-wrap: wrap; }
</style>
