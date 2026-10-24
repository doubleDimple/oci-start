/** Public authentication requests deliberately bypass the authenticated API client's
 * 401 redirect: invalid credentials must stay on the form with a useful error. */
export interface AuthBootstrap {
  siteLogoName: string
  publicKey: string
  allowRegister: boolean
  githubEnabled: boolean
  googleEnabled: boolean
  turnstileEnabled: boolean
  turnstileSiteKey: string
  messageEnabled: boolean
  mfaEnabled: boolean
  locale: string
  loginBlocked?: boolean
  loginBlockedUntil?: string | null
  loginBlockedMessage?: string | null
}

export class AuthError extends Error {
  constructor(public readonly key: 'network' | 'invalidResponse' | 'failed' | 'encryption', public readonly detail = '',
    public readonly status?: number, public readonly loginBlocked = false, public readonly loginBlockedUntil: string | null = null) {
    super(detail || key)
  }
}

function record(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value)
}

async function requestText(path: string, init: RequestInit = {}): Promise<{ response: Response; text: string }> {
  const controller = new AbortController()
  const abort = () => controller.abort()
  if (init.signal?.aborted) abort()
  else init.signal?.addEventListener('abort', abort, { once: true })
  const timeout = setTimeout(abort, 20000)
  try {
    const response = await fetch(path, {
      credentials: 'same-origin', cache: 'no-store', ...init, signal: controller.signal,
      headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest', ...init.headers },
    })
    return { response, text: await response.text() }
  } catch (error) {
    if (init.signal?.aborted) throw error
    throw new AuthError('network')
  } finally {
    clearTimeout(timeout)
    init.signal?.removeEventListener('abort', abort)
  }
}

async function authRequest(path: string, init: RequestInit = {}, allowEmpty = false): Promise<Record<string, unknown>> {
  const { response, text } = await requestText(path, init)
  let body: unknown
  try { body = text ? JSON.parse(text) : undefined } catch { /* Some legacy endpoints return plain text errors. */ }
  if (!response.ok || (record(body) && (body.success === false || (body.code != null && !['0', '200'].includes(String(body.code)))))) {
    const detail = record(body) && typeof body.message === 'string' ? body.message
      : !text.trimStart().startsWith('<') && text.length < 2000 ? text : ''
    throw new AuthError('failed', detail, response.status, record(body) && body.loginBlocked === true,
      record(body) && typeof body.loginBlockedUntil === 'string' ? body.loginBlockedUntil : null)
  }
  if (record(body)) return body
  if (allowEmpty && !text.trim()) return {}
  // Never interpret a followed HTML login redirect as authentication success.
  throw new AuthError('invalidResponse')
}

export async function fetchAuthBootstrap(locale: string, signal?: AbortSignal): Promise<AuthBootstrap> {
  const body = await authRequest(`/api/auth/bootstrap?lang=${encodeURIComponent(locale === 'en' ? 'en_US' : 'zh_CN')}`, { signal })
  const flags = ['allowRegister', 'githubEnabled', 'googleEnabled', 'turnstileEnabled', 'messageEnabled', 'mfaEnabled']
  if (typeof body.publicKey !== 'string' || !body.publicKey || flags.some(key => typeof body[key] !== 'boolean')
    || typeof body.turnstileSiteKey !== 'string' || (body.turnstileEnabled && !body.turnstileSiteKey)) throw new AuthError('invalidResponse')
  if ((body.loginBlocked !== undefined && typeof body.loginBlocked !== 'boolean')
    || (body.loginBlockedUntil != null && typeof body.loginBlockedUntil !== 'string')
    || (body.loginBlockedMessage != null && typeof body.loginBlockedMessage !== 'string')) throw new AuthError('invalidResponse')
  return body as unknown as AuthBootstrap
}

export interface LoginValues {
  username: string
  password: string
  remember: boolean
  method: 'message' | 'mfa'
  verificationCode: string
  mfaCode: string
  turnstileToken: string
}

export function normalizeLoginVerificationCode(value: string): string {
  return value.trim().toUpperCase()
}

export function isLoginVerificationCode(value: string): boolean {
  return /^[A-Z0-9]{8}$/.test(normalizeLoginVerificationCode(value))
}

export function loginPayload(values: LoginValues, config: AuthBootstrap, encrypt: (value: string) => string | false): URLSearchParams {
  const password = encrypt(values.password)
  if (!password) throw new AuthError('encryption')
  const body = new URLSearchParams({ username: values.username, password })
  if (values.remember) body.set('remember-me', 'true')
  if (values.method === 'message' && config.messageEnabled) body.set('verificationCode', normalizeLoginVerificationCode(values.verificationCode))
  if (values.method === 'mfa' && config.mfaEnabled) body.set('mfaCode', values.mfaCode)
  if (config.turnstileEnabled) body.set('cf-turnstile-response', values.turnstileToken)
  return body
}

export async function signIn(body: URLSearchParams, signal?: AbortSignal): Promise<string> {
  const result = await authRequest('/perform_login', { method: 'POST', body, signal })
  if (result.success !== true) throw new AuthError('invalidResponse')
  return safeLoginRedirect(result.redirectUrl)
}

export function safeLoginRedirect(value: unknown): string {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || /[\\\r\n]/.test(value)) return '/index'
  const path = value.split(/[?#]/, 1)[0]
  if (['/login', '/m/login'].includes(path)) return '/index'
  return value
}

function post(path: string, body: object, signal?: AbortSignal, allowEmpty = false) {
  return authRequest(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal }, allowEmpty)
}

export const registerAccount = (username: string, password: string, signal?: AbortSignal) => post('/api/register-first-user', { username, password }, signal, true)
export const sendLoginCode = (username: string, signal?: AbortSignal) => post('/api/send-verification-code', { username }, signal, true)
/* 忘记密码 API 已停用，与后台路由同步保留为注释。
async function resetRequest(path: string, body: object, signal?: AbortSignal) {
  const result = await post(path, body, signal)
  if (result.success !== true) throw new AuthError('invalidResponse')
  return result
}
export const sendResetCode = (username: string, signal?: AbortSignal) => resetRequest('/api/send-reset-code', { username }, signal)
export async function verifyResetCode(username: string, verificationCode: string, signal?: AbortSignal): Promise<string> {
  const body = await post('/api/verify-reset-code', { username, verificationCode }, signal)
  if (body.success !== true || !record(body.data) || typeof body.data.resetToken !== 'string' || !body.data.resetToken) throw new AuthError('invalidResponse')
  return body.data.resetToken
}
export const resetPassword = (username: string, resetToken: string, signal?: AbortSignal) => resetRequest('/api/reset-password', { username, resetToken }, signal)

*/

export async function oauthLoginUrl(provider: 'github' | 'google', remember: boolean, signal?: AbortSignal): Promise<string> {
  const { response, text } = await requestText(`/api/${provider}/login/url${remember ? '?remember-me=on' : ''}`, { signal, headers: { Accept: 'text/plain' } })
  if (!response.ok) {
    let body: unknown
    try { body = JSON.parse(text) } catch { /* The OAuth guard also returns plain text. */ }
    const detail = record(body) && typeof body.message === 'string' ? body.message
      : !text.trimStart().startsWith('<') && text.length < 2000 ? text : ''
    throw new AuthError('failed', detail, response.status)
  }
  const value = text.trim()
  try {
    const url = new URL(value)
    if (url.protocol === 'https:' && !url.username && !url.password) return url.href
  } catch { /* A URL is required; never execute an arbitrary response. */ }
  throw new AuthError('invalidResponse')
}
