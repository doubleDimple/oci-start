import { isAxiosError } from 'axios'
import { i18n } from '@/i18n'
import { tenantGet } from './tenant'

export interface InstanceRow {
  /** Local record ID. Most /oci mutations call this field tenantId. */
  id: string
  tenantId: string
  /** OCI OCID. Used by VNIC navigation, never by local-record mutations. */
  instanceId: string
  displayName: string
  tenancyName: string
  userName: string
  state: string
  availabilityDomain?: string
  compartmentId?: string
  shape: string
  architecture: string
  processorDescription: string
  regionName: string
  regionCode: string
  ocpus: number | null
  memoryInGBs: number | null
  bootVolumeSizeInGBs: number | null
  vpusPerGB: number | null
  bootVolumeId: string
  bootVolumeName?: string
  publicIps: string
  privateIps: string
  ipv6Addresses: string
  remark: string
  createTime: string | number | null
}

export interface InstanceTenant {
  id: string
  tenantId: string
  userName: string
  tenancyName: string
  region: string
}

class InstanceResponseError extends Error {
  constructor() { super('instances.invalidResponse') }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

export function isInstanceTenantId(value: unknown): value is string {
  const max = '9223372036854775807'
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < max.length || value <= max)
}

function identifier(value: unknown): string {
  if (isInstanceTenantId(value)) return value
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) return String(value)
  throw new InstanceResponseError()
}

function text(value: unknown): string {
  if (value == null) return ''
  if (typeof value !== 'string') throw new InstanceResponseError()
  return value
}

function quantity(value: unknown): number | null {
  if (value == null || value === '') return null
  if (typeof value !== 'number' && typeof value !== 'string') throw new InstanceResponseError()
  const parsed = Number(value)
  if (!Number.isFinite(parsed) || parsed < 0) throw new InstanceResponseError()
  return parsed
}

function row(value: unknown): InstanceRow {
  if (!object(value)) throw new InstanceResponseError()
  const created = value.createTime
  if (created != null && typeof created !== 'string' && typeof created !== 'number') throw new InstanceResponseError()
  return {
    id: identifier(value.id), tenantId: identifier(value.tenantIdStr || value.tenantId),
    instanceId: text(value.instanceId), displayName: text(value.displayName),
    tenancyName: text(value.tenancyName), userName: text(value.userName), state: text(value.state),
    availabilityDomain: text(value.availabilityDomain), compartmentId: text(value.compartmentId),
    shape: text(value.shape), architecture: text(value.architecture), processorDescription: text(value.processorDescription),
    regionName: text(value.regionName), regionCode: text(value.regionCode),
    ocpus: quantity(value.ocpus), memoryInGBs: quantity(value.memoryInGBs),
    bootVolumeSizeInGBs: quantity(value.bootVolumeSizeInGBs), vpusPerGB: quantity(value.vpusPerGB === 'null' ? null : value.vpusPerGB),
    bootVolumeId: text(value.bootVolumeId), bootVolumeName: text(value.bootVolumeName),
    publicIps: text(value.publicIps), privateIps: text(value.privateIps),
    ipv6Addresses: text(value.ipv6Addresses), remark: text(value.remark), createTime: created ?? null,
  }
}

export async function getInstances(page: number, size: number, tenantId: string, signal: AbortSignal) {
  if (tenantId && !isInstanceTenantId(tenantId)) throw new InstanceResponseError()
  const body = await tenantGet<unknown>('/oci/list/json', { page, size, tenantId: tenantId || undefined }, { signal })
  if (!object(body) || !Array.isArray(body.content)
    || ![body.currentPage, body.totalPages, body.totalElements, body.size].every(value => typeof value === 'number' && Number.isSafeInteger(value) && value >= 0)
    || body.currentPage !== page || body.size !== size) throw new InstanceResponseError()
  const rows = body.content.map(row)
  if (new Set(rows.map(value => value.id)).size !== rows.length) throw new InstanceResponseError()
  return { rows, total: body.totalElements as number, totalPages: body.totalPages as number }
}

function tenants(body: unknown): InstanceTenant[] {
  if (!Array.isArray(body)) throw new InstanceResponseError()
  return body.map(value => {
    if (!object(value)) throw new InstanceResponseError()
    return { id: identifier(value.id), tenantId: text(value.tenantId), userName: text(value.userName), tenancyName: text(value.tenancyName), region: text(value.region) }
  })
}

export async function getInstanceTenants(signal: AbortSignal) {
  return tenants(await tenantGet<unknown>('/tenants/listParentTenants', undefined, { signal }))
}

export async function getInstanceRegions(parentId: string, signal: AbortSignal) {
  if (!isInstanceTenantId(parentId)) throw new InstanceResponseError()
  return tenants(await tenantGet<unknown>('/tenants/listRegions', { parentId }, { signal }))
}

/** Resolve a regional deep link using local account metadata, without cloud synchronization. */
export async function getInstanceParent(regionId: string, parents: InstanceTenant[], signal: AbortSignal): Promise<string> {
  const direct = parents.find(parent => parent.id === regionId)
  if (direct) return direct.id
  const body = await tenantGet<unknown>('/tenants/regionList/json', { tenantId: regionId }, { signal })
  if (!Array.isArray(body)) throw new InstanceResponseError()
  const region = body.find(value => object(value) && (value.idStr === regionId || value.id === regionId))
  if (!object(region)) return ''
  // The legacy entity's parenId is a numeric Long. Never round an unsafe ID.
  const parentId = typeof region.parenId === 'string' ? region.parenId
    : typeof region.parenId === 'number' && Number.isSafeInteger(region.parenId) ? String(region.parenId) : ''
  const byId = parents.find(parent => parent.id === parentId)
  if (byId) return byId.id
  const matching = parents.filter(parent => parent.tenantId && parent.tenantId === region.tenantId)
  return matching.length === 1 ? matching[0]!.id : ''
}

export function instanceError(error: unknown): string {
  if (error instanceof InstanceResponseError) return i18n.global.t('instances.invalidResponse')
  const body = isAxiosError(error) ? error.response?.data : error
  if (object(body)) {
    for (const key of ['message', 'msg', 'error']) {
      if (typeof body[key] === 'string' && body[key]) return body[key]
    }
  }
  if (isAxiosError(error) && ['ECONNABORTED', 'ETIMEDOUT'].includes(error.code || '')) return i18n.global.t('instances.timeout')
  return i18n.global.t('instances.requestFailed')
}
