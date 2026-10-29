<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { chromeRevision } from '@/composables/useChrome'
import { usePageMotion } from '@/composables/usePageMotion'
import { readChartTheme } from '@/utils/chartTheme'
import DashboardChart from './DashboardChart.vue'
import AnimatedNumber from './AnimatedNumber.vue'
import { finite, useDashboard, type MetricKey } from './useDashboard'
import { capacityOption, trendOption, type SeriesSpec } from './dashboardCharts'

const { t, locale } = useI18n()
const root = ref<HTMLElement | null>(null)
usePageMotion(root)
const { metrics, visibleSamples, readings, interval, windowMinutes, paused, loading, monitorError, updatedAt, summary, refresh } = useDashboard()
const m = computed(() => metrics.value ?? {})
const tr = (key: string, params: Record<string, string | number> = {}) => t(`dashboardMonitor.${key}`, params)
const palette = computed(() => { void chromeRevision.value; return readChartTheme() })
const number = (value: unknown, decimals = 1) => finite(value) === null ? '—' : Number(Number(value).toFixed(decimals)).toLocaleString(locale.value)
const percent = (value: unknown) => finite(value) === null ? '—' : `${number(Math.min(Number(value), 100))}%`
function size(value: unknown) {
  const bytes = finite(value)
  if (bytes === null) return '—'
  const power = bytes > 0 ? Math.min(4, Math.max(0, Math.floor(Math.log(bytes) / Math.log(1024)))) : 0
  return `${number(bytes / 1024 ** power, 1)} ${['B', 'KiB', 'MiB', 'GiB', 'TiB'][power]}`
}
const memorySize = (value: unknown) => finite(value) === null ? '—' : size(Number(value) * 1024 ** 2)
const speed = (value: unknown) => finite(value) === null ? '—' : Number(value) >= 1024 ? `${number(Number(value) / 1024)} MiB/s` : `${number(value)} KiB/s`
const time = (value: number) => new Date(value).toLocaleTimeString(locale.value, { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
const uptime = computed(() => {
  const seconds = finite(m.value.systemUptime)
  if (seconds === null) return '—'
  const days = Math.floor(seconds / 86400), hours = Math.floor(seconds % 86400 / 3600), minutes = Math.floor(seconds % 3600 / 60)
  return [days ? `${days}${tr('day')}` : '', `${hours}${tr('hour')}`, `${minutes}${tr('minute')}`].filter(Boolean).join(' ')
})
const liveState = computed(() => monitorError.value ? 'unavailable' : paused.value ? 'paused' : metrics.value ? 'live' : 'connecting')
const selectedMetrics = ref<MetricKey[]>(['cpu', 'memory', 'disk'])
const resourceSeries = computed<SeriesSpec[]>(() => [
  { key: 'cpu', name: 'CPU', color: palette.value.brand },
  { key: 'memory', name: tr('memoryLabel'), color: palette.value.info },
  { key: 'disk', name: tr('diskLabel'), color: palette.value.tertiary },
])
const networkSeries = computed<SeriesSpec[]>(() => [
  { key: 'upload', name: tr('upload'), color: palette.value.brand },
  { key: 'download', name: tr('download'), color: palette.value.info },
])
function toggleMetric(key: MetricKey) {
  if (selectedMetrics.value.includes(key)) {
    if (selectedMetrics.value.length > 1) selectedMetrics.value = selectedMetrics.value.filter(item => item !== key)
  } else selectedMetrics.value = [...selectedMetrics.value, key]
}
const resources = computed(() => trendOption(visibleSamples.value, resourceSeries.value.filter(item => selectedMetrics.value.includes(item.key)), palette.value, locale.value))
const network = computed(() => trendOption(visibleSamples.value, networkSeries.value, palette.value, locale.value, 'KiB/s'))
const activity = computed(() => trendOption(visibleSamples.value, [
  { key: 'processes', name: tr('processes'), color: palette.value.info },
  { key: 'threads', name: tr('threads'), color: palette.value.tertiary },
], palette.value, locale.value, '', true))
const metricCards = computed(() => {
  const up = finite(m.value.uploadSpeed), down = finite(m.value.downloadSpeed)
  const rate = up === null || down === null ? null : up + down
  return [
    { key: 'cpu', title: tr('cpu'), icon: 'i-mdi-chip', value: finite(m.value.cpuUsage), color: palette.value.brand, unit: '%', detail: tr('cores', { count: number(m.value.cpuLogicalCount, 0) }), extra: `${tr('peak')} ${percent(summary('cpu').peak)}`, series: [resourceSeries.value[0]!] },
    { key: 'memory', title: tr('memory'), icon: 'i-mdi-memory', value: finite(m.value.memoryUsage), color: palette.value.info, unit: '%', detail: tr('usedOf', { used: memorySize(m.value.usedMemory), total: memorySize(m.value.totalMemory) }), extra: `${tr('available')} ${memorySize(m.value.availableMemory)}`, series: [resourceSeries.value[1]!] },
    { key: 'disk', title: tr('disk'), icon: 'i-mdi-harddisk', value: finite(m.value.diskUsage), color: palette.value.tertiary, unit: '%', detail: tr('usedOf', { used: size(m.value.diskUsed), total: size(m.value.diskTotal) }), extra: `${tr('available')} ${size(m.value.diskFree)}`, series: [resourceSeries.value[2]!] },
    { key: 'network', title: tr('network'), icon: 'i-mdi-swap-vertical', value: rate === null ? null : rate >= 1024 ? rate / 1024 : rate, color: palette.value.info, unit: rate !== null && rate >= 1024 ? 'MiB/s' : 'KiB/s', detail: `↑ ${speed(up)}`, extra: `↓ ${speed(down)}`, series: networkSeries.value },
  ].map(card => ({ ...card, status: card.value === null ? 'noData' : card.key === 'network' ? '' : card.value >= 85 ? 'critical' : card.value >= 65 ? 'busy' : 'normal', chart: trendOption(visibleSamples.value, card.series, palette.value, locale.value, card.key === 'network' ? 'KiB/s' : '%', true) }))
})
const capacities = computed(() => [
  { key: 'memory', label: tr('memoryLabel'), value: finite(m.value.memoryUsage), used: finite(m.value.usedMemory), total: finite(m.value.totalMemory), free: memorySize(m.value.availableMemory), usedLabel: memorySize(m.value.usedMemory), totalLabel: memorySize(m.value.totalMemory), color: palette.value.info },
  { key: 'disk', label: tr('diskLabel'), value: finite(m.value.diskUsage), used: finite(m.value.diskUsed), total: finite(m.value.diskTotal), free: size(m.value.diskFree), usedLabel: size(m.value.diskUsed), totalLabel: size(m.value.diskTotal), color: palette.value.tertiary },
].map(item => ({ ...item, chart: capacityOption(item.used, item.total, [tr('used'), tr('available')], item.color, palette.value) })))
const resourceSummary = computed(() => [
  { label: tr('averageCpu'), value: percent(summary('cpu').average), color: palette.value.brand },
  { label: tr('peakMemory'), value: percent(summary('memory').peak), color: palette.value.info },
  { label: tr('peakDisk'), value: percent(summary('disk').peak), color: palette.value.tertiary },
])
const networkSummary = computed(() => [
  { label: tr('averageDown'), value: speed(summary('download').average) },
  { label: tr('peakUp'), value: speed(summary('upload').peak) },
  { label: tr('peakDown'), value: speed(summary('download').peak) },
])
const chartLabel = (name: string) => tr('chartDescription', { name, count: readings.value.length })
</script>

<template>
  <div ref="root" class="dash monitor-dashboard">
    <div class="monitor-toolbar" data-motion-enter>
      <div class="monitor-host"><span class="monitor-state" :class="liveState"><span class="live-dot" />{{ tr(liveState) }}</span><span class="host-name" :title="m.hostname">{{ m.hostname || '—' }}</span></div>
      <div class="monitor-controls">
        <div class="time-window" role="group" :aria-label="tr('timeWindow')"><button v-for="minutes in [5, 15, 60]" :key="minutes" type="button" :aria-pressed="windowMinutes === minutes" @click="windowMinutes = minutes">{{ tr('minutes', { count: minutes }) }}</button></div>
        <label class="sample-interval"><i class="i-mdi-timer-outline" aria-hidden="true" /><select v-model.number="interval" :aria-label="tr('interval')"><option v-for="seconds in [5, 10, 30]" :key="seconds" :value="seconds">{{ tr('everySeconds', { seconds }) }}</option></select></label>
        <button type="button" class="monitor-icon-button" :class="{ selected: paused }" :title="tr(paused ? 'resume' : 'pause')" :aria-label="tr(paused ? 'resume' : 'pause')" :aria-pressed="paused" @click="paused = !paused"><i :class="paused ? 'i-mdi-play-outline' : 'i-mdi-pause'" aria-hidden="true" /></button>
        <button type="button" class="monitor-icon-button" :disabled="loading" :title="tr('refresh')" :aria-label="tr('refresh')" :aria-busy="loading" @click="refresh"><i class="i-mdi-refresh" :class="{ refreshing: loading }" aria-hidden="true" /></button>
      </div>
    </div>
    <div v-if="monitorError" class="monitor-notice" role="status"><i class="i-mdi-alert-circle-outline" aria-hidden="true" /><span>{{ tr(metrics ? 'monitorFailed' : 'monitorEmpty') }}</span><button type="button" :disabled="loading" @click="refresh">{{ tr('retry') }}</button></div>

    <div class="metric-grid">
      <article v-for="card in metricCards" :key="card.key" class="metric-card" :data-metric="card.key" data-motion-enter>
        <div class="metric-heading"><span><i :class="card.icon" aria-hidden="true" />{{ card.title }}</span><span v-if="card.status" class="metric-status" :class="card.status">{{ tr(card.status) }}</span></div>
        <div class="metric-value"><AnimatedNumber :value="card.value" :format="value => number(value)" /><small>{{ card.unit }}</small></div>
        <div class="metric-sparkline"><DashboardChart :option="card.chart" :label="chartLabel(card.title)" /></div>
        <div class="metric-details"><span>{{ card.detail }}</span><span>{{ card.extra }}</span></div>
      </article>
    </div>

    <div class="monitor-grid">
      <section class="monitor-panel resource-panel" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr('resourceTrend') }}</h2><div class="series-switches" role="group" :aria-label="tr('resourceTrend')"><button v-for="series in resourceSeries" :key="series.key" type="button" :aria-pressed="selectedMetrics.includes(series.key)" @click="toggleMetric(series.key)"><span class="legend-dot" :style="{ background: series.color }" />{{ series.name }}</button></div></header>
        <div class="main-chart"><DashboardChart :option="resources" :label="chartLabel(tr('resourceTrend'))" /><span v-if="readings.length < 2" class="chart-collecting">{{ tr('collecting') }}</span></div>
        <div class="chart-summary"><div v-for="item in resourceSummary" :key="item.label"><span>{{ item.label }}</span><strong :style="{ color: item.color }">{{ item.value }}</strong></div></div>
      </section>

      <section class="monitor-panel capacity-panel" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr('capacity') }}</h2><i class="i-mdi-chart-donut" aria-hidden="true" /></header>
        <div class="capacity-grid"><div v-for="item in capacities" :key="item.key" class="capacity-item"><div class="capacity-ring"><DashboardChart :option="item.chart" :label="tr('capacityDescription', { name: item.label, used: item.usedLabel, free: item.free })" /><div class="ring-label"><strong>{{ percent(item.value) }}</strong><span>{{ item.label }}</span></div></div><strong class="capacity-total">{{ item.totalLabel }}</strong><span class="capacity-free"><span class="legend-dot" :style="{ background: item.color }" />{{ tr('used') }} {{ item.usedLabel }}</span><span class="capacity-free">{{ tr('available') }} {{ item.free }}</span></div></div>
        <div class="swap-summary"><span><i class="i-mdi-swap-horizontal" aria-hidden="true" />{{ tr('swap') }}</span><strong>{{ m.swapTotal === 0 ? tr('noSwap') : `${memorySize(m.swapUsed)} / ${memorySize(m.swapTotal)}` }}</strong></div>
      </section>

      <section class="monitor-panel network-panel" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr('networkTrend') }}</h2><div class="chart-legend"><span v-for="series in networkSeries" :key="series.key"><i class="legend-dot" :style="{ background: series.color }" />{{ series.name }}</span></div></header>
        <div class="network-totals"><div><span>{{ tr('totalUp') }}</span><strong>{{ size(m.totalUploadBytes) }}</strong></div><div><span>{{ tr('totalDown') }}</span><strong>{{ size(m.totalDownloadBytes) }}</strong></div><span class="chart-unit">KiB/s</span></div>
        <div class="network-chart"><DashboardChart :option="network" :label="chartLabel(tr('networkTrend'))" /><span v-if="readings.length < 2" class="chart-collecting">{{ tr('collecting') }}</span></div>
        <div class="chart-summary"><div v-for="item in networkSummary" :key="item.label"><span>{{ item.label }}</span><strong>{{ item.value }}</strong></div></div>
      </section>

      <section class="monitor-panel host-panel" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr('system') }}</h2><i class="i-mdi-server-outline" aria-hidden="true" /></header>
        <div class="host-uptime"><i class="i-mdi-clock-outline" aria-hidden="true" /><div><span>{{ tr('uptime') }}</span><strong>{{ uptime }}</strong></div></div>
        <dl class="host-facts"><div><dt>{{ tr('operatingSystem') }}</dt><dd :title="m.osName">{{ m.osName || '—' }}</dd></div><div><dt>{{ tr('architecture') }}</dt><dd>{{ m.osArch || '—' }}</dd></div><div><dt>{{ tr('cpuModel') }}</dt><dd :title="m.cpuModel">{{ m.cpuModel || '—' }}</dd></div><div><dt>{{ tr('physical') }} / {{ tr('logical') }}</dt><dd>{{ number(m.cpuPhysicalCount, 0) }} / {{ number(m.cpuLogicalCount, 0) }}</dd></div><div><dt>{{ tr('frequency') }} / {{ tr('temperature') }}</dt><dd>{{ finite(m.cpuFrequency) ? `${number(m.cpuFrequency, 2)} GHz` : '—' }} / {{ finite(m.cpuTemperature) ? `${number(m.cpuTemperature)} °C` : '—' }}</dd></div></dl>
        <div class="process-totals"><span><i class="legend-dot" :style="{ background: palette.info }" />{{ tr('processes') }} <b>{{ number(m.totalProcesses, 0) }}</b></span><span><i class="legend-dot" :style="{ background: palette.tertiary }" />{{ tr('threads') }} <b>{{ number(m.threadCount, 0) }}</b></span></div>
        <div class="activity-chart"><DashboardChart :option="activity" :label="chartLabel(`${tr('processes')} / ${tr('threads')}`)" /></div>
      </section>


    </div>
    <footer class="monitor-footer"><span>{{ tr('samples', { count: readings.length }) }}<span class="sampling-note"> · {{ tr('observation') }}</span></span><time v-if="updatedAt" :datetime="new Date(updatedAt).toISOString()">{{ tr('updated', { time: time(updatedAt) }) }}</time></footer>
  </div>
</template>

<style src="./dashboard.scss" lang="scss" scoped />
