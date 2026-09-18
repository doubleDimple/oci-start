<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import type { VpsRow } from '@/api/vps'
import type { NetworkQualityAgent, NetworkQualityResult, NetworkQualityTask, QualityOperator } from '@/api/networkQuality'
import type { VpsAgentStatus, VpsLiveMetrics } from './useVpsLive'
import type { VpsLatencyResult } from './useVpsLatency'
import VpsNetworkQuality from './VpsNetworkQuality.vue'

interface QualityEntry { task: NetworkQualityTask; result: NetworkQualityResult | null }
const props = defineProps<{
  row: VpsRow | null
  metrics: VpsLiveMetrics | null
  agentState: VpsAgentStatus
  latency: VpsLatencyResult | null
  qualityAgent: NetworkQualityAgent | null
  qualityEntries: QualityEntry[]
  qualityLoaded: boolean
  qualityLoading: boolean
  qualityStale: boolean
  qualityServerTime: number | null
  ipVisible: boolean
  tenantVisible: boolean
  disabled: boolean
}>()
const emit = defineEmits<{ close: []; toggleIp: []; toggleTenant: []; quality: [] }>()
const { t, locale } = useI18n()
const compact = useCompactViewport()
const unknown = '—'
function number(value: number | null | undefined, digits = 2): string {
  return value == null || !Number.isFinite(value) ? unknown
    : new Intl.NumberFormat(locale.value, { maximumFractionDigits: digits }).format(value)
}
function percent(value: number | null | undefined): string {
  return value == null ? unknown : new Intl.NumberFormat(locale.value, { style: 'percent', maximumFractionDigits: 1 }).format(value / 100)
}
function amount(value: number | null | undefined, unit: string): string { return value == null ? unknown : `${number(value)} ${unit}` }
function byteSize(value: number | null | undefined): string {
  if (value == null) return unknown
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']
  let scaled = value, index = 0
  while (scaled >= 1024 && index < units.length - 1) { scaled /= 1024; ++index }
  return `${number(scaled)} ${units[index]}`
}
function capacity(used: number | null | undefined, total: number | null | undefined, ratio: number | null | undefined): string {
  if (used == null && total == null) return unknown
  const gib = (total ?? used ?? 0) >= 1024, divisor = gib ? 1024 : 1
  const value = `${number(used == null ? null : used / divisor)} / ${number(total == null ? null : total / divisor)} ${gib ? 'GiB' : 'MiB'}`
  return ratio == null ? value : `${value} · ${percent(ratio)}`
}
function time(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return unknown
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) return unknown
  return new Intl.DateTimeFormat(locale.value, {
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).format(date)
}
function uptime(value: number | null | undefined): string {
  if (value == null) return unknown
  let left = Math.floor(value)
  const parts: string[] = []
  for (const [unit, seconds] of [['days', 86400], ['hours', 3600], ['minutes', 60], ['seconds', 1]] as const) {
    const count = Math.floor(left / seconds); left %= seconds
    if (count || unit === 'seconds') parts.push(t(`vpsDetails.${unit}`, { count: number(count, 0) }))
  }
  return parts.join(' ')
}
function provider(value: number | null | undefined): string {
  if (value == null) return unknown
  return ({ 1: 'Oracle Cloud', 2: 'Google Cloud', 3: 'Azure', 4: 'AWS' } as Record<number, string>)[value]
    ?? t('vpsDetails.otherProvider', { code: number(value, 0) })
}
function flag(value: 0 | 1 | null | undefined): string { return value == null ? unknown : t(value ? 'vpsDetails.enabled' : 'vpsDetails.disabled') }
const resourceFields = computed(() => {
  const row = props.row
  return [
    ['recordId', row?.id || unknown], ['provider', provider(row?.cloudType)],
    ['region', row?.regionName || unknown], ['regionCode', row?.regionCode || unknown],
    ['cpuAllocation', amount(row?.ocpus, t('vpsDetails.cores'))], ['memoryAllocation', amount(row?.memoryInGBs, 'GB')],
    ['diskAllocation', amount(row?.bootVolumeSizeInGBs, 'GB')], ['architecture', row?.architecture || unknown],
    ['lastPing', row?.onLineEnable == null ? unknown : t(row.onLineEnable ? 'vpsDetails.online' : 'vpsDetails.offline')],
    ['automaticPing', row?.cloudType === 1 ? flag(row.enablePing) : t('vpsDetails.notApplicable')],
  ]
})
const metricFields = computed(() => {
  const value = props.metrics
  return [
    ['agentStatus', t(`vps.agents.${props.agentState}`)], ['receivedAt', time(value?.receivedAt)],
    ['uptime', uptime(value?.uptimeSeconds)], ['cpuUsage', percent(value?.cpuUsage)],
    ['reportedCores', number(value?.cpuCores)], ['loadOne', number(value?.load[0])],
    ['loadFive', number(value?.load[1])], ['loadFifteen', number(value?.load[2])],
    ['memoryUsage', capacity(value?.memoryUsedMiB, value?.memoryTotalMiB, value?.memoryPercent)],
    ['diskUsage', capacity(value?.diskUsedMiB, value?.diskTotalMiB, value?.diskPercent)],
    ['swapUsage', value?.swapUsedMiB == null ? unknown : byteSize(value.swapUsedMiB * 1024 * 1024)],
    ['receivedDelta', value?.rxIntervalBytes == null ? unknown : t('vpsDetails.perReport', { value: byteSize(value.rxIntervalBytes) })],
    ['sentDelta', value?.txIntervalBytes == null ? unknown : t('vpsDetails.perReport', { value: byteSize(value.txIntervalBytes) })],
    ['receivedTotal', byteSize(value?.rxTotalBytes)], ['sentTotal', byteSize(value?.txTotalBytes)],
  ]
})
const currentLatency = computed(() => props.latency?.id === props.row?.id ? props.latency : null)
const latencyFields = computed(() => {
  const value = currentLatency.value
  return [
    ['measurementStatus', value ? t(`vps.latencyStates.${value.status}`) : t('vpsDetails.notMeasured')],
    ['measurementTime', amount(value?.latencyMs, 'ms')],
    ['measurementTarget', value?.target ? props.ipVisible ? value.target : t('vpsDetails.hidden') : unknown],
    ['measurementAttempts', value ? number(value.attempts, 0) : unknown], ['measuredAt', time(value?.measuredAt)],
  ]
})
const currentQualityAgent = computed(() => props.qualityAgent?.id === props.row?.id ? props.qualityAgent : null)
const currentQualityEntries = computed<QualityEntry[]>(() => props.qualityEntries
  .filter(entry => !!props.row && entry.task.instanceIds.includes(props.row.id))
  .map(entry => ({ task: entry.task, result: entry.result?.instanceId === props.row?.id
    && entry.result?.taskId === entry.task.id && entry.result?.revision === entry.task.version ? entry.result : null })))
// The shared summary exposes task names in a tooltip. Hide those too while IPs
// are concealed, since a user may have named a check after its target address.
const summaryEntries = computed(() => currentQualityEntries.value.map(entry => ({ ...entry,
  task: { ...entry.task, name: props.ipVisible ? entry.task.name : t('vpsDetails.hiddenTarget'),
    target: props.ipVisible ? entry.task.target : '', region: props.ipVisible ? entry.task.region : '' },
})))
const carriers = computed(() => {
  const operators: QualityOperator[] = ['telecom', 'unicom', 'mobile']
  if (currentQualityEntries.value.some(entry => entry.task.operator === 'custom')) operators.push('custom')
  return operators.map(operator => ({ operator, entries: currentQualityEntries.value.filter(entry => entry.task.operator === operator) }))
})
function oldSample(entry: QualityEntry): boolean {
  return props.qualityStale || !entry.task.enabled || currentQualityAgent.value?.qualityStatus !== 'online'
    || (!!entry.result && props.qualityServerTime !== null
      && props.qualityServerTime - entry.result.updatedAt > (entry.task.intervalSeconds + 120) * 1000)
}
function qualityFields(entry: QualityEntry): string[][] {
  const result = entry.result
  const fields = [
    ['target', props.ipVisible ? entry.task.target : t('vpsDetails.hidden')],
    ['protocol', entry.task.type.toUpperCase()], ['targetRegion', props.ipVisible ? entry.task.region || unknown : t('vpsDetails.hidden')],
    ['taskStatus', t(entry.task.enabled ? 'vpsDetails.enabled' : 'vpsDetails.disabled')],
    ['interval', t('vpsDetails.seconds', { count: number(entry.task.intervalSeconds, 0) })],
    ['sampleCount', number(entry.task.sampleCount, 0)],
    ['result', result ? t(`networkQuality.statuses.${result.status}`) : t('networkQuality.noData')],
    ['average', amount(result?.avgMs, 'ms')], ['minimum', amount(result?.minMs, 'ms')], ['maximum', amount(result?.maxMs, 'ms')],
    ['successfulSamples', result && (result.successful !== null || result.attempts !== null)
      ? `${number(result.successful, 0)} / ${number(result.attempts, 0)}` : unknown],
    ['sampledAt', time(result?.updatedAt)],
  ]
  if (entry.task.type === 'http') fields.push(['httpStatus', number(result?.httpStatus, 0)])
  if (result?.errorCode && ['timeout', 'dns_error', 'connection_refused', 'network_error', 'http_error', 'unsupported', 'internal_error', 'lease_expired'].includes(result.errorCode)) {
    fields.push(['diagnostic', t(`networkQuality.reasons.${result.errorCode}`)])
  }
  return fields
}
function close() { if (!props.disabled) emit('close') }
function toggleIp() { if (!props.disabled) emit('toggleIp') }
function toggleTenant() { if (!props.disabled) emit('toggleTenant') }
function quality() { if (!props.disabled && props.row) emit('quality') }
</script>

<template>
  <el-drawer :model-value="row !== null" class="vps-resource-drawer" :title="t('vpsDetails.title')" size="min(740px, 100vw)"
    append-to-body destroy-on-close :close-on-click-modal="!disabled" :close-on-press-escape="!disabled"
    :show-close="!disabled" :before-close="close">
    <template v-if="row">
      <div class="vps-resource-heading"><h2>{{ row.displayName || '—' }}</h2></div>
      <section class="vps-resource-section">
        <h3>{{ t('vpsDetails.resource') }}</h3>
        <dl class="vps-resource-fields">
          <div class="vps-resource-wide"><dt>{{ t('vpsDetails.tenant') }}</dt><dd class="vps-resource-private"><div><span>{{ row.tenancyName || row.tenantId ? tenantVisible ? row.tenancyName || '—' : t('vpsDetails.hidden') : '—' }}</span><small v-if="tenantVisible && row.tenantId">{{ t('vpsDetails.tenantId') }} · {{ row.tenantId }}</small></div><button v-if="row.tenancyName || row.tenantId" type="button" :disabled="disabled" @click="toggleTenant"><i :class="tenantVisible ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />{{ t(tenantVisible ? 'vpsDetails.hideTenant' : 'vpsDetails.showTenant') }}</button></dd></div>
          <div class="vps-resource-wide"><dt>{{ t('vpsDetails.publicIps') }}</dt><dd class="vps-resource-private"><span class="vps-resource-addresses">{{ row.publicIps ? ipVisible ? row.publicIps : t('vpsDetails.hidden') : '—' }}</span><button v-if="row.publicIps || currentLatency?.target || currentQualityEntries.length" type="button" :disabled="disabled" @click="toggleIp"><i :class="ipVisible ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />{{ t(ipVisible ? 'vpsDetails.hideIp' : 'vpsDetails.showIp') }}</button></dd></div>
          <div v-for="field in resourceFields" :key="field[0]"><dt>{{ t(`vpsDetails.${field[0]}`) }}</dt><dd>{{ field[1] }}</dd></div>
        </dl>
      </section>

      <section class="vps-resource-section">
        <div class="vps-resource-section-heading"><h3>{{ t('vpsDetails.agent') }}</h3><span v-if="metrics?.stale" class="vps-resource-note">{{ t('vpsDetails.previousReport') }}</span></div>
        <p v-if="!metrics" class="vps-resource-note">{{ t('vpsDetails.noReport') }}</p>
        <dl class="vps-resource-fields"><div v-for="field in metricFields" :key="field[0]"><dt>{{ t(`vpsDetails.${field[0]}`) }}</dt><dd>{{ field[1] }}</dd></div></dl>
      </section>

      <section class="vps-resource-section">
        <h3>{{ t('vpsDetails.browserLatency') }}</h3>
        <dl class="vps-resource-fields"><div v-for="field in latencyFields" :key="field[0]" :class="{ 'vps-resource-wide': field[0] === 'measurementTarget' }"><dt>{{ t(`vpsDetails.${field[0]}`) }}</dt><dd>{{ field[1] }}</dd></div></dl>
      </section>

      <section class="vps-resource-section">
        <div class="vps-resource-section-heading"><h3>{{ t('vpsDetails.networkQuality') }}</h3><button type="button" class="vps-resource-link" :disabled="disabled" @click="quality"><i class="i-mdi-chart-line" aria-hidden="true" />{{ t('vpsDetails.history') }}</button></div>
        <VpsNetworkQuality :agent="currentQualityAgent" :entries="summaryEntries" :loaded="qualityLoaded" :loading="qualityLoading"
          :stale="qualityStale" :server-time="qualityServerTime" :disabled="disabled" @details="quality" />
        <template v-if="qualityLoaded && currentQualityAgent">
          <section v-for="carrier in carriers" :key="carrier.operator" class="vps-resource-carrier">
            <h4>{{ t(`networkQuality.operators.${carrier.operator}`) }}<span>{{ t('vpsDetails.targets', { count: number(carrier.entries.length, 0) }) }}</span></h4>
            <p v-if="!carrier.entries.length" class="vps-resource-note">{{ t('networkQuality.noTargets') }}</p>
            <MobileRecordList v-if="compact && carrier.entries.length" drilldown :list-id="`vps-carrier-${row.id}-${carrier.operator}`" :record-keys="carrier.entries.map(entry => entry.task.id)" :loading="qualityLoading">
              <MobileRecordCard v-for="(entry, index) in carrier.entries" :key="entry.task.id" :record-key="entry.task.id" :summary-title="ipVisible ? entry.task.name : t('vpsDetails.targetNumber', { count: number(index + 1, 0) })" :summary-meta="`${entry.task.type.toUpperCase()} · ${amount(entry.result?.avgMs, 'ms')}`" :summary-status="oldSample(entry) && entry.result ? t('networkQuality.stale') : entry.result ? t(`networkQuality.statuses.${entry.result.status}`) : t('networkQuality.noData')" :summary-tone="oldSample(entry) ? 'warning' : entry.result?.status === 'success' ? 'success' : entry.result?.status === 'failed' || entry.result?.status === 'error' ? 'danger' : 'neutral'">
                <template #identity><div class="mobile-record-title">{{ ipVisible ? entry.task.name : t('vpsDetails.targetNumber', { count: number(index + 1, 0) }) }}</div><span v-if="entry.result && oldSample(entry)" class="mobile-record-subtitle">{{ t('networkQuality.stale') }}</span></template>
                <dl class="mobile-record-fields"><div v-for="field in qualityFields(entry)" :key="field[0]" :class="{ 'mobile-record-wide': field[0] === 'target' }"><dt>{{ t(`vpsDetails.${field[0]}`) }}</dt><dd>{{ field[1] }}</dd></div></dl>
              </MobileRecordCard>
            </MobileRecordList>
            <template v-else><div v-for="(entry, index) in carrier.entries" :key="entry.task.id" class="vps-resource-target">
              <div class="vps-resource-target-heading"><strong>{{ ipVisible ? entry.task.name : t('vpsDetails.targetNumber', { count: number(index + 1, 0) }) }}</strong><span v-if="entry.result && oldSample(entry)" class="vps-resource-note">{{ t('networkQuality.stale') }}</span></div>
              <dl class="vps-resource-fields"><div v-for="field in qualityFields(entry)" :key="field[0]" :class="{ 'vps-resource-wide': field[0] === 'target' }"><dt>{{ t(`vpsDetails.${field[0]}`) }}</dt><dd>{{ field[1] }}</dd></div></dl>
            </div></template>
          </section>
        </template>
      </section>
    </template>
    <template #footer><GhostBtn :disabled="disabled" @click="close">{{ t('vpsDetails.close') }}</GhostBtn></template>
  </el-drawer>
</template>

<style lang="scss">
.vps-resource-drawer {
  background: var(--bg-card); color: var(--text-primary); font: 400 var(--font-size-body)/1.6 var(--sans);
  .el-drawer__header { margin: 0; padding: 20px 24px; border-bottom: 1px solid var(--border); color: var(--text-primary); }
  .el-drawer__title { font: 600 var(--font-size-dialog-title)/1.5 var(--sans); }
  .el-drawer__close-btn { color: var(--text-primary); }
  .el-drawer__body { min-width: 0; padding: 0 24px 24px; scrollbar-gutter: stable; }
  .el-drawer__footer { padding: 14px 24px; border-top: 1px solid var(--border); }
  .el-drawer__footer .btn { min-height: 36px; font-size: var(--font-size-body); }
  .vps-resource-heading { padding: 22px 0 0; }
  .vps-resource-heading h2 { margin: 0; font-size: var(--font-size-section); font-weight: 600; overflow-wrap: anywhere; }
  .vps-resource-section { padding: 24px 0 0; }
  .vps-resource-section + .vps-resource-section { margin-top: 24px; border-top: 1px solid var(--border); }
  .vps-resource-section h3 { margin: 0 0 12px; font-size: var(--font-size-section); font-weight: 600; }
  .vps-resource-section-heading { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; margin-bottom: 12px; }
  .vps-resource-section-heading h3 { margin: 0; }
  .vps-resource-note { margin: 6px 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
  .vps-resource-fields { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 24px; margin: 0; }
  .vps-resource-fields > div { display: grid; grid-template-columns: minmax(0, 1fr); align-content: start; gap: 4px; min-width: 0; padding: 10px 0; }
  .vps-resource-fields .vps-resource-wide { grid-column: 1 / -1; }
  .vps-resource-fields dt { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 500; }
  .vps-resource-fields dd { margin: 0; min-width: 0; color: var(--text-primary); overflow-wrap: anywhere; font-variant-numeric: tabular-nums; }
  .vps-resource-fields dd small { display: block; font-size: var(--font-size-secondary); }
  .vps-resource-fields .vps-resource-private { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
  .vps-resource-private > div, .vps-resource-private > span { min-width: 0; }
  .vps-resource-addresses { white-space: pre-wrap; }
  .vps-resource-private button, .vps-resource-link, .vps-quality-multiple {
    display: inline-flex; align-items: center; gap: 6px; min-height: 30px; padding: 0; border: 0; background: transparent;
    color: var(--text-primary); font: inherit; text-align: left; cursor: pointer;
  }
  .vps-resource-private button { flex: none; white-space: nowrap; }
  button > i { display: inline-block; flex: none; width: 18px; height: 18px; }
  .vps-resource-private button:hover:not(:disabled), .vps-resource-link:hover:not(:disabled), .vps-quality-multiple:hover:not(:disabled) { text-decoration: underline; text-underline-offset: 3px; }
  button:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
  button:disabled { cursor: default; opacity: .6; }
  .vps-quality { display: grid; gap: 8px; min-width: 0; margin: 16px 0; font-variant-numeric: tabular-nums; }
  .vps-quality-caption, .vps-quality-old, .vps-quality-protocol { color: var(--text-secondary); font-size: var(--font-size-secondary); }
  .vps-quality-line { display: grid; grid-template-columns: 84px minmax(0, 1fr) auto; align-items: baseline; gap: 10px; min-width: 0; }
  .vps-quality-carrier { display: inline-flex; align-items: center; gap: 7px; }
  .vps-quality-dot { flex: none; width: 6px; height: 6px; border-radius: 50%; background: var(--text-secondary); }
  .vps-quality-dot.telecom { background: var(--brand); }
  .vps-quality-dot.unicom { background: var(--status-info); }
  .vps-quality-dot.mobile { background: var(--status-warn); }
  .vps-quality-value { min-width: 0; overflow-wrap: anywhere; }
  .vps-quality-multiple { grid-column: 2 / -1; min-width: 0; }
  .vps-resource-carrier { padding-top: 14px; }
  .vps-resource-carrier h4 { display: flex; justify-content: space-between; flex-wrap: wrap; gap: 10px; margin: 0; padding: 10px 0; border-bottom: 1px solid var(--border); font-size: var(--font-size-body); font-weight: 600; }
  .vps-resource-carrier h4 span { color: var(--text-secondary); font-size: var(--font-size-secondary); font-weight: 400; }
  .vps-resource-target + .vps-resource-target { margin-top: 12px; border-top: 1px solid var(--border); }
  .vps-resource-target-heading { display: flex; justify-content: space-between; gap: 12px; padding-top: 14px; }
  .vps-resource-target-heading strong { min-width: 0; overflow-wrap: anywhere; font-size: var(--font-size-body); font-weight: 500; }
  .vps-resource-target-heading .vps-resource-note { flex: none; margin: 0; }
}
@media (max-width: 520px) {
  .vps-resource-drawer .el-drawer__header, .vps-resource-drawer .el-drawer__footer { padding-inline: 16px; }
  .vps-resource-drawer .el-drawer__body { padding-inline: 16px; }
  .vps-resource-drawer .vps-resource-fields { column-gap: 16px; }
  .vps-resource-drawer .vps-resource-fields .vps-resource-private { flex-wrap: wrap; }
  .vps-resource-drawer .vps-quality-line { grid-template-columns: 76px minmax(0, 1fr) auto; gap: 8px; }
}
</style>
