import { tenantGet, tenantPost } from './tenant'

export interface TrafficRegion {
  id: string
  region?: string
  userName?: string
  tenancyName?: string
}

export interface TrafficSample {
  instanceId: string
  instanceName: string
  publicIp: string
  tenancyName: string
  timePoint: string
  ingressBytes: number
  egressBytes: number
}

export interface TrafficPoint {
  timePoint: string
  ingressBytes: number
  egressBytes: number
}

export interface TrafficQuery {
  tenantIds: string[]
  startDate: string
  endDate: string
  period: '1d'
}

export interface TrafficAlert {
  threshold?: number | null
  enabled?: boolean
  statisticsEnabled?: boolean
  autoShutdown?: boolean
}

export class TrafficResponseError extends Error {
  constructor() {
    super('trafficResponseInvalid')
    this.name = 'TrafficResponseError'
  }
}

function timePoint(value: unknown): string {
  // Spring can serialize LocalDateTime as either ISO text or an integer array.
  if (Array.isArray(value) && value.length >= 3) {
    const [year, month, day, hour = 0, minute = 0, second = 0] = value
    const pad = (part: unknown) => String(part).padStart(2, '0')
    return `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:${pad(second)}`
  }
  return typeof value === 'string' ? value.trim().replace(' ', 'T') : ''
}

function bytes(value: unknown): number {
  if (value == null || value === '') return 0
  const amount = Number(value)
  if (!Number.isFinite(amount) || amount < 0) throw new TrafficResponseError()
  return amount
}

export async function getTrafficRegions(parentId: string, signal?: AbortSignal): Promise<TrafficRegion[]> {
  const body = await tenantGet<unknown>('/tenants/listRegions', { parentId }, { signal })
  if (!Array.isArray(body)) throw new TrafficResponseError()
  const regions = new Map<string, TrafficRegion>()
  for (const item of body) {
    if (!item || typeof item !== 'object' || typeof item.id !== 'string') throw new TrafficResponseError()
    if (!item.id) continue
    regions.set(item.id, {
      id: item.id,
      region: item.region,
      userName: item.userName,
      tenancyName: item.tenancyName,
    })
  }
  return [...regions.values()]
}

export async function getTrafficAlert(tenantId: string, signal?: AbortSignal): Promise<TrafficAlert | null> {
  const body = await tenantGet<{ success?: boolean; data?: TrafficAlert | null }>('/monitor/api/traffic/alert', { tenantId }, { signal })
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new TrafficResponseError()
  if (body.success !== true) throw new TrafficResponseError()
  if (body.data != null && (typeof body.data !== 'object' || Array.isArray(body.data))) throw new TrafficResponseError()
  return body.data ?? null
}

export async function queryTenantTraffic(query: TrafficQuery, signal?: AbortSignal): Promise<TrafficSample[]> {
  // This endpoint queries OCI metrics for every selected region and returns a bare array.
  const body = await tenantPost<unknown>('/monitor/api/instances/traffic', query, { signal, timeout: 0 })
  if (!Array.isArray(body)) throw new TrafficResponseError()
  return body.map((item) => {
    if (!item || typeof item !== 'object') throw new TrafficResponseError()
    const time = timePoint(item.timePoint)
    if (typeof item.instanceId !== 'string' || !item.instanceId || !time) throw new TrafficResponseError()
    return {
      instanceId: item.instanceId,
      instanceName: typeof item.instanceName === 'string' ? item.instanceName : '',
      publicIp: typeof item.publicIp === 'string' ? item.publicIp : '',
      tenancyName: typeof item.tenancyName === 'string' ? item.tenancyName : '',
      timePoint: time,
      ingressBytes: bytes(item.ingressBytes),
      egressBytes: bytes(item.egressBytes),
    }
  })
}

export function aggregateTraffic(samples: TrafficPoint[]): TrafficPoint[] {
  const buckets = new Map<string, TrafficPoint>()
  for (const sample of samples) {
    const bucket = buckets.get(sample.timePoint) ?? { timePoint: sample.timePoint, ingressBytes: 0, egressBytes: 0 }
    bucket.ingressBytes += sample.ingressBytes
    bucket.egressBytes += sample.egressBytes
    buckets.set(sample.timePoint, bucket)
  }
  return [...buckets.values()].sort((a, b) => a.timePoint.localeCompare(b.timePoint))
}
