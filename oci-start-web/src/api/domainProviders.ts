import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export type DomainProvider = 'cloudflare' | 'edgeOne'
export interface CloudflareProviderConfig {
  enabled: boolean
  /** The legacy apiToken field contains a Cloudflare Global API Key. */
  apiToken: string
  zoneId: string
  email: string
}
export interface EdgeOneProviderConfig {
  enabled: boolean
  secretId: string
  secretKey: string
  region: string
}
export interface DomainProviderConfigs {
  cloudflare: CloudflareProviderConfig
  edgeOne: EdgeOneProviderConfig
}
export type DomainProviderErrorKey = 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden' | 'cloudflareRequired' | 'invalidEmail'
  | 'edgeOneRequired' | 'testFailed' | 'saveUnverified' | 'saveMismatch'

export class DomainProviderApiError extends Error {
  constructor(
    public key: DomainProviderErrorKey,
    public detail = '',
    /** Save was submitted; the failure cannot establish whether its transaction committed. */
    public writeAttempted = false,
  ) {
    super(key)
    this.name = 'DomainProviderApiError'
  }
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new DomainProviderApiError('invalidResponse') }
function field(value: unknown): string {
  return value == null ? '' : typeof value === 'string' ? value : invalidResponse()
}
function enabled(value: unknown): boolean {
  return typeof value === 'boolean' ? value : invalidResponse()
}
function cloudflareConfig(value: unknown): CloudflareProviderConfig {
  if (!object(value)) return invalidResponse()
  return {
    enabled: enabled(value.enabled), apiToken: field(value.apiToken),
    zoneId: field(value.zoneId), email: field(value.email),
  }
}
function edgeOneConfig(value: unknown): EdgeOneProviderConfig {
  if (!object(value)) return invalidResponse()
  return {
    enabled: enabled(value.enabled), secretId: field(value.secretId),
    secretKey: field(value.secretKey), region: field(value.region),
  }
}

/** Trim visible credentials as the old form did, while retaining hidden settings verbatim. */
export function normalizeCloudflareProvider(
  config: CloudflareProviderConfig,
  purpose: 'save' | 'test',
): CloudflareProviderConfig {
  if (purpose !== 'save' && purpose !== 'test') return invalidResponse()
  const source = cloudflareConfig(config)
  const result = { ...source, apiToken: source.apiToken.trim(), email: source.email.trim() }
  if ((result.enabled || purpose === 'test') && (!result.apiToken || !result.email)) {
    throw new DomainProviderApiError('cloudflareRequired')
  }
  if (result.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.email)) {
    throw new DomainProviderApiError('invalidEmail')
  }
  return result
}

export function normalizeEdgeOneProvider(
  config: EdgeOneProviderConfig,
  purpose: 'save' | 'test',
): EdgeOneProviderConfig {
  if (purpose !== 'save' && purpose !== 'test') return invalidResponse()
  const source = edgeOneConfig(config)
  const result = { ...source, secretId: source.secretId.trim(), secretKey: source.secretKey.trim() }
  if ((result.enabled || purpose === 'test') && (!result.secretId || !result.secretKey)) {
    throw new DomainProviderApiError('edgeOneRequired')
  }
  return result
}

// No numeric IDs occur in these DTOs. Secrets and any digit-only textual settings
// remain JSON strings; do not coerce numbers into credentials or store raw responses.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try { return JSON.parse(raw) } catch { return raw }
}
const readConfig = { transformResponse: [decode], timeout: 30000 }
const EMPTY_SAVE_BODY = Symbol('empty-domain-provider-save')
function decodeSaveResponse(raw: unknown): unknown {
  return typeof raw === 'string' && raw.trim() === '' ? EMPTY_SAVE_BODY : decode(raw)
}

/** Credential-bearing response: keep its projected fields in page-local state only. */
export async function loadDomainProviderConfigs(signal?: AbortSignal): Promise<DomainProviderConfigs> {
  try {
    const body = await tenantGet<unknown>('/api/system/domainProviderConfigs', undefined, {
      ...readConfig, signal, headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' },
    })
    if (!object(body) || body.success !== true || !object(body.data)) return invalidResponse()
    return {
      cloudflare: cloudflareConfig(body.data.cloudflare),
      // The backend getter already supplies ap-beijing when its stored region is empty.
      edgeOne: edgeOneConfig(body.data.edgeOne),
    }
  } catch (cause) { throw domainProviderError(cause) }
}

async function saveProvider(path: string, config: CloudflareProviderConfig | EdgeOneProviderConfig): Promise<void> {
  const secrets = Object.values(config).filter((value): value is string => typeof value === 'string')
  try {
    const body = await tenantPost<unknown>(path, config, { transformResponse: [decodeSaveResponse], timeout: 0 })
    // Both controllers return HTTP 200 with no body after their local transaction.
    // A JSON envelope, literal null or HTML document is not this save contract.
    if (body !== EMPTY_SAVE_BODY) return invalidResponse()
  } catch (cause) {
    const error = domainProviderError(cause, secrets)
    throw new DomainProviderApiError(error.key, error.detail, true)
  }
}

/** Local configuration save only; it does not authenticate with Cloudflare. */
export async function saveCloudflareProvider(config: CloudflareProviderConfig): Promise<void> {
  return saveProvider('/api/system/updateCloudflareConfig', normalizeCloudflareProvider(config, 'save'))
}

/** Local configuration save only; the region is preserved even though the old UI hides it. */
export async function saveEdgeOneProvider(config: EdgeOneProviderConfig): Promise<void> {
  return saveProvider('/api/system/updateEdgeOneConfig', normalizeEdgeOneProvider(config, 'save'))
}

async function testProvider(
  path: string,
  config: CloudflareProviderConfig | EdgeOneProviderConfig,
  signal?: AbortSignal,
): Promise<void> {
  const secrets = Object.values(config).filter((value): value is string => typeof value === 'string')
  try {
    const body = await tenantPost<unknown>(path, config, { ...readConfig, signal })
    if (!object(body) || body.success !== true) return invalidResponse()
  } catch (cause) {
    const error = domainProviderError(cause, secrets)
    const body: unknown = isAxiosError(cause) ? cause.response?.data : cause
    // The shared interceptor rejects an HTTP-200 success:false before returning it.
    if (object(body) && body.success === false
      && error.key !== 'unauthorized' && error.key !== 'forbidden') {
      throw new DomainProviderApiError('testFailed', error.detail)
    }
    throw error
  }
}

/** Remote read-only credential test; cancellation stops waiting, not the server's HTTP call. */
export async function testCloudflareProvider(config: CloudflareProviderConfig, signal?: AbortSignal): Promise<void> {
  return testProvider('/api/system/testCloudflareConnection', normalizeCloudflareProvider(config, 'test'), signal)
}

/** DescribeZones authentication test; neither enables the provider nor saves the draft. */
export async function testEdgeOneProvider(config: EdgeOneProviderConfig, signal?: AbortSignal): Promise<void> {
  return testProvider('/api/system/testEdgeOneConnection', normalizeEdgeOneProvider(config, 'test'), signal)
}

function safeDetail(value: unknown, secrets: string[]): string {
  if (typeof value !== 'string') return ''
  let detail = value.trim()
  if (!detail || /[<>{}\[\]\r\n]/.test(detail) || /https?:\/\//i.test(detail)) return ''
  const variants = new Set<string>()
  for (const secret of secrets) {
    if (typeof secret !== 'string' || !secret) continue
    for (const candidate of [secret, secret.trim()]) {
      if (!candidate) continue
      variants.add(candidate)
      variants.add(JSON.stringify(candidate).slice(1, -1))
      try { variants.add(encodeURIComponent(candidate)) } catch { /* Malformed surrogate: retain literal redaction. */ }
    }
  }
  // Redact before truncating, otherwise the end of a secret might be cut off first.
  for (const secret of [...variants].sort((left, right) => right.length - left.length)) {
    detail = detail.split(secret).join('•••')
  }
  // Credentials echoed under a field name can come from a different request or
  // server configuration, so omit assignments even when that value is not known here.
  if (/(?:api[ _-]?(?:key|token)|secret[ _-]?(?:id|key)|password|authorization)\s*[:=]/i.test(detail)) return ''
  return detail.slice(0, 1000)
}

/** Strip request/response references and redact supplied credentials from display-only errors. */
export function domainProviderError(cause: unknown, secrets: string[] = []): DomainProviderApiError {
  if (cause instanceof DomainProviderApiError) {
    return new DomainProviderApiError(cause.key, safeDetail(cause.detail, secrets), cause.writeAttempted)
  }
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) {
    return new DomainProviderApiError('cancelled')
  }
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const code = object(body) ? String(body.code ?? '') : ''
  if ((httpError && cause.response?.status === 401) || code === '401') return new DomainProviderApiError('unauthorized')
  if ((httpError && cause.response?.status === 403) || code === '403') return new DomainProviderApiError('forbidden')
  let detail = safeDetail(body, secrets)
  if (object(body)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      detail = safeDetail(body[key], secrets)
      if (detail) break
    }
  }
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new DomainProviderApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
