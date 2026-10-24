import { isAxiosError } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export interface GcpInstanceRow {
  bootId: string
  instanceName: string
  defName: string
  cloudType: number | null
  ocpu: number | null
  memory: number | null
  disk: number | null
  architecture: string
  status: number | null
  publicIp: string
  rootPassword: string
  zone: string
}
export interface GcpInstancePage {
  rows: GcpInstanceRow[]
  page: number
  size: number
  total: number
  totalPages: number
}
export type GcpInstanceAction = 'changeIp' | 'refresh' | 'delete'
export class GcpInstancesResponseError extends Error {}

function object(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value)
}
function string(value: unknown): string { return typeof value === 'string' ? value : '' }
function number(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}
function count(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) throw new GcpInstancesResponseError()
  return value
}

/** Keep Java Long account identifiers as strings, including the all-accounts value 0. */
export function isGcpTenantId(value: string): boolean {
  return /^(0|[1-9]\d*)$/.test(value) && (value.length < 19 || (value.length === 19 && value <= '9223372036854775807'))
}

export async function getGcpInstances(
  params: { tenantId: string; cloudType: number; page: number; size: number },
  signal: AbortSignal,
): Promise<GcpInstancePage> {
  const body = await tenantGet<unknown>('/other/instances/list/json', params, { signal })
  if (!object(body) || body.success !== true || !Array.isArray(body.content)) throw new GcpInstancesResponseError()
  const ids = new Set<string>()
  const rows = body.content.map((raw): GcpInstanceRow => {
    if (!object(raw) || !string(raw.bootId).trim() || ids.has(string(raw.bootId))) throw new GcpInstancesResponseError()
    ids.add(string(raw.bootId))
    return {
      // All actions use this string boot ID. Numeric database IDs are deliberately unused.
      bootId: string(raw.bootId), instanceName: string(raw.instanceName), defName: string(raw.defName),
      cloudType: number(raw.cloudType), ocpu: number(raw.ocpu), memory: number(raw.memory), disk: number(raw.disk),
      architecture: string(raw.architecture), status: number(raw.status), publicIp: string(raw.publicIp),
      rootPassword: string(raw.rootPassword), zone: string(raw.zone),
    }
  })
  const page = count(body.number)
  const size = count(body.size)
  if (page !== params.page || size !== params.size) throw new GcpInstancesResponseError()
  return { rows, page, size, total: count(body.totalElements), totalPages: count(body.totalPages) }
}

export async function runGcpInstanceAction(
  action: GcpInstanceAction,
  row: GcpInstanceRow,
  tenantId: string,
  signal: AbortSignal,
): Promise<void> {
  if (!row.bootId || row.cloudType !== 2 || (action === 'changeIp' && row.status !== 2)) throw new GcpInstancesResponseError()
  const body = await tenantPost<unknown>(`/other/instances/${encodeURIComponent(row.bootId)}/${action}`,
    { tenantId, cloudType: row.cloudType },
    // IP replacement waits for two cloud operations, each with a 120-second limit.
    { signal, timeout: action === 'changeIp' ? 300000 : 90000 },
  )
  if (!object(body) || body.success !== true) throw new GcpInstancesResponseError()
  // The controller does not return a cloud operation status or a new IP.
  // Its legacy service can also swallow failures, so callers must reread the list.
}

export function gcpInstancesServerError(cause: unknown): string {
  if (cause instanceof GcpInstancesResponseError) return ''
  const body = isAxiosError(cause) ? cause.response?.data : cause
  if (object(body)) {
    for (const key of ['message', 'msg', 'error']) if (typeof body[key] === 'string' && body[key]) return body[key]
  }
  return ''
}
