import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute } from 'vue-router'
import {
  VpsApiError, fetchVpsInstances, isVpsLocalId, runVpsOperation, vpsError,
  type VpsMutationResult, type VpsOperationKind, type VpsRow,
} from '@/api/vps'

export interface VpsOperation { kind: VpsOperationKind; row: VpsRow | null }

/** Resource inventory reads are explicit; the live metrics stream is owned separately. */
export function useVpsPage() {
  const route = useRoute()
  const tenantId = computed(() => typeof route.query.tenantId === 'string' ? route.query.tenantId : '')
  const contextValid = computed(() => route.query.tenantId == null
    || (typeof route.query.tenantId === 'string' && (!tenantId.value || isVpsLocalId(tenantId.value))))
  const scope = computed(() => JSON.stringify(route.query.tenantId ?? ''))
  const rows = shallowRef<VpsRow[]>([])
  const loading = ref(false)
  const loaded = ref(false)
  const readProblem = shallowRef<VpsApiError | null>(null)
  const lastUpdated = ref<Date | null>(null)
  const snapshotScope = ref('')
  const operation = shallowRef<VpsOperation | null>(null)
  const operationPending = ref(false)
  const operationOutcome = ref<'idle' | 'success' | 'unknown' | 'failed'>('idle')
  const operationResult = shallowRef<VpsMutationResult | null>(null)
  const operationProblem = shallowRef<VpsApiError | null>(null)
  const requiresReview = ref(false)
  const reviewTenantId = ref('')
  const reviewScope = ref('')
  const readRevision = ref(0)
  const reviewAfterRevision = ref(0)
  const contextLocked = computed(() => !!operation.value || operationPending.value)
  const canDismissOperation = computed(() => !operationPending.value)
  const canOperate = computed(() => contextValid.value && loaded.value && !loading.value && !readProblem.value
    && snapshotScope.value === scope.value && !contextLocked.value && !requiresReview.value)
  const reviewReady = computed(() => requiresReview.value && contextValid.value && loaded.value
    && !loading.value && !readProblem.value && snapshotScope.value === scope.value
    && scope.value === reviewScope.value && readRevision.value >= reviewAfterRevision.value)

  let mounted = false
  let disposed = false
  let sequence = 0
  let controller: AbortController | undefined

  function cancelRead(): void {
    ++sequence
    controller?.abort()
    controller = undefined
    loading.value = false
  }
  async function readRecords(): Promise<void> {
    if (!mounted || disposed || operationPending.value) return
    cancelRead()
    if (!contextValid.value) {
      readProblem.value = new VpsApiError('invalidInput')
      return
    }
    const current = sequence
    const targetScope = scope.value
    const targetTenant = tenantId.value
    const active = new AbortController()
    controller = active
    loading.value = true
    readProblem.value = null
    const isCurrent = () => !disposed && current === sequence && controller === active
      && !active.signal.aborted && targetScope === scope.value
    try {
      const result = await fetchVpsInstances(targetTenant, active.signal)
      if (!isCurrent()) return
      rows.value = result
      loaded.value = true
      snapshotScope.value = targetScope
      lastUpdated.value = new Date()
      ++readRevision.value
    } catch (cause) {
      if (isCurrent()) readProblem.value = vpsError(cause)
    } finally {
      if (isCurrent()) { controller = undefined; loading.value = false }
    }
  }
  async function read(): Promise<void> {
    if (contextLocked.value) return
    await readRecords()
  }
  const refresh = read

  function openOperation(kind: VpsOperationKind, row?: VpsRow): void {
    if (disposed || !canOperate.value) return
    if (!['install', 'uninstall', 'enablePing', 'disablePing', 'ping'].includes(kind)) return
    let target: VpsRow | null = null
    if (kind === 'install' || kind === 'uninstall') {
      const current = row ? rows.value.find(value => value.id === row.id) : null
      if (!current || !isVpsLocalId(current.id)) return
      target = { ...current }
    }
    cancelRead()
    operation.value = { kind, row: target }
    operationOutcome.value = 'idle'
    operationResult.value = null
    operationProblem.value = null
  }
  function closeOperation(): void {
    if (operationPending.value) return
    operation.value = null
    operationOutcome.value = 'idle'
    operationResult.value = null
    operationProblem.value = null
  }
  async function submitOperation(): Promise<void> {
    const target = operation.value
    if (disposed || !target || operationPending.value || requiresReview.value
      || operationOutcome.value === 'success' || operationOutcome.value === 'unknown') return
    const targetScope = scope.value
    const targetTenant = tenantId.value
    operationPending.value = true
    operationProblem.value = null
    operationResult.value = null
    cancelRead()
    let attempted = false
    try {
      const result = await runVpsOperation(target.kind, target.row?.id)
      attempted = true
      if (disposed) return
      operationResult.value = result
      operationOutcome.value = 'success'
    } catch (cause) {
      if (disposed) return
      const problem = vpsError(cause)
      attempted = problem.writeAttempted
      operationProblem.value = problem
      operationOutcome.value = attempted ? 'unknown' : 'failed'
      if (attempted) {
        requiresReview.value = true
        reviewTenantId.value = targetTenant
        reviewScope.value = targetScope
        reviewAfterRevision.value = readRevision.value + 1
      }
    } finally {
      if (!disposed) {
        operationPending.value = false
        // Preserve the command receipt even if the inventory read-back fails.
        if (attempted && targetScope === scope.value) await readRecords()
      }
    }
  }
  function acknowledgeReview(): void {
    if (contextLocked.value || !reviewReady.value) return
    requiresReview.value = false
    reviewTenantId.value = ''
    reviewScope.value = ''
    reviewAfterRevision.value = 0
  }
  function beforeUnload(event: BeforeUnloadEvent): void {
    if (!operationPending.value) return
    event.preventDefault()
    event.returnValue = ''
  }

  watch(scope, () => {
    cancelRead()
    rows.value = []
    loaded.value = false
    snapshotScope.value = ''
    lastUpdated.value = null
    readProblem.value = null
    if (mounted && !disposed) void readRecords()
  }, { flush: 'sync' })
  onBeforeRouteLeave(() => !contextLocked.value)
  onBeforeRouteUpdate(() => !contextLocked.value)
  onMounted(() => {
    mounted = true
    void read()
    window.addEventListener('beforeunload', beforeUnload)
  })
  onBeforeUnmount(() => {
    disposed = true
    mounted = false
    cancelRead()
    rows.value = []
    operation.value = null
    window.removeEventListener('beforeunload', beforeUnload)
    // A submitted command is not aborted; detached callbacks cannot publish UI state.
  })

  return {
    rows, loading, loaded, readProblem, lastUpdated, tenantId, contextValid, read, refresh,
    operation, operationPending, operationOutcome, operationResult, operationProblem,
    openOperation, submitOperation, closeOperation, canDismissOperation, contextLocked, canOperate,
    requiresReview, reviewTenantId, reviewReady, acknowledgeReview,
  }
}
