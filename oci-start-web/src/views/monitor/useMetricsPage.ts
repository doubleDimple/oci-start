import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router'
import {
  deleteMetricServer,
  fetchMetrics,
  isMetricServerId,
  metricsError,
  type MetricServer,
  type MetricsApiError,
} from '@/api/metrics'

export type MetricDeleteResult = 'idle' | 'success' | 'unknown' | 'failed'

const REFRESH_INTERVAL = 5_000

/** Latest probe snapshots. A successful delete does not stop future probe reports. */
export function useMetricsPage() {
  const rows = ref<MetricServer[]>([])
  const loading = ref(false)
  const loaded = ref(false)
  const readProblem = shallowRef<MetricsApiError | null>(null)
  const lastUpdated = ref<Date | null>(null)
  const autoRefresh = ref(true)
  const pageHidden = ref(typeof document !== 'undefined' && document.hidden)

  const deleteTarget = shallowRef<MetricServer | null>(null)
  const deletePending = ref(false)
  const deleteProblem = shallowRef<MetricsApiError | null>(null)
  const deleteResult = ref<MetricDeleteResult>('idle')
  const canDismissModal = computed(() => !deletePending.value)
  const autoRefreshPaused = computed(() => autoRefresh.value && (pageHidden.value || !!deleteTarget.value))

  let mounted = false
  let disposed = false
  let sequence = 0
  let controller: AbortController | undefined
  let timer: ReturnType<typeof setTimeout> | undefined

  function clearTimer(): void {
    if (timer !== undefined) clearTimeout(timer)
    timer = undefined
  }

  function cancelRead(): void {
    ++sequence
    controller?.abort()
    controller = undefined
    loading.value = false
  }

  function scheduleRefresh(): void {
    clearTimer()
    if (!mounted || disposed || !autoRefresh.value || pageHidden.value || deleteTarget.value || loading.value) return
    // Schedule from completion instead of overlapping slow requests every 5 s.
    timer = setTimeout(() => {
      timer = undefined
      void refresh()
    }, REFRESH_INTERVAL)
  }

  async function refresh(): Promise<void> {
    if (!mounted || disposed || deletePending.value || loading.value) return
    clearTimer()
    const current = ++sequence
    const active = new AbortController()
    controller = active
    loading.value = true
    readProblem.value = null
    const isCurrent = () => !disposed && current === sequence
      && controller === active && !active.signal.aborted
    try {
      const result = await fetchMetrics(active.signal)
      if (!isCurrent()) return
      rows.value = result
      loaded.value = true
      lastUpdated.value = new Date()
    } catch (cause) {
      // Keep the previous snapshot and its timestamp when a refresh fails.
      if (isCurrent()) readProblem.value = metricsError(cause)
    } finally {
      if (isCurrent()) {
        controller = undefined
        loading.value = false
        scheduleRefresh()
      }
    }
  }

  function openDelete(row: MetricServer): void {
    if (disposed || deletePending.value || deleteTarget.value) return
    if (!isMetricServerId(row.serverId)) return
    clearTimer()
    cancelRead()
    // Preserve the selected record independently from later read-back snapshots.
    deleteTarget.value = { ...row }
    deleteProblem.value = null
    deleteResult.value = 'idle'
  }

  function closeDelete(): void {
    if (deletePending.value || !deleteTarget.value) return
    deleteTarget.value = null
    deleteProblem.value = null
    deleteResult.value = 'idle'
    if (autoRefresh.value && !pageHidden.value) void refresh()
  }

  async function confirmDelete(): Promise<void> {
    const target = deleteTarget.value
    if (disposed || !target || deletePending.value || deleteResult.value !== 'idle') return
    // Preserve the opaque identifier exactly; do not trim or coerce it to a number.
    const serverId = target.serverId
    if (!isMetricServerId(serverId)) return
    deletePending.value = true
    deleteProblem.value = null
    clearTimer()
    cancelRead()
    try {
      // This legacy endpoint mutates data even though it uses GET. Never abort or
      // retry it: a lost reply cannot establish whether deletion took effect.
      await deleteMetricServer(serverId)
      if (disposed) return
      deleteResult.value = 'success'
      rows.value = rows.value.filter(row => row.serverId !== serverId)
    } catch (cause) {
      if (disposed) return
      const problem = metricsError(cause)
      deleteProblem.value = problem
      deleteResult.value = problem.writeAttempted ? 'unknown' : 'failed'
    } finally {
      if (!disposed) {
        deletePending.value = false
        // A read failure must not turn a successful deletion receipt into failure.
        // Unknown outcomes also get a read, but never another automatic write.
        await refresh()
      }
    }
  }

  function visibilityChanged(): void {
    pageHidden.value = document.hidden
    clearTimer()
    // Let an in-flight read settle. Hidden pages schedule no further polling.
    if (!pageHidden.value && autoRefresh.value && !deleteTarget.value) void refresh()
  }

  function beforeUnload(event: BeforeUnloadEvent): void {
    if (!deletePending.value) return
    event.preventDefault()
    event.returnValue = ''
  }

  watch(autoRefresh, (enabled) => {
    clearTimer()
    if (enabled && mounted && !pageHidden.value && !deleteTarget.value) void refresh()
  }, { flush: 'sync' })

  onBeforeRouteLeave(() => !deletePending.value)
  onBeforeRouteUpdate(() => !deletePending.value)
  onMounted(() => {
    mounted = true
    pageHidden.value = document.hidden
    document.addEventListener('visibilitychange', visibilityChanged)
    window.addEventListener('beforeunload', beforeUnload)
    void refresh()
  })
  onBeforeUnmount(() => {
    disposed = true
    mounted = false
    clearTimer()
    cancelRead()
    document.removeEventListener('visibilitychange', visibilityChanged)
    window.removeEventListener('beforeunload', beforeUnload)
    // A submitted deletion keeps running; only its detached UI callbacks stop.
  })

  return {
    rows, loading, loaded, readProblem, lastUpdated,
    autoRefresh, pageHidden, autoRefreshPaused, refresh,
    deleteTarget, deletePending, deleteProblem, deleteResult,
    openDelete, closeDelete, confirmDelete, canDismissModal,
  }
}
