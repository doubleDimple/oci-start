<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { NetworkQualityAgent, NetworkQualityResult, NetworkQualityTask, QualityOperator } from '@/api/networkQuality'

interface Entry { task: NetworkQualityTask; result: NetworkQualityResult | null }
const props = defineProps<{
  instanceId: string
  operator: QualityOperator
  agent: NetworkQualityAgent | null
  entries: Entry[]
  loaded: boolean
  loading: boolean
  stale: boolean
  serverTime: number | null
  ipVisible: boolean
  disabled: boolean
}>()
const emit = defineEmits<{ details: [] }>()
const { t, locale } = useI18n()
const entries = computed(() => props.entries
  .filter(entry => entry.task.operator === props.operator && entry.task.instanceIds.includes(props.instanceId))
  .map(entry => ({ task: entry.task, result: entry.result?.instanceId === props.instanceId
    && entry.result.taskId === entry.task.id && entry.result.revision === entry.task.version ? entry.result : null }))
  // A stable target keeps the displayed measurement from switching with every report.
  .sort((a, b) => Number(b.task.enabled) - Number(a.task.enabled)
    || a.task.id.length - b.task.id.length || a.task.id.localeCompare(b.task.id)))
const entry = computed(() => props.loaded ? entries.value[0] : undefined)
const result = computed(() => entry.value?.result ?? null)
const agent = computed(() => props.agent?.id === props.instanceId ? props.agent : null)
const historical = computed(() => !!result.value && (props.stale || !entry.value?.task.enabled
  || agent.value?.qualityStatus !== 'online' || props.serverTime === null
  || props.serverTime - result.value.updatedAt > ((entry.value?.task.intervalSeconds ?? 0) + 120) * 1000))
const loss = computed(() => {
  const value = result.value
  if (!value || !['success', 'partial', 'failed'].includes(value.status)
    || value.attempts === null || value.attempts <= 0 || value.successful === null) return null
  return (value.attempts - value.successful) / value.attempts * 100
})
function number(value: number) { return new Intl.NumberFormat(locale.value, { maximumFractionDigits: 1 }).format(value) }
const lossLabel = computed(() => t(entry.value?.task.type === 'icmp' ? 'networkQuality.packetLoss' : 'networkQuality.failureRate'))
const measurement = computed(() => result.value?.avgMs != null
  ? t('networkQuality.ms', { value: number(result.value.avgMs) })
  : '—')
const state = computed(() => {
  if (!props.loaded) return t(props.loading ? 'networkQuality.loading' : 'networkQuality.notLoaded')
  if (!entry.value) return ''
  if (!entry.value.task.enabled) return t('networkQuality.stopped')
  if (!agent.value) return t('networkQuality.missingInstance')
  if (agent.value.qualityStatus !== 'online') return t(`networkQuality.agents.${agent.value.qualityStatus}`)
  if (!result.value) return t('networkQuality.waiting')
  if (historical.value) return t('networkQuality.stale')
  if (result.value.status === 'error') return t('networkQuality.statuses.error')
  return ''
})
const targetLabel = computed(() => entry.value
  ? `${props.ipVisible ? entry.value.task.name : t('vps.carrierTarget')} · ${entry.value.task.type.toUpperCase()}` : '')
const description = computed(() => [
  t(`networkQuality.operators.${props.operator}`), targetLabel.value, measurement.value,
  loss.value === null ? '' : `${lossLabel.value} ${number(loss.value)}%`,
  result.value ? t(`networkQuality.statuses.${result.value.status}`) : '', state.value,
  historical.value ? t('networkQuality.stale') : '',
  entries.value.length > 1 ? t('vps.carrierMoreHint', { count: entries.value.length }) : '',
  t('networkQuality.details'),
].filter(Boolean).join(' · '))
function details() { if (!props.disabled) emit('details') }
</script>

<template>
  <button type="button" class="vps-carrier-summary" :disabled="disabled" :title="description" :aria-label="description" @click="details">
    <span class="vps-carrier-measurement">
      <strong :class="{ 'is-warning': historical || result?.status === 'partial', 'is-error': !historical && (result?.status === 'failed' || result?.status === 'error') }">{{ measurement }}</strong>
      <i v-if="historical" class="i-mdi-clock-outline" :aria-label="t('networkQuality.stale')" role="img" />
      <small v-if="loss !== null" class="vps-carrier-loss" :class="{ 'is-warning': loss > 0 }">{{ t(entry?.task.type === 'icmp' ? 'vps.carrierLoss' : 'vps.carrierFailure', { value: number(loss) }) }}</small>
    </span>
    <span v-if="result && (state || targetLabel)" class="vps-carrier-caption"><span>{{ state || targetLabel }}</span><small v-if="loaded && entries.length > 1" class="vps-carrier-more">+{{ entries.length - 1 }}</small></span>
  </button>
</template>

<style scoped lang="scss">
.vps-carrier-summary { display: grid; gap: 3px; width: 100%; min-width: 0; padding: 0; border: 0; border-radius: 3px; background: transparent; color: var(--text-primary); text-align: left; font: inherit; cursor: pointer; }
.vps-carrier-measurement, .vps-carrier-caption { display: flex; align-items: center; gap: 5px; min-width: 0; min-height: 20px; white-space: nowrap; }
.vps-carrier-measurement { font-variant-numeric: tabular-nums; }
.vps-carrier-measurement > strong { min-width: 0; overflow: hidden; text-overflow: ellipsis; font-weight: 500; }
.vps-carrier-measurement > i { flex: none; width: 13px; height: 13px; color: var(--status-warn); }
.vps-carrier-loss { flex: none; margin-left: auto; font-size: var(--font-size-secondary); }
.vps-carrier-caption { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.vps-carrier-caption > span { min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.vps-carrier-more { flex: none; margin-left: auto; font: inherit; }
.vps-carrier-summary:hover:not(:disabled) strong { text-decoration: underline; text-underline-offset: 4px; }
.vps-carrier-summary:disabled { cursor: default; }
.is-warning { color: var(--status-warn); }
.is-error { color: var(--status-danger); }
</style>
