import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from 'vue'
import {
  VpnProxyApiError, collectVpnProxyRecords, deleteVpnProxy, fetchVpnProxyPage, fetchVpnProxyPassword,
  fetchVpnProxyTenants, normalizeVpnProxyInput, saveVpnProxy, setVpnProxyForce, testVpnProxy, vpnProxyError,
  type VpnProxyInput, type VpnProxyRecord, type VpnProxyTenant, type VpnProxyTestResult,
} from '@/api/vpnProxy'

export type VpnProxyOperationKind = 'create' | 'edit' | 'delete' | 'force' | 'test' | 'testAll'
export interface VpnProxyOperation { kind: VpnProxyOperationKind; row: VpnProxyRecord | null; nextForce?: 0 | 1 }
export interface VpnProxyMutation {
  pending: boolean; outcome: 'idle' | 'success' | 'unknown' | 'failed'; problem: VpnProxyApiError | null
  result: { kind: VpnProxyOperationKind; test: VpnProxyTestResult | null } | null
}
export interface VpnProxyBatchEntry {
  id: string; customName: string; proxyType: string; proxyHost: string; proxyPort: number | null
  status: 'queued' | 'testing' | 'connected' | 'disconnected' | 'unknown' | 'skipped'
  result: VpnProxyTestResult | null; problem: VpnProxyApiError | null
}
export interface VpnProxyBatch {
  state: 'idle' | 'preparing' | 'running' | 'completed' | 'stopped'; stopRequested: boolean
  total: number; completed: number; connected: number; disconnected: number; unknown: number; skipped: number
  currentId: string | null; entries: VpnProxyBatchEntry[]
}
function emptyMutation(): VpnProxyMutation { return { pending: false, outcome: 'idle', problem: null, result: null } }
function emptyBatch(): VpnProxyBatch {
  return { state: 'idle', stopRequested: false, total: 0, completed: 0, connected: 0, disconnected: 0,
    unknown: 0, skipped: 0, currentId: null, entries: [] }
}
function clone(row: VpnProxyRecord): VpnProxyRecord { return { ...row, tenantIds: [...row.tenantIds] } }

/** No automatic reads or navigation guards: the page owns mounting and confirmations. */
export function useVpnProxy() {
  const rows = shallowRef<VpnProxyRecord[]>([])
  const page = ref(1), size = ref(10), total = ref(0), totalPages = ref(0)
  const loading = ref(false), loaded = ref(false), lastUpdated = ref<number | null>(null)
  const problem = shallowRef<VpnProxyApiError | null>(null)
  const parents = shallowRef<VpnProxyTenant[]>([])
  const parentsLoading = ref(false), parentsLoaded = ref(false)
  const parentsProblem = shallowRef<VpnProxyApiError | null>(null)
  const operation = shallowRef<VpnProxyOperation | null>(null)
  const mutation = shallowRef<VpnProxyMutation>(emptyMutation())
  const batch = ref<VpnProxyBatch>(emptyBatch())
  const requiresReview = ref(false)
  const readRevision = ref(0), reviewAfterRevision = ref(0)
  const passwordTarget = shallowRef<VpnProxyRecord | null>(null)
  const password = ref<string | null>(null), passwordLoading = ref(false)
  const passwordProblem = shallowRef<VpnProxyApiError | null>(null)
  const contextLocked = computed(() => !!operation.value || !!passwordTarget.value || mutation.value.pending)
  const canOperate = computed(() => loaded.value && !loading.value && !problem.value && !requiresReview.value && !contextLocked.value)
  const canSubmit = computed(() => !!operation.value && !mutation.value.pending && !requiresReview.value
    && ['idle', 'failed'].includes(mutation.value.outcome)
    && (!['create', 'edit'].includes(operation.value.kind) || (parentsLoaded.value && !parentsLoading.value && !parentsProblem.value)))
  const reviewReady = computed(() => requiresReview.value && !loading.value && !problem.value && loaded.value
    && !contextLocked.value && readRevision.value >= reviewAfterRevision.value)
  let disposed = false
  let readSequence = 0, parentsSequence = 0, passwordSequence = 0
  let readController: AbortController | undefined, parentsController: AbortController | undefined
  let passwordController: AbortController | undefined, collectionController: AbortController | undefined
  let pendingInput: VpnProxyInput | undefined

  function cancelRead(): void { ++readSequence; readController?.abort(); readController = undefined; loading.value = false }
  async function load(targetPage: number, targetSize: number): Promise<void> {
    if (disposed) return
    cancelRead()
    const sequence = readSequence, controller = new AbortController()
    readController = controller; loading.value = true; problem.value = null
    const current = () => !disposed && sequence === readSequence && readController === controller && !controller.signal.aborted
    try {
      let result = await fetchVpnProxyPage(targetPage, targetSize, controller.signal)
      if (!current()) return
      // Deleting the last row may remove the current page. Correct at most once.
      if (targetPage > Math.max(1, result.totalPages)) {
        result = await fetchVpnProxyPage(Math.max(1, result.totalPages), targetSize, controller.signal)
        if (!current()) return
        if (result.page > Math.max(1, result.totalPages)) throw new VpnProxyApiError('invalidResponse')
      }
      rows.value = result.records; page.value = result.page; size.value = result.size
      total.value = result.total; totalPages.value = result.totalPages
      loaded.value = true; lastUpdated.value = Date.now(); ++readRevision.value
    } catch (cause) { if (current()) problem.value = vpnProxyError(cause) }
    finally { if (current()) { loading.value = false; readController = undefined } }
  }
  async function refresh(): Promise<void> { if (!contextLocked.value) await load(page.value, size.value) }
  async function changePage(value: number): Promise<void> { if (!contextLocked.value) await load(value, size.value) }
  async function changeSize(value: number): Promise<void> { if (!contextLocked.value) await load(1, value) }
  async function loadParents(): Promise<void> {
    if (disposed || mutation.value.pending) return
    ++parentsSequence; parentsController?.abort()
    const sequence = parentsSequence, controller = new AbortController()
    parentsController = controller; parentsLoading.value = true; parentsProblem.value = null
    const current = () => !disposed && sequence === parentsSequence && parentsController === controller && !controller.signal.aborted
    try {
      const result = await fetchVpnProxyTenants(controller.signal)
      if (current()) { parents.value = result; parentsLoaded.value = true }
    } catch (cause) { if (current()) parentsProblem.value = vpnProxyError(cause) }
    finally { if (current()) { parentsLoading.value = false; parentsController = undefined } }
  }
  function openOperation(kind: VpnProxyOperationKind, row?: VpnProxyRecord, nextForce?: 0 | 1): void {
    if (!canOperate.value) return
    const found = row ? rows.value.find(item => item.id === row.id) : undefined
    if (!['create', 'testAll'].includes(kind) && !found) return
    if (kind === 'force' && nextForce !== 0 && nextForce !== 1) return
    cancelRead(); closePassword()
    mutation.value = emptyMutation(); batch.value = emptyBatch()
    operation.value = { kind, row: found ? clone(found) : null, ...(kind === 'force' ? { nextForce } : {}) }
  }
  function closeOperation(): void { if (!mutation.value.pending) operation.value = null }
  function markUnknown(): void {
    requiresReview.value = true
    reviewAfterRevision.value = readRevision.value + 1
  }
  function acknowledgeReview(): void {
    if (!reviewReady.value) return
    requiresReview.value = false; mutation.value = emptyMutation()
  }
  function updateTestedRow(result: VpnProxyTestResult): void {
    if (result.connected === null) return
    rows.value = rows.value.map(row => row.id === result.id ? { ...row, availableStatus: result.availableStatus } : row)
  }
  function stopBatch(): void {
    if (!mutation.value.pending || !['preparing', 'running'].includes(batch.value.state)) return
    batch.value.stopRequested = true
    // Only the collection is abortable. An already submitted probe must settle.
    if (batch.value.state === 'preparing') collectionController?.abort()
  }
  async function runBatch(): Promise<boolean> {
    batch.value = { ...emptyBatch(), state: 'preparing' }
    const controller = new AbortController()
    collectionController = controller
    let collection: VpnProxyRecord[]
    try { collection = await collectVpnProxyRecords(controller.signal) }
    catch (cause) {
      if (!disposed && batch.value.stopRequested && controller.signal.aborted) {
        batch.value.state = 'stopped'
        return false
      }
      if (!disposed) batch.value.state = 'idle'
      throw cause
    } finally { if (collectionController === controller) collectionController = undefined }
    if (disposed) return false
    batch.value.total = collection.length
    batch.value.entries = collection.map(row => ({ id: row.id, customName: row.customName, proxyType: row.proxyType,
      proxyHost: row.proxyHost, proxyPort: row.proxyPort, status: 'queued', result: null, problem: null }))
    batch.value.state = 'running'
    let attempted = false
    for (let index = 0; index < batch.value.entries.length; index += 1) {
      if (disposed || batch.value.stopRequested) break
      const entry = batch.value.entries[index]!
      entry.status = 'testing'; batch.value.currentId = entry.id; attempted = true
      try {
        const result = await testVpnProxy(entry.id)
        if (disposed) return attempted
        entry.result = result
        entry.proxyType = result.proxyType; entry.proxyHost = result.proxyHost; entry.proxyPort = result.proxyPort
        if (result.connected === null) {
          entry.status = 'unknown'; entry.problem = new VpnProxyApiError('configurationChanged', '', true)
          ++batch.value.unknown
        } else if (result.connected) { entry.status = 'connected'; ++batch.value.connected }
        else { entry.status = 'disconnected'; ++batch.value.disconnected }
        updateTestedRow(result)
      } catch (cause) {
        if (disposed) return attempted
        entry.status = 'unknown'; entry.problem = vpnProxyError(cause); ++batch.value.unknown
      }
      ++batch.value.completed
    }
    if (disposed) return attempted
    for (const entry of batch.value.entries) {
      if (entry.status === 'queued') { entry.status = 'skipped'; ++batch.value.skipped }
    }
    batch.value.currentId = null
    batch.value.state = batch.value.stopRequested ? 'stopped' : 'completed'
    return attempted
  }
  function inputMatches(input: VpnProxyInput, row: VpnProxyRecord): boolean {
    return row.customName === input.customName && row.proxyType === input.proxyType && row.proxyHost === input.proxyHost
      && row.proxyPort === input.proxyPort && row.proxyUsername === input.proxyUsername
      && row.availableStatus === input.availableStatus && row.forceProxy === input.forceProxy
      && row.tenantIds.length === input.tenantIds.length && input.tenantIds.every(id => row.tenantIds.includes(id))
      && (input.proxyPassword === undefined || row.hasPassword === (input.proxyPassword !== ''))
  }
  async function submitOperation(input?: VpnProxyInput): Promise<void> {
    if (disposed || !canSubmit.value || !operation.value) return
    const target = operation.value
    const snapshot = target.row ? clone(target.row) : undefined
    let normalized: VpnProxyInput | undefined
    try {
      if (target.kind === 'create' || target.kind === 'edit') {
        if (!input) throw new VpnProxyApiError('invalidInput')
        normalized = normalizeVpnProxyInput({ ...input, id: target.kind === 'edit' ? snapshot?.id : undefined,
          tenantIds: [...input.tenantIds] }, snapshot)
      }
    } catch (cause) { mutation.value = { ...emptyMutation(), outcome: 'failed', problem: vpnProxyError(cause) }; return }
    pendingInput = normalized
    cancelRead(); closePassword()
    mutation.value = { ...emptyMutation(), pending: true }
    let readBack = false
    let result: VpnProxyTestResult | null = null
    let expected: VpnProxyInput | undefined
    let expectedPassword: boolean | undefined
    try {
      if (target.kind === 'testAll') {
        readBack = await runBatch()
        if (disposed) return
        if (batch.value.unknown > 0) markUnknown()
      } else if (target.kind === 'create' || target.kind === 'edit') {
        if (!normalized) throw new VpnProxyApiError('invalidInput')
        expectedPassword = normalized.proxyPassword === undefined ? undefined : normalized.proxyPassword !== ''
        expected = { ...normalized, proxyPassword: undefined, tenantIds: [...normalized.tenantIds] }
        await saveVpnProxy(normalized, snapshot); readBack = true
      } else if (target.kind === 'delete') { await deleteVpnProxy(snapshot!.id); readBack = true }
      else if (target.kind === 'force') { await setVpnProxyForce(snapshot!.id, target.nextForce!); readBack = true }
      else {
        result = await testVpnProxy(snapshot!.id); readBack = true
        if (!disposed) {
          updateTestedRow(result)
          if (result.connected === null) markUnknown()
        }
      }
      if (disposed) return
      mutation.value = { pending: true, outcome: requiresReview.value ? 'unknown' : 'success',
        result: { kind: target.kind, test: result }, problem: result?.errorKey ? new VpnProxyApiError(result.errorKey, '', true) : null }
    } catch (cause) {
      if (disposed) return
      const failure = vpnProxyError(cause)
      if (failure.writeAttempted) { markUnknown(); readBack = true }
      mutation.value = { pending: true, outcome: failure.writeAttempted ? 'unknown' : 'failed', problem: failure, result: null }
    } finally {
      if (normalized) normalized.proxyPassword = undefined
      pendingInput = undefined
      if (!disposed) {
        if (readBack) {
          await load(target.kind === 'create' ? 1 : page.value, size.value)
          if (!disposed && !problem.value && mutation.value.outcome === 'success') {
            const current = snapshot ? rows.value.find(row => row.id === snapshot.id) : undefined
            if ((expected && current && (!inputMatches(expected, current)
                || (expectedPassword !== undefined && current.hasPassword !== expectedPassword)))
              || (target.kind === 'force' && current && current.forceProxy !== target.nextForce)
              || (target.kind === 'delete' && current)) problem.value = new VpnProxyApiError('saveMismatch')
          }
        }
        if (!disposed) mutation.value = { ...mutation.value, pending: false }
      }
    }
  }
  function closePassword(): void {
    ++passwordSequence; passwordController?.abort(); passwordController = undefined
    password.value = null; passwordTarget.value = null; passwordLoading.value = false; passwordProblem.value = null
  }
  async function revealPassword(row: VpnProxyRecord): Promise<void> {
    if (disposed || contextLocked.value || !loaded.value || loading.value || problem.value) return
    const found = rows.value.find(item => item.id === row.id)
    if (!found) return
    closePassword()
    const sequence = passwordSequence, controller = new AbortController()
    passwordTarget.value = clone(found); passwordController = controller; passwordLoading.value = true
    const current = () => !disposed && sequence === passwordSequence && passwordController === controller && !controller.signal.aborted
    try { const result = await fetchVpnProxyPassword(found.id, controller.signal); if (current()) password.value = result }
    catch (cause) { if (current()) passwordProblem.value = vpnProxyError(cause) }
    finally { if (current()) { passwordLoading.value = false; passwordController = undefined } }
  }
  function hidePassword(): void { if (document.hidden) closePassword() }
  onMounted(() => document.addEventListener('visibilitychange', hidePassword))
  onBeforeUnmount(() => {
    disposed = true
    cancelRead(); ++parentsSequence; parentsController?.abort(); collectionController?.abort(); closePassword()
    if (pendingInput) pendingInput.proxyPassword = undefined
    pendingInput = undefined
    rows.value = []; parents.value = []; operation.value = null; batch.value = emptyBatch()
    document.removeEventListener('visibilitychange', hidePassword)
  })
  return { rows, page, size, total, totalPages, loading, loaded, problem, lastUpdated, refresh, changePage, changeSize,
    parents, parentsLoading, parentsLoaded, parentsProblem, loadParents, operation, mutation, openOperation, submitOperation, closeOperation,
    canOperate, canSubmit, contextLocked, requiresReview, reviewReady, acknowledgeReview, batch, stopBatch,
    passwordTarget, password, passwordLoading, passwordProblem, revealPassword, closePassword }
}
