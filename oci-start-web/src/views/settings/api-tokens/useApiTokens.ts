import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from 'vue'
import {
  ApiTokenApiError, apiTokenError, generateApiToken, loadApiTokenMaterial, loadApiTokenState, revokeApiToken,
  type ApiTokenInput, type ApiTokenMaterial, type ApiTokenState,
} from '@/api/apiTokens'

export interface ApiTokenMutation {
  kind: 'generate' | 'revoke' | null
  pending: boolean
  outcome: 'idle' | 'success' | 'failed' | 'unknown'
  problem: ApiTokenApiError | null
  result: ApiTokenState | null
}
function emptyMutation(): ApiTokenMutation { return { kind: null, pending: false, outcome: 'idle', problem: null, result: null } }

/** The page owns drafts, confirmation snapshots and navigation. No automatic writes or refreshes. */
export function useApiTokens() {
  const state = shallowRef<ApiTokenState | null>(null), loading = ref(false)
  const loaded = computed(() => state.value !== null), problem = shallowRef<ApiTokenApiError | null>(null)
  const lastUpdated = ref<number | null>(null), isExpired = ref<boolean | null>(null)
  const material = shallowRef<ApiTokenMaterial | null>(null), materialLoading = ref(false)
  const materialProblem = shallowRef<ApiTokenApiError | null>(null)
  const mutation = shallowRef<ApiTokenMutation>(emptyMutation())
  const requiresReview = ref(false), readRevision = ref(0), reviewAfterRevision = ref(0)
  const readbackCompleted = ref(false), hidden = ref(document.hidden)
  const contextLocked = computed(() => mutation.value.pending)
  const canMutate = computed(() => loaded.value && !loading.value && !problem.value && !contextLocked.value
    && !requiresReview.value && !materialLoading.value && !hidden.value)
  const canReveal = computed(() => !!state.value?.hasToken && state.value.enabled && isExpired.value === false
    && state.value.expiresAtEpochMs !== null
    && !loading.value && !problem.value && !contextLocked.value && !materialLoading.value && !hidden.value)
  const reviewReady = computed(() => requiresReview.value && loaded.value && !loading.value && !problem.value
    && !contextLocked.value && readRevision.value >= reviewAfterRevision.value)
  const readbackChanged = computed(() => mutation.value.outcome === 'success' && readbackCompleted.value
    && !loading.value && !problem.value && !!state.value && !!mutation.value.result
    && state.value.revision !== mutation.value.result.revision)
  let disposed = false, readSequence = 0, materialSequence = 0
  let readController: AbortController | undefined, materialController: AbortController | undefined
  let expiryTimer: number | undefined, expiresMonotonic = 0, expiresWall = 0

  function cancelRead(): void { ++readSequence; readController?.abort(); readController = undefined; loading.value = false }
  function clearMaterial(): void {
    ++materialSequence; materialController?.abort(); materialController = undefined
    if (material.value) material.value.tokenValue = ''
    material.value = null; materialLoading.value = false; materialProblem.value = null
  }
  function cancelExpiry(): void {
    if (expiryTimer !== undefined) window.clearTimeout(expiryTimer)
    expiryTimer = undefined; expiresMonotonic = 0; expiresWall = 0
  }
  function checkExpiry(): void {
    if (disposed || !expiresMonotonic) return
    if (expiryTimer !== undefined) window.clearTimeout(expiryTimer)
    const remaining = Math.min(expiresMonotonic - performance.now(), expiresWall - Date.now())
    if (remaining <= 0) {
      cancelExpiry(); isExpired.value = true
      // Expiring the old token during replacement must not invalidate the later
      // explicit generation receipt when no reveal is currently held or loading.
      if (material.value || materialLoading.value) clearMaterial()
      return
    }
    // Long-lived tokens may exceed the browser's maximum setTimeout delay.
    expiryTimer = window.setTimeout(checkExpiry, Math.min(remaining, 2_147_000_000))
  }
  function acceptState(value: ApiTokenState, requestStarted: number): void {
    if (material.value && material.value.metadata.revision !== value.revision) clearMaterial()
    state.value = value; lastUpdated.value = Date.now(); cancelExpiry()
    isExpired.value = value.isExpired
    if (value.isExpired === true) { clearMaterial(); return }
    if (value.expiresAtEpochMs === null) return
    // Subtract the complete round trip rather than extending validity by network time.
    const now = performance.now(), lifetime = value.expiresAtEpochMs - value.serverTime - Math.max(0, now - requestStarted)
    expiresMonotonic = now + lifetime; expiresWall = Date.now() + lifetime
    checkExpiry()
  }
  async function load(): Promise<boolean> {
    if (disposed) return false
    cancelRead()
    const sequence = readSequence, controller = new AbortController(), started = performance.now()
    readController = controller; loading.value = true; problem.value = null
    const current = () => !disposed && sequence === readSequence && readController === controller && !controller.signal.aborted
    try {
      const result = await loadApiTokenState(controller.signal)
      if (!current()) return false
      acceptState(result, started); ++readRevision.value
      return true
    } catch (cause) { if (current()) problem.value = apiTokenError(cause); return false }
    finally { if (current()) { readController = undefined; loading.value = false } }
  }
  async function refresh(): Promise<void> {
    if (disposed || contextLocked.value) return
    clearMaterial()
    const complete = await load()
    if (!disposed && complete && mutation.value.outcome === 'success') readbackCompleted.value = true
  }
  async function revealToken(expectedRevision = state.value?.revision): Promise<void> {
    checkExpiry()
    if (disposed || !canReveal.value || !expectedRevision || expectedRevision !== state.value?.revision) return
    clearMaterial()
    const sequence = materialSequence, controller = new AbortController(), started = performance.now()
    materialController = controller; materialLoading.value = true
    const current = () => !disposed && !hidden.value && !contextLocked.value && sequence === materialSequence
      && materialController === controller && !controller.signal.aborted && state.value?.revision === expectedRevision
    try {
      const result = await loadApiTokenMaterial(expectedRevision, controller.signal)
      try {
        if (!current()) return
        acceptState(result.metadata, started)
        if (!current() || isExpired.value === true || !result.metadata.enabled) return
        material.value = { metadata: result.metadata, tokenValue: result.tokenValue }
      } finally { result.tokenValue = '' }
    } catch (cause) { if (current()) materialProblem.value = apiTokenError(cause) }
    finally { if (current()) { materialController = undefined; materialLoading.value = false } }
  }
  function clearMutation(): void {
    if (contextLocked.value || requiresReview.value) return
    mutation.value = emptyMutation(); readbackCompleted.value = false
  }
  function acknowledgeReview(): void {
    if (!reviewReady.value) return
    // A fresh read makes manual comparison possible; it does not prove a lost request has finished.
    requiresReview.value = false; clearMutation()
  }
  async function perform(kind: 'generate' | 'revoke', write: () => Promise<ApiTokenState | ApiTokenMaterial>): Promise<void> {
    if (disposed || !canMutate.value) return
    cancelRead(); clearMaterial(); readbackCompleted.value = false
    mutation.value = { kind, pending: true, outcome: 'idle', problem: null, result: null }
    const started = performance.now(), materialGeneration = materialSequence
    let readBack = false
    try {
      const receipt = await write()
      const generated = 'metadata' in receipt ? receipt : null
      try {
        if (disposed) return
        const metadata = generated ? generated.metadata : receipt as ApiTokenState
        mutation.value = { ...mutation.value, outcome: 'success', result: metadata }
        acceptState(metadata, started)
        if (generated && !hidden.value && materialSequence === materialGeneration && isExpired.value !== true) {
          material.value = { metadata, tokenValue: generated.tokenValue }
        }
        readBack = true
      } finally { if (generated) generated.tokenValue = '' }
    } catch (cause) {
      if (disposed) return
      const failure = apiTokenError(cause)
      mutation.value = { ...mutation.value, outcome: failure.writeAttempted ? 'unknown' : 'failed', problem: failure }
      if (failure.writeAttempted) {
        requiresReview.value = true; reviewAfterRevision.value = readRevision.value + 1; readBack = true
      } else if (failure.key === 'conflict' || failure.key === 'notFound') readBack = true
    } finally {
      if (!disposed) {
        if (readBack) readbackCompleted.value = await load()
        if (!disposed) mutation.value = { ...mutation.value, pending: false }
      }
    }
  }
  async function generateToken(input: ApiTokenInput, expectedRevision: string): Promise<void> {
    const snapshot = { ...input }, revision = expectedRevision
    await perform('generate', () => generateApiToken(snapshot, revision))
  }
  async function revokeToken(expectedRevision: string): Promise<void> {
    const revision = expectedRevision
    await perform('revoke', () => revokeApiToken(revision))
  }
  function visibilityChanged(): void {
    hidden.value = document.hidden
    if (hidden.value) clearMaterial()
    else checkExpiry()
  }
  onMounted(() => document.addEventListener('visibilitychange', visibilityChanged))
  onBeforeUnmount(() => {
    disposed = true; cancelRead(); clearMaterial(); cancelExpiry()
    state.value = null; mutation.value = emptyMutation()
    document.removeEventListener('visibilitychange', visibilityChanged)
  })
  return { state, loading, loaded, problem, lastUpdated, refresh, isExpired, canReveal,
    material, materialLoading, materialProblem, revealToken, clearMaterial, mutation, canMutate, contextLocked,
    requiresReview, reviewReady, readbackChanged, acknowledgeReview, clearMutation, generateToken, revokeToken }
}
