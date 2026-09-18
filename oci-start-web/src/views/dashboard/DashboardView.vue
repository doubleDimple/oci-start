<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { init, use, type ECharts } from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, LegendPlainComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { fetchDashboardStats, fetchMonitorStats } from '@/api/dashboard'
import { theme } from '@/composables/useTheme'
import { chromeRevision } from '@/composables/useChrome'
import { readChartTheme } from '@/utils/chartTheme'

use([LineChart, GridComponent, LegendPlainComponent, TooltipComponent, CanvasRenderer])

const { t, locale } = useI18n()
const stats = ref<any>({})
const m = ref<any>({})
const lastUpdate = ref('')
const chartEl = ref<HTMLDivElement | null>(null)
let chart: ECharts | null = null
const netLabels: string[] = []
const netUp: number[] = []
const netDown: number[] = []
let statsTimer: number | null = null
let monitorTimer: number | null = null
let chartObserver: ResizeObserver | undefined

function formatSize(bytes: number) {
  if (!bytes) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${Number((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`
}

function formatSpeed(speed: number) {
  if (speed == null || Number.isNaN(Number(speed))) return '0 KB/s'
  const n = Number(speed)
  if (n < 1024) return `${n.toFixed(2)} KB/s`
  return `${(n / 1024).toFixed(2)} MB/s`
}

function formatUptime(seconds: number) {
  if (!seconds) return `0${t('dashboard.minuteUnit')}`
  const years = Math.floor(seconds / (86400 * 365))
  const days = Math.floor((seconds % (86400 * 365)) / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const result: string[] = []
  if (years > 0) result.push(`${years}${t('dashboard.yearUnit')}`)
  if (days > 0) result.push(`${days}${t('dashboard.dayUnit')}`)
  if (hours > 0) result.push(`${hours}${t('dashboard.hourUnit')}`)
  if (minutes > 0) result.push(`${minutes}${t('dashboard.minuteUnit')}`)
  return result.join(' ') || `0${t('dashboard.minuteUnit')}`
}

function gaugeColor(v: number) {
  if (v <= 60) return 'var(--status-ok)'
  if (v <= 80) return 'var(--status-warn)'
  return 'var(--status-danger)'
}

function gaugeStyle(v: number) {
  const value = Math.min(Math.max(0, v || 0), 100)
  const color = gaugeColor(value)
  return { background: `conic-gradient(${color} ${value * 3.6}deg, var(--bg-search) ${value * 3.6}deg)` }
}

const kpis = computed(() => [
  { key: 'api', label: t('dashboard.apiTotal'), value: stats.value.totalApiCalls ?? '-', icon: 'i-mdi-tune', tint: 'mint' },
  { key: 'boot', label: t('dashboard.bootInstances'), value: stats.value.totalBootInstances ?? '-', icon: 'i-mdi-server', tint: 'lavender' },
  { key: 'total', label: t('dashboard.attemptTotal'), value: stats.value.totalAttempts ?? '-', icon: 'i-mdi-sync', tint: 'blue' },
  { key: 'ok', label: t('dashboard.attemptSuccess'), value: stats.value.successfulAttempts ?? '-', icon: 'i-mdi-check-circle-outline', tint: 'mint' },
  { key: 'fail', label: t('dashboard.attemptFail'), value: stats.value.failCounts ?? 0, icon: 'i-mdi-close-circle-outline', tint: 'peach' },
])

const cpu = computed(() => Math.min(100, Math.round(m.value.cpuUsage || 0)))
const mem = computed(() => Math.round(m.value.memoryUsage || 0))
const disk = computed(() => Math.round(m.value.diskUsage || 0))
const uptimePct = computed(() => Math.min(((m.value.systemUptime || 0) / (315360000 / 2)) * 100, 100))
const uptimeDays = computed(() => Math.floor((m.value.systemUptime || 0) / 86400))

function pushNet(up: number, down: number) {
  const timeStr = new Date().toLocaleTimeString(locale.value, { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
  netLabels.push(timeStr)
  netUp.push(up)
  netDown.push(down)
  if (netLabels.length > 30) {
    netLabels.shift()
    netUp.shift()
    netDown.shift()
  }
  chart?.setOption({
    xAxis: { data: netLabels },
    series: [{ data: netUp }, { data: netDown }],
  })
}

function ink() {
  const palette = readChartTheme()
  return {
    text: palette.secondary,
    muted: palette.muted,
    surface: palette.surface,
    family: palette.fontFamily,
    split: palette.border,
  }
}

function chartFontSize() {
  return readChartTheme().secondarySize
}

function applyChartTheme() {
  if (!chart) return
  const c = ink()
  const fontSize = chartFontSize()
  chart.setOption({
    textStyle: { fontFamily: c.family, color: c.text },
    tooltip: { backgroundColor: c.surface, borderColor: c.split, textStyle: { fontFamily: c.family, color: c.text, fontSize } },
    legend: { textStyle: { color: c.text, fontSize } },
    xAxis: { axisLabel: { fontSize, color: c.muted } },
    yAxis: { axisLabel: { fontSize, color: c.text }, nameTextStyle: { color: c.muted, fontSize }, splitLine: { lineStyle: { type: 'dashed', color: c.split } } },
  })
}

function initChart() {
  if (!chartEl.value) return
  chart = init(chartEl.value)
  const c = ink()
  const fontSize = chartFontSize()
  chart.setOption({
    animation: false,
    textStyle: { fontFamily: c.family, color: c.text },
    grid: { left: 44, right: 12, top: 28, bottom: 24 },
    legend: { top: 0, textStyle: { color: c.text, fontSize } },
    tooltip: { trigger: 'axis', backgroundColor: c.surface, borderColor: c.split, textStyle: { fontFamily: c.family, color: c.text, fontSize } },
    xAxis: { type: 'category', data: [], boundaryGap: false, axisLabel: { fontSize, color: c.muted } },
    yAxis: { type: 'value', name: 'KB/s', axisLabel: { fontSize, color: c.text }, nameTextStyle: { color: c.muted, fontSize }, splitLine: { lineStyle: { type: 'dashed', color: c.split } } },
    series: [
      { name: t('dashboard.netUp'), type: 'line', smooth: true, showSymbol: false, lineStyle: { width: 2, color: '#0071e3' }, areaStyle: { color: 'rgba(0,113,227,0.08)' }, data: [] },
      { name: t('dashboard.netDown'), type: 'line', smooth: true, showSymbol: false, lineStyle: { width: 2, color: '#1b8a6a' }, areaStyle: { color: 'rgba(27,138,106,0.08)' }, data: [] },
    ],
  })
}

async function loadStats() {
  try {
    const res: any = await fetchDashboardStats()
    if (res?.success && res.data) stats.value = res.data
  } catch { /* silent like dashboard.js */ }
}

async function loadMonitor() {
  try {
    const res: any = await fetchMonitorStats()
    if (!(res?.success && res.data)) return
    const data = res.data
    m.value = data
    lastUpdate.value = data.timestamp || ''
    pushNet(Number(data.uploadSpeed || 0), Number(data.downloadSpeed || 0))
  } catch { /* silent */ }
}

function onResize() { chart?.resize() }

watch([theme, chromeRevision], applyChartTheme, { flush: 'post' })
watch(locale, () => {
  chart?.setOption({ series: [{ name: t('dashboard.netUp') }, { name: t('dashboard.netDown') }] })
  applyChartTheme()
})

onMounted(() => {
  initChart()
  if (chartEl.value && typeof ResizeObserver !== 'undefined') {
    chartObserver = new ResizeObserver(onResize)
    chartObserver.observe(chartEl.value)
  }
  loadStats()
  loadMonitor()
  statsTimer = window.setInterval(loadStats, 60000)
  monitorTimer = window.setInterval(loadMonitor, 20000)
  window.addEventListener('resize', onResize)
})
onUnmounted(() => {
  if (statsTimer) clearInterval(statsTimer)
  if (monitorTimer) clearInterval(monitorTimer)
  window.removeEventListener('resize', onResize)
  chartObserver?.disconnect()
  chart?.dispose()
})
</script>

<template>
  <div class="dash">
    <div class="kpis">
      <article v-for="k in kpis" :key="k.key" class="kpi">
        <small :title="k.label">{{ k.label }}</small>
        <b :class="{ fail: k.key === 'fail' }" :title="String(k.value)">{{ k.value }}</b>
        <div class="kpi-icon" :class="k.tint"><i :class="k.icon" aria-hidden="true" /></div>
      </article>
    </div>

    <div class="monitors">
      <article class="card cpu-card">
        <header>
          <div class="ico"><i class="i-mdi-cpu-64-bit" /></div>
          <div>
            <h3>{{ t('dashboard.cpuTitle') }}</h3>
            <small :title="m.cpuModel">{{ m.cpuModel || t('dashboard.loading') }}</small>
          </div>
        </header>
        <div class="gauge-wrap">
          <div class="gauge" :style="gaugeStyle(cpu)" />
          <span class="gval" :style="{ color: gaugeColor(cpu) }">{{ cpu }}%</span>
        </div>
        <dl>
          <div><dt>{{ t('dashboard.cpuPhysical') }}</dt><dd>{{ m.cpuPhysicalCount ?? '-' }} C</dd></div>
          <div><dt>{{ t('dashboard.cpuLogical') }}</dt><dd>{{ m.cpuLogicalCount ?? '-' }} C</dd></div>
          <div><dt>{{ t('dashboard.cpuTemp') }}</dt><dd>{{ m.cpuTemperature > 0 ? m.cpuTemperature.toFixed(1) + '°C' : 'N/A' }}</dd></div>
          <div><dt>{{ t('dashboard.cpuFreq') }}</dt><dd>{{ m.cpuFrequency ?? 0 }} GHz</dd></div>
        </dl>
      </article>

      <article class="card memory-card">
        <header>
          <div class="ico"><i class="i-mdi-memory" /></div>
          <div>
            <h3>{{ t('dashboard.memTitle') }}</h3>
            <small>{{ m.totalMemory ? (m.totalMemory / 1024).toFixed(1) + ' GB' : t('dashboard.loading') }}</small>
          </div>
        </header>
        <div class="gauge-wrap">
          <div class="gauge" :style="gaugeStyle(mem)" />
          <span class="gval" :style="{ color: gaugeColor(mem) }">{{ mem }}%</span>
        </div>
        <dl>
          <div><dt>{{ t('dashboard.memTotal') }}</dt><dd>{{ formatSize((m.totalMemory || 0) * 1024 * 1024) }}</dd></div>
          <div><dt>{{ t('dashboard.memUsed') }}</dt><dd>{{ formatSize((m.usedMemory || 0) * 1024 * 1024) }}</dd></div>
          <div><dt>{{ t('dashboard.memAvailable') }}</dt><dd>{{ formatSize((m.availableMemory || 0) * 1024 * 1024) }}</dd></div>
          <div><dt>{{ t('dashboard.memSwap') }}</dt><dd>{{ formatSize((m.swapUsed || 0) * 1024 * 1024) }} / {{ formatSize((m.swapTotal || 0) * 1024 * 1024) }}</dd></div>
        </dl>
      </article>

      <article class="card disk-card">
        <header>
          <div class="ico"><i class="i-mdi-harddisk" /></div>
          <div>
            <h3>{{ t('dashboard.diskTitle') }}</h3>
            <small>{{ t('dashboard.diskSubtitle') }}</small>
          </div>
        </header>
        <div class="gauge-wrap">
          <div class="gauge" :style="gaugeStyle(disk)" />
          <span class="gval" :style="{ color: gaugeColor(disk) }">{{ disk }}%</span>
        </div>
        <dl>
          <div><dt>{{ t('dashboard.diskTotal') }}</dt><dd>{{ formatSize(m.diskTotal || 0) }}</dd></div>
          <div><dt>{{ t('dashboard.diskUsed') }}</dt><dd>{{ formatSize(m.diskUsed || 0) }}</dd></div>
          <div><dt>{{ t('dashboard.diskFree') }}</dt><dd>{{ formatSize(m.diskFree || 0) }}</dd></div>
          <div><dt>{{ t('dashboard.diskIo') }}</dt><dd>-</dd></div>
        </dl>
      </article>

      <article class="card system-card">
        <header>
          <div class="ico"><i class="i-mdi-server" /></div>
          <div>
            <h3>{{ t('dashboard.sysTitle') }}</h3>
            <small :title="m.hostname">{{ m.hostname || t('dashboard.loading') }}</small>
          </div>
        </header>
        <div class="gauge-wrap">
          <div class="gauge" :style="gaugeStyle(uptimePct)" />
          <span class="gval">{{ uptimeDays }} {{ t('dashboard.dayUnit') }}</span>
        </div>
        <dl>
          <div><dt>{{ t('dashboard.sysOs') }}</dt><dd :title="m.osName || undefined">{{ m.osName || '-' }}</dd></div>
          <div><dt>{{ t('dashboard.sysArch') }}</dt><dd>{{ m.osArch || '-' }}</dd></div>
          <div><dt>{{ t('dashboard.sysUptime') }}</dt><dd :title="formatUptime(m.systemUptime)">{{ formatUptime(m.systemUptime) }}</dd></div>
          <div><dt>{{ t('dashboard.sysProcesses') }}</dt><dd>{{ m.totalProcesses ?? '-' }}</dd></div>
          <div><dt>{{ t('dashboard.sysThreads') }}</dt><dd>{{ m.threadCount ?? '-' }}</dd></div>
        </dl>
      </article>

      <article class="card net">
        <header>
          <div class="ico"><i class="i-mdi-chart-areaspline" /></div>
          <div>
            <h3>{{ t('dashboard.netTitle') }}</h3>
            <small>{{ t('dashboard.netSubtitle') }}</small>
          </div>
        </header>
        <div ref="chartEl" class="chart" />
        <dl>
          <div><dt>{{ t('dashboard.netUp') }}</dt><dd>{{ formatSpeed(m.uploadSpeed || 0) }}</dd></div>
          <div><dt>{{ t('dashboard.netDown') }}</dt><dd>{{ formatSpeed(m.downloadSpeed || 0) }}</dd></div>
          <div><dt>{{ t('dashboard.netTotalUp') }}</dt><dd>{{ formatSize(m.totalUploadBytes || 0) }}</dd></div>
          <div><dt>{{ t('dashboard.netTotalDown') }}</dt><dd>{{ formatSize(m.totalDownloadBytes || 0) }}</dd></div>
        </dl>
      </article>


    </div>
    <div class="updated">{{ lastUpdate || t('dashboard.loading') }}</div>
  </div>
</template>

<style scoped>
.dash { min-width: 0; container-type: inline-size; font: var(--font-size-body)/1.47 var(--sans); color: var(--text-primary); }
.updated { margin-top: 14px; color: var(--text-secondary); font-size: var(--font-size-secondary); text-align: right; }
.kpis { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; margin-bottom: 16px; }
.kpi {
  display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: 8px;
  min-width: 0; padding: 16px 18px; background: var(--bg-card); border-radius: var(--r-card); box-shadow: var(--shadow-card);
}
.kpi small { grid-column: 1 / -1; display: block; min-width: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; color: var(--text-primary); font-size: var(--font-size-body); }
.kpi b { min-width: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; font-size: 24px; font-weight: 600; letter-spacing: -.025em; font-variant-numeric: tabular-nums; }
.kpi b.fail { color: var(--status-danger); }
.kpi-icon { width: 34px; height: 34px; border-radius: 11px; display: grid; place-items: center; font-size: 18px; }
.kpi-icon.mint { background: var(--icon-mint); color: var(--brand); }
.kpi-icon.lavender { background: var(--icon-lavender); color: var(--brand); }
.kpi-icon.blue { background: var(--icon-blue); color: var(--status-info); }
.kpi-icon.peach { background: var(--icon-peach); color: var(--status-warn); }
.monitors { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; align-items: stretch; }
.card { display: flex; flex-direction: column; min-width: 0; background: var(--bg-card); border-radius: var(--r-card); box-shadow: var(--shadow-card); padding: 20px; }
.card.net { grid-column: span 2; }
.card header { display: flex; gap: 10px; align-items: center; min-width: 0; }
.card header > div:last-child { flex: 1; min-width: 0; }
.card header h3 { margin: 0; font-size: var(--font-size-section); font-weight: 600; line-height: 1.5; white-space: nowrap; }
.card header small { display: block; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; }
.ico { flex: none; width: 36px; height: 36px; border-radius: 11px; background: var(--icon-mint); color: var(--brand); display: grid; place-items: center; font-size: 18px; }
.gauge-wrap { position: relative; flex: none; width: 116px; height: 116px; margin: 20px auto; }
.gauge { width: 100%; height: 100%; border-radius: 50%; }
.gval { position: absolute; inset: 14px; border-radius: 50%; background: var(--bg-card); display: grid; place-items: center; font-size: var(--font-size-section); font-weight: 600; white-space: nowrap; font-variant-numeric: tabular-nums; }
.chart { flex: 1; min-width: 0; min-height: 230px; margin: 20px 0 8px; }
.card dl { display: grid; grid-template-columns: minmax(0, 1fr); gap: 0; margin: auto 0 0; }
.card dl > div { display: grid; grid-template-columns: max-content minmax(0, 1fr); align-items: baseline; gap: 16px; min-width: 0; min-height: 36px; padding: 8px 0; box-sizing: border-box; font-size: var(--font-size-body); }
.card dl > div + div { border-top: 1px solid color-mix(in srgb, var(--border) 38%, transparent); }
.card dt { color: var(--text-primary); white-space: nowrap; }
.card dd { min-width: 0; margin: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; text-align: right; font-weight: 500; font-variant-numeric: tabular-nums; }
.net dl { grid-template-columns: repeat(2, minmax(0, 1fr)); column-gap: 28px; }
.net dl > div:nth-child(2) { border-top: 0; }
@container (max-width: 980px) {
  .kpi { padding: 14px; }
  .kpi-icon { width: 28px; height: 28px; font-size: 16px; }
  .monitors { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .card.net { grid-column: 1 / -1; }
}
@container (max-width: 720px) {
  .kpis { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .card { padding: 18px; }
}
@container (max-width: 540px) {
  .kpis { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
  .kpi:last-child { grid-column: 1 / -1; grid-template-columns: minmax(0, 1fr) auto auto; }
  .kpi:last-child small { grid-column: auto; }
  .monitors { grid-template-columns: minmax(0, 1fr); gap: 12px; }
  .card.net { grid-column: auto; }
  .net dl { grid-template-columns: minmax(0, 1fr); }
  .net dl > div:nth-child(2) { border-top: 1px solid color-mix(in srgb, var(--border) 38%, transparent); }
  .chart { min-height: 220px; }
}
</style>
