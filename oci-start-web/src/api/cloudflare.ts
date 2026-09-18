import { isAxiosError, isCancel } from 'axios'
import request from './request'
import { tenantCsrfToken, tenantGet, tenantPost, tenantPut } from './tenant'

export interface CloudflareZone { id: string; name: string; status: string }
export interface CloudflareRecord {
  id: string
  type: string
  name: string
  content: string
  contentEditable: boolean | null
  ttl: number | null
  proxied: boolean | null
  priority: number | null
}
export interface CloudflarePage {
  records: CloudflareRecord[]
  total: number
  /** Cloudflare API pages start at 1; the old page URL starts at 0. */
  page: number
  size: number
  totalPages: number
}
export interface CloudflareQuery {
  zoneId: string
  page: number
  size: number
  searchName?: string
  searchContent?: string
}
export interface CloudflareRecordInput {
  type: string
  name: string
  content: string
  ttl: number | null
  proxied: boolean | null
  priority: number | null
}
export interface CloudflareMutationResult { message: string; syncCount: number | null }
export type CloudflareErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden' | 'recordRequired' | 'invalidTtl'
  | 'invalidPriority' | 'unsupportedType'
export class CloudflareApiError extends Error {
  constructor(public key: CloudflareErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'CloudflareApiError'
  }
}

export const CLOUDFLARE_RECORD_TYPES = ['A', 'AAAA', 'CNAME', 'MX', 'TXT'] as const
export const CLOUDFLARE_TTLS = [1, 300, 600, 1800, 3600, 7200, 18000, 43200, 86400] as const
const EDITABLE_TYPES: readonly string[] = [...CLOUDFLARE_RECORD_TYPES, 'NS', 'SRV', 'PTR', 'SOA', 'CAA']
const PAGE_SIZES = [10, 20, 30, 50]
const MAX_INT = 2147483647

export function isCloudflareId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9_-]+$/.test(value)
}
export function cloudflareCanProxy(type: string): boolean { return ['A', 'AAAA', 'CNAME'].includes(type) }
export function cloudflareCanEdit(type: string): boolean { return EDITABLE_TYPES.includes(type) }
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new CloudflareApiError('invalidResponse') }
function integer(value: unknown, min = 0, max = MAX_INT): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max
}
function text(value: unknown): string { return typeof value === 'string' ? value : invalidResponse() }
function id(value: unknown): string { return isCloudflareId(value) ? value : invalidResponse() }
function requireId(value: unknown): asserts value is string {
  if (!isCloudflareId(value)) throw new CloudflareApiError('invalidInput')
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

export async function fetchCloudflareZones(signal?: AbortSignal): Promise<CloudflareZone[]> {
  try {
    const body = envelope(await tenantGet<unknown>('/dns/cloudflare/api/zones', undefined, { ...readOptions, signal }))
    if (!Array.isArray(body.data)) return invalidResponse()
    return unique(body.data.map((raw): CloudflareZone => {
      if (!object(raw)) return invalidResponse()
      return { id: id(raw.id), name: text(raw.name), status: text(raw.status) }
    }))
  } catch (cause) { throw cloudflareError(cause) }
}

export async function fetchCloudflareRecords(query: CloudflareQuery, signal?: AbortSignal): Promise<CloudflarePage> {
  requireId(query.zoneId)
  if (!integer(query.page, 1) || !PAGE_SIZES.includes(query.size)
    || (query.searchName !== undefined && typeof query.searchName !== 'string')
    || (query.searchContent !== undefined && typeof query.searchContent !== 'string')) throw new CloudflareApiError('invalidInput')
  try {
    const body = envelope(await tenantGet<unknown>(`/dns/cloudflare/api/zones/${encodeURIComponent(query.zoneId)}/records`, {
      page: query.page, size: query.size,
      searchName: query.searchName?.trim() || undefined, searchContent: query.searchContent?.trim() || undefined,
    }, { ...readOptions, signal }))
    const page = body.data
    if (!object(page) || !Array.isArray(page.content) || !integer(page.totalElements)
      || !integer(page.totalPages) || !integer(page.number) || !integer(page.size, 1)
      || page.size !== query.size || page.number + 1 !== query.page) return invalidResponse()
    const records = unique(page.content.map((raw): CloudflareRecord => {
      if (!object(raw)) return invalidResponse()
      return {
        id: id(raw.id), type: text(raw.type), name: text(raw.name), content: text(raw.content),
        contentEditable: typeof raw.contentEditable === 'boolean' ? raw.contentEditable : null,
        ttl: integer(raw.ttl, 1) ? raw.ttl : null,
        proxied: typeof raw.proxied === 'boolean' ? raw.proxied : null,
        priority: integer(raw.priority, 0, 65535) ? raw.priority : null,
      }
    }))
    if (records.length > page.size || records.length > page.totalElements
      || (page.totalElements > 0 && page.totalPages === 0)) return invalidResponse()
    return { records, total: page.totalElements, page: page.number + 1, size: page.size, totalPages: page.totalPages }
  } catch (cause) { throw cloudflareError(cause) }
}

function recordPayload(input: CloudflareRecordInput, editing: boolean): Record<string, unknown> {
  if (!input || typeof input.type !== 'string' || typeof input.name !== 'string' || typeof input.content !== 'string'
    || !input.name.trim() || !input.content.trim()) throw new CloudflareApiError('recordRequired')
  if (editing ? !cloudflareCanEdit(input.type) : !(CLOUDFLARE_RECORD_TYPES as readonly string[]).includes(input.type)) {
    throw new CloudflareApiError('unsupportedType')
  }
  if (!integer(input.ttl, 1)) throw new CloudflareApiError('invalidTtl')
  if (input.proxied !== null && typeof input.proxied !== 'boolean') throw new CloudflareApiError('invalidInput')
  if (input.priority !== null && !integer(input.priority, 0, 65535)) throw new CloudflareApiError('invalidPriority')
  if (!editing && input.type === 'MX' && input.priority === null) throw new CloudflareApiError('invalidPriority')
  const result: Record<string, unknown> = editing
    ? { recordType: input.type, recordName: input.name, content: input.content.trim(), ttl: input.ttl }
    : { type: input.type, name: input.name.trim(), content: input.content.trim(), ttl: input.ttl }
  // Omitted edit fields preserve the real cloud record, including uneditable data.
  if (cloudflareCanProxy(input.type) && input.proxied !== null) result.proxied = input.proxied
  if (input.type === 'MX' && input.priority !== null) result.priority = input.priority
  return result
}

async function mutate(send: () => Promise<unknown>, sync = false): Promise<CloudflareMutationResult> {
  try {
    const body = envelope(await send())
    let syncCount: number | null = null
    if (sync) {
      const raw = object(body.data) ? body.data.syncCount : null
      const value = typeof raw === 'string' && /^\d+$/.test(raw) ? Number(raw) : raw
      if (!integer(value)) return invalidResponse()
      syncCount = value
    }
    return { message: safeDetail(body.message), syncCount }
  } catch (cause) {
    const problem = cloudflareError(cause)
    // Cloud DNS may have changed even if its local persistence or reply failed.
    throw new CloudflareApiError(problem.key, problem.detail, true)
  }
}
export async function createCloudflareRecord(zoneId: string, input: CloudflareRecordInput): Promise<CloudflareMutationResult> {
  requireId(zoneId)
  const data = { zoneId, ...recordPayload(input, false) }
  return mutate(() => tenantPost('/dns/cloudflare/api/records', data, writeOptions))
}
export async function updateCloudflareRecord(zoneId: string, recordId: string, input: CloudflareRecordInput): Promise<CloudflareMutationResult> {
  requireId(zoneId)
  requireId(recordId)
  const data = { zoneId, ...recordPayload(input, true) }
  return mutate(() => tenantPut(`/dns/cloudflare/api/records/${encodeURIComponent(recordId)}`, data, writeOptions))
}
export async function deleteCloudflareRecord(zoneId: string, recordId: string): Promise<CloudflareMutationResult> {
  requireId(zoneId)
  requireId(recordId)
  const headers: Record<string, string> = {}
  const token = tenantCsrfToken()
  const csrfHeader = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
  if (token) headers[csrfHeader] = token
  return mutate(() => request.delete(`/dns/cloudflare/api/records/${encodeURIComponent(recordId)}`, {
    ...writeOptions, params: { zoneId }, headers, silent: true,
  }))
}
export async function syncCloudflareRecords(zoneId: string, domainName: string): Promise<CloudflareMutationResult> {
  requireId(zoneId)
  if (typeof domainName !== 'string' || !domainName.trim()) throw new CloudflareApiError('invalidInput')
  return mutate(() => tenantPost(`/dns/cloudflare/api/zones/${encodeURIComponent(zoneId)}/sync`, {
    zoneId, domainName,
  }, writeOptions), true)
}

function safeDetail(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  if (!detail || /[<>{}\[\]\r\n]/.test(detail) || /https?:\/\//i.test(detail)
    || /(?:api[ _-]?(?:key|token)|secret[ _-]?(?:id|key)|authorization|password)\s*[:=]/i.test(detail)) return ''
  return detail.slice(0, 1000)
}
export function cloudflareError(cause: unknown): CloudflareApiError {
  if (cause instanceof CloudflareApiError) return new CloudflareApiError(cause.key, safeDetail(cause.detail), cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new CloudflareApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const code = object(body) ? String(body.code ?? '') : ''
  if ((httpError && cause.response?.status === 401) || code === '401') return new CloudflareApiError('unauthorized')
  if ((httpError && cause.response?.status === 403) || code === '403') return new CloudflareApiError('forbidden')
  let detail = safeDetail(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = safeDetail(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code || '')
  return new CloudflareApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
