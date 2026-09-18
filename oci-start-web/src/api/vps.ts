import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export interface VpsRow {
  /** Local record identity. Monitor mutations and SSH navigation use this ID. */
  id: string
  /** Cloud/machine identity used by the monitoring WebSocket token. */
  instanceId: string
  tenantId: string
  displayName: string
  publicIps: string
  tenancyName: string
  regionName: string
  regionCode: string
  architecture: string
  cloudType: number | null
  ocpus: number | null
  memoryInGBs: number | null
  bootVolumeSizeInGBs: number | null
  onLineEnable: 0 | 1 | null
  enablePing: 0 | 1 | null
  monitorInstalled: boolean | null
  /** Epoch milliseconds. Older installations may have initialized this without a report. */
  lastHeartbeat: number | null
}
export type VpsOperationKind = 'install' | 'uninstall' | 'enablePing' | 'disablePing' | 'ping'
export interface VpsMutationResult { message: string }
export type VpsErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed'
  | 'timeout' | 'cancelled' | 'unauthorized' | 'forbidden'
export class VpsApiError extends Error {
  constructor(public key: VpsErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'VpsApiError'
  }
}

const PAGE_SIZE = 200
const MAX_LONG = '9223372036854775807'
export function isVpsLocalId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < MAX_LONG.length || value <= MAX_LONG)
}
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new VpsApiError('invalidResponse') }
function integer(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
}
function quantity(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value > 0
    && value <= Number.MAX_SAFE_INTEGER ? value : null
}
function text(value: unknown): string {
  if (value == null) return ''
  return typeof value === 'string' ? value : invalidResponse()
}
function flag(value: unknown): 0 | 1 | null { return value === 0 || value === 1 ? value : null }
function row(value: unknown): VpsRow {
  if (!object(value) || !isVpsLocalId(value.id)) return invalidResponse()
  // The legacy DTO defaults its primitive tenant ID to zero for an unknown owner.
  const tenantId = value.tenantId === '0' ? '' : text(value.tenantId)
  if (tenantId && !isVpsLocalId(tenantId)) return invalidResponse()
  // Legacy list defaults are placeholders, not an assigned IP or a known architecture.
  const publicIps = text(value.publicIps).trim()
  const architecture = text(value.architecture).trim()
  return {
    id: value.id, instanceId: text(value.instanceId), tenantId,
    displayName: text(value.displayName), publicIps: publicIps === '0.0.0.0' ? '' : publicIps,
    tenancyName: text(value.tenancyName),
    regionName: text(value.regionName), regionCode: text(value.regionCode), architecture: architecture === 'NONE' ? '' : architecture,
    cloudType: integer(value.cloudType) ? value.cloudType : null,
    ocpus: quantity(value.ocpus), memoryInGBs: quantity(value.memoryInGBs),
    bootVolumeSizeInGBs: quantity(value.bootVolumeSizeInGBs),
    onLineEnable: flag(value.onLineEnable), enablePing: flag(value.enablePing),
    monitorInstalled: typeof value.monitorInstalled === 'boolean' ? value.monitorInstalled : null,
    lastHeartbeat: integer(value.lastHeartbeat) && value.lastHeartbeat <= 8_640_000_000_000_000
      ? value.lastHeartbeat : null,
  }
}
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try { return JSON.parse(raw) } catch { return raw }
}

/** Publish only a complete, internally consistent collection across all vendors. */
export async function fetchVpsInstances(tenantId = '', signal?: AbortSignal): Promise<VpsRow[]> {
  if (tenantId && !isVpsLocalId(tenantId)) throw new VpsApiError('invalidInput')
  const rows: VpsRow[] = []
  const identities = new Set<string>()
  let total: number | undefined
  let pages = 1
  try {
    for (let page = 0; page < pages; ++page) {
      if (signal?.aborted) throw new VpsApiError('cancelled')
      const body = await tenantGet<unknown>('/vps/instances/list/json', {
        page, size: PAGE_SIZE, tenantId: tenantId || undefined,
      }, {
        signal, timeout: 30000, transformResponse: [decode],
        headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' },
      })
      if (!object(body) || !Array.isArray(body.content)
        || !integer(body.currentPage) || body.currentPage !== page
        || body.size !== PAGE_SIZE || !integer(body.totalElements) || !integer(body.totalPages)
        || body.totalPages !== Math.ceil(body.totalElements / PAGE_SIZE)
        || (total !== undefined && body.totalElements !== total)) return invalidResponse()
      total = body.totalElements
      pages = Math.max(1, body.totalPages)
      const expected = Math.min(PAGE_SIZE, Math.max(0, total - page * PAGE_SIZE))
      if (body.content.length !== expected) return invalidResponse()
      for (const value of body.content) {
        const item = row(value)
        if (identities.has(item.id) || (tenantId && item.tenantId !== tenantId)) return invalidResponse()
        identities.add(item.id)
        rows.push(item)
      }
    }
    if (rows.length !== total) return invalidResponse()
    return rows
  } catch (cause) { throw vpsError(cause) }
}

/** Never abort or retry a submitted command. Ping actions always address all OCI instances. */
export async function runVpsOperation(kind: VpsOperationKind, rowId?: string): Promise<VpsMutationResult> {
  if (!['install', 'uninstall', 'enablePing', 'disablePing', 'ping'].includes(kind)) throw new VpsApiError('invalidInput')
  const monitor = kind === 'install' || kind === 'uninstall'
  if (monitor && !isVpsLocalId(rowId)) throw new VpsApiError('invalidInput')
  const path = monitor ? `/api/monitor/${kind}` : `/vps/instances/${kind}`
  const data = monitor ? new URLSearchParams({ vpsId: rowId! }) : undefined
  try {
    const body = await tenantPost<unknown>(path, data, {
      timeout: 0, transformResponse: [decode],
      headers: monitor ? { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' } : undefined,
    })
    if (!object(body) || body.success !== true) return invalidResponse()
    return { message: safeDetail(body.message) }
  } catch (cause) {
    const problem = vpsError(cause)
    throw new VpsApiError(problem.key, problem.detail, true)
  }
}

function safeDetail(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  if (!detail || /[<>{}\[\]\r\n]/.test(detail) || /https?:\/\//i.test(detail)
    || /(?:api[ _-]?(?:key|token)|secret[ _-]?(?:id|key)|authorization|password|rootPassword)\s*[:=]/i.test(detail)) return ''
  return detail.slice(0, 1000)
}
/** Project display fields only; do not keep raw responses, SSH settings or credentials. */
export function vpsError(cause: unknown): VpsApiError {
  if (cause instanceof VpsApiError) return new VpsApiError(cause.key, safeDetail(cause.detail), cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new VpsApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const code = object(body) ? String(body.code ?? '') : ''
  if ((httpError && cause.response?.status === 401) || code === '401') return new VpsApiError('unauthorized')
  if ((httpError && cause.response?.status === 403) || code === '403') return new VpsApiError('forbidden')
  let detail = safeDetail(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = safeDetail(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code || '')
  return new VpsApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
