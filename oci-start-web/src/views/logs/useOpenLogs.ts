import { onBeforeUnmount, onMounted, ref, shallowReactive } from 'vue'
import { checkSession } from '@/utils/session'
import {
  loadOpenLogHistory, OPEN_LOG_STREAM_URL, openLogsError, type OpenLogsApiError,
} from '@/api/openLogs'

export type OpenLogLevel = 'success' | 'warn' | 'error' | 'default'
export interface OpenLogRow {
  key: number
  text: string
  level: OpenLogLevel
}
export type OpenLogConnection = 'idle' | 'connecting' | 'connected'
  | 'reconnecting' | 'disconnected' | 'unsupported'
export interface OpenLogSource {
  loadHistory: (signal?: AbortSignal) => Promise<string[]>
  streamUrl: string
}

const MAX_ROWS = 1000
const FLUSH_INTERVAL_MS = 100
const RECONNECT_DELAY_MS = 5000

function logLevel(text: string): OpenLogLevel {
  // Match the old marker precedence without altering the actual log text.
  const lower = text.toLowerCase()
  if (lower.includes('[success]')) return 'success'
  if (lower.includes('[warn]') || lower.includes('warning')) return 'warn'
  if (lower.includes('[error]') || lower.includes('error')) return 'error'
  return 'default'
}

/** History first, then a manually reconnected, same-origin native SSE stream. */
export function useOpenLogs(sourceOptions: OpenLogSource = {
  loadHistory: loadOpenLogHistory, streamUrl: OPEN_LOG_STREAM_URL,
}) {
  // A mounted viewer owns one fixed source; source changes require a new viewer.
  const { loadHistory, streamUrl } = sourceOptions
  const rows = ref<OpenLogRow[]>([])
  const history = shallowReactive({
    loading: false, loaded: false, problem: null as OpenLogsApiError | null,
  })
  const connection = ref<OpenLogConnection>('idle')
  const bufferRevision = ref(0)
  const liveReceivedCount = ref(0)
  const trimmedCount = ref(0)
  const hasStreamGap = ref(false)

  let nextKey = 0
  let pending: OpenLogRow[] = []
  let pendingDropped = 0
  let batchTimer: ReturnType<typeof setTimeout> | undefined
  let batchSequence = 0
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined
  let reconnectSequence = 0
  let source: EventSource | undefined
  let streamSequence = 0
  let streamAttempted = false
  let historyController: AbortController | undefined
  let historySequence = 0
  let disposed = false

  function makeRow(text: string): OpenLogRow {
    return { key: ++nextKey, text, level: logLevel(text) }
  }

  function cancelBatchTimer() {
    ++batchSequence
    if (batchTimer !== undefined) clearTimeout(batchTimer)
    batchTimer = undefined
  }

  function flushPending() {
    cancelBatchTimer()
    if (!pending.length || disposed) return
    const combined = [...rows.value, ...pending]
    const dropped = pendingDropped + Math.max(0, combined.length - MAX_ROWS)
    // Count live entries at flush time, including live entries evicted from the
    // bounded pending queue. History replacement and screen clearing are not arrivals.
    liveReceivedCount.value += pending.length + pendingDropped
    pending = []
    pendingDropped = 0
    rows.value = combined.slice(-MAX_ROWS)
    trimmedCount.value += dropped
    ++bufferRevision.value
  }

  function enqueue(text: string) {
    // Both buffers are independently bounded, including while background-tab
    // timers are throttled. Keep this queue and its drop count nonreactive so a
    // full displayed window still updates only once per 100 ms flush.
    if (pending.length === MAX_ROWS) {
      pending.shift()
      ++pendingDropped
    }
    pending.push(makeRow(text))
    if (batchTimer !== undefined) return
    const current = ++batchSequence
    batchTimer = setTimeout(() => {
      if (disposed || current !== batchSequence) return
      batchTimer = undefined
      flushPending()
    }, FLUSH_INTERVAL_MS)
  }

  function cancelReconnectTimer() {
    ++reconnectSequence
    if (reconnectTimer !== undefined) clearTimeout(reconnectTimer)
    reconnectTimer = undefined
  }

  function closeStream() {
    ++streamSequence
    const previous = source
    source = undefined
    if (!previous) return
    previous.onopen = null
    previous.onmessage = null
    previous.onerror = null
    // Native retry must be disabled before scheduling our single retry timer.
    previous.close()
  }

  function scheduleReconnect() {
    cancelReconnectTimer()
    if (disposed || history.loading) return
    connection.value = 'reconnecting'
    const current = reconnectSequence
    reconnectTimer = setTimeout(() => {
      if (disposed || current !== reconnectSequence || history.loading) return
      reconnectTimer = undefined
      connectStream()
    }, RECONNECT_DELAY_MS)
  }

  function connectStream(): boolean {
    if (disposed || history.loading || source) return false
    cancelReconnectTimer()
    if (typeof EventSource === 'undefined') {
      connection.value = 'unsupported'
      return false
    }
    connection.value = 'connecting'
    streamAttempted = true
    const current = ++streamSequence
    let active: EventSource
    try {
      // A relative same-origin URL uses the browser's existing session cookies.
      active = new EventSource(streamUrl)
    } catch {
      hasStreamGap.value = true
      connection.value = 'disconnected'
      scheduleReconnect()
      return false
    }
    source = active
    const isCurrent = () => !disposed && current === streamSequence && source === active
    active.onopen = () => {
      if (isCurrent()) connection.value = 'connected'
    }
    active.onmessage = (event: MessageEvent<string>) => {
      // Empty strings, repeated lines, markers and multiline text are valid logs.
      if (isCurrent()) enqueue(event.data)
    }
    active.onerror = () => {
      if (!isCurrent()) return
      void checkSession()
      closeStream()
      hasStreamGap.value = true
      connection.value = 'disconnected'
      scheduleReconnect()
    }
    return true
  }

  /** Retry the live stream only. Ignore repeated clicks while a connection opens. */
  function reconnect(): boolean {
    if (disposed || history.loading || connection.value === 'connecting'
      || connection.value === 'connected') return false
    if (streamAttempted) hasStreamGap.value = true
    cancelReconnectTimer()
    closeStream()
    return connectStream()
  }

  /** Replace the visible history window only after a successful fresh read. */
  async function refreshHistory(): Promise<boolean> {
    if (disposed || history.loading) return false
    if (streamAttempted) hasStreamGap.value = true
    cancelReconnectTimer()
    closeStream()
    // Keep all already received entries if this read fails, including its batch.
    flushPending()
    connection.value = 'idle'
    const current = ++historySequence
    const controller = new AbortController()
    historyController = controller
    history.loading = true
    history.problem = null
    const isCurrent = () => !disposed && current === historySequence
      && historyController === controller && !controller.signal.aborted
    try {
      const lines = await loadHistory(controller.signal)
      if (!isCurrent()) return false
      cancelBatchTimer()
      pending = []
      pendingDropped = 0
      trimmedCount.value = Math.max(0, lines.length - MAX_ROWS)
      rows.value = lines.slice(-MAX_ROWS).map(makeRow)
      history.loaded = true
      ++bufferRevision.value
      return true
    } catch (cause) {
      if (!isCurrent()) return false
      const problem = openLogsError(cause)
      if (problem.key !== 'cancelled') history.problem = problem
      return false
    } finally {
      // A clear/unmount invalidates this read and owns the next connection, so
      // even a transport that resolves after abort cannot refill or reopen it.
      if (isCurrent()) {
        historyController = undefined
        history.loading = false
        connectStream()
      }
    }
  }

  /** Local screen clear only: leave a healthy live connection running. */
  function clear() {
    if (disposed) return
    const wasReading = history.loading
    ++historySequence
    historyController?.abort()
    historyController = undefined
    history.loading = false
    history.problem = null
    cancelBatchTimer()
    pending = []
    pendingDropped = 0
    rows.value = []
    trimmedCount.value = 0
    ++bufferRevision.value
    // Clearing during the initial/history read must still start the live stream.
    if (wasReading) connectStream()
  }

  onMounted(() => { void refreshHistory() })
  onBeforeUnmount(() => {
    disposed = true
    ++historySequence
    historyController?.abort()
    historyController = undefined
    history.loading = false
    cancelReconnectTimer()
    closeStream()
    cancelBatchTimer()
    pending = []
    pendingDropped = 0
    connection.value = 'disconnected'
  })

  return {
    rows, history, connection, bufferRevision, liveReceivedCount, trimmedCount, hasStreamGap,
    reconnect, refreshHistory, clear,
  }
}
