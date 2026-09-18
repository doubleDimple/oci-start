import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export interface ConsoleMetadata {
  /** Local InstanceDetails.id, never the OCI OCID. */
  instanceId: string
  ociInstanceId: string
  /** Local Tenant.id, derived from the instance record by the backend. */
  tenantId: string
  instanceIp: string
  instanceName: string
}

export type ConsoleErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed'
  | 'timeout' | 'cancelled' | 'unauthorized' | 'forbidden' | 'notFound' | 'endpointUnavailable' | 'invalidContext'
  | 'socketFailed' | 'connectionFailed' | 'preparationTimeout' | 'vncTimeout'
  | 'invalidMessage' | 'outputOverflow' | 'idleTimeout' | 'vncDisconnected'

/** Display metadata only; never retain raw requests, responses or connection secrets. */
export class ConsoleApiError extends Error {
  constructor(
    public key: ConsoleErrorKey,
    public detail = '',
    public writeAttempted = false,
  ) {
    super(key)
    this.name = 'ConsoleApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

/** Exact positive Java Long IDs; numeric conversion would corrupt large identifiers. */
export function isConsoleInstanceId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && value.trim() === value
    && (value.length < 19 || value <= '9223372036854775807')
}

function isOciInstanceId(value: unknown): value is string {
  return typeof value === 'string' && value.startsWith('ocid1.instance.')
    && value.length > 'ocid1.instance.'.length && !/[\s\x00-\x1f\x7f]/.test(value)
}

function isMetadata(value: unknown): value is ConsoleMetadata {
  return object(value) && isConsoleInstanceId(value.instanceId)
    && isConsoleInstanceId(value.tenantId) && isOciInstanceId(value.ociInstanceId)
    && typeof value.instanceIp === 'string' && typeof value.instanceName === 'string'
}

/** A local database read: no console creation, cloud request or credential retrieval. */
export async function getConsoleMetadata(instanceId: string, signal?: AbortSignal): Promise<ConsoleMetadata> {
  if (!isConsoleInstanceId(instanceId)) throw new ConsoleApiError('invalidInput')
  try {
    const body = await tenantGet<unknown>(`/oci/console/metadata/${encodeURIComponent(instanceId)}`, undefined, {
      signal, timeout: 30000,
    })
    if (!object(body) || body.success !== true || !isMetadata(body.data)
      || body.data.instanceId !== instanceId) throw new ConsoleApiError('invalidResponse')
    const data = body.data
    // Project the contract explicitly even if a future response includes additional fields.
    return {
      instanceId: data.instanceId,
      ociInstanceId: data.ociInstanceId,
      tenantId: data.tenantId,
      instanceIp: data.instanceIp,
      instanceName: data.instanceName,
    }
  } catch (cause) { throw consoleError(cause) }
}

/**
 * The legacy controller accepts a reset into an asynchronous task. A successful
 * response only acknowledges submission, not a completed instance restart.
 * No cancellation, mutation timeout or retry: a missing response may still mean
 * the reset was submitted. All errors after issuing the POST retain that fact.
 */
export async function restartConsoleInstance(metadata: ConsoleMetadata): Promise<void> {
  if (!isMetadata(metadata)) throw new ConsoleApiError('invalidInput')
  try {
    const body = await tenantPost<unknown>('/oci/console/heavyNewRestart', {
      instanceId: metadata.ociInstanceId,
      tenantId: metadata.tenantId,
    }, { timeout: 0 })
    if (!object(body) || body.success !== true) throw new ConsoleApiError('invalidResponse')
  } catch (cause) {
    const error = consoleError(cause)
    throw new ConsoleApiError(error.key, error.detail, true)
  }
}

function pageLocation(): Location {
  if (typeof window === 'undefined'
    || !['http:', 'https:'].includes(window.location.protocol)) throw new ConsoleApiError('invalidInput')
  return window.location
}

/** Same-origin session cookies are handled by the browser's WebSocket connection. */
export function getConsoleControlUrl(): string {
  const location = pageLocation()
  return `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws/console`
}

/**
 * Keep the existing deployment contract: HTTP uses this host's websockify port;
 * HTTPS requires the same-origin /websockify/{port} reverse proxy. Never trust a
 * returned remote hostname or URL, and preserve bracketed IPv6 literals.
 */
export function getVncUrl(port: number): string {
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new ConsoleApiError('invalidInput')
  const location = pageLocation()
  if (location.protocol === 'https:') return `wss://${location.host}/websockify/${port}`
  const hostname = location.hostname.includes(':') && !location.hostname.startsWith('[')
    ? `[${location.hostname}]` : location.hostname
  return `ws://${hostname}:${port}/`
}

function detailText(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  // A login document or proxy response is not a business error message.
  return !detail || /^[<{\[]/.test(detail) ? '' : detail.slice(0, 1000)
}

export function consoleError(cause: unknown): ConsoleApiError {
  if (cause instanceof ConsoleApiError) return cause
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new ConsoleApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const status = httpError ? cause.response?.status : undefined
  const code = object(body) ? String(body.code ?? '') : ''
  if (status === 401 || code === '401') return new ConsoleApiError('unauthorized')
  if (status === 403 || code === '403') return new ConsoleApiError('forbidden')
  // Metadata errors are machine keys so the UI can consistently translate them.
  if (object(body)) {
    const key = body.errorKey
    if (key === 'invalidInput' || key === 'invalidContext' || key === 'notFound' || key === 'requestFailed') {
      return new ConsoleApiError(key)
    }
  }
  // Only the metadata endpoint's explicit errorKey above establishes that the
  // instance is missing. A generic 404 can mean an older backend has no route.
  if (status === 404) return new ConsoleApiError('endpointUnavailable')
  let detail = detailText(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = detailText(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new ConsoleApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
