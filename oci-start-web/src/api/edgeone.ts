import { isAxiosError, isCancel } from 'axios'
import request from './request'
import { tenantCsrfToken, tenantGet, tenantPost, tenantPut } from './tenant'

export type EdgeOneMode = 'dns' | 'domain'
export interface EdgeOneZone { id: string; name: string; status: string }
export interface EdgeOneRecord {
  id: string
  type: string
  name: string
  content: string
  ttl: number | null
  priority: number | null
  status: string
  /** Origin protocol, not viewer HTTPS availability or certificate status. */
  originProtocol: string | null
}
export interface EdgeOneRecordInput {
  type: string
  name: string
  content: string
  ttl: number | null
  priority: number | null
}
export interface EdgeOneMutationResult { message: string; syncCount: number | null }
export type EdgeOneErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden' | 'recordRequired' | 'invalidTtl'
  | 'invalidPriority' | 'unsupportedType'
export class EdgeOneApiError extends Error {
  constructor(public key: EdgeOneErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'EdgeOneApiError'
  }
}

export const EDGEONE_TTLS = [300, 600, 1800, 3600, 7200, 18000, 43200, 86400] as const
const EDITABLE_TYPES = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SRV', 'PTR', 'SOA', 'CAA']
export function edgeOneCanEdit(type: string): boolean { return EDITABLE_TYPES.includes(type) }
export function isEdgeOneZoneId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9_-]+$/.test(value)
}
/** Preserve the SDK's original string identity without numeric coercion. */
export function isEdgeOneRecordId(value: unknown): value is string { return isEdgeOneZoneId(value) }
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function integer(value: unknown, min = 0, max = 2147483647): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max
}
function invalidResponse(): never { throw new EdgeOneApiError('invalidResponse') }
function text(value: unknown): string { return typeof value === 'string' ? value : invalidResponse() }
function nullableText(value: unknown): string | null { return value == null ? null : text(value) }
function identity(value: unknown): string { return isEdgeOneRecordId(value) ? value : invalidResponse() }
function requireZone(value: unknown): asserts value is string {
  if (!isEdgeOneZoneId(value)) throw new EdgeOneApiError('invalidInput')
}
function requireMode(value: unknown): asserts value is EdgeOneMode {
  if (value !== 'dns' && value !== 'domain') throw new EdgeOneApiError('invalidInput')
}
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try { return JSON.parse(raw) } catch { return raw }
}
function envelope(value: unknown): Record<string, unknown> {
  return object(value) && value.success === true ? value : invalidResponse()
}
function unique<T extends { id: string }>(values: T[]): T[] {
  if (new Set(values.map(value => value.id)).size !== values.length) return invalidResponse()
  return values
}
const readOptions = {
  timeout: 30000, transformResponse: [decode],
  headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' },
}
const writeOptions = { timeout: 0, transformResponse: [decode] }

export async function fetchEdgeOneZones(signal?: AbortSignal): Promise<EdgeOneZone[]> {
  try {
    const body = envelope(await tenantGet<unknown>('/dns/edgeone/api/zones', undefined, { ...readOptions, signal }))
    if (!Array.isArray(body.data)) return invalidResponse()
    return unique(body.data.map((value): EdgeOneZone => {
      if (!object(value)) return invalidResponse()
      return { id: identity(value.id), name: text(value.name), status: nullableText(value.status) || '' }
    }))
  } catch (cause) { throw edgeOneError(cause) }
}

/** Both modes return a complete cloud collection; filtering/paging is page-local. */
export async function fetchEdgeOneRecords(zoneId: string, mode: EdgeOneMode, signal?: AbortSignal): Promise<EdgeOneRecord[]> {
  requireZone(zoneId)
  requireMode(mode)
  try {
    const body = envelope(await tenantGet<unknown>('/dns/edgeone/api/records', { zoneId, type: mode }, { ...readOptions, signal }))
    if (!Array.isArray(body.data)) return invalidResponse()
    return unique(body.data.map((value): EdgeOneRecord => {
      if (!object(value)) return invalidResponse()
      if (mode === 'domain') {
        const name = text(value.domainName)
        const recordId = text(value.id)
        if (!name.trim() || value.zoneId !== zoneId || recordId !== `${zoneId}_${name}`) return invalidResponse()
        return {
          id: recordId, type: 'domain', name, content: nullableText(value.cname) || '',
          status: nullableText(value.status) || '', originProtocol: nullableText(value.originProtocol),
          ttl: null, priority: null,
        }
      }
      return {
        id: identity(value.id), type: text(value.type), name: text(value.name), content: text(value.content),
        ttl: integer(value.ttl, 1) ? value.ttl : null,
        priority: integer(value.priority, 0, 65535) ? value.priority : null,
        status: nullableText(value.status) || '', originProtocol: null,
      }
    }))
  } catch (cause) { throw edgeOneError(cause) }
}

async function mutate(send: () => Promise<unknown>, sync = false): Promise<EdgeOneMutationResult> {
  try {
    const body = envelope(await send())
    let syncCount: number | null = null
    if (sync) {
      const raw = object(body.data) ? body.data.syncCount : null
      const count = typeof raw === 'string' && /^\d+$/.test(raw) ? Number(raw) : raw
      if (!integer(count)) return invalidResponse()
      syncCount = count
    }
    return { message: safeDetail(body.message), syncCount }
  } catch (cause) {
    const problem = edgeOneError(cause)
    throw new EdgeOneApiError(problem.key, problem.detail, true)
  }
}

export async function updateEdgeOneRecord(zoneId: string, recordId: string, input: EdgeOneRecordInput): Promise<EdgeOneMutationResult> {
  requireZone(zoneId)
  if (!isEdgeOneRecordId(recordId)) throw new EdgeOneApiError('invalidInput')
  if (!input || typeof input.type !== 'string' || typeof input.name !== 'string' || typeof input.content !== 'string'
    || !input.name.trim() || !input.content.trim()) throw new EdgeOneApiError('recordRequired')
  if (!edgeOneCanEdit(input.type)) throw new EdgeOneApiError('unsupportedType')
  if (input.ttl !== null && !integer(input.ttl, 1)) throw new EdgeOneApiError('invalidTtl')
  if (input.priority !== null && !integer(input.priority, 0, 65535)) throw new EdgeOneApiError('invalidPriority')
  const data: Record<string, unknown> = {
    zoneId, recordType: input.type, recordName: input.name, content: input.content.trim(),
  }
  if (input.ttl !== null) data.ttl = input.ttl
  if (input.type === 'MX' && input.priority !== null) data.priority = input.priority
  return mutate(() => tenantPut(`/dns/edgeone/api/records/${encodeURIComponent(recordId)}`, data, writeOptions))
}

function deleteRequest(path: string, params: Record<string, string>): Promise<unknown> {
  const headers: Record<string, string> = {}
  const token = tenantCsrfToken()
  const name = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
  if (token) headers[name] = token
  return request.delete(path, { ...writeOptions, params, headers, silent: true })
}
export async function deleteEdgeOneRecord(zoneId: string, recordId: string): Promise<EdgeOneMutationResult> {
  requireZone(zoneId)
  if (!isEdgeOneRecordId(recordId)) throw new EdgeOneApiError('invalidInput')
  return mutate(() => deleteRequest(`/dns/edgeone/api/records/${encodeURIComponent(recordId)}`, { zoneId }))
}
export async function deleteEdgeOneDomain(zoneId: string, recordId: string, domainName: string): Promise<EdgeOneMutationResult> {
  requireZone(zoneId)
  if (typeof domainName !== 'string' || !domainName.trim() || recordId !== `${zoneId}_${domainName}`) {
    throw new EdgeOneApiError('invalidInput')
  }
  return mutate(() => deleteRequest(`/dns/edgeone/api/domains/${encodeURIComponent(recordId)}`, { zoneId, domainName }))
}
export async function syncEdgeOneRecords(zoneId: string, domainName: string, mode: EdgeOneMode): Promise<EdgeOneMutationResult> {
  requireZone(zoneId)
  requireMode(mode)
  if (typeof domainName !== 'string' || !domainName.trim()) throw new EdgeOneApiError('invalidInput')
  const endpoint = mode === 'dns' ? 'sync' : 'sync-domains'
  return mutate(() => tenantPost(`/dns/edgeone/api/zones/${encodeURIComponent(zoneId)}/${endpoint}`, { zoneId, domainName }, writeOptions), true)
}

function safeDetail(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  if (!detail || /[<>{}\[\]\r\n]/.test(detail) || /https?:\/\//i.test(detail)
    || /(?:api[ _-]?(?:key|token)|secret[ _-]?(?:id|key)|authorization|password)\s*[:=]/i.test(detail)) return ''
  return detail.slice(0, 1000)
}
export function edgeOneError(cause: unknown): EdgeOneApiError {
  if (cause instanceof EdgeOneApiError) return new EdgeOneApiError(cause.key, safeDetail(cause.detail), cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new EdgeOneApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const code = object(body) ? String(body.code ?? '') : ''
  if ((httpError && cause.response?.status === 401) || code === '401') return new EdgeOneApiError('unauthorized')
  if ((httpError && cause.response?.status === 403) || code === '403') return new EdgeOneApiError('forbidden')
  let detail = safeDetail(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = safeDetail(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code || '')
  return new EdgeOneApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
