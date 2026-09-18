import { isAxiosError, isCancel } from 'axios'
import request from './request'
import { tenantCsrfToken, tenantGet, tenantPost, tenantPut } from './tenant'

export type QualityType = 'icmp' | 'tcp' | 'http'
export type QualityOperator = 'telecom' | 'unicom' | 'mobile' | 'custom'
export type QualityStatus = 'success' | 'partial' | 'failed' | 'unsupported' | 'error' | 'unknown'
export type HistoryHours = 1 | 6 | 24 | 168
export interface NetworkQualityTaskInput {
  name: string; operator: QualityOperator; region: string; type: QualityType; target: string
  intervalSeconds: number; sampleCount: number; enabled: boolean; instanceIds: string[]
}
export interface NetworkQualityTask extends NetworkQualityTaskInput {
  id: string; version: string; createdAt: number; updatedAt: number
}
export interface NetworkQualityAgent {
  id: string; instanceId: string; displayName: string | null; publicIps: string | null
  tenancyName: string | null; regionName: string | null; cloudType: number | null
  monitorInstalled: boolean | null
  qualityStatus: 'not_installed' | 'upgrade_required' | 'online' | 'offline'
  lastSeen: number | null; version: string | null
}
export interface NetworkQualityResult {
  instanceId: string; taskId: string; revision: string; executionId: string; updatedAt: number
  status: QualityStatus; attempts: number | null; successful: number | null
  avgMs: number | null; minMs: number | null; maxMs: number | null
  errorCode: string | null; errorMessage: string | null; httpStatus: number | null
}
export interface NetworkQualityOverview {
  tasks: NetworkQualityTask[]; agents: NetworkQualityAgent[]; latest: NetworkQualityResult[]
  serverTime: number; legacyDisabled: true
}
export interface NetworkQualityStats {
  count: number; successCount: number; partialCount: number; failedCount: number
  unsupportedCount: number; errorCount: number; unknownCount: number
  attempts: number; successful: number; avgMs: number | null; minMs: number | null
  maxMs: number | null; lossPercent: number | null
}
export interface NetworkQualityHistorySelection {
  instanceId: string; taskId: string; revision: string; hours: HistoryHours
}
export interface NetworkQualityHistory extends NetworkQualityHistorySelection {
  from: number; to: number; points: NetworkQualityResult[]; totalPoints: number
  truncated: boolean; stats: NetworkQualityStats
}
export interface NetworkQualityRunReceipt {
  status: 'queued'; requested: number; queued: number; alreadyRunning: number; alreadyQueued: number
}
export type NetworkQualityErrorKey = 'invalidInput' | 'invalidResponse' | 'notFound' | 'conflict'
  | 'unauthorized' | 'forbidden' | 'expired' | 'requestFailed' | 'limitExceeded' | 'timeout' | 'cancelled'
export class NetworkQualityApiError extends Error {
  constructor(public key: NetworkQualityErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'NetworkQualityApiError'
  }
}

const BASE = '/api/network-quality'
const MAX_LONG = '9223372036854775807'
const types: QualityType[] = ['icmp', 'tcp', 'http']
const operators: QualityOperator[] = ['telecom', 'unicom', 'mobile', 'custom']
const statuses: QualityStatus[] = ['success', 'partial', 'failed', 'unsupported', 'error', 'unknown']
const agentStatuses = ['not_installed', 'upgrade_required', 'online', 'offline'] as const
const errorCodes = ['timeout', 'dns_error', 'connection_refused', 'network_error', 'http_error', 'unsupported', 'internal_error', 'lease_expired']
const errorKeys: NetworkQualityErrorKey[] = ['invalidInput', 'invalidResponse', 'notFound', 'conflict',
  'unauthorized', 'forbidden', 'expired', 'requestFailed', 'limitExceeded', 'timeout', 'cancelled']

export function isNetworkQualityId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < MAX_LONG.length || value <= MAX_LONG)
}
function isVersion(value: unknown): value is string { return value === '0' || isNetworkQualityId(value) }
function requireVersion(value: unknown): asserts value is string {
  if (!isVersion(value)) throw new NetworkQualityApiError('invalidInput')
}
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalid(): never { throw new NetworkQualityApiError('invalidResponse') }
function requireId(value: unknown): asserts value is string {
  if (!isNetworkQualityId(value)) throw new NetworkQualityApiError('invalidInput')
}
function integer(value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max
}
function epoch(value: unknown): number {
  return integer(value, 0, 8_640_000_000_000_000) ? value : invalid()
}
function nullableText(value: unknown): string | null {
  return value == null ? null : typeof value === 'string' ? value : invalid()
}
function metric(value: unknown, max = 60000): number | null {
  if (value == null) return null
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= max ? value : invalid()
}
function nullableInteger(value: unknown, min: number, max: number): number | null {
  return value == null ? null : integer(value, min, max) ? value : invalid()
}
function identity(value: unknown): string { return isNetworkQualityId(value) ? value : invalid() }
function unique<T>(values: T[], key: (value: T) => string): T[] {
  if (new Set(values.map(key)).size !== values.length) return invalid()
  return values
}
function validHost(value: string): boolean {
  const host = value.startsWith('[') && value.endsWith(']') ? value.slice(1, -1) : value
  if (!host || host.length > 253) return false
  if (host.includes(':')) {
    if (host.includes('%')) return false
    try { return !!new URL(`http://[${host}]/`).hostname } catch { return false }
  }
  const name = host.endsWith('.') ? host.slice(0, -1) : host
  return name.split('.').every(label => /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(label))
}

/** Syntax checks only. The server remains authoritative; no DNS lookup or probe occurs here. */
export function normalizeNetworkQualityTask(input: NetworkQualityTaskInput): NetworkQualityTaskInput {
  if (!object(input) || typeof input.name !== 'string' || typeof input.region !== 'string'
    || typeof input.target !== 'string' || !types.includes(input.type) || !operators.includes(input.operator)
    || typeof input.enabled !== 'boolean' || !integer(input.intervalSeconds, 30, 86400)
    || !integer(input.sampleCount, 1, 10) || !Array.isArray(input.instanceIds)
    || input.instanceIds.length < 1 || input.instanceIds.length > 256
    || input.instanceIds.some(id => !isNetworkQualityId(id))
    || new Set(input.instanceIds).size !== input.instanceIds.length) throw new NetworkQualityApiError('invalidInput')
  const name = input.name.trim(), region = input.region.trim(), target = input.target.trim()
  if (!name || name.length > 80 || region.length > 80 || !target || target.length > 2048
    || /[\u0000-\u001f\u007f]/.test(name + region) || /\s/.test(target)) throw new NetworkQualityApiError('invalidInput')
  if (input.type === 'http') {
    let url: URL
    try { url = new URL(target) } catch { throw new NetworkQualityApiError('invalidInput') }
    if (!/^https?:\/\//.test(target) || !['http:', 'https:'].includes(url.protocol) || !validHost(url.hostname)
      || url.username || url.password || url.hash || url.port === '0' || target.includes('#') || target.includes('\\')) {
      throw new NetworkQualityApiError('invalidInput')
    }
  } else if (input.type === 'tcp') {
    const match = /^(\[[0-9a-fA-F:.]+\]|[^\s:/?#@\[\]]+):(\d{1,5})$/.exec(target)
    if (!match || !validHost(match[1]!) || !integer(Number(match[2]), 1, 65535)) throw new NetworkQualityApiError('invalidInput')
  } else if (!validHost(target)) {
    throw new NetworkQualityApiError('invalidInput')
  }
  return { name, operator: input.operator, region, type: input.type, target,
    intervalSeconds: input.intervalSeconds, sampleCount: input.sampleCount,
    enabled: input.enabled, instanceIds: [...input.instanceIds] }
}
function task(value: unknown): NetworkQualityTask {
  if (!object(value)) return invalid()
  let input: NetworkQualityTaskInput
  try { input = normalizeNetworkQualityTask(value as unknown as NetworkQualityTaskInput) } catch { return invalid() }
  return { ...input, id: identity(value.id), version: isVersion(value.version) ? value.version : invalid(),
    createdAt: epoch(value.createdAt), updatedAt: epoch(value.updatedAt) }
}
function agent(value: unknown): NetworkQualityAgent {
  if (!object(value) || !agentStatuses.includes(value.qualityStatus as typeof agentStatuses[number])) return invalid()
  const id = identity(value.id), instanceId = identity(value.instanceId)
  if (id !== instanceId) return invalid()
  return { id, instanceId, displayName: nullableText(value.displayName), publicIps: nullableText(value.publicIps),
    tenancyName: nullableText(value.tenancyName), regionName: nullableText(value.regionName),
    cloudType: nullableInteger(value.cloudType, 0, 2147483647),
    monitorInstalled: value.monitorInstalled == null ? null
      : typeof value.monitorInstalled === 'boolean' ? value.monitorInstalled : invalid(),
    qualityStatus: value.qualityStatus as NetworkQualityAgent['qualityStatus'],
    lastSeen: value.lastSeen == null ? null : epoch(value.lastSeen), version: nullableText(value.version) }
}
function result(value: unknown): NetworkQualityResult {
  if (!object(value) || !statuses.includes(value.status as QualityStatus)
    || typeof value.executionId !== 'string'
    || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.executionId)) return invalid()
  const attempts = nullableInteger(value.attempts, 0, 10)
  const successful = nullableInteger(value.successful, 0, 10)
  const avgMs = metric(value.avgMs), minMs = metric(value.minMs), maxMs = metric(value.maxMs)
  if (attempts !== null && successful !== null && successful > attempts) return invalid()
  if (successful === null || successful === 0) {
    if (avgMs !== null || minMs !== null || maxMs !== null) return invalid()
  } else if (avgMs === null || minMs === null || maxMs === null || minMs > avgMs || avgMs > maxMs) return invalid()
  const errorCode = nullableText(value.errorCode)
  if (errorCode !== null && !errorCodes.includes(errorCode)) return invalid()
  return { instanceId: identity(value.instanceId), taskId: identity(value.taskId), revision: isVersion(value.revision) ? value.revision : invalid(),
    executionId: value.executionId, updatedAt: epoch(value.updatedAt), status: value.status as QualityStatus,
    attempts, successful, avgMs, minMs, maxMs, errorCode,
    errorMessage: safeDetail(value.errorMessage) || null, httpStatus: nullableInteger(value.httpStatus, 100, 599) }
}
function stats(value: unknown): NetworkQualityStats {
  if (!object(value)) return invalid()
  const keys = ['count', 'successCount', 'partialCount', 'failedCount', 'unsupportedCount',
    'errorCount', 'unknownCount', 'attempts', 'successful'] as const
  const counts = {} as Pick<NetworkQualityStats, typeof keys[number]>
  for (const key of keys) { if (!integer(value[key])) return invalid(); counts[key] = value[key] as number }
  if (counts.successful > counts.attempts || counts.count !== counts.successCount + counts.partialCount
    + counts.failedCount + counts.unsupportedCount + counts.errorCount + counts.unknownCount) return invalid()
  const avgMs = metric(value.avgMs), minMs = metric(value.minMs), maxMs = metric(value.maxMs)
  const lossPercent = metric(value.lossPercent, 100)
  if ((!counts.successful && (avgMs !== null || minMs !== null || maxMs !== null))
    // SQL weighted sums can introduce a tiny rounding difference for identical decimal samples.
    || (counts.successful > 0 && (avgMs === null || minMs === null || maxMs === null || minMs - avgMs > 0.000001 || avgMs - maxMs > 0.000001))
    || (counts.attempts === 0 ? lossPercent !== null : lossPercent === null)) return invalid()
  return { ...counts, avgMs, minMs, maxMs, lossPercent }
}
function unwrap(body: unknown): unknown {
  if (!object(body) || body.success !== true || !Object.prototype.hasOwnProperty.call(body, 'data')) return invalid()
  return body.data
}
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try { return JSON.parse(raw) } catch { return raw }
}
const writeOptions = { timeout: 0, transformResponse: [decode] }
const readOptions = { timeout: 30000, transformResponse: [decode],
  headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' } }

export async function fetchNetworkQualityOverview(signal?: AbortSignal): Promise<NetworkQualityOverview> {
  try {
    const data = unwrap(await tenantGet(`${BASE}/overview`, undefined, { ...readOptions, signal }))
    if (!object(data) || !Array.isArray(data.tasks) || data.tasks.length > 64 || !Array.isArray(data.agents)
      || data.agents.length > 20000 || !Array.isArray(data.latest) || data.latest.length > 16384 || data.legacyDisabled !== true) return invalid()
    return { tasks: unique(data.tasks.map(task), row => row.id), agents: unique(data.agents.map(agent), row => row.id),
      latest: unique(data.latest.map(result), row => `${row.instanceId}:${row.taskId}`),
      serverTime: epoch(data.serverTime), legacyDisabled: true }
  } catch (cause) { throw networkQualityError(cause) }
}
export async function fetchNetworkQualityHistory(selection: NetworkQualityHistorySelection, signal?: AbortSignal): Promise<NetworkQualityHistory> {
  requireId(selection.instanceId); requireId(selection.taskId)
  requireVersion(selection.revision)
  if (![1, 6, 24, 168].includes(selection.hours)) throw new NetworkQualityApiError('invalidInput')
  try {
    const data = unwrap(await tenantGet(`${BASE}/history`, {
      instanceId: selection.instanceId, taskId: selection.taskId, revision: selection.revision, hours: selection.hours,
    }, { ...readOptions, signal }))
    if (!object(data) || data.instanceId !== selection.instanceId || data.taskId !== selection.taskId
      || data.revision !== selection.revision || data.hours !== selection.hours || !Array.isArray(data.points) || data.points.length > 720
      || !integer(data.totalPoints) || typeof data.truncated !== 'boolean') return invalid()
    const from = epoch(data.from), to = epoch(data.to)
    const points = unique(data.points.map(result), point => point.executionId)
    if (from > to || data.totalPoints < points.length || data.truncated !== (data.totalPoints > points.length)
      || points.some((point, index) => point.instanceId !== selection.instanceId || point.taskId !== selection.taskId
        || point.revision !== selection.revision || point.updatedAt < from || point.updatedAt > to
        || (index > 0 && point.updatedAt < points[index - 1]!.updatedAt))) return invalid()
    const windowStats = stats(data.stats)
    if (windowStats.count !== data.totalPoints) return invalid()
    return { ...selection, from, to, points, totalPoints: data.totalPoints, truncated: data.truncated, stats: windowStats }
  } catch (cause) { throw networkQualityError(cause) }
}
/** Once dispatched, a write is neither cancelled nor retried by the client. */
async function mutate<T>(send: () => Promise<unknown>, parse: (value: unknown) => T): Promise<T> {
  try { return parse(await send()) } catch (cause) {
    const problem = networkQualityError(cause)
    throw new NetworkQualityApiError(problem.key, problem.detail, true)
  }
}
export function createNetworkQualityTask(input: NetworkQualityTaskInput): Promise<NetworkQualityTask> {
  const payload = normalizeNetworkQualityTask(input)
  return mutate(() => tenantPost(`${BASE}/tasks`, payload, writeOptions), body => task(unwrap(body)))
}
export function updateNetworkQualityTask(id: string, version: string, input: NetworkQualityTaskInput): Promise<NetworkQualityTask> {
  requireId(id); requireVersion(version)
  const payload = { ...normalizeNetworkQualityTask(input), version }
  return mutate(() => tenantPut(`${BASE}/tasks/${id}`, payload, writeOptions), body => {
    const updated = task(unwrap(body))
    return updated.id === id ? updated : invalid()
  })
}
export function deleteNetworkQualityTask(id: string, version: string): Promise<{ deleted: true }> {
  requireId(id); requireVersion(version)
  const headers: Record<string, string> = {}
  const token = tenantCsrfToken()
  if (token) headers[document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'] = token
  return mutate(() => request.delete(`${BASE}/tasks/${id}`, { ...writeOptions, params: { version }, headers, silent: true }), body => {
    const data = unwrap(body)
    return object(data) && data.deleted === true ? { deleted: true } : invalid()
  })
}
export function runNetworkQualityTask(id: string, version: string, instanceIds?: string[]): Promise<NetworkQualityRunReceipt> {
  requireId(id); requireVersion(version)
  if (instanceIds !== undefined && (!Array.isArray(instanceIds) || !instanceIds.length || instanceIds.length > 256
    || instanceIds.some(value => !isNetworkQualityId(value)) || new Set(instanceIds).size !== instanceIds.length)) {
    throw new NetworkQualityApiError('invalidInput')
  }
  return mutate(() => tenantPost(`${BASE}/tasks/${id}/run`, { version, ...(instanceIds ? { instanceIds: [...instanceIds] } : {}) }, writeOptions), body => {
    const data = unwrap(body)
    if (!object(data) || data.status !== 'queued' || !integer(data.requested, 1, 256)
      || !integer(data.queued, 0, 256) || !integer(data.alreadyRunning, 0, 256) || !integer(data.alreadyQueued, 0, 256)
      || data.requested !== data.queued + data.alreadyRunning + data.alreadyQueued) return invalid()
    return { status: 'queued', requested: data.requested, queued: data.queued,
      alreadyRunning: data.alreadyRunning, alreadyQueued: data.alreadyQueued }
  })
}
export function installNetworkQualityAgent(instanceId: string): Promise<{ message: string }> {
  requireId(instanceId)
  return mutate(() => tenantPost('/api/monitor/install', new URLSearchParams({ vpsId: instanceId }), {
    ...writeOptions, headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
  }), body => {
    if (!object(body) || body.success !== true) return invalid()
    return { message: safeDetail(body.message) }
  })
}
function safeDetail(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  if (/[<>{}\[\]\r\n]/.test(detail) || /https?:\/\//i.test(detail)
    || /(?:api[ _-]?(?:key|token)|secret|authorization|password|bearer)\s*[:= ]/i.test(detail)) return ''
  return detail.slice(0, 500)
}
/** Keep only a known key and safe display detail; never retain request objects or credentials. */
export function networkQualityError(cause: unknown): NetworkQualityApiError {
  if (cause instanceof NetworkQualityApiError) return new NetworkQualityApiError(cause.key, safeDetail(cause.detail), cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new NetworkQualityApiError('cancelled')
  const http = isAxiosError(cause), body: unknown = http ? cause.response?.data : cause
  if (http && ['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code || '')) return new NetworkQualityApiError('timeout')
  const code = object(body) ? body.errorKey : undefined
  const statusKey: Record<number, NetworkQualityErrorKey> = { 401: 'unauthorized', 403: 'forbidden', 404: 'notFound', 409: 'conflict', 410: 'expired' }
  const key = typeof code === 'string' && errorKeys.includes(code as NetworkQualityErrorKey)
    ? code as NetworkQualityErrorKey : http && cause.response ? statusKey[cause.response.status] || 'requestFailed' : 'requestFailed'
  return new NetworkQualityApiError(key, object(body) ? safeDetail(body.message) : '')
}
