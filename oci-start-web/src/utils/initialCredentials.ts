/** First-account policy only; existing accounts can still sign in with these names. */
export function isReservedRegistrationUsername(value: string): boolean {
  const name = value.trim().normalize('NFKC').trim().toLowerCase()
  return ['root', 'admin', 'administrator', 'superadmin', 'superuser', 'system', 'guest', 'test', 'user'].includes(name)
    || /^(root|admin)\d+$/.test(name)
}

/** Generate first-account suggestions only with the browser's cryptographic random source. */
export function generateInitialCredentials(): { username: string; password: string } {
  const random = globalThis.crypto
  if (!random?.getRandomValues) throw new Error('Secure random source unavailable')
  const index = (size: number) => {
    const limit = 256 - (256 % size)
    const byte = new Uint8Array(1)
    do { random.getRandomValues(byte) } while (byte[0]! >= limit)
    return byte[0]! % size
  }
  const pick = (alphabet: string) => alphabet[index(alphabet.length)]!
  const usernameAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789'
  const groups = ['abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', '0123456789', '!@#$%^&*()-_=+']
  const alphabet = groups.join('')
  const password = groups.map(pick)
  while (password.length < 24) password.push(pick(alphabet))
  for (let position = password.length - 1; position > 0; position--) {
    const other = index(position + 1)
    const current = password[position]!
    password[position] = password[other]!
    password[other] = current
  }
  return { username: `u_${Array.from({ length: 10 }, () => pick(usernameAlphabet)).join('')}`, password: password.join('') }
}

/** Called only by a user gesture. The temporary fallback field is always cleared and removed. */
export async function copyCredentialText(value: string): Promise<boolean> {
  if (!value) return false
  try {
    if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value)
      return true
    }
  } catch { /* Plain HTTP and denied clipboard permission can use the user-gesture fallback. */ }
  if (typeof document === 'undefined' || !document.body) return false
  const active = document.activeElement as HTMLElement | null
  const field = document.createElement('textarea')
  field.value = value
  field.readOnly = true
  field.setAttribute('aria-hidden', 'true')
  field.style.cssText = 'position:fixed;top:0;left:-9999px;opacity:0'
  try {
    document.body.appendChild(field)
    field.select()
    field.setSelectionRange(0, value.length)
    return typeof document.execCommand === 'function' && document.execCommand('copy')
  } catch {
    return false
  } finally {
    field.value = ''
    field.remove()
    try { active?.focus?.({ preventScroll: true }) } catch { /* Copy result is independent of restoring focus. */ }
  }
}
