import { tenantGet, type TenantRow } from '@/api/tenant'

export type TenantPermission =
  | 'BASIC_READ' | 'INSTANCE_POWER' | 'INSTANCE_CREATE' | 'INSTANCE_DELETE'
  | 'INSTANCE_UPDATE' | 'INSTANCE_REINSTALL' | 'BOOT_VOLUME_DELETE' | 'BLOCK_VOLUME_DELETE'
  | 'VOLUME_MANAGE' | 'NETWORK_MANAGE' | 'REGION_SUBSCRIBE' | 'COST_READ' | 'TRAFFIC_READ'
  | 'AUDIT_READ' | 'MYSQL_READ' | 'MYSQL_MANAGE' | 'USER_READ' | 'USER_CREATE' | 'USER_DELETE'
  | 'USER_PASSWORD_RESET' | 'DOMAIN_SECURITY_MANAGE' | 'DOMAIN_USER_MANAGE'

type PermissionSubject = Pick<TenantRow, 'permissionMode' | 'permissionsJson'> | null | undefined

export function isManagedTenant(tenant: PermissionSubject): boolean {
  return Boolean(tenant?.permissionMode)
}

/** Unknown and malformed managed grants fail closed; existing imports retain their behaviour. */
export function hasTenantPermission(tenant: PermissionSubject, permission: TenantPermission): boolean {
  if (!tenant) return false
  if (!isManagedTenant(tenant)) return true
  if (tenant.permissionMode !== 'managed-v1') return false
  try {
    const grants: unknown = JSON.parse(tenant.permissionsJson || '[]')
    return Array.isArray(grants) && grants.every(value => typeof value === 'string')
      && grants.includes('BASIC_READ') && grants.includes(permission)
  } catch { return false }
}

export async function loadTenantPermissionContext(id: string, signal?: AbortSignal): Promise<TenantRow> {
  const rows = await tenantGet<TenantRow[]>('/tenants/regionList/json', { tenantId: id }, { signal })
  const row = Array.isArray(rows) ? rows.find(value => String(value.idStr || value.id) === id) : undefined
  if (!row) throw new Error('无法读取租户权限 / Unable to read tenant permissions')
  return { ...row, id }
}

export async function loadInstancePermissionContext(instanceId: string, signal?: AbortSignal): Promise<TenantRow> {
  const body = await tenantGet<{ success: boolean; data?: TenantRow }>('/tenants/permissions/instance-context', { instanceId }, { signal })
  if (body.success !== true || !body.data) {
    throw new Error('无法读取实例所属租户权限 / Unable to read instance permissions')
  }
  // Non-OCI hosts can have no tenant. Only the server's explicit persisted classification permits this.
  if (body.data.nonOci === true) return { id: String(body.data.id || ''), nonOci: true, permissionMode: '' }
  if (typeof body.data.id !== 'string' || !/^[1-9]\d*$/.test(body.data.id)) {
    throw new Error('无法读取实例所属租户权限 / Unable to read instance permissions')
  }
  return body.data
}

export const instanceActionPermissions: Record<string, TenantPermission> = {
  start: 'INSTANCE_POWER', stop: 'INSTANCE_POWER', terminate: 'INSTANCE_DELETE',
  config: 'INSTANCE_UPDATE', name: 'INSTANCE_UPDATE', volume: 'VOLUME_MANAGE', vpu: 'VOLUME_MANAGE',
  ip: 'NETWORK_MANAGE', ipv6: 'NETWORK_MANAGE', network: 'NETWORK_MANAGE',
  reinstall: 'INSTANCE_REINSTALL', console: 'INSTANCE_REINSTALL', ssh: 'INSTANCE_REINSTALL',
}

export function allowsInstanceAction(tenant: PermissionSubject, action: string): boolean {
  const permission = instanceActionPermissions[action]
  return permission ? hasTenantPermission(tenant, permission) : true
}
