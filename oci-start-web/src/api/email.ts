import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

/** Email POST lists use one-based pageNum; returned Spring page numbers are zero-based. */
export interface EmailPageQuery {
  pageNum: number
  pageSize: number
  sort?: string
  order?: 'asc' | 'desc'
}

export interface EmailPage<T> {
  content: T[]
  number: number
  size: number
  totalElements: number
  totalPages: number
}

/** Only presentation fields are retained; SMTP credentials never enter page state. */
export interface EmailTenantConfig {
  id: string
  tenantId: string
  tenantName: string
  domainName: string
  senderEmail: string
  active: boolean | null
  createdTime: string
  lastResetDate: string
  todaySentCount: number | null
  dailyEmailLimit: number | null
}

export interface EmailAvailableTenant {
  id: string
  tenancyName: string
  defName: string
  userName: string
  region: string
  cloudType: number | null
  emailEnable: number | null
}

export interface EmailContact {
  id: string
  name: string
  email: string
  createTime: string
  updateTime: string
}

export interface EmailBody {
  /** Database primary key, used by /email/body/delete. */
  id: string
  /** Business ID, used by /email/send/list. Never substitute the primary key. */
  emailBodyId: string
  tenantId: string
  tenantName: string
  tenantEmailConfigId: string
  senderEmail: string
  title: string
  /** The SMTP implementation sends plain UTF-8 text. */
  content: string
  receiveTotal: number | null
  receiveSuccessTotal: number | null
  receiveFailTotal: number | null
  createTime: string
}

export interface EmailSendRecord {
  id: string
  emailSendRecordId: string
  emailBodyId: string
  emailSendAddress: string
  tenantId: string
  tenantName: string
  emailReceiveId: string
  receiveEmailAddress: string
  /** 1 confirms success. 0 also initializes records before SMTP has completed. */
  sendState: number | null
  createTime: string
}

export interface EmailContactInput { name: string; email: string }
export interface EmailEnableInput { tenantId: string; emailDomain: string }
export interface EmailSendInput {
  title: string
  content: string
  tenantEmailConfigId: string
  emailReceiveIds: string[]
}
export interface EmailContactQuery extends EmailPageQuery { name?: string; email?: string }
export interface EmailAvailableTenantQuery extends EmailPageQuery { keyword?: string }
export interface EmailSendRecordQuery extends EmailPageQuery { emailBodyId: string }

export type EmailErrorKey = 'invalidResponse' | 'invalidInput' | 'requestFailed' | 'timeout' | 'cancelled'
export class EmailApiError extends Error {
  constructor(public key: EmailErrorKey, public detail = '', public explicit = false) {
    super(key)
    this.name = 'EmailApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new EmailApiError('invalidResponse') }
function invalidInput(): never { throw new EmailApiError('invalidInput', '', true) }

export function isEmailId(value: unknown): value is string {
  const max = '9223372036854775807'
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < max.length || value <= max)
}
function requireId(value: string): string { return isEmailId(value) ? value : invalidInput() }
function identifier(value: unknown): string {
  if (isEmailId(value)) return value
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) return String(value)
  return invalidResponse()
}
function optionalIdentifier(value: unknown): string { return value == null ? '' : identifier(value) }
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalidResponse() }
function integer(value: unknown): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^(0|[1-9]\d*)$/.test(value))) return invalidResponse()
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : invalidResponse()
}
function count(value: unknown): number | null {
  if (value == null || value === '') return null
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^(0|[1-9]\d*)$/.test(value))) return invalidResponse()
  const parsed = Number(value)
  // Unknown or oversized counters must not become zero or a rounded quantity in the UI.
  if (!Number.isSafeInteger(parsed)) return null
  return parsed >= 0 ? parsed : invalidResponse()
}
function boolean(value: unknown): boolean | null {
  return value == null ? null : typeof value === 'boolean' ? value : invalidResponse()
}
function state(value: unknown): number | null {
  return value == null ? null : typeof value === 'number' && Number.isSafeInteger(value) ? value : invalidResponse()
}
function date(value: unknown): string {
  if (!Array.isArray(value)) return text(value)
  if (value.length < 3 || value.length > 7 || value.some(part => typeof part !== 'number' || !Number.isSafeInteger(part) || part < 0)) return invalidResponse()
  const [year, month, day, hour = 0, minute = 0, second = 0] = value as number[]
  const pad = (part: number) => String(part).padStart(2, '0')
  const dayText = `${String(year).padStart(4, '0')}-${pad(month!)}-${pad(day!)}`
  return value.length === 3 ? dayText : `${dayText}T${pad(hour)}:${pad(minute)}:${pad(second)}`
}

// Entity IDs are raw Java Long values. Consume complete JSON strings first so their
// contents stay untouched, then preserve large integer tokens before JSON can round them.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, (token: string, number?: string) => {
      return number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token
    }))
  } catch { return invalidResponse() }
}
const responseConfig = { transformResponse: [decode] }
const writeConfig = { ...responseConfig, timeout: 0 }

function accepted(body: unknown): Record<string, unknown> {
  // The shared client rejects success:false and business error codes before this step.
  if (!object(body) || body.success !== true) return invalidResponse()
  return body
}
function paging(query: EmailPageQuery, defaultSort: string, allowedSort: string[]) {
  if (![query.pageNum, query.pageSize].every(value => Number.isInteger(value) && value >= 1 && value <= 2147483647)
    || (query.order !== undefined && query.order !== 'asc' && query.order !== 'desc')) return invalidInput()
  const sort = query.sort || defaultSort
  if (!allowedSort.includes(sort)) return invalidInput()
  return { pageNum: query.pageNum, pageSize: query.pageSize, sort, order: query.order || 'desc' }
}
function page<T extends { id: string }>(body: unknown, query: EmailPageQuery, map: (value: unknown) => T, bare = false): EmailPage<T> {
  const value = bare ? body : accepted(body).data
  if (!object(value) || !Array.isArray(value.content)) return invalidResponse()
  const number = integer(bare ? value.currentPage : value.number)
  const size = integer(value.size)
  const totalElements = integer(value.totalElements)
  const totalPages = integer(value.totalPages)
  const content = value.content.map(map)
  if (number !== query.pageNum - 1 || size !== query.pageSize || content.length > size || totalElements < content.length
    || totalPages !== Math.ceil(totalElements / size) || new Set(content.map(row => row.id)).size !== content.length) return invalidResponse()
  return { content, number, size, totalElements, totalPages }
}

function configRow(value: unknown): EmailTenantConfig {
  if (!object(value)) return invalidResponse()
  return {
    id: identifier(value.id), tenantId: optionalIdentifier(value.tenantId), tenantName: text(value.tenantName),
    domainName: text(value.domainName), senderEmail: text(value.senderEmail), active: boolean(value.active),
    createdTime: date(value.createdTime), lastResetDate: date(value.lastResetDate),
    todaySentCount: count(value.todaySentCount), dailyEmailLimit: count(value.dailyEmailLimit),
  }
}
function availableTenantRow(value: unknown): EmailAvailableTenant {
  if (!object(value)) return invalidResponse()
  return {
    id: identifier(value.idStr || value.id), tenancyName: text(value.tenancyName), defName: text(value.defName),
    userName: text(value.userName), region: text(value.region), cloudType: count(value.cloudType), emailEnable: count(value.emailEnable),
  }
}
function contactRow(value: unknown): EmailContact {
  if (!object(value)) return invalidResponse()
  return { id: identifier(value.id), name: text(value.name), email: text(value.email), createTime: date(value.createTime), updateTime: date(value.updateTime) }
}
function bodyRow(value: unknown): EmailBody {
  if (!object(value) || !text(value.emailBodyId)) return invalidResponse()
  return {
    id: identifier(value.id), emailBodyId: text(value.emailBodyId), tenantId: optionalIdentifier(value.tenantId),
    tenantName: text(value.tenantName), tenantEmailConfigId: optionalIdentifier(value.tenantEmailConfigId), senderEmail: text(value.senderEmail),
    title: text(value.title), content: text(value.content), receiveTotal: count(value.receiveTotal),
    receiveSuccessTotal: count(value.receiveSuccessTotal), receiveFailTotal: count(value.receiveFailTotal), createTime: date(value.createTime),
  }
}
function sendRecordRow(value: unknown): EmailSendRecord {
  if (!object(value)) return invalidResponse()
  return {
    id: identifier(value.id), emailSendRecordId: text(value.emailSendRecordId), emailBodyId: text(value.emailBodyId),
    emailSendAddress: text(value.emailSendAddress), tenantId: optionalIdentifier(value.tenantId), tenantName: text(value.tenantName),
    emailReceiveId: optionalIdentifier(value.emailReceiveId), receiveEmailAddress: text(value.receiveEmailAddress),
    sendState: state(value.sendState), createTime: date(value.createTime),
  }
}

export async function listEmailTenants(query: EmailPageQuery, signal?: AbortSignal): Promise<EmailPage<EmailTenantConfig>> {
  // This endpoint has no server-side name/domain/keyword predicate.
  const input = paging(query, 'createdTime', ['createdTime', 'id', 'senderEmail', 'domainName'])
  return page(await tenantPost<unknown>('/email/tenant/list', input, { ...responseConfig, signal }), query, configRow)
}
export async function listEmailAvailableTenants(query: EmailAvailableTenantQuery, signal?: AbortSignal): Promise<EmailPage<EmailAvailableTenant>> {
  paging(query, 'createdAt', ['createdAt'])
  const body = await tenantGet<unknown>('/tenants/list/json', {
    page: query.pageNum - 1, size: query.pageSize, cloudType: 1, emailEnable: 0, keyword: query.keyword?.trim() || undefined,
  }, { ...responseConfig, signal })
  // The legacy controller catches repository failures and returns an empty page.
  // Its response cannot prove that every tenant has already enabled email.
  return page(body, query, availableTenantRow, true)
}
export async function listEmailContacts(query: EmailContactQuery, signal?: AbortSignal): Promise<EmailPage<EmailContact>> {
  const input = { ...paging(query, 'createTime', ['createTime', 'updateTime', 'id', 'name', 'email']), name: query.name?.trim(), email: query.email?.trim() }
  return page(await tenantPost<unknown>('/email/receive/list', input, { ...responseConfig, signal }), query, contactRow)
}
export async function listEmailBodies(query: EmailPageQuery, signal?: AbortSignal): Promise<EmailPage<EmailBody>> {
  const input = paging(query, 'createTime', ['createTime', 'id'])
  return page(await tenantPost<unknown>('/email/body/list', input, { ...responseConfig, signal }), query, bodyRow)
}
export async function listEmailSendRecords(query: EmailSendRecordQuery, signal?: AbortSignal): Promise<EmailPage<EmailSendRecord>> {
  if (!query.emailBodyId?.trim()) return invalidInput()
  const input = { ...paging(query, 'createTime', ['createTime', 'id']), emailBodyId: query.emailBodyId }
  const result = page(await tenantPost<unknown>('/email/send/list', input, { ...responseConfig, signal }), query, sendRecordRow)
  if (result.content.some(row => row.emailBodyId !== query.emailBodyId)) return invalidResponse()
  return result
}
export async function getEmailTenantConfigs(tenantId: string, signal?: AbortSignal): Promise<EmailTenantConfig[]> {
  const body = accepted(await tenantPost<unknown>('/email/tenant/get', { tenantId: requireId(tenantId) }, { ...responseConfig, signal }))
  if (!Array.isArray(body.data)) return invalidResponse()
  const rows = body.data.map(configRow)
  if (rows.some(row => row.tenantId !== tenantId) || new Set(rows.map(row => row.id)).size !== rows.length) return invalidResponse()
  return rows
}
export async function getEmailContact(id: string, signal?: AbortSignal): Promise<EmailContact> {
  const body = accepted(await tenantPost<unknown>('/email/receive/get', undefined, { ...responseConfig, params: { id: requireId(id) }, signal }))
  const row = contactRow(body.data)
  return row.id === id ? row : invalidResponse()
}

/** Mutations are never retried or cancelled by list/navigation cleanup. */
export async function addEmailContact(input: EmailContactInput): Promise<EmailContact> {
  if (!input.name.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email.trim())) return invalidInput()
  const body = accepted(await tenantPost<unknown>('/email/receive/add', { name: input.name.trim(), email: input.email.trim() }, writeConfig))
  return contactRow(body.data)
}
export async function deleteEmailContact(id: string): Promise<void> {
  accepted(await tenantPost<unknown>('/email/receive/delete', undefined, { ...writeConfig, params: { id: requireId(id) } }))
}
export async function enableTenantEmail(input: EmailEnableInput): Promise<void> {
  const tenantId = requireId(input.tenantId)
  const emailDomain = input.emailDomain.trim()
  if (!/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(\.[a-zA-Z]{2,})$/.test(emailDomain)) return invalidInput()
  // This legacy facade can return success after provisioning failed. The caller must
  // verify the requested domain with getEmailTenantConfigs before reporting activation.
  accepted(await tenantPost<unknown>('/tenants/email/enable', { tenantId, emailDomain }, writeConfig))
}
export async function disableTenantEmail(configId: string): Promise<void> {
  // This is the CONFIG ID, not tenantId. Cloud deletion helpers can swallow failures;
  // acceptance confirms local configuration removal, not complete cloud/DNS cleanup.
  accepted(await tenantPost<unknown>('/email/disable', { id: requireId(configId) }, writeConfig))
}
export async function sendEmail(input: EmailSendInput): Promise<void> {
  const tenantEmailConfigId = requireId(input.tenantEmailConfigId)
  if (!input.title.trim() || !input.content.trim() || input.emailReceiveIds.length === 0) return invalidInput()
  const emailReceiveIds = input.emailReceiveIds.map(requireId)
  if (new Set(emailReceiveIds).size !== emailReceiveIds.length) return invalidInput()
  // The server joins all SMTP tasks, but success:true can include failed recipients.
  // Even a rejected request may have sent mail; refresh history before any manual retry.
  accepted(await tenantPost<unknown>('/email/send', {
    title: input.title.trim(), content: input.content.trim(), tenantEmailConfigId, emailReceiveIds,
  }, writeConfig))
}
export async function deleteEmailBody(id: string): Promise<void> {
  accepted(await tenantPost<unknown>('/email/body/delete', { id: requireId(id) }, writeConfig))
}
export async function deleteAllEmailBodies(): Promise<void> {
  // No IDs or current-page filter: the endpoint deletes every body and send record.
  accepted(await tenantPost<unknown>('/email/body/batchDelete', undefined, writeConfig))
}

/** Returns display-safe metadata only, without retaining response data or SMTP secrets. */
export function emailError(cause: unknown): EmailApiError {
  if (cause instanceof EmailApiError) return cause
  if (isCancel(cause)) return new EmailApiError('cancelled')
  const body: unknown = isAxiosError(cause) ? cause.response?.data : cause
  const explicit = object(body) && body.success === false
  let detail = ''
  if (object(body)) {
    for (const key of ['message', 'msg', 'error']) {
      if (typeof body[key] === 'string' && body[key]) { detail = body[key]; break }
    }
  }
  const timeout = isAxiosError(cause) && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new EmailApiError(timeout ? 'timeout' : 'requestFailed', detail, explicit)
}

/** An explicit rejection still does not promise rollback of OCI/SMTP side effects. */
export function isEmailWriteUncertain(cause: unknown): boolean {
  return !emailError(cause).explicit
}
