import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export interface SshCredentials {
  host: string
  port: number
  username: string
  password: string
}
export interface SshConfigInput {
  username: string
  port: number
  password: string
}
export type SshErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden' | 'saveUnverified' | 'saveMismatch'
  | 'socketFailed' | 'connectionFailed' | 'connectionTimeout' | 'invalidMessage'
  | 'bufferFull' | 'outputFailed'

/** Display metadata only: never retain Axios requests, responses or credentials. */
export class SshApiError extends Error {
  constructor(
    public key: SshErrorKey,
    public detail = '',
    public writeAttempted = false,
    public saveAcknowledged = false,
  ) {
    super(key)
    this.name = 'SshApiError'
  }
}

export const SSH_CONNECTED_MESSAGE = '\r\n✅ SSH conn success\r\n'
export const SSH_CONNECT_ERROR_PREFIX = '\r\n❌ SSH conn error: '
export const SSH_CONNECT_TIMEOUT_MS = 30000

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, (token: string, number?: string) => {
      return number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token
    }))
  } catch { return raw }
}
function localId(value: string): string {
  if (typeof value !== 'string' || !/^[1-9]\d{0,18}$/.test(value)
    || (value.length === 19 && value > '9223372036854775807')) throw new SshApiError('invalidInput')
  return value
}
function validPort(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 65535
}
function configInput(input: SshConfigInput): SshConfigInput {
  if (!input || typeof input.username !== 'string' || !input.username.trim()
    || /[\x00\r\n]/.test(input.username) || !validPort(input.port)
    || typeof input.password !== 'string' || input.password.includes('\0')) throw new SshApiError('invalidInput')
  // Empty passwords may be saved, matching the existing settings endpoint.
  return { username: input.username.trim(), port: input.port, password: input.password }
}
/** Validate locally without looking up or contacting the SSH destination. */
export function normalizeSshCredentials(input: SshCredentials): SshCredentials {
  const config = configInput(input)
  if (typeof input.host !== 'string' || !input.host.trim()
    || /[\s\x00/\\?#@]/.test(input.host.trim()) || !input.password) throw new SshApiError('invalidInput')
  return { host: input.host.trim(), ...config }
}
function text(value: unknown): string {
  if (value == null) return ''
  if (typeof value !== 'string') throw new SshApiError('invalidResponse')
  return value
}
function responseData(body: unknown): unknown {
  if (!object(body) || body.success !== true || !Object.prototype.hasOwnProperty.call(body, 'data')) {
    throw new SshApiError('invalidResponse')
  }
  return body.data
}

/** Local InstanceDetails.id, not its OCI OCID. Only project connection fields. */
export async function getSshConfig(instanceId: string, signal?: AbortSignal): Promise<SshCredentials | null> {
  const id = localId(instanceId)
  try {
    const body = await tenantGet<unknown>(`/oci/ssh/config/${encodeURIComponent(id)}`, undefined, {
      signal, timeout: 30000, transformResponse: [decode],
    })
    const data = responseData(body)
    if (data === null) return null
    if (!object(data)) throw new SshApiError('invalidResponse')
    const port = data.port == null ? 22 : data.port
    if (!validPort(port)) throw new SshApiError('invalidResponse')
    return { host: text(data.host), port, username: text(data.username), password: text(data.sshPassword) }
  } catch (cause) { throw sshError(cause) }
}

/**
 * Host is derived from the current instance IP by the backend and is not saved.
 * POST returns the full instance entity; discard it and independently verify the
 * three saved fields because the create-connection service can swallow errors.
 * No mutation timeout, cancellation or automatic retry: a lost reply may still
 * mean the configuration was saved. A failed readback never repeats the POST.
 */
export async function saveSshConfig(instanceId: string, input: SshConfigInput): Promise<void> {
  const id = localId(instanceId)
  const value = configInput(input)
  let acknowledged = false
  try {
    const body = await tenantPost<unknown>('/oci/ssh/config', {
      instanceId: id, username: value.username, port: String(value.port), password: value.password,
    }, { timeout: 0, transformResponse: [decode] })
    if (!object(body) || body.success !== true) throw new SshApiError('invalidResponse')
    acknowledged = true
  } catch (cause) {
    const error = sshError(cause)
    throw new SshApiError(error.key, redactSshDetail(error.detail, value.password), true, acknowledged)
  }
  let saved: SshCredentials | null
  try { saved = await getSshConfig(id) } catch {
    // The successful write receipt must survive an unavailable readback.
    throw new SshApiError('saveUnverified', '', true, true)
  }
  if (!saved || saved.username !== value.username || saved.port !== value.port || saved.password !== value.password) {
    throw new SshApiError('saveMismatch', '', true, true)
  }
}

/** Same-origin session cookies are handled by WebSocket; no secrets in its URL. */
export function getSshWebSocketUrl(): string {
  return `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/ws/ssh`
}

export function redactSshDetail(value: string, password: string): string {
  return password ? value.split(password).join('[redacted]') : value
}
function detailText(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  return !detail || /^[<{\[]/.test(detail) ? '' : detail.slice(0, 1000)
}
export function sshError(cause: unknown): SshApiError {
  if (cause instanceof SshApiError) return cause
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new SshApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const code = object(body) ? String(body.code ?? '') : ''
  if ((httpError && cause.response?.status === 401) || code === '401') return new SshApiError('unauthorized')
  if ((httpError && cause.response?.status === 403) || code === '403') return new SshApiError('forbidden')
  let detail = detailText(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = detailText(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new SshApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
export function isSshSaveUncertain(cause: unknown): boolean { return sshError(cause).writeAttempted }
