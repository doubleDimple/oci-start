import { isAxiosError, isCancel } from 'axios'
import { tenantGet } from './tenant'

export const DELAY_PROBE_TIMEOUT_MS = 10000

export interface DelayRegion {
  /** Region code, not a numeric tenant/resource ID. */
  code: string
  name: string
  simpleName: string
  endpoint: string
}
export interface DelayClientIp {
  raw: string
  /** Address observed by the app server for this request, including proxy headers. */
  ip: string
  location: string
}
export type DelayMeasurement = { status: 'success'; latencyMs: number }
  | { status: 'timeout' | 'failed'; latencyMs: null }
export type DelayTestErrorKey = 'invalidInput' | 'invalidResponse' | 'invalidEndpoint'
  | 'requestFailed' | 'timeout' | 'cancelled'
export class DelayTestApiError extends Error {
  constructor(public key: DelayTestErrorKey, public detail = '') {
    super(key)
    this.name = 'DelayTestApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new DelayTestApiError('invalidResponse') }
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalidResponse() }
function regionCode(value: unknown): value is string {
  return typeof value === 'string' && /^[a-z]{2}-[a-z0-9]+(?:-[a-z0-9]+)*-[1-9]\d*$/.test(value)
}

/** Validate the initial public Object Storage URL; opaque responses hide the final URL. */
function endpointUrl(code: unknown, endpoint: unknown): string {
  if (!regionCode(code) || typeof endpoint !== 'string' || /[?#@]/.test(endpoint)) {
    throw new DelayTestApiError('invalidEndpoint')
  }
  try {
    const url = new URL(endpoint)
    // URL normalizes an explicit HTTPS :443 to an empty port and a missing path to '/'.
    if (url.protocol !== 'https:' || url.hostname !== `objectstorage.${code}.oraclecloud.com`
      || url.port || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
      throw new Error()
    }
    return url.href
  } catch { throw new DelayTestApiError('invalidEndpoint') }
}

// The current DTO has textual region codes and no Long identifiers. Preserve any
// large integer JSON tokens before parsing anyway; never turn them into rounded IDs.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, (token: string, number?: string) => {
      return number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token
    }))
  } catch { return raw }
}
const readConfig = { transformResponse: [decode], timeout: 30000 }
function accepted(body: unknown): Record<string, unknown> {
  // The shared client handles authentication and rejects business errors first.
  if (!object(body) || body.success !== true) return invalidResponse()
  return body
}

export async function listDelayRegions(signal?: AbortSignal): Promise<DelayRegion[]> {
  try {
    const body = accepted(await tenantGet<unknown>('/api/getOracleEndpoint', undefined, { ...readConfig, signal }))
    if (!Array.isArray(body.data)) return invalidResponse()
    const rows: DelayRegion[] = []
    for (const value of body.data) {
      if (!object(value)) return invalidResponse()
      const endpoint = text(value.endpoint)
      // Both RegionEnum.getAllRegion and the old page exclude empty endpoints.
      if (!endpoint) continue
      if (!regionCode(value.code)) return invalidResponse()
      rows.push({
        code: value.code, name: text(value.name), simpleName: text(value.simpleName),
        endpoint: endpointUrl(value.code, endpoint),
      })
    }
    if (new Set(rows.map(row => row.code)).size !== rows.length) return invalidResponse()
    return rows
  } catch (cause) { throw delayTestError(cause) }
}

export async function getDelayClientIp(signal?: AbortSignal): Promise<DelayClientIp> {
  try {
    const body = accepted(await tenantGet<unknown>('/api/getCurrentIp', undefined, { ...readConfig, signal }))
    if (typeof body.data !== 'string') return invalidResponse()
    const raw = body.data
    const separator = raw.indexOf('/')
    // A successful empty string is possible when the server could not read the IP.
    // Split once so the rest of the location remains data, never HTML or a URL.
    return separator >= 0
      ? { raw, ip: raw.slice(0, separator).trim(), location: raw.slice(separator + 1).trim() }
      : { raw, ip: raw.replace(/_/g, '.').trim(), location: '' }
  } catch (cause) { throw delayTestError(cause) }
}

/**
 * One browser HEAD sample. The caller owns the legacy second sample/minimum rule,
 * bounded parallel regions and run generation. Nothing is probed just by importing this module.
 * An opaque no-cors response records completion time, not HTTP status or service health.
 * Its final URL is also unavailable, so this cannot validate a redirect destination.
 */
export async function measureDelayRegion(
  region: DelayRegion,
  signal?: AbortSignal,
  timeoutMs = DELAY_PROBE_TIMEOUT_MS,
): Promise<DelayMeasurement> {
  if (!region || !Number.isSafeInteger(timeoutMs) || timeoutMs <= 0 || timeoutMs > 2147483647) {
    throw new DelayTestApiError('invalidInput')
  }
  const endpoint = endpointUrl(region.code, region.endpoint)
  if (signal?.aborted) throw new DelayTestApiError('cancelled')
  const controller = new AbortController()
  const cancel = () => controller.abort()
  signal?.addEventListener('abort', cancel, { once: true })
  let timedOut = false
  const startedAt = performance.now()
  const timer = setTimeout(() => { timedOut = true; controller.abort() }, timeoutMs)
  try {
    // Keep external requests separate from tenantGet: no session credentials,
    // CSRF tokens, authorization or app-specific headers may leave this origin.
    // no-cors requires redirect:'follow'; 'error' or 'manual' rejects the request.
    // The opaque response cannot reveal the final redirect URL or HTTP status.
    await fetch(endpoint, {
      method: 'HEAD', mode: 'no-cors', cache: 'no-cache', referrerPolicy: 'no-referrer',
      credentials: 'omit', redirect: 'follow', signal: controller.signal,
    })
    if (signal?.aborted) throw new DelayTestApiError('cancelled')
    const elapsed = performance.now() - startedAt
    if (timedOut || elapsed >= timeoutMs) return { status: 'timeout', latencyMs: null }
    if (!Number.isFinite(elapsed) || elapsed < 0) return { status: 'failed', latencyMs: null }
    // Do not inspect response.ok/status: cross-origin opaque responses have status 0.
    return { status: 'success', latencyMs: Math.round(elapsed) }
  } catch (cause) {
    if (signal?.aborted || (cause instanceof DelayTestApiError && cause.key === 'cancelled')) {
      throw new DelayTestApiError('cancelled')
    }
    return { status: timedOut ? 'timeout' : 'failed', latencyMs: null }
  } finally {
    clearTimeout(timer)
    signal?.removeEventListener('abort', cancel)
  }
}

function detailText(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  return !detail || /^[<{\[]/.test(detail) ? '' : detail.slice(0, 1000)
}

export function delayTestError(cause: unknown): DelayTestApiError {
  if (cause instanceof DelayTestApiError) return cause
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new DelayTestApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  let detail = detailText(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = detailText(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new DelayTestApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
