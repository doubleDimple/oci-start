import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch, type Ref } from 'vue'

export interface VpsLatencyRow { id: string; publicIps: string }
export type VpsLatencyStatus = 'queued' | 'running' | 'success' | 'failed' | 'timeout' | 'cancelled' | 'blocked' | 'invalid'
export type VpsLatencyRunState = 'idle' | 'running' | 'completed' | 'stopped'
export interface VpsLatencyResult {
  id: string
  /** The first valid address, normalized without brackets. */
  ip: string | null
  /** The exact HTTP target for this measurement; this is not an ICMP test. */
  target: string | null
  status: VpsLatencyStatus
  latencyMs: number | null
  attempts: number
  measuredAt: number | null
}
export interface VpsLatencyCounts {
  total: number
  queued: number
  running: number
  success: number
  failed: number
  timeout: number
  cancelled: number
  blocked: number
  invalid: number
}
interface Target { ip: string; target: string }
interface Job { id: string; ip: string; target: string; key: string }
type ProbeResult = { status: 'success'; latencyMs: number }
  | { status: 'failed' | 'timeout' | 'cancelled'; latencyMs: null }
const CONCURRENCY = 4
const TIMEOUT_MS = 5000
const AUTO_START_MS = 800

function ipv4(value: string): string | null {
  if (!/^(?:0|[1-9]\d{0,2})(?:\.(?:0|[1-9]\d{0,2})){3}$/.test(value)) return null
  const parts = value.split('.').map(Number)
  if (parts.some(part => part > 255) || parts[0] === 0 || parts[0] === 127
    || parts[0]! >= 224 || (parts[0] === 169 && parts[1] === 254)) return null
  return parts.join('.')
}
function address(value: string): Target | null {
  const source = value.trim().replace(/^(['"])(.*)\1$/, '$2')
  const host = source.startsWith('[') && source.endsWith(']') ? source.slice(1, -1) : source
  const v4 = ipv4(host)
  if (v4) return { ip: v4, target: `http://${v4}/` }
  const v6 = host
  if (!v6.includes(':') || !/^[a-fA-F0-9:.]+$/.test(v6)) return null
  try {
    // Native URL parsing validates IPv6 without accepting ports, credentials,
    // DNS names, scope IDs, paths, or a user-supplied URL.
    const parsed = new URL(`http://[${v6}]/`)
    const normalized = parsed.hostname.slice(1, -1).toLowerCase()
    if (!normalized || normalized === '::' || normalized === '::1') return null
    const first = Number.parseInt(normalized.split(':')[0] || '0', 16)
    if ((first & 0xff00) === 0xff00 || (first & 0xffc0) === 0xfe80) return null
    if (normalized.startsWith('::ffff:')) {
      const words = normalized.slice(7).split(':')
      if (words.length !== 2) return null
      const high = Number.parseInt(words[0]!, 16)
      const low = Number.parseInt(words[1]!, 16)
      if (!ipv4(`${high >> 8}.${high & 255}.${low >> 8}.${low & 255}`)) return null
    } else if (first === 0) return null
    return { ip: normalized, target: parsed.href }
  } catch { return null }
}

/** Resolve only literal IPs; never pass a hostname or arbitrary URL to fetch. */
export function vpsLatencyTarget(publicIps: string): Target | null {
  if (typeof publicIps !== 'string' || publicIps.length > 16384) return null
  const source = publicIps.trim()
  let candidates: string[]
  if (source.startsWith('[') && source.endsWith(']')) {
    try {
      const decoded: unknown = JSON.parse(source)
      candidates = Array.isArray(decoded) && decoded.every(value => typeof value === 'string')
        ? decoded : [source]
    } catch { candidates = source.includes(',') ? source.slice(1, -1).split(/[,;|\s]+/) : [source] }
  } else candidates = source.split(/[,;|\s]+/)
  for (const candidate of candidates) {
    const target = address(candidate)
    if (target) return target
  }
  return null
}
function resultKey(id: string, ip: string | null): string { return JSON.stringify([id, ip]) }

/** Browser HTTP request duration, independent of stored server-side Ping state. */
export function useVpsLatency<T extends VpsLatencyRow>(rows: Ref<T[]>, ready: Ref<boolean>, paused: Ref<boolean>) {
  const runState = ref<VpsLatencyRunState>('idle')
  const running = computed(() => runState.value === 'running')
  const results = shallowRef<Record<string, VpsLatencyResult>>({})
  const hidden = ref(false)
  const targets = computed(() => rows.value.map(row => ({ id: row.id, value: vpsLatencyTarget(row.publicIps) })))
  const scope = computed(() => JSON.stringify(targets.value.map(({ id, value }) => [id, value?.ip ?? null])))
  const counts = computed<VpsLatencyCounts>(() => {
    const value: VpsLatencyCounts = { total: 0, queued: 0, running: 0, success: 0, failed: 0, timeout: 0, cancelled: 0, blocked: 0, invalid: 0 }
    for (const { id, value: target } of targets.value) {
      const result = results.value[id]
      if (!result || result.id !== id || result.ip !== (target?.ip ?? null)) continue
      ++value.total
      ++value[result.status]
    }
    return value
  })
  let mounted = false
  let disposed = false
  let generation = 0
  let autoStarted = false
  let autoTimer: ReturnType<typeof setTimeout> | undefined
  const controllers = new Set<AbortController>()

  function eligible(): boolean { return mounted && !disposed && ready.value && !paused.value && !hidden.value }
  function clearAuto(): void { if (autoTimer !== undefined) clearTimeout(autoTimer); autoTimer = undefined }
  function current(job: Job, currentGeneration: number): boolean {
    if (!eligible() || generation !== currentGeneration) return false
    return targets.value.some(({ id, value }) => id === job.id && value?.ip === job.ip)
  }
  function setResult(job: Job, currentGeneration: number, change: Partial<VpsLatencyResult>): void {
    if (!current(job, currentGeneration)) return
    const previous = results.value[job.id]
    if (!previous || resultKey(previous.id, previous.ip) !== job.key) return
    results.value = { ...results.value, [job.id]: { ...previous, ...change } }
  }
  function cancelWork(): void {
    clearAuto()
    ++generation
    for (const controller of controllers) controller.abort()
    controllers.clear()
    if (!running.value) return
    const next: Record<string, VpsLatencyResult> = {}
    for (const [id, result] of Object.entries(results.value)) {
      next[id] = result.status === 'queued' || result.status === 'running'
        ? { ...result, status: 'cancelled', latencyMs: null, measuredAt: null } : result
    }
    results.value = next
    runState.value = 'stopped'
  }
  async function probe(target: string, signal: AbortSignal): Promise<ProbeResult> {
    const active = new AbortController()
    let timedOut = false
    const abort = () => active.abort()
    signal.addEventListener('abort', abort, { once: true })
    if (signal.aborted) active.abort()
    const timer = setTimeout(() => { timedOut = true; active.abort() }, TIMEOUT_MS)
    const started = performance.now()
    try {
      await fetch(target, {
        method: 'HEAD', mode: 'no-cors', redirect: 'follow', cache: 'no-store',
        credentials: 'omit', referrerPolicy: 'no-referrer', signal: active.signal,
      })
      if (signal.aborted) return { status: 'cancelled', latencyMs: null }
      if (timedOut) return { status: 'timeout', latencyMs: null }
      const elapsed = performance.now() - started
      return Number.isFinite(elapsed) && elapsed >= 0
        ? { status: 'success', latencyMs: Math.round(elapsed) } : { status: 'failed', latencyMs: null }
    } catch {
      return { status: signal.aborted ? 'cancelled' : timedOut ? 'timeout' : 'failed', latencyMs: null }
    } finally {
      clearTimeout(timer)
      signal.removeEventListener('abort', abort)
    }
  }
  async function measure(job: Job, currentGeneration: number): Promise<void> {
    if (!current(job, currentGeneration)) return
    const controller = new AbortController()
    controllers.add(controller)
    try {
      for (let attempt = 1; attempt <= 2; ++attempt) {
        if (!current(job, currentGeneration) || controller.signal.aborted) return
        setResult(job, currentGeneration, { status: 'running', attempts: attempt })
        const result = await probe(job.target, controller.signal)
        if (!current(job, currentGeneration)) return
        if (result.status === 'cancelled') return
        if (result.status === 'success' || attempt === 2) {
          setResult(job, currentGeneration, { status: result.status, latencyMs: result.latencyMs, measuredAt: Date.now() })
          return
        }
      }
    } finally { controllers.delete(controller) }
  }
  async function consume(jobs: Job[], currentGeneration: number): Promise<void> {
    let cursor = 0
    async function worker(): Promise<void> {
      while (eligible() && generation === currentGeneration && cursor < jobs.length) {
        const job = jobs[cursor++]
        if (job) await measure(job, currentGeneration)
      }
    }
    await Promise.all(Array.from({ length: Math.min(CONCURRENCY, jobs.length) }, () => worker()))
    if (!disposed && generation === currentGeneration && running.value) runState.value = 'completed'
  }
  function start(): void {
    if (!eligible() || running.value) return
    clearAuto()
    autoStarted = true
    const currentGeneration = ++generation
    const jobs: Job[] = []
    const next: Record<string, VpsLatencyResult> = {}
    const blocked = window.location.protocol !== 'http:' || typeof fetch !== 'function' || typeof AbortController === 'undefined'
    for (const { id, value } of targets.value) {
      if (!id) continue
      next[id] = {
        id, ip: value?.ip ?? null, target: value?.target ?? null,
        status: !value ? 'invalid' : blocked ? 'blocked' : 'queued',
        latencyMs: null, attempts: 0, measuredAt: null,
      }
      if (value && !blocked) jobs.push({ id, ...value, key: resultKey(id, value.ip) })
    }
    results.value = next
    runState.value = jobs.length ? 'running' : 'completed'
    if (jobs.length) void consume(jobs, currentGeneration)
  }
  function stop(): void { autoStarted = true; cancelWork() }
  function scheduleAuto(): void {
    if (!eligible() || autoStarted || autoTimer !== undefined || running.value) return
    autoTimer = setTimeout(() => { autoTimer = undefined; start() }, AUTO_START_MS)
  }
  function synchronize(): void {
    if (!eligible()) cancelWork()
    else scheduleAuto()
  }
  function changedRows(): void {
    cancelWork()
    const next: Record<string, VpsLatencyResult> = {}
    for (const { id, value } of targets.value) {
      const result = results.value[id]
      if (result?.id === id && result.ip === (value?.ip ?? null)) next[id] = result
    }
    results.value = next
    synchronize()
  }
  function resultFor(row: VpsLatencyRow): VpsLatencyResult | null {
    const result = results.value[row.id]
    return result?.id === row.id && result.ip === (vpsLatencyTarget(row.publicIps)?.ip ?? null) ? result : null
  }
  function visibilityChanged(): void { hidden.value = document.hidden; synchronize() }

  watch(scope, changedRows, { flush: 'sync' })
  watch([ready, paused], synchronize, { flush: 'sync' })
  onMounted(() => {
    mounted = true
    hidden.value = document.hidden
    document.addEventListener('visibilitychange', visibilityChanged)
    synchronize()
  })
  onBeforeUnmount(() => {
    disposed = true
    mounted = false
    document.removeEventListener('visibilitychange', visibilityChanged)
    cancelWork()
  })

  return { runState, running, results, resultFor, counts, start, stop }
}
