import { tenantCsrfToken } from './tenant'
import { checkSession, handleSessionResponse } from '@/utils/session'

export const API_TOKEN_NAME_LIMIT = 255
export const API_TOKEN_DESCRIPTION_LIMIT = 1000
export const API_TOKEN_EXPIRATION_DAYS = [7, 30, 90, 180, 365] as const
export interface ApiTokenInput { tokenName: string; expirationDays: number; description: string }
export interface ApiTokenState {
  revision: string
  tokenName: string
  description: string
  enabled: boolean
  hasToken: boolean
  isExpired: boolean | null
  expirationDays: number
  createdAt: string | null
  expiresAt: string | null
  daysUntilExpiration: number | null
  allowSwaggerAccess: boolean
  serverTime: number
  expiresAtEpochMs: number | null
  serverTimeZone: string
}
export interface ApiTokenMaterial { metadata: ApiTokenState; tokenValue: string }
export type ApiTokenErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'unauthorized'
  | 'forbidden' | 'notFound' | 'conflict' | 'timeout' | 'cancelled' | 'saveMismatch'
export class ApiTokenApiError extends Error {
  constructor(public key: ApiTokenErrorKey, public detail = '', public writeAttempted = false) {
    super(key); this.name = 'ApiTokenApiError'
  }
}
const BASE = '/api/system'
const errorKeys = new Set<ApiTokenErrorKey>(['invalidInput', 'requestFailed', 'unauthorized', 'forbidden', 'notFound', 'conflict'])
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function invalid(): never { throw new ApiTokenApiError('invalidResponse') }
function bad(): never { throw new ApiTokenApiError('invalidInput') }
export function isApiTokenRevision(value: unknown): value is string { return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value) }
function text(value: unknown, max: number): string { return typeof value === 'string' && value.length <= max ? value : invalid() }
function boolean(value: unknown): boolean { return typeof value === 'boolean' ? value : invalid() }
function integer(value: unknown, minimum = 0): number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum ? value : invalid()
}
function localTime(value: unknown): string | null {
  return value === null || (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?$/.test(value)) ? value : invalid()
}
function state(value: unknown): ApiTokenState {
  if (!object(value) || !isApiTokenRevision(value.revision)) return invalid()
  const expirationDays = integer(value.expirationDays, 1)
  if (expirationDays > 365) return invalid()
  return {
    revision: value.revision, tokenName: text(value.tokenName, API_TOKEN_NAME_LIMIT),
    description: text(value.description, API_TOKEN_DESCRIPTION_LIMIT), enabled: boolean(value.enabled),
    hasToken: boolean(value.hasToken), isExpired: value.isExpired === null ? null : boolean(value.isExpired), expirationDays,
    createdAt: localTime(value.createdAt), expiresAt: localTime(value.expiresAt),
    daysUntilExpiration: value.daysUntilExpiration === null ? null : integer(value.daysUntilExpiration),
    allowSwaggerAccess: boolean(value.allowSwaggerAccess), serverTime: integer(value.serverTime, 1),
    expiresAtEpochMs: value.expiresAtEpochMs === null ? null : integer(value.expiresAtEpochMs, 1),
    serverTimeZone: text(value.serverTimeZone, 100),
  }
}
function material(value: unknown): ApiTokenMaterial {
  if (!object(value)) return invalid()
  const metadata = state(value.metadata)
  const tokenValue = text(value.tokenValue, 4096)
  if (!tokenValue || !/^[\x21-\x7e]+$/.test(tokenValue) || !metadata.hasToken) return invalid()
  return { metadata, tokenValue }
}
export function normalizeApiTokenInput(value: ApiTokenInput): ApiTokenInput {
  if (!value || typeof value.tokenName !== 'string' || typeof value.description !== 'string') return bad()
  const tokenName = value.tokenName.trim(), description = value.description
  if (!tokenName || tokenName.length > API_TOKEN_NAME_LIMIT || description.length > API_TOKEN_DESCRIPTION_LIMIT
    || !Number.isInteger(value.expirationDays) || value.expirationDays < 1 || value.expirationDays > 365) return bad()
  return { tokenName, description, expirationDays: value.expirationDays }
}
async function readJson(response: Response): Promise<unknown> {
  if (!response.body) return invalid()
  const reader = response.body.getReader(), chunks: Uint8Array[] = []
  let size = 0
  try {
    while (true) {
      const next = await reader.read()
      if (next.done) break
      size += next.value.byteLength
      if (size > 64 * 1024) { await reader.cancel(); return invalid() }
      chunks.push(next.value)
    }
    const bytes = new Uint8Array(size)
    let offset = 0
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
    try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) } catch { return invalid() }
  } finally { reader.releaseLock() }
}
async function request<T>(path: string, parse: (value: unknown) => T,
  options: { signal?: AbortSignal; payload?: object; revision?: string; write?: boolean } = {}): Promise<T> {
  const controller = options.write ? undefined : new AbortController()
  let timedOut = false, declaredRejection = false
  const abort = () => controller?.abort()
  options.signal?.addEventListener('abort', abort, { once: true })
  if (options.signal?.aborted) abort()
  const timer = controller ? window.setTimeout(() => { timedOut = true; controller.abort() }, 30_000) : undefined
  try {
    const headers = new Headers({ Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' })
    const csrf = tenantCsrfToken()
    if (csrf) headers.set(document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN', csrf)
    if (options.payload) headers.set('Content-Type', 'application/json')
    if (options.revision) headers.set('If-Match', options.revision)
    const response = await fetch(BASE + path, { method: options.write ? 'POST' : 'GET',
      headers, credentials: 'same-origin', cache: 'no-store', redirect: 'manual', signal: controller?.signal,
      body: options.payload ? JSON.stringify(options.payload) : undefined })
    handleSessionResponse({ status: response.status, url: response.url })
    if (response.type === 'opaqueredirect') void checkSession()
    const actual = response.url ? new URL(response.url) : null, expected = new URL(BASE + path, window.location.origin)
    if (response.redirected || response.type === 'opaqueredirect' || !actual
      || actual.origin !== expected.origin || actual.pathname !== expected.pathname) return invalid()
    if (response.headers.get('Content-Type')?.split(';')[0]?.trim().toLowerCase() !== 'application/json') {
      throw new ApiTokenApiError(response.status === 401 ? 'unauthorized' : response.status === 403 ? 'forbidden' : 'invalidResponse')
    }
    const body = await readJson(response)
    handleSessionResponse({ body })
    if (!object(body)) return invalid()
    if (response.status === 401 && body.code === 401) { declaredRejection = true; throw new ApiTokenApiError('unauthorized') }
    if (response.ok && body.success === true) return parse(body.data)
    if (body.success === false && typeof body.errorKey === 'string' && errorKeys.has(body.errorKey as ApiTokenErrorKey)) {
      declaredRejection = body.writeAttempted === false
      throw new ApiTokenApiError(body.errorKey as ApiTokenErrorKey)
    }
    return invalid()
  } catch (cause) {
    const error = apiTokenError(cause)
    throw new ApiTokenApiError(timedOut ? 'timeout' : error.key, '', !!options.write && !declaredRejection)
  } finally {
    if (timer !== undefined) window.clearTimeout(timer)
    options.signal?.removeEventListener('abort', abort)
  }
}
export async function loadApiTokenState(signal?: AbortSignal): Promise<ApiTokenState> {
  return request('/apiTokenConfigs', state, { signal })
}
export async function loadApiTokenMaterial(revision: string, signal?: AbortSignal): Promise<ApiTokenMaterial> {
  if (!isApiTokenRevision(revision)) return bad()
  return request('/apiTokenMaterial?revision=' + revision, value => {
    const result = material(value)
    if (result.metadata.revision !== revision) return invalid()
    return result
  }, { signal })
}
export async function generateApiToken(input: ApiTokenInput, revision: string): Promise<ApiTokenMaterial> {
  if (!isApiTokenRevision(revision)) return bad()
  const normalized = normalizeApiTokenInput(input)
  return request('/generateApiToken', material, {
    write: true, revision, payload: { ...normalized, enabled: true, allowSwaggerAccess: true },
  })
}
export async function revokeApiToken(revision: string): Promise<ApiTokenState> {
  if (!isApiTokenRevision(revision)) return bad()
  return request('/revokeApiToken', state, { write: true, revision })
}
export function apiTokenError(cause: unknown): ApiTokenApiError {
  if (cause instanceof ApiTokenApiError) return new ApiTokenApiError(cause.key, '', cause.writeAttempted)
  if (cause instanceof DOMException && cause.name === 'AbortError') return new ApiTokenApiError('cancelled')
  return new ApiTokenApiError('requestFailed')
}
