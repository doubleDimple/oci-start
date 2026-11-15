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
export type CloudflareIpFamily = 'IPv4' | 'IPv6'
export interface CloudflarePublicIpRecord {
  id: string
  zoneName: string
  type: 'A' | 'AAAA'
  name: string
  proxied: boolean | null
}
export interface CloudflarePublicIpGroup {
  ip: string
  family: CloudflareIpFamily
  records: CloudflarePublicIpRecord[]
}
export interface CloudflarePublicIpsResult {
  groups: CloudflarePublicIpGroup[]
  zones: string[]
  totalRecords: number
}
export interface CloudflareOfficialIpEntry {
  cidr: string
  family: CloudflareIpFamily
}
export type CloudflareOfficialIpsSource = 'live' | 'builtin'
export interface CloudflareOfficialIpsResult {
  ipv4: string[]
  ipv6: string[]
  entries: CloudflareOfficialIpEntry[]
  etag: string
  source: CloudflareOfficialIpsSource
}
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
export const CLOUDFLARE_OFFICIAL_IPV4_CIDRS = [
  '103.21.244.0/22',
  '103.22.200.0/22',
  '103.31.4.0/22',
  '104.16.0.0/13',
  '104.24.0.0/14',
  '108.162.192.0/18',
  '131.0.72.0/22',
  '141.101.64.0/18',
  '162.158.0.0/15',
  '172.64.0.0/13',
  '173.245.48.0/20',
  '188.114.96.0/20',
  '190.93.240.0/20',
  '197.234.240.0/22',
  '198.41.128.0/17',
] as const
export const CLOUDFLARE_OFFICIAL_IPV6_CIDRS = [
  '2400:cb00::/32',
  '2405:8100::/32',
  '2405:b500::/32',
  '2606:4700::/32',
  '2803:f800::/32',
  '2a06:98c0::/29',
  '2c0f:f248::/32',
] as const
const EDITABLE_TYPES: readonly string[] = [...CLOUDFLARE_RECORD_TYPES, 'NS', 'SRV', 'PTR', 'SOA', 'CAA']
const PAGE_SIZES = [10, 20, 30, 50]
const MAX_INT = 2147483647

export function isCloudflareId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9_-]+$/.test(value)
}
export function cloudflareCanProxy(type: string): boolean { return ['A', 'AAAA', 'CNAME'].includes(type) }
export function cloudflareCanEdit(type: string): boolean { return EDITABLE_TYPES.includes(type) }

function parseIpv4(raw: string): [number, number, number, number] | null {
  const parts = raw.split('.')
  if (parts.length !== 4) return null
  const octets: number[] = []
  for (const part of parts) {
    if (!/^(?:0|[1-9]\d{0,2})$/.test(part)) return null
    const value = Number(part)
    if (value < 0 || value > 255) return null
    octets.push(value)
  }
  return octets as [number, number, number, number]
}

function isPublicIpv4(octets: [number, number, number, number]): boolean {
  const [a, b, c] = octets
  if (a === 0 || a === 10 || a === 127 || a >= 224) return false
  if (a === 100 && b >= 64 && b <= 127) return false
  if (a === 169 && b === 254) return false
  if (a === 172 && b >= 16 && b <= 31) return false
  if (a === 192 && b === 0 && (c === 0 || c === 2)) return false
  if (a === 192 && b === 168) return false
  if (a === 198 && (b === 18 || b === 19)) return false
  if (a === 198 && b === 51 && c === 100) return false
  if (a === 203 && b === 0 && c === 113) return false
  return true
}

function parseIpv6(raw: string): number[] | null {
  if (!raw.includes(':')) return null
  const doubleColonParts = raw.split('::')
  if (doubleColonParts.length > 2) return null

  const parseSegmentList = (part: string, allowTrailingV4: boolean): number[] | null => {
    if (!part) return []
    const tokens = part.split(':')
    const result: number[] = []
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i]!
      if (!token) return null
      if (allowTrailingV4 && i === tokens.length - 1 && token.includes('.')) {
        const v4 = parseIpv4(token)
        if (!v4) return null
        result.push((v4[0] << 8) | v4[1], (v4[2] << 8) | v4[3])
      } else {
        if (!/^[0-9a-fA-F]{1,4}$/.test(token)) return null
        result.push(Number.parseInt(token, 16))
      }
    }
    return result
  }

  if (doubleColonParts.length === 1) {
    const groups = parseSegmentList(doubleColonParts[0]!, true)
    return groups && groups.length === 8 ? groups : null
  }
  const head = parseSegmentList(doubleColonParts[0]!, false)
  const tail = parseSegmentList(doubleColonParts[1]!, true)
  if (!head || !tail) return null
  const missing = 8 - head.length - tail.length
  if (missing < 1) return null
  return [...head, ...Array<number>(missing).fill(0), ...tail]
}

function isPublicIpv6(groups: number[]): boolean {
  const s0 = groups[0]!
  const s1 = groups[1]!
  // Unspecified (::) and loopback (::1)
  if (groups.slice(0, 7).every(g => g === 0) && (groups[7] === 0 || groups[7] === 1)) return false
  // IPv4-mapped (::ffff:w.x.y.z) and IPv4-compatible (::w.x.y.z)
  if (groups.slice(0, 5).every(g => g === 0) && (groups[5] === 0xffff || groups[5] === 0)) {
    const w = groups[6]!
    const x = groups[7]!
    return isPublicIpv4([w >> 8, w & 0xff, x >> 8, x & 0xff])
  }
  // Unique local fc00::/7, link-local fe80::/10, multicast ff00::/8
  if ((s0 & 0xfe00) === 0xfc00 || (s0 & 0xffc0) === 0xfe80 || (s0 & 0xff00) === 0xff00) return false
  // Documentation 2001:db8::/32 and discard 100::/64
  if (s0 === 0x2001 && s1 === 0x0db8) return false
  if (s0 === 0x0100 && s1 === 0 && groups[2] === 0 && groups[3] === 0) return false
  return true
}

export function classifyPublicIp(raw: string): CloudflareIpFamily | null {
  const value = raw.trim()
  if (!value) return null
  const v4 = parseIpv4(value)
  if (v4) return isPublicIpv4(v4) ? 'IPv4' : null
  const v6 = parseIpv6(value)
  if (v6) return isPublicIpv6(v6) ? 'IPv6' : null
  return null
}
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

export async function fetchCloudflareAllPublicIps(signal?: AbortSignal): Promise<CloudflarePublicIpsResult> {
  try {
    const body = envelope(await tenantGet<unknown>('/dns/cloudflare/api/records/all', undefined, { ...readOptions, timeout: 60000, signal }))
    if (!object(body.data)) return invalidResponse()
    const grouped = new Map<string, CloudflarePublicIpGroup>()
    const zonesWithIps = new Set<string>()
    let totalRecords = 0

    for (const [zoneName, rawList] of Object.entries(body.data)) {
      if (!Array.isArray(rawList)) return invalidResponse()
      for (const raw of rawList) {
        if (!object(raw)) return invalidResponse()
        const type = typeof raw.type === 'string' ? raw.type.toUpperCase() : ''
        if (type !== 'A' && type !== 'AAAA') continue
        const ip = typeof raw.content === 'string' ? raw.content.trim() : ''
        const family = classifyPublicIp(ip)
        if (!family || (type === 'A' && family !== 'IPv4') || (type === 'AAAA' && family !== 'IPv6')) continue

        const entry: CloudflarePublicIpRecord = {
          id: typeof raw.id === 'string' && raw.id ? raw.id : `${zoneName}:${type}:${raw.name}:${ip}`,
          zoneName,
          type,
          name: typeof raw.name === 'string' && raw.name.trim() ? raw.name.trim() : zoneName,
          proxied: typeof raw.proxied === 'boolean' ? raw.proxied : null,
        }
        zonesWithIps.add(zoneName)
        totalRecords += 1
        const existing = grouped.get(ip)
        if (existing) existing.records.push(entry)
        else grouped.set(ip, { ip, family, records: [entry] })
      }
    }

    const groups = Array.from(grouped.values()).sort((a, b) => a.family === b.family ? a.ip.localeCompare(b.ip) : a.family.localeCompare(b.family))
    for (const group of groups) {
      group.records.sort((a, b) => a.zoneName.localeCompare(b.zoneName) || a.name.localeCompare(b.name))
    }
    return { groups, zones: Array.from(zonesWithIps).sort(), totalRecords }
  } catch (cause) { throw cloudflareError(cause) }
}

function normalizeCidrList(raw: unknown, fallback: readonly string[]): string[] {
  if (!Array.isArray(raw)) return [...fallback]
  const seen = new Set<string>()
  const list: string[] = []
  for (const item of raw) {
    if (typeof item !== 'string') continue
    const trimmed = item.trim()
    if (!trimmed || seen.has(trimmed)) continue
    seen.add(trimmed)
    list.push(trimmed)
  }
  return list.length ? list : [...fallback]
}

function buildOfficialIpsResult(
  ipv4: string[],
  ipv6: string[],
  etag: string,
  source: CloudflareOfficialIpsSource,
): CloudflareOfficialIpsResult {
  const entries: CloudflareOfficialIpEntry[] = [
    ...ipv4.map(cidr => ({ cidr, family: 'IPv4' as const })),
    ...ipv6.map(cidr => ({ cidr, family: 'IPv6' as const })),
  ]
  return { ipv4, ipv6, entries, etag, source }
}

export async function fetchCloudflareOfficialIps(signal?: AbortSignal): Promise<CloudflareOfficialIpsResult> {
  try {
    const body = envelope(await tenantGet<unknown>('/dns/cloudflare/api/official-ips', undefined, {
      ...readOptions,
      timeout: 12000,
      signal,
    }))
    if (!object(body.data)) {
      return buildOfficialIpsResult([...CLOUDFLARE_OFFICIAL_IPV4_CIDRS], [...CLOUDFLARE_OFFICIAL_IPV6_CIDRS], '', 'builtin')
    }
    const ipv4 = normalizeCidrList(body.data.ipv4, CLOUDFLARE_OFFICIAL_IPV4_CIDRS)
    const ipv6 = normalizeCidrList(body.data.ipv6, CLOUDFLARE_OFFICIAL_IPV6_CIDRS)
    const etag = typeof body.data.etag === 'string' ? body.data.etag.trim() : ''
    const source: CloudflareOfficialIpsSource = body.data.source === 'live' ? 'live' : 'builtin'
    return buildOfficialIpsResult(ipv4, ipv6, etag, source)
  } catch (cause) {
    const parsed = cloudflareError(cause)
    if (parsed.key === 'cancelled') throw parsed
    return buildOfficialIpsResult([...CLOUDFLARE_OFFICIAL_IPV4_CIDRS], [...CLOUDFLARE_OFFICIAL_IPV6_CIDRS], '', 'builtin')
  }
}

export function formatCloudflareNginxRealIpConfig(cidrs: readonly string[]): string {
  const lines = cidrs
    .map(cidr => cidr.trim())
    .filter(Boolean)
    .map(cidr => `set_real_ip_from ${cidr};`)
  if (!lines.length) return ''
  return `${lines.join('\n')}\nreal_ip_header CF-Connecting-IP;`
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
