import { isAxiosError } from 'axios'
import { i18n } from '@/i18n'
import { tenantGet, tenantPost } from './tenant'

export interface TenantPermissionOption {
  code: string
  label: string
  labelEn?: string
  group: string
  defaultEnabled: boolean
  required: boolean
  supported: boolean
  reason?: string
  dependencies?: string[]
}
export interface TenantAccountScope {
  allUsers: boolean
  passwordResetUserIds: string[]
  userManagementGroupIds: string[]
}
export interface RestrictedTenantOptions {
  managedUserName: string
  permissions: string[]
  accountScope: TenantAccountScope
}

export async function getTenantPermissionCatalog(signal?: AbortSignal): Promise<TenantPermissionOption[]> {
  const body = await tenantGet<{ success: boolean; data: TenantPermissionOption[] }>('/tenants/permissions/catalog', undefined, { signal })
  if (!body.success || !Array.isArray(body.data)) throw new Error('无法读取权限列表 / Unable to load permissions')
  return body.data
}

export type ImportProvider = 1 | 2

export interface TenantImportFields {
  userName: string
  tenantId: string
  fingerprint: string
  tenancy: string
  region: string
}

export interface OciProfile {
  id: string
  name: string
  fields: TenantImportFields
  keyFileHint: string
}

type ImportErrorKey =
  | 'tenantImport.invalidOciConfig'
  | 'tenantImport.invalidJson'
  | 'tenantImport.notServiceAccount'
  | 'tenantImport.incompleteGcp'
  | 'tenantImport.invalidResponse'
  | 'tenantImport.requestFailed'
  | 'tenantImport.invalidDowngradeTenant'
  | 'tenantImport.backupInvalid'
  | 'tenantImport.backupRequired'

class TenantImportValidationError extends Error {
  constructor(
    readonly translationKey: ImportErrorKey,
    readonly params: Record<string, string> = {},
  ) {
    // Store only the error key, never the configuration or its credentials.
    super(translationKey)
    this.name = 'TenantImportValidationError'
  }
}

class TenantImportRejectedError extends Error {}

export interface TenantDowngradeSource {
  id: string
  userId: string
  tenancy: string
  name: string
  region: string
}

export function isLocalTenantId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < 19 || value <= '9223372036854775807')
}

/** Export uses Long IDs. Preserve them before parsing, including regional children. */
function decodeBackup(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g,
      (token: string, number?: string) => number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token))
  } catch { throw new TenantImportValidationError('tenantImport.backupInvalid') }
}

export async function sendTenantBackupCode(signal?: AbortSignal): Promise<void> {
  await tenantPost('/tenants/verify/sendExportCode', undefined, { signal })
}

export async function loadTenantDowngradeBackup(source: TenantDowngradeSource, code: string, signal?: AbortSignal): Promise<Blob> {
  const verificationCode = code.trim().toUpperCase()
  if (!isLocalTenantId(source.id) || !nonEmpty(source.userId) || !nonEmpty(source.tenancy) || !/^[A-Z0-9]{8}$/.test(verificationCode)) {
    throw new TenantImportValidationError('tenantImport.backupInvalid')
  }
  const raw = await tenantGet<unknown>('/tenants/exportByTenant', { id: source.id }, {
    signal, headers: { 'X-Verify-Code': verificationCode }, responseType: 'text', transformResponse: [(value: unknown) => value],
  })
  const body = decodeBackup(raw)
  if (isObject(body) && body.success === false) throw new TenantImportRejectedError(backendMessage(body) || i18n.global.t('tenantImport.requestFailed'))
  const idOf = (row: Record<string, unknown>) => {
    const id = row.id
    return isLocalTenantId(id) ? id : typeof id === 'number' && Number.isSafeInteger(id) && id > 0 ? String(id) : ''
  }
  const validRecord = (row: unknown): boolean => isObject(row) && Boolean(idOf(row))
    && (!nonEmpty(row.id_str) || row.id_str === idOf(row))
    && row.tenant_id === source.userId && row.tenancy === source.tenancy
    && nonEmpty(row.fingerprint) && nonEmpty(row.region) && nonEmpty(row.key_file_content)
    && (row.permission_mode == null || row.permission_mode === '') && Number(row.cloud_type) === 1
    && (row.children == null || (Array.isArray(row.children) && row.children.every(validRecord)))
  if (!Array.isArray(body) || body.length !== 1 || !validRecord(body[0]) || idOf(body[0]) !== source.id) {
    // Never include exported data or private key fragments in an error.
    throw new TenantImportValidationError('tenantImport.backupInvalid')
  }
  return new Blob([typeof raw === 'string' ? raw : JSON.stringify(body, null, 2)], { type: 'application/json' })
}

export async function downgradeTenantCredentials(
  tenantId: string, options: RestrictedTenantOptions, backupConfirmed: boolean, signal?: AbortSignal,
): Promise<string[]> {
  if (!backupConfirmed) throw new TenantImportValidationError('tenantImport.backupRequired')
  if (!isLocalTenantId(tenantId) || !options.managedUserName.trim() || !options.permissions.includes('BASIC_READ')) {
    throw new TenantImportValidationError('tenantImport.invalidDowngradeTenant')
  }
  const body = await tenantPost<unknown>('/tenants/restricted/downgrade', {
    tenantId, managedUserName: options.managedUserName.trim(), permissions: JSON.stringify(options.permissions),
    accountScope: JSON.stringify(options.accountScope), backupConfirmed: true,
  }, { signal, timeout: 0 })
  if (!isObject(body) || body.success !== true) {
    if (isObject(body) && body.success === false) {
      throw new TenantImportRejectedError(backendMessage(body) || i18n.global.t('tenantImport.requestFailed'))
    }
    throw new TenantImportValidationError('tenantImport.invalidResponse')
  }
  const warnings = isObject(body.data) ? body.data.cleanupWarnings : undefined
  if (warnings === undefined) return []
  // A confirmed success must stay successful even if warning metadata is malformed.
  // Read only the documented string list, never stringify response objects or credentials.
  if (!Array.isArray(warnings) || warnings.some(value => typeof value !== 'string')) {
    return [i18n.global.t('tenantImport.cleanupWarningsUnavailable')]
  }
  return warnings.filter(nonEmpty).map(value => value.trim())
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function emptyFields(userName = ''): TenantImportFields {
  return { userName, tenantId: '', fingerprint: '', tenancy: '', region: '' }
}

function iniValue(value: string): string {
  const trimmed = value.trim()
  const quote = trimmed[0]
  if (quote === '"' || quote === "'") {
    const end = trimmed.lastIndexOf(quote)
    if (end > 0 && /^(?:\s*[#;].*)?$/.test(trimmed.slice(end + 1))) {
      return trimmed.slice(1, end)
    }
  }
  // A comment must be separated from its value, so a path containing # survives.
  return trimmed.replace(/(^|\s+)[#;].*$/, '').trim()
}

export function parseOciConfig(text: string): OciProfile[] {
  if (typeof text !== 'string') throw new TenantImportValidationError('tenantImport.invalidOciConfig')
  const profiles: OciProfile[] = []
  const named = new Map<string, OciProfile>()
  const recognized = new Set<OciProfile>()
  const assigned = new Map<OciProfile, Map<string, string>>()
  let current: OciProfile | undefined

  function createProfile(name: string): OciProfile {
    const profile: OciProfile = {
      id: `oci-profile-${profiles.length + 1}`,
      name,
      fields: emptyFields(name),
      keyFileHint: '',
    }
    profiles.push(profile)
    assigned.set(profile, new Map())
    return profile
  }

  for (const raw of text.replace(/^\uFEFF/, '').split(/\r\n|\n|\r/)) {
    const line = raw.trim()
    if (!line || line.startsWith('#') || line.startsWith(';')) continue

    if (line.startsWith('[')) {
      const section = /^\[([^\]]+)\]\s*(?:[#;].*)?$/.exec(line)
      const name = section?.[1]?.trim()
      // A malformed section must not let its fields fall into the preceding account.
      if (!name) throw new TenantImportValidationError('tenantImport.invalidOciConfig')
      current = named.get(name)
      if (!current) {
        current = createProfile(name)
        named.set(name, current)
      }
      continue
    }

    const separator = line.indexOf('=')
    if (separator < 0) continue
    const key = line.slice(0, separator).trim().toLowerCase()
    if (!['user', 'fingerprint', 'tenancy', 'region', 'key_file'].includes(key)) continue
    if (!current) current = createProfile('')
    const value = iniValue(line.slice(separator + 1))
    const values = assigned.get(current)!
    // Repeated sections can supply missing fields, but conflicting credentials are ambiguous.
    if (values.has(key) && values.get(key) !== value) {
      throw new TenantImportValidationError('tenantImport.invalidOciConfig')
    }
    values.set(key, value)
    if (key === 'key_file') {
      current.keyFileHint = value
      continue
    }
    recognized.add(current)
    if (key === 'user') current.fields.tenantId = value
    else if (key === 'fingerprint') current.fields.fingerprint = value
    else if (key === 'tenancy') current.fields.tenancy = value
    else if (key === 'region') current.fields.region = value
  }

  const result = profiles.filter(profile => recognized.has(profile))
  if (!result.length) throw new TenantImportValidationError('tenantImport.invalidOciConfig')
  return result
}

export function parseGcpConfig(
  text: string,
  originalFile?: File,
): { fields: TenantImportFields; file: File } {
  let config: unknown
  try {
    config = JSON.parse(text.replace(/^\uFEFF/, ''))
  } catch {
    // JSON parser exceptions can include a fragment of the private key.
    throw new TenantImportValidationError('tenantImport.invalidJson')
  }
  if (!isObject(config) || config.type !== 'service_account') {
    throw new TenantImportValidationError('tenantImport.notServiceAccount')
  }
  const required = ['project_id', 'client_email', 'private_key_id', 'private_key'] as const
  const missing = required.filter(key => !nonEmpty(config[key]))
  if (missing.length) {
    throw new TenantImportValidationError('tenantImport.incompleteGcp', { fields: missing.join(', ') })
  }

  const project = config.project_id as string
  const filename = project.replace(/[^a-zA-Z0-9._-]/g, '-').replace(/^[.-]+/, '') || 'gcp'
  return {
    fields: {
      userName: project,
      tenantId: config.client_email as string,
      fingerprint: config.private_key_id as string,
      tenancy: project,
      region: '',
    },
    // Keep the selected File and its name; pasted JSON retains the complete original text.
    file: originalFile ?? new File([text], `${filename}-service-account.json`, { type: 'application/json' }),
  }
}

export async function saveTenantCredentials(
  provider: ImportProvider,
  fields: TenantImportFields,
  file: File,
  signal?: AbortSignal,
  restricted?: RestrictedTenantOptions,
): Promise<void> {
  if (
    (provider !== 1 && provider !== 2)
    || ![fields.userName, fields.tenantId, fields.fingerprint, fields.tenancy].every(nonEmpty)
    || (provider === 1 && !nonEmpty(fields.region))
    || !(file instanceof File)
    || file.size === 0
  ) {
    throw new TenantImportValidationError('tenantImport.requestFailed')
  }
  const data = new FormData()
  data.append('userName', fields.userName)
  data.append('tenantId', fields.tenantId)
  data.append('fingerprint', fields.fingerprint)
  data.append('tenancy', fields.tenancy)
  data.append('region', provider === 1 ? fields.region : '')
  data.append('status', '0')
  data.append('cloudType', String(provider))
  data.append('keyFileStr', file)
  if (provider === 1 && restricted) {
    if (!restricted?.managedUserName.trim() || !restricted.permissions.includes('BASIC_READ')) {
      throw new TenantImportValidationError('tenantImport.requestFailed')
    }
    data.append('managedUserName', restricted.managedUserName.trim())
    data.append('permissions', JSON.stringify(restricted.permissions))
    data.append('accountScope', JSON.stringify(restricted.accountScope))
  }
  const body = await tenantPost<unknown>(provider === 1 && restricted ? '/tenants/restricted/save' : '/tenants/save', data, {
    signal,
    // Saving OCI credentials synchronously reads subscribed regions and cloud resources.
    // Aborting this request does not undo a save already running on the server.
    timeout: 0,
  })
  if (!isObject(body) || body.success !== true) {
    if (isObject(body) && body.success === false) {
      throw new TenantImportRejectedError(backendMessage(body) || i18n.global.t('tenantImport.requestFailed'))
    }
    throw new TenantImportValidationError('tenantImport.invalidResponse')
  }
}

function backendMessage(body: unknown): string {
  if (typeof body === 'string') return nonEmpty(body) && !body.trimStart().startsWith('<') ? body : ''
  if (!isObject(body)) return ''
  for (const key of ['error', 'message', 'msg']) {
    if (nonEmpty(body[key])) return body[key]
  }
  return ''
}

/** Distinguish an explicit rejection from a write whose response cannot establish its outcome. */
export function tenantImportOutcomeUnknown(error: unknown): boolean {
  if (error instanceof TenantImportRejectedError) return false
  if (error instanceof TenantImportValidationError) return error.translationKey === 'tenantImport.invalidResponse'
  // The shared Axios interceptor rejects business errors with the original JSON body.
  if (isObject(error) && error.success === false) return false
  if (isAxiosError(error)) {
    const body: unknown = error.response?.data
    if (isObject(body) && body.success === false) return false
    const status = error.response?.status
    if (typeof status === 'number' && status > 0) return status >= 500 || status === 408
    if (['ECONNABORTED', 'ETIMEDOUT', 'ERR_NETWORK', 'ERR_CANCELED'].includes(error.code || '')) return true
    // An Axios setup error without a request was rejected before submission.
    return Boolean(error.request)
  }
  return true
}

export function tenantImportError(error: unknown): string {
  if (error instanceof TenantImportValidationError) {
    return i18n.global.t(error.translationKey, error.params)
  }
  if (isAxiosError(error)) {
    const message = backendMessage(error.response?.data)
    if (message) return message
    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') return i18n.global.t('tenantImport.timeoutError')
    if (error.code === 'ERR_CANCELED') return i18n.global.t('tenantImport.requestFailed')
    if (error.code === 'ERR_NETWORK' || (!error.response && error.request)) return i18n.global.t('tenantImport.networkError')
    return i18n.global.t('tenantImport.requestFailed')
  }
  return backendMessage(error) || i18n.global.t('tenantImport.requestFailed')
}
