import { computed, onBeforeUnmount, readonly, ref, shallowRef } from 'vue'
import { checkSession } from '@/utils/session'
import {
  ConsoleApiError, getConsoleControlUrl, getVncUrl, isConsoleInstanceId,
  type ConsoleMetadata,
} from '@/api/console'

export type ConsoleSessionState = 'idle' | 'preparing' | 'connecting' | 'credentials'
  | 'connected' | 'manual' | 'closed' | 'error'
const PREPARATION_TIMEOUT = 5 * 60 * 1000
const VNC_TIMEOUT = 30000
const CREDENTIAL_TIMEOUT = 5 * 60 * 1000
const IDLE_TIMEOUT = 30 * 60 * 1000
// Retained UTF-16 text is bounded to 128 KiB; the pending batch has the same cap.
const OUTPUT_CHARACTERS = 64 * 1024
const OUTPUT_LINES = 2000
const MAX_MESSAGE_CHARACTERS = 1024 * 1024

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function port(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0 && value <= 65535
}
function detail(value: unknown): string {
  return typeof value === 'string' ? value.trim().slice(0, 1000) : ''
}

/** Own the JSON control socket. RFB owns the separate binary display socket. */
export function useConsoleSession() {
  const state = ref<ConsoleSessionState>('idle')
  const problem = shallowRef<ConsoleApiError | null>(null)
  const vncUrl = ref('')
  const command = ref('')
  const connectionId = ref('')
  const output = ref('')
  const outputTruncated = ref(false)
  const key = ref(0)
  const idleRemainingSeconds = ref(IDLE_TIMEOUT / 1000)
  const idleWarning = ref(false)
  const connecting = computed(() => ['preparing', 'connecting', 'credentials'].includes(state.value))
  const connected = computed(() => state.value === 'connected')
  let socket: WebSocket | null = null
  let disposed = false
  let createAttempted = false
  let lastActivity = 0
  let deadline: ReturnType<typeof setTimeout> | undefined
  let heartbeat: ReturnType<typeof setInterval> | undefined
  let ping: ReturnType<typeof setInterval> | undefined
  let idleTimer: ReturnType<typeof setInterval> | undefined
  let outputTimer: ReturnType<typeof setTimeout> | undefined
  let pendingOutput = ''

  function flushOutput() {
    if (outputTimer !== undefined) clearTimeout(outputTimer)
    outputTimer = undefined
    if (!pendingOutput) return
    let next = output.value + pendingOutput
    pendingOutput = ''
    if (next.length > OUTPUT_CHARACTERS) {
      next = next.slice(-OUTPUT_CHARACTERS)
      const boundary = next.indexOf('\n')
      if (boundary >= 0) next = next.slice(boundary + 1)
      outputTruncated.value = true
    }
    const lines = next.split('\n')
    if (lines.length > OUTPUT_LINES) {
      next = lines.slice(-OUTPUT_LINES).join('\n')
      outputTruncated.value = true
    }
    output.value = next
  }
  function appendOutput(text: string) {
    pendingOutput += text
    if (pendingOutput.length > OUTPUT_CHARACTERS) {
      pendingOutput = pendingOutput.slice(-OUTPUT_CHARACTERS)
      outputTruncated.value = true
    }
    if (outputTimer === undefined) outputTimer = setTimeout(flushOutput, 200)
  }
  function clearDeadline() {
    if (deadline !== undefined) clearTimeout(deadline)
    deadline = undefined
  }
  function clearTimers() {
    clearDeadline()
    if (heartbeat !== undefined) clearInterval(heartbeat)
    if (ping !== undefined) clearInterval(ping)
    if (idleTimer !== undefined) clearInterval(idleTimer)
    heartbeat = ping = idleTimer = undefined
  }
  function current(candidate: WebSocket, generation: number) {
    return !disposed && socket === candidate && generation === key.value
  }
  function activeGeneration(generation: number) { return !disposed && generation === key.value && !!socket }
  function release(nextState: ConsoleSessionState, error: ConsoleApiError | null = null) {
    ++key.value
    const previous = socket
    socket = null
    clearTimers()
    flushOutput()
    vncUrl.value = ''
    state.value = nextState
    problem.value = error
    idleWarning.value = false
    idleRemainingSeconds.value = IDLE_TIMEOUT / 1000
    lastActivity = 0
    if (previous) {
      previous.onopen = previous.onmessage = previous.onerror = previous.onclose = null
      try {
        if (previous.readyState === WebSocket.OPEN) previous.send(JSON.stringify({ type: 'disconnect' }))
      } catch { /* Closing the socket also invokes backend cleanup. */ }
      try { previous.close(1000) } catch { /* May still be opening or already closed. */ }
    }
    // command, connectionId and retained logs intentionally survive disconnect.
  }
  function fail(error: ConsoleApiError) {
    release('error', new ConsoleApiError(error.key, error.detail, createAttempted || error.writeAttempted))
  }
  function send(frame: unknown): boolean {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      fail(new ConsoleApiError('socketFailed'))
      return false
    }
    if (socket.bufferedAmount > 64 * 1024) {
      fail(new ConsoleApiError('socketFailed'))
      return false
    }
    try { socket.send(JSON.stringify(frame)); return true } catch {
      fail(new ConsoleApiError('socketFailed'))
      return false
    }
  }
  function setDeadline(milliseconds: number, error: 'preparationTimeout' | 'vncTimeout') {
    clearDeadline()
    const generation = key.value
    deadline = setTimeout(() => {
      if (activeGeneration(generation)) fail(new ConsoleApiError(error))
    }, milliseconds)
  }
  function touch() {
    if (!connected.value) return
    // A suspended background tab may not run its interval on time. The first
    // activity after returning must not revive an already expired session.
    if (lastActivity && Date.now() - lastActivity >= IDLE_TIMEOUT) {
      fail(new ConsoleApiError('idleTimeout'))
      return
    }
    lastActivity = Date.now()
    idleRemainingSeconds.value = IDLE_TIMEOUT / 1000
    idleWarning.value = false
  }
  function markVncConnected(generation = key.value) {
    if (!activeGeneration(generation) || !vncUrl.value || !['connecting', 'credentials'].includes(state.value)) return
    clearDeadline()
    state.value = 'connected'
    problem.value = null
    touch()
    if (idleTimer !== undefined) clearInterval(idleTimer)
    idleTimer = setInterval(() => {
      if (!activeGeneration(generation) || !connected.value) return
      const remaining = Math.max(0, Math.ceil((IDLE_TIMEOUT - (Date.now() - lastActivity)) / 1000))
      idleRemainingSeconds.value = remaining
      idleWarning.value = remaining > 0 && remaining <= 60
      if (remaining === 0) fail(new ConsoleApiError('idleTimeout'))
    }, 1000)
  }
  function markVncDisconnected(reason = '', generation = key.value) {
    if (!activeGeneration(generation)) return
    fail(new ConsoleApiError('vncDisconnected', detail(reason)))
  }
  function credentialsPause(paused: boolean, generation = key.value) {
    if (!activeGeneration(generation) || !vncUrl.value || !['connecting', 'credentials'].includes(state.value)) return
    state.value = paused ? 'credentials' : 'connecting'
    // Prompting has its own finite window; submitting resumes the RFB deadline.
    setDeadline(paused ? CREDENTIAL_TIMEOUT : VNC_TIMEOUT, 'vncTimeout')
  }
  function onMessage(raw: unknown) {
    if (typeof raw !== 'string' || raw.length > MAX_MESSAGE_CHARACTERS) throw new ConsoleApiError('invalidMessage')
    let event: unknown
    try { event = JSON.parse(raw) } catch { throw new ConsoleApiError('invalidMessage') }
    if (!object(event) || typeof event.type !== 'string') throw new ConsoleApiError('invalidMessage')
    if (event.type === 'heartbeat') { send({ type: 'heartbeat_response', timestamp: Date.now() }); return }
    if (event.type === 'heartbeat_response' || event.type === 'pong') return
    if (event.type === 'output') {
      if (typeof event.data !== 'string') throw new ConsoleApiError('invalidMessage')
      appendOutput(event.data)
      return
    }
    if (event.type === 'error') {
      if (typeof event.message !== 'string') throw new ConsoleApiError('invalidMessage')
      fail(new ConsoleApiError('connectionFailed', detail(event.message)))
      return
    }
    if (event.type !== 'vnc_ready' || state.value !== 'preparing') throw new ConsoleApiError('invalidMessage')
    if (typeof event.connectionId !== 'string' || !event.connectionId.trim()
      || typeof event.command !== 'string' || !port(event.port)) throw new ConsoleApiError('invalidMessage')
    connectionId.value = event.connectionId
    command.value = event.command
    if (typeof event.message === 'string' && event.message) appendOutput(event.message + '\r\n')
    clearDeadline()
    if (event.websockifyPort == null) {
      // Existing server fallback also emits vnc_ready when websockify fails.
      // A manual command is useful, but it does not establish a browser display.
      state.value = 'manual'
      setDeadline(PREPARATION_TIMEOUT, 'vncTimeout')
      return
    }
    if (!port(event.websockifyPort)) throw new ConsoleApiError('invalidMessage')
    state.value = 'connecting'
    vncUrl.value = getVncUrl(event.websockifyPort)
    setDeadline(VNC_TIMEOUT, 'vncTimeout')
  }
  function start(metadata: ConsoleMetadata): boolean {
    if (disposed || connecting.value || connected.value || state.value === 'manual') return false
    if (!metadata || !isConsoleInstanceId(metadata.instanceId) || !isConsoleInstanceId(metadata.tenantId)
      || typeof metadata.ociInstanceId !== 'string' || !metadata.ociInstanceId.startsWith('ocid1.instance.')
      || typeof metadata.instanceIp !== 'string' || typeof metadata.instanceName !== 'string') {
      problem.value = new ConsoleApiError('invalidContext')
      return false
    }
    release('preparing')
    createAttempted = false
    command.value = connectionId.value = output.value = pendingOutput = ''
    outputTruncated.value = false
    const target = Object.freeze({ ...metadata })
    let candidate: WebSocket
    try { candidate = new WebSocket(getConsoleControlUrl()) } catch {
      fail(new ConsoleApiError('socketFailed'))
      return false
    }
    socket = candidate
    const generation = key.value
    setDeadline(PREPARATION_TIMEOUT, 'preparationTimeout')
    candidate.onopen = () => {
      if (!current(candidate, generation)) return
      createAttempted = true
      if (!send({ type: 'create_connection', data: {
        instanceId: target.instanceId, tenantId: target.tenantId,
        displayName: target.instanceIp || target.instanceName || 'VNC', connectionType: 'vnc',
      } })) return
      heartbeat = setInterval(() => {
        if (current(candidate, generation)) send({ type: 'heartbeat', timestamp: Date.now() })
      }, 30000)
      ping = setInterval(() => {
        if (current(candidate, generation) && state.value !== 'preparing') send({ type: 'ping', timestamp: Date.now() })
      }, 10000)
    }
    candidate.onmessage = (event: MessageEvent<unknown>) => {
      if (!current(candidate, generation)) return
      try { onMessage(event.data) } catch (cause) {
        if (current(candidate, generation)) fail(cause instanceof ConsoleApiError ? cause : new ConsoleApiError('invalidMessage'))
      }
    }
    candidate.onerror = () => {
      if (!current(candidate, generation)) return
      void checkSession()
      fail(new ConsoleApiError('socketFailed'))
    }
    candidate.onclose = () => {
      if (!current(candidate, generation)) return
      void checkSession()
      fail(new ConsoleApiError('socketFailed'))
    }
    return true
  }
  function stop() { release('closed') }
  /** A different route target must not inherit another instance's diagnostics. */
  function reset() {
    release('idle')
    command.value = connectionId.value = output.value = pendingOutput = ''
    outputTruncated.value = false
    createAttempted = false
  }
  onBeforeUnmount(() => { disposed = true; release('closed') })
  return {
    state: readonly(state), problem: readonly(problem), vncUrl: readonly(vncUrl),
    command: readonly(command), connectionId: readonly(connectionId), output: readonly(output),
    outputTruncated: readonly(outputTruncated), key: readonly(key), connecting, connected,
    idleRemainingSeconds: readonly(idleRemainingSeconds), idleWarning: readonly(idleWarning),
    start, stop, reset, markVncConnected, markVncDisconnected, touch, credentialsPause,
  }
}
