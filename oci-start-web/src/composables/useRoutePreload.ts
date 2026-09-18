import { onBeforeUnmount, onMounted } from 'vue'
import { routePreloader } from '@/router'

/** Warm a deliberate navigation target, plus at most three common pages while idle. */
export function useRoutePreload(warmPaths: string[] = []) {
  let disposed = false
  let intentTimer: ReturnType<typeof setTimeout> | undefined
  let warmTimer: ReturnType<typeof setTimeout> | undefined
  let idleHandle: number | undefined
  const remaining = [...new Set(warmPaths)].slice(0, 3)

  function cancelIntent() {
    if (intentTimer !== undefined) clearTimeout(intentTimer)
    intentTimer = undefined
  }

  function prepare(href: string) {
    cancelIntent()
    // Ignore incidental pointer passes across a menu while moving to another control.
    intentTimer = setTimeout(() => {
      intentTimer = undefined
      if (!disposed) void routePreloader.preload(href)
    }, 90)
  }

  function warmNext() {
    if (disposed || document.hidden || !remaining.length) return
    const run = async () => {
      idleHandle = undefined
      if (disposed || document.hidden) return
      const href = remaining.shift()
      if (href) await routePreloader.preload(href, true)
      if (!disposed && remaining.length) warmTimer = setTimeout(warmNext, 1000)
    }
    if ('requestIdleCallback' in window) idleHandle = window.requestIdleCallback(() => { void run() })
    else warmTimer = setTimeout(() => { void run() }, 500)
  }

  function startWarmup() {
    // Let the first page and its initial reads take priority over speculative code loading.
    if (!disposed && remaining.length) warmTimer = setTimeout(warmNext, 2000)
  }

  onMounted(() => {
    if (!remaining.length) return
    if (document.readyState === 'complete') startWarmup()
    else window.addEventListener('load', startWarmup, { once: true })
  })
  onBeforeUnmount(() => {
    disposed = true
    cancelIntent()
    if (warmTimer !== undefined) clearTimeout(warmTimer)
    if (idleHandle !== undefined) window.cancelIdleCallback(idleHandle)
    window.removeEventListener('load', startWarmup)
  })

  return { prepare, cancelIntent }
}
