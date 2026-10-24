import { computed, onBeforeUnmount, ref, shallowRef } from 'vue'
import {
  MemoApiError, createMemo, deleteMemo, getMemo, isMemoId, isMemoRevision, listMemos,
  memoError, normalizeMemoInput, updateMemo, type MemoInput, type MemoRecord,
} from '@/api/memos'

export interface MemoMutation {
  kind: 'create' | 'update' | 'delete' | null
  targetId: string | null
  pending: boolean
  outcome: 'idle' | 'success' | 'unknown' | 'failed'
  result: MemoRecord | null
  problem: MemoApiError | null
}
function emptyMutation(): MemoMutation {
  return { kind: null, targetId: null, pending: false, outcome: 'idle', result: null, problem: null }
}

/** The page owns drafts, confirmation, navigation and the initial list read. */
export function useMemos() {
  const rows = shallowRef<MemoRecord[]>([]), loading = ref(false), loaded = ref(false)
  const problem = shallowRef<MemoApiError | null>(null), lastUpdated = ref<number | null>(null)
  const selectedId = ref<string | null>(null), detail = shallowRef<MemoRecord | null>(null)
  const detailLoading = ref(false), detailProblem = shallowRef<MemoApiError | null>(null)
  const detailExists = ref<boolean | null>(null)
  const mutation = shallowRef<MemoMutation>(emptyMutation())
  const requiresReview = ref(false), reviewTargetId = ref<string | null>(null)
  const listRevision = ref(0), detailRevision = ref(0)
  const reviewAfterList = ref(0), reviewAfterDetail = ref(0)
  const contextLocked = computed(() => mutation.value.pending)
  const canMutate = computed(() => loaded.value && !loading.value && !problem.value && !detailLoading.value
    && !contextLocked.value && !requiresReview.value)
  const reviewReady = computed(() => requiresReview.value && !contextLocked.value && loaded.value
    && !loading.value && !problem.value && listRevision.value >= reviewAfterList.value
    && (reviewTargetId.value === null || (selectedId.value === reviewTargetId.value && !detailLoading.value
      && detailRevision.value >= reviewAfterDetail.value
      && (detailExists.value === false || (detailExists.value === true && !detailProblem.value
        && detail.value?.id === reviewTargetId.value && isMemoRevision(detail.value.revision))))))
  let disposed = false, listSequence = 0, detailSequence = 0
  let listController: AbortController | undefined, detailController: AbortController | undefined

  function cancelList(): void {
    ++listSequence; listController?.abort(); listController = undefined; loading.value = false
  }
  function cancelDetail(): void {
    ++detailSequence; detailController?.abort(); detailController = undefined; detailLoading.value = false
  }
  async function loadList(): Promise<void> {
    if (disposed) return
    cancelList()
    const sequence = listSequence, controller = new AbortController()
    listController = controller; loading.value = true; problem.value = null
    const current = () => !disposed && sequence === listSequence && listController === controller && !controller.signal.aborted
    try {
      const result = await listMemos(controller.signal)
      if (current()) { rows.value = result; loaded.value = true; lastUpdated.value = Date.now(); ++listRevision.value }
    } catch (cause) { if (current()) problem.value = memoError(cause) }
    finally { if (current()) { loading.value = false; listController = undefined } }
  }
  async function loadDetail(memoId: string): Promise<void> {
    if (disposed) return
    cancelDetail()
    if (selectedId.value !== memoId) { detail.value = null; detailExists.value = null }
    selectedId.value = memoId; detailProblem.value = null
    if (!isMemoId(memoId)) {
      detail.value = null; detailExists.value = null; detailProblem.value = new MemoApiError('invalidInput'); return
    }
    const sequence = detailSequence, controller = new AbortController()
    detailController = controller; detailLoading.value = true
    const current = () => !disposed && sequence === detailSequence && detailController === controller
      && !controller.signal.aborted && selectedId.value === memoId
    try {
      const result = await getMemo(memoId, controller.signal)
      if (current()) { detail.value = result; detailExists.value = true; ++detailRevision.value }
    } catch (cause) {
      if (current()) {
        const failure = memoError(cause)
        detailProblem.value = failure
        if (failure.key === 'notFound') {
          detail.value = null; detailExists.value = false; ++detailRevision.value
        } else detailExists.value = null
      }
    } finally { if (current()) { detailLoading.value = false; detailController = undefined } }
  }
  async function refresh(): Promise<void> { if (!contextLocked.value) await loadList() }
  async function selectMemo(memoId: string): Promise<void> { if (!contextLocked.value) await loadDetail(memoId) }
  async function reloadDetail(): Promise<void> {
    if (!contextLocked.value && selectedId.value !== null) await loadDetail(selectedId.value)
  }
  function clearDetail(): void {
    if (contextLocked.value) return
    cancelDetail(); selectedId.value = null; detail.value = null; detailExists.value = null; detailProblem.value = null
  }
  function clearMutation(): void {
    // Closing feedback never clears an uncertain write's review requirement.
    if (!contextLocked.value && !requiresReview.value) mutation.value = emptyMutation()
  }
  function acknowledgeReview(): void {
    if (!reviewReady.value) return
    requiresReview.value = false; reviewTargetId.value = null; clearMutation()
  }
  function baselineRevision(record: MemoRecord): string {
    if (!record || !isMemoId(record.id) || !isMemoRevision(record.revision)) throw new MemoApiError('invalidInput')
    if (detailLoading.value || detailProblem.value || detailExists.value !== true || selectedId.value !== record.id
      || detail.value?.id !== record.id || detail.value.revision !== record.revision) throw new MemoApiError('conflict')
    return record.revision
  }
  function reject(kind: MemoMutation['kind'], targetId: string | null, cause: unknown): void {
    mutation.value = { ...emptyMutation(), kind, targetId, outcome: 'failed', problem: memoError(cause) }
  }
  async function perform(kind: Exclude<MemoMutation['kind'], null>, targetId: string | null,
    send: () => Promise<MemoRecord | null>): Promise<void> {
    if (disposed || !canMutate.value) return
    cancelList(); cancelDetail()
    mutation.value = { kind, targetId, pending: true, outcome: 'idle', result: null, problem: null }
    let readBack = false, readDetailId: string | null = null
    try {
      const result = await send()
      if (disposed) return
      mutation.value = { ...mutation.value, outcome: 'success', result }
      readBack = true
      if (result) {
        // The canonical receipt is usable immediately, but only guarded GET supplies
        // the next revision. A failed read-back must never enable another old write.
        selectedId.value = result.id; detail.value = result; detailExists.value = true; detailProblem.value = null
        rows.value = kind === 'create' ? [result, ...rows.value.filter(row => row.id !== result.id)]
          : rows.value.map(row => row.id === result.id ? result : row)
        readDetailId = result.id
      } else if (kind === 'delete') {
        rows.value = rows.value.filter(row => row.id !== targetId)
        if (selectedId.value === targetId) { detail.value = null; detailExists.value = false; detailProblem.value = null }
      }
    } catch (cause) {
      if (disposed) return
      const failure = memoError(cause)
      mutation.value = { ...mutation.value, outcome: failure.writeAttempted ? 'unknown' : 'failed', problem: failure }
      if (failure.writeAttempted) {
        requiresReview.value = true; reviewTargetId.value = targetId
        reviewAfterList.value = listRevision.value + 1; reviewAfterDetail.value = detailRevision.value + 1
        readBack = true; readDetailId = targetId
      } else if (targetId !== null && (failure.key === 'conflict' || failure.key === 'notFound')) {
        // Show the current saved version (or confirmed absence) beside the retained
        // draft after a guarded rejection. The failed write is never retried.
        readBack = true; readDetailId = targetId
      }
    } finally {
      if (!disposed) {
        if (readBack) {
          // Both loaders own their failures. A list/detail error cannot revoke a
          // confirmed write or manufacture a successful receipt for an unknown one.
          await Promise.all([loadList(), readDetailId === null ? Promise.resolve() : loadDetail(readDetailId)])
        }
        if (!disposed) mutation.value = { ...mutation.value, pending: false }
      }
    }
  }
  async function save(input: MemoInput, baseline?: MemoRecord): Promise<void> {
    if (disposed || !canMutate.value) return
    const kind = baseline ? 'update' : 'create', targetId = baseline?.id ?? null
    let snapshot: MemoInput, revision: string | null = null
    try { snapshot = normalizeMemoInput({ ...input }); if (baseline) revision = baselineRevision(baseline) }
    catch (cause) { reject(kind, targetId, cause); return }
    await perform(kind, targetId, () => targetId !== null && revision !== null
      ? updateMemo(targetId, snapshot, revision) : createMemo(snapshot))
  }
  async function remove(record: MemoRecord): Promise<void> {
    if (disposed || !canMutate.value) return
    let revision: string
    try { revision = baselineRevision(record) }
    catch (cause) { reject('delete', record?.id ?? null, cause); return }
    const targetId = record.id
    await perform('delete', targetId, async () => { await deleteMemo(targetId, revision); return null })
  }
  onBeforeUnmount(() => {
    disposed = true; cancelList(); cancelDetail()
    rows.value = []; detail.value = null; selectedId.value = null; mutation.value = emptyMutation()
  })
  return { rows, loading, loaded, problem, lastUpdated, refresh, selectedId, detail, detailLoading, detailProblem,
    detailExists, selectMemo, reloadDetail, clearDetail, mutation, canMutate, contextLocked, requiresReview,
    reviewReady, reviewTargetId, acknowledgeReview, clearMutation, save, remove }
}
