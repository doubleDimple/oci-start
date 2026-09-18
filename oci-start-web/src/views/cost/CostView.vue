<script setup lang="ts">
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import type { TableInstance } from 'element-plus'
import { costCategory, isCostDate, isCostTenantId, ociCostError, queryOciCost, type OciCostError, type OciCostRow } from '@/api/ociCost'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import CostTrendChart from './CostTrendChart.vue'

type Preset = 'today' | 'month' | 'custom'
const compact = useCompactViewport()
const route = useRoute()
const router = useRouter()
const { t, locale, n, te } = useI18n()
const presets: Preset[] = ['today', 'month', 'custom']
const preset = ref<Preset>('month')
const tenantId = computed(() => typeof route.query.tenantId === 'string' ? route.query.tenantId : '')
const validTenant = computed(() => isCostTenantId(tenantId.value))
const startDate = ref('')
const endDate = ref('')
const rows = ref<OciCostRow[]>([])
const state = ref<'idle' | 'loading' | 'ready' | 'cancelled' | 'error'>('idle')
const problem = ref<OciCostError | null>(null)
const validationKey = ref('')
const positiveOnly = ref(false)
const page = ref(1)
const pageSize = ref(20)
const table = ref<TableInstance>()
let generation = 0
let controller: AbortController | undefined
let disposed = false

const busy = computed(() => state.value === 'loading')
const hasRecords = computed(() => state.value === 'ready' && rows.value.length > 0)
const error = computed(() => !validTenant.value ? t('ociCost.errors.invalidTenant')
  : validationKey.value ? t(`ociCost.errors.${validationKey.value}`)
    : problem.value ? problem.value.detail || t(`ociCost.errors.${problem.value.key}`) : '')
const filteredRows = computed(() => positiveOnly.value ? rows.value.filter(row => row.cost > 0) : rows.value)
const pageRows = computed(() => filteredRows.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
function costRecordKey(row: OciCostRow) {
  const identity = (item: OciCostRow) => JSON.stringify([item.day, item.resourceType, item.skuName, item.resourceId, item.cost])
  const key = identity(row)
  const occurrence = rows.value.slice(0, rows.value.indexOf(row)).filter(item => identity(item) === key).length
  return `${key}:${occurrence}`
}
const mobileCostRows = computed(() => compact.value && typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith(`cost-${tenantId.value}:`) ? filteredRows.value : pageRows.value)
const totals = computed(() => {
  const amounts = { total: 0, compute: 0, storage: 0, network: 0, other: 0 }
  for (const row of rows.value) {
    amounts.total += row.cost
    amounts[costCategory(row.resourceType)] += row.cost
  }
  return amounts
})
const metrics = computed(() => [
  { key: 'total', label: t('ociCost.categories.total'), value: totals.value.total },
  { key: 'compute', label: t('ociCost.categories.compute'), value: totals.value.compute },
  { key: 'storage', label: t('ociCost.categories.storage'), value: totals.value.storage },
  { key: 'network', label: t('ociCost.categories.network'), value: totals.value.network },
  { key: 'other', label: t('ociCost.categories.other'), value: totals.value.other },
])
const rangeLabel = computed(() => isCostDate(startDate.value) && isCostDate(endDate.value)
  ? t('ociCost.selectedRange', { start: formatDate(startDate.value), end: formatDate(endDate.value) }) : '')
const emptyText = computed(() => busy.value ? t('ociCost.loading') : hasRecords.value && positiveOnly.value
  ? t('ociCost.noPositive') : state.value === 'ready' ? t('ociCost.noRecords') : t('ociCost.queryHint'))

function dateYmd(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function choosePreset(next: Preset) {
  preset.value = next
  if (next === 'custom') return
  // Match the legacy presets: local-calendar today, or the first of this month through today.
  const today = new Date()
  startDate.value = dateYmd(next === 'today' ? today : new Date(today.getFullYear(), today.getMonth(), 1))
  endDate.value = dateYmd(today)
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', {
    year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'UTC',
  }).format(new Date(`${value}T00:00:00Z`))
}

function money(value: number, digits: number) {
  return new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', {
    style: 'currency', currency: 'USD', minimumFractionDigits: digits, maximumFractionDigits: digits,
  }).format(value)
}

function resourceType(value: string) {
  const key = `ociCost.resourceTypes.${value.toLowerCase()}`
  return te(key) ? t(key) : value
}

function invalidate() {
  generation++
  controller?.abort()
  controller = undefined
  rows.value = []
  state.value = 'idle'
  problem.value = null
  validationKey.value = ''
  page.value = 1
}

function cancelQuery() {
  invalidate()
  state.value = 'cancelled'
}

async function query() {
  if (busy.value || !validTenant.value) return
  validationKey.value = ''
  if (!isCostDate(startDate.value) || !isCostDate(endDate.value)) { validationKey.value = 'invalidDate'; return }
  if (startDate.value > endDate.value) { validationKey.value = 'reversedDates'; return }
  const request = { tenantId: tenantId.value, startDate: startDate.value, endDate: endDate.value }
  invalidate()
  const current = generation
  const activeController = new AbortController()
  controller = activeController
  state.value = 'loading'
  try {
    const result = await queryOciCost(request, activeController.signal)
    if (disposed || current !== generation || activeController.signal.aborted) return
    rows.value = result
    state.value = 'ready'
  } catch (cause) {
    if (disposed || current !== generation || activeController.signal.aborted) return
    problem.value = ociCostError(cause)
    state.value = 'error'
  } finally {
    if (current === generation) controller = undefined
  }
}

function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push({ path: '/tenants/list', query: typeof route.query.cloudType === 'string' ? { cloudType: route.query.cloudType } : {} })
}

choosePreset('month')
watch([tenantId, startDate, endDate], invalidate, { flush: 'sync' })
watch([positiveOnly, pageSize], () => { page.value = 1 })
watch(page, async () => { await nextTick(); table.value?.setScrollTop(0) })
watch([locale, hasRecords], async () => { await nextTick(); table.value?.doLayout() })
onBeforeUnmount(() => { disposed = true; generation++; controller?.abort() })
</script>

<template>
  <section class="cost-page" :aria-label="t('ociCost.title')">
    <form class="cost-query" @submit.prevent="query">
      <PageBackButton @click="back" />
      <div class="range-control">
        <span id="cost-range-label" class="field-label">{{ t('ociCost.timeRange') }}</span>
        <div class="time-presets" role="group" aria-labelledby="cost-range-label">
          <button v-for="value in presets" :key="value" type="button" :class="{ active: preset === value }" :aria-pressed="preset === value" @click="choosePreset(value)">{{ t(`ociCost.${value}`) }}</button>
        </div>
      </div>
      <template v-if="preset === 'custom'">
        <div class="date-field"><label for="cost-start-date" class="sr-only">{{ t('ociCost.startDate') }}</label><el-date-picker id="cost-start-date" v-model="startDate" type="date" value-format="YYYY-MM-DD" format="YYYY-MM-DD" :placeholder="t('ociCost.startPlaceholder')" :aria-label="t('ociCost.startDate')" popper-class="oci-cost-calendar" /></div>
        <div class="date-field"><label for="cost-end-date" class="sr-only">{{ t('ociCost.endDate') }}</label><el-date-picker id="cost-end-date" v-model="endDate" type="date" value-format="YYYY-MM-DD" format="YYYY-MM-DD" :placeholder="t('ociCost.endPlaceholder')" :aria-label="t('ociCost.endDate')" popper-class="oci-cost-calendar" /></div>
      </template>
      <div class="query-actions" data-page-error-anchor>
        <GhostBtn v-if="busy" @click="cancelQuery">{{ t('ociCost.cancelQuery') }}</GhostBtn>
        <PrimaryBtn type="submit" :loading="busy" :disabled="!validTenant"><i class="i-mdi-magnify" aria-hidden="true" />{{ t('ociCost.query') }}</PrimaryBtn>
      </div>
    </form>

    <div class="cost-body">
      <div class="query-context"><span v-if="validTenant">{{ t('ociCost.tenant', { id: tenantId }) }}</span><span v-if="rangeLabel">{{ rangeLabel }}</span><span>{{ t('ociCost.dailyUsd') }}</span></div>
      <PageErrorNotice v-if="error">{{ error }}</PageErrorNotice>
      <dl class="cost-metrics" :aria-busy="busy">
        <div v-for="metric in metrics" :key="metric.key" class="metric-item" :class="{ 'metric-total': metric.key === 'total' }">
          <dt>{{ metric.label }}</dt><dd :title="hasRecords ? money(metric.value, 4) : undefined">{{ hasRecords ? money(metric.value, 4) : '—' }}</dd>
        </div>
      </dl>

      <div v-if="!hasRecords" class="cost-state" role="status" :aria-busy="busy">
        <span v-if="busy" class="query-spinner" aria-hidden="true" />
        <p>{{ busy ? t('ociCost.loading') : state === 'ready' ? t('ociCost.noRecords') : state === 'cancelled' ? t('ociCost.cancelled') : error ? '—' : t('ociCost.queryHint') }}</p>
        <p v-if="state === 'ready'" class="state-note">{{ t('ociCost.noRecordsHint') }}</p>
      </div>

      <template v-else>
        <section class="chart-section" :aria-label="t('ociCost.trend')">
          <CostTrendChart :rows="rows"><template #heading><h2 class="section-title">{{ t('ociCost.trend') }}</h2></template></CostTrendChart>
        </section>
        <section class="details-section" :aria-label="t('ociCost.details')">
          <div class="detail-toolbar">
            <h2 class="section-title">{{ t('ociCost.details') }}</h2>
            <el-checkbox v-model="positiveOnly">{{ t('ociCost.positiveOnly') }}</el-checkbox>
          </div>
          <p v-if="positiveOnly" class="filter-hint">{{ t('ociCost.filterHint') }}</p>
          <MobileRecordList v-if="compact" drilldown :list-id="`cost-${tenantId}`" :record-keys="filteredRows.map(costRecordKey)" :loading="busy">
            <MobileRecordCard v-for="row in mobileCostRows" :key="costRecordKey(row)" :record-key="costRecordKey(row)" :summary-title="row.skuName || resourceType(row.resourceType) || '—'" :summary-meta="formatDate(row.day)" :summary-status="money(row.cost, 6)">
              <template #identity><h3 class="mobile-record-title">{{ row.skuName || resourceType(row.resourceType) || '—' }}</h3></template>
              <dl class="mobile-record-fields">
                <div><dt>{{ t('ociCost.columns.day') }}</dt><dd>{{ formatDate(row.day) }}</dd></div>
                <div><dt>{{ t('ociCost.columns.cost') }}</dt><dd>{{ money(row.cost, 6) }}</dd></div>
                <div class="mobile-record-wide"><dt>{{ t('ociCost.columns.resourceType') }}</dt><dd>{{ resourceType(row.resourceType) || '—' }}</dd></div>
                <div class="mobile-record-wide"><dt>{{ t('ociCost.columns.sku') }}</dt><dd>{{ row.skuName || '—' }}</dd></div>
                <div class="mobile-record-wide"><dt>{{ t('ociCost.columns.resourceId') }}</dt><dd>{{ row.resourceId || '—' }}</dd></div>
              </dl>
            </MobileRecordCard>
            <p v-if="!mobileCostRows.length" role="status">{{ emptyText }}</p>
          </MobileRecordList>
          <el-table v-else ref="table" :data="pageRows" class="cost-table" table-layout="fixed" max-height="460" :empty-text="emptyText" header-cell-class-name="cost-header-cell" scrollbar-always-on>
            <el-table-column prop="day" :label="t('ociCost.columns.day')" width="136" align="left" header-align="left" show-overflow-tooltip><template #default="{ row }">{{ formatDate(row.day) }}</template></el-table-column>
            <el-table-column prop="resourceType" :label="t('ociCost.columns.resourceType')" width="166" align="left" header-align="left" show-overflow-tooltip><template #default="{ row }">{{ resourceType(row.resourceType) || '—' }}</template></el-table-column>
            <el-table-column prop="skuName" :label="t('ociCost.columns.sku')" min-width="280" align="left" header-align="left" show-overflow-tooltip><template #default="{ row }">{{ row.skuName || '—' }}</template></el-table-column>
            <el-table-column prop="resourceId" :label="t('ociCost.columns.resourceId')" min-width="320" align="left" header-align="left" show-overflow-tooltip><template #default="{ row }">{{ row.resourceId || '—' }}</template></el-table-column>
            <el-table-column prop="cost" :label="t('ociCost.columns.cost')" width="190" fixed="right" align="right" header-align="right" show-overflow-tooltip><template #default="{ row }"><span class="cost-value">{{ money(row.cost, 6) }}</span></template></el-table-column>
          </el-table>
        </section>
      </template>
    </div>
    <PagePagination v-if="hasRecords" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50, 100]" :total="filteredRows.length">
      <span>{{ positiveOnly ? t('ociCost.filteredCount', { count: n(filteredRows.length), total: n(rows.length) }) : t('ociCost.count', { count: n(rows.length) }) }}</span>
    </PagePagination>
  </section>
</template>

<style scoped>
.cost-page { display: flex; flex-direction: column; width: 100%; height: 100%; min-width: 0; min-height: 0; overflow: hidden; border: 1px solid var(--border); border-radius: var(--r-card); background: var(--bg-card); box-shadow: var(--shadow-card); color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
.cost-query { display: flex; flex: none; align-items: center; flex-wrap: wrap; gap: 10px; padding: 12px 18px; border-bottom: 1px solid var(--border); }
.range-control { display: flex; align-items: center; gap: 10px; min-width: 0; }
.field-label { flex: none; color: var(--text-primary); font-size: var(--font-size-body); white-space: nowrap; }
.time-presets { display: flex; align-items: center; gap: 3px; min-height: 36px; padding: 3px; border-radius: var(--r-pill); background: var(--bg-search); }
.time-presets button { border: 0; border-radius: var(--r-pill); min-height: 30px; padding: 5px 11px; background: transparent; color: var(--text-primary); font: inherit; white-space: nowrap; cursor: pointer; }
.time-presets button.active { background: var(--bg-card); color: var(--text-primary); font-weight: 600; box-shadow: var(--shadow-card); }
.time-presets button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
.date-field { flex: 0 1 168px; min-width: 150px; }
.date-field :deep(.el-date-editor.el-input) { width: 100%; height: 36px; }
.query-actions { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; margin-left: auto; }
.query-actions :deep(.btn:not(.page-back-button)) { min-height: 36px; padding: 8px 13px; }
.cost-body { flex: 1; min-width: 0; min-height: 0; overflow: auto; overscroll-behavior: contain; padding: 0 18px 18px; }
.query-context { display: flex; align-items: center; flex-wrap: wrap; gap: 6px 18px; padding: 12px 0; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.query-error { margin: 0 0 14px; }
.cost-metrics { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 14px 24px; margin: 0; padding: 4px 0 18px; border-bottom: 1px solid var(--border); }
.metric-item { min-width: 0; padding-left: 18px; border-left: 1px solid var(--border); }
.metric-item:first-child { border-left: 0; padding-left: 0; }
.metric-item dt { margin: 0; color: var(--text-primary); font-size: var(--font-size-body); white-space: nowrap; }
.metric-item dd { margin: 6px 0 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-primary); font-size: var(--font-size-dialog-title); font-weight: 600; font-variant-numeric: tabular-nums; }
.metric-total dt { font-weight: 600; }
.cost-state { display: grid; justify-items: center; align-content: center; min-height: 230px; gap: 14px; padding: 40px 20px; text-align: center; }
.cost-state p { margin: 0; }
.state-note { max-width: 620px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.query-spinner { width: 24px; height: 24px; border: 2px solid var(--border); border-top-color: var(--brand); border-radius: 50%; animation: cost-spin 1s linear infinite; }
.chart-section { min-width: 0; padding: 18px 0; border-bottom: 1px solid var(--border); }
.section-title { flex: none; margin: 0; color: var(--text-primary); font-size: var(--font-size-section); font-weight: 600; }
.details-section { min-width: 0; padding-top: 16px; }
.detail-toolbar { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px 18px; margin-bottom: 12px; }
.detail-toolbar :deep(.el-checkbox) { height: auto; min-height: 28px; max-width: 100%; }
.detail-toolbar :deep(.el-checkbox__label) { white-space: normal; }
.filter-hint { margin: 0 0 12px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.cost-table { width: 100%; font-family: var(--sans); font-size: var(--font-size-body); --el-table-header-bg-color: var(--bg-search); --el-table-header-text-color: var(--text-primary); --el-table-text-color: var(--text-primary); }
.cost-table :deep(.el-table__cell) { padding-block: 12px; }
.cost-table :deep(.el-table__cell > .cell) { padding-inline: 14px; font-family: var(--sans); font-size: var(--font-size-body); line-height: 22px; }
.cost-table :deep(th.cost-header-cell) { background: var(--bg-search); }
.cost-table :deep(th.cost-header-cell > .cell) { color: var(--text-primary); font-weight: 600; white-space: nowrap; }
.cost-table :deep(td.el-table__cell > .cell) { color: var(--text-primary); }
.cost-value { color: var(--text-primary); white-space: nowrap; font-variant-numeric: tabular-nums; }
.cost-page :deep(.el-input__inner), .cost-page :deep(.el-checkbox__label), .cost-page :deep(.el-select__wrapper) { font-family: var(--sans); font-size: var(--font-size-body); }
.cost-page :deep(.el-alert__title) { font-size: var(--font-size-body); }
.cost-page :deep(.el-alert__description) { font-size: var(--font-size-secondary); }
.sr-only { position: absolute; width: 1px; height: 1px; margin: -1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; border: 0; }
:global(.oci-cost-calendar.el-popper) { font-family: var(--sans); }
:global(.oci-cost-calendar .el-date-table), :global(.oci-cost-calendar .el-month-table), :global(.oci-cost-calendar .el-year-table) { font-family: var(--sans); font-size: var(--font-size-body); }
:global(.oci-cost-calendar .el-date-picker__header-label) { font-size: var(--font-size-section); font-weight: 600; }
@keyframes cost-spin { to { transform: rotate(360deg); } }
@media (max-width: 1100px) { .cost-metrics { grid-template-columns: repeat(3, minmax(0, 1fr)); }.metric-item:nth-child(3n + 1) { border-left: 0; padding-left: 0; } }
@media (max-width: 760px) { .query-actions { margin-left: 0; }.date-field { flex-basis: 168px; }.cost-metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }.metric-item:nth-child(n) { padding-left: 0; border-left: 0; } }
@media (max-width: 560px) { .cost-query { padding: 10px 12px; gap: 8px; }.range-control { gap: 8px; }.field-label { display: none; }.time-presets button { padding-inline: 10px; }.date-field { flex: 1 1 calc(50% - 8px); }.cost-body { padding-inline: 12px; }.detail-toolbar { align-items: flex-start; flex-direction: column; } }
@media (prefers-reduced-motion: reduce) { .query-spinner { animation: none; } }
</style>
