import { isAxiosError, isCancel } from 'axios'
import { tenantGet } from './tenant'

export interface MetricServer {
  /** Probe-defined identity; neither an InstanceDetails Long nor an OCI OCID. */
  serverId: string
  serverIp: string | null
  online: boolean | null
  cpuUsage: number | null
  memoryUsage: number | null
  diskUsage: number | null
  cpuCores: number | null
  totalMemory: number | null
  totalDisk: number | null
  /** Preserve probe-reported text: the endpoint does not provide a reliable unit. */
  totalUploadTraffic: string | null
  totalDownloadTraffic: string | null
  /** Server-local receipt times, formatted yyyy-MM-dd HH:mm:ss without a timezone. */
  lastCheckTime: string | null
  lastConnectionTime: string | null
}

export type MetricsErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed'
  | 'timeout' | 'cancelled' | 'unauthorized' | 'forbidden'

export class MetricsApiError extends Error {
  constructor(
    public key: MetricsErrorKey,
    public detail = '',
    /** True once deletion was attempted; an error then cannot prove that no rows were removed. */
    public writeAttempted = false,
  ) {
    super(key)
    this.name = 'MetricsApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new MetricsApiError('invalidResponse') }
export function isMetricServerId(value: unknown): value is string {
  return typeof value === 'string' && !!value.trim() && !value.includes('\0')
}
function nullableText(value: unknown): string | null {
  return typeof value === 'string' ? value : null
}
function nullableBoolean(value: unknown): boolean | null {
  return typeof value === 'boolean' ? value : null
}
function nonnegativeNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? value : null
}
function percentage(value: unknown): number | null {
  const number = nonnegativeNumber(value)
  return number == null || number <= 100 ? number : null
}
function cores(value: unknown): number | null {
  const number = nonnegativeNumber(value)
  return number == null || (Number.isInteger(number) && number <= 2147483647)
    ? number : null
}

// This DTO has no numeric Long identity: serverId is a probe-defined JSON string.
// Never coerce a JSON number into an ID; an invalid numeric identity stays unknown.
// Valid digit-only string IDs therefore retain their original precision and bytes.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try { return JSON.parse(raw) } catch { return raw }
}

function metricServer(value: unknown): MetricServer {
  if (!object(value)) return invalidResponse()
  return {
    serverId: typeof value.serverId === 'string' ? value.serverId : '',
    serverIp: nullableText(value.serverIp),
    online: nullableBoolean(value.online),
    cpuUsage: percentage(value.cpuUsage),
    memoryUsage: percentage(value.memoryUsage),
    diskUsage: percentage(value.diskUsage),
    cpuCores: cores(value.cpuCores),
    totalMemory: nonnegativeNumber(value.totalMemory),
    totalDisk: nonnegativeNumber(value.totalDisk),
    totalUploadTraffic: nullableText(value.totalUploadTraffic),
    totalDownloadTraffic: nullableText(value.totalDownloadTraffic),
    lastCheckTime: nullableText(value.lastCheckTime),
    lastConnectionTime: nullableText(value.lastConnectionTime),
  }
}

/** Latest probe reports only: no tenant, instance, pagination or time-range parameters. */
export async function fetchMetrics(signal?: AbortSignal): Promise<MetricServer[]> {
  try {
    const body = await tenantGet<unknown>('/api/metrics/status', undefined, {
      transformResponse: [decode], timeout: 30000, signal,
      headers: { 'Cache-Control': 'no-cache', Pragma: 'no-cache' },
    })
    if (!Array.isArray(body)) return invalidResponse()
    // findAll has no ordering/uniqueness guarantee. Preserve duplicate reports:
    // deletion addresses all rows with that exact ID, never a rendering index.
    return body.map(metricServer)
  } catch (cause) { throw metricsError(cause) }
}

/**
 * Legacy GET mutation: deletes local monitoring records, not the server or its
 * probe. A later report may recreate the entry. There is no retry, abort signal
 * or short timeout; callers distinguish this receipt from a subsequent read.
 */
export async function deleteMetricServer(serverId: string): Promise<void> {
  if (!isMetricServerId(serverId)) throw new MetricsApiError('invalidInput')
  try {
    const body = await tenantGet<unknown>('/api/metrics/deleteMetrics', { serverId }, {
      transformResponse: [decode], timeout: 0,
      headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' },
    })
    // HTTP 200, an empty body, or an HTML login page is not a deletion receipt.
    if (!object(body) || body.success !== true) return invalidResponse()
  } catch (cause) {
    const error = metricsError(cause)
    throw new MetricsApiError(error.key, error.detail, true)
  }
}

function detailText(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  // Never surface a login document, proxy HTML or serialized payload as a message.
  return !detail || /^[<{\[]/.test(detail) ? '' : detail.slice(0, 1000)
}

/** Keep display metadata only; never retain an Axios request or raw response body. */
export function metricsError(cause: unknown): MetricsApiError {
  if (cause instanceof MetricsApiError) return cause
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) {
    return new MetricsApiError('cancelled')
  }
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const code = object(body) ? String(body.code ?? '') : ''
  if ((httpError && cause.response?.status === 401) || code === '401') return new MetricsApiError('unauthorized')
  if ((httpError && cause.response?.status === 403) || code === '403') return new MetricsApiError('forbidden')
  let detail = detailText(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = detailText(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new MetricsApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
