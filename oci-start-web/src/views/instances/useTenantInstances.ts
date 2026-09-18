import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { isCancel } from 'axios'
import { useRoute, useRouter } from 'vue-router'
import { getInstances, isInstanceTenantId, type InstanceRow } from '@/api/instances'

export type TenantInstancesTab = 'instances' | 'volumes'

const MAX_PAGE = 2147483646
const PAGE_SIZES = [10, 20, 30, 50]

function pageFromQuery(value: unknown): number {
  if (typeof value !== 'string' || !/^\d+$/.test(value)) return 0
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed >= 0 && parsed <= MAX_PAGE ? parsed : 0
}

function sizeFromQuery(value: unknown): number {
  if (typeof value !== 'string' || !/^\d+$/.test(value)) return 20
  const parsed = Number(value)
  return PAGE_SIZES.includes(parsed) ? parsed : 20
}

/** Read the selected regional tenant's local instance page, without cloud writes. */
export function useTenantInstances() {
  const route = useRoute()
  const router = useRouter()
  const rows = ref<InstanceRow[]>([])
  const total = ref(0)
  const loaded = ref(false)
  const loading = ref(false)
  const problem = ref<unknown>(null)
  const updatedAt = ref<Date | null>(null)
  const tenantId = computed(() => typeof route.query.tenantId === 'string' ? route.query.tenantId : '')
  // The shared API also serves an unscoped page. Never pass its optional empty
  // tenant value here: this dedicated page always requires a valid local Long ID.
  const invalidScope = computed(() => !isInstanceTenantId(route.query.tenantId))
  const page = computed(() => pageFromQuery(route.query.page))
  const size = computed(() => sizeFromQuery(route.query.size))
  const tab = computed<TenantInstancesTab>(() => route.query.tab === 'volumes' ? 'volumes' : 'instances')
  const volumeRows = computed(() => rows.value.filter((row) => {
    const volumeId = row.bootVolumeId.trim()
    return volumeId !== '' && volumeId !== '-1'
  }))
  // A tab changes the presentation of this same page; it must not start a read.
  const queryKey = computed(() => JSON.stringify([route.query.tenantId, page.value, size.value]))

  let dataKey = ''
  let sequence = 0
  let controller: AbortController | undefined
  let disposed = false

  function clearData(key: string) {
    dataKey = key
    rows.value = []
    total.value = 0
    loaded.value = false
    updatedAt.value = null
  }

  async function load(): Promise<void> {
    if (disposed) return
    const current = ++sequence
    controller?.abort()
    controller = undefined
    const key = queryKey.value
    const path = route.path
    const scope = tenantId.value
    const requestedPage = page.value
    const requestedSize = size.value
    if (dataKey !== key || invalidScope.value) clearData(key)
    problem.value = null
    if (invalidScope.value) {
      loading.value = false
      return
    }
    const active = new AbortController()
    controller = active
    loading.value = true
    const isCurrent = () => !disposed && current === sequence && controller === active
      && !active.signal.aborted && queryKey.value === key && route.path === path
    try {
      const result = await getInstances(requestedPage, requestedSize, scope, active.signal)
      if (!isCurrent()) return
      if (requestedPage > 0 && requestedPage >= result.totalPages) {
        const lastPage = Math.max(0, result.totalPages - 1)
        // The query watcher loads the corrected page. Do not briefly publish the
        // out-of-range response or issue a duplicate request after navigation.
        const failure = await router.replace({
          path, query: { ...route.query, page: String(lastPage) }, hash: route.hash,
        })
        if (failure && isCurrent()) problem.value = failure
        return
      }
      rows.value = result.rows
      total.value = result.total
      loaded.value = true
      updatedAt.value = new Date()
    } catch (cause) {
      if (isCurrent() && !isCancel(cause)) problem.value = cause
      // Same-page refresh failures retain its last successful data and timestamp.
    } finally {
      if (!disposed && current === sequence && controller === active) {
        controller = undefined
        loading.value = false
      }
    }
  }

  function navigate(query: Record<string, string>, replace = false) {
    if (disposed) return
    const origin = route.fullPath
    const location = { path: route.path, query: { ...route.query, ...query }, hash: route.hash }
    const navigation = replace ? router.replace(location) : router.push(location)
    void navigation.catch((cause: unknown) => {
      if (!disposed && route.fullPath === origin) problem.value = cause
    })
  }

  function changePage(oneBased: number): void {
    if (!Number.isSafeInteger(oneBased) || oneBased < 1 || oneBased > MAX_PAGE + 1) return
    const next = oneBased - 1
    if (next !== page.value) navigate({ page: String(next) })
  }

  function changeSize(value: number): void {
    if (PAGE_SIZES.includes(value) && value !== size.value) navigate({ page: '0', size: String(value) })
  }

  function changeTab(value: TenantInstancesTab): void {
    if ((value === 'instances' || value === 'volumes') && value !== tab.value) navigate({ tab: value }, true)
  }

  watch(queryKey, () => { void load() }, { immediate: true })
  onBeforeUnmount(() => {
    disposed = true
    ++sequence
    controller?.abort()
    controller = undefined
    loading.value = false
  })

  return {
    rows, total, loaded, loading, problem, updatedAt,
    tenantId, invalidScope, page, size, tab, volumeRows,
    load, changePage, changeSize, changeTab,
  }
}
