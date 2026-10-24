import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch, type Ref } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useCompactViewport } from '@/composables/useCompactViewport'
import {
  CloudflareApiError, cloudflareCanEdit, cloudflareError, createCloudflareRecord,
  deleteCloudflareRecord, fetchCloudflareRecords, fetchCloudflareZones, isCloudflareId,
  syncCloudflareRecords, updateCloudflareRecord,
  type CloudflareMutationResult, type CloudflareQuery, type CloudflareRecord,
  type CloudflareRecordInput, type CloudflareZone,
} from '@/api/cloudflare'

export interface CloudflareOperation {
  kind: 'create' | 'edit' | 'delete' | 'sync'
  zone: CloudflareZone
  record: CloudflareRecord | null
}
const PAGE_SIZES = [10, 20, 30, 50]
const MAX_PAGE = 2147483647

export function useCloudflarePage(dialogOpen: Ref<boolean>) {
  const route = useRoute()
  const router = useRouter()
  const compact = useCompactViewport()
  const zones = ref<CloudflareZone[]>([])
  const zonesLoading = ref(false)
  const zonesLoaded = ref(false)
  const zonesProblem = shallowRef<CloudflareApiError | null>(null)
  const zoneId = ref('')
  const selectedZone = computed(() => zones.value.find(zone => zone.id === zoneId.value) || null)
  const zoneUnavailable = computed(() => !!zoneId.value && (!isCloudflareId(zoneId.value)
    || (zonesLoaded.value && !zonesLoading.value && !selectedZone.value)))
  const records = ref<CloudflareRecord[]>([])
  const loading = ref(false)
  const loaded = ref(false)
  const readProblem = shallowRef<CloudflareApiError | null>(null)
  const page = ref(1)
  const size = ref(20)
  const total = ref(0)
  const totalPages = ref(0)
  const searchName = ref('')
  const searchContent = ref('')
  const appliedFilters = shallowRef({ searchName: '', searchContent: '' })
  const lastUpdated = ref<Date | null>(null)

  const operation = shallowRef<CloudflareOperation | null>(null)
  const operationPending = ref(false)
  const operationOutcome = ref<'idle' | 'success' | 'unknown' | 'failed'>('idle')
  const operationResult = shallowRef<CloudflareMutationResult | null>(null)
  const operationProblem = shallowRef<CloudflareApiError | null>(null)
  const requiresReview = ref(false)
  const reviewZoneId = ref('')
  const reviewZone = shallowRef<CloudflareZone | null>(null)
  const readRevision = ref(0)
  const reviewAfterRevision = ref(0)
  const snapshotZoneId = ref('')
  const canDismissOperation = computed(() => !operationPending.value)
  const contextLocked = computed(() => dialogOpen.value || !!operation.value || operationPending.value)
  const canOperate = computed(() => !!selectedZone.value && zonesLoaded.value && !zonesLoading.value
    && !zonesProblem.value && !loading.value && loaded.value && !readProblem.value
    && snapshotZoneId.value === zoneId.value && !contextLocked.value && !requiresReview.value)
  const reviewReady = computed(() => requiresReview.value && !loading.value && !zonesLoading.value
    && !readProblem.value && !zonesProblem.value && !!selectedZone.value
    && zoneId.value === reviewZoneId.value && snapshotZoneId.value === reviewZoneId.value
    && readRevision.value >= reviewAfterRevision.value)

  let disposed = false
  let mounted = false
  let zonesSequence = 0
  let recordsSequence = 0
  let zonesController: AbortController | undefined
  let recordsController: AbortController | undefined
  let requested: CloudflareQuery | null = null
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
    records.value = []
    loaded.value = false
    readProblem.value = null
    total.value = totalPages.value = 0
    page.value = 1
    size.value = 20
    appliedFilters.value = { searchName: '', searchContent: '' }
    lastUpdated.value = null
    snapshotZoneId.value = ''
  }
  function currentQuery(): CloudflareQuery {
    return requested?.zoneId === zoneId.value ? { ...requested } : {
      zoneId: zoneId.value, page: page.value, size: size.value, ...appliedFilters.value,
    }
  }

  async function readRecords(query: CloudflareQuery, corrected = false): Promise<void> {
    if (disposed || !mounted || operationPending.value || dialogOpen.value
      || !selectedZone.value || query.zoneId !== zoneId.value) return
    cancelRecords()
    requested = { ...query }
    const current = recordsSequence
    const active = new AbortController()
    recordsController = active
    loading.value = true
    readProblem.value = null
    const isCurrent = () => !disposed && current === recordsSequence && !active.signal.aborted
      && recordsController === active && query.zoneId === zoneId.value
    try {
      const result = await fetchCloudflareRecords(query, active.signal)
      if (!isCurrent()) return
      if (query.page > Math.max(1, result.totalPages)) {
        // Deleting a last row can make its page disappear. Correct by reading
        // the last available page, without publishing a misleading empty page.
        if (corrected) throw new CloudflareApiError('invalidResponse')
        await readRecords({ ...query, page: Math.max(1, result.totalPages) }, true)
        return
      }
      records.value = result.records
      page.value = result.page
      size.value = result.size
      total.value = result.total
      totalPages.value = result.totalPages
      appliedFilters.value = { searchName: query.searchName || '', searchContent: query.searchContent || '' }
      loaded.value = true
      lastUpdated.value = new Date()
      snapshotZoneId.value = query.zoneId
      ++readRevision.value
    } catch (cause) {
      if (isCurrent()) readProblem.value = cloudflareError(cause)
    } finally {
      if (isCurrent()) {
        recordsController = undefined
        loading.value = false
      }
    }
  }

  async function loadZones(): Promise<void> {
    if (disposed || !mounted || contextLocked.value || zonesLoading.value) return
    cancelZones()
    const current = zonesSequence
    const active = new AbortController()
    zonesController = active
    zonesLoading.value = true
    zonesProblem.value = null
    let accepted = false
    try {
      const result = await fetchCloudflareZones(active.signal)
      if (disposed || current !== zonesSequence || active.signal.aborted) return
      zones.value = result
      zonesLoaded.value = true
      accepted = true
      if (!selectedZone.value && zoneId.value) clearRecords()
    } catch (cause) {
      if (!disposed && current === zonesSequence && !active.signal.aborted) zonesProblem.value = cloudflareError(cause)
    } finally {
      if (!disposed && current === zonesSequence) {
        zonesController = undefined
        zonesLoading.value = false
      }
    }
    // A refreshed account list validates scope before any dependent record read.
    if (accepted && !disposed && current === zonesSequence && selectedZone.value) await readRecords(currentQuery())
  }
  async function refresh(): Promise<void> {
    if (contextLocked.value || zonesLoading.value) return
    await readRecords(currentQuery())
  }
  function selectZone(value: string): void {
    if (disposed || contextLocked.value || value === zoneId.value) return
    if (value !== '' && (!isCloudflareId(value) || !zones.value.some(zone => zone.id === value))) return
    zoneId.value = value
    searchName.value = searchContent.value = ''
    clearRecords()
    requested = { zoneId: value, page: 1, size: 20, searchName: '', searchContent: '' }
    if (value) void readRecords(requested)
  }
  function applySearch(): void {
    if (contextLocked.value) return
    void readRecords({ zoneId: zoneId.value, page: 1, size: size.value,
      searchName: searchName.value.trim(), searchContent: searchContent.value.trim() })
  }
  function clearSearch(): void {
    if (contextLocked.value) return
    searchName.value = searchContent.value = ''
    applySearch()
  }
  function changePage(value: number): void {
    if (contextLocked.value || !Number.isSafeInteger(value) || value < 1 || value > MAX_PAGE) return
    void readRecords({ zoneId: zoneId.value, page: value, size: size.value, ...appliedFilters.value })
  }
  function changeSize(value: number): void {
    if (contextLocked.value || !PAGE_SIZES.includes(value)) return
    void readRecords({ zoneId: zoneId.value, page: 1, size: value, ...appliedFilters.value })
  }

  function openOperation(kind: CloudflareOperation['kind'], row?: CloudflareRecord): void {
    if (!canOperate.value || !selectedZone.value) return
    let record: CloudflareRecord | null = null
    if (kind === 'edit' || kind === 'delete') {
      if (!row || snapshotZoneId.value !== zoneId.value) return
      const current = records.value.find(value => value.id === row.id)
      if (!current || (kind === 'edit' && !cloudflareCanEdit(current.type))) return
      record = { ...current }
    }
    cancelRecords()
    operation.value = { kind, zone: { ...selectedZone.value }, record }
    operationOutcome.value = 'idle'
    operationResult.value = null
    operationProblem.value = null
  }
  function openCreate(): void { openOperation('create') }
  function openEdit(row: CloudflareRecord): void { openOperation('edit', row) }
  function openDelete(row: CloudflareRecord): void { openOperation('delete', row) }
  function openSync(): void { openOperation('sync') }
  function closeOperation(): void {
    if (operationPending.value) return
    operation.value = null
    operationOutcome.value = 'idle'
    operationResult.value = null
    operationProblem.value = null
  }
  async function submitOperation(input?: CloudflareRecordInput): Promise<void> {
    const target = operation.value
    if (disposed || !target || operationPending.value || dialogOpen.value
      || requiresReview.value || operationOutcome.value === 'success' || operationOutcome.value === 'unknown') return
    operationPending.value = true
    operationProblem.value = null
    operationResult.value = null
    cancelRecords()
    let attempted = false
    try {
      let result: CloudflareMutationResult
      if (target.kind === 'create') {
        if (!input) throw new CloudflareApiError('recordRequired')
        result = await createCloudflareRecord(target.zone.id, { ...input })
      } else if (target.kind === 'edit') {
        if (!input || !target.record) throw new CloudflareApiError('recordRequired')
        result = await updateCloudflareRecord(target.zone.id, target.record.id, {
          ...input, type: target.record.type, name: target.record.name,
        })
      } else if (target.kind === 'delete') {
        if (!target.record) throw new CloudflareApiError('invalidInput')
        result = await deleteCloudflareRecord(target.zone.id, target.record.id)
      } else result = await syncCloudflareRecords(target.zone.id, target.zone.name)
      attempted = true
      if (disposed) return
      operationResult.value = result
      operationOutcome.value = 'success'
    } catch (cause) {
      if (disposed) return
      const problem = cloudflareError(cause)
      attempted = problem.writeAttempted
      operationProblem.value = problem
      operationOutcome.value = attempted ? 'unknown' : 'failed'
      if (attempted) {
        requiresReview.value = true
        reviewZoneId.value = target.zone.id
        reviewZone.value = { ...target.zone }
        reviewAfterRevision.value = readRevision.value + 1
      }
    } finally {
      if (!disposed) {
        operationPending.value = false
        // Keep the mutation receipt even if the subsequent read fails. Reads may
        // correct an empty last page; no read failure ever resubmits the write.
        if (attempted && zoneId.value === target.zone.id) await readRecords(currentQuery())
      }
    }
  }
  function acknowledgeReview(): void {
    if (contextLocked.value || !reviewReady.value) return
    requiresReview.value = false
    reviewZoneId.value = ''
    reviewZone.value = null
    reviewAfterRevision.value = 0
  }

  function applyRoute(): void {
    if (!mounted || disposed || contextLocked.value) return
    const target = typeof route.query.zoneId === 'string' ? route.query.zoneId : ''
    if (target !== zoneId.value) { zoneId.value = target; clearRecords() }
    const rawPage = typeof route.query.page === 'string' && /^\d+$/.test(route.query.page) ? Number(route.query.page) : 0
    const requestedPage = Number.isSafeInteger(rawPage) && rawPage >= 0 && rawPage < MAX_PAGE ? rawPage + 1 : 1
    const rawSize = typeof route.query.size === 'string' ? Number(route.query.size) : 20
    const requestedSize = PAGE_SIZES.includes(rawSize) ? rawSize : 20
    let savedFilters: { searchName: string; searchContent: string } | null = null
    if (compact.value && route.query.mobileDnsSession === '1') {
      try {
        const saved = JSON.parse(sessionStorage.getItem(`oci.mobile.cloudflare.${target}`) || 'null')
        if (saved && typeof saved.searchName === 'string' && typeof saved.searchContent === 'string') savedFilters = saved
      } catch { /* An unavailable session store leaves the explicit route filters intact. */ }
    }
    searchName.value = savedFilters?.searchName ?? (typeof route.query.searchName === 'string' ? route.query.searchName : '')
    searchContent.value = savedFilters?.searchContent ?? (typeof route.query.searchContent === 'string' ? route.query.searchContent : '')
    requested = { zoneId: target, page: requestedPage, size: requestedSize,
      searchName: searchName.value.trim(), searchContent: searchContent.value.trim() }
    if (compact.value && loaded.value && !loading.value && snapshotZoneId.value === target
      && page.value === requestedPage && size.value === requestedSize
      && appliedFilters.value.searchName === requested.searchName && appliedFilters.value.searchContent === requested.searchContent) return
    if (selectedZone.value && !zonesLoading.value) void readRecords(requested)
  }
  watch(() => JSON.stringify([route.query.zoneId, route.query.page, route.query.size, route.query.searchName, route.query.searchContent, route.query.mobileDnsSession]), applyRoute)
  watch([zoneId, page, size, appliedFilters, loading, loaded, contextLocked, compact], () => {
    if (!compact.value || !mounted || disposed || contextLocked.value || loading.value || !loaded.value || snapshotZoneId.value !== zoneId.value) return
    let stored = false
    try { sessionStorage.setItem(`oci.mobile.cloudflare.${zoneId.value}`, JSON.stringify(appliedFilters.value)); stored = true } catch { /* URL context remains usable without session storage. */ }
    const values = { zoneId: zoneId.value, page: String(page.value - 1), size: String(size.value), mobileDnsSession: stored ? '1' : undefined }
    if (Object.entries(values).every(([key, value]) => route.query[key] === value)) return
    void router.replace({ query: { ...route.query, ...values } })
  }, { flush: 'post' })
  watch(dialogOpen, (open) => {
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
    requested = null
    window.removeEventListener('beforeunload', beforeUnload)
  })

  return {
    zones, zonesLoading, zonesLoaded, zonesProblem, zoneId, selectedZone, zoneUnavailable,
    records, loading, loaded, readProblem, page, size, total, totalPages,
    searchName, searchContent, appliedFilters, lastUpdated,
    loadZones, refresh, selectZone, applySearch, clearSearch, changePage, changeSize,
    operation, operationPending, operationOutcome, operationResult, operationProblem,
    openCreate, openEdit, openDelete, openSync, submitOperation, closeOperation, canDismissOperation,
    contextLocked, canOperate, requiresReview, reviewZoneId, reviewZone, reviewReady, acknowledgeReview,
  }
}
