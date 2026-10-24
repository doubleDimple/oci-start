import type { Router } from 'vue-router'

type PageLoader = () => Promise<unknown>
type NetworkHint = { saveData?: boolean; effectiveType?: string }

function canPreload() {
  const connection = (navigator as Navigator & { connection?: NetworkHint }).connection
  return !document.hidden && navigator.onLine && !connection?.saveData
    && !['slow-2g', '2g', '3g'].includes(connection?.effectiveType ?? '')
}

/** Import page code only. Vue setup hooks and business requests still run on navigation. */
export function createRoutePreloader(router: Router) {
  const loaded = new WeakMap<PageLoader, Promise<unknown>>()
  let requested: string | null = null
  let running: Promise<void> | null = null
  let navigating = true

  async function loadPage(href: string) {
    const route = router.resolve(href)
    await Promise.all(route.matched.map(record => {
      const component = record.components?.default
      // This router uses import functions for lazy pages; resolved components are objects.
      if (typeof component !== 'function') return
      const loader = component as PageLoader
      let promise = loaded.get(loader)
      if (!promise) {
        promise = Promise.resolve().then(loader)
        loaded.set(loader, promise)
        void promise.catch(() => loaded.delete(loader))
      }
      return promise
    }))
  }

  async function drain() {
    while (requested && !navigating && canPreload()) {
      const href = requested
      requested = null
      try { await loadPage(href) } catch { /* Navigation retains its normal error handling. */ }
    }
    requested = null
  }

  function preload(href: string, idle = false): Promise<void> {
    if (!href.startsWith('/') || href.startsWith('//') || navigating || !canPreload()) return Promise.resolve()
    // A new hover replaces queued work. Idle warming never displaces a user's target.
    if (idle && running) return Promise.resolve()
    requested = href
    if (!running) running = drain().finally(() => {
      running = null
      if (requested) void preload(requested)
    })
    return running
  }

  function navigationPending(value: boolean) {
    navigating = value
    if (value) requested = null
  }

  return { preload, navigationPending }
}
