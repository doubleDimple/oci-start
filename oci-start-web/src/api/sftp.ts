import { tenantCsrfToken } from './tenant'
import { handleSessionResponse } from '@/utils/session'

/** Each transfer opens its own SFTP connection; there is no server session ID. */
export interface SftpCredentials { host: string; port: number; username: string; password: string }
export interface SftpProgress { loaded: number; total?: number }
export interface SftpTransferOptions {
  signal?: AbortSignal
  onProgress?: (progress: SftpProgress) => void
}
export interface SftpDownload { blob: Blob; filename: string }
export type SftpErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden' | 'tooLarge' | 'unsupported'

export class SftpApiError extends Error {
  constructor(public key: SftpErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'SftpApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function validate(credentials: SftpCredentials, remotePath: string) {
  if (!credentials || typeof credentials.host !== 'string' || !credentials.host.trim()
    || typeof credentials.username !== 'string' || !credentials.username.trim()
    || typeof credentials.password !== 'string' || !Number.isInteger(credentials.port)
    || credentials.port < 1 || credentials.port > 65535
    || typeof remotePath !== 'string' || !remotePath.trim() || remotePath.includes('\0')) {
    throw new SftpApiError('invalidInput')
  }
}

function safeDetail(value: unknown, password: string): string {
  if (typeof value !== 'string') return ''
  let detail = value.trim()
  if (!detail || /^[<{\[]/.test(detail)) return ''
  if (password) detail = detail.split(password).join('••••')
  return detail.slice(0, 1000)
}

interface TransferResponse { body: unknown; contentType: string; disposition: string }

/** Native XHR preserves binary headers and reports actual browser transfer bytes. */
function transfer(
  path: '/oci/sftp/upload' | '/oci/sftp/download',
  body: FormData | string,
  options: SftpTransferOptions,
): Promise<TransferResponse> {
  const uploading = path.endsWith('/upload')
  return new Promise((resolve, reject) => {
    if (typeof XMLHttpRequest === 'undefined') { reject(new SftpApiError('unsupported')); return }
    if (options.signal?.aborted) { reject(new SftpApiError('cancelled')); return }
    const xhr = new XMLHttpRequest()
    let settled = false
    let sent = false
    const cleanup = () => {
      options.signal?.removeEventListener('abort', abort)
      xhr.onload = null
      xhr.onerror = null
      xhr.onabort = null
      xhr.ontimeout = null
      xhr.onprogress = null
      xhr.upload.onprogress = null
    }
    const fail = (key: SftpErrorKey) => {
      if (settled) return
      settled = true
      cleanup()
      reject(new SftpApiError(key, '', uploading && sent))
    }
    const abort = () => {
      // Aborting the browser request does not roll back an SFTP put on the server.
      xhr.abort()
      fail('cancelled')
    }
    const progress = (event: ProgressEvent) => {
      if (settled || options.signal?.aborted || !Number.isFinite(event.loaded) || event.loaded < 0) return
      const total = event.lengthComputable && Number.isFinite(event.total) && event.total > 0 ? event.total : undefined
      options.onProgress?.({ loaded: event.loaded, total })
    }
    try {
      xhr.open('POST', path, true)
      xhr.withCredentials = true
      xhr.timeout = 0
      xhr.responseType = uploading ? 'json' : 'blob'
      xhr.setRequestHeader('Accept', uploading ? 'application/json' : 'application/octet-stream')
      xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest')
      const token = tenantCsrfToken()
      const csrfHeader = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
      if (token) xhr.setRequestHeader(csrfHeader, token)
      if (!uploading) xhr.setRequestHeader('Content-Type', 'application/json')
      if (uploading) xhr.upload.onprogress = progress
      else xhr.onprogress = progress
      xhr.onerror = () => fail('requestFailed')
      xhr.onabort = () => fail('cancelled')
      xhr.ontimeout = () => fail('timeout')
      xhr.onload = () => {
        if (settled) return
        handleSessionResponse({ status: xhr.status, url: xhr.responseURL, body: uploading ? xhr.response as unknown : undefined })
        // A redirected login page must never become a downloaded file or success.
        let redirected = false
        try { redirected = new URL(xhr.responseURL).pathname !== path }
        catch { fail('invalidResponse'); return }
        if (redirected || xhr.status === 401) { fail('unauthorized'); return }
        if (xhr.status === 403) { fail('forbidden'); return }
        if (xhr.status === 413) { fail('tooLarge'); return }
        if (xhr.status !== 200) { fail('requestFailed'); return }
        const result = {
          body: xhr.response as unknown,
          contentType: xhr.getResponseHeader('Content-Type') || '',
          disposition: xhr.getResponseHeader('Content-Disposition') || '',
        }
        settled = true
        cleanup()
        resolve(result)
      }
      options.signal?.addEventListener('abort', abort, { once: true })
      sent = true
      xhr.send(body)
    } catch { fail('requestFailed') }
  })
}

export async function uploadSftpFile(
  credentials: SftpCredentials, remotePath: string, file: File, options: SftpTransferOptions = {},
): Promise<void> {
  validate(credentials, remotePath)
  // MultipartFile.isEmpty() rejects zero-byte files in the actual controller.
  if (!(file instanceof File) || file.size === 0) throw new SftpApiError('invalidInput')
  const form = new FormData()
  form.append('host', credentials.host)
  form.append('port', String(credentials.port))
  form.append('username', credentials.username)
  form.append('password', credentials.password)
  form.append('remotePath', remotePath)
  form.append('file', file)
  const result = await transfer('/oci/sftp/upload', form, options)
  const body = result.body
  if (!object(body) || typeof body.success !== 'boolean') throw new SftpApiError('invalidResponse', '', true)
  if (!body.success) throw new SftpApiError('requestFailed', safeDetail(body.message, credentials.password), true)
  if (body.code !== 200) throw new SftpApiError('invalidResponse', '', true)
}

function downloadName(disposition: string, remotePath: string): string {
  let filename = remotePath.split('/').at(-1) || 'download'
  const encoded = disposition.match(/filename\*\s*=\s*UTF-8''([^;\r\n]+)/i)
  if (encoded?.[1]) {
    try { filename = decodeURIComponent(encoded[1].trim()) }
    catch { /* Keep the requested basename if a proxy damaged the header. */ }
  }
  return filename.replace(/[\u0000-\u001f\u007f/\\]/g, '_') || 'download'
}

export async function downloadSftpFile(
  credentials: SftpCredentials, remotePath: string, options: SftpTransferOptions = {},
): Promise<SftpDownload> {
  validate(credentials, remotePath)
  const result = await transfer('/oci/sftp/download', JSON.stringify({ ...credentials, remotePath }), options)
  if (!(result.body instanceof Blob)
    || result.contentType.split(';')[0]?.trim().toLowerCase() !== 'application/octet-stream'
    || !/^attachment\s*;/i.test(result.disposition)) throw new SftpApiError('invalidResponse')
  // No remote size/checksum is available. A completed HTTP response is the only
  // completion evidence; callers must not claim remote integrity or disk saving.
  return { blob: result.body, filename: downloadName(result.disposition, remotePath) }
}

/** Return display metadata only; never retain an XHR, request body or credentials. */
export function sftpError(cause: unknown): SftpApiError {
  return cause instanceof SftpApiError ? cause : new SftpApiError('requestFailed')
}
