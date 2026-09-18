import { nextTick, readonly, ref } from 'vue'

const expired = ref(false)
export const sessionExpired = readonly(expired)
let checking: Promise<void> | undefined
let checkedAt = 0

/** Full navigation bypasses route-leave guards; unmount first to release sessions
 * and their beforeunload handlers. Never repeat redirects for concurrent 401s. */
export function redirectToLogin() {
  if (expired.value || ['/login', '/m/login'].includes(window.location.pathname)) return
  expired.value = true
  const mobile = window.location.pathname.startsWith('/m/') || window.matchMedia('(max-width: 760px)').matches
  void nextTick().then(() => window.location.replace(mobile ? '/m/login' : '/login'))
}

/** Only application responses belong here, never external cloud/probe responses. */
export function handleSessionResponse(response: { status?: number; url?: string; body?: unknown }): boolean {
  let loginResponse = false
  if (response.url) {
    try {
      const url = new URL(response.url, window.location.origin)
      loginResponse = url.origin === window.location.origin && ['/login', '/m/login'].includes(url.pathname)
    } catch { /* An invalid URL is not proof that the session expired. */ }
  }
  let body = response.body
  if (typeof body === 'string' && body.length <= 65536 && body.trimStart().startsWith('{')) {
    try { body = JSON.parse(body) } catch { /* Preserve the caller's parse error. */ }
  }
  const unauthorized = body !== null && typeof body === 'object' && !Array.isArray(body)
    && String((body as { code?: unknown }).code).trim() === '401'
  if (response.status !== 401 && !unauthorized && !loginResponse) return false
  redirectToLogin()
  return true
}

/** WebSocket/EventSource errors hide HTTP status. Confirm via a read-only endpoint
 * instead of mistaking a network interruption or cloud error for logout. */
export function checkSession(): Promise<void> {
  if (expired.value || document.hidden) return Promise.resolve()
  if (checking) return checking
  if (Date.now() - checkedAt < 5000) return Promise.resolve()
  checkedAt = Date.now()
  const controller = new AbortController()
  const timer = window.setTimeout(() => controller.abort(), 5000)
  checking = (async () => {
    try {
      const response = await fetch('/api/userInfo', {
        credentials: 'same-origin', cache: 'no-store', redirect: 'follow', signal: controller.signal,
        headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
      })
      if (handleSessionResponse({ status: response.status, url: response.url })) return
      if (response.headers.get('content-type')?.includes('application/json')) {
        const body: unknown = await response.json()
        handleSessionResponse({ body })
      }
    } catch { /* Offline, timeout and server failure do not establish logout. */ }
    finally {
      window.clearTimeout(timer)
      checking = undefined
    }
  })()
  return checking
}
