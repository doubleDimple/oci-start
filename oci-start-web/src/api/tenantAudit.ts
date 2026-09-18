import { isAxiosError } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export interface TenantAuditRow {
  userName: string
  ipAddress: string
  eventType: string
  clientEnv: string
  eventTime: string
  responseStatus: string
}
export interface TenantAuditPage { rows: TenantAuditRow[]; nextToken: string | null }
export interface TenantAuditContext { name: string; region: string }
export interface TenantAuditDates { startDate: string; endDate: string }
export class TenantAuditResponseError extends Error {}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function text(value: unknown): string {
  if (value == null) return ''
  if (typeof value !== 'string') throw new TenantAuditResponseError()
  return value
}
export function isAuditTenantId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < 19 || value <= '9223372036854775807')
}

export async function getTenantAuditPage(
  tenantId: string, dates: TenantAuditDates, pageToken: string | null, signal: AbortSignal,
): Promise<TenantAuditPage> {
  if (!isAuditTenantId(tenantId)) throw new TenantAuditResponseError()
  const body = await tenantPost<unknown>('/tenants/audit/log', { tenantId, ...dates, pageToken }, { signal, timeout: 120000 })
  if (!object(body) || body.success !== true || !object(body.data) || !Array.isArray(body.data.data)) throw new TenantAuditResponseError()
  return {
    rows: body.data.data.map((value): TenantAuditRow => {
      if (!object(value)) throw new TenantAuditResponseError()
      return {
        userName: text(value.userName), ipAddress: text(value.ipAddress), eventType: text(value.eventType),
        clientEnv: text(value.clientEnv), eventTime: text(value.eventTime), responseStatus: text(value.responseStatus),
      }
    }),
    nextToken: text(body.data.nextPageToken) || null,
  }
}

/** Resolve the exact selected account using string IDs. Names are never used to choose a tenant. */
export async function getTenantAuditContext(tenantId: string, signal: AbortSignal): Promise<TenantAuditContext | null> {
  if (!isAuditTenantId(tenantId)) throw new TenantAuditResponseError()
  const body = await tenantGet<unknown>('/tenants/regionList/json', { tenantId }, { signal })
  if (!Array.isArray(body)) throw new TenantAuditResponseError()
  const row = body.find(value => object(value) && (value.idStr === tenantId || value.id === tenantId ||
    (typeof value.id === 'number' && Number.isSafeInteger(value.id) && String(value.id) === tenantId)))
  if (!object(row)) return null
  return { name: text(row.defName) || text(row.tenancyName) || text(row.userName), region: text(row.region) || text(row.regionEn) }
}

export function tenantAuditServerError(cause: unknown): string {
  if (cause instanceof TenantAuditResponseError) return ''
  const body = isAxiosError(cause) ? cause.response?.data : cause
  if (object(body)) {
    for (const key of ['message', 'error', 'msg']) if (typeof body[key] === 'string' && body[key]) return body[key]
  }
  return ''
}
