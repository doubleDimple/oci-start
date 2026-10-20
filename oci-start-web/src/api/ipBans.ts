import { tenantGet, tenantPost } from './tenant'
import { securitySettingsError } from './securitySettings'

export interface IpBanRecord {
  id: string
  ipAddress: string
  source: string
  operatorName: string
  reason: string
  status: 0 | 1
  createTime: string
  unbanTime: string
  unbanReason: string
  unbanOperatorName: string
}
export interface IpBanPage { items: IpBanRecord[]; total: number; page: number; size: number }
export interface IpBanQuery { page: number; size: number; status?: 0 | 1; ip?: string }
export type IpBanErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout' | 'cancelled'
  | 'unauthorized' | 'forbidden' | 'notFound'
export class IpBanApiError extends Error {
  constructor(public key: IpBanErrorKey, public detail = '') { super(key); this.name = 'IpBanApiError' }
}
const BASE = '/api/system/ip-bans'
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalid(): never { throw new IpBanApiError('invalidResponse') }
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalid() }
function integer(value: unknown, minimum: number): number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum ? value : invalid()
}
function id(value: unknown): string {
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) return String(value)
  return typeof value === 'string' && /^[1-9]\d*$/.test(value) ? value : invalid()
}
function unwrap(body: unknown): Record<string, unknown> {
  return object(body) && body.success === true && object(body.data) ? body.data : invalid()
}
// Keep database IDs exact even when the server serializes a long integer as a JSON number.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g,
      (token: string, number?: string) => number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token))
  } catch { return raw }
}
function record(value: unknown): IpBanRecord {
  if (!object(value) || (value.status !== 0 && value.status !== 1)) return invalid()
  const ipAddress = text(value.ipAddress)
  if (!ipAddress) return invalid()
  return {
    id: id(value.id), ipAddress, status: value.status, source: text(value.source),
    operatorName: text(value.operatorName), reason: text(value.reason), createTime: text(value.createTime),
    unbanTime: text(value.unbanTime), unbanReason: text(value.unbanReason), unbanOperatorName: text(value.unbanOperatorName),
  }
}
export function ipBanError(cause: unknown): IpBanApiError {
  if (cause instanceof IpBanApiError) return cause
  const error = securitySettingsError(cause)
  const keys: string[] = ['invalidInput', 'invalidResponse', 'requestFailed', 'timeout', 'cancelled', 'unauthorized', 'forbidden', 'notFound']
  return new IpBanApiError(keys.includes(error.key) ? error.key as IpBanErrorKey : 'requestFailed', error.detail)
}
export async function loadIpBans(query: IpBanQuery, signal?: AbortSignal): Promise<IpBanPage> {
  if (!Number.isSafeInteger(query.page) || query.page < 1 || !Number.isSafeInteger(query.size) || query.size < 1 || query.size > 100
    || (query.status !== undefined && query.status !== 0 && query.status !== 1) || (query.ip && query.ip.length > 64)) {
    throw new IpBanApiError('invalidInput')
  }
  try {
    const data = unwrap(await tenantGet<unknown>(BASE, {
      page: query.page, size: query.size,
      ...(query.status !== undefined ? { status: query.status } : {}),
      ...(query.ip?.trim() ? { ip: query.ip.trim() } : {}),
    }, { signal, timeout: 30000, transformResponse: [decode], headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' } }))
    if (!Array.isArray(data.items)) return invalid()
    const items = data.items.map(record)
    if (new Set(items.map(item => item.id)).size !== items.length) return invalid()
    return { items, total: integer(data.total, 0), page: integer(data.page, 1), size: integer(data.size, 1) }
  } catch (cause) { throw ipBanError(cause) }
}
/** Never abort or automatically retry an unban after submitting it. */
export async function unbanIp(recordId: string): Promise<{ changed: boolean; message: string }> {
  if (!/^[1-9]\d*$/.test(recordId)) throw new IpBanApiError('invalidInput')
  try {
    const data = unwrap(await tenantPost<unknown>(`${BASE}/${recordId}/unban`, undefined, { timeout: 0, transformResponse: [decode] }))
    if (typeof data.changed !== 'boolean') return invalid()
    return { changed: data.changed, message: text(data.message) }
  } catch (cause) { throw ipBanError(cause) }
}
