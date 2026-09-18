import { tenantCsrfToken } from './tenant'
import { checkSession, handleSessionResponse } from '@/utils/session'

export const MAX_BACKUP_BYTES = 10 * 1024 * 1024
export interface MigrationExportArtifact { blob: Blob; masterKey: string; filename: string }
export interface MigrationTableResult { table: string; importedRows: number; preservedRows: number }
export interface MigrationImportReceipt {
  formatVersion: 1 | 2
  importedRows: number
  preservedRows: number
  tables: MigrationTableResult[]
}
export type MigrationFailureOutcome = 'rejected' | 'rolledBack' | 'unknown'
export type MigrationErrorKey = 'invalidFile' | 'invalidKey' | 'unsupportedFormat' | 'invalidSql'
  | 'schemaMismatch' | 'duplicateData' | 'limitExceeded' | 'importFailed' | 'invalidResponse'
  | 'requestFailed' | 'unauthorized' | 'forbidden' | 'cancelled' | 'downloadFailed'
export class MigrationApiError extends Error {
  constructor(public key: MigrationErrorKey, public detail = '', public outcome: MigrationFailureOutcome | null = null) {
    super(key)
    this.name = 'MigrationApiError'
  }
}
const EXPORT_PATH = '/migration/exportEncrypted'
const IMPORT_PATH = '/migration/importEncryptedResult'
const BEGIN = '-----BEGIN OCI-START MIGRATION-----'
const END = '-----END OCI-START MIGRATION-----'
const serverErrors = new Set<MigrationErrorKey>(['invalidFile', 'invalidKey', 'unsupportedFormat',
  'invalidSql', 'schemaMismatch', 'duplicateData', 'limitExceeded', 'importFailed'])
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function fail(key: MigrationErrorKey, outcome: MigrationFailureOutcome | null = null): never { throw new MigrationApiError(key, '', outcome) }
function abortIfNeeded(signal?: AbortSignal): void { if (signal?.aborted) fail('cancelled') }
function headers(accept: string): Headers {
  const result = new Headers({ Accept: accept, 'X-Requested-With': 'XMLHttpRequest' })
  const token = tenantCsrfToken()
  if (token) result.set(document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN', token)
  return result
}
function base64Length(value: string): number | null {
  if (!value || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return null
  const padding = value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0
  if ((padding && value.length % 4 !== 0) || (!padding && value.length % 4 === 1)) return null
  return Math.floor(value.length * 3 / 4) - padding
}
export function normalizeMigrationKey(value: string): string {
  if (typeof value !== 'string') return fail('invalidKey', 'rejected')
  const candidate = value.trim()
  if (base64Length(candidate) !== 32) return fail('invalidKey', 'rejected')
  try {
    const decoded = atob(candidate)
    if (decoded.length !== 32) return fail('invalidKey', 'rejected')
    return btoa(decoded)
  } catch { return fail('invalidKey', 'rejected') }
}
function verifyEnvelope(bytes: Uint8Array): void {
  let value: string
  try { value = new TextDecoder('utf-8', { fatal: true }).decode(bytes) }
  catch { return fail('invalidFile', 'rejected') }
  const lines = value.trim().split(/\r?\n/)
  if (lines.length !== 4 || lines[0] !== BEGIN || lines[3] !== END
    || !lines[1]?.startsWith('IV:') || !lines[2]?.startsWith('DATA:')) return fail('invalidFile', 'rejected')
  const iv = lines[1].slice(3), data = lines[2].slice(5)
  if (base64Length(iv) !== 16) return fail('invalidFile', 'rejected')
  const bytesLength = base64Length(data)
  if (bytesLength === null || bytesLength < 16 || bytesLength % 16 !== 0) return fail('invalidFile', 'rejected')
}
async function readStream(stream: ReadableStream<Uint8Array> | null, limit: number, signal?: AbortSignal): Promise<Uint8Array> {
  if (!stream) return fail('invalidResponse')
  abortIfNeeded(signal)
  const reader = stream.getReader(), chunks: Uint8Array[] = []
  let size = 0
  const abort = () => { void reader.cancel().catch(() => undefined) }
  signal?.addEventListener('abort', abort, { once: true })
  try {
    while (true) {
      abortIfNeeded(signal)
      const chunk = await reader.read()
      abortIfNeeded(signal)
      if (chunk.done) break
      size += chunk.value.byteLength
      if (size > limit) { await reader.cancel(); return fail('limitExceeded') }
      chunks.push(chunk.value)
    }
    const bytes = new Uint8Array(size)
    let offset = 0
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
    return bytes
  } finally { signal?.removeEventListener('abort', abort); reader.releaseLock() }
}
export async function validateMigrationFile(file: File, signal?: AbortSignal): Promise<void> {
  if (!(file instanceof File) || !file.name.toLowerCase().endsWith('.enc') || file.size === 0) return fail('invalidFile', 'rejected')
  if (file.size > MAX_BACKUP_BYTES) return fail('limitExceeded', 'rejected')
  try {
    const bytes = await readStream(file.stream(), MAX_BACKUP_BYTES, signal)
    if (bytes.byteLength !== file.size) return fail('invalidFile', 'rejected')
    verifyEnvelope(bytes)
  } catch (cause) {
    const error = migrationError(cause)
    throw new MigrationApiError(error.key, '', error.key === 'cancelled' ? null : 'rejected')
  }
}
function validResponseUrl(response: Response, path: string): boolean {
  if (response.redirected || response.type === 'opaqueredirect' || !response.url) return false
  try {
    const url = new URL(response.url)
    return url.origin === window.location.origin && url.pathname === path
  } catch { return false }
}
function statusError(status: number): MigrationErrorKey {
  return status === 401 ? 'unauthorized' : status === 403 ? 'forbidden' : 'requestFailed'
}
export async function exportEncryptedBackup(signal?: AbortSignal): Promise<MigrationExportArtifact> {
  try {
    const response = await fetch(EXPORT_PATH, { method: 'GET', credentials: 'same-origin', redirect: 'manual',
      cache: 'no-store', headers: headers('application/octet-stream'), signal })
    handleSessionResponse({ status: response.status, url: response.url })
    if (response.type === 'opaqueredirect') void checkSession()
    if (!validResponseUrl(response, EXPORT_PATH)) return fail('invalidResponse')
    if (response.headers.get('Content-Type')?.split(';')[0]?.trim().toLowerCase() === 'application/json') {
      // Only inspect a bounded JSON error, never decode the backup as JSON.
      try {
        const bytes = await readStream(response.body, 64 * 1024, signal)
        const body: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes))
        handleSessionResponse({ body })
      } catch { /* Preserve the export's original response validation below. */ }
    }
    if (!response.ok) return fail(statusError(response.status))
    if (response.headers.get('Content-Type')?.split(';')[0]?.trim().toLowerCase() !== 'application/octet-stream') return fail('invalidResponse')
    let masterKey: string
    try { masterKey = normalizeMigrationKey(response.headers.get('X-MASTER-KEY') || '') }
    catch { return fail('invalidResponse') }
    const length = response.headers.get('Content-Length')
    if (length !== null && (!/^\d+$/.test(length) || !Number.isSafeInteger(Number(length)))) return fail('invalidResponse')
    if (length !== null && Number(length) > MAX_BACKUP_BYTES) { await response.body?.cancel(); return fail('limitExceeded') }
    const bytes = await readStream(response.body, MAX_BACKUP_BYTES, signal)
    const encoding = response.headers.get('Content-Encoding')
    if (length !== null && (!encoding || encoding === 'identity') && Number(length) !== bytes.byteLength) return fail('invalidResponse')
    try { verifyEnvelope(bytes) } catch { return fail('invalidResponse') }
    abortIfNeeded(signal)
    // readStream creates this contiguous, zero-offset ArrayBuffer itself.
    return { blob: new Blob([bytes.buffer as ArrayBuffer], { type: 'application/octet-stream' }), masterKey,
      filename: 'oci-start_migration_' + Date.now() + '.enc' }
  } catch (cause) { throw migrationError(cause) }
}
function count(value: unknown): number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : fail('invalidResponse')
}
function parseReceipt(body: Record<string, unknown>): MigrationImportReceipt {
  if (body.success !== true || ![1, 2].includes(body.formatVersion as number) || !Array.isArray(body.tables)) return fail('invalidResponse')
  const seen = new Set<string>()
  const tables = body.tables.map((value): MigrationTableResult => {
    if (!object(value) || typeof value.table !== 'string' || !/^[A-Za-z][A-Za-z0-9_]{0,127}$/.test(value.table)
      || seen.has(value.table)) return fail('invalidResponse')
    seen.add(value.table)
    return { table: value.table, importedRows: count(value.importedRows), preservedRows: count(value.preservedRows) }
  })
  const importedRows = count(body.importedRows), preservedRows = count(body.preservedRows)
  if (importedRows === 0 && preservedRows === 0) return fail('invalidResponse')
  if (tables.reduce((sum, table) => sum + table.importedRows, 0) !== importedRows
    || tables.reduce((sum, table) => sum + table.preservedRows, 0) !== preservedRows) return fail('invalidResponse')
  return { formatVersion: body.formatVersion as 1 | 2, importedRows, preservedRows, tables }
}
/** Once dispatched, importing has no abort, timeout, retry or fallback endpoint. */
export async function importEncryptedBackup(file: File, masterKey: string): Promise<MigrationImportReceipt> {
  const key = normalizeMigrationKey(masterKey)
  await validateMigrationFile(file)
  const form = new FormData()
  form.append('file', file, file.name); form.append('masterKey', key)
  try {
    const response = await fetch(IMPORT_PATH, { method: 'POST', credentials: 'same-origin', redirect: 'manual',
      cache: 'no-store', headers: headers('application/json'), body: form })
    handleSessionResponse({ status: response.status, url: response.url })
    if (response.type === 'opaqueredirect') void checkSession()
    if (!validResponseUrl(response, IMPORT_PATH)) return fail('invalidResponse', 'unknown')
    if (response.headers.get('Content-Type')?.split(';')[0]?.trim().toLowerCase() !== 'application/json') return fail(statusError(response.status), 'unknown')
    const bytes = await readStream(response.body, 64 * 1024)
    let body: unknown
    try { body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) }
    catch { return fail('invalidResponse', 'unknown') }
    handleSessionResponse({ body })
    if (!object(body)) return fail('invalidResponse', 'unknown')
    // SaToken's global preHandle rejects this exact receipt before the controller runs.
    if (response.status === 401 && body.code === 401) return fail('unauthorized', 'rejected')
    if (response.ok && body.success === true) return parseReceipt(body)
    const key = typeof body.error === 'string' && body.error.startsWith('migration.')
      ? body.error.slice('migration.'.length) as MigrationErrorKey : null
    if (body.success === false && key && serverErrors.has(key)
      && ['rejected', 'rolledBack', 'unknown'].includes(body.outcome as string)) {
      return fail(key, body.outcome as MigrationFailureOutcome)
    }
    return fail(response.ok ? 'invalidResponse' : statusError(response.status), 'unknown')
  } catch (cause) {
    if (cause instanceof MigrationApiError && cause.outcome !== null) throw migrationError(cause)
    const error = migrationError(cause)
    throw new MigrationApiError(error.key, '', 'unknown')
  } finally { form.delete('masterKey'); form.delete('file') }
}
export function migrationError(cause: unknown): MigrationApiError {
  if (cause instanceof MigrationApiError) return new MigrationApiError(cause.key, '', cause.outcome)
  if (object(cause) && cause.name === 'AbortError') return new MigrationApiError('cancelled')
  return new MigrationApiError('requestFailed')
}
