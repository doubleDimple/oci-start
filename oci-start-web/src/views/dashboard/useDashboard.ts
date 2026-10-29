import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { fetchMonitorStats, type SystemMetrics } from '@/api/dashboard'

export type MetricKey = 'cpu' | 'memory' | 'disk' | 'upload' | 'download' | 'processes' | 'threads'
export interface MonitorSample extends Record<MetricKey, number | null> { at: number }

export function finite(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
}
const percent = (value: unknown) => {
  const n = finite(value)
  return n === null ? null : Math.min(n, 100)
}

export function useDashboard() {
  const metrics = ref<SystemMetrics | null>(null)
  const samples = ref<MonitorSample[]>([])
  const interval = ref(10)
  const windowMinutes = ref(15)
  const paused = ref(false)
  const loading = ref(false)
  const monitorError = ref(false)
  const updatedAt = ref<number | null>(null)
  let mounted = false
  let monitorTimer: number | undefined
  let monitorRequest: AbortController | undefined
  let needsGap = false

  const visibleSamples = computed(() => {
    const latest = samples.value.at(-1)?.at ?? Date.now()
    return samples.value.filter(sample => sample.at >= latest - windowMinutes.value * 60000)
  })
  const readings = computed(() => visibleSamples.value.filter(sample => [sample.cpu, sample.memory, sample.disk, sample.upload, sample.download, sample.processes, sample.threads].some(value => value !== null)))
  const summary = (key: MetricKey) => {
    const values = visibleSamples.value.map(sample => sample[key]).filter((value): value is number => value !== null)
    return { average: values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null, peak: values.length ? Math.max(...values) : null, min: values.length ? Math.min(...values) : null }
  }

  function append(data: SystemMetrics) {
    const at = Date.now()
    const previous = samples.value.at(-1)
    if (previous && (needsGap || at - previous.at > interval.value * 2500)) {
      samples.value.push({ at: previous.at + 1, cpu: null, memory: null, disk: null, upload: null, download: null, processes: null, threads: null })
    }
    needsGap = false
    samples.value.push({ at, cpu: percent(data.cpuUsage), memory: percent(data.memoryUsage), disk: percent(data.diskUsage), upload: finite(data.uploadSpeed), download: finite(data.downloadSpeed), processes: finite(data.totalProcesses), threads: finite(data.threadCount) })
    // At most one hour of actual observations; no fabricated history.
    samples.value = samples.value.filter(sample => sample.at >= at - 3600000).slice(-1500)
    updatedAt.value = at
  }

  async function refreshMonitor() {
    if (!mounted || monitorRequest) return
    const controller = new AbortController()
    monitorRequest = controller
    loading.value = true
    try {
      const response = await fetchMonitorStats(controller.signal)
      if (controller.signal.aborted || !mounted) return
      if (!response?.success || !response.data || typeof response.data !== 'object') throw new Error('No metrics')
      const data = response.data
      if (![data.cpuUsage, data.memoryUsage, data.diskUsage, data.uploadSpeed, data.downloadSpeed].some(value => finite(value) !== null)) throw new Error('Empty metrics')
      metrics.value = data
      monitorError.value = false
      append(data)
    } catch {
      if (!controller.signal.aborted && mounted) {
        monitorError.value = true
        needsGap = true
      }
    } finally {
      if (monitorRequest === controller) monitorRequest = undefined
      if (mounted) loading.value = false
    }
  }

  function schedule() {
    window.clearInterval(monitorTimer)
    if (!mounted || paused.value || document.hidden) return
    monitorTimer = window.setInterval(refreshMonitor, interval.value * 1000)
  }

  async function refresh() { await refreshMonitor() }
  function visibilityChanged() {
    if (document.hidden) needsGap = true
    else if (!paused.value) void refresh()
    schedule()
  }
  watch([interval, paused], ([, isPaused], [, wasPaused]) => {
    if (isPaused) {
      needsGap = true
      monitorRequest?.abort()
    }
    else if (wasPaused && !document.hidden) void refresh()
    schedule()
  })
  onMounted(() => {
    mounted = true
    void refresh()
    schedule()
    document.addEventListener('visibilitychange', visibilityChanged)
  })
  onBeforeUnmount(() => {
    mounted = false
    window.clearInterval(monitorTimer)
    monitorRequest?.abort()
    document.removeEventListener('visibilitychange', visibilityChanged)
  })

  return { metrics, samples, visibleSamples, readings, interval, windowMinutes, paused, loading, monitorError, updatedAt, summary, refresh }
}
