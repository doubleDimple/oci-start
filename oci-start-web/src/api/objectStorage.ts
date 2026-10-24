import { isAxiosError, isCancel, type AxiosProgressEvent } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export const STORAGE_PREVIEW_LIMIT = 50 * 1024 * 1024
export const STORAGE_MULTIPART_CHUNK_SIZE = 10 * 1024 * 1024
export type StorageAccessType = 'NoPublicAccess' | 'ObjectRead' | 'ObjectReadWithoutList'

export interface StorageTenant {
  id: string
  tenantId: string
  userName: string
  tenancyName: string
  region: string
  isHomeRegion: boolean | null
}
export interface StorageBucket {
  name: string
  namespace: string
  timeCreated: string
  /** Legacy accessType freeform tag, not an authoritative live permission lookup. */
  publicAccess: string
}
export interface StorageObject { name: string; size: number | null; timeModified: string }
export interface StorageBucketContext { tenantId: string; namespace: string; bucketName: string }
export interface StorageObjectContext extends StorageBucketContext { objectName: string }
export interface StorageBucketQuery { tenantId: string; limit?: number; pageToken?: string | null }
export interface StorageObjectQuery extends StorageBucketContext { limit?: number; startToken?: string | null; prefix?: string }
export interface StorageBucketPage { items: StorageBucket[]; nextPage: string | null }
export interface StorageObjectPage { items: StorageObject[]; nextStartWith: string | null }
export interface StorageCreateBucketInput { tenantId: string; bucketName: string; publicAccessType: StorageAccessType }

export interface StorageMultipartPart { partNum: number; etag: string }
export interface StorageMultipartContext extends StorageObjectContext { uploadId: string }
export interface StorageMultipartInitInput extends StorageObjectContext { contentType: string; totalSize: number; chunkSize: number }
export interface StorageMultipartInitResult { uploadId: string; objectName: string; namespace: string; bucketName: string }
export interface StorageMultipartPartInput extends StorageMultipartContext { partNumber: number }
export interface StorageMultipartCommitInput extends StorageMultipartContext { parts: StorageMultipartPart[] }
export interface StorageMultipartRecord {
  id: string
  uploadId: string
  objectName: string
  bucketName: string
  namespace: string
  totalSize: number | null
  chunkSize: number | null
  totalParts: number | null
  completedPartCount: number
  completedParts: StorageMultipartPart[]
  createTime: string
}
export interface StorageUploadProgress { loaded: number; total?: number }
export interface StorageUploadOptions {
  /** Explicit user cancellation only; aborting transmission cannot roll back OCI writes. */
  signal?: AbortSignal
  onProgress?: (progress: StorageUploadProgress) => void
  objectName?: string
}

export type StorageErrorKey = 'invalidResponse' | 'invalidInput' | 'invalidUrl' | 'requestFailed' | 'timeout' | 'cancelled' | 'previewTooLarge'
export class StorageApiError extends Error {
  constructor(public key: StorageErrorKey, public detail = '', public explicit = false) {
    super(key)
    this.name = 'StorageApiError'
  }
}
export { StorageApiError as StorageError }

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new StorageApiError('invalidResponse') }
function invalidInput(): never { throw new StorageApiError('invalidInput', '', true) }
export function isStorageTenantId(value: unknown): value is string {
  const max = '9223372036854775807'
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value)
    && (value.length < max.length || value <= max)
}
function requireId(value: unknown): string { return isStorageTenantId(value) ? value : invalidInput() }
function identifier(value: unknown): string {
  if (isStorageTenantId(value)) return value
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? String(value) : invalidResponse()
}
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalidResponse() }
function nonBlank(value: unknown): value is string { return typeof value === 'string' && value.trim().length > 0 && !value.includes('\0') }
function requiredText(value: unknown): string { return nonBlank(value) ? value : invalidResponse() }
function inputText(value: unknown): string { return nonBlank(value) ? value : invalidInput() }
function nullableCount(value: unknown): number | null {
  if (value == null) return null
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^(0|[1-9]\d*)$/.test(value))) return invalidResponse()
  const number = Number(value)
  if (!Number.isSafeInteger(number)) return null
  return number >= 0 ? number : invalidResponse()
}
function integer(value: unknown): number {
  const number = nullableCount(value)
  return number === null ? invalidResponse() : number
}
function positive(value: unknown): value is number { return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 }
function inputPartNumber(value: unknown): number {
  return positive(value) && value <= 2147483647 ? value : invalidInput()
}
function limitValue(value = 5): number { return positive(value) && value <= 1000 ? value : invalidInput() }
function cursor(value: unknown): string | null {
  if (value == null || value === '') return null
  return nonBlank(value) ? value : invalidResponse()
}
function inputCursor(value: unknown): string | undefined {
  if (value == null || value === '') return undefined
  return nonBlank(value) ? value : invalidInput()
}
function bucketContext(input: StorageBucketContext): StorageBucketContext {
  return { tenantId: requireId(input.tenantId), namespace: inputText(input.namespace), bucketName: inputText(input.bucketName) }
}
function objectContext(input: StorageObjectContext): StorageObjectContext {
  return { ...bucketContext(input), objectName: inputText(input.objectName) }
}
function multipartContext(input: StorageMultipartContext): StorageMultipartContext {
  return { ...objectContext(input), uploadId: inputText(input.uploadId) }
}

// Preserve large Java Long tokens before JSON.parse; quoted JSON strings remain intact.
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
function accepted(value: unknown): Record<string, unknown> {
  // The shared client handles success:false, business codes, authentication and CSRF.
  if (!object(value) || value.success !== true) return invalidResponse()
  return value
}
function dataObject(value: unknown): Record<string, unknown> {
  const data = accepted(value).data
  return object(data) ? data : invalidResponse()
}
function part(value: unknown): StorageMultipartPart {
  if (!object(value)) return invalidResponse()
  const partNum = integer(value.partNum)
  if (partNum < 1 || partNum > 2147483647) return invalidResponse()
  return { partNum, etag: requiredText(value.etag) }
}

/** This existing endpoint is restricted to OCI parent tenants (up to 1000 records). */
export async function listStorageTenants(signal?: AbortSignal): Promise<StorageTenant[]> {
  const body = await tenantGet<unknown>('/tenants/listParentTenants', undefined, { ...responseConfig, signal })
  if (!Array.isArray(body)) return invalidResponse()
  const rows = body.map(value => {
    if (!object(value) || (value.isHomeRegion != null && typeof value.isHomeRegion !== 'boolean')) return invalidResponse()
    return { id: identifier(value.id), tenantId: text(value.tenantId), userName: text(value.userName),
      tenancyName: text(value.tenancyName), region: text(value.region), isHomeRegion: (value.isHomeRegion as boolean | null | undefined) ?? null }
  })
  if (new Set(rows.map(row => row.id)).size !== rows.length) return invalidResponse()
  return rows
}
export async function getStorageNamespace(tenantId: string, signal?: AbortSignal): Promise<string> {
  const body = dataObject(await tenantGet<unknown>('/oci/storage/namespace', { tenantId: requireId(tenantId) }, { ...responseConfig, signal }))
  return requiredText(body.namespace)
}
export async function listStorageBuckets(query: StorageBucketQuery, signal?: AbortSignal): Promise<StorageBucketPage> {
  const limit = limitValue(query.limit)
  const pageToken = inputCursor(query.pageToken)
  const body = dataObject(await tenantGet<unknown>('/oci/storage/buckets', { tenantId: requireId(query.tenantId), limit, pageToken }, { ...responseConfig, signal }))
  if (!Array.isArray(body.items)) return invalidResponse()
  const items = body.items.map(value => {
    if (!object(value)) return invalidResponse()
    return { name: requiredText(value.name), namespace: requiredText(value.namespace), timeCreated: text(value.timeCreated), publicAccess: text(value.publicAccess) }
  })
  const nextPage = cursor(body.nextPage)
  if (items.length > limit || new Set(items.map(row => `${row.namespace}\0${row.name}`)).size !== items.length
    || (nextPage !== null && nextPage === pageToken)) return invalidResponse()
  return { items, nextPage }
}
export async function listStorageObjects(query: StorageObjectQuery, signal?: AbortSignal): Promise<StorageObjectPage> {
  const context = bucketContext(query)
  const limit = limitValue(query.limit)
  const startToken = inputCursor(query.startToken)
  if (query.prefix !== undefined && typeof query.prefix !== 'string') return invalidInput()
  const body = dataObject(await tenantGet<unknown>('/oci/storage/objects', { ...context, limit, startToken, prefix: query.prefix }, { ...responseConfig, signal }))
  if (!Array.isArray(body.items)) return invalidResponse()
  const items = body.items.map(value => {
    if (!object(value)) return invalidResponse()
    return { name: requiredText(value.name), size: nullableCount(value.size), timeModified: text(value.timeModified) }
  })
  const nextStartWith = cursor(body.nextStartWith)
  if (items.length > limit || new Set(items.map(row => row.name)).size !== items.length
    || (nextStartWith !== null && nextStartWith === startToken)) return invalidResponse()
  return { items, nextStartWith }
}
export async function createStorageBucket(input: StorageCreateBucketInput): Promise<void> {
  const tenantId = requireId(input.tenantId)
  const bucketName = inputText(input.bucketName).trim()
  if (!['NoPublicAccess', 'ObjectRead', 'ObjectReadWithoutList'].includes(input.publicAccessType)) return invalidInput()
  accepted(await tenantPost<unknown>('/oci/storage/bucket/create', { tenantId, bucketName, publicAccessType: input.publicAccessType }, writeConfig))
}
export async function deleteStorageBucket(input: StorageBucketContext): Promise<void> {
  // The backend calls deleteBucket only; it does not recursively empty the bucket.
  accepted(await tenantPost<unknown>('/oci/storage/bucket/delete', bucketContext(input), writeConfig))
}
export async function deleteStorageObject(input: StorageObjectContext): Promise<void> {
  accepted(await tenantPost<unknown>('/oci/storage/object/delete', objectContext(input), writeConfig))
}
export async function createStoragePresignedUrl(input: StorageObjectContext, validitySeconds = 3600): Promise<string> {
  const context = objectContext(input)
  if (!positive(validitySeconds) || validitySeconds > 2147483647) return invalidInput()
  // Creating a PAR grants ObjectRead access to anyone holding this URL. It is a
  // cloud mutation, not a read-only calculation, and must never be auto-retried.
  const body = dataObject(await tenantPost<unknown>('/oci/storage/object/presigned', { ...context, validitySeconds }, writeConfig))
  const value = requiredText(body.url)
  try {
    const url = new URL(value)
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash) throw new Error()
    return url.href
  } catch { throw new StorageApiError('invalidUrl') }
}
export function getStorageDownloadUrl(input: StorageObjectContext): string {
  // Fixed same-origin route; object names remain encoded query values, never paths.
  const context = objectContext(input)
  return `/oci/storage/object/download?${new URLSearchParams({ ...context }).toString()}`
}

/** Bounded binary read. Never interpret an object's JSON/HTML as an API response. */
export async function getStoragePreview(
  input: StorageObjectContext,
  signal?: AbortSignal,
  expectedSize?: number | null,
  maxBytes = STORAGE_PREVIEW_LIMIT,
): Promise<Blob> {
  const context = objectContext(input)
  if (!positive(maxBytes) || maxBytes > STORAGE_PREVIEW_LIMIT
    || (expectedSize != null && (!Number.isSafeInteger(expectedSize) || expectedSize < 0))) return invalidInput()
  if (expectedSize != null && expectedSize > maxBytes) throw new StorageApiError('previewTooLarge', '', true)
  const controller = new AbortController()
  const abort = () => controller.abort()
  signal?.addEventListener('abort', abort, { once: true })
  if (signal?.aborted) controller.abort()
  let oversized = false
  let contentLength: number | null = null
  let compressed = false
  try {
    const result = await tenantGet<unknown>('/oci/storage/object/preview', { ...context }, {
      signal: controller.signal,
      timeout: 0,
      responseType: 'blob',
      // XHR progress exposes Content-Length as total before the complete Blob.
      onDownloadProgress: (event: AxiosProgressEvent) => {
        if (event.loaded > maxBytes || (event.total !== undefined && event.total > maxBytes)) {
          oversized = true
          controller.abort()
        }
      },
      transformResponse: [(value: unknown, headers: Record<string, unknown>) => {
        const length = String(headers['content-length'] ?? '')
        if (/^\d+$/.test(length)) {
          const parsed = Number(length)
          if (Number.isSafeInteger(parsed)) contentLength = parsed
        }
        const encoding = String(headers['content-encoding'] ?? '').trim().toLowerCase()
        compressed = !!encoding && encoding !== 'identity'
        return value
      }],
    })
    if (oversized || (result instanceof Blob && result.size > maxBytes)) throw new StorageApiError('previewTooLarge')
    if (!(result instanceof Blob)) return invalidResponse()
    // A proxy may compress the transfer. Content-Length and the listed object size
    // then describe encoded bytes and cannot be compared with the decoded Blob.
    if (!compressed && ((contentLength !== null && contentLength !== result.size)
      || (expectedSize != null && expectedSize !== result.size))) return invalidResponse()
    if (result.size === 0 && expectedSize !== 0) return invalidResponse()
    return result
  } catch (cause) {
    if (oversized) throw new StorageApiError('previewTooLarge')
    throw cause
  } finally {
    signal?.removeEventListener('abort', abort)
  }
}

function uploadProgress(callback?: StorageUploadOptions['onProgress']) {
  return callback ? (event: AxiosProgressEvent) => callback({ loaded: event.loaded, total: event.total }) : undefined
}
function uploadForm(context: StorageBucketContext): FormData {
  const data = new FormData()
  for (const [key, value] of Object.entries(context)) data.append(key, value)
  return data
}
export async function uploadStorageObject(context: StorageBucketContext, file: File, options: StorageUploadOptions = {}): Promise<void> {
  const target = bucketContext(context)
  if (!(file instanceof File) || !positive(file.size)) return invalidInput()
  const data = uploadForm(target)
  if (options.objectName !== undefined) data.append('objectName', inputText(options.objectName))
  else inputText(file.name)
  data.append('file', file)
  // 100% browser upload progress is not confirmation of OCI persistence.
  accepted(await tenantPost<unknown>('/oci/storage/object/upload', data, {
    ...writeConfig, signal: options.signal, onUploadProgress: uploadProgress(options.onProgress),
  }))
}
export async function initiateStorageMultipart(input: StorageMultipartInitInput): Promise<StorageMultipartInitResult> {
  const context = objectContext(input)
  if (!positive(input.totalSize) || !positive(input.chunkSize) || Math.ceil(input.totalSize / input.chunkSize) > 2147483647
    || typeof input.contentType !== 'string') return invalidInput()
  // The server aborts older active uploads for this object before initialization.
  // Never retry this call automatically, including after a lost response.
  const body = dataObject(await tenantPost<unknown>('/oci/storage/object/multipart/initiate', {
    ...context, contentType: input.contentType || 'application/octet-stream', totalSize: input.totalSize, chunkSize: input.chunkSize,
  }, writeConfig))
  const result = { uploadId: requiredText(body.uploadId), objectName: requiredText(body.objectName), namespace: requiredText(body.namespace), bucketName: requiredText(body.bucketName) }
  if (result.objectName !== context.objectName || result.namespace !== context.namespace || result.bucketName !== context.bucketName) return invalidResponse()
  return result
}
export async function uploadStoragePart(input: StorageMultipartPartInput, chunk: Blob, options: StorageUploadOptions = {}): Promise<StorageMultipartPart> {
  const context = multipartContext(input)
  const partNumber = inputPartNumber(input.partNumber)
  if (!(chunk instanceof Blob) || !positive(chunk.size)) return invalidInput()
  const data = uploadForm(context)
  data.append('partNumber', String(partNumber))
  data.append('chunk', chunk, `part-${partNumber}`)
  const result = part(dataObject(await tenantPost<unknown>('/oci/storage/object/multipart/part', data, {
    ...writeConfig, signal: options.signal, onUploadProgress: uploadProgress(options.onProgress),
  })))
  return result.partNum === partNumber ? result : invalidResponse()
}
export async function commitStorageMultipart(input: StorageMultipartCommitInput): Promise<void> {
  const context = multipartContext(input)
  if (!Array.isArray(input.parts) || !input.parts.length) return invalidInput()
  const parts = input.parts.map(value => ({ partNum: inputPartNumber(value.partNum), etag: inputText(value.etag) })).sort((a, b) => a.partNum - b.partNum)
  if (parts.some((value, index) => value.partNum !== index + 1)) return invalidInput()
  accepted(await tenantPost<unknown>('/oci/storage/object/multipart/commit', { ...context, parts }, writeConfig))
}
export async function abortStorageMultipart(input: StorageMultipartContext): Promise<void> {
  accepted(await tenantPost<unknown>('/oci/storage/object/multipart/abort', multipartContext(input), writeConfig))
}
export async function listStorageResumableUploads(input: StorageBucketContext, signal?: AbortSignal): Promise<StorageMultipartRecord[]> {
  const context = bucketContext(input)
  const body = accepted(await tenantGet<unknown>('/oci/storage/object/multipart/resumeable', {
    tenantId: context.tenantId, bucketName: context.bucketName,
  }, { ...responseConfig, signal }))
  if (!Array.isArray(body.data)) return invalidResponse()
  const records = body.data.map(value => {
    if (!object(value) || !Array.isArray(value.completedParts)) return invalidResponse()
    const completedParts = value.completedParts.map(part).sort((a, b) => a.partNum - b.partNum)
    const record: StorageMultipartRecord = {
      id: identifier(value.id), uploadId: requiredText(value.uploadId), objectName: requiredText(value.objectName),
      bucketName: requiredText(value.bucketName), namespace: requiredText(value.namespace), totalSize: nullableCount(value.totalSize),
      chunkSize: nullableCount(value.chunkSize), totalParts: nullableCount(value.totalParts),
      completedPartCount: integer(value.completedPartCount), completedParts, createTime: text(value.createTime),
    }
    if (record.namespace !== context.namespace || record.bucketName !== context.bucketName
      || record.completedPartCount !== completedParts.length || new Set(completedParts.map(value => value.partNum)).size !== completedParts.length
      || (record.totalParts !== null && record.totalParts > 0 && completedParts.some(value => value.partNum > record.totalParts!))) return invalidResponse()
    return record
  })
  if (new Set(records.map(row => row.id)).size !== records.length || new Set(records.map(row => row.uploadId)).size !== records.length) return invalidResponse()
  // These are local DB records, not a fresh OCI multipart-parts inventory.
  return records
}

export function storageError(cause: unknown): StorageApiError {
  if (cause instanceof StorageApiError) return cause
  if (isCancel(cause)) return new StorageApiError('cancelled')
  const body: unknown = isAxiosError(cause) ? cause.response?.data : cause
  const explicit = object(body) && body.success === false
  let detail = ''
  if (object(body)) {
    for (const key of ['message', 'msg', 'error']) {
      if (typeof body[key] === 'string' && body[key]) { detail = body[key]; break }
    }
  }
  const timeout = isAxiosError(cause) && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new StorageApiError(timeout ? 'timeout' : 'requestFailed', detail, explicit)
}
/** SDK failures become success:false after a cloud write may already have taken
 * effect. Only local input rejection proves that no request was submitted. */
export function isStorageWriteUncertain(cause: unknown): boolean {
  return storageError(cause).key !== 'invalidInput'
}
