import { computed, nextTick, readonly, ref, shallowRef } from 'vue'
import type { RouteLocationNormalized, Router } from 'vue-router'

const startup = document.getElementById('startup-loading')
const pending = ref(true)
const loading = ref(false)
const visible = ref(!!startup && window.getComputedStyle(startup).opacity !== '0')
const targetPath = ref('')
const problem = shallowRef<{ href: string; cause: unknown } | null>(null)
export const navigationPending = readonly(pending)
export const navigationLoading = readonly(loading)
export const navigationLoadingVisible = readonly(visible)
export const navigationTargetPath = readonly(targetPath)
export const navigationProblem = readonly(problem)
export const navigationErrorDetail = computed(() => {
  const cause = problem.value?.cause
  return cause instanceof Error ? cause.message : typeof cause === 'string' ? cause : ''
})

let sequence = 0
let current: { id: number; href: string; route: RouteLocationNormalized | null } | null = null
let showTimer: ReturnType<typeof setTimeout> | undefined

function showLoading() {
  loading.value = true
  if (!visible.value && showTimer === undefined) {
    showTimer = setTimeout(() => {
      showTimer = undefined
      if (loading.value) visible.value = true
    }, 160)
  }
}

function begin(path: string, href: string, route: RouteLocationNormalized | null) {
  current = { id: ++sequence, href, route }
  pending.value = true
  targetPath.value = path
  problem.value = null
  if (route) showLoading()
  else {
    // Leave-confirmation dialogs must remain interactive until their guard settles.
    loading.value = false
    visible.value = false
    if (showTimer !== undefined) clearTimeout(showTimer)
    showTimer = undefined
  }
  return current.id
}

function finish(cause?: unknown) {
  if (cause) problem.value = { href: current?.href || window.location.pathname, cause }
  current = null
  if (showTimer !== undefined) clearTimeout(showTimer)
  showTimer = undefined
  pending.value = false
  loading.value = false
  visible.value = false
  targetPath.value = ''
}

export function isSameNavigation(first: RouteLocationNormalized, second: RouteLocationNormalized) {
  return (first.redirectedFrom ?? first) === (second.redirectedFrom ?? second)
}

export function beginRouteNavigation(to: RouteLocationNormalized) {
  if (current && !current.route) {
    // An older navigation can finish its guards during a newer click's paint frame.
    if (current.href !== to.fullPath && current.href !== to.redirectedFrom?.fullPath) return
    current.route = to
    current.href = to.fullPath
    targetPath.value = to.path
    showLoading()
    return
  }
  if (current?.route && isSameNavigation(current.route, to)) {
    current.route = to
    current.href = to.fullPath
    targetPath.value = to.path
    showLoading()
    return
  }
  begin(to.path, to.fullPath, to)
}

export async function endRouteNavigation(to: RouteLocationNormalized, failed = false, cause?: unknown) {
  if (!current?.route || !isSameNavigation(current.route, to)) return
  const id = current.id
  // Successful routing commits before Vue has mounted the new page.
  if (!failed) await nextTick()
  if (current?.id === id && current.route && isSameNavigation(current.route, to)) finish(cause)
}

/** Paint the selected menu before cached page setup or chart rendering can occupy the thread. */
export async function navigateWithFeedback(router: Router, href: string) {
  const target = router.resolve(href)
  if (target.fullPath === router.currentRoute.value.fullPath && !pending.value) return
  const id = begin(target.path, target.fullPath, null)
  await nextTick()
  await new Promise<void>(resolve => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })
  if (current?.id !== id) return
  try {
    await router.push(href)
    // Duplicated, rejected and redirected navigation may skip the final beforeEach.
    await nextTick()
    if (current?.id === id) finish()
  } catch (cause) {
    if (current?.id === id) finish(cause)
  }
}

export function dismissNavigationProblem() { problem.value = null }
