<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import ListCard from '@/components/ListCard.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import {
  getTenantAuditPage, getTenantAuditContext, isAuditTenantId, tenantAuditServerError, TenantAuditResponseError,
  type TenantAuditContext, type TenantAuditDates, type TenantAuditPage, type TenantAuditRow,
} from '@/api/tenantAudit'

const route = useRoute()
const router = useRouter()
const compact = useCompactViewport()
const { t, locale } = useI18n()
const tenantId = computed(() => isAuditTenantId(route.query.tenantId) ? route.query.tenantId : '')
const validContext = computed(() => !!tenantId.value && (route.query.cloudType == null || route.query.cloudType === '1'))
const contextKey = computed(() => JSON.stringify([route.path, route.query.tenantId, route.query.cloudType]))
const context = ref<TenantAuditContext | null>(null)
const metadataFailed = ref(false)
const contextLabel = computed(() => context.value?.name || t('tenantAudit.tenantId', { id: tenantId.value }))
const startDate = ref('')
const endDate = ref('')
const queriedDates = ref<TenantAuditDates | null>(null)
const page = ref(1)
const cache = ref<Record<number, TenantAuditPage>>({})
const tokens = ref<Record<number, string | null>>({ 1: null })
const pageOffsets = ref<Record<number, number>>({ 1: 0 })
const loading = ref(false)
const error = ref<unknown>(null)
const validationKey = ref('')
const failedPage = ref<number | null>(null)
const cleared = ref(false)
const rows = computed(() => cache.value[page.value]?.rows || [])
// The audit API has no row ID. Hash all fields, then distinguish identical
// records within the page, so refresh never substitutes a different row index.
const mobileRows = computed(() => {
  const duplicates = new Map<string, number>()
  return rows.value.map((row, index) => {
    const source = JSON.stringify([row.userName, row.ipAddress, row.eventType, row.clientEnv, row.eventTime, row.responseStatus])
    let first = 2166136261, second = 5381
    for (let position = 0; position < source.length; position++) {
      first = Math.imul(first ^ source.charCodeAt(position), 16777619)
      second = Math.imul(second, 33) ^ source.charCodeAt(position)
    }
    const hash = `${(first >>> 0).toString(36)}-${(second >>> 0).toString(36)}`
    const occurrence = duplicates.get(hash) || 0
    duplicates.set(hash, occurrence + 1)
    return { row, index, key: `${hash}-${occurrence}` }
  })
})
const knownPages = computed(() => Math.max(1, ...Object.keys(tokens.value).map(Number)))
const count = computed(() => Object.values(cache.value).reduce((sum, value) => sum + value.rows.length, 0))
const hasMore = computed(() => {
  const lastLoaded = Math.max(0, ...Object.keys(cache.value).map(Number))
  return !!cache.value[lastLoaded]?.nextToken
})
const offset = computed(() => pageOffsets.value[page.value] || 0)
const errorMessage = computed(() => !validContext.value ? t('tenantAudit.invalidTenant') : validationKey.value ? t(`tenantAudit.${validationKey.value}`) :
  error.value ? tenantAuditServerError(error.value) || t(error.value instanceof TenantAuditResponseError ? 'tenantAudit.responseInvalid' : 'tenantAudit.loadFailed') : '')
let disposed = false
let requestSequence = 0
let contextSequence = 0
let controller: AbortController | undefined
let metadataController: AbortController | undefined

function number(value: number): string { return new Intl.NumberFormat(locale.value).format(value) }
function displayDate(value: string): string {
  return new Intl.DateTimeFormat(locale.value, { year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'UTC' }).format(new Date(`${value}T00:00:00Z`))
}
function utcToday(): string { return new Date().toISOString().slice(0, 10) }
function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const time = Date.parse(`${value}T00:00:00Z`)
  return Number.isFinite(time) && new Date(time).toISOString().slice(0, 10) === value
}
function disabledDate(value: Date): boolean {
  const date = `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`
  const earliest = new Date(`${utcToday()}T00:00:00Z`)
  earliest.setUTCDate(earliest.getUTCDate() - 90)
  return date < earliest.toISOString().slice(0, 10) || date > utcToday()
}
function validation(): string {
  if (!startDate.value) return 'startRequired'
  const end = endDate.value || startDate.value
  if (!validDate(startDate.value) || !validDate(end)) return 'invalidDate'
  if (startDate.value > end) return 'dateOrder'
  const today = utcToday()
  if (startDate.value > today || end > today) return 'futureDate'
  const earliest = new Date(`${today}T00:00:00Z`)
  earliest.setUTCDate(earliest.getUTCDate() - 90)
  if (startDate.value < earliest.toISOString().slice(0, 10)) return 'dateTooOld'
  if ((Date.parse(end) - Date.parse(startDate.value)) / 86400000 > 90) return 'dateRangeExceeded'
  return ''
}
function stopReading() {
  requestSequence++
  controller?.abort()
  controller = undefined
  loading.value = false
}
function resetResults() {
  stopReading()
  cache.value = {}
  tokens.value = { 1: null }
  pageOffsets.value = { 1: 0 }
  page.value = 1
  error.value = null
  validationKey.value = ''
  failedPage.value = null
}
function clear() {
  resetResults()
  startDate.value = endDate.value = ''
  queriedDates.value = null
  cleared.value = true
  if (compact.value) void router.replace({ query: { ...route.query, auditStart: undefined, auditEnd: undefined, auditPage: undefined, auditCursors: undefined, auditOffsets: undefined, mobileRecord: undefined }, hash: route.hash })
}
function persistPage(clearDetail = false) {
  if (!compact.value || !queriedDates.value) return
  void router.replace({ query: { ...route.query, auditStart: queriedDates.value.startDate, auditEnd: queriedDates.value.endDate,
    auditPage: page.value > 1 ? String(page.value) : undefined,
    auditCursors: Object.keys(tokens.value).length > 1 ? JSON.stringify(tokens.value) : undefined,
    auditOffsets: Object.keys(pageOffsets.value).length > 1 ? JSON.stringify(pageOffsets.value) : undefined,
    mobileRecord: clearDetail ? undefined : route.query.mobileRecord }, hash: route.hash })
}
function restorePage(): number {
  const target = Number(route.query.auditPage || 1)
  if (!Number.isSafeInteger(target) || target < 1) return 1
  if (typeof route.query.auditCursors !== 'string') return 1
  try {
    const cursors: unknown = JSON.parse(route.query.auditCursors)
    const offsets: unknown = typeof route.query.auditOffsets === 'string' ? JSON.parse(route.query.auditOffsets) : {}
    if (!cursors || typeof cursors !== 'object' || Array.isArray(cursors) || !offsets || typeof offsets !== 'object' || Array.isArray(offsets)) return 1
    const entries = Object.entries(cursors).sort(([a], [b]) => Number(a) - Number(b))
    // Accept only a continuous chain of cursors already obtained from the API.
    if (entries.some(([key, value], index) => String(index + 1) !== key || (index === 0 ? value !== null : typeof value !== 'string' || !value))) return 1
    if (!(target in cursors)) return 1
    const restoredOffsets: Record<number, number> = { 1: 0 }
    for (const [key] of entries) {
      const value = (offsets as Record<string, unknown>)[key]
      if (key !== '1' && (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0)) return 1
      restoredOffsets[Number(key)] = key === '1' ? 0 : value as number
    }
    tokens.value = Object.fromEntries(entries) as Record<number, string | null>
    pageOffsets.value = restoredOffsets
    return target
  } catch { return 1 }
}
function query() {
  if (!validContext.value || loading.value || disposed) return
  validationKey.value = validation()
  if (validationKey.value) return
  resetResults()
  queriedDates.value = { startDate: startDate.value, endDate: endDate.value || startDate.value }
  cleared.value = false
  persistPage(true)
  void loadPage(1)
}
async function loadPage(target: number) {
  if (disposed || !validContext.value || loading.value || !queriedDates.value || !Number.isSafeInteger(target) || target < 1 || !(target in tokens.value)) return
  error.value = null
  validationKey.value = ''
  failedPage.value = null
  const pageChanged = target !== page.value
  if (cache.value[target]) { page.value = target; persistPage(pageChanged); return }
  const sequence = ++requestSequence
  const key = contextKey.value
  const current = new AbortController()
  controller?.abort()
  controller = current
  loading.value = true
  try {
    const result = await getTenantAuditPage(tenantId.value, { ...queriedDates.value }, tokens.value[target] || null, current.signal)
    if (disposed || current.signal.aborted || sequence !== requestSequence || key !== contextKey.value) return
    // A repeated cursor cannot expose another page; keep the last good page and show an error.
    if (result.nextToken && Object.entries(tokens.value).some(([key, value]) => Number(key) !== target + 1 && value === result.nextToken)) throw new TenantAuditResponseError()
    // A refreshed cursor can invalidate later pages; do not retain an old chain.
    if ((tokens.value[target + 1] || null) !== result.nextToken) {
      for (const key of Object.keys(tokens.value).map(Number)) if (key > target) {
        delete tokens.value[key]; delete pageOffsets.value[key]; delete cache.value[key]
      }
    }
    cache.value[target] = result
    if (result.nextToken) { tokens.value[target + 1] = result.nextToken; pageOffsets.value[target + 1] = (pageOffsets.value[target] || 0) + result.rows.length }
    page.value = target
    persistPage(pageChanged)
  } catch (cause) {
    if (!disposed && !current.signal.aborted && sequence === requestSequence && key === contextKey.value) {
      error.value = cause
      failedPage.value = target
    }
  } finally {
    if (!disposed && sequence === requestSequence) loading.value = false
  }
}
async function readContext() {
  const sequence = ++contextSequence
  const key = contextKey.value
  metadataController?.abort()
  const current = new AbortController()
  metadataController = current
  try {
    const value = await getTenantAuditContext(tenantId.value, current.signal)
    if (disposed || current.signal.aborted || sequence !== contextSequence || key !== contextKey.value) return
    context.value = value
    metadataFailed.value = !value
  } catch { if (!disposed && !current.signal.aborted && sequence === contextSequence && key === contextKey.value) metadataFailed.value = true }
}
function goBack() {
  const back = window.history.state?.back
  if (typeof back === 'string' && /^\/tenants\/(list|regionList)(?:\?|$)/.test(back)) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: '1' } })
}
function unusualResponse(row: TenantAuditRow): boolean { return !!row.responseStatus && row.responseStatus !== '-' && row.responseStatus !== '200' }
function rowClass({ row }: { row: TenantAuditRow }): string { return unusualResponse(row) ? 'tenant-audit-response-row' : '' }
watch(contextKey, () => {
  resetResults()
  contextSequence++
  metadataController?.abort()
  context.value = null
  metadataFailed.value = false
  queriedDates.value = null
  cleared.value = false
  startDate.value = typeof route.query.auditStart === 'string' ? route.query.auditStart : utcToday()
  endDate.value = typeof route.query.auditEnd === 'string' ? route.query.auditEnd : startDate.value
  if (!validContext.value) return
  void readContext()
  validationKey.value = validation()
  if (validationKey.value) return
  queriedDates.value = { startDate: startDate.value, endDate: endDate.value || startDate.value }
  const target = restorePage()
  page.value = target
  void loadPage(target)
}, { immediate: true })
onBeforeUnmount(() => {
  disposed = true
  contextSequence++
  stopReading()
  metadataController?.abort()
  cache.value = {}
})

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<TenantAuditRow>
</script>

<template>
  <div class="tenant-audit-page">
    <ListCard class="tenant-audit-card" :aria-label="t('tenantAudit.label')">
      <template #toolbar>
        <PageBackButton :title="t('tenantAudit.back')" @click="goBack" />
        <div class="tenant-audit-context" :title="metadataFailed ? t('tenantAudit.metadataFailed') : contextLabel"><strong>{{ tenantId ? contextLabel : t('tenantAudit.tenant') }}</strong><span v-if="context?.region">{{ context.region }}</span></div>
        <form class="tenant-audit-filters" data-page-error-anchor :title="t('tenantAudit.dateHint')" @submit.prevent="query">
          <label for="tenant-audit-start">{{ t('tenantAudit.startDate') }}</label>
          <el-date-picker id="tenant-audit-start" v-model="startDate" type="date" value-format="YYYY-MM-DD" :format="locale === 'en' ? 'MM/DD/YYYY' : 'YYYY-MM-DD'" :placeholder="t('tenantAudit.startPlaceholder')" :aria-label="t('tenantAudit.startDate')" :disabled="loading || !validContext" :disabled-date="disabledDate" popper-class="tenant-audit-calendar" />
          <label for="tenant-audit-end">{{ t('tenantAudit.endDate') }}</label>
          <el-date-picker id="tenant-audit-end" v-model="endDate" type="date" value-format="YYYY-MM-DD" :format="locale === 'en' ? 'MM/DD/YYYY' : 'YYYY-MM-DD'" :placeholder="t('tenantAudit.endPlaceholder')" :aria-label="t('tenantAudit.endDate')" :disabled="loading || !validContext" :disabled-date="disabledDate" popper-class="tenant-audit-calendar" />
          <PrimaryBtn type="submit" :loading="loading" :disabled="!validContext">{{ t('tenantAudit.query') }}</PrimaryBtn>
          <GhostBtn :disabled="!validContext" :title="t('tenantAudit.clearHint')" @click="clear">{{ t('tenantAudit.clear') }}</GhostBtn>
        </form>
      </template>
      <div v-if="errorMessage && (!validContext || validationKey)" class="tenant-audit-error" role="alert">{{ errorMessage }}</div>
      <PageErrorNotice v-else-if="errorMessage"><span>{{ errorMessage }}<br v-if="failedPage && Object.keys(cache).length" /><span v-if="failedPage && Object.keys(cache).length">{{ t('tenantAudit.failedPage', { page: number(failedPage) }) }}</span></span><GhostBtn v-if="error && failedPage" :loading="loading" @click="loadPage(failedPage)">{{ t('tenantAudit.retry') }}</GhostBtn></PageErrorNotice>
      <div class="tenant-audit-table-wrap" :aria-busy="loading">
        <MobileRecordList v-if="compact" class="tenant-audit-mobile-list" drilldown :list-id="`audit-${tenantId}`" :record-keys="mobileRows.map(item => item.key)" :loading="loading">
          <MobileRecordCard v-for="item in mobileRows" :key="item.key" :record-key="item.key" :summary-title="item.row.eventType || '—'" :summary-meta="[item.row.userName, item.row.eventTime].filter(Boolean).join(' · ')" :summary-status="item.row.responseStatus || '—'" :summary-tone="unusualResponse(item.row) ? 'danger' : item.row.responseStatus === '200' ? 'success' : 'neutral'">
            <template #identity><h2 class="mobile-record-title">{{ item.row.eventType || '—' }}</h2><span class="mobile-record-subtitle">{{ item.row.eventTime || '—' }}</span></template>
            <dl class="mobile-record-fields"><div><dt>{{ t('tenantAudit.index') }}</dt><dd>{{ number(offset + item.index + 1) }}</dd></div><div><dt>{{ t('tenantAudit.response') }}</dt><dd :class="{ 'tenant-audit-response': unusualResponse(item.row) }">{{ item.row.responseStatus || '—' }}</dd></div><div class="mobile-record-wide"><dt>{{ t('tenantAudit.username') }}</dt><dd>{{ item.row.userName || '—' }}</dd></div><div class="mobile-record-wide"><dt>{{ t('tenantAudit.sourceIp') }}</dt><dd>{{ item.row.ipAddress || '—' }}</dd></div><div class="mobile-record-wide"><dt>{{ t('tenantAudit.client') }}</dt><dd>{{ item.row.clientEnv || '—' }}</dd></div><div class="mobile-record-wide"><dt>{{ t('tenantAudit.eventTime') }}</dt><dd>{{ item.row.eventTime || '—' }}<span class="mobile-record-subtitle">{{ t('tenantAudit.timeHint') }}</span></dd></div></dl>
          </MobileRecordCard>
          <div v-if="!mobileRows.length" class="tenant-audit-empty" role="status"><strong>{{ t(loading ? 'tenantAudit.loading' : errorMessage ? 'tenantAudit.loadFailed' : queriedDates ? 'tenantAudit.empty' : 'tenantAudit.idle') }}</strong><span v-if="!loading && !errorMessage">{{ t(cleared ? 'tenantAudit.clearedHint' : 'tenantAudit.emptyHint') }}</span></div>
        </MobileRecordList>
        <el-table v-else :data="rows" height="100%" v-loading="loading" :element-loading-text="t('tenantAudit.loading')" :row-class-name="rowClass">
          <el-table-column :label="t('tenantAudit.index')" width="74"><template #default="{ $index }">{{ number(offset + $index + 1) }}</template></el-table-column>
          <el-table-column :label="t('tenantAudit.username')" min-width="185"><template #default="{ row }"><span>{{ row.userName || '—' }}</span></template></el-table-column>
          <el-table-column :label="t('tenantAudit.sourceIp')" min-width="210"><template #default="{ row }"><span>{{ row.ipAddress || '—' }}</span></template></el-table-column>
          <el-table-column :label="t('tenantAudit.eventType')" min-width="205"><template #default="{ row }"><span>{{ row.eventType || '—' }}</span></template></el-table-column>
          <el-table-column :label="t('tenantAudit.client')" min-width="210" show-overflow-tooltip><template #default="{ row }"><span>{{ row.clientEnv || '—' }}</span></template></el-table-column>
          <el-table-column :label="t('tenantAudit.eventTime')" min-width="170"><template #header><span :title="t('tenantAudit.timeHint')">{{ t('tenantAudit.eventTime') }}</span></template><template #default="{ row }">{{ row.eventTime || '—' }}</template></el-table-column>
          <el-table-column :label="t('tenantAudit.response')" width="110"><template #default="{ row }"><span :class="{ 'tenant-audit-response': unusualResponse(row) }">{{ row.responseStatus || '—' }}</span></template></el-table-column>
          <template #empty><div class="tenant-audit-empty"><strong>{{ t(loading ? 'tenantAudit.loading' : errorMessage ? 'tenantAudit.loadFailed' : queriedDates ? 'tenantAudit.empty' : 'tenantAudit.idle') }}</strong><span v-if="!loading && !errorMessage">{{ t(cleared ? 'tenantAudit.clearedHint' : 'tenantAudit.emptyHint') }}</span></div></template>
        </el-table>
      </div>
      <template #footer>
        <PagePagination embedded :aria-label="t('tenantAudit.pagination')" :current-page="page" :page-size="1" :page-count="knownPages" :disabled="loading || !validContext || !queriedDates" @current-change="loadPage">
          <span class="tenant-audit-count" aria-live="polite">{{ t(hasMore ? 'tenantAudit.loadedWithMore' : 'tenantAudit.loaded', { count: number(count) }) }}</span>
          <span class="tenant-audit-range" :title="t('tenantAudit.dateHint')">{{ queriedDates ? t('tenantAudit.dateRange', { start: displayDate(queriedDates.startDate), end: displayDate(queriedDates.endDate) }) : t('tenantAudit.dateHint') }}</span>
        </PagePagination>
      </template>
    </ListCard>
  </div>
</template>

<style lang="scss">
.tenant-audit-page { display: flex; width: 100%; height: 100%; min-width: 0; min-height: 0; color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
.tenant-audit-page {
  .tenant-audit-card { flex: 1; min-width: 0; }
  .tenant-audit-card > .toolbar { padding-bottom: 12px; border-bottom: 1px solid var(--border); }
  .tenant-audit-card > .body { display: flex; flex: 1; flex-direction: column; min-height: 160px; padding-top: 0; padding-bottom: 0; overflow: hidden; }
  .tenant-audit-card > .footer { flex: none; align-items: center; flex-wrap: wrap; gap: 10px 16px; border-top: 1px solid var(--border); }
  .tenant-audit-context { display: grid; gap: 2px; min-width: 110px; max-width: 220px; }
  .tenant-audit-context strong { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tenant-audit-context span { color: var(--text-secondary); font-size: var(--font-size-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tenant-audit-filters { display: flex; flex: 1; align-items: center; justify-content: flex-end; flex-wrap: wrap; gap: 8px 10px; margin-left: auto; }
  .tenant-audit-filters label { color: var(--text-primary); font-size: var(--font-size-body); white-space: nowrap; }
  .tenant-audit-filters .el-date-editor { width: 158px; flex: 0 1 158px; }
  .tenant-audit-filters .btn { min-height: 36px; padding: 8px 12px; }
  .tenant-audit-filters .el-input__inner { color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
  .tenant-audit-error { display: flex; flex: none; align-items: center; justify-content: space-between; gap: 12px; padding: 10px 12px; margin: 10px 0; border-radius: var(--r-sm); background: var(--status-danger-bg); color: var(--status-danger); overflow-wrap: anywhere; }
  .tenant-audit-table-wrap { position: relative; flex: 1; min-width: 0; min-height: 140px; }
  .tenant-audit-mobile-list { position: absolute; inset: 0; overflow: auto; overscroll-behavior: contain; }
  .el-table { position: absolute; inset: 0; color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
  .el-table .el-table__cell { padding: 12px 0; }
  .el-table .cell { color: var(--text-primary); font-size: var(--font-size-body); line-height: 1.47; overflow-wrap: anywhere; }
  .el-table th.el-table__cell { background: var(--bg-card); color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; }
  .tenant-audit-response-row { --el-table-tr-bg-color: var(--status-danger-bg); }
  .tenant-audit-response { color: var(--status-danger); }
  .tenant-audit-empty { display: grid; gap: 8px; padding: 40px 12px; line-height: 1.6; }
  .tenant-audit-empty strong { color: var(--text-primary); font-size: var(--font-size-section); font-weight: 600; }
  .tenant-audit-empty span { color: var(--text-secondary); font-size: var(--font-size-secondary); }
  .tenant-audit-count { margin-right: auto; }
  .tenant-audit-count, .tenant-audit-range { color: var(--text-secondary); font-size: var(--font-size-secondary); }
}
.tenant-audit-calendar { font-family: var(--sans); color: var(--text-primary); }
.tenant-audit-calendar .el-date-table, .tenant-audit-calendar .el-month-table, .tenant-audit-calendar .el-year-table { color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
.tenant-audit-calendar .el-date-picker__header-label { color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-section); font-weight: 600; }
@media (max-width: 1100px) { .tenant-audit-page .tenant-audit-filters { justify-content: flex-start; flex-basis: 100%; margin-left: 0; } }
@media (max-width: 620px) {
  .tenant-audit-page .tenant-audit-filters { display: grid; grid-template-columns: max-content minmax(0, 1fr); }
  .tenant-audit-page .tenant-audit-filters .el-date-editor { width: 100%; }
  .tenant-audit-page .tenant-audit-count { width: 100%; }
  .tenant-audit-page .tenant-audit-range { margin-right: auto; }
}
</style>
