import { shallowRef } from 'vue'

/** Holds an active token revealed or created during the current in-memory SPA session only. */
export const sessionPlainToken = shallowRef('')

export function setSessionPlainToken(token: string) {
  sessionPlainToken.value = token.trim()
}

export function clearSessionPlainToken() {
  sessionPlainToken.value = ''
}
