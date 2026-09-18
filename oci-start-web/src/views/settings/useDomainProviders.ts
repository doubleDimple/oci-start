import { computed, onBeforeUnmount, onMounted, reactive, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router'
import {
  DomainProviderApiError, domainProviderError, loadDomainProviderConfigs,
  normalizeCloudflareProvider, normalizeEdgeOneProvider,
  saveCloudflareProvider, saveEdgeOneProvider, testCloudflareProvider, testEdgeOneProvider,
  type CloudflareProviderConfig, type DomainProvider, type EdgeOneProviderConfig,
} from '@/api/domainProviders'

type ProviderConfig = CloudflareProviderConfig | EdgeOneProviderConfig
export interface DomainProviderState<T extends ProviderConfig> {
  draft: T
  baseline: T | null
  loaded: boolean
  readonly dirty: boolean
  testState: 'none' | 'testing' | 'passed' | 'failed'
  testProblem: DomainProviderApiError | null
  saveState: 'idle' | 'saved' | 'unknown'
  saveProblem: DomainProviderApiError | null
  requiresReload: boolean
}
type SaveSnapshot =
  | { provider: 'cloudflare'; before: CloudflareProviderConfig; config: CloudflareProviderConfig }
  | { provider: 'edgeOne'; before: EdgeOneProviderConfig; config: EdgeOneProviderConfig }

function emptyCloudflare(): CloudflareProviderConfig { return { enabled: false, apiToken: '', email: '', zoneId: '' } }
function emptyEdgeOne(): EdgeOneProviderConfig { return { enabled: false, secretId: '', secretKey: '', region: '' } }
function equal<T extends ProviderConfig>(left: T, right: T): boolean {
  return Object.keys(left).length === Object.keys(right).length
    && (Object.keys(left) as (keyof T)[]).every(key => left[key] === right[key])
}
function providerState<T extends ProviderConfig>(draft: T): DomainProviderState<T> {
  const state: DomainProviderState<T> = reactive({
    draft, baseline: null, loaded: false,
    dirty: computed(() => state.baseline !== null && !equal(state.draft, state.baseline)),
    testState: 'none', testProblem: null, saveState: 'idle', saveProblem: null, requiresReload: false,
  }) as DomainProviderState<T>
  return state
}

/** Credentials stay in this page's memory; save receipts require a separate read-back. */
export function useDomainProviders() {
  const providers = {
    cloudflare: providerState(emptyCloudflare()),
    edgeOne: providerState(emptyEdgeOne()),
  }
  const loading = ref(false)
  const loadProblem = shallowRef<DomainProviderApiError | null>(null)
  const loaded = computed(() => providers.cloudflare.loaded && providers.edgeOne.loaded)
  const anyDirty = computed(() => providers.cloudflare.dirty || providers.edgeOne.dirty)
  const saveProvider = ref<DomainProvider | null>(null)
  const savePending = ref(false)
  const saveCompleted = ref(false)
  const canDismissSave = computed(() => !savePending.value)
  const tests: Record<DomainProvider, { sequence: number; controller?: AbortController }> = {
    cloudflare: { sequence: 0 }, edgeOne: { sequence: 0 },
  }
  let disposed = false
  let readSequence = 0
  let readController: AbortController | undefined
  let snapshot: SaveSnapshot | null = null
  const saveEnabled = computed<boolean | null>(() => saveProvider.value && snapshot ? snapshot.config.enabled : null)

  function secrets(): string[] {
    return [providers.cloudflare.draft, providers.cloudflare.baseline,
      providers.edgeOne.draft, providers.edgeOne.baseline, snapshot?.config, snapshot?.before]
      .flatMap(value => value ? Object.values(value).filter((item): item is string => typeof item === 'string' && !!item) : [])
  }
  function cancelRead(): void {
    ++readSequence
    readController?.abort()
    readController = undefined
    loading.value = false
  }
  function cancelTest(provider: DomainProvider): void {
    const test = tests[provider]
    ++test.sequence
    test.controller?.abort()
    test.controller = undefined
    providers[provider].testState = 'none'
    providers[provider].testProblem = null
  }

  async function load(): Promise<void> {
    if (disposed || saveProvider.value || savePending.value || loading.value) return
    cancelRead()
    cancelTest('cloudflare')
    cancelTest('edgeOne')
    const current = readSequence
    const active = new AbortController()
    readController = active
    loading.value = true
    loadProblem.value = null
    try {
      const config = await loadDomainProviderConfigs(active.signal)
      if (disposed || current !== readSequence || active.signal.aborted) return
      Object.assign(providers.cloudflare.draft, config.cloudflare)
      Object.assign(providers.edgeOne.draft, config.edgeOne)
      providers.cloudflare.baseline = { ...config.cloudflare }
      providers.edgeOne.baseline = { ...config.edgeOne }
      for (const state of Object.values(providers)) {
        state.loaded = true
        state.requiresReload = false
        state.saveState = 'idle'
        state.saveProblem = null
      }
    } catch (cause) {
      if (!disposed && current === readSequence && !active.signal.aborted) {
        loadProblem.value = domainProviderError(cause, secrets())
      }
    } finally {
      if (!disposed && current === readSequence) {
        readController = undefined
        loading.value = false
      }
    }
  }

  function prepareSave(provider: DomainProvider): boolean {
    const state = providers[provider]
    if (disposed || loading.value || saveProvider.value || !state.loaded || state.requiresReload) return false
    state.saveProblem = null
    state.saveState = 'idle'
    try {
      snapshot = provider === 'cloudflare'
        ? { provider, before: { ...providers.cloudflare.draft }, config: normalizeCloudflareProvider(providers.cloudflare.draft, 'save') }
        : { provider, before: { ...providers.edgeOne.draft }, config: normalizeEdgeOneProvider(providers.edgeOne.draft, 'save') }
    } catch (cause) {
      state.saveProblem = domainProviderError(cause, secrets())
      return false
    }
    cancelTest(provider)
    saveCompleted.value = false
    saveProvider.value = provider
    return true
  }
  function closeSave(): void {
    if (savePending.value) return
    saveProvider.value = null
    saveCompleted.value = false
    snapshot = null
  }

  async function confirmSave(): Promise<void> {
    const submitted = snapshot
    if (disposed || !submitted || savePending.value) return
    const state = providers[submitted.provider]
    if (!state.loaded || state.requiresReload || state.saveState === 'saved') return
    savePending.value = true
    saveCompleted.value = false
    state.saveProblem = null
    cancelRead()
    cancelTest('cloudflare')
    cancelTest('edgeOne')
    const redactions = secrets()
    let receipt = false
    try {
      if (submitted.provider === 'cloudflare') await saveCloudflareProvider(submitted.config)
      else await saveEdgeOneProvider(submitted.config)
      receipt = true
      if (disposed) return
      const active = new AbortController()
      readController = active
      const config = await loadDomainProviderConfigs(active.signal)
      if (disposed || active.signal.aborted) return
      // The other provider's draft and baseline are never touched by this read.
      if (submitted.provider === 'cloudflare') {
        providers.cloudflare.baseline = { ...config.cloudflare }
        if (!equal(submitted.config, config.cloudflare)) throw new DomainProviderApiError('saveMismatch', '', true)
        if (equal(providers.cloudflare.draft, submitted.before)) Object.assign(providers.cloudflare.draft, submitted.config)
      } else {
        providers.edgeOne.baseline = { ...config.edgeOne }
        if (!equal(submitted.config, config.edgeOne)) throw new DomainProviderApiError('saveMismatch', '', true)
        if (equal(providers.edgeOne.draft, submitted.before)) Object.assign(providers.edgeOne.draft, submitted.config)
      }
      state.saveState = 'saved'
      state.saveProblem = null
    } catch (cause) {
      if (disposed) return
      const problem = domainProviderError(cause, redactions)
      state.saveProblem = receipt && problem.key !== 'saveMismatch'
        ? new DomainProviderApiError('saveUnverified', problem.detail, true) : problem
      if (receipt || problem.writeAttempted) {
        state.saveState = 'unknown'
        state.requiresReload = true
      }
    } finally {
      if (!disposed) {
        readController = undefined
        savePending.value = false
        saveCompleted.value = true
      }
    }
  }

  async function runTest(provider: DomainProvider): Promise<void> {
    const state = providers[provider]
    if (disposed || !state.loaded || loading.value || saveProvider.value || savePending.value || state.testState === 'testing') return
    cancelTest(provider)
    const test = tests[provider]
    const current = test.sequence
    const active = new AbortController()
    test.controller = active
    const redactions = secrets()
    state.testState = 'testing'
    try {
      if (provider === 'cloudflare') await testCloudflareProvider(normalizeCloudflareProvider(providers.cloudflare.draft, 'test'), active.signal)
      else await testEdgeOneProvider(normalizeEdgeOneProvider(providers.edgeOne.draft, 'test'), active.signal)
      if (!disposed && current === test.sequence && !active.signal.aborted) state.testState = 'passed'
    } catch (cause) {
      if (!disposed && current === test.sequence && !active.signal.aborted) {
        state.testState = 'failed'
        state.testProblem = domainProviderError(cause, redactions)
      }
    } finally {
      if (!disposed && current === test.sequence) test.controller = undefined
    }
  }

  watch(() => [providers.cloudflare.draft.apiToken, providers.cloudflare.draft.email, providers.cloudflare.draft.zoneId], () => cancelTest('cloudflare'), { flush: 'sync' })
  watch(() => [providers.edgeOne.draft.secretId, providers.edgeOne.draft.secretKey, providers.edgeOne.draft.region], () => cancelTest('edgeOne'), { flush: 'sync' })
  function beforeUnload(event: BeforeUnloadEvent): void {
    if (!savePending.value && !anyDirty.value) return
    event.preventDefault()
    event.returnValue = ''
  }
  onBeforeRouteLeave(() => !savePending.value)
  onBeforeRouteUpdate(() => !savePending.value)
  onMounted(() => {
    window.addEventListener('beforeunload', beforeUnload)
    void load()
  })
  onBeforeUnmount(() => {
    disposed = true
    cancelRead()
    cancelTest('cloudflare')
    cancelTest('edgeOne')
    snapshot = null
    saveProvider.value = null
    loadProblem.value = null
    for (const state of Object.values(providers)) { state.baseline = null; state.saveProblem = null; state.loaded = false }
    Object.assign(providers.cloudflare.draft, emptyCloudflare())
    Object.assign(providers.edgeOne.draft, emptyEdgeOne())
    window.removeEventListener('beforeunload', beforeUnload)
    // A submitted save is not cancelled or retried when its view disappears.
  })

  return {
    providers, loading, loadProblem, loaded, anyDirty,
    saveProvider, savePending, saveCompleted, saveEnabled, canDismissSave,
    prepareSave, confirmSave, closeSave, load, reload: load, runTest, cancelTest,
  }
}
