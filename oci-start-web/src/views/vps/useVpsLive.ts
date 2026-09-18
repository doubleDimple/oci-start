import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch, type Ref } from 'vue'
import { checkSession } from '@/utils/session'

export interface VpsLiveRow {
  id: string
  instanceId: string
  monitorInstalled: boolean | null
  /** Stored heartbeat only; older installations may have written their install time. */
  lastHeartbeat: number | null
}
export type VpsLiveConnection = 'idle' | 'connecting' | 'connected' | 'reconnecting'
  | 'paused' | 'hidden' | 'disconnected' | 'unsupported'
export type VpsAgentStatus = 'online' | 'offline' | 'notInstalled' | 'unknown'
export interface VpsLiveMetrics {
  cpuUsage: number | null
  cpuCores: number | null
  load: [number | null, number | null, number | null]
  memoryUsedMiB: number | null
  memoryTotalMiB: number | null
  memoryPercent: number | null
  swapUsedMiB: number | null
  diskUsedMiB: number | null
  diskTotalMiB: number | null
  diskPercent: number | null
  /** The shipped agent reports byte deltas, despite the DTO's Bytes/s comment. */
  rxIntervalBytes: number | null
  txIntervalBytes: number | null
  rxTotalBytes: number | null
  txTotalBytes: number | null
  uptimeSeconds: number | null
  receivedAt: number
  stale: boolean
}
type MetricValues = Omit<VpsLiveMetrics, 'receivedAt' | 'stale'>
interface Snapshot { token: string; epoch: number; receivedAt: number; values: MetricValues }
interface InstallationState { instanceId: string; installed: boolean | null }
const STALE_AFTER_MS = 12000
const STATUS_INTERVAL_MS = 3000
const RECONNECT_MS = 3000
const CONNECT_TIMEOUT_MS = 10000
const MAX_FRAME_LENGTH = 65536

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function nonnegative(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    && value <= Number.MAX_SAFE_INTEGER ? value : null
}
function whole(value: unknown): number | null {
  const result = nonnegative(value)
  return result !== null && Number.isSafeInteger(result) ? result : null
}
function percent(used: number | null, total: number | null): number | null {
  return used !== null && total !== null && total > 0 && used <= total ? used / total * 100 : null
}
function capacity(raw: unknown): { used: number | null; total: number | null } {
  const source = object(raw) ? raw : {}
  const total = whole(source.total)
  const value = whole(source.used)
  const used = value !== null && total !== null && value > total ? null : value
  return { used, total }
}
function decodeMetrics(frame: Record<string, unknown>): MetricValues | null {
  for (const key of ['cpu', 'memory', 'disk', 'network', 'host']) {
    if (frame[key] != null && !object(frame[key])) return null
  }
  const cpu = object(frame.cpu) ? frame.cpu : {}
  const memory = object(frame.memory) ? frame.memory : {}
  const network = object(frame.network) ? frame.network : {}
  const host = object(frame.host) ? frame.host : {}
  const cpuUsage = nonnegative(cpu.usage)
  const cpuCores = whole(cpu.cores)
  const load = Array.isArray(cpu.load) ? cpu.load : []
  const mem = capacity(frame.memory)
  const disk = capacity(frame.disk)
  const values: MetricValues = {
    cpuUsage: cpuUsage !== null && cpuUsage <= 100 ? cpuUsage : null,
    cpuCores: cpuCores !== null && cpuCores > 0 && cpuCores <= 2147483647 ? cpuCores : null,
    load: [nonnegative(load[0]), nonnegative(load[1]), nonnegative(load[2])],
    memoryUsedMiB: mem.used, memoryTotalMiB: mem.total, memoryPercent: percent(mem.used, mem.total),
    swapUsedMiB: whole(memory.swap_used),
    diskUsedMiB: disk.used, diskTotalMiB: disk.total, diskPercent: percent(disk.used, disk.total),
    rxIntervalBytes: whole(network.rx_rate), txIntervalBytes: whole(network.tx_rate),
    rxTotalBytes: whole(network.rx_total), txTotalBytes: whole(network.tx_total),
    uptimeSeconds: whole(host.uptime),
  }
  // A token-only message or a wholly invalid report cannot establish a heartbeat.
  return Object.values(values).some(value => typeof value === 'number'
    || (Array.isArray(value) && value.some(item => typeof item === 'number'))) ? values : null
}

/** Observe reports only while this page can see its active list context. */
export function useVpsLive<T extends VpsLiveRow>(rows: Ref<T[]>, paused: Ref<boolean>) {
  const connection = ref<VpsLiveConnection>('idle')
  const now = ref(Date.now())
  const hidden = ref(false)
  // Keep each local row's observation separate, even when rows share a machine.
  const snapshots = shallowRef(new Map<string, Snapshot>())
  const tokens = computed(() => {
    const result = new Map<string, string[]>()
    for (const row of rows.value) {
      if (!row.id || typeof row.instanceId !== 'string' || !row.instanceId.trim()) continue
      const matchingRows = result.get(row.instanceId)
      if (matchingRows) matchingRows.push(row.id)
      else result.set(row.instanceId, [row.id])
    }
    return result
  })
  const installations = computed(() => {
    const result = new Map<string, InstallationState>()
    for (const row of rows.value) {
      result.set(row.id, { instanceId: row.instanceId, installed: row.monitorInstalled })
    }
    return result
  })
  let previousInstallations = new Map<string, InstallationState>()
  let mounted = false
  let disposed = false
  let epoch = 0
  let connectedAt: number | null = null
  let socket: WebSocket | null = null
  let connectTimer: ReturnType<typeof setTimeout> | undefined
  let retryTimer: ReturnType<typeof setTimeout> | undefined
  let statusTimer: ReturnType<typeof setInterval> | undefined

  function eligible(): boolean {
    return mounted && !disposed && !paused.value && !hidden.value
      && tokens.value.size > 0
  }
  function clearRetry(): void { if (retryTimer !== undefined) clearTimeout(retryTimer); retryTimer = undefined }
  function closeSocket(): void {
    ++epoch
    connectedAt = null
    if (connectTimer !== undefined) clearTimeout(connectTimer)
    connectTimer = undefined
    const previous = socket
    socket = null
    if (!previous) return
    previous.onopen = previous.onmessage = previous.onerror = previous.onclose = null
    try { previous.close() } catch { /* A failed/closing transport needs no further action. */ }
  }
  function scheduleRetry(): void {
    if (!eligible() || retryTimer !== undefined) return
    connection.value = 'reconnecting'
    retryTimer = setTimeout(() => { retryTimer = undefined; connect(true) }, RECONNECT_MS)
  }
  function failed(active: WebSocket, current: number): void {
    if (disposed || socket !== active || epoch !== current) return
    closeSocket()
    connection.value = 'disconnected'
    now.value = Date.now()
    scheduleRetry()
  }
  function connect(retrying = false): void {
    if (!eligible() || socket) return
    clearRetry()
    if (typeof WebSocket === 'undefined' || !['http:', 'https:'].includes(window.location.protocol)) {
      connection.value = 'unsupported'
      return
    }
    connection.value = retrying ? 'reconnecting' : 'connecting'
    const current = ++epoch
    let active: WebSocket
    try {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      active = new WebSocket(`${protocol}//${window.location.host}/ws/monitor`)
    } catch {
      connection.value = 'disconnected'
      scheduleRetry()
      return
    }
    socket = active
    connectTimer = setTimeout(() => failed(active, current), CONNECT_TIMEOUT_MS)
    active.onopen = () => {
      if (disposed || socket !== active || current !== epoch || !eligible()) return
      if (connectTimer !== undefined) clearTimeout(connectTimer)
      connectTimer = undefined
      connectedAt = Date.now()
      now.value = connectedAt
      connection.value = 'connected'
    }
    active.onmessage = event => {
      if (disposed || socket !== active || epoch !== current || !eligible()
        || connection.value !== 'connected' || typeof event.data !== 'string'
        || event.data.length > MAX_FRAME_LENGTH) return
      let frame: unknown
      try { frame = JSON.parse(event.data) } catch { return }
      if (!object(frame) || frame.type != null || typeof frame.token !== 'string') return
      const rowIds = tokens.value.get(frame.token)
      if (!rowIds?.length) return
      const values = decodeMetrics(frame)
      if (!values) return
      const receivedAt = Date.now()
      const next = new Map(snapshots.value)
      for (const rowId of rowIds) {
        next.set(rowId, { token: frame.token, epoch: current, receivedAt, values })
      }
      snapshots.value = next
      now.value = receivedAt
    }
    const onTransportFailure = () => {
      if (disposed || socket !== active || epoch !== current) return
      void checkSession()
      failed(active, current)
    }
    active.onerror = onTransportFailure
    active.onclose = onTransportFailure
  }
  function synchronize(): void {
    const next = new Map([...snapshots.value].filter(([rowId, snapshot]) => {
      const token = snapshot.token
      if (!tokens.value.get(token)?.includes(rowId)) return false
      const previous = previousInstallations.get(rowId)
      const current = installations.value.get(rowId)
      // A newly recorded uninstall supersedes reports retained from before it.
      // An unchanged false flag alone cannot invalidate an observed live agent.
      return !(previous?.instanceId === token && current?.instanceId === token
        && previous.installed === true && current.installed === false)
    }))
    previousInstallations = installations.value
    if (next.size !== snapshots.value.size) snapshots.value = next
    if (!mounted || disposed) return
    now.value = Date.now()
    if (!eligible()) {
      clearRetry()
      closeSocket()
      connection.value = paused.value ? 'paused' : hidden.value ? 'hidden' : 'idle'
      return
    }
    if (!socket && retryTimer === undefined) connect()
  }
  function snapshotFor(row: VpsLiveRow): Snapshot | null {
    if (!tokens.value.get(row.instanceId)?.includes(row.id)) return null
    const snapshot = snapshots.value.get(row.id)
    return snapshot?.token === row.instanceId ? snapshot : null
  }
  function fresh(snapshot: Snapshot): boolean {
    const age = now.value - snapshot.receivedAt
    return connection.value === 'connected' && !paused.value && !hidden.value
      && snapshot.epoch === epoch && age >= 0 && age <= STALE_AFTER_MS
  }
  function metricsFor(row: VpsLiveRow): VpsLiveMetrics | null {
    const snapshot = snapshotFor(row)
    return snapshot ? { ...snapshot.values, receivedAt: snapshot.receivedAt, stale: !fresh(snapshot) } : null
  }
  function agentStatus(row: VpsLiveRow): VpsAgentStatus {
    const snapshot = snapshotFor(row)
    if (snapshot && fresh(snapshot)) return 'online'
    if (row.monitorInstalled === false && !snapshot) return 'notInstalled'
    if (connection.value !== 'connected' || paused.value || hidden.value
      || !tokens.value.get(row.instanceId)?.includes(row.id) || connectedAt === null) return 'unknown'
    // Reconnection starts a new observation window. A stale cached timestamp alone
    // does not prove whether the agent currently runs, and never supplies metrics.
    if (now.value - connectedAt >= STALE_AFTER_MS && (row.monitorInstalled === true || snapshot)) return 'offline'
    return 'unknown'
  }
  function reconnect(): void {
    if (!eligible()) { synchronize(); return }
    if (socket && connection.value !== 'connected') return
    clearRetry()
    closeSocket()
    connect(true)
  }
  function visibilityChanged(): void { hidden.value = document.hidden; synchronize() }

  watch([installations, paused], synchronize, { flush: 'sync' })
  onMounted(() => {
    mounted = true
    hidden.value = document.hidden
    document.addEventListener('visibilitychange', visibilityChanged)
    statusTimer = setInterval(() => { now.value = Date.now() }, STATUS_INTERVAL_MS)
    synchronize()
  })
  onBeforeUnmount(() => {
    disposed = true
    mounted = false
    document.removeEventListener('visibilitychange', visibilityChanged)
    if (statusTimer !== undefined) clearInterval(statusTimer)
    clearRetry()
    closeSocket()
    snapshots.value = new Map()
    previousInstallations = new Map()
    connection.value = 'idle'
  })

  return { connection, now, metricsFor, agentStatus, reconnect }
}
