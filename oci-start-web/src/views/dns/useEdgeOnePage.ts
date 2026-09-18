import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch, type Ref } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useCompactViewport } from '@/composables/useCompactViewport'
import {
  EdgeOneApiError, deleteEdgeOneDomain, deleteEdgeOneRecord, edgeOneCanEdit, edgeOneError,
  fetchEdgeOneRecords, fetchEdgeOneZones, isEdgeOneZoneId, syncEdgeOneRecords, updateEdgeOneRecord,
  type EdgeOneMode, type EdgeOneMutationResult, type EdgeOneRecord,
  type EdgeOneRecordInput, type EdgeOneZone,
} from '@/api/edgeone'

export interface EdgeOneOperation {
  kind: 'edit' | 'delete' | 'sync'
  mode: EdgeOneMode
  zone: EdgeOneZone
  record: EdgeOneRecord | null
}
interface Filters { searchName: string; searchContent: string; searchStatus: string }
interface ViewRequest { page: number; size: number; filters: Filters }
const PAGE_SIZES = [10, 20, 30, 50]
function emptyFilters(): Filters { return { searchName: '', searchContent: '', searchStatus: '' } }

/** Each scope has one complete cloud collection; page controls perform no writes or reads. */
export function useEdgeOnePage(credentialsOpen: Ref<boolean>) {
  const route = useRoute()
  const router = useRouter()
  const compact = useCompactViewport()
  const zones = ref<EdgeOneZone[]>([])
  const zonesLoading = ref(false)
  const zonesLoaded = ref(false)
  const zonesProblem = shallowRef<EdgeOneApiError | null>(null)
  const zoneId = ref('')
  const mode = ref<EdgeOneMode>('dns')
  const selectedZone = computed(() => zones.value.find(zone => zone.id === zoneId.value) || null)
  const zoneUnavailable = computed(() => !!zoneId.value && (!isEdgeOneZoneId(zoneId.value)
    || (zonesLoaded.value && !zonesLoading.value && !selectedZone.value)))
  const allRows = shallowRef<EdgeOneRecord[]>([])
  const loading = ref(false)
  const loaded = ref(false)
  const readProblem = shallowRef<EdgeOneApiError | null>(null)
  const page = ref(1)
  const size = ref(20)
  const searchName = ref('')
  const searchContent = ref('')
  const searchStatus = ref('')
  const appliedFilters = shallowRef<Filters>(emptyFilters())
  const lastUpdated = ref<Date | null>(null)
  const scope = computed(() => JSON.stringify([zoneId.value, mode.value]))
  const snapshotScope = ref('')
  const filtered = computed(() => {
    if (snapshotScope.value !== scope.value) return []
    const filters = appliedFilters.value
    const name = filters.searchName.toLowerCase()
    const content = filters.searchContent.toLowerCase()
    return allRows.value.filter(row => (!name || row.name.toLowerCase().includes(name))
      && (mode.value === 'dns'
        ? (!content || row.content.toLowerCase().includes(content))
        : (!filters.searchStatus || row.status === filters.searchStatus)))
  })
  const total = computed(() => filtered.value.length)
  const totalPages = computed(() => Math.ceil(total.value / size.value))
  const records = computed(() => filtered.value.slice((page.value - 1) * size.value, page.value * size.value))

  const operation = shallowRef<EdgeOneOperation | null>(null)
  const operationPending = ref(false)
  const operationOutcome = ref<'idle' | 'success' | 'unknown' | 'failed'>('idle')
  const operationResult = shallowRef<EdgeOneMutationResult | null>(null)
  const operationProblem = shallowRef<EdgeOneApiError | null>(null)
  const requiresReview = ref(false)
  const reviewZoneId = ref('')
  const reviewZone = shallowRef<EdgeOneZone | null>(null)
  const reviewMode = ref<EdgeOneMode | null>(null)
  const readRevision = ref(0)
  const reviewAfterRevision = ref(0)
  const contextLocked = computed(() => credentialsOpen.value || !!operation.value || operationPending.value)
  const canDismissOperation = computed(() => !operationPending.value)
  const canOperate = computed(() => !!selectedZone.value && zonesLoaded.value && !zonesLoading.value
    && !zonesProblem.value && loaded.value && !loading.value && !readProblem.value
    && snapshotScope.value === scope.value && !contextLocked.value && !requiresReview.value)
  const reviewReady = computed(() => requiresReview.value && !loading.value && !zonesLoading.value
    && !readProblem.value && !zonesProblem.value && !!selectedZone.value
    && zoneId.value === reviewZoneId.value && mode.value === reviewMode.value
    && snapshotScope.value === scope.value && readRevision.value >= reviewAfterRevision.value)

  let mounted = false
  let disposed = false
  let zonesSequence = 0
  let recordsSequence = 0
  let zonesController: AbortController | undefined
  let recordsController: AbortController | undefined
  let autoSelectFirst = true
  let requested: ViewRequest = { page: 1, size: 20, filters: emptyFilters() }
  let resumeZones = false
  let resumeRecords = false

  function cancelZones(): void {
    ++zonesSequence
    zonesController?.abort()
    zonesController = undefined
    zonesLoading.value = false
  }
  function cancelRecords(): void {
    ++recordsSequence
    recordsController?.abort()
    recordsController = undefined
    loading.value = false
  }
  function clearRecords(): void {
    cancelRecords()
    allRows.value = []
    loaded.value = false
    readProblem.value = null
    snapshotScope.value = ''
    lastUpdated.value = null
    page.value = 1
    size.value = 20
    appliedFilters.value = emptyFilters()
  }
  function publishView(): void {
    appliedFilters.value = { ...requested.filters }
    size.value = requested.size
    page.value = Math.min(requested.page, Math.max(1, totalPages.value))
    requested = { ...requested, page: page.value }
  }
  function resetView(): void {
    searchName.value = searchContent.value = searchStatus.value = ''
    requested = { page: 1, size: 20, filters: emptyFilters() }
    clearRecords()
  }

  async function readRecords(): Promise<void> {
    if (!mounted || disposed || operationPending.value || credentialsOpen.value || zonesLoading.value || !selectedZone.value) return
    cancelRecords()
    const current = recordsSequence
    const targetScope = scope.value
    const targetZone = zoneId.value
    const targetMode = mode.value
    const active = new AbortController()
    recordsController = active
    loading.value = true
    readProblem.value = null
    const isCurrent = () => !disposed && current === recordsSequence && !active.signal.aborted
      && recordsController === active && targetScope === scope.value
    try {
      const result = await fetchEdgeOneRecords(targetZone, targetMode, active.signal)
      if (!isCurrent()) return
      allRows.value = result
      loaded.value = true
      snapshotScope.value = targetScope
      lastUpdated.value = new Date()
      ++readRevision.value
      publishView()
    } catch (cause) {
      if (isCurrent()) readProblem.value = edgeOneError(cause)
    } finally {
      if (isCurrent()) { recordsController = undefined; loading.value = false }
    }
  }
  async function loadZones(): Promise<void> {
    if (!mounted || disposed || contextLocked.value || zonesLoading.value) return
    cancelZones()
    cancelRecords()
    const current = zonesSequence
    const active = new AbortController()
    zonesController = active
    zonesLoading.value = true
    zonesProblem.value = null
    let accepted = false
    try {
      const result = await fetchEdgeOneZones(active.signal)
      if (disposed || current !== zonesSequence || active.signal.aborted) return
      zones.value = result
      zonesLoaded.value = true
      accepted = true
      if (autoSelectFirst && !zoneId.value && result.length) {
        zoneId.value = result[0]!.id
        clearRecords()
      }
      // An explicit missing deep-link never silently becomes another write target.
      if (!selectedZone.value && zoneId.value) clearRecords()
    } catch (cause) {
      if (!disposed && current === zonesSequence && !active.signal.aborted) zonesProblem.value = edgeOneError(cause)
    } finally {
      if (!disposed && current === zonesSequence) { zonesController = undefined; zonesLoading.value = false }
    }
    if (accepted && !disposed && current === zonesSequence && selectedZone.value) await readRecords()
  }
  async function refresh(): Promise<void> {
    if (contextLocked.value) return
    await readRecords()
  }
  function selectZone(value: string): void {
    if (disposed || contextLocked.value || value === zoneId.value) return
    if (value !== '' && (!isEdgeOneZoneId(value) || !zones.value.some(zone => zone.id === value))) return
    autoSelectFirst = false
    zoneId.value = value
    resetView()
    if (value) void readRecords()
  }
  function selectMode(value: EdgeOneMode): void {
    if (disposed || contextLocked.value || value === mode.value || (value !== 'dns' && value !== 'domain')) return
    mode.value = value
    resetView()
    void readRecords()
  }
  function applySearch(): void {
    if (contextLocked.value || loading.value) return
    requested = { page: 1, size: size.value, filters: {
      searchName: searchName.value.trim(),
      searchContent: mode.value === 'dns' ? searchContent.value.trim() : '',
      searchStatus: mode.value === 'domain' ? searchStatus.value : '',
    } }
    if (loaded.value && snapshotScope.value === scope.value) publishView()
  }
  function clearSearch(): void {
    if (contextLocked.value || loading.value) return
    searchName.value = searchContent.value = searchStatus.value = ''
    applySearch()
  }
  function changePage(value: number): void {
    if (contextLocked.value || loading.value || !loaded.value || !Number.isSafeInteger(value)
      || value < 1 || value > Math.max(1, totalPages.value)) return
    requested = { page: value, size: size.value, filters: { ...appliedFilters.value } }
    publishView()
  }
  function changeSize(value: number): void {
    if (contextLocked.value || loading.value || !loaded.value || !PAGE_SIZES.includes(value)) return
    requested = { page: 1, size: value, filters: { ...appliedFilters.value } }
    publishView()
  }

  function openOperation(kind: EdgeOneOperation['kind'], row?: EdgeOneRecord): void {
    if (!canOperate.value || !selectedZone.value) return
    let record: EdgeOneRecord | null = null
    if (kind !== 'sync') {
      const current = row ? allRows.value.find(value => value.id === row.id) : null
      if (!current || (kind === 'edit' && (mode.value !== 'dns' || !edgeOneCanEdit(current.type)))) return
      record = { ...current }
    }
    cancelRecords()
    operation.value = { kind, mode: mode.value, zone: { ...selectedZone.value }, record }
    operationOutcome.value = 'idle'
    operationResult.value = null
    operationProblem.value = null
  }
  function openEdit(row: EdgeOneRecord): void { openOperation('edit', row) }
  function openDelete(row: EdgeOneRecord): void { openOperation('delete', row) }
  function openSync(): void { openOperation('sync') }
  function closeOperation(): void {
    if (operationPending.value) return
    operation.value = null
    operationOutcome.value = 'idle'
    operationResult.value = null
    operationProblem.value = null
  }
  async function submitOperation(input?: EdgeOneRecordInput): Promise<void> {
    const target = operation.value
    if (disposed || !target || operationPending.value || credentialsOpen.value || requiresReview.value
      || operationOutcome.value === 'success' || operationOutcome.value === 'unknown') return
    operationPending.value = true
    operationProblem.value = null
    operationResult.value = null
    cancelRecords()
    let attempted = false
    try {
      let result: EdgeOneMutationResult
      if (target.kind === 'edit') {
        if (!input || !target.record || target.mode !== 'dns') throw new EdgeOneApiError('recordRequired')
        result = await updateEdgeOneRecord(target.zone.id, target.record.id, {
          ...input, type: target.record.type, name: target.record.name,
        })
      } else if (target.kind === 'delete') {
        if (!target.record) throw new EdgeOneApiError('invalidInput')
        result = target.mode === 'dns'
          ? await deleteEdgeOneRecord(target.zone.id, target.record.id)
          : await deleteEdgeOneDomain(target.zone.id, target.record.id, target.record.name)
      } else result = await syncEdgeOneRecords(target.zone.id, target.zone.name, target.mode)
      attempted = true
      if (disposed) return
      operationResult.value = result
      operationOutcome.value = 'success'
    } catch (cause) {
      if (disposed) return
      const problem = edgeOneError(cause)
      attempted = problem.writeAttempted
      operationProblem.value = problem
      operationOutcome.value = attempted ? 'unknown' : 'failed'
      if (attempted) {
        requiresReview.value = true
        reviewZoneId.value = target.zone.id
        reviewZone.value = { ...target.zone }
        reviewMode.value = target.mode
        reviewAfterRevision.value = readRevision.value + 1
      }
    } finally {
      if (!disposed) {
        operationPending.value = false
        // A read-back failure never invalidates a successful mutation receipt.
        if (attempted && target.zone.id === zoneId.value && target.mode === mode.value) await readRecords()
      }
    }
  }
  function acknowledgeReview(): void {
    if (contextLocked.value || !reviewReady.value) return
    requiresReview.value = false
    reviewZoneId.value = ''
    reviewZone.value = null
    reviewMode.value = null
    reviewAfterRevision.value = 0
  }

  function applyRoute(): void {
    if (!mounted || disposed || contextLocked.value) return
    const targetZone = typeof route.query.zoneId === 'string' ? route.query.zoneId : ''
    const targetMode: EdgeOneMode = route.query.type === 'domain' ? 'domain' : 'dns'
    autoSelectFirst = !targetZone
    const selected = targetZone || zones.value[0]?.id || ''
    const changed = selected !== zoneId.value || targetMode !== mode.value
    zoneId.value = selected
    mode.value = targetMode
    if (changed) clearRecords()
    const rawPage = typeof route.query.page === 'string' && /^\d+$/.test(route.query.page) ? Number(route.query.page) : 0
    const requestedPage = Number.isSafeInteger(rawPage) && rawPage >= 0 && rawPage < 2147483647 ? rawPage + 1 : 1
    const rawSize = typeof route.query.size === 'string' ? Number(route.query.size) : 20
    let savedFilters: Filters | null = null
    if (compact.value && route.query.mobileDnsSession === '1') {
      try {
        const saved = JSON.parse(sessionStorage.getItem(`oci.mobile.edgeone.${selected}.${targetMode}`) || 'null')
        if (saved && typeof saved.searchName === 'string' && typeof saved.searchContent === 'string' && typeof saved.searchStatus === 'string') savedFilters = saved
      } catch { /* An unavailable session store leaves the explicit route filters intact. */ }
    }
    searchName.value = savedFilters?.searchName ?? (typeof route.query.searchName === 'string' ? route.query.searchName : '')
    searchContent.value = targetMode === 'dns' ? savedFilters?.searchContent ?? (typeof route.query.searchContent === 'string' ? route.query.searchContent : '') : ''
    searchStatus.value = targetMode === 'domain' ? savedFilters?.searchStatus ?? (typeof route.query.status === 'string' ? route.query.status : '') : ''
    requested = { page: requestedPage, size: PAGE_SIZES.includes(rawSize) ? rawSize : 20, filters: {
      searchName: searchName.value.trim(), searchContent: searchContent.value.trim(), searchStatus: searchStatus.value,
    } }
    if (loaded.value && snapshotScope.value === scope.value) publishView()
    else if (selectedZone.value && !zonesLoading.value) void readRecords()
  }
  watch(() => JSON.stringify([route.query.zoneId, route.query.type, route.query.page, route.query.size,
    route.query.searchName, route.query.searchContent, route.query.status, route.query.mobileDnsSession]), applyRoute)
  watch([zoneId, mode, page, size, appliedFilters, loading, loaded, contextLocked, compact], () => {
    if (!compact.value || !mounted || disposed || contextLocked.value || loading.value || !loaded.value || snapshotScope.value !== scope.value) return
    let stored = false
    try { sessionStorage.setItem(`oci.mobile.edgeone.${zoneId.value}.${mode.value}`, JSON.stringify(appliedFilters.value)); stored = true } catch { /* URL context remains usable without session storage. */ }
    const values = { zoneId: zoneId.value, type: mode.value, page: String(page.value - 1), size: String(size.value), mobileDnsSession: stored ? '1' : undefined }
    if (Object.entries(values).every(([key, value]) => route.query[key] === value)) return
    void router.replace({ query: { ...route.query, ...values } })
  }, { flush: 'post' })
  watch(credentialsOpen, (open) => {
    if (open) {
      resumeZones = zonesLoading.value
      resumeRecords = loading.value
      cancelZones()
      cancelRecords()
    } else if (!disposed) {
      if (resumeZones) void loadZones()
      else if (resumeRecords) void refresh()
      resumeZones = resumeRecords = false
    }
  }, { flush: 'sync' })
  function beforeUnload(event: BeforeUnloadEvent): void {
    if (!operationPending.value) return
    event.preventDefault()
    event.returnValue = ''
  }
  onBeforeRouteLeave(() => !contextLocked.value)
  onBeforeRouteUpdate(() => !contextLocked.value)
  onMounted(() => {
    mounted = true
    applyRoute()
    void loadZones()
    window.addEventListener('beforeunload', beforeUnload)
  })
  onBeforeUnmount(() => {
    disposed = true
    mounted = false
    cancelZones()
    cancelRecords()
    operation.value = null
    allRows.value = []
    window.removeEventListener('beforeunload', beforeUnload)
  })

  return {
    zones, zonesLoading, zonesLoaded, zonesProblem, zoneId, selectedZone, zoneUnavailable, mode, selectMode,
    records, loading, loaded, readProblem, page, size, total, totalPages, lastUpdated,
    searchName, searchContent, searchStatus, appliedFilters,
    loadZones, refresh, selectZone, applySearch, clearSearch, changePage, changeSize,
    operation, operationPending, operationOutcome, operationResult, operationProblem,
    openEdit, openDelete, openSync, submitOperation, closeOperation, canDismissOperation,
    contextLocked, canOperate, requiresReview, reviewZoneId, reviewZone, reviewMode, reviewReady, acknowledgeReview,
  }
}
