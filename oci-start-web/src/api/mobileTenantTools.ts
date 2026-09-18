import { tenantGet, type TenantRow } from './tenant'

export type MobileTenantTool = 'users' | 'volumes' | 'security' | 'mysql'
export type MobileTenantContextError = 'invalidTenant' | 'invalidResponse' | 'notFound' | 'unsupportedCloud'

export class MobileTenantToolError extends Error {
  constructor(readonly key: MobileTenantContextError) {
    super(key)
    this.name = 'MobileTenantToolError'
  }
}

export function isMobileTenantId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < 19 || value <= '9223372036854775807')
}

export function isMobileTenantTool(value: unknown): value is MobileTenantTool {
  return typeof value === 'string' && ['users', 'volumes', 'security', 'mysql'].includes(value)
}

function object(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value)
}

function rowId(row: Record<string, unknown>): string {
  // idStr preserves Java Long values that cannot be represented by a JS number.
  if (isMobileTenantId(row.idStr)) return row.idStr
  if (isMobileTenantId(row.id)) return row.id
  if (typeof row.id === 'number' && Number.isSafeInteger(row.id) && row.id > 0) return String(row.id)
  return ''
}

function text(value: unknown): string {
  if (value == null) return ''
  if (typeof value !== 'string') throw new MobileTenantToolError('invalidResponse')
  return value
}

/** Resolve the exact legacy deep link; never select an account by its query-string name. */
export async function getMobileTenantToolContext(tenantId: string, signal: AbortSignal): Promise<TenantRow> {
  if (!isMobileTenantId(tenantId)) throw new MobileTenantToolError('invalidTenant')
  const body = await tenantGet<unknown>('/tenants/regionList/json', { tenantId }, { signal })
  if (!Array.isArray(body)) throw new MobileTenantToolError('invalidResponse')
  const matches = body.filter(value => object(value) && rowId(value) === tenantId)
  if (!matches.length) throw new MobileTenantToolError('notFound')
  if (matches.length !== 1 || !object(matches[0])) throw new MobileTenantToolError('invalidResponse')
  const row = matches[0]
  if (row.cloudType !== 1 && row.cloudType !== '1') throw new MobileTenantToolError('unsupportedCloud')
  // Keep only the fields these tools need; the legacy entity can contain credentials.
  return {
    id: tenantId,
    cloudType: 1,
    defName: text(row.defName),
    tenancyName: text(row.tenancyName),
    userName: text(row.userName),
    region: text(row.region) || text(row.regionEn),
  }
}
