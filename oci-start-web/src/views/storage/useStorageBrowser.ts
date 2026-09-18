import { computed, onBeforeUnmount, ref, shallowReactive, shallowRef, watch } from 'vue'
import {
  listStorageTenants, listStorageBuckets, listStorageObjects, listStorageResumableUploads,
  type StorageTenant, type StorageBucket, type StorageObject, type StorageBucketContext,
} from '@/api/objectStorage'

/** OCI supplies cursors, not totals. Only commit navigation after a successful read. */
export function useStorageBrowser() {
  const tenantId = ref('')
  const selectedBucket = shallowRef<StorageBucket | null>(null)
  const tenants = shallowReactive({ rows: [] as StorageTenant[], loading: false, problem: null as unknown })
  const buckets = shallowReactive({ rows: [] as StorageBucket[], loading: false, loaded: false, problem: null as unknown, nextPage: null as string | null, repeatedCursor: false })
  const objects = shallowReactive({ rows: [] as StorageObject[], loading: false, loaded: false, problem: null as unknown, page: 1, next: null as string | null, repeatedCursor: false })
  const resumable = shallowReactive({ count: null as number | null, loading: false, problem: null as unknown })
  const context = computed<StorageBucketContext | null>(() => tenantId.value && selectedBucket.value
    ? { tenantId: tenantId.value, namespace: selectedBucket.value.namespace, bucketName: selectedBucket.value.name } : null)
  let tenantRequest: AbortController | undefined
  let bucketRequest: AbortController | undefined
  let objectRequest: AbortController | undefined
  let resumeRequest: AbortController | undefined
  let bucketTokens: (string | null)[] = []
  let objectTokens: (string | null)[] = [null]
  let retryObjectPage = 1
  let retryObjectReset = false
  let retryBucketAppend = false
  let disposed = false

  async function loadTenants() {
    tenantRequest?.abort()
    const request = tenantRequest = new AbortController()
    tenants.loading = true
    tenants.problem = null
    try {
      const rows = await listStorageTenants(request.signal)
      if (disposed || request !== tenantRequest) return
      tenants.rows = rows
      if (tenantId.value && !rows.some(row => row.id === tenantId.value)) tenantId.value = ''
    } catch (cause) {
      if (!disposed && request === tenantRequest && !request.signal.aborted) tenants.problem = cause
    } finally { if (!disposed && request === tenantRequest) tenants.loading = false }
  }

  async function loadBuckets(append = false) {
    const id = tenantId.value
    if (!id || (append && !buckets.nextPage)) return
    bucketRequest?.abort()
    const request = bucketRequest = new AbortController()
    const token = append ? buckets.nextPage : null
    retryBucketAppend = append
    buckets.loading = true
    buckets.problem = null
    buckets.repeatedCursor = false
    try {
      const result = await listStorageBuckets({ tenantId: id, limit: 5, pageToken: token || undefined }, request.signal)
      if (disposed || request !== bucketRequest || tenantId.value !== id) return
      const loaded = append ? [...buckets.rows] : []
      for (const row of result.items) {
        const index = loaded.findIndex(item => item.name === row.name && item.namespace === row.namespace)
        if (index < 0) loaded.push(row)
        else loaded[index] = row
      }
      bucketTokens = append ? [...bucketTokens, token] : [null]
      buckets.rows = loaded
      buckets.loaded = true
      buckets.repeatedCursor = result.nextPage != null && bucketTokens.includes(result.nextPage)
      buckets.nextPage = buckets.repeatedCursor ? null : result.nextPage
      // Refreshing the first bucket page does not prove a selected later-page bucket was deleted.
      const refreshed = loaded.find(row => row.name === selectedBucket.value?.name && row.namespace === selectedBucket.value?.namespace)
      if (refreshed) selectedBucket.value = refreshed
    } catch (cause) {
      if (!disposed && request === bucketRequest && !request.signal.aborted) buckets.problem = cause
    } finally { if (!disposed && request === bucketRequest) buckets.loading = false }
  }

  function clearObjects() {
    objectRequest?.abort()
    objectRequest = undefined
    objectTokens = [null]
    Object.assign(objects, { rows: [], loading: false, loaded: false, problem: null, page: 1, next: null, repeatedCursor: false })
  }
  function selectBucket(bucket: StorageBucket | null) {
    clearObjects()
    selectedBucket.value = bucket
    if (bucket) void loadObjects(1, true)
  }
  async function loadObjects(page = objects.page, reset = false) {
    const target = context.value
    if (!target) return
    if (page < 1 || (!reset && page > objectTokens.length)) return
    const key = JSON.stringify(target)
    const token = reset ? null : objectTokens[page - 1]
    objectRequest?.abort()
    const request = objectRequest = new AbortController()
    retryObjectPage = page
    retryObjectReset = reset
    objects.loading = true
    objects.problem = null
    objects.repeatedCursor = false
    try {
      const result = await listStorageObjects({ ...target, limit: 5, startToken: token ?? undefined }, request.signal)
      if (disposed || request !== objectRequest || JSON.stringify(context.value) !== key) return
      const history = reset ? [null] : objectTokens.slice(0, page)
      objects.repeatedCursor = result.nextStartWith != null && history.includes(result.nextStartWith)
      objects.next = objects.repeatedCursor ? null : result.nextStartWith
      if (objects.next != null) history.push(objects.next)
      objectTokens = history
      objects.rows = result.items
      objects.page = page
      objects.loaded = true
    } catch (cause) {
      if (!disposed && request === objectRequest && !request.signal.aborted) objects.problem = cause
    } finally { if (!disposed && request === objectRequest) objects.loading = false }
  }
  async function afterObjectDelete(target: StorageBucketContext) {
    const key = JSON.stringify({ tenantId: target.tenantId, namespace: target.namespace, bucketName: target.bucketName })
    if (JSON.stringify(context.value) !== key) return
    await loadObjects()
    if (disposed || JSON.stringify(context.value) !== key) return
    if (!objects.problem && !objects.loading && objects.rows.length === 0 && objects.page > 1) await loadObjects(objects.page - 1)
  }
  async function loadResumable() {
    const target = context.value
    if (!target) return
    resumeRequest?.abort()
    const request = resumeRequest = new AbortController()
    const key = JSON.stringify(target)
    resumable.loading = true
    resumable.problem = null
    try {
      const rows = await listStorageResumableUploads(target, request.signal)
      if (disposed || request !== resumeRequest || JSON.stringify(context.value) !== key) return
      resumable.count = rows.length
    } catch (cause) {
      if (!disposed && request === resumeRequest && !request.signal.aborted) resumable.problem = cause
    } finally { if (!disposed && request === resumeRequest) resumable.loading = false }
  }
  function afterBucketDelete(target: StorageBucketContext) {
    if (tenantId.value !== target.tenantId) return
    if (selectedBucket.value?.name === target.bucketName && selectedBucket.value.namespace === target.namespace) selectBucket(null)
    buckets.rows = buckets.rows.filter(row => row.name !== target.bucketName || row.namespace !== target.namespace)
    void loadBuckets()
  }
  watch(tenantId, () => {
    bucketRequest?.abort()
    bucketRequest = undefined
    bucketTokens = []
    Object.assign(buckets, { rows: [], loading: false, loaded: false, problem: null, nextPage: null, repeatedCursor: false })
    selectBucket(null)
    if (tenantId.value) void loadBuckets()
  }, { flush: 'sync' })
  watch(() => JSON.stringify(context.value), () => {
    resumeRequest?.abort()
    resumeRequest = undefined
    Object.assign(resumable, { count: null, loading: false, problem: null })
    if (context.value) void loadResumable()
  }, { flush: 'sync' })
  onBeforeUnmount(() => {
    disposed = true
    tenantRequest?.abort()
    bucketRequest?.abort()
    objectRequest?.abort()
    resumeRequest?.abort()
  })
  return {
    tenantId, selectedBucket, context, tenants, buckets, objects, resumable, loadTenants, loadBuckets, selectBucket, loadObjects, loadResumable,
    afterObjectDelete, afterBucketDelete,
    retryBuckets: () => loadBuckets(retryBucketAppend), retryObjects: () => loadObjects(retryObjectPage, retryObjectReset),
  }
}
