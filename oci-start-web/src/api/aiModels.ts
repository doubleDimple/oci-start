import { AxiosHeaders, isAxiosError, isCancel } from 'axios'
import request from './request'
import { tenantCsrfToken, tenantGet, tenantPost } from './tenant'

export interface AiModelTenant { id: string; name: string }
export interface AvailableAiModel {
  /** OCI model OCID; this is not a local numeric primary key. */
  id: string
  tenantId: string
  name: string
  description: string
  provider: string
  modelName: string
  enabled: boolean | null
  userName: string
}

/** Presentation fields only. Credentials and advanced settings stay out of page state. */
export interface AiModelConfig {
  id: string
  tenantId: string
  modelId: string
  showModelId: string
  cloudType: number | null
  modelName: string
  provider: string
  enabled: boolean | null
  region: string
  userName: string
}
export interface AiModelConfigInput {
  tenantId: string
  modelId: string
  modelName: string
  provider: string
  userName?: string
}
export interface AiModelBatchResult { updatedCount: number; enabled: boolean; message: string }

export type AiModelsErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed'
  | 'timeout' | 'cancelled' | 'alreadyConfigured' | 'configMissing'
export class AiModelsApiError extends Error {
  constructor(
    public key: AiModelsErrorKey,
    public detail = '',
    public explicit = false,
    /** False for validation and preflight reads; true once a write was attempted. */
    public writeAttempted = false,
  ) {
    super(key)
    this.name = 'AiModelsApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new AiModelsApiError('invalidResponse') }
function invalidInput(): never { throw new AiModelsApiError('invalidInput', '', true) }
/** Local tenant/config primary keys only; available model OCIDs are textual IDs. */
export function isAiModelId(value: unknown): value is string {
  const max = '9223372036854775807'
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < max.length || value <= max)
}
function requireId(value: unknown): string { return isAiModelId(value) ? value : invalidInput() }
function identifier(value: unknown): string {
  if (isAiModelId(value)) return value
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? String(value) : invalidResponse()
}
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalidResponse() }
function nullableText(value: unknown): string | null {
  return value == null ? null : typeof value === 'string' ? value : invalidResponse()
}
function inputText(value: unknown): string {
  return typeof value === 'string' && value.trim() && !value.includes('\0') ? value : invalidInput()
}
function requiredText(value: unknown): string { return typeof value === 'string' && value.trim() ? value : invalidResponse() }
function boolean(value: unknown): boolean | null {
  return value == null ? null : typeof value === 'boolean' ? value : invalidResponse()
}
function integer(value: unknown): number | null {
  return value == null ? null : typeof value === 'number' && Number.isInteger(value)
    && value >= -2147483648 && value <= 2147483647 ? value : invalidResponse()
}
function tenantReference(value: unknown): string {
  // Legacy configs can outlive their tenant; they must remain visible and removable.
  if (value == null || value === '') return ''
  if (value === '-1') return value
  return identifier(value)
}

// Consume complete JSON strings before number tokens so Java Long IDs survive parsing.
// The controller also returns empty DELETE responses and plain-text HTTP errors.
// Unexpected text on a successful list/save is rejected by the schema below.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string' || !raw.trim()) return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, (token: string, number?: string) => {
      return number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token
    }))
  } catch { return raw }
}
const readConfig = { transformResponse: [decode], timeout: 30000 }
// Writes have no automatic retry, cancellation signal or short request timeout.
const writeConfig = { transformResponse: [decode], timeout: 0 }

function configRow(value: unknown): AiModelConfig {
  if (!object(value)) return invalidResponse()
  return {
    id: identifier(value.id), tenantId: tenantReference(value.tenantId), modelId: text(value.modelId),
    showModelId: text(value.showModelId), cloudType: integer(value.cloudType), modelName: text(value.modelName),
    provider: text(value.provider), enabled: boolean(value.enabled), region: text(value.region), userName: text(value.userName),
  }
}

/** Private, request-local DTOs: never return these records or an Axios error to the UI. */
async function readConfigDtos(signal?: AbortSignal): Promise<Record<string, unknown>[]> {
  try {
    const body = await tenantGet<unknown>('/system/telegramAiConfigs', undefined, { ...readConfig, signal })
    if (!Array.isArray(body)) return invalidResponse()
    const rows = body.map(value => {
      if (!object(value)) return invalidResponse()
      configRow(value)
      return value
    })
    if (new Set(rows.map(row => identifier(row.id))).size !== rows.length) return invalidResponse()
    return rows
  } catch (cause) { throw aiModelsError(cause) }
}

/** Supported OCI AI tenant/region records, not the generic parent-tenant selector. */
export async function listAiModelTenants(signal?: AbortSignal): Promise<AiModelTenant[]> {
  try {
    const body = await tenantGet<unknown>('/system/ai/tenants', undefined, { ...readConfig, signal })
    if (!Array.isArray(body)) return invalidResponse()
    const rows = body.map(value => {
      if (!object(value)) return invalidResponse()
      return { id: identifier(value.id), name: text(value.name) }
    })
    if (new Set(rows.map(row => row.id)).size !== rows.length) return invalidResponse()
    return rows
  } catch (cause) { throw aiModelsError(cause) }
}

/** Server returns one array of active, non-retired chat/image models, without a cursor. */
export async function listAvailableAiModels(tenantId: string, signal?: AbortSignal): Promise<AvailableAiModel[]> {
  const id = requireId(tenantId)
  try {
    const body = await tenantGet<unknown>('/system/ai/modelsByTenant', { tenantId: id }, { ...readConfig, signal })
    if (!Array.isArray(body)) return invalidResponse()
    const rows = body.map(value => {
      if (!object(value) || identifier(value.tenantId) !== id) return invalidResponse()
      return {
        id: requiredText(value.id), tenantId: id, name: text(value.name), description: text(value.description),
        provider: text(value.provider), modelName: text(value.modelName), enabled: boolean(value.enabled),
        // The current ModelSummaryDef has no userName; the old request permits an empty value.
        userName: text(value.userName),
      }
    })
    if (new Set(rows.map(row => row.id)).size !== rows.length) return invalidResponse()
    return rows
  } catch (cause) { throw aiModelsError(cause) }
}

/** All OCI configs, including disabled rows. Pagination and tenant filtering are local. */
export async function listAiModelConfigs(signal?: AbortSignal): Promise<AiModelConfig[]> {
  return (await readConfigDtos(signal)).map(configRow)
}

function attemptedError(cause: unknown): AiModelsApiError {
  const error = aiModelsError(cause)
  return new AiModelsApiError(error.key, error.detail, error.explicit, true)
}

export async function addAiModelConfig(input: AiModelConfigInput): Promise<AiModelConfig> {
  const payload = {
    tenantId: requireId(input.tenantId), modelId: inputText(input.modelId), modelName: inputText(input.modelName),
    provider: inputText(input.provider), userName: input.userName === undefined ? '' : input.userName,
    cloudType: 1, enabled: true,
  }
  if (payload.provider !== 'OCI' || typeof payload.userName !== 'string') return invalidInput()
  // Preserve the legacy global-modelId policy, including disabled configs. There is
  // no database uniqueness constraint, so this read cannot guarantee cross-session exclusion.
  const existing = await listAiModelConfigs()
  if (existing.some(row => row.modelId === payload.modelId)) throw new AiModelsApiError('alreadyConfigured', '', true)
  try {
    const row = configRow(await tenantPost<unknown>('/system/updateTelegramAiConfig', payload, writeConfig))
    if (row.tenantId !== payload.tenantId || row.modelId !== payload.modelId || row.modelName !== payload.modelName
      || row.provider !== payload.provider || row.cloudType !== 1 || row.enabled !== true) return invalidResponse()
    return row
  } catch (cause) { throw attemptedError(cause) }
}

export async function setAiModelConfigEnabled(id: string, enabled: boolean): Promise<AiModelConfig> {
  const configId = requireId(id)
  if (typeof enabled !== 'boolean') return invalidInput()
  const current = (await readConfigDtos()).find(row => identifier(row.id) === configId)
  if (!current) throw new AiModelsApiError('configMissing', '', true)
  const before = configRow(current)
  if (before.cloudType !== 1) return invalidResponse()
  // saveOrUpdateConfig replaces these advanced fields, even when omitted. Fetch a
  // fresh private snapshot and explicitly preserve them instead of sending {id, enabled}.
  // The DTO exposes no @Version/ETag, so the existing endpoint cannot make this atomic.
  const payload = {
    id: configId, tenantId: current.tenantId ?? null, modelId: nullableText(current.modelId),
    modelName: nullableText(current.modelName), provider: nullableText(current.provider), cloudType: 1, enabled,
    apiKey: nullableText(current.apiKey), baseUrl: nullableText(current.baseUrl),
    systemPrompt: nullableText(current.systemPrompt), maxTokens: integer(current.maxTokens),
    maxHistoryMessages: integer(current.maxHistoryMessages),
    // temperature is intentionally absent: the actual service does not write it.
  }
  try {
    const row = configRow(await tenantPost<unknown>('/system/updateTelegramAiConfig', payload, writeConfig))
    if (row.id !== configId || row.enabled !== enabled || row.cloudType !== 1
      || row.tenantId !== before.tenantId || row.modelId !== before.modelId) return invalidResponse()
    return row
  } catch (cause) { throw attemptedError(cause) }
}

export async function deleteAiModelConfig(id: string): Promise<void> {
  const configId = requireId(id)
  const headers = new AxiosHeaders()
  const csrfToken = tenantCsrfToken()
  const csrfHeader = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
  if (csrfToken) headers.set(csrfHeader, csrfToken)
  try {
    // The shared interceptor unwraps data. Only an empty successful response is valid here.
    const body: unknown = await request.delete(`/system/deleteTelegramAiConfig/${encodeURIComponent(configId)}`, {
      ...writeConfig, silent: true, headers,
    })
    if (body !== undefined && body !== null && body !== '') return invalidResponse()
  } catch (cause) {
    if (isAxiosError(cause) && cause.response?.status === 404) throw new AiModelsApiError('configMissing', '', true, true)
    throw attemptedError(cause)
  }
}

/** Updates every OCI config, irrespective of selected tenant or either local page. */
export async function setAllAiModelConfigsEnabled(enabled: boolean): Promise<AiModelBatchResult> {
  if (typeof enabled !== 'boolean') return invalidInput()
  try {
    const body = await tenantPost<unknown>('/system/batchToggleTelegramAiConfigs', { enabled }, writeConfig)
    if (!object(body) || body.enabled !== enabled) return invalidResponse()
    const updatedCount = integer(body.updatedCount)
    if (updatedCount === null || updatedCount < 0) return invalidResponse()
    return { updatedCount, enabled, message: text(body.message) }
  } catch (cause) { throw attemptedError(cause) }
}

function detailText(value: unknown): string {
  if (typeof value !== 'string') return ''
  const detail = value.trim()
  // A redirected login document or gateway error page is not a business error message.
  return !detail || /^[<{\[]/.test(detail) ? '' : detail.slice(0, 1000)
}

/** Strip Axios request/response objects so hidden configuration values are not retained. */
export function aiModelsError(cause: unknown): AiModelsApiError {
  if (cause instanceof AiModelsApiError) return cause
  if (isCancel(cause)) return new AiModelsApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  let detail = detailText(body)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = detailText(body[key])
      if (detail) break
    }
  }
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  const explicit = (httpError && !!cause.response) || (object(body) && body.success === false)
  return new AiModelsApiError(timeout ? 'timeout' : 'requestFailed', detail, explicit)
}

/** Preflight failures are safe to retry; a failed write requires a fresh read first. */
export function isAiModelsWriteUncertain(cause: unknown): boolean {
  return aiModelsError(cause).writeAttempted
}
