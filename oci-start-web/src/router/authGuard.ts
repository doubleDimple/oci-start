import type { RouteLocationNormalized } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { sessionExpired } from '@/utils/session'
import { i18n } from '@/i18n'

/** Confirm the session before mounting a private layout or starting its page requests. */
export function createAuthenticationGuard() {
  let checking: Promise<void> | undefined

  return async (to: RouteLocationNormalized): Promise<boolean> => {
    if (to.meta.public) return true
    if (sessionExpired.value) return false

    const user = useUserStore()
    if (!user.username || user.loadFailed) {
      // Concurrent startup navigations must share the same identity read.
      checking ??= user.load().finally(() => { checking = undefined })
      await checking
    }
    if (sessionExpired.value) return false
    // A timeout, server failure or malformed response does not establish a session.
    // The existing router error view offers a reload without mounting private content.
    if (!user.username || user.loadFailed) throw new Error(i18n.global.t('header.userFailed'))
    return true
  }
}
