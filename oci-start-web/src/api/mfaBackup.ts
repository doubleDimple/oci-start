import { tenantCsrfToken } from './tenant'
import { checkSession, handleSessionResponse } from '@/utils/session'

export const MFA_MAX_ENTRIES = 5000
export const MFA_MAX_BATCH = 100
export const MFA_MAX_IMAGE_BYTES = 5 * 1024 * 1024
export interface MfaEntry { id: string; keyName: string; issuer: string; createTime: string | null; revision: string }
export interface MfaCandidate { keyName: string; issuer: string; secretKey: string }
export type MfaPreviewInput = { mode: 'manual'; keyName: string; issuer: string; secretKey: string }
  | { mode: 'uri'; qrUrl: string } | { mode: 'image'; qrCode: File }
export interface MfaPreviewResult { entries: MfaCandidate[]; partialBatch: boolean; batchIndex: number; batchSize: number }
export interface MfaMaterial { id: string; keyName: string; issuer: string; revision: string; secretKey: string; qrCode: string }
export interface MfaImportResult { importedCount: number; preservedCount: number; totalCount: number; ids: string[] }
export interface MfaExportEntry extends MfaCandidate { id: string }
export type MfaCodeErrorKey = 'notFound' | 'invalidSecret' | 'requestFailed' | 'invalidResponse'
export interface MfaCodeItem { id: string; code: string | null; errorKey: MfaCodeErrorKey | null }
export interface MfaCodesBatch { serverTime: number; expiresAt: number; items: MfaCodeItem[] }
export type MfaErrorKey = 'invalidInput' | 'invalidSecret' | 'invalidUri' | 'unsupportedParameters'
  | 'invalidImage' | 'imageTooLarge' | 'qrNotFound' | 'qrGenerationFailed' | 'tooManyEntries' | 'notFound' | 'conflict'
  | 'limitExceeded' | 'requestFailed' | 'invalidResponse' | 'unauthorized' | 'forbidden' | 'timeout'
  | 'cancelled' | 'downloadFailed' | 'copyFailed'
export class MfaApiError extends Error {
  constructor(public key: MfaErrorKey, public detail = '', public writeAttempted = false) {
    super(key); this.name = 'MfaApiError'
  }
}
const BASE = '/api/mfa'
const MAX_LONG = '9223372036854775807'
const errors = new Set<MfaErrorKey>(['invalidInput', 'invalidSecret', 'invalidUri', 'unsupportedParameters',
  'invalidImage', 'imageTooLarge', 'qrNotFound', 'qrGenerationFailed', 'tooManyEntries', 'notFound', 'conflict',
  'limitExceeded', 'requestFailed', 'unauthorized', 'forbidden'])
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function invalid(): never { throw new MfaApiError('invalidResponse') }
function bad(key: MfaErrorKey = 'invalidInput'): never { throw new MfaApiError(key) }
export function isMfaId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d*$/.test(value)
    && (value.length < MAX_LONG.length || (value.length === MAX_LONG.length && value <= MAX_LONG))
}
export function isMfaRevision(value: unknown): value is string { return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value) }
function text(value: unknown, limit = 255): string {
  return typeof value === 'string' && value.length <= limit ? value : invalid()
}
function integer(value: unknown, min = 0): number { return typeof value === 'number' && Number.isSafeInteger(value) && value >= min ? value : invalid() }
function identity(value: unknown): string { return isMfaId(value) ? value : invalid() }
function ids(values: string[], max: number): string[] {
  if (!Array.isArray(values)) return bad()
  if (!values.length || values.length > max || values.some(value => !isMfaId(value))
    || new Set(values).size !== values.length) return bad(values.length > max ? 'tooManyEntries' : 'invalidInput')
  return [...values]
}
function entry(value: unknown): MfaEntry {
  if (!object(value) || !isMfaRevision(value.revision)) return invalid()
  const time = value.createTime
  if (time !== null && (typeof time !== 'string' || !/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?$/.test(time))) return invalid()
  return { id: identity(value.id), keyName: text(value.keyName), issuer: text(value.issuer),
    createTime: time, revision: value.revision }
}
export function normalizeMfaCandidate(value: MfaCandidate): MfaCandidate {
  if (!value || typeof value.keyName !== 'string' || typeof value.issuer !== 'string' || typeof value.secretKey !== 'string') return bad()
  const keyName = value.keyName.trim(), issuer = value.issuer.trim(), secretKey = value.secretKey.replace(/\s/g, '').toUpperCase()
  if (!keyName || keyName.length > 255 || issuer.length > 255) return bad()
  if (!secretKey || secretKey.length > 255 || !/^[A-Z2-7]+={0,6}$/.test(secretKey)) return bad('invalidSecret')
  return { keyName, issuer, secretKey }
}
function candidate(value: unknown): MfaCandidate {
  if (!object(value)) return invalid()
  return { keyName: text(value.keyName), issuer: text(value.issuer), secretKey: text(value.secretKey) }
}
async function jsonBody(response: Response, max: number): Promise<unknown> {
  if (!response.body) return invalid()
  const reader = response.body.getReader(), chunks: Uint8Array[] = []
  let size = 0
  try {
    while (true) {
      const next = await reader.read()
      if (next.done) break
      size += next.value.byteLength
      if (size > max) { await reader.cancel(); return invalid() }
      chunks.push(next.value)
    }
    const bytes = new Uint8Array(size)
    let offset = 0
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
    try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) } catch { return invalid() }
  } finally { reader.releaseLock() }
}
async function request<T>(path: string, method: 'GET' | 'POST', payload: object | FormData | undefined,
  parse: (body: Record<string, unknown>) => T, options: { signal?: AbortSignal; write?: boolean; max?: number } = {}): Promise<T> {
  const controller = options.write ? undefined : new AbortController()
  let timedOut = false, declaredRejection = false
  const abort = () => controller?.abort()
  options.signal?.addEventListener('abort', abort, { once: true })
  if (options.signal?.aborted) abort()
  const timer = controller ? window.setTimeout(() => { timedOut = true; controller.abort() }, 30_000) : undefined
  try {
    const headers = new Headers({ Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' })
    const token = tenantCsrfToken()
    if (token) headers.set(document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN', token)
    if (payload && !(payload instanceof FormData)) headers.set('Content-Type', 'application/json')
    const response = await fetch(BASE + path, { method, headers, credentials: 'same-origin', cache: 'no-store',
      redirect: 'manual', signal: controller?.signal,
      body: payload ? payload instanceof FormData ? payload : JSON.stringify(payload) : undefined })
    handleSessionResponse({ status: response.status, url: response.url })
    if (response.type === 'opaqueredirect') void checkSession()
    const url = response.url ? new URL(response.url) : null
    if (response.redirected || response.type === 'opaqueredirect' || !url || url.origin !== window.location.origin || url.pathname !== BASE + path) return invalid()
    if (response.headers.get('Content-Type')?.split(';')[0]?.trim().toLowerCase() !== 'application/json') {
      throw new MfaApiError(response.status === 401 ? 'unauthorized' : response.status === 403 ? 'forbidden' : 'invalidResponse')
    }
    const body = await jsonBody(response, options.max ?? 16 * 1024 * 1024)
    handleSessionResponse({ body })
    if (!object(body)) return invalid()
    if (response.status === 401 && body.code === 401) { declaredRejection = true; throw new MfaApiError('unauthorized') }
    if (response.ok && body.success === true) return parse(body)
    if (body.success === false && typeof body.errorKey === 'string' && errors.has(body.errorKey as MfaErrorKey)) {
      declaredRejection = body.writeAttempted === false
      throw new MfaApiError(body.errorKey as MfaErrorKey)
    }
    return invalid()
  } catch (cause) {
    const error = mfaError(cause)
    throw new MfaApiError(timedOut ? 'timeout' : error.key, '', !!options.write && !declaredRejection)
  } finally {
    if (timer !== undefined) window.clearTimeout(timer)
    options.signal?.removeEventListener('abort', abort)
  }
}
export async function listMfaEntries(signal?: AbortSignal): Promise<MfaEntry[]> {
  return request('/entries', 'GET', undefined, body => {
    if (!Array.isArray(body.data) || body.data.length > MFA_MAX_ENTRIES) return invalid()
    const rows = body.data.map(entry)
    if (new Set(rows.map(row => row.id)).size !== rows.length) return invalid()
    return rows
  }, { signal })
}
export async function getMfaCodes(values: string[], signal?: AbortSignal): Promise<MfaCodesBatch> {
  const requested = ids(values, MFA_MAX_BATCH)
  return request('/codes', 'POST', { ids: requested }, body => {
    const serverTime = integer(body.serverTime, 1), expiresAt = integer(body.expiresAt, 1)
    if (expiresAt <= serverTime || expiresAt - serverTime > 30_000 || !Array.isArray(body.items) || body.items.length !== requested.length) return invalid()
    const seen = new Set<string>()
    const items = body.items.map((value): MfaCodeItem => {
      if (!object(value)) return invalid()
      const id = identity(value.id)
      if (!requested.includes(id) || seen.has(id)) return invalid()
      seen.add(id)
      if (typeof value.code === 'string' && /^\d{6}$/.test(value.code) && !value.errorKey) return { id, code: value.code, errorKey: null }
      const errorKey = ['notFound', 'invalidSecret', 'requestFailed'].includes(value.errorKey as string)
        ? value.errorKey as MfaCodeErrorKey : 'invalidResponse'
      return { id, code: null, errorKey }
    })
    return { serverTime, expiresAt, items }
  }, { signal, max: 128 * 1024 })
}
export async function getMfaMaterial(id: string, signal?: AbortSignal): Promise<MfaMaterial> {
  if (!isMfaId(id)) return bad()
  return request('/entries/' + id + '/material', 'GET', undefined, body => {
    if (!object(body.data) || body.data.id !== id || !isMfaRevision(body.data.revision)) return invalid()
    const qrCode = text(body.data.qrCode, 2 * 1024 * 1024)
    if (!/^iVBORw0KGgo[A-Za-z0-9+/]*={0,2}$/.test(qrCode)) return invalid()
    return { id, keyName: text(body.data.keyName), issuer: text(body.data.issuer), revision: body.data.revision,
      secretKey: text(body.data.secretKey), qrCode }
  }, { signal, max: 3 * 1024 * 1024 })
}
export async function previewMfa(input: MfaPreviewInput, signal?: AbortSignal): Promise<MfaPreviewResult> {
  const form = new FormData()
  form.append('mode', input.mode)
  if (input.mode === 'manual') {
    if (typeof input.secretKey !== 'string' || input.secretKey.length > 1024
      || typeof input.keyName !== 'string' || input.keyName.length > 255 || typeof input.issuer !== 'string' || input.issuer.length > 255) return bad()
    form.append('keyName', input.keyName); form.append('issuer', input.issuer); form.append('secretKey', input.secretKey)
  } else if (input.mode === 'uri') {
    if (typeof input.qrUrl !== 'string' || new TextEncoder().encode(input.qrUrl).length > 65_536 || !input.qrUrl.trim()) return bad('invalidUri')
    form.append('qrUrl', input.qrUrl)
  } else if (input.mode === 'image') {
    if (!(input.qrCode instanceof File) || !input.qrCode.size) return bad('invalidImage')
    if (input.qrCode.size > MFA_MAX_IMAGE_BYTES) return bad('imageTooLarge')
    form.append('qrCode', input.qrCode, input.qrCode.name)
  } else return bad()
  try {
    return await request('/preview', 'POST', form, body => {
      if (!object(body.data) || !Array.isArray(body.data.entries) || !body.data.entries.length
        || body.data.entries.length > MFA_MAX_BATCH || typeof body.data.partialBatch !== 'boolean') return invalid()
      const batchSize = integer(body.data.batchSize, 1), batchIndex = integer(body.data.batchIndex)
      if (batchIndex >= batchSize || body.data.partialBatch !== (batchSize > 1)) return invalid()
      return { entries: body.data.entries.map(candidate), partialBatch: body.data.partialBatch, batchIndex, batchSize }
    }, { signal, max: 1024 * 1024 })
  } finally { for (const key of ['secretKey', 'qrUrl', 'qrCode']) form.delete(key) }
}
export async function importMfaEntries(entries: MfaCandidate[]): Promise<MfaImportResult> {
  if (!Array.isArray(entries) || !entries.length || entries.length > MFA_MAX_BATCH) return bad('tooManyEntries')
  const snapshot = entries.map(normalizeMfaCandidate)
  try {
    return await request('/import', 'POST', { entries: snapshot }, body => {
      if (!object(body.data) || !Array.isArray(body.data.ids)) return invalid()
      const importedCount = integer(body.data.importedCount), preservedCount = integer(body.data.preservedCount)
      const totalCount = integer(body.data.totalCount, 1)
      if (totalCount !== snapshot.length || importedCount + preservedCount !== totalCount || body.data.ids.length !== totalCount) return invalid()
      return { importedCount, preservedCount, totalCount, ids: body.data.ids.map(identity) }
    }, { write: true, max: 128 * 1024 })
  } finally { snapshot.forEach(value => { value.secretKey = '' }) }
}
export async function deleteMfaEntry(id: string, revision: string): Promise<void> {
  if (!isMfaId(id) || !isMfaRevision(revision)) return bad()
  return request('/entries/' + id + '/delete', 'POST', { revision }, body => {
    if (!object(body.data) || body.data.id !== id) return invalid()
  }, { write: true, max: 128 * 1024 })
}
export async function exportMfaEntries(values: string[], signal?: AbortSignal): Promise<MfaExportEntry[]> {
  const requested = ids(values, MFA_MAX_ENTRIES)
  return request('/export', 'POST', { ids: requested }, body => {
    if (!Array.isArray(body.data) || body.data.length !== requested.length) return invalid()
    const rows = new Map<string, MfaExportEntry>()
    for (const value of body.data) {
      if (!object(value)) return invalid()
      const id = identity(value.id)
      if (!requested.includes(id) || rows.has(id)) return invalid()
      rows.set(id, { id, ...candidate(value) })
    }
    return requested.map(id => rows.get(id)!)
  }, { signal })
}
export function mfaError(cause: unknown): MfaApiError {
  if (cause instanceof MfaApiError) return new MfaApiError(cause.key, '', cause.writeAttempted)
  if (object(cause) && cause.name === 'AbortError') return new MfaApiError('cancelled')
  return new MfaApiError('requestFailed')
}
