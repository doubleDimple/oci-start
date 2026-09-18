import { computed, onBeforeUnmount, onMounted, ref, shallowReactive, watch } from 'vue'
import { onBeforeRouteLeave, useRoute } from 'vue-router'
import {
  DelayTestApiError, delayTestError, getDelayClientIp, listDelayRegions, measureDelayRegion,
  type DelayClientIp, type DelayMeasurement, type DelayRegion,
} from '@/api/delayTest'
import { navigationPending, navigationTargetPath } from '@/utils/navigation'

// Leave room for navigation assets and normal application requests.
const PROBE_CONCURRENCY = 6

function yieldToBrowser(signal: AbortSignal): Promise<void> {
  return new Promise(resolve => {
    const timer = setTimeout(done, 0)
    function done() {
      clearTimeout(timer)
      signal.removeEventListener('abort', done)
      resolve()
    }
    signal.addEventListener('abort', done, { once: true })
    if (signal.aborted) done()
  })
}

export type DelayResultStatus = 'idle' | 'queued' | 'testing' | 'success' | 'timeout' | 'failed' | 'cancelled'
export type DelaySample = (DelayMeasurement | { status: 'cancelled'; latencyMs: null }) & {
  attempt: 1 | 2
  problem: DelayTestApiError | null
}
export interface DelayRegionResult extends DelayRegion {
  status: DelayResultStatus
  latencyMs: number | null
  attempt: 0 | 1 | 2
  samples: DelaySample[]
  problem: DelayTestApiError | null
}
export type SuccessfulDelayResult = DelayRegionResult & { status: 'success'; latencyMs: number }
export type DelayRunState = 'idle' | 'running' | 'completed' | 'stopped'

function resultFor(region: DelayRegion, status: DelayResultStatus = 'idle'): DelayRegionResult {
  return { ...region, status, latencyMs: null, attempt: 0, samples: [], problem: null }
}

/** Browser HEAD orchestration only; all actual reads and samples live in the API. */
export function useDelayTest() {
  const route = useRoute()
  const pagePath = route.path
  const regions = shallowReactive({
    rows: [] as DelayRegion[], loading: false, loaded: false, problem: null as DelayTestApiError | null,
  })
  const ip = shallowReactive({
    value: null as DelayClientIp | null, loading: false, loaded: false, problem: null as DelayTestApiError | null,
  })
  const results = ref<DelayRegionResult[]>([])
  const runState = ref<DelayRunState>('idle')
  const running = computed(() => runState.value === 'running')
  const autoStartPending = ref(false)
  let regionSequence = 0
  let ipSequence = 0
  let generation = 0
  let regionController: AbortController | undefined
  let ipController: AbortController | undefined
  let runController: AbortController | undefined
  let autoTimer: ReturnType<typeof setTimeout> | undefined
  let autoSequence = 0
  let initialDirectoryHandled = false
  let disposed = false
  let leaving = false

  const successfulResults = computed(() => results.value.filter((row): row is SuccessfulDelayResult => row.status === 'success' && row.latencyMs !== null))
  const sortedResults = computed(() => [...successfulResults.value].sort((a, b) => a.latencyMs - b.latencyMs))
  const best = computed<SuccessfulDelayResult | null>(() => sortedResults.value[0] || null)
  const average = computed<number | null>(() => successfulResults.value.length
    ? Math.round(successfulResults.value.reduce((sum, row) => sum + row.latencyMs, 0) / successfulResults.value.length)
    : null)
  // Keep the original strict threshold. A 150 ms sample does not enter Top 5.
  const top5 = computed(() => sortedResults.value.filter((row) => row.latencyMs < 150).slice(0, 5))
  const counts = computed(() => {
    const value = { total: results.value.length, idle: 0, queued: 0, testing: 0, completed: 0, success: 0, failed: 0, timeout: 0, errors: 0, cancelled: 0, settled: 0 }
    for (const row of results.value) {
      if (row.status === 'failed') value.errors++
      else value[row.status]++
    }
    value.failed = value.timeout + value.errors
    value.completed = value.success + value.failed
    value.settled = value.completed + value.cancelled
    return value
  })

  function cancelAutoStart() {
    ++autoSequence
    if (autoTimer !== undefined) clearTimeout(autoTimer)
    autoTimer = undefined
    autoStartPending.value = false
  }
  function markCancelled(row: DelayRegionResult) {
    if (row.status !== 'testing' && row.status !== 'queued') return
    // A completed first sample remains inspectable, but a region stopped during
    // its second sample is not counted as completed or included in the ranking.
    if (row.attempt && !row.samples.some((sample) => sample.attempt === row.attempt)) {
      row.samples.push({ attempt: row.attempt, status: 'cancelled', latencyMs: null, problem: null })
    }
    row.status = 'cancelled'
    row.latencyMs = null
    row.problem = new DelayTestApiError('cancelled')
  }
  function cancelRun(updateResults = true) {
    ++generation
    runController?.abort()
    runController = undefined
    if (updateResults) for (const row of results.value) markCancelled(row)
  }
  function stop() {
    if (disposed) return
    const wasPending = running.value || autoStartPending.value
    initialDirectoryHandled = true
    cancelAutoStart()
    cancelRun()
    if (wasPending) runState.value = 'stopped'
  }

  async function sample(region: DelayRegion, attempt: 1 | 2, signal: AbortSignal): Promise<DelaySample> {
    try {
      const measurement = await measureDelayRegion(region, signal)
      return { ...measurement, attempt, problem: null }
    } catch (cause) {
      const problem = delayTestError(cause)
      return {
        attempt, status: problem.key === 'cancelled' ? 'cancelled' : problem.key === 'timeout' ? 'timeout' : 'failed',
        latencyMs: null, problem,
      }
    }
  }
  async function testRegion(row: DelayRegionResult, current: number, controller: AbortController) {
    const isCurrent = () => !disposed && !leaving && current === generation && runController === controller && !controller.signal.aborted
    if (!isCurrent()) return
    row.status = 'testing'
    row.attempt = 1
    const first = await sample(row, 1, controller.signal)
    if (!isCurrent()) return
    row.samples.push(first)
    if (first.status !== 'success') {
      row.status = first.status
      row.problem = first.problem
      return
    }
    row.latencyMs = first.latencyMs
    row.attempt = 2
    // Match the old page: only a successful first HEAD gets a second HEAD.
    const second = await sample(row, 2, controller.signal)
    if (!isCurrent()) return
    row.samples.push(second)
    if (second.status === 'cancelled') {
      row.status = 'cancelled'
      row.latencyMs = null
      row.problem = second.problem
      return
    }
    // A failed or timed-out second request does not erase the successful first.
    row.latencyMs = second.status === 'success' ? Math.min(first.latencyMs, second.latencyMs) : first.latencyMs
    row.status = 'success'
    row.problem = null
  }
  /** Duplicate starts are ignored; call stop before explicitly starting a new round. */
  async function start(): Promise<boolean> {
    if (disposed || leaving || running.value || !regions.loaded || regions.loading || regions.problem || !regions.rows.length) return false
    initialDirectoryHandled = true
    cancelAutoStart()
    cancelRun()
    const current = generation
    const controller = new AbortController()
    runController = controller
    results.value = regions.rows.map((region) => resultFor(region, 'queued'))
    runState.value = 'running'
    // Start a sample's clock only when its worker actually sends the HEAD.
    // Queued regions do not compete with navigation for dozens of connections.
    const roundRows = results.value
    let next = 0
    const isCurrent = () => !disposed && !leaving && current === generation && !controller.signal.aborted && runController === controller
    async function worker() {
      while (isCurrent()) {
        const row = roundRows[next++]
        if (!row) return
        try {
          await testRegion(row, current, controller)
        } catch (cause) {
          if (!isCurrent()) return
          // Preserve actual successful samples if an unexpected row error escapes.
          const problem = delayTestError(cause)
          if (row.attempt && !row.samples.some((item) => item.attempt === row.attempt)) {
            row.samples.push({ attempt: row.attempt, status: 'failed', latencyMs: null, problem })
          }
          const successful = row.samples.filter((item): item is DelaySample & { status: 'success'; latencyMs: number } => item.status === 'success')
          row.status = successful.length ? 'success' : 'failed'
          row.latencyMs = successful.length ? Math.min(...successful.map((item) => item.latencyMs)) : null
          row.problem = successful.length ? null : problem
        }
        if (!isCurrent()) return
        // Even immediately rejected requests must yield to clicks and painting.
        await yieldToBrowser(controller.signal)
      }
    }
    await Promise.all(Array.from({ length: Math.min(PROBE_CONCURRENCY, roundRows.length) }, () => worker()))
    if (!isCurrent()) return false
    runController = undefined
    runState.value = results.value.some((row) => row.status === 'cancelled') ? 'stopped' : 'completed'
    return true
  }

  function scheduleInitialRound() {
    if (disposed || leaving || initialDirectoryHandled) return
    initialDirectoryHandled = true
    // An empty successful directory has nothing to measure and must not create
    // a later surprise automatic round when the user refreshes it manually.
    if (!regions.rows.length) return
    const sequence = ++autoSequence
    autoStartPending.value = true
    autoTimer = setTimeout(() => {
      if (disposed || leaving || sequence !== autoSequence) return
      autoTimer = undefined
      autoStartPending.value = false
      void start()
    }, 500)
  }
  function applyDirectory(rows: DelayRegion[]) {
    const previous = new Map(regions.rows.map((region) => [region.code, region.endpoint]))
    const sameTargets = rows.length === previous.size && rows.every((region) => previous.get(region.code) === region.endpoint)
    if (!sameTargets) {
      cancelRun()
      results.value = rows.map((region) => resultFor(region))
      runState.value = 'idle'
    } else {
      // Keep active result objects so a same-target refresh cannot orphan their
      // in-flight callbacks; only names and ordering follow the new directory.
      const existing = new Map(results.value.map((row) => [row.code, row]))
      results.value = rows.map((region) => {
        const row = existing.get(region.code)
        if (!row) return resultFor(region)
        Object.assign(row, region)
        return row
      })
    }
    regions.rows = rows
    regions.loaded = true
  }
  async function loadRegions(): Promise<boolean> {
    if (disposed || leaving) return false
    cancelAutoStart()
    regionController?.abort()
    const sequence = ++regionSequence
    const controller = new AbortController()
    regionController = controller
    regions.loading = true
    regions.problem = null
    try {
      const rows = await listDelayRegions(controller.signal)
      if (disposed || controller.signal.aborted || sequence !== regionSequence) return false
      applyDirectory(rows)
      scheduleInitialRound()
      return true
    } catch (cause) {
      if (!disposed && !controller.signal.aborted && sequence === regionSequence) regions.problem = delayTestError(cause)
      return false
    } finally {
      if (!disposed && sequence === regionSequence) {
        regions.loading = false
        regionController = undefined
      }
    }
  }
  async function loadCurrentIp(): Promise<boolean> {
    if (disposed || leaving) return false
    ipController?.abort()
    const sequence = ++ipSequence
    const controller = new AbortController()
    ipController = controller
    ip.loading = true
    ip.problem = null
    try {
      const value = await getDelayClientIp(controller.signal)
      if (disposed || controller.signal.aborted || sequence !== ipSequence) return false
      ip.value = value
      ip.loaded = true
      return true
    } catch (cause) {
      if (!disposed && !controller.signal.aborted && sequence === ipSequence) ip.problem = delayTestError(cause)
      return false
    } finally {
      if (!disposed && sequence === ipSequence) {
        ip.loading = false
        ipController = undefined
      }
    }
  }

  function cancelReads() {
    ++regionSequence
    ++ipSequence
    regionController?.abort()
    ipController?.abort()
    regionController = ipController = undefined
    regions.loading = ip.loading = false
  }

  function leavePage() {
    if (disposed || leaving) return
    leaving = true
    initialDirectoryHandled = true
    cancelAutoStart()
    // No per-row mutations, final-result repaint, or waiting for fetch to settle
    // on the critical path between clicking a menu and loading the next page.
    cancelRun(false)
    cancelReads()
  }

  function restorePage() {
    if (disposed || !leaving || route.path !== pagePath) return
    leaving = false
    for (const row of results.value) markCancelled(row)
    if (running.value) runState.value = 'stopped'
    // A cancelled/failed navigation may leave this page mounted. Keep it usable,
    // but do not silently restart a test that was interrupted by leaving.
    if (!regions.loaded && !regions.problem) void loadRegions()
    if (!ip.loaded && !ip.problem) void loadCurrentIp()
  }

  watch([navigationTargetPath, navigationPending], ([target, pending]) => {
    if (target && target !== pagePath) leavePage()
    else if (!pending) restorePage()
  }, { immediate: true, flush: 'sync' })
  onBeforeRouteLeave(to => {
    if (to.path !== pagePath) leavePage()
    return true
  })
  onMounted(() => { void Promise.allSettled([loadRegions(), loadCurrentIp()]) })
  onBeforeUnmount(() => {
    disposed = true
    cancelAutoStart()
    cancelRun(false)
    cancelReads()
  })

  return {
    regions, ip, results, runState, running, autoStartPending,
    counts, best, average, top5, successfulResults, loadRegions, loadCurrentIp, start, stop,
  }
}
