<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import * as echarts from 'echarts'
import { fetchDashboardStats, fetchMonitorStats } from '@/api/dashboard'
import { theme } from '@/composables/useTheme'

const { t } = useI18n()
const stats = ref<any>({})
const m = ref<any>({})
const lastUpdate = ref('')
const chartEl = ref<HTMLDivElement | null>(null)
let chart: echarts.ECharts | null = null
const netLabels: string[] = []
const netUp: number[] = []
const netDown: number[] = []
let statsTimer: number | null = null
let monitorTimer: number | null = null

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
  if (!seconds) return '0min'
  const years = Math.floor(seconds / (86400 * 365))
  const days = Math.floor((seconds % (86400 * 365)) / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const result: string[] = []
  if (years > 0) result.push(`${years}year`)
  if (days > 0) result.push(`${days}day`)
  if (hours > 0) result.push(`${hours}hour`)
  if (minutes > 0) result.push(`${minutes}min`)
  return result.join(' ') || '0min'
}

function gaugeColor(v: number) {
  if (v <= 60) return 'var(--status-ok)'
  if (v <= 80) return 'var(--status-warn)'
  return 'var(--status-danger)'
}

function gaugeStyle(v: number) {
  const value = Math.min(Math.max(0, v || 0), 100)
  const color = value <= 60 ? '#1b8a6a' : value <= 80 ? '#ffb11d' : '#e24b4a'
  return { background: `conic-gradient(${color} ${value * 3.6}deg, #edf0f5 ${value * 3.6}deg)` }
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
  const timeStr = new Date().toLocaleTimeString('zh-CN', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
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
  const s = getComputedStyle(document.documentElement)
  return {
    text: s.getPropertyValue('--text-secondary').trim() || '#6e6e73',
    muted: s.getPropertyValue('--text-muted').trim() || '#86868b',
    split: s.getPropertyValue('--border').trim() || '#d2d2d7',
  }
}

function applyChartTheme() {
  if (!chart) return
  const c = ink()
  chart.setOption({
    legend: { textStyle: { color: c.text, fontSize: 12 } },
    xAxis: { axisLabel: { fontSize: 10, color: c.muted } },
    yAxis: { nameTextStyle: { color: c.muted }, splitLine: { lineStyle: { type: 'dashed', color: c.split } } },
  })
}

function initChart() {
  if (!chartEl.value) return
  chart = echarts.init(chartEl.value)
  const c = ink()
  chart.setOption({
    animation: false,
    grid: { left: 44, right: 12, top: 28, bottom: 24 },
    legend: { top: 0, textStyle: { color: c.text, fontSize: 12 } },
    tooltip: { trigger: 'axis' },
    xAxis: { type: 'category', data: [], boundaryGap: false, axisLabel: { fontSize: 10, color: c.muted } },
    yAxis: { type: 'value', name: 'KB/s', nameTextStyle: { color: c.muted }, splitLine: { lineStyle: { type: 'dashed', color: c.split } } },
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

watch(theme, () => applyChartTheme())

onMounted(() => {
  initChart()
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
  chart?.dispose()
})
</script>

<template>
  <div class="dash">
    <div class="kpis">
      <article v-for="k in kpis" :key="k.key" class="kpi">
        <div class="kpi-icon" :class="k.tint"><i :class="k.icon" /></div>
        <div>
          <small>{{ k.label }}</small>
          <b :class="{ fail: k.key === 'fail' }">{{ k.value }}</b>
        </div>
      </article>
    </div>

    <div class="monitors">
      <article class="card">
        <header>
          <div class="ico"><i class="i-mdi-cpu-64-bit" /></div>
          <div>
            <h3>{{ t('dashboard.cpuTitle') }}</h3>
            <small>{{ m.cpuModel || t('dashboard.loading') }}</small>
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

      <article class="card">
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
          <div><dt>{{ t('dashboard.memSwap') }}</dt><dd>{{ (m.swapUsed || 0) }}MB / {{ (m.swapTotal || 0) }}MB</dd></div>
        </dl>
      </article>

      <article class="card">
        <header>
          <div class="ico"><i class="i-mdi-server" /></div>
          <div>
            <h3>{{ t('dashboard.sysTitle') }}</h3>
            <small>{{ m.hostname || t('dashboard.loading') }}</small>
          </div>
        </header>
        <div class="gauge-wrap">
          <div class="gauge" :style="gaugeStyle(uptimePct)" />
          <span class="gval">{{ uptimeDays }}天</span>
        </div>
        <dl>
          <div><dt>{{ t('dashboard.sysOs') }}</dt><dd>{{ m.osName || '-' }}</dd></div>
          <div><dt>{{ t('dashboard.sysArch') }}</dt><dd>{{ m.osArch || '-' }}</dd></div>
          <div><dt>{{ t('dashboard.sysUptime') }}</dt><dd>{{ formatUptime(m.systemUptime) }}</dd></div>
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

      <article class="card">
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
    </div>
    <div class="updated">{{ lastUpdate || t('dashboard.loading') }}</div>
  </div>
</template>

<style scoped>
.updated { margin-top: 12px; color: var(--text-secondary); font-size: 12px; text-align: right; }
.kpis { display: grid; grid-template-columns: repeat(5, 1fr); gap: 12px; margin-bottom: 16px; }
.kpi {
  background: var(--bg-card); border-radius: var(--r-card); box-shadow: var(--shadow-card);
  padding: 16px; display: flex; gap: 12px; align-items: center;
}
.kpi small { display: block; color: var(--text-secondary); font-size: 12px; }
.kpi b { font-size: 24px; letter-spacing: -0.03em; }
.kpi b.fail { color: var(--status-danger); }
.kpi-icon { width: 42px; height: 42px; border-radius: 14px; display: grid; place-items: center; font-size: 20px; }
.kpi-icon.mint { background: var(--icon-mint); color: var(--brand); }
.kpi-icon.lavender { background: var(--icon-lavender); color: #5b4db3; }
.kpi-icon.blue { background: var(--icon-blue); color: var(--status-info); }
.kpi-icon.peach { background: var(--icon-peach); color: #d97706; }
.monitors { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
.card { background: var(--bg-card); border-radius: var(--r-card); box-shadow: var(--shadow-card); padding: 18px; }
.card.net { grid-column: span 2; }
header { display: flex; gap: 10px; align-items: center; margin-bottom: 8px; }
header h3 { margin: 0; font-size: 15px; }
header small { color: var(--text-secondary); }
.ico { width: 36px; height: 36px; border-radius: 12px; background: var(--icon-mint); color: var(--brand); display: grid; place-items: center; }
.gauge-wrap { position: relative; width: 140px; height: 140px; margin: 12px auto; }
.gauge { width: 100%; height: 100%; border-radius: 50%; }
.gval { position: absolute; inset: 22px; border-radius: 50%; background: var(--bg-card); display: grid; place-items: center; font-weight: 700; }
.chart { height: 180px; }
dl { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 12px; margin: 12px 0 0; }
dl div { display: flex; justify-content: space-between; gap: 8px; font-size: 12px; }
dt { color: var(--text-secondary); }
dd { margin: 0; font-weight: 600; }
@media (max-width: 1100px) {
  .kpis, .monitors { grid-template-columns: 1fr 1fr; }
  .card.net { grid-column: auto; }
}
</style>
