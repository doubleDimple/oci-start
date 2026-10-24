import { computed, onBeforeUnmount, onMounted, ref, shallowReactive, watch } from 'vue'
import {
  aiModelsError, listAiModelConfigs, listAiModelTenants, listAvailableAiModels,
  type AiModelConfig, type AiModelTenant, type AvailableAiModel,
} from '@/api/aiModels'

export const AI_MODELS_PAGE_SIZE = 6

export interface AiModelsReadState<T> {
  rows: T[]
  loading: boolean
  /** A successful response exists for the current scope, including an empty list. */
  loaded: boolean
  problem: ReturnType<typeof aiModelsError> | null
}
interface ReadLane<T> {
  state: AiModelsReadState<T>
  sequence: number
  controller?: AbortController
}
function createLane<T>(): ReadLane<T> {
  return {
    state: shallowReactive({ rows: [] as T[], loading: false, loaded: false, problem: null }),
    sequence: 0,
  }
}
function stopLane<T>(lane: ReadLane<T>) {
  ++lane.sequence
  lane.controller?.abort()
  lane.controller = undefined
  lane.state.loading = false
}
function clampPage(value: number, pages: number) {
  return Number.isSafeInteger(value) ? Math.min(Math.max(1, value), pages) : 1
}

/** Read-only data for the OCI AI models page. Writes remain owned by its view. */
export function useAiModelsData() {
  const tenantId = ref('')
  const filterByTenant = ref(false)
  const tenantLane = createLane<AiModelTenant>()
  const modelLane = createLane<AvailableAiModel>()
  const configLane = createLane<AiModelConfig>()
  const tenants = tenantLane.state
  const models = modelLane.state
  const configs = configLane.state
  const modelPage = ref(1)
  const configPage = ref(1)
  let modelScope = ''
  let disposed = false

  const selectedTenant = computed(() => tenants.rows.find((tenant) => tenant.id === tenantId.value) || null)
  // The old association switch still shows every configuration when no tenant
  // is selected. Filtering is entirely local; the API always returns OCI rows.
  const visibleConfigs = computed(() => filterByTenant.value && tenantId.value
    ? configs.rows.filter((config) => config.tenantId === tenantId.value)
    : configs.rows)
  const modelPages = computed(() => Math.max(1, Math.ceil(models.rows.length / AI_MODELS_PAGE_SIZE)))
  const configPages = computed(() => Math.max(1, Math.ceil(visibleConfigs.value.length / AI_MODELS_PAGE_SIZE)))
  const pagedModels = computed(() => {
    const start = (modelPage.value - 1) * AI_MODELS_PAGE_SIZE
    return models.rows.slice(start, start + AI_MODELS_PAGE_SIZE)
  })
  const pagedConfigs = computed(() => {
    const start = (configPage.value - 1) * AI_MODELS_PAGE_SIZE
    return visibleConfigs.value.slice(start, start + AI_MODELS_PAGE_SIZE)
  })
  // Preserve the legacy UI's GLOBAL modelId policy, including disabled rows.
  // The backend has no modelId uniqueness constraint; this is not a DB guarantee.
  const configuredModelIds = computed(() => new Set(configs.rows.map((config) => config.modelId).filter(Boolean)))
  function isModelConfigured(modelId: string) { return configuredModelIds.value.has(modelId) }
  function setModelPage(value: number) { modelPage.value = clampPage(value, modelPages.value) }
  function setConfigPage(value: number) { configPage.value = clampPage(value, configPages.value) }

  async function readLane<T>(
    lane: ReadLane<T>,
    read: (signal: AbortSignal) => Promise<T[]>,
    sameScope: () => boolean = () => true,
    afterRead?: (rows: T[]) => void,
  ): Promise<boolean> {
    if (disposed) return false
    stopLane(lane)
    const sequence = lane.sequence
    const controller = new AbortController()
    lane.controller = controller
    lane.state.loading = true
    lane.state.problem = null
    try {
      const rows = await read(controller.signal)
      if (disposed || controller.signal.aborted || sequence !== lane.sequence || !sameScope()) return false
      lane.state.rows = rows
      lane.state.loaded = true
      afterRead?.(rows)
      return true
    } catch (cause) {
      if (!disposed && !controller.signal.aborted && sequence === lane.sequence && sameScope()) {
        lane.state.problem = aiModelsError(cause)
      }
      // A refresh failure retains the last successful rows and loaded flag.
      return false
    } finally {
      if (!disposed && sequence === lane.sequence) {
        lane.state.loading = false
        lane.controller = undefined
      }
    }
  }

  function resetModels(scope: string) {
    stopLane(modelLane)
    modelScope = scope
    models.rows = []
    models.loaded = false
    models.problem = null
    modelPage.value = 1
  }
  function loadTenants(): Promise<boolean> {
    return readLane(tenantLane, listAiModelTenants, undefined, (rows) => {
      // This endpoint returns the complete tenant list, so an absent selected
      // tenant can be cleared after success, never after a failed refresh.
      if (tenantId.value && !rows.some((tenant) => tenant.id === tenantId.value)) tenantId.value = ''
    })
  }
  function loadModels(): Promise<boolean> {
    if (disposed) return Promise.resolve(false)
    const scope = tenantId.value
    if (modelScope !== scope || !scope) resetModels(scope)
    if (!scope) return Promise.resolve(false)
    return readLane(modelLane, (signal) => listAvailableAiModels(scope, signal), () => tenantId.value === scope && modelScope === scope)
  }
  /** Returns true only when this read actually applied a successful response. */
  function loadConfigs(): Promise<boolean> { return readLane(configLane, listAiModelConfigs) }
  async function refreshAll(): Promise<void> {
    if (disposed) return
    await Promise.allSettled([loadTenants(), loadConfigs(), loadModels()])
  }
  /** Cancel before a write so pre-write responses cannot overwrite its refresh. */
  function cancelReads() {
    stopLane(tenantLane)
    stopLane(modelLane)
    stopLane(configLane)
  }

  watch(tenantId, (scope) => {
    resetModels(scope)
    if (filterByTenant.value) configPage.value = 1
    if (scope) void loadModels()
  }, { flush: 'sync' })
  watch(filterByTenant, () => { configPage.value = 1 }, { flush: 'sync' })
  // Refreshes preserve the current local page unless the result shrank. These
  // watchers also bound direct v-model page changes from the pagination UI.
  watch([modelPage, modelPages], () => setModelPage(modelPage.value), { flush: 'sync' })
  watch([configPage, configPages], () => setConfigPage(configPage.value), { flush: 'sync' })

  onMounted(() => { void Promise.allSettled([loadTenants(), loadConfigs()]) })
  onBeforeUnmount(() => { disposed = true; cancelReads() })

  return {
    tenantId, filterByTenant, selectedTenant, tenants, models, configs,
    visibleConfigs, pagedModels, pagedConfigs, modelPage, configPage, modelPages, configPages,
    pageSize: AI_MODELS_PAGE_SIZE, configuredModelIds, isModelConfigured,
    loadTenants, loadModels, loadConfigs, refreshAll, cancelReads, setModelPage, setConfigPage,
  }
}
