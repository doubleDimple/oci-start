import { computed, onBeforeUnmount, ref, shallowRef } from 'vue'
import {
  NetworkQualityApiError, createNetworkQualityTask, deleteNetworkQualityTask,
  fetchNetworkQualityHistory, fetchNetworkQualityOverview, installNetworkQualityAgent,
  networkQualityError, normalizeNetworkQualityTask, runNetworkQualityTask, updateNetworkQualityTask,
  type NetworkQualityAgent, type NetworkQualityHistory, type NetworkQualityHistorySelection,
  type NetworkQualityOverview, type NetworkQualityRunReceipt, type NetworkQualityTask,
  type NetworkQualityTaskInput,
} from '@/api/networkQuality'

export type NetworkQualityMutationResult = { kind: 'save'; task: NetworkQualityTask }
  | { kind: 'delete'; deleted: true } | { kind: 'run'; receipt: NetworkQualityRunReceipt }
  | { kind: 'install'; message: string }
export interface NetworkQualityMutation {
  kind: 'save' | 'delete' | 'run' | 'install' | null
  targetId: string
  pending: boolean
  outcome: 'idle' | 'success' | 'unknown' | 'failed'
  result: NetworkQualityMutationResult | null
  problem: NetworkQualityApiError | null
}
function emptyMutation(): NetworkQualityMutation {
  return { kind: null, targetId: '', pending: false, outcome: 'idle', result: null, problem: null }
}
function sameSelection(a: NetworkQualityHistorySelection | null, b: NetworkQualityHistorySelection | null): boolean {
  return !!a && !!b && a.instanceId === b.instanceId && a.taskId === b.taskId
    && a.revision === b.revision && a.hours === b.hours
}

/** The page owns visibility, refresh cadence, confirmation dialogs and navigation guards. */
export function useNetworkQuality() {
  const overview = shallowRef<NetworkQualityOverview | null>(null)
  const tasks = computed(() => overview.value?.tasks ?? [])
  const agents = computed(() => overview.value?.agents ?? [])
  const latest = computed(() => overview.value?.latest ?? [])
  const loading = ref(false)
  const loaded = computed(() => overview.value !== null)
  const problem = shallowRef<NetworkQualityApiError | null>(null)
  const lastUpdated = ref<number | null>(null)
  const mutation = shallowRef<NetworkQualityMutation>(emptyMutation())
  const requiresReview = ref(false)
  const readRevision = ref(0)
  const reviewAfterRevision = ref(0)
  const contextLocked = computed(() => mutation.value.pending)
  const canMutate = computed(() => loaded.value && !loading.value && !problem.value && !contextLocked.value
    && !requiresReview.value && ['idle', 'failed'].includes(mutation.value.outcome))
  const reviewReady = computed(() => requiresReview.value && loaded.value && !loading.value && !problem.value
    && !contextLocked.value && readRevision.value >= reviewAfterRevision.value)
  const historySelection = shallowRef<NetworkQualityHistorySelection | null>(null)
  const historyData = shallowRef<NetworkQualityHistory | null>(null)
  const historyLoading = ref(false)
  const historyProblem = shallowRef<NetworkQualityApiError | null>(null)
  let disposed = false
  let overviewSequence = 0
  let overviewController: AbortController | undefined
  let historySequence = 0
  let historyController: AbortController | undefined

  function cancelOverview(): void {
    ++overviewSequence
    overviewController?.abort()
    overviewController = undefined
    loading.value = false
  }
  function cancelHistory(): void {
    ++historySequence
    historyController?.abort()
    historyController = undefined
    historyLoading.value = false
  }
  async function loadOverview(): Promise<void> {
    if (disposed) return
    cancelOverview()
    const sequence = overviewSequence
    const controller = new AbortController()
    overviewController = controller
    loading.value = true
    problem.value = null
    const current = () => !disposed && sequence === overviewSequence && overviewController === controller && !controller.signal.aborted
    try {
      const data = await fetchNetworkQualityOverview(controller.signal)
      if (!current()) return
      overview.value = data
      lastUpdated.value = data.serverTime
      ++readRevision.value
    } catch (cause) {
      if (current()) problem.value = networkQualityError(cause)
    } finally {
      if (current()) { overviewController = undefined; loading.value = false }
    }
  }
  async function refresh(): Promise<void> {
    if (contextLocked.value || disposed) return
    await loadOverview()
  }
  async function loadHistory(selection: NetworkQualityHistorySelection): Promise<void> {
    if (disposed) return
    const target = { ...selection }
    if (!sameSelection(historySelection.value, target)) historyData.value = null
    historySelection.value = target
    cancelHistory()
    const sequence = historySequence
    const controller = new AbortController()
    historyController = controller
    historyLoading.value = true
    historyProblem.value = null
    const current = () => !disposed && sequence === historySequence && historyController === controller
      && !controller.signal.aborted && sameSelection(historySelection.value, target)
    try {
      const data = await fetchNetworkQualityHistory(target, controller.signal)
      if (current()) historyData.value = data
    } catch (cause) {
      if (current()) historyProblem.value = networkQualityError(cause)
    } finally {
      if (current()) { historyController = undefined; historyLoading.value = false }
    }
  }
  async function readHistory(selection: NetworkQualityHistorySelection): Promise<void> {
    if (contextLocked.value || disposed) return
    await loadHistory(selection)
  }
  async function refreshHistory(): Promise<void> {
    if (historySelection.value) await readHistory(historySelection.value)
  }
  function closeHistory(): void {
    cancelHistory()
    historySelection.value = null
    historyData.value = null
    historyProblem.value = null
  }
  function clearMutation(): void {
    if (contextLocked.value) return
    mutation.value = emptyMutation()
  }
  function acknowledgeReview(): void {
    if (!reviewReady.value) return
    requiresReview.value = false
    clearMutation()
  }
  function currentTask(snapshot: NetworkQualityTask): void {
    const current = tasks.value.find(task => task.id === snapshot.id)
    if (!current) throw new NetworkQualityApiError('notFound')
    if (current.version !== snapshot.version) throw new NetworkQualityApiError('conflict')
  }
  async function perform(kind: NonNullable<NetworkQualityMutation['kind']>, targetId: string,
    write: () => Promise<NetworkQualityMutationResult>): Promise<void> {
    if (disposed || !canMutate.value) return
    cancelOverview()
    cancelHistory()
    mutation.value = { kind, targetId, pending: true, outcome: 'idle', result: null, problem: null }
    let readBack = false
    try {
      const receipt = await write()
      if (disposed) return
      mutation.value = { ...mutation.value, outcome: 'success', result: receipt }
      // A deleted task's history has also been removed. Do not retain its former chart as current data.
      if (kind === 'delete' && historySelection.value?.taskId === targetId) closeHistory()
      readBack = true
    } catch (cause) {
      if (disposed) return
      const failure = networkQualityError(cause)
      mutation.value = { ...mutation.value, outcome: failure.writeAttempted ? 'unknown' : 'failed', problem: failure }
      if (failure.writeAttempted) {
        requiresReview.value = true
        reviewAfterRevision.value = readRevision.value + 1
        readBack = true
      }
    } finally {
      if (!disposed) {
        // Preserve the mutation receipt even if either independent read-back fails.
        if (readBack) {
          await loadOverview()
          if (!disposed && historySelection.value) await loadHistory(historySelection.value)
        }
        if (!disposed) mutation.value = { ...mutation.value, pending: false }
      }
    }
  }
  async function saveTask(input: NetworkQualityTaskInput, existingTask?: NetworkQualityTask): Promise<void> {
    // Clone before awaiting: the modal can never retarget a dispatched mutation.
    const snapshot = existingTask ? { ...existingTask, instanceIds: [...existingTask.instanceIds] } : null
    const draft = { ...input, instanceIds: Array.isArray(input.instanceIds) ? [...input.instanceIds] : input.instanceIds }
    await perform('save', snapshot?.id ?? '', async () => {
      const normalized = normalizeNetworkQualityTask(draft)
      if (snapshot) currentTask(snapshot)
      const task = snapshot ? await updateNetworkQualityTask(snapshot.id, snapshot.version, normalized)
        : await createNetworkQualityTask(normalized)
      return { kind: 'save', task }
    })
  }
  async function deleteTask(task: NetworkQualityTask): Promise<void> {
    const snapshot = { ...task }
    await perform('delete', snapshot.id, async () => {
      currentTask(snapshot)
      await deleteNetworkQualityTask(snapshot.id, snapshot.version)
      return { kind: 'delete', deleted: true }
    })
  }
  async function runTask(task: NetworkQualityTask, instanceIds?: string[]): Promise<void> {
    const snapshot = { ...task, instanceIds: [...task.instanceIds] }
    const targets = instanceIds ? [...instanceIds] : undefined
    await perform('run', snapshot.id, async () => {
      currentTask(snapshot)
      if (targets?.some(id => !snapshot.instanceIds.includes(id))) throw new NetworkQualityApiError('invalidInput')
      return { kind: 'run', receipt: await runNetworkQualityTask(snapshot.id, snapshot.version, targets) }
    })
  }
  async function installAgent(agent: NetworkQualityAgent): Promise<void> {
    const id = agent.id
    await perform('install', id, async () => {
      if (!agents.value.some(value => value.id === id)) throw new NetworkQualityApiError('notFound')
      return { kind: 'install', ...await installNetworkQualityAgent(id) }
    })
  }

  onBeforeUnmount(() => {
    disposed = true
    cancelOverview()
    closeHistory()
    overview.value = null
    mutation.value = emptyMutation()
  })
  return { overview, tasks, agents, latest, loading, loaded, problem, lastUpdated, refresh,
    mutation, contextLocked, canMutate, requiresReview, reviewReady, acknowledgeReview, clearMutation,
    saveTask, deleteTask, runTask, installAgent,
    historySelection, historyLoading, historyData, historyProblem, readHistory, refreshHistory, closeHistory }
}
