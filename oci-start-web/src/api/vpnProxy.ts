import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export interface VpnProxyRecord {
  id: string; customName: string; proxyType: string; proxyHost: string; proxyPort: number | null
  proxyUsername: string; hasPassword: boolean; availableStatus: 0 | 1 | null; forceProxy: 0 | 1 | null
  tenantIds: string[]; tenantName: string; createTime: string | null; updateTime: string | null
}
export interface VpnProxyTenant { id: string; name: string; region: string }
export interface VpnProxyInput {
  id?: string; customName: string; proxyType: string; proxyHost: string; proxyPort: number
  proxyUsername: string; proxyPassword?: string; availableStatus: 0 | 1; forceProxy: 0 | 1; tenantIds: string[]
}
export interface VpnProxyPage { records: VpnProxyRecord[]; page: number; size: number; total: number; totalPages: number }
export interface VpnProxyTestResult {
  id: string; connected: boolean | null; availableStatus: 0 | 1 | null; errorKey: 'configurationChanged' | null
  proxyHost: string; proxyPort: number | null; proxyType: string
}
export type VpnProxyErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden' | 'notFound' | 'saveMismatch' | 'limitExceeded' | 'configurationChanged'
export class VpnProxyApiError extends Error {
  constructor(public key: VpnProxyErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'VpnProxyApiError'
  }
}
const MAX_LONG = '9223372036854775807'
const MAX_COLLECTION = 100_000
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function invalid(): never { throw new VpnProxyApiError('invalidResponse') }
function badInput(): never { throw new VpnProxyApiError('invalidInput') }
export function isVpnProxyId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d*$/.test(value)
    && (value.length < MAX_LONG.length || (value.length === MAX_LONG.length && value <= MAX_LONG))
}
function id(value: unknown): string {
  const candidate = typeof value === 'number' && Number.isSafeInteger(value) ? String(value) : value
  return isVpnProxyId(candidate) ? candidate : invalid()
}
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalid() }
function flag(value: unknown): 0 | 1 | null { return value === 0 || value === 1 ? value : null }
function port(value: unknown): number | null { return typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 65535 ? value : null }
function count(value: unknown): number { return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : invalid() }
function ack(value: unknown): Record<string, unknown> { return object(value) && value.success === true ? value : invalid() }
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g,
      (token: string, number?: string) => number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token))
  } catch { return raw }
}
const readOptions = { timeout: 30_000, transformResponse: [decode], headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' } }
const writeOptions = { timeout: 0, transformResponse: [decode] }
function record(value: unknown): VpnProxyRecord {
  if (!object(value) || typeof value.hasPassword !== 'boolean') return invalid()
  const tenantIds = Array.isArray(value.tenantIds) ? value.tenantIds.map(id)
    : value.tenantId == null ? [] : [id(value.tenantId)]
  if (new Set(tenantIds).size !== tenantIds.length) return invalid()
  // Deliberately exclude any password field sent by a legacy server.
  return { id: id(value.id), customName: text(value.customName), proxyType: text(value.proxyType), proxyHost: text(value.proxyHost),
    proxyPort: port(value.proxyPort), proxyUsername: text(value.proxyUsername), hasPassword: value.hasPassword,
    availableStatus: flag(value.availableStatus), forceProxy: flag(value.forceProxy), tenantIds, tenantName: text(value.tenantName),
    createTime: value.createTime == null ? null : text(value.createTime), updateTime: value.updateTime == null ? null : text(value.updateTime) }
}
export async function fetchVpnProxyPage(page = 1, size = 10, signal?: AbortSignal): Promise<VpnProxyPage> {
  if (!Number.isSafeInteger(page) || page < 1 || !Number.isInteger(size) || size < 1 || size > 1000) return badInput()
  try {
    const data = ack(await tenantPost('/vpnProxy/pageList?redacted=true', { pageNum: page, pageSize: size, sort: 'id', order: 'desc' }, { ...readOptions, signal })).data
    if (!object(data) || !Array.isArray(data.content)) return invalid()
    const total = count(data.totalElements), totalPages = count(data.totalPages)
    if (count(data.number) !== page - 1 || count(data.size) !== size || totalPages !== Math.ceil(total / size)
      || data.content.length !== Math.max(0, Math.min(size, total - (page - 1) * size))) return invalid()
    const records = data.content.map(record)
    if (new Set(records.map(item => item.id)).size !== records.length) return invalid()
    return { records, page, size, total, totalPages }
  } catch (cause) { throw vpnProxyError(cause) }
}
/** Read a complete, stable ID collection before starting any bulk probe. */
export async function collectVpnProxyRecords(signal?: AbortSignal): Promise<VpnProxyRecord[]> {
  const records: VpnProxyRecord[] = [], seen = new Set<string>()
  let expectedTotal: number | undefined
  for (let page = 1; ; page += 1) {
    const result = await fetchVpnProxyPage(page, 200, signal)
    if (result.total > MAX_COLLECTION) throw new VpnProxyApiError('limitExceeded')
    if (expectedTotal !== undefined && result.total !== expectedTotal) return invalid()
    expectedTotal = result.total
    for (const item of result.records) {
      if (seen.has(item.id)) return invalid()
      seen.add(item.id); records.push(item)
    }
    if (page >= result.totalPages) {
      if (records.length !== result.total) return invalid()
      return records
    }
  }
}
export async function fetchVpnProxyTenants(signal?: AbortSignal): Promise<VpnProxyTenant[]> {
  try {
    const body: unknown = await tenantGet('/tenants/listParentTenants', undefined, { ...readOptions, signal })
    const data = Array.isArray(body) ? body : ack(body).data
    if (!Array.isArray(data)) return invalid()
    if (data.length > MAX_COLLECTION) throw new VpnProxyApiError('limitExceeded')
    const result = data.map(value => {
      if (!object(value)) return invalid()
      const localId = id(value.id)
      return { id: localId, name: text(value.tenancyName) || text(value.userName) || text(value.tenantId) || `#${localId}`, region: text(value.region) }
    })
    if (new Set(result.map(item => item.id)).size !== result.length) return invalid()
    return result
  } catch (cause) { throw vpnProxyError(cause) }
}
export async function fetchVpnProxyPassword(proxyId: string, signal?: AbortSignal): Promise<string | null> {
  if (!isVpnProxyId(proxyId)) return badInput()
  try {
    const data = ack(await tenantPost('/vpnProxy/password', { id: proxyId }, { ...readOptions, signal })).data
    if (!object(data) || id(data.id) !== proxyId || (data.proxyPassword !== null && typeof data.proxyPassword !== 'string')) return invalid()
    return data.proxyPassword
  } catch (cause) { throw vpnProxyError(cause) }
}
function inputText(value: unknown, max: number, trim = true): string {
  if (typeof value !== 'string') return badInput()
  const result = trim ? value.trim() : value
  if (result.length > max || /[\u0000-\u001f\u007f]/.test(result)) return badInput()
  return result
}
export function normalizeVpnProxyInput(input: VpnProxyInput, original?: VpnProxyRecord): VpnProxyInput {
  if (input.id !== undefined && (!isVpnProxyId(input.id) || !original || input.id !== original.id)) return badInput()
  const proxyType = inputText(input.proxyType, 20).toUpperCase()
  if (!['HTTP', 'HTTPS'].includes(proxyType)
    && !(input.id && proxyType === 'SOCKS5' && original?.proxyType.toUpperCase() === 'SOCKS5')) return badInput()
  const proxyHost = inputText(input.proxyHost, 128)
  if (!proxyHost || /[\s/?#@\\]/.test(proxyHost) || proxyHost.includes('://') || port(input.proxyPort) === null) return badInput()
  if (flag(input.availableStatus) === null || flag(input.forceProxy) === null || !Array.isArray(input.tenantIds)
    || input.tenantIds.some(value => !isVpnProxyId(value)) || new Set(input.tenantIds).size !== input.tenantIds.length) return badInput()
  return { ...(input.id === undefined ? {} : { id: input.id }), customName: inputText(input.customName, 128), proxyType,
    proxyHost, proxyPort: input.proxyPort, proxyUsername: inputText(input.proxyUsername, 64, false),
    ...(input.proxyPassword === undefined ? {} : { proxyPassword: inputText(input.proxyPassword, 128, false) }),
    availableStatus: input.availableStatus, forceProxy: input.forceProxy, tenantIds: [...input.tenantIds] }
}
async function write(path: string, payload: unknown): Promise<Record<string, unknown>> {
  try { return ack(await tenantPost(`/vpnProxy/${path}`, payload, writeOptions)) }
  catch (cause) { const failure = vpnProxyError(cause); throw new VpnProxyApiError(failure.key, '', true) }
}
export async function saveVpnProxy(input: VpnProxyInput, original?: VpnProxyRecord): Promise<void> {
  const payload = normalizeVpnProxyInput(input, original)
  await write('saveOrUpdate', payload)
}
export async function deleteVpnProxy(proxyId: string): Promise<void> {
  if (!isVpnProxyId(proxyId)) return badInput()
  await write('delete', { id: proxyId })
}
export async function setVpnProxyForce(proxyId: string, forceProxy: 0 | 1): Promise<void> {
  if (!isVpnProxyId(proxyId) || flag(forceProxy) === null) return badInput()
  await write('force', { id: proxyId, forceProxy })
}
/** This server-side probe also writes the recorded availability; it is not an abortable read. */
export async function testVpnProxy(proxyId: string): Promise<VpnProxyTestResult> {
  if (!isVpnProxyId(proxyId)) return badInput()
  try {
    const data = (await write('testConnection', { id: proxyId })).data
    if (!object(data) || id(data.id) !== proxyId) return invalid()
    const changed = data.connected === null && data.availableStatus === null && data.errorKey === 'configurationChanged'
    if (!changed && (typeof data.connected !== 'boolean' || data.availableStatus !== (data.connected ? 1 : 0)
      || data.errorKey != null)) return invalid()
    return { id: proxyId, connected: changed ? null : data.connected as boolean,
      availableStatus: changed ? null : data.availableStatus as 0 | 1, errorKey: changed ? 'configurationChanged' : null,
      proxyHost: text(data.proxyHost), proxyPort: port(data.proxyPort), proxyType: text(data.proxyType) }
  } catch (cause) { const failure = vpnProxyError(cause); throw new VpnProxyApiError(failure.key, '', true) }
}
export function vpnProxyError(cause: unknown): VpnProxyApiError {
  // Never retain response bodies, proxy credentials, Axios configuration or raw server exception text.
  if (cause instanceof VpnProxyApiError) return new VpnProxyApiError(cause.key, '', cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new VpnProxyApiError('cancelled')
  if (isAxiosError(cause)) {
    const status = cause.response?.status
    if (status === 401) return new VpnProxyApiError('unauthorized')
    if (status === 403) return new VpnProxyApiError('forbidden')
    if (status === 404) return new VpnProxyApiError('notFound')
    if (['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code ?? '')) return new VpnProxyApiError('timeout')
  }
  return new VpnProxyApiError('requestFailed')
}
