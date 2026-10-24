import { computed, onBeforeUnmount, readonly, ref, shallowRef } from 'vue'
import { checkSession } from '@/utils/session'
import {
  getSshWebSocketUrl, normalizeSshCredentials, redactSshDetail, sshError,
  SSH_CONNECTED_MESSAGE, SSH_CONNECT_ERROR_PREFIX, SSH_CONNECT_TIMEOUT_MS,
  SshApiError, type SshCredentials,
} from '@/api/ssh'

export type SshSessionState = 'idle' | 'connecting' | 'connected' | 'closed' | 'error'
const MAX_SOCKET_BUFFER_BYTES = 1024 * 1024
const MAX_INPUT_CHUNK_CHARACTERS = 1024
const MAX_CONTROL_FRAME_BYTES = 8 * 1024
const MAX_OUTPUT_FRAME_CHARACTERS = 1024 * 1024

/** Owns a single explicit SSH connection; raw terminal output is never JSON parsed. */
export function useSshSession(options: { onOutput: (text: string) => void }) {
  const state = ref<SshSessionState>('idle')
  const problem = shallowRef<SshApiError | null>(null)
  const profile = shallowRef<Readonly<SshCredentials> | null>(null)
  const connectionKey = ref(0)
  const connecting = computed(() => state.value === 'connecting')
  const connected = computed(() => state.value === 'connected')
  let socket: WebSocket | null = null
  let pendingCredentials: SshCredentials | null = null
  let deadline: ReturnType<typeof setTimeout> | undefined
  let disposed = false
  let dimensions = { cols: 80, rows: 24 }
  let sentDimensions = ''
  const encoder = new TextEncoder()

  function clearDeadline() {
    if (deadline !== undefined) clearTimeout(deadline)
    deadline = undefined
  }
  function release(nextState: SshSessionState, error: SshApiError | null = null) {
    // Invalidate before closing: onclose may otherwise mutate a new connection.
    ++connectionKey.value
    const previous = socket
    socket = null
    pendingCredentials = null
    profile.value = null
    sentDimensions = ''
    clearDeadline()
    state.value = nextState
    problem.value = error
    if (previous) {
      previous.onopen = previous.onmessage = previous.onerror = previous.onclose = null
      try { previous.close(1000) } catch { /* Already closing or not yet open. */ }
    }
  }
  function fail(error: SshApiError) { release('error', error) }
  function current(candidate: WebSocket, generation: number) {
    return !disposed && socket === candidate && generation === connectionKey.value
  }
  function sendEncoded(data: string): boolean {
    const candidate = socket
    if (!candidate || candidate.readyState !== WebSocket.OPEN) {
      if (connecting.value || connected.value) fail(new SshApiError('socketFailed'))
      return false
    }
    // Bound queued input rather than silently truncating or replaying commands.
    const bytes = encoder.encode(data).byteLength
    if (bytes > MAX_CONTROL_FRAME_BYTES || candidate.bufferedAmount + bytes > MAX_SOCKET_BUFFER_BYTES) {
      fail(new SshApiError('bufferFull'))
      return false
    }
    try { candidate.send(data); return true } catch {
      fail(new SshApiError('socketFailed'))
      return false
    }
  }
  function sendFrame(frame: unknown): boolean { return sendEncoded(JSON.stringify(frame)) }
  function sendDimensions(): boolean {
    const key = `${dimensions.cols}:${dimensions.rows}`
    if (key === sentDimensions) return true
    if (!sendFrame({ type: 'resize', data: { ...dimensions } })) return false
    sentDimensions = key
    return true
  }
  function resize(cols: number, rows: number): boolean {
    if (!Number.isInteger(cols) || !Number.isInteger(rows) || cols < 1 || rows < 1 || cols > 10000 || rows > 10000) return false
    dimensions = { cols, rows }
    return connected.value ? sendDimensions() : true
  }
  function sendInput(data: string): boolean {
    if (!connected.value || typeof data !== 'string') return false
    if (!data) return true
    if (data.length > MAX_SOCKET_BUFFER_BYTES) {
      fail(new SshApiError('bufferFull'))
      return false
    }
    const frames: string[] = []
    let totalBytes = 0
    for (let offset = 0; offset < data.length;) {
      let end = Math.min(data.length, offset + MAX_INPUT_CHUNK_CHARACTERS)
      // JSON escapes can take six bytes per UTF-16 unit. Small frames stay
      // within the servlet container's default message size without losing
      // bracketed-paste delimiters or splitting supplementary characters.
      const previous = data.charCodeAt(end - 1)
      const next = data.charCodeAt(end)
      if (end < data.length && previous >= 0xD800 && previous <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) --end
      const frame = JSON.stringify({ type: 'input', data: data.slice(offset, end) })
      totalBytes += encoder.encode(frame).byteLength
      if (totalBytes + (socket?.bufferedAmount || 0) > MAX_SOCKET_BUFFER_BYTES) {
        // Reject before sending any of this paste, rather than silently sending
        // only a prefix. Transport failure mid-send still requires disconnect.
        fail(new SshApiError('bufferFull'))
        return false
      }
      frames.push(frame)
      offset = end
    }
    for (const frame of frames) if (!sendEncoded(frame)) return false
    return true
  }
  function connect(credentials: SshCredentials): boolean {
    if (disposed || connecting.value) return false
    let normalized: SshCredentials
    try { normalized = normalizeSshCredentials(credentials) } catch (cause) {
      problem.value = sshError(cause)
      return false
    }
    release('connecting')
    pendingCredentials = normalized
    let candidate: WebSocket
    try { candidate = new WebSocket(getSshWebSocketUrl()) } catch {
      fail(new SshApiError('socketFailed'))
      return false
    }
    socket = candidate
    const generation = connectionKey.value
    deadline = setTimeout(() => {
      if (current(candidate, generation) && connecting.value) fail(new SshApiError('connectionTimeout'))
    }, SSH_CONNECT_TIMEOUT_MS)
    candidate.onopen = () => {
      if (!current(candidate, generation) || !pendingCredentials) return
      sendFrame({ type: 'connect', data: { ...pendingCredentials } })
    }
    candidate.onmessage = (event: MessageEvent<unknown>) => {
      if (!current(candidate, generation)) return
      if (typeof event.data !== 'string' || event.data.length > MAX_OUTPUT_FRAME_CHARACTERS) {
        fail(new SshApiError('invalidMessage'))
        return
      }
      const text = event.data
      if (connecting.value && (text.startsWith(SSH_CONNECT_ERROR_PREFIX) || text.startsWith('❌ IO 初始化失败: '))) {
        // This is a handshake control frame, never remote-shell output.
        const detail = redactSshDetail(text.trim(), pendingCredentials?.password || '').slice(0, 1000)
        fail(new SshApiError('connectionFailed', detail))
        return
      }
      if (connecting.value && text === SSH_CONNECTED_MESSAGE) {
        clearDeadline()
        profile.value = pendingCredentials ? Object.freeze({ ...pendingCredentials }) : null
        pendingCredentials = null
        state.value = 'connected'
        problem.value = null
        if (!sendDimensions()) return
      }
      // Includes the legacy successful connection banner. The renderer owns
      // ANSI handling and batching; JSON-looking shell output remains literal.
      try { options.onOutput(text) } catch {
        if (current(candidate, generation)) fail(new SshApiError('outputFailed'))
      }
    }
    candidate.onerror = () => {
      if (!current(candidate, generation)) return
      void checkSession()
      fail(new SshApiError('socketFailed'))
    }
    candidate.onclose = (event) => {
      if (!current(candidate, generation)) return
      void checkSession()
      if (connecting.value) fail(new SshApiError('connectionFailed'))
      else if (event.code !== 1000) fail(new SshApiError('socketFailed'))
      else release('closed')
    }
    return true
  }
  function disconnect() { release('closed') }
  onBeforeUnmount(() => { disposed = true; release('closed') })

  return {
    state: readonly(state), problem: readonly(problem), profile: readonly(profile),
    connectionKey: readonly(connectionKey), connecting, connected,
    connect, disconnect, sendInput, resize,
  }
}
