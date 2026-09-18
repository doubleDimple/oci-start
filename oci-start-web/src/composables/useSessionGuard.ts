import { onBeforeUnmount, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { checkSession, sessionExpired } from '@/utils/session'

/** Keep idle/stream-only pages aware of logout without delaying navigation. */
export function useSessionGuard() {
  const route = useRoute()
  let timer: ReturnType<typeof setInterval> | undefined
  const verify = () => { if (route.matched.length && !route.meta.public && !sessionExpired.value) void checkSession() }
  onMounted(() => {
    // The shell's initial userInfo read already checks entry authentication.
    timer = setInterval(verify, 30000)
    window.addEventListener('focus', verify)
    window.addEventListener('online', verify)
    document.addEventListener('visibilitychange', verify)
  })
  watch(() => route.fullPath, verify)
  onBeforeUnmount(() => {
    if (timer !== undefined) clearInterval(timer)
    window.removeEventListener('focus', verify)
    window.removeEventListener('online', verify)
    document.removeEventListener('visibilitychange', verify)
  })
}
