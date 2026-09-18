import { isAxiosError, isCancel } from 'axios'
import request from './request'
import { tenantCsrfToken, tenantGet, tenantPost } from './tenant'

export interface GithubSecurityConfig {
  enabled: boolean; userName: string; githubId: string; clientId: string; redirectUri: string; hasClientSecret: boolean
}
export interface GoogleSecurityConfig {
  enabled: boolean; email: string; clientId: string; redirectUri: string; hasClientSecret: boolean
}
export interface MfaSecurityConfig { enabled: boolean; issuer: string; hasSecretKey: boolean }
export interface TurnstileSecurityConfig { enabled: boolean; siteKey: string; hasSecretKey: boolean }
export interface SecuritySettings {
  currentUsername: string; siteLogoName: string
  github: GithubSecurityConfig; google: GoogleSecurityConfig; mfa: MfaSecurityConfig
  turnstile: TurnstileSecurityConfig; channelNotifyEnabled: boolean
}
export interface GithubSecurityInput extends Omit<GithubSecurityConfig, 'hasClientSecret'> { keepSecret: boolean; clientSecret: string }
export interface GoogleSecurityInput extends Omit<GoogleSecurityConfig, 'hasClientSecret'> { keepSecret: boolean; clientSecret: string }
export interface TurnstileSecurityInput extends Omit<TurnstileSecurityConfig, 'hasSecretKey'> { keepSecret: boolean; secretKey: string }
export interface MfaSecurityInput { enabled: boolean; issuer: string }
export interface AccountSecurityInput { currentPassword: string; newUsername?: string; newPassword?: string }
export interface GithubIdentity { id: string; login: string }
export interface MfaEnrollment { secretKey: string | null; qrCode: string | null }
export type SecuritySettingsErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'forbidden' | 'notFound' | 'verifyFailed' | 'githubLookupFailed' | 'saveMismatch'
  | 'currentPasswordIncorrect' | 'usernameExists'
export class SecuritySettingsApiError extends Error {
  constructor(public key: SecuritySettingsErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'SecuritySettingsApiError'
  }
}
const BASE = '/api/system'
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalid(): never { throw new SecuritySettingsApiError('invalidResponse') }
function badInput(): never { throw new SecuritySettingsApiError('invalidInput') }
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalid() }
function boolean(value: unknown): boolean { return typeof value === 'boolean' ? value : invalid() }
function unwrap(body: unknown): Record<string, unknown> {
  return object(body) && body.success === true && object(body.data) ? body.data : invalid()
}
function validGithubId(value: unknown): value is string { return typeof value === 'string' && /^[1-9]\d*$/.test(value) }
function configs(value: Record<string, unknown>): SecuritySettings {
  const github = value.github, google = value.google, mfa = value.mfa, turnstile = value.turnstile
  if (!object(github) || !object(google) || !object(mfa) || !object(turnstile)) return invalid()
  const githubId = text(github.githubId)
  if (githubId && !validGithubId(githubId)) return invalid()
  // Explicit projection: never retain legacy secret fields even if an older server sends them.
  return {
    currentUsername: text(value.currentUsername), siteLogoName: text(value.siteLogoName),
    github: { enabled: boolean(github.enabled), userName: text(github.userName), githubId,
      clientId: text(github.clientId), redirectUri: text(github.redirectUri), hasClientSecret: boolean(github.hasClientSecret) },
    google: { enabled: boolean(google.enabled), email: text(google.email), clientId: text(google.clientId),
      redirectUri: text(google.redirectUri), hasClientSecret: boolean(google.hasClientSecret) },
    mfa: { enabled: boolean(mfa.enabled), issuer: text(mfa.issuer), hasSecretKey: boolean(mfa.hasSecretKey) },
    turnstile: { enabled: boolean(turnstile.enabled), siteKey: text(turnstile.siteKey), hasSecretKey: boolean(turnstile.hasSecretKey) },
    channelNotifyEnabled: boolean(value.channelNotifyEnabled),
  }
}
/** Preserve large GitHub numeric IDs as strings before JSON.parse can round them. */
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g,
      (token: string, number?: string) => number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token))
  } catch { return raw }
}
const EMPTY_BODY = Symbol('empty-security-save')
function decodeWrite(raw: unknown): unknown { return typeof raw === 'string' && raw.trim() === '' ? EMPTY_BODY : decode(raw) }
const readOptions = { timeout: 30000, transformResponse: [decode], headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' } }
const writeOptions = { timeout: 0, transformResponse: [decodeWrite] }

export async function loadSecuritySettings(signal?: AbortSignal): Promise<SecuritySettings> {
  try { return configs(unwrap(await tenantGet(`${BASE}/securitySettingsConfigs`, { redacted: true }, { ...readOptions, signal }))) }
  catch (cause) { throw securitySettingsError(cause) }
}
function stringInput(value: unknown): string { return typeof value === 'string' ? value : badInput() }
function flagInput(value: unknown): boolean { return typeof value === 'boolean' ? value : badInput() }
function callback(value: string): string {
  const result = value.trim()
  if (!result) return ''
  let url: URL
  try { url = new URL(result) } catch { return badInput() }
  if (!/^https?:\/\//.test(result) || !['http:', 'https:'].includes(url.protocol) || !url.hostname
    || url.username || url.password || url.hash || result.includes('#') || /[\s\\]/.test(result)) return badInput()
  return result
}
function oauth(input: { enabled: boolean; clientId: string; clientSecret: string; keepSecret: boolean; redirectUri: string }) {
  const enabled = flagInput(input.enabled), keepSecret = flagInput(input.keepSecret)
  const clientId = stringInput(input.clientId).trim(), clientSecret = stringInput(input.clientSecret)
  const redirectUri = callback(stringInput(input.redirectUri))
  if (enabled && (!clientId || !redirectUri || (!keepSecret && !clientSecret.trim()))) return badInput()
  return { enabled, clientId, redirectUri, keepSecret, ...(!keepSecret ? { clientSecret } : {}) }
}
export function normalizeGithubSecurity(input: GithubSecurityInput) {
  const common = oauth(input)
  const userName = stringInput(input.userName).trim(), githubId = stringInput(input.githubId).trim()
  if ((githubId && !validGithubId(githubId)) || (common.enabled && !githubId)) return badInput()
  return { ...common, userName, githubId }
}
export function normalizeGoogleSecurity(input: GoogleSecurityInput) {
  const common = oauth(input), email = stringInput(input.email).trim()
  if ((email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) || (common.enabled && !email)) return badInput()
  return { ...common, email }
}
export function normalizeTurnstileSecurity(input: TurnstileSecurityInput) {
  const enabled = flagInput(input.enabled), keepSecret = flagInput(input.keepSecret)
  const siteKey = stringInput(input.siteKey).trim(), secretKey = stringInput(input.secretKey)
  if (enabled && (!siteKey || (!keepSecret && !secretKey.trim()))) return badInput()
  return { enabled, siteKey, keepSecret, ...(!keepSecret ? { secretKey } : {}) }
}
export function normalizeMfaSecurity(input: MfaSecurityInput): MfaSecurityInput {
  const enabled = flagInput(input.enabled), issuer = stringInput(input.issuer).trim() || 'OCI-Start Verify'
  if (/[\u0000-\u001f\u007f]/.test(issuer)) return badInput()
  return { enabled, issuer }
}
export function normalizeAccountSecurity(input: AccountSecurityInput): AccountSecurityInput {
  const currentPassword = stringInput(input.currentPassword)
  const newUsername = input.newUsername === undefined ? '' : stringInput(input.newUsername).trim()
  const newPassword = input.newPassword === undefined ? '' : stringInput(input.newPassword)
  if (!currentPassword || (!newUsername && !newPassword) || (newPassword && !newPassword.trim())
    || /[\u0000-\u001f\u007f]/.test(newUsername)) return badInput()
  return { currentPassword, ...(newUsername ? { newUsername } : {}), ...(newPassword ? { newPassword } : {}) }
}
/** No retry or abort once a configuration write has been sent. */
async function mutation<T>(send: () => Promise<unknown>, parse: (body: unknown) => T, secrets: string[] = []): Promise<T> {
  try { return parse(await send()) } catch (cause) {
    const problem = securitySettingsError(cause, secrets)
    throw new SecuritySettingsApiError(problem.key, problem.detail, true)
  }
}
function empty(body: unknown): void { if (body !== EMPTY_BODY) return invalid() }
function saveEmpty(path: string, data?: unknown, secrets: string[] = []): Promise<void> {
  return mutation(() => tenantPost(`${BASE}/${path}`, data, writeOptions), empty, secrets)
}
export async function updateSecurityAccount(input: AccountSecurityInput): Promise<{ needRelogin: boolean }> {
  const payload = normalizeAccountSecurity(input)
  const secrets = [payload.currentPassword, payload.newPassword ?? '']
  try {
    const body = await tenantPost(`${BASE}/updatePassword`, payload, writeOptions)
    const data = unwrap(body)
    return { needRelogin: boolean(data.needRelogin) }
  } catch (cause) {
    const rejection: unknown = isAxiosError(cause) ? cause.response?.data : null
    // Only this endpoint's explicit pre-write validation receipt proves that no
    // account change occurred. A general HTTP 400 is not proof of rollback.
    if (isAxiosError(cause) && cause.response?.status === 400 && object(rejection)
      && rejection.success === false && rejection.writeAttempted === false
      && (rejection.errorKey === 'currentPasswordIncorrect' || rejection.errorKey === 'usernameExists')) {
      throw new SecuritySettingsApiError(rejection.errorKey, safeDetail(rejection.message, secrets), false)
    }
    const problem = securitySettingsError(cause, secrets)
    throw new SecuritySettingsApiError(problem.key, problem.detail, true)
  }
}
export function updateSecurityLogo(logoName: string): Promise<void> {
  const name = stringInput(logoName).trim()
  if (!name || name.length > 15 || /[\u0000-\u001f\u007f]/.test(name)) return badInput()
  return mutation(() => tenantPost(`${BASE}/settings/logo`, new URLSearchParams({ logoName: name }), {
    ...writeOptions, headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
  }), body => { if (!object(body) || body.code !== 200 || body.msg !== 'success') return invalid() })
}
export function updateGithubSecurity(input: GithubSecurityInput): Promise<void> {
  return saveEmpty('updateGithubConfig', normalizeGithubSecurity(input), [input.clientSecret])
}
export function updateGoogleSecurity(input: GoogleSecurityInput): Promise<void> {
  return saveEmpty('updateGoogleConfig', normalizeGoogleSecurity(input), [input.clientSecret])
}
export function updateMfaSecurity(input: MfaSecurityInput): Promise<void> { return saveEmpty('updateMfaConfig', normalizeMfaSecurity(input)) }
export function regenerateSecurityMfa(): Promise<void> { return saveEmpty('regenerateMfaSecret') }
export function deleteSecurityMfa(): Promise<void> {
  const headers: Record<string, string> = {}
  const token = tenantCsrfToken()
  if (token) headers[document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'] = token
  return mutation(() => request.delete(`${BASE}/deleteMfaConfig`, { ...writeOptions, headers, silent: true }), empty)
}
export function updateTurnstileSecurity(input: TurnstileSecurityInput): Promise<void> {
  return saveEmpty('updateTurnstileConfig', normalizeTurnstileSecurity(input), [input.secretKey])
}
export function updateSecurityChannelNotify(enabled: boolean): Promise<void> { return saveEmpty('updateChannelNotifyConfig', { enabled: flagInput(enabled) }) }

export async function loadSecurityMfaEnrollment(signal?: AbortSignal): Promise<MfaEnrollment> {
  try {
    const data = unwrap(await tenantGet(`${BASE}/mfaMaterial`, undefined, { ...readOptions, signal }))
    const secretKey = data.secretKey == null ? null : text(data.secretKey)
    const qrCode = data.qrCode == null ? null : text(data.qrCode)
    if (secretKey !== null && (!/^[A-Z2-7]+=*$/.test(secretKey) || secretKey.length > 256)) return invalid()
    if (qrCode !== null && (qrCode.length > 1_000_000 || !/^iVBORw0KGgo[A-Za-z0-9+/]*={0,2}$/.test(qrCode))) return invalid()
    return { secretKey, qrCode }
  } catch (cause) { throw securitySettingsError(cause) }
}
/** Checks the six-digit code only; this endpoint does not enable or save MFA. */
export async function verifySecurityMfa(code: string, signal?: AbortSignal): Promise<void> {
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) return badInput()
  try {
    const body = await tenantPost(`${BASE}/verifyMfaCode`, { code }, { ...readOptions, signal })
    if (!object(body) || body.success !== true) return invalid()
  } catch (cause) {
    const body: unknown = isAxiosError(cause) ? cause.response?.data : cause
    const problem = securitySettingsError(cause, [code])
    if (object(body) && body.success === false && !['unauthorized', 'forbidden'].includes(problem.key)) {
      throw new SecuritySettingsApiError('verifyFailed', problem.detail)
    }
    throw problem
  }
}
/** Explicit public lookup only. Never use the application's authenticated Axios client here. */
export async function lookupSecurityGithub(username: string, signal?: AbortSignal): Promise<GithubIdentity> {
  const name = stringInput(username).trim()
  if (!/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/.test(name)) return badInput()
  const controller = new AbortController()
  let timedOut = false
  const abort = () => controller.abort()
  if (signal?.aborted) throw new SecuritySettingsApiError('cancelled')
  signal?.addEventListener('abort', abort, { once: true })
  const timer = setTimeout(() => { timedOut = true; controller.abort() }, 30000)
  try {
    const response = await fetch(`https://api.github.com/users/${encodeURIComponent(name)}`, {
      signal: controller.signal, credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-store', redirect: 'error',
      headers: { Accept: 'application/vnd.github+json' },
    })
    if (!response.ok) throw new SecuritySettingsApiError(response.status === 404 ? 'notFound' : 'githubLookupFailed')
    const data = decode(await response.text())
    if (!object(data) || typeof data.login !== 'string'
      || !/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/.test(data.login)) return invalid()
    const id = typeof data.id === 'number' && Number.isSafeInteger(data.id) ? String(data.id) : data.id
    if (!validGithubId(id)) return invalid()
    return { id, login: data.login }
  } catch (cause) {
    if (timedOut) throw new SecuritySettingsApiError('timeout')
    if (signal?.aborted) throw new SecuritySettingsApiError('cancelled')
    throw cause instanceof SecuritySettingsApiError ? cause : new SecuritySettingsApiError('githubLookupFailed')
  } finally {
    clearTimeout(timer)
    signal?.removeEventListener('abort', abort)
  }
}
function safeDetail(value: unknown, secrets: string[]): string {
  if (typeof value !== 'string') return ''
  let detail = value.trim()
  if (!detail || /[<>{}\[\]\r\n]/.test(detail) || /https?:\/\//i.test(detail)) return ''
  const variants = new Set<string>()
  for (const secret of secrets) {
    if (!secret) continue
    for (const value of [secret, secret.trim()]) {
      if (!value) continue
      variants.add(value); variants.add(JSON.stringify(value).slice(1, -1))
      try { variants.add(encodeURIComponent(value)) } catch { /* The literal remains redacted. */ }
    }
  }
  for (const value of [...variants].sort((a, b) => b.length - a.length)) detail = detail.split(value).join('•••')
  if (/(?:secret|password|authorization|bearer|token)\s*[:=]/i.test(detail)) return ''
  return detail.slice(0, 500)
}
export function securitySettingsError(cause: unknown, secrets: string[] = []): SecuritySettingsApiError {
  if (cause instanceof SecuritySettingsApiError) return new SecuritySettingsApiError(cause.key, safeDetail(cause.detail, secrets), cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new SecuritySettingsApiError('cancelled')
  const http = isAxiosError(cause), body: unknown = http ? cause.response?.data : cause
  const status = http ? cause.response?.status : object(body) ? Number(body.code) : undefined
  if (status === 401) return new SecuritySettingsApiError('unauthorized')
  if (status === 403) return new SecuritySettingsApiError('forbidden')
  if (status === 404) return new SecuritySettingsApiError('notFound')
  if (http && ['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code ?? '')) return new SecuritySettingsApiError('timeout')
  return new SecuritySettingsApiError('requestFailed', safeDetail(object(body) ? body.message ?? body.msg ?? body.error : body, secrets))
}
