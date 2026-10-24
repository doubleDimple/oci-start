<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { NetworkQualityAgent, NetworkQualityResult, NetworkQualityTask, QualityOperator } from '@/api/networkQuality'

interface Entry { task: NetworkQualityTask; result: NetworkQualityResult | null }
const props = defineProps<{
  agent: NetworkQualityAgent | null
  entries: Entry[]
  loaded: boolean
  loading: boolean
  stale: boolean
  serverTime: number | null
  disabled: boolean
}>()
const emit = defineEmits<{ details: [] }>()
const { t, locale } = useI18n()
const carriers = computed(() => {
  const operators: QualityOperator[] = ['telecom', 'unicom', 'mobile']
  if (props.entries.some(entry => entry.task.operator === 'custom')) operators.push('custom')
  return operators.map(operator => ({ operator, entries: props.entries.filter(entry => entry.task.operator === operator) }))
})
const caption = computed(() => {
  if (!props.loaded) return t(props.loading ? 'networkQuality.loading' : 'networkQuality.notLoaded')
  if (!props.agent) return t('networkQuality.missingInstance')
  if (props.agent.qualityStatus !== 'online') return t(`networkQuality.agents.${props.agent.qualityStatus}`)
  if (props.stale) return t('networkQuality.stale')
  return ''
})
function old(entry: Entry | undefined) {
  if (!entry) return false
  return props.stale || !entry.task.enabled || props.agent?.qualityStatus !== 'online'
    || (entry.result !== null && props.serverTime !== null
      && props.serverTime - entry.result.updatedAt > (entry.task.intervalSeconds + 120) * 1000)
}
function value(entry: Entry | undefined) {
  if (!entry) return '—'
  if (!entry.result) return t(entry.task.enabled ? 'networkQuality.waiting' : 'networkQuality.stopped')
  const result = entry.result
  if (result.avgMs === null) return t(`networkQuality.statuses.${result.status}`)
  const latency = t('networkQuality.ms', { value: new Intl.NumberFormat(locale.value, { maximumFractionDigits: 2 }).format(result.avgMs) })
  return result.status === 'success' ? latency : `${latency} · ${t(`networkQuality.statuses.${result.status}`)}`
}
function detail(entry: Entry | undefined) {
  if (!entry) return t('networkQuality.noTargets')
  return [entry.task.name, value(entry), entry.task.type.toUpperCase(),
    old(entry) && entry.result ? t('networkQuality.stale') : '', !entry.task.enabled ? t('networkQuality.stopped') : ''].filter(Boolean).join(' · ')
}
function details() { if (!props.disabled) emit('details') }
</script>

<template>
  <div class="vps-quality" :title="stale ? t('networkQuality.snapshotStale') : undefined">
    <small v-if="caption" class="vps-quality-caption">{{ caption }}</small>
    <template v-if="loaded && agent">
      <div v-for="carrier in carriers" :key="carrier.operator" class="vps-quality-line">
        <span class="vps-quality-carrier"><i class="vps-quality-dot" :class="carrier.operator" aria-hidden="true" />{{ t(`networkQuality.operators.${carrier.operator}`) }}</span>
        <button v-if="carrier.entries.length > 1" type="button" class="vps-quality-multiple" :disabled="disabled" :title="t('networkQuality.details')" @click="details">{{ t('networkQuality.multipleTargets', { count: carrier.entries.length }) }}<i class="i-mdi-chevron-right" aria-hidden="true" /></button>
        <template v-else>
          <span class="vps-truncate vps-quality-value" :title="detail(carrier.entries[0])">{{ value(carrier.entries[0]) }}<span v-if="carrier.entries[0]?.result && old(carrier.entries[0])" class="vps-quality-old"> · {{ t('networkQuality.stale') }}</span></span>
          <small class="vps-quality-protocol">{{ carrier.entries[0]?.task.type.toUpperCase() ?? '' }}</small>
        </template>
      </div>
    </template>
    <span v-else>—</span>
  </div>
</template>
