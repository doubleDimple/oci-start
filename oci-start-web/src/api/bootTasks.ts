import { isAxiosError } from 'axios'
import { tenantGet, tenantPost } from './tenant'
import { isBootTenantId } from './ociBoot'

export { isBootTenantId as isBootTaskId } from './ociBoot'

interface BootTaskBase { id: string; tenantId: string; architecture: string }
export interface BootTaskGroup extends BootTaskBase {
  tenancyName: string; defName: string; regionName: string; openBootFlag: boolean
  recordCount: string; executingCount: string; totalCount: string; yesterdayAttemptCount: string
  currentAttemptCount: string; failCount: string; successCount: string; createdAt: string
}
export interface BootTaskDetail extends BootTaskBase {
  bootId: string
  ocpu: number; memory: number; disk: number; loopTime: number; rootPassword: string; dayGap: string
  operatingSystem: string; operatingSystemVersion: string; status: number; createdAt: string
  yesterdayAttemptCount: string; currentAttemptCount: string; failCount: string
}
export interface BootTaskEdit {
  id: string; ocpu: number; memory: number; disk: number; loopTime: number; rootPassword: string; dayGap: string
}
export type BootTaskAction = 'clone' | 'start' | 'stop' | 'delete' | 'manual' | 'batchStart' | 'batchStop'
  | 'resetFailures' | 'detailStart' | 'detailStop' | 'detailDelete' | 'edit'

export class BootTaskError extends Error {
  constructor(public key: 'invalidResponse' | 'invalidId' | 'requestFailed' | 'timeout', public detail = '', public explicit = false) { super(key) }
}
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function invalid(): never { throw new BootTaskError('invalidResponse') }
function identifier(value: unknown): string {
  if (isBootTenantId(value)) return value
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) return String(value)
  return invalid()
}
function requireId(id: string) { if (!isBootTenantId(id)) throw new BootTaskError('invalidId', '', true) }
function text(value: unknown): string { if (value == null) return ''; return typeof value === 'string' ? value : invalid() }
function count(value: unknown): string {
  if (value == null) return '0'
  if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) return String(value)
  if (typeof value === 'string' && /^(0|[1-9]\d*)$/.test(value)) return value
  return invalid()
}
function integer(value: unknown): number { return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : invalid() }

// BootInstance exposes raw Java Long IDs. Preserve integer tokens before Axios/JSON can round them.
// The first regex alternative consumes complete JSON strings, including escaped quotes.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, (token: string, number?: string) => {
      return number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token
    }))
  } catch { return invalid() }
}
const responseConfig = { transformResponse: [decode] }
function accepted(body: unknown): Record<string, unknown> {
  if (!object(body) || body.success !== true) return invalid()
  return body
}
function base(value: Record<string, unknown>): BootTaskBase {
  const architecture = text(value.architecture)
  if (!architecture) return invalid()
  return { id: identifier(value.id), tenantId: identifier(value.tenantId), architecture }
}
function group(value: unknown): BootTaskGroup {
  if (!object(value) || typeof value.openBootFlag !== 'boolean') return invalid()
  return { ...base(value), tenancyName: text(value.tenancyName), defName: text(value.defName), regionName: text(value.regionName),
    openBootFlag: value.openBootFlag, recordCount: count(value.recordCount), executingCount: count(value.executingCount),
    totalCount: count(value.totalCount), yesterdayAttemptCount: count(value.yesterdayAttemptCount),
    currentAttemptCount: count(value.currentAttemptCount), failCount: count(value.failCount), successCount: count(value.successCount),
    createdAt: text(value.createAtStr || value.createdAt) }
}
function detail(value: unknown): BootTaskDetail {
  if (!object(value)) return invalid()
  return { ...base(value), bootId: text(value.bootId), ocpu: integer(value.ocpu), memory: integer(value.memory), disk: integer(value.disk), loopTime: integer(value.loopTime),
    rootPassword: text(value.rootPassword), dayGap: text(value.dayGap), operatingSystem: text(value.operatingSystem),
    operatingSystemVersion: text(value.operatingSystemVersion), status: integer(value.status), createdAt: text(value.createdAt),
    yesterdayAttemptCount: count(value.yesterdayAttemptCount), currentAttemptCount: count(value.currentAttemptCount), failCount: count(value.failCount) }
}
export async function getBootTasks(page: number, size: number, tenantId: string, signal: AbortSignal) {
  if (tenantId) requireId(tenantId)
  const body = await tenantGet<unknown>('/boot/fullBootList/json', { page, size, tenantId: tenantId || undefined }, { ...responseConfig, signal })
  if (!object(body) || !Array.isArray(body.content) || body.currentPage !== page || body.size !== size) return invalid()
  const total = integer(body.totalElements), totalPages = integer(body.totalPages)
  const rows = body.content.map(group)
  if (totalPages !== Math.ceil(total / size) || new Set(rows.map(row => `${row.tenantId}:${row.architecture}`)).size !== rows.length || rows.length > size
    || rows.some(row => tenantId && row.tenantId !== tenantId) || total < rows.length) return invalid()
  return { rows, total, totalPages }
}
export async function getBootTaskDetails(target: BootTaskBase, signal: AbortSignal): Promise<BootTaskDetail[]> {
  requireId(target.tenantId)
  // Resolve the current representative after a child deletion or an external change.
  const lookup = accepted(await tenantPost<unknown>('/boot/bootDetailList', { tenantId: target.tenantId, architecture: target.architecture }, { ...responseConfig, signal }))
  if (lookup.bootId === null) return []
  const id = identifier(lookup.bootId)
  const body = accepted(await tenantGet<unknown>('/boot/bootDetail', { bootId: id }, { ...responseConfig, signal }))
  if (!Array.isArray(body.data)) return invalid()
  const rows = body.data.map(detail)
  if (new Set(rows.map(row => row.id)).size !== rows.length
    || rows.some(row => row.tenantId !== target.tenantId || row.architecture !== target.architecture)) return invalid()
  return rows
}
export async function getBootTaskBatchCount(action: 'batchStart' | 'batchStop', signal: AbortSignal): Promise<string> {
  const body = await tenantGet<unknown>(`/boot/${action === 'batchStart' ? 'getOfflineCount' : 'getStartingCount'}`, undefined, { ...responseConfig, signal })
  if (!object(body) || body.count == null) return invalid()
  return count(body.count)
}
export function validBootTaskEdit(input: BootTaskEdit): boolean {
  if (!isBootTenantId(input.id) || ![input.ocpu, input.memory, input.disk, input.loopTime].every(value => Number.isInteger(value) && value >= 1 && value <= 2147483647)
    || !input.rootPassword.trim()) return false
  if (!input.dayGap) return true
  const match = /^(\d{1,2})-(\d{1,2})$/.exec(input.dayGap)
  return !!match && Number(match[1]) >= 0 && Number(match[1]) <= 23 && Number(match[2]) >= 1
    && Number(match[2]) <= 24 && Number(match[1]) < Number(match[2])
}
export async function performBootTaskAction(action: BootTaskAction, id?: string, input?: BootTaskEdit): Promise<void> {
  if (action === 'batchStart' || action === 'batchStop' || action === 'resetFailures') {
    accepted(await tenantPost<unknown>(`/boot/${action === 'resetFailures' ? 'batchInitFailCount' : action}`, undefined, responseConfig))
    return
  }
  requireId(id || '')
  if (action === 'edit') {
    if (!input || input.id !== id || !validBootTaskEdit(input)) throw new BootTaskError('invalidResponse', '', true)
    accepted(await tenantPost<unknown>('/boot/updateBoot', input, responseConfig))
  } else if (action === 'detailStart' || action === 'detailStop') {
    accepted(await tenantPost<unknown>('/boot/toggleStatus', new URLSearchParams({ id: id!, status: action === 'detailStart' ? '1' : '0' }), responseConfig))
  } else if (action === 'manual' || action === 'detailDelete') {
    accepted(await tenantPost<unknown>(`/boot/${action === 'manual' ? 'manualBoot' : 'deleteBootDetail'}`, undefined, { ...responseConfig, params: { bootId: id } }))
  } else {
    const endpoints = { clone: 'startCloneBoot', start: 'startBoot', stop: 'stopBoot', delete: 'deleteBoot' } as const
    // Preserve legacy GET mutation contracts; never invoke these from a link or prefetch.
    accepted(await tenantGet<unknown>(`/boot/${endpoints[action]}`, { bootId: id }, { ...responseConfig, headers: { 'Cache-Control': 'no-cache' } }))
  }
}
export function bootTaskError(cause: unknown): BootTaskError {
  if (cause instanceof BootTaskError) return cause
  const body: unknown = isAxiosError(cause) ? cause.response?.data : cause
  const explicit = object(body) && body.success === false
  let message = ''
  if (object(body)) for (const key of ['message', 'msg', 'error']) { if (typeof body[key] === 'string' && body[key]) { message = body[key]; break } }
  return new BootTaskError(isAxiosError(cause) && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '') ? 'timeout' : 'requestFailed', message, explicit)
}
