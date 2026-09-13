import { isAxiosError } from 'axios'
import { i18n } from '@/i18n'
import { tenantPost } from './tenant'

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
  const body = await tenantPost<unknown>('/tenants/save', data, {
    signal,
    // Saving OCI credentials synchronously reads subscribed regions and cloud resources.
    // Aborting this request does not undo a save already running on the server.
    timeout: 0,
  })
  if (!isObject(body) || body.success !== true) {
    if (isObject(body) && nonEmpty(body.error)) throw new Error(body.error)
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
