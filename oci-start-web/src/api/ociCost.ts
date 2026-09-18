import { isAxiosError } from 'axios'
import { tenantPost } from './tenant'

export interface OciCostQuery {
  tenantId: string
  startDate: string
  endDate: string
}

export interface OciCostRow {
  day: string
  resourceType: string
  resourceId: string
  skuName: string
  cost: number
  cloudType: number
}

export type OciCostCategory = 'compute' | 'storage' | 'network' | 'other'
export type OciCostErrorKey = 'invalidTenant' | 'invalidDate' | 'reversedDates' | 'invalidResponse' | 'requestFailed' | 'timeout'

export class OciCostError extends Error {
  constructor(public key: OciCostErrorKey, public detail = '') {
    super(key)
  }
}

export function isCostTenantId(value: unknown): value is string {
  const maximum = '9223372036854775807'
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < maximum.length || value <= maximum)
}

export function isCostDate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const date = new Date(`${value}T00:00:00Z`)
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
}

/** Preserve the category rules from the active oci_cost.js implementation. */
export function costCategory(resourceType: string): OciCostCategory {
  switch (resourceType.toLowerCase()) {
    case 'instance': return 'compute'
    case 'boot-volume': case 'block-volume': return 'storage'
    case 'vnic': return 'network'
    default: return 'other'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function optionalText(value: unknown): string {
  if (value == null) return ''
  if (typeof value !== 'string') throw new OciCostError('invalidResponse')
  return value
}

function parseRow(value: unknown): OciCostRow {
  if (!object(value) || !isCostDate(value.day)
    || !Number.isInteger(value.cloudType)
    || !['string', 'number'].includes(typeof value.cost)
    || String(value.cost).trim() === '') throw new OciCostError('invalidResponse')
  const cost = Number(value.cost)
  if (!Number.isFinite(cost)) throw new OciCostError('invalidResponse')
  return {
    day: value.day,
    cloudType: value.cloudType as number,
    resourceId: optionalText(value.resourceId),
    resourceType: optionalText(value.resourceType) || 'unknown',
    skuName: optionalText(value.skuName),
    cost,
  }
}

export async function queryOciCost(query: OciCostQuery, signal: AbortSignal): Promise<OciCostRow[]> {
  if (!isCostTenantId(query.tenantId)) throw new OciCostError('invalidTenant')
  if (!isCostDate(query.startDate) || !isCostDate(query.endDate)) throw new OciCostError('invalidDate')
  if (query.startDate > query.endDate) throw new OciCostError('reversedDates')
  const result = await tenantPost<unknown>('/cost/query', query, { signal, timeout: 120000 })
  if (!object(result) || result.success !== true || !Array.isArray(result.data)) throw new OciCostError('invalidResponse')
  const rows = result.data.map(parseRow)
  if (rows.some(row => row.day < query.startDate || row.day > query.endDate)
    || !Number.isFinite(rows.reduce((sum, row) => sum + Math.abs(row.cost), 0))) throw new OciCostError('invalidResponse')
  return rows.sort((first, second) => first.day.localeCompare(second.day))
}

export function ociCostError(cause: unknown): OciCostError {
  if (cause instanceof OciCostError) return cause
  if (isAxiosError(cause) && ['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code || '')) return new OciCostError('timeout')
  const body = isAxiosError(cause) ? cause.response?.data : cause
  const detail = object(body) && typeof body.message === 'string' ? body.message
    : object(body) && typeof body.msg === 'string' ? body.msg : ''
  return new OciCostError('requestFailed', detail)
}
