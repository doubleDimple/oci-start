import { computed, onBeforeUnmount, ref, shallowRef } from 'vue'
import {
  SecuritySettingsApiError, deleteSecurityMfa, loadSecurityMfaEnrollment, loadSecuritySettings,
  lookupSecurityGithub, regenerateSecurityMfa, securitySettingsError, updateGithubSecurity,
  updateGoogleSecurity, updateMfaSecurity, updateSecurityAccount, updateSecurityChannelNotify,
  updateSecurityLogo, updateTurnstileSecurity, verifySecurityMfa,
  type AccountSecurityInput, type GithubIdentity, type GithubSecurityInput, type GoogleSecurityInput,
  type MfaEnrollment, type MfaSecurityInput, type SecuritySettings, type TurnstileSecurityInput,
} from '@/api/securitySettings'

export type SecurityMutationKind = 'account' | 'logo' | 'github' | 'google' | 'mfa'
  | 'regenerateMfa' | 'deleteMfa' | 'turnstile' | 'channelNotify'
export interface SecurityMutationResult { kind: SecurityMutationKind; logoName?: string; needRelogin?: boolean }
export interface SecurityMutation {
  kind: SecurityMutationKind | null; pending: boolean; outcome: 'idle' | 'success' | 'unknown' | 'failed'
  problem: SecuritySettingsApiError | null; result: SecurityMutationResult | null
}
function emptyMutation(): SecurityMutation { return { kind: null, pending: false, outcome: 'idle', problem: null, result: null } }

/** The page owns drafts, confirmations and navigation; no credentials are persisted. */
export function useSecuritySettings() {
  const settings = shallowRef<SecuritySettings | null>(null)
  const loading = ref(false)
  const loaded = computed(() => settings.value !== null)
  const problem = shallowRef<SecuritySettingsApiError | null>(null)
  const lastUpdated = ref<number | null>(null)
  const mutation = shallowRef<SecurityMutation>(emptyMutation())
  const needRelogin = ref(false)
  const requiresReview = ref(false)
  const readRevision = ref(0)
  const reviewAfterRevision = ref(0)
  const contextLocked = computed(() => mutation.value.pending)
  const canMutate = computed(() => loaded.value && !loading.value && !problem.value && !contextLocked.value
    && !needRelogin.value && !requiresReview.value && ['idle', 'failed'].includes(mutation.value.outcome))
  const reviewReady = computed(() => requiresReview.value && !needRelogin.value && loaded.value && !loading.value
    && !problem.value && !contextLocked.value && readRevision.value >= reviewAfterRevision.value)
  const githubLookup = shallowRef<{ loading: boolean; result: GithubIdentity | null; problem: SecuritySettingsApiError | null }>({ loading: false, result: null, problem: null })
  const mfaEnrollment = shallowRef<MfaEnrollment | null>(null)
  const mfaLoading = ref(false)
  const mfaProblem = shallowRef<SecuritySettingsApiError | null>(null)
  const verification = shallowRef<{ state: 'idle' | 'checking' | 'passed' | 'failed'; problem: SecuritySettingsApiError | null }>({ state: 'idle', problem: null })
  let disposed = false
  let readSequence = 0
  let readController: AbortController | undefined
  let lookupSequence = 0
  let lookupController: AbortController | undefined
  let mfaSequence = 0
  let mfaController: AbortController | undefined
  let verificationSequence = 0
  let verificationController: AbortController | undefined
  const sensitiveSnapshots = new Set<() => void>()
  function ownSecrets(snapshot: object): () => void {
    const release = () => {
      const fields = snapshot as Record<string, unknown>
      for (const key of ['currentPassword', 'newPassword', 'clientSecret', 'secretKey']) {
        if (Object.prototype.hasOwnProperty.call(fields, key)) fields[key] = ''
      }
      sensitiveSnapshots.delete(release)
    }
    sensitiveSnapshots.add(release)
    return release
  }

  function cancelRead(): void {
    ++readSequence; readController?.abort(); readController = undefined; loading.value = false
  }
  async function load(): Promise<void> {
    if (disposed || needRelogin.value) return
    cancelRead()
    const sequence = readSequence, controller = new AbortController()
    readController = controller
    loading.value = true; problem.value = null
    const current = () => !disposed && sequence === readSequence && readController === controller && !controller.signal.aborted
    try {
      const result = await loadSecuritySettings(controller.signal)
      if (!current()) return
      settings.value = result
      lastUpdated.value = Date.now()
      ++readRevision.value
    } catch (cause) { if (current()) problem.value = securitySettingsError(cause) }
    finally { if (current()) { readController = undefined; loading.value = false } }
  }
  async function refresh(): Promise<void> { if (!contextLocked.value) await load() }
  function clearMutation(): void { if (!contextLocked.value) mutation.value = emptyMutation() }
  function acknowledgeReview(): void {
    if (!reviewReady.value) return
    requiresReview.value = false
    clearMutation()
  }
  function cancelGithubLookup(): void {
    ++lookupSequence; lookupController?.abort(); lookupController = undefined
    githubLookup.value = { loading: false, result: null, problem: null }
  }
  async function lookupGithub(username: string): Promise<GithubIdentity | null> {
    if (disposed || !loaded.value || loading.value || contextLocked.value || needRelogin.value) return null
    cancelGithubLookup()
    const sequence = lookupSequence, controller = new AbortController()
    lookupController = controller
    githubLookup.value = { loading: true, result: null, problem: null }
    const current = () => !disposed && sequence === lookupSequence && lookupController === controller && !controller.signal.aborted
    try {
      const result = await lookupSecurityGithub(username, controller.signal)
      if (!current()) return null
      githubLookup.value = { loading: false, result, problem: null }
      return result
    } catch (cause) {
      if (current()) githubLookup.value = { loading: false, result: null, problem: securitySettingsError(cause) }
      return null
    } finally { if (current()) lookupController = undefined }
  }
  function clearMfaEnrollment(): void {
    ++mfaSequence; mfaController?.abort(); mfaController = undefined
    // QR and secret belong only to this explicit reveal, never the settings baseline.
    mfaEnrollment.value = null; mfaLoading.value = false; mfaProblem.value = null
  }
  async function loadMfaEnrollment(): Promise<void> {
    if (disposed || !loaded.value || loading.value || contextLocked.value || needRelogin.value) return
    clearMfaEnrollment()
    const sequence = mfaSequence, controller = new AbortController()
    mfaController = controller; mfaLoading.value = true
    const current = () => !disposed && sequence === mfaSequence && mfaController === controller && !controller.signal.aborted
    try { const result = await loadSecurityMfaEnrollment(controller.signal); if (current()) mfaEnrollment.value = result }
    catch (cause) { if (current()) mfaProblem.value = securitySettingsError(cause) }
    finally { if (current()) { mfaController = undefined; mfaLoading.value = false } }
  }
  function clearVerification(): void {
    ++verificationSequence; verificationController?.abort(); verificationController = undefined
    verification.value = { state: 'idle', problem: null }
  }
  async function verifyMfa(code: string): Promise<void> {
    if (disposed || !loaded.value || loading.value || contextLocked.value || needRelogin.value || verification.value.state === 'checking') return
    clearVerification()
    const sequence = verificationSequence, controller = new AbortController()
    verificationController = controller
    verification.value = { state: 'checking', problem: null }
    const current = () => !disposed && sequence === verificationSequence && verificationController === controller && !controller.signal.aborted
    try {
      await verifySecurityMfa(code, controller.signal)
      if (current()) verification.value = { state: 'passed', problem: null }
    } catch (cause) { if (current()) verification.value = { state: 'failed', problem: securitySettingsError(cause, [code]) } }
    finally { if (current()) verificationController = undefined }
  }
  async function perform(kind: SecurityMutationKind, write: () => Promise<SecurityMutationResult>,
    matches?: (current: SecuritySettings) => boolean): Promise<void> {
    if (disposed || !canMutate.value) return
    cancelRead(); cancelGithubLookup(); clearMfaEnrollment(); clearVerification()
    mutation.value = { kind, pending: true, outcome: 'idle', problem: null, result: null }
    let readBack = false
    try {
      const result = await write()
      if (disposed) return
      mutation.value = { ...mutation.value, outcome: 'success', result }
      if (kind === 'account') needRelogin.value = result.needRelogin === true
      readBack = !needRelogin.value
    } catch (cause) {
      if (disposed) return
      const failure = securitySettingsError(cause)
      mutation.value = { ...mutation.value, outcome: failure.writeAttempted ? 'unknown' : 'failed', problem: failure }
      if (failure.writeAttempted) {
        requiresReview.value = true
        reviewAfterRevision.value = readRevision.value + 1
        // A settings GET cannot prove which password is now valid; preserve the
        // unknown receipt and require sign-in instead of triggering a hidden 401 redirect.
        if (kind === 'account') needRelogin.value = true
        else readBack = true
      }
    } finally {
      if (!disposed) {
        if (readBack) {
          await load()
          // A successful receipt remains successful. A different public read-back
          // is a separate discrepancy; existence flags cannot verify a secret's value.
          if (!disposed && mutation.value.outcome === 'success' && !problem.value && settings.value
            && matches && !matches(settings.value)) problem.value = new SecuritySettingsApiError('saveMismatch')
        }
        if (!disposed) mutation.value = { ...mutation.value, pending: false }
      }
    }
  }
  function requireStoredSecret(enabled: boolean, keep: boolean, exists: boolean | undefined): void {
    if (enabled && keep && !exists) throw new SecuritySettingsApiError('invalidInput')
  }
  async function saveAccount(input: AccountSecurityInput): Promise<void> {
    const snapshot = { ...input }
    const release = ownSecrets(snapshot)
    const expectedUsername = snapshot.newUsername?.trim() || settings.value?.currentUsername
    try {
      await perform('account', async () => {
        try { return { kind: 'account', ...await updateSecurityAccount(snapshot) } }
        finally { release() }
      }, current => current.currentUsername === expectedUsername)
    } finally { release() }
  }
  async function saveLogo(logoName: string): Promise<void> {
    const snapshot = logoName
    await perform('logo', async () => { await updateSecurityLogo(snapshot); return { kind: 'logo', logoName: snapshot.trim() } },
      current => current.siteLogoName === snapshot.trim())
  }
  async function saveGithub(input: GithubSecurityInput): Promise<void> {
    const snapshot = { ...input }
    const release = ownSecrets(snapshot)
    const hasSecret = snapshot.keepSecret ? settings.value?.github.hasClientSecret : !!snapshot.clientSecret.trim()
    try {
      await perform('github', async () => {
        try {
          requireStoredSecret(snapshot.enabled, snapshot.keepSecret, settings.value?.github.hasClientSecret)
          await updateGithubSecurity(snapshot); return { kind: 'github' }
        } finally { release() }
      }, current => current.github.enabled === snapshot.enabled && current.github.userName === snapshot.userName.trim()
        && current.github.githubId === snapshot.githubId.trim() && current.github.clientId === snapshot.clientId.trim()
        && current.github.redirectUri === snapshot.redirectUri.trim() && current.github.hasClientSecret === hasSecret)
    } finally { release() }
  }
  async function saveGoogle(input: GoogleSecurityInput): Promise<void> {
    const snapshot = { ...input }
    const release = ownSecrets(snapshot)
    const hasSecret = snapshot.keepSecret ? settings.value?.google.hasClientSecret : !!snapshot.clientSecret.trim()
    try {
      await perform('google', async () => {
        try {
          requireStoredSecret(snapshot.enabled, snapshot.keepSecret, settings.value?.google.hasClientSecret)
          await updateGoogleSecurity(snapshot); return { kind: 'google' }
        } finally { release() }
      }, current => current.google.enabled === snapshot.enabled && current.google.email === snapshot.email.trim()
        && current.google.clientId === snapshot.clientId.trim() && current.google.redirectUri === snapshot.redirectUri.trim()
        && current.google.hasClientSecret === hasSecret)
    } finally { release() }
  }
  async function saveMfa(input: MfaSecurityInput): Promise<void> {
    const snapshot = { ...input }
    await perform('mfa', async () => { await updateMfaSecurity(snapshot); return { kind: 'mfa' } },
      current => current.mfa.enabled === snapshot.enabled && current.mfa.issuer === (snapshot.issuer.trim() || 'OCI-Start Verify')
        && (!snapshot.enabled || current.mfa.hasSecretKey))
  }
  async function regenerateMfa(): Promise<void> {
    await perform('regenerateMfa', async () => { await regenerateSecurityMfa(); return { kind: 'regenerateMfa' } }, current => current.mfa.hasSecretKey)
  }
  async function deleteMfa(): Promise<void> {
    await perform('deleteMfa', async () => { await deleteSecurityMfa(); return { kind: 'deleteMfa' } }, current => !current.mfa.enabled && !current.mfa.hasSecretKey)
  }
  async function saveTurnstile(input: TurnstileSecurityInput): Promise<void> {
    const snapshot = { ...input }
    const release = ownSecrets(snapshot)
    const hasSecret = snapshot.keepSecret ? settings.value?.turnstile.hasSecretKey : !!snapshot.secretKey.trim()
    try {
      await perform('turnstile', async () => {
        try {
          requireStoredSecret(snapshot.enabled, snapshot.keepSecret, settings.value?.turnstile.hasSecretKey)
          await updateTurnstileSecurity(snapshot); return { kind: 'turnstile' }
        } finally { release() }
      }, current => current.turnstile.enabled === snapshot.enabled && current.turnstile.siteKey === snapshot.siteKey.trim()
        && current.turnstile.hasSecretKey === hasSecret)
    } finally { release() }
  }
  async function saveChannelNotify(enabled: boolean): Promise<void> {
    await perform('channelNotify', async () => { await updateSecurityChannelNotify(enabled); return { kind: 'channelNotify' } },
      current => current.channelNotifyEnabled === enabled)
  }
  onBeforeUnmount(() => {
    disposed = true
    cancelRead(); cancelGithubLookup(); clearMfaEnrollment(); clearVerification()
    for (const release of sensitiveSnapshots) release()
    settings.value = null; mutation.value = emptyMutation()
  })
  return { settings, loading, loaded, problem, lastUpdated, refresh, mutation, contextLocked, canMutate,
    requiresReview, reviewReady, acknowledgeReview, clearMutation, needRelogin,
    saveAccount, saveLogo, saveGithub, saveGoogle, saveMfa, regenerateMfa, deleteMfa, saveTurnstile, saveChannelNotify,
    githubLookup, lookupGithub, cancelGithubLookup, mfaEnrollment, mfaLoading, mfaProblem,
    loadMfaEnrollment, clearMfaEnrollment, verification, verifyMfa, clearVerification }
}
