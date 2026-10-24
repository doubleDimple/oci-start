import { isAxiosError, isCancel } from 'axios'
import { tenantGet } from './tenant'

export const OPEN_LOG_HISTORY_LINES = 300
/** Fixed, same-origin GET. Native EventSource owns framing, cookies and connection events. */
export const OPEN_LOG_STREAM_URL = '/system/streamLogs?isBootLog=true'
export const SYSTEM_LOG_STREAM_URL = '/system/streamLogs?isBootLog=false'

export type OpenLogsErrorKey = 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden'
export class OpenLogsApiError extends Error {
  constructor(public key: OpenLogsErrorKey, public detail = '') {
    super(key)
    this.name = 'OpenLogsApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new OpenLogsApiError('invalidResponse') }

// Log text is always a JSON string: consume strings first so numbers inside log
// messages remain unchanged. Any large numeric tokens outside them retain precision.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, (token: string, number?: string) => {
      return number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token
    }))
  } catch { return raw }
}

/**
 * Read recent log blocks in their original order, retaining blank lines.
 * The endpoint returns a bare {lines, count, error?}, not an ApiResponse envelope.
 * A complete block can exceed the requested 300 lines; display retention belongs
 * to the caller. Older server versions may swallow file errors and return [].
 */
async function loadLogHistory(path: string, signal?: AbortSignal): Promise<string[]> {
  try {
    const body = await tenantGet<unknown>(path, { lines: OPEN_LOG_HISTORY_LINES }, {
      transformResponse: [decode], timeout: 30000, signal,
    })
    if (!object(body)) return invalidResponse()
    if (body.error != null) {
      if (typeof body.error !== 'string') return invalidResponse()
      // The controller reports read failures in an otherwise successful HTTP 200.
      if (body.error.trim()) throw new OpenLogsApiError('requestFailed', detailText(body.error))
    }
    if (!Array.isArray(body.lines) || body.lines.some(line => typeof line !== 'string')
      || typeof body.count !== 'number' || !Number.isSafeInteger(body.count)
      || body.count < 0 || body.count !== body.lines.length) return invalidResponse()
    // Do not deduplicate or strip markers: identical log messages are valid entries.
    return body.lines.slice() as string[]
  } catch (cause) { throw openLogsError(cause) }
}

export function loadOpenLogHistory(signal?: AbortSignal): Promise<string[]> {
  return loadLogHistory('/system/openLogs/json', signal)
}

export function loadSystemLogHistory(signal?: AbortSignal): Promise<string[]> {
  return loadLogHistory('/system/logs/json', signal)
}

function detailText(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  // Never render a login document or proxy error page as a business error message.
  return !detail || /^[<{\[]/.test(detail) ? '' : detail.slice(0, 1000)
}

/** Retain display metadata only, without keeping response/request objects or log bodies. */
export function openLogsError(cause: unknown): OpenLogsApiError {
  if (cause instanceof OpenLogsApiError) return cause
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new OpenLogsApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const code = object(body) ? String(body.code ?? '') : ''
  if ((httpError && cause.response?.status === 401) || code === '401') return new OpenLogsApiError('unauthorized')
  if ((httpError && cause.response?.status === 403) || code === '403') return new OpenLogsApiError('forbidden')
  let detail = detailText(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = detailText(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new OpenLogsApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
