<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, shallowRef, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { usePageMotion } from '@/composables/usePageMotion'
import { regionCityName } from '@/views/regions/regionCoords'
import {
  getSubscribedRegions, getAvailableRegions, getRegionSummary, getSubscriptionStatus,
  subscribeRegions, subscriptionError,
  type SubscribedRegion, type AvailableRegion, type RegionSummary, type SubscriptionResult,
} from '@/api/regionSubscription'
import './tenants.scss'

type Tab = 'subscribed' | 'available'
type Source = Tab | 'summary'
interface RegionRow { key: string; name: string; location: string; status: string; home: boolean }
const tabs: Tab[] = ['subscribed', 'available']
const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const root = ref<HTMLElement | null>(null)
const scrollArea = ref<HTMLElement | null>(null)
const { revealRows } = usePageMotion(root)
const tenantId = computed(() => {
  const id = route.query.tenantId
  // Local IDs are Java Long values. Never round them through a JS number.
  return typeof id === 'string' && /^[1-9]\d*$/.test(id)
    && (id.length < 19 || (id.length === 19 && id <= '9223372036854775807')) ? id : ''
})
const numberFormat = computed(() => new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN'))
const count = (value: number) => numberFormat.value.format(value)
const subscribedRows = shallowRef<SubscribedRegion[]>([])
const availableRows = shallowRef<AvailableRegion[]>([])
const summary = shallowRef<RegionSummary | null>(null)
const loading = reactive<Record<Source, boolean>>({ subscribed: false, available: false, summary: false })
const loaded = reactive<Record<Source, boolean>>({ subscribed: false, available: false, summary: false })
const errors = shallowRef<Partial<Record<Source, unknown>>>({})
const controllers = new Map<Source, AbortController>()
const checkControllers = new Map<string, AbortController>()
let subscriptionController: AbortController | undefined
let scope = 0

const activeTab = ref<Tab>('subscribed')
const search = ref('')
const statusFilter = ref('')
const page = ref(1)
const pageSize = ref(20)
const selected = ref(new Set<string>())
const checking = ref(new Set<string>())
const checkErrors = shallowRef<Record<string, unknown>>({})
const detailKey = ref('')
const detail = computed(() => subscribedRows.value.find(row => row.regionKey === detailKey.value))
const dialogOpen = ref(false)
const dialogStage = ref<'confirm' | 'pending' | 'result'>('confirm')
const draft = shallowRef<RegionRow[]>([])
const submitting = ref(false)
const result = shallowRef<SubscriptionResult | null>(null)
const submitError = shallowRef<unknown>(null)
const refreshIncomplete = computed(() => dialogStage.value === 'result'
  && Boolean(errors.value.subscribed || errors.value.available || errors.value.summary))

function statusLabel(status: string) {
  const key: Record<string, string> = {
    READY: 'statusReady', IN_PROGRESS: 'statusProgress', FAILED: 'statusFailed',
    NOT_SUBSCRIBED: 'statusNotSubscribed',
  }
  return key[status] ? t(`tenantSubscription.${key[status]}`) : status || t('tenantSubscription.statusUnknown')
}
function statusTone(status: string) {
  return status === 'READY' ? 'ready' : status === 'IN_PROGRESS' ? 'progress' : status === 'FAILED' ? 'failed' : 'unknown'
}
function locationName(name: string, cnName = '') {
  return locale.value.startsWith('zh') && cnName ? cnName : regionCityName(name, locale.value)
}
const rows = computed<RegionRow[]>(() => activeTab.value === 'subscribed'
  ? subscribedRows.value.map(row => ({
    key: row.regionKey, name: row.regionName, location: locationName(row.regionName),
    status: row.status, home: row.isHomeRegion,
  }))
  : availableRows.value.map(row => ({
    key: row.key, name: row.name, location: locationName(row.name, row.cnName), status: '', home: false,
  })))
const filteredRows = computed(() => {
  const keyword = search.value.trim().toLocaleLowerCase()
  return rows.value.filter(row => {
    if (activeTab.value === 'subscribed' && statusFilter.value && row.status !== statusFilter.value) return false
    return !keyword || [row.key, row.name, row.location, row.status ? statusLabel(row.status) : '']
      .some(value => value.toLocaleLowerCase().includes(keyword))
  })
})
const pageRows = computed(() => filteredRows.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
const statusOptions = computed(() => Array.from(new Set(subscribedRows.value.map(row => row.status))))
const allPageSelected = computed(() => pageRows.value.length > 0 && pageRows.value.every(row => selected.value.has(row.key)))
const somePageSelected = computed(() => !allPageSelected.value && pageRows.value.some(row => selected.value.has(row.key)))
const isRefreshing = computed(() => Object.values(loading).some(Boolean))
const activeError = computed(() => errors.value[activeTab.value])
const selectedCount = computed(() => selected.value.size)
const successCount = computed(() => result.value?.details.filter(item => item.success).length ?? 0)
const failedCount = computed(() => result.value?.details.filter(item => !item.success).length ?? 0)
const resultHeading = computed(() => {
  if (!result.value) return t('tenantSubscription.resultUnknown')
  if (!failedCount.value) return t('tenantSubscription.resultAllSuccess', { count: count(successCount.value) })
  if (!successCount.value) return t('tenantSubscription.resultAllFailed', { count: count(failedCount.value) })
  return t('tenantSubscription.resultPartial', { success: count(successCount.value), failed: count(failedCount.value) })
})
const dialogTitle = computed(() => t(`tenantSubscription.${dialogStage.value === 'confirm' ? 'confirmTitle' : dialogStage.value === 'pending' ? 'submitting' : 'resultTitle'}`))
const resultDetails = computed(() => new Map(result.value?.details.map(item => [item.regionKey, item]) ?? []))

function setError(source: Source, error?: unknown) {
  errors.value = { ...errors.value, [source]: error }
}
async function loadSource(source: Source): Promise<boolean> {
  if (!tenantId.value) return false
  if (source === 'subscribed') {
    // A newer full refresh supersedes outstanding checks against the old list.
    checkControllers.forEach(controller => controller.abort())
    checkControllers.clear()
    checking.value = new Set()
  }
  controllers.get(source)?.abort()
  const controller = new AbortController()
  controllers.set(source, controller)
  const currentScope = scope
  const id = tenantId.value
  const current = () => currentScope === scope && controllers.get(source) === controller && !controller.signal.aborted
  loading[source] = true
  setError(source)
  try {
    if (source === 'subscribed') {
      const data = await getSubscribedRegions(id, controller.signal)
      if (!current()) return false
      subscribedRows.value = data
      checkErrors.value = {}
    } else if (source === 'available') {
      const data = await getAvailableRegions(id, controller.signal)
      if (!current()) return false
      availableRows.value = data
      const keys = new Set(data.map(row => row.key))
      selected.value = new Set([...selected.value].filter(key => keys.has(key)))
    } else {
      const data = await getRegionSummary(id, controller.signal)
      if (!current()) return false
      summary.value = data
    }
    loaded[source] = true
    return true
  } catch (error) {
    if (current()) setError(source, error)
    return false
  } finally {
    if (current()) {
      loading[source] = false
      controllers.delete(source)
    }
  }
}
async function refreshAll(includeAvailable = false) {
  const sources: Source[] = ['subscribed', 'summary']
  if (includeAvailable || loaded.available || activeTab.value === 'available') sources.push('available')
  const outcomes = await Promise.all(sources.map(loadSource))
  return outcomes.every(Boolean)
}
function goBack() {
  void router.push({ path: '/tenants/list', query: { cloudType: String(route.query.cloudType || '1') } })
}
function selectTab(tab: Tab) {
  if (activeTab.value === tab) return
  activeTab.value = tab
  page.value = 1
  statusFilter.value = ''
  if (tab === 'available' && !loading.available) void loadSource('available')
}
function moveTab(event: KeyboardEvent) {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
  event.preventDefault()
  selectTab(event.key === 'Home' ? 'subscribed' : event.key === 'End' ? 'available' : activeTab.value === 'subscribed' ? 'available' : 'subscribed')
  root.value?.querySelector<HTMLButtonElement>(`#subscription-tab-${activeTab.value}`)?.focus()
}
function toggleRow(key: string, checked: boolean) {
  if (submitting.value) return
  const next = new Set(selected.value)
  if (checked) next.add(key)
  else next.delete(key)
  selected.value = next
}
function togglePage(checked: boolean) {
  if (submitting.value) return
  const next = new Set(selected.value)
  for (const row of pageRows.value) {
    if (checked) next.add(row.key)
    else next.delete(row.key)
  }
  selected.value = next
}
function clearFilters() { search.value = ''; statusFilter.value = '' }
function tabCount(tab: Tab) {
  if (loaded[tab]) return count(tab === 'subscribed' ? subscribedRows.value.length : availableRows.value.length)
  if (summary.value) return count(tab === 'subscribed' ? summary.value.subscribedRegions : summary.value.unsubscribedRegions)
  return '—'
}
function openSubscribe(keys: string[]) {
  if (submitting.value || loading.available || !tenantId.value) return
  const wanted = new Set(keys)
  draft.value = availableRows.value.filter(row => wanted.has(row.key)).map(row => ({
    key: row.key, name: row.name, location: locationName(row.name, row.cnName), status: '', home: false,
  }))
  if (!draft.value.length) return
  result.value = null
  submitError.value = null
  dialogStage.value = 'confirm'
  dialogOpen.value = true
}
async function submit() {
  if (submitting.value || dialogStage.value !== 'confirm' || !tenantId.value || !draft.value.length) return
  const currentScope = scope
  const id = tenantId.value
  const keys = draft.value.map(row => row.key)
  const controller = new AbortController()
  subscriptionController = controller
  const current = () => currentScope === scope && !controller.signal.aborted
  submitting.value = true
  dialogStage.value = 'pending'
  try {
    const response = await subscribeRegions(id, keys, controller.signal)
    if (!current()) return
    result.value = response
    const successful = new Set(response.details.filter(item => item.success).map(item => item.regionKey))
    selected.value = new Set([...selected.value].filter(key => !successful.has(key)))
  } catch (error) {
    if (!current()) return
    submitError.value = error
  } finally {
    if (current()) {
      submitting.value = false
      subscriptionController = undefined
      dialogStage.value = 'result'
      // An existing subscription can return success while still IN_PROGRESS.
      // Reload OCI state instead of optimistically claiming READY.
      await refreshAll(true)
    }
  }
}
async function checkStatus(key: string) {
  if (checking.value.has(key) || loading.subscribed || !tenantId.value) return
  const currentScope = scope
  const controller = new AbortController()
  checkControllers.set(key, controller)
  checking.value = new Set([...checking.value, key])
  checkErrors.value = { ...checkErrors.value, [key]: undefined }
  try {
    const response = await getSubscriptionStatus(tenantId.value, key, controller.signal)
    if (currentScope !== scope || controller.signal.aborted) return
    subscribedRows.value = subscribedRows.value.map(row => row.regionKey === key ? { ...row, status: response.status } : row)
    ElMessage.info(t('tenantSubscription.statusUpdated', { region: key, status: statusLabel(response.status) }))
    if (response.status === 'READY' || !response.subscribed) void refreshAll(loaded.available)
  } catch (error) {
    if (currentScope === scope && !controller.signal.aborted) checkErrors.value = { ...checkErrors.value, [key]: error }
  } finally {
    if (currentScope === scope && !controller.signal.aborted) {
      checking.value = new Set([...checking.value].filter(value => value !== key))
      checkControllers.delete(key)
    }
  }
}
function viewSubscribed() { dialogOpen.value = false; clearFilters(); selectTab('subscribed') }
function cancelRequests() {
  scope += 1
  controllers.forEach(controller => controller.abort())
  controllers.clear()
  checkControllers.forEach(controller => controller.abort())
  checkControllers.clear()
  // This only stops listening in this view; it does not cancel an OCI operation.
  subscriptionController?.abort()
  subscriptionController = undefined
}
watch(tenantId, () => {
  cancelRequests()
  subscribedRows.value = []
  availableRows.value = []
  summary.value = null
  for (const source of ['subscribed', 'available', 'summary'] as Source[]) { loading[source] = false; loaded[source] = false }
  errors.value = {}
  selected.value = new Set()
  checking.value = new Set()
  checkErrors.value = {}
  detailKey.value = ''
  activeTab.value = 'subscribed'
  clearFilters()
  page.value = 1
  dialogOpen.value = false
  dialogStage.value = 'confirm'
  submitting.value = false
  draft.value = []
  result.value = null
  submitError.value = null
  if (tenantId.value) void refreshAll()
}, { immediate: true })
watch([search, statusFilter, pageSize], () => { page.value = 1 })
watch(() => filteredRows.value.length, length => { page.value = Math.min(page.value, Math.max(1, Math.ceil(length / pageSize.value))) })
watch([activeTab, page, pageSize, search, statusFilter], () => {
  if (scrollArea.value) scrollArea.value.scrollTop = 0
}, { flush: 'post' })
watch(pageRows, revealRows, { flush: 'post' })
onBeforeUnmount(cancelRequests)
</script>

<template>
  <div ref="root" class="tenants-page subscription-page">
    <section class="tenant-card" data-motion-enter>
      <div class="list-toolbar">
        <button class="toolbar-button" type="button" :aria-label="t('tenantSubscription.back')" :title="t('tenantSubscription.back')" @click="goBack"><i class="i-mdi-arrow-left" aria-hidden="true" /></button>
        <div class="subscription-tabs" role="tablist" :aria-label="t('tenantSubscription.tabsLabel')" @keydown="moveTab">
          <button v-for="tab in tabs" :id="`subscription-tab-${tab}`" :key="tab" type="button" role="tab" :aria-selected="activeTab === tab" aria-controls="subscription-panel" :tabindex="activeTab === tab ? 0 : -1" @click="selectTab(tab)">
            {{ t(`tenantSubscription.${tab}`) }}<span>{{ tabCount(tab) }}</span>
          </button>
        </div>
        <label class="tenant-search">
          <i class="i-mdi-magnify" aria-hidden="true" />
          <input v-model="search" type="search" :placeholder="t('tenantSubscription.searchPlaceholder')" :aria-label="t('tenantSubscription.searchPlaceholder')" @keydown.esc="search = ''" />
          <button v-if="search" type="button" :aria-label="t('tenantSubscription.clearSearch')" @click="search = ''"><i class="i-mdi-close" aria-hidden="true" /></button>
        </label>
        <el-select v-if="activeTab === 'subscribed'" v-model="statusFilter" class="status-filter" :aria-label="t('tenantSubscription.statusFilter')" :placeholder="t('tenantSubscription.allStatuses')">
          <el-option :label="t('tenantSubscription.allStatuses')" value="" />
          <el-option v-for="status in statusOptions" :key="status" :label="statusLabel(status)" :value="status" />
        </el-select>
        <div class="toolbar-actions">
          <button class="toolbar-button" type="button" :disabled="isRefreshing || !tenantId" :aria-label="t('tenantSubscription.refresh')" :title="t('tenantSubscription.refresh')" @click="refreshAll()"><i class="i-mdi-refresh" :class="{ 'subscription-spin': isRefreshing }" aria-hidden="true" /></button>
          <PrimaryBtn v-if="activeTab === 'subscribed'" class="tenant-import" :disabled="!tenantId || submitting" @click="selectTab('available')"><i class="i-mdi-plus" aria-hidden="true" />{{ t('tenantSubscription.subscribeNew') }}</PrimaryBtn>
          <PrimaryBtn v-else class="tenant-import" :disabled="!selectedCount || loading.available || !tenantId || submitting" @click="openSubscribe([...selected])">{{ t('tenantSubscription.subscribeSelected', { count: count(selectedCount) }) }}</PrimaryBtn>
        </div>
      </div>

      <div v-if="submitting || dialogStage === 'result'" class="operation-notice" :class="{ 'has-failures': !submitting && (!result || failedCount) }" role="status">
        <i :class="submitting ? 'i-mdi-loading subscription-spin' : result && !failedCount ? 'i-mdi-check-circle-outline' : 'i-mdi-information-outline'" aria-hidden="true" />
        <span>{{ submitting ? t('tenantSubscription.actionPending', { count: count(draft.length) }) : resultHeading }}</span>
        <button type="button" @click="dialogOpen = true">{{ t(`tenantSubscription.${submitting ? 'viewProgress' : 'viewResult'}`) }}</button>
      </div>
      <div v-if="selectedCount && activeTab === 'available'" class="search-context selection-context" role="status">
        <span>{{ t('tenantSubscription.selection', { count: count(selectedCount) }) }}</span>
        <button type="button" :disabled="submitting" @click="selected = new Set()">{{ t('tenantSubscription.clearSelection') }}</button>
      </div>
      <div v-if="activeError" class="list-error" role="alert">
        <i class="i-mdi-alert-circle-outline" aria-hidden="true" />
        <div><strong>{{ t('tenantSubscription.loadFailed') }}</strong><p>{{ subscriptionError(activeError) }}</p><p v-if="loaded[activeTab]">{{ t('tenantSubscription.retainedData') }}</p></div>
        <GhostBtn :loading="loading[activeTab]" @click="loadSource(activeTab)">{{ t('tenantSubscription.retry') }}</GhostBtn>
      </div>

      <div id="subscription-panel" class="table-stage" role="tabpanel" :aria-labelledby="`subscription-tab-${activeTab}`" :aria-busy="loading[activeTab]" tabindex="0">
        <div v-if="loading[activeTab]" class="refresh-track" aria-hidden="true"><span /></div>
        <div ref="scrollArea" class="table-scroll">
          <div v-if="!tenantId" class="tenant-empty">
            <span class="empty-icon"><i class="i-mdi-account-alert-outline" aria-hidden="true" /></span>
            <h3>{{ t('tenantSubscription.invalidTenant') }}</h3><p>{{ t('tenantSubscription.invalidTenantHint') }}</p>
            <GhostBtn @click="goBack">{{ t('tenantSubscription.back') }}</GhostBtn>
          </div>
          <template v-else>
            <table v-if="pageRows.length || (loading[activeTab] && !loaded[activeTab])" class="tenant-table subscription-table" :aria-label="t(`tenantSubscription.${activeTab}`)">
              <thead><tr>
                <th v-if="activeTab === 'available'" scope="col" class="checkbox-column"><input type="checkbox" :checked="allPageSelected" :indeterminate="somePageSelected" :disabled="!pageRows.length || submitting || loading.available" :aria-label="t('tenantSubscription.selectPage')" @change="togglePage(($event.target as HTMLInputElement).checked)" /></th>
                <th scope="col" class="key-column">{{ t('tenantSubscription.regionKey') }}</th>
                <th scope="col">{{ t('tenantSubscription.regionName') }}</th>
                <th v-if="activeTab === 'subscribed'" scope="col">{{ t('tenantSubscription.status') }}</th>
                <th v-if="activeTab === 'subscribed'" scope="col">{{ t('tenantSubscription.homeRegion') }}</th>
                <th v-else scope="col">{{ t('tenantSubscription.location') }}</th>
                <th scope="col" class="row-actions-column">{{ t('tenantSubscription.actions') }}</th>
              </tr></thead>
              <tbody v-if="loading[activeTab] && !loaded[activeTab]" aria-hidden="true">
                <tr v-for="index in 6" :key="index" class="skeleton-row"><td v-for="column in 5" :key="column"><span class="skeleton" /></td></tr>
              </tbody>
              <tbody v-else>
                <tr v-for="row in pageRows" :key="`${activeTab}-${row.key}`" :class="{ 'is-selected': activeTab === 'available' && selected.has(row.key) }" data-motion-row>
                  <td v-if="activeTab === 'available'" class="checkbox-column"><input type="checkbox" :checked="selected.has(row.key)" :disabled="submitting || loading.available" :aria-label="t('tenantSubscription.selectRegion', { region: row.name })" @change="toggleRow(row.key, ($event.target as HTMLInputElement).checked)" /></td>
                  <td class="key-column"><span class="region-key">{{ row.key }}</span></td>
                  <td>
                    <button v-if="activeTab === 'subscribed'" class="cell-link" type="button" @click="detailKey = row.key">{{ row.name }}</button><span v-else class="region-code">{{ row.name }}</span>
                    <span v-if="activeTab === 'subscribed' && row.location !== row.name" class="cell-secondary">{{ row.location }}</span>
                    <span v-if="checkErrors[row.key]" class="check-error" role="alert">{{ t('tenantSubscription.checkFailed') }} · {{ subscriptionError(checkErrors[row.key]) }}</span>
                  </td>
                  <td v-if="activeTab === 'subscribed'"><span class="tenant-status" :class="`subscription-status-${statusTone(row.status)}`" :title="row.status">{{ statusLabel(row.status) }}</span></td>
                  <td v-if="activeTab === 'subscribed'"><span :class="row.home ? 'home-region' : 'secondary-region'"><i v-if="row.home" class="i-mdi-home-outline" aria-hidden="true" />{{ t(`tenantSubscription.${row.home ? 'home' : 'secondary'}`) }}</span></td>
                  <td v-else class="region-location">{{ row.location }}</td>
                  <td class="row-actions-column"><div class="row-actions">
                    <template v-if="activeTab === 'subscribed'">
                      <button v-if="row.status !== 'READY'" class="toolbar-button" type="button" :disabled="checking.has(row.key) || loading.subscribed" :aria-busy="checking.has(row.key)" :aria-label="`${t('tenantSubscription.checkStatus')} · ${row.name}`" :title="t('tenantSubscription.checkStatus')" @click="checkStatus(row.key)"><i class="i-mdi-refresh" :class="{ 'subscription-spin': checking.has(row.key) }" aria-hidden="true" /></button>
                      <button class="toolbar-button" type="button" :aria-label="`${t('tenantSubscription.details')} · ${row.name}`" :title="t('tenantSubscription.details')" @click="detailKey = row.key"><i class="i-mdi-information-outline" aria-hidden="true" /></button>
                    </template>
                    <button v-else class="subscribe-row" type="button" :disabled="submitting || loading.available" @click="openSubscribe([row.key])"><i class="i-mdi-plus" aria-hidden="true" />{{ t('tenantSubscription.subscribe') }}</button>
                  </div></td>
                </tr>
              </tbody>
            </table>
            <div v-else-if="!activeError" class="tenant-empty">
              <span class="empty-icon"><i :class="search || statusFilter ? 'i-mdi-magnify' : 'i-mdi-earth'" aria-hidden="true" /></span>
              <h3>{{ t(`tenantSubscription.${search || statusFilter ? 'noMatches' : activeTab === 'subscribed' ? 'emptySubscribed' : 'emptyAvailable'}`) }}</h3>
              <p>{{ t(`tenantSubscription.${search || statusFilter ? 'noMatchesHint' : activeTab === 'subscribed' ? 'emptySubscribedHint' : 'emptyAvailableHint'}`) }}</p>
              <GhostBtn v-if="search || statusFilter" @click="clearFilters">{{ t('tenantSubscription.clearSearch') }}</GhostBtn>
              <GhostBtn v-else-if="activeTab === 'subscribed'" @click="selectTab('available')">{{ t('tenantSubscription.subscribeNew') }}</GhostBtn>
            </div>
          </template>
        </div>
        <span v-if="loading[activeTab]" class="sr-only" role="status">{{ t('tenantSubscription.loading') }}</span>
      </div>

      <footer class="list-footer">
        <div class="footer-context">
          <span v-if="tenantId" class="tenant-context" :title="t('tenantSubscription.tenantContext', { id: tenantId })">{{ t('tenantSubscription.tenantContext', { id: tenantId }) }}</span>
          <span v-if="search || statusFilter">{{ t('tenantSubscription.matches', { count: count(filteredRows.length) }) }}</span>
          <span v-else-if="summary">{{ t('tenantSubscription.summaryCount', { total: count(summary.totalRegions), subscribed: count(summary.subscribedRegions), available: count(summary.unsubscribedRegions) }) }}</span>
          <span v-else-if="loaded[activeTab]">{{ t('tenantSubscription.footerCount', { count: count(rows.length) }) }}</span>
          <button v-if="errors.summary" type="button" class="summary-retry" :disabled="loading.summary" :title="subscriptionError(errors.summary)" @click="loadSource('summary')"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('tenantSubscription.summaryFailed') }} · {{ t('tenantSubscription.retry') }}</button>
        </div>
        <el-pagination v-if="filteredRows.length" v-model:current-page="page" v-model:page-size="pageSize" background :total="filteredRows.length" :page-sizes="[10, 20, 50]" :pager-count="5" layout="sizes, prev, pager, next" />
      </footer>
    </section>

    <el-dialog :model-value="Boolean(detail)" :title="t('tenantSubscription.detailsTitle')" width="min(460px, calc(100vw - 32px))" class="subscription-dialog" @close="detailKey = ''">
      <template v-if="detail">
        <dl class="region-details">
          <div><dt>{{ t('tenantSubscription.regionKey') }}</dt><dd class="region-key">{{ detail.regionKey }}</dd></div>
          <div><dt>{{ t('tenantSubscription.regionName') }}</dt><dd>{{ detail.regionName }}</dd></div>
          <div><dt>{{ t('tenantSubscription.location') }}</dt><dd>{{ locationName(detail.regionName) }}</dd></div>
          <div><dt>{{ t('tenantSubscription.status') }}</dt><dd><span class="tenant-status" :class="`subscription-status-${statusTone(detail.status)}`">{{ statusLabel(detail.status) }}</span><small class="raw-status">{{ detail.status }}</small></dd></div>
          <div><dt>{{ t('tenantSubscription.homeRegion') }}</dt><dd>{{ t(`tenantSubscription.${detail.isHomeRegion ? 'home' : 'secondary'}`) }}</dd></div>
        </dl>
        <p v-if="checkErrors[detail.regionKey]" class="dialog-error" role="alert">{{ subscriptionError(checkErrors[detail.regionKey]) }}</p>
      </template>
      <template #footer><div class="dialog-actions">
        <GhostBtn @click="detailKey = ''">{{ t('tenantSubscription.close') }}</GhostBtn>
        <PrimaryBtn v-if="detail && detail.status !== 'READY'" :loading="checking.has(detail.regionKey)" :disabled="loading.subscribed" @click="checkStatus(detail.regionKey)">{{ t('tenantSubscription.checkStatus') }}</PrimaryBtn>
      </div></template>
    </el-dialog>

    <el-dialog v-model="dialogOpen" :title="dialogTitle" width="min(560px, calc(100vw - 32px))" class="subscription-dialog" :close-on-click-modal="false">
      <template v-if="dialogStage === 'confirm'">
        <p class="dialog-description">{{ t('tenantSubscription.confirmDescription', { count: count(draft.length) }) }}</p>
        <ul class="subscription-targets"><li v-for="row in draft" :key="row.key"><span class="region-key">{{ row.key }}</span><span>{{ row.name }}</span></li></ul>
        <p class="dialog-hint">{{ t('tenantSubscription.confirmHint') }}</p>
      </template>
      <template v-else>
        <div class="result-intro" :class="{ 'has-failures': dialogStage === 'result' && (!result || failedCount) }" role="status">
          <i :class="dialogStage === 'pending' ? 'i-mdi-loading subscription-spin' : result && !failedCount ? 'i-mdi-check-circle-outline' : 'i-mdi-information-outline'" aria-hidden="true" />
          <div><strong>{{ dialogStage === 'pending' ? t('tenantSubscription.submitting') : resultHeading }}</strong><p v-if="dialogStage === 'pending'">{{ t('tenantSubscription.pendingHint') }}</p><p v-else-if="!result">{{ t('tenantSubscription.resultUnknownHint') }}</p></div>
        </div>
        <p v-if="submitError" class="dialog-error" role="alert">{{ subscriptionError(submitError) }}</p>
        <ul class="subscription-results">
          <li v-for="row in draft" :key="row.key">
            <div class="result-region"><span class="region-key">{{ row.key }}</span><span>{{ row.name }}</span><span class="result-state" :class="resultDetails.get(row.key)?.success ? 'result-success' : resultDetails.has(row.key) ? 'result-failed' : ''">{{ t(`tenantSubscription.${dialogStage === 'pending' ? 'resultPending' : resultDetails.has(row.key) ? resultDetails.get(row.key)?.success ? 'resultSuccess' : 'resultFailed' : 'noResult'}`) }}</span></div>
            <p v-if="resultDetails.get(row.key)?.message">{{ resultDetails.get(row.key)?.message }}</p>
          </li>
        </ul>
        <p v-if="refreshIncomplete" class="dialog-hint" role="status">{{ t('tenantSubscription.refreshIncomplete') }}</p>
      </template>
      <template #footer><div class="dialog-actions">
        <template v-if="dialogStage === 'confirm'"><GhostBtn @click="dialogOpen = false">{{ t('tenantSubscription.cancel') }}</GhostBtn><PrimaryBtn @click="submit">{{ t('tenantSubscription.confirmSubscribe') }}</PrimaryBtn></template>
        <template v-else><GhostBtn @click="dialogOpen = false">{{ t('tenantSubscription.returnToList') }}</GhostBtn><PrimaryBtn v-if="dialogStage === 'result'" @click="viewSubscribed">{{ t('tenantSubscription.viewSubscribed') }}</PrimaryBtn></template>
      </div></template>
    </el-dialog>
  </div>
</template>

<style scoped lang="scss" src="./region-subscription.scss"></style>
