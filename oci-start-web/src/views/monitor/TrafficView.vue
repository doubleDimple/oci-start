<script setup lang="ts">
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { isAxiosError, isCancel } from 'axios'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import TrafficSeriesChart from './components/TrafficSeriesChart.vue'
import {
  aggregateTraffic, getTrafficAlert, getTrafficRegions, queryTenantTraffic, TrafficResponseError,
  type TrafficAlert, type TrafficQuery, type TrafficRegion, type TrafficSample,
} from '@/api/tenantTraffic'

type Preset = 'today' | 'month' | 'custom'
interface Failure { key: string; detail?: string }
const compact = useCompactViewport()
const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const tenantId = computed(() => typeof route.query.tenantId === 'string' ? route.query.tenantId : '')
const regions = ref<TrafficRegion[]>([])
const selectedRegions = ref<string[]>([])
const preset = ref<Preset>('month')
const customDates = ref<[string, string] | null>(null)
const regionsLoading = ref(false)
const contextLoaded = ref(false)
const loading = ref(false)
const regionsFailure = ref<Failure | null>(null)
const queryFailure = ref<Failure | null>(null)
const validationKey = ref('')
const samples = ref<TrafficSample[]>([])
const resultQuery = ref<TrafficQuery | null>(null)
const updatedAt = ref<Date | null>(null)
const thresholdGB = ref(10240)
const thresholdSource = ref<'configured' | 'default' | 'failed'>('default')
let contextController: AbortController | null = null
let queryController: AbortController | null = null
let contextVersion = 0
let queryVersion = 0
let disposed = false

const language = computed(() => locale.value === 'en' ? 'en-US' : 'zh-CN')
const numberFormat = computed(() => new Intl.NumberFormat(language.value, { maximumFractionDigits: 2 }))
const percentFormat = computed(() => new Intl.NumberFormat(language.value, { style: 'percent', maximumFractionDigits: 1 }))
const sortedRegions = computed(() => [...regions.value].sort((a, b) => regionLabel(a).localeCompare(regionLabel(b), language.value)))
const allPoints = computed(() => aggregateTraffic(samples.value))
const hasTraffic = computed(() => resultQuery.value !== null && samples.value.length > 0)
const moduleEmptyText = computed(() => {
  if (!tenantId.value) return t('tenantTraffic.missingTenant')
  if (regionsLoading.value || !contextLoaded.value) return t('tenantTraffic.regionsLoading')
  if (regionsFailure.value) return t('tenantTraffic.regionsFailed')
  if (!regions.value.length) return t('tenantTraffic.noRegions')
  if (loading.value) return t('tenantTraffic.loading')
  if (queryFailure.value) return t('tenantTraffic.failed')
  return t(resultQuery.value ? 'tenantTraffic.empty' : 'tenantTraffic.beforeQueryHint')
})
const ingress = computed(() => samples.value.reduce((sum, row) => sum + row.ingressBytes, 0))
const egress = computed(() => samples.value.reduce((sum, row) => sum + row.egressBytes, 0))
const metrics = computed(() => [
  { id: 'total', label: t('tenantTraffic.total'), usageLabel: t('tenantTraffic.totalUsage'), value: ingress.value + egress.value },
  { id: 'ingress', label: t('tenantTraffic.ingress'), usageLabel: t('tenantTraffic.ingressUsage'), value: ingress.value },
  { id: 'egress', label: t('tenantTraffic.egress'), usageLabel: t('tenantTraffic.egressUsage'), value: egress.value },
])
const instanceGroups = computed(() => {
  const groups = new Map<string, TrafficSample[]>()
  for (const sample of samples.value) {
    const group = groups.get(sample.instanceId) ?? []
    group.push(sample)
    groups.set(sample.instanceId, group)
  }
  return [...groups.entries()].map(([id, items]) => ({
    id,
    name: items.find((item) => item.instanceName)?.instanceName || t('tenantTraffic.unknownInstance'),
    publicIp: items.find((item) => item.publicIp)?.publicIp || '',
    points: aggregateTraffic(items),
  })).sort((a, b) => a.name.localeCompare(b.name, language.value))
})
const thresholdText = computed(() => thresholdGB.value >= 1024
  ? `${numberFormat.value.format(thresholdGB.value / 1024)} TB`
  : `${numberFormat.value.format(thresholdGB.value)} GB`)
const thresholdHint = computed(() => t(thresholdSource.value === 'configured'
  ? 'tenantTraffic.thresholdConfigured' : thresholdSource.value === 'failed'
    ? 'tenantTraffic.thresholdFallback' : 'tenantTraffic.thresholdDefault'))
const resultRangeText = computed(() => resultQuery.value ? t('tenantTraffic.resultRange', {
  start: displayDate(resultQuery.value.startDate), end: displayDate(resultQuery.value.endDate),
  count: numberFormat.value.format(resultQuery.value.tenantIds.length),
}) : '')
const updatedText = computed(() => updatedAt.value ? t('tenantTraffic.updated', {
  time: new Intl.DateTimeFormat(language.value, { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(updatedAt.value),
}) : '')

function regionLabel(region: TrafficRegion) { return region.region || t('tenantTraffic.regionFallback', { id: region.id }) }
function localDate(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}
function dateValue(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return NaN
  const [year, month, day] = value.split('-').map(Number)
  const result = Date.UTC(year!, month! - 1, day!)
  return new Date(result).toISOString().slice(0, 10) === value ? result : NaN
}
function displayDate(value: string) {
  const time = dateValue(value)
  return Number.isNaN(time) ? value : new Intl.DateTimeFormat(language.value, { year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC' }).format(time)
}
function selectPreset(value: Preset) {
  preset.value = value
  validationKey.value = ''
  if (value === 'custom' && !customDates.value) {
    const now = new Date()
    const previousMonth = new Date(now.getFullYear(), now.getMonth() - 1, now.getDate())
    customDates.value = [localDate(previousMonth), localDate(now)]
  }
}
function clearValidation() { validationKey.value = '' }
function formatBytes(value: number) { return `${numberFormat.value.format(value / 1024 ** 3)} GB` }
function ratio(value: number) { return value / (thresholdGB.value * 1024 ** 3) }
function remaining(value: number) { return Math.max(thresholdGB.value * 1024 ** 3 - value, 0) }
function usageStyle(value: number) {
  return { '--traffic-used-angle': `${Math.min(ratio(value), 1) * 360}deg`, '--traffic-usage-color': ratio(value) >= 1 ? 'var(--status-danger)' : 'var(--brand)' }
}
function usageDescription(metric: { usageLabel: string; value: number }) {
  if (!hasTraffic.value) return `${metric.usageLabel}：${t('tenantTraffic.noData')}`
  return t('tenantTraffic.usageLabel', { name: metric.usageLabel, used: formatBytes(metric.value), remaining: formatBytes(remaining(metric.value)), percent: percentFormat.value.format(ratio(metric.value)) })
}
function failureFor(cause: unknown): Failure {
  if (cause instanceof TrafficResponseError) return { key: 'tenantTraffic.responseInvalid' }
  const error = cause as { message?: string; msg?: string; response?: { data?: { message?: string; msg?: string } } }
  const detail = error?.response?.data?.message || error?.response?.data?.msg || error?.msg || (!isAxiosError(cause) ? error?.message : undefined)
  return { key: 'tenantTraffic.requestFailed', ...(detail ? { detail: String(detail) } : {}) }
}
function failureText(failure: Failure) { return failure.detail || t(failure.key) }
function applyAlert(alert: TrafficAlert | null) {
  const threshold = Number(alert?.threshold)
  const configured = Number.isFinite(threshold) && threshold > 0
  thresholdGB.value = configured ? threshold : 10240
  thresholdSource.value = configured ? 'configured' : 'default'
}

async function initialize() {
  const version = ++contextVersion
  ++queryVersion
  contextController?.abort()
  queryController?.abort()
  contextController = new AbortController()
  const currentTenant = tenantId.value
  regions.value = []
  selectedRegions.value = []
  samples.value = []
  resultQuery.value = null
  updatedAt.value = null
  loading.value = false
  regionsFailure.value = null
  queryFailure.value = null
  validationKey.value = ''
  thresholdGB.value = 10240
  thresholdSource.value = 'default'
  regionsLoading.value = !!currentTenant
  contextLoaded.value = false
  if (!currentTenant) return
  const signal = contextController.signal
  const [regionResult, alertResult] = await Promise.allSettled([getTrafficRegions(currentTenant, signal), getTrafficAlert(currentTenant, signal)])
  if (disposed || version !== contextVersion) return
  if (regionResult.status === 'fulfilled') regions.value = regionResult.value
  else if (!isCancel(regionResult.reason)) regionsFailure.value = failureFor(regionResult.reason)
  if (alertResult.status === 'fulfilled') applyAlert(alertResult.value)
  else if (!isCancel(alertResult.reason)) thresholdSource.value = 'failed'
  regionsLoading.value = false
  contextLoaded.value = true
}

function buildQuery(): TrafficQuery | null {
  validationKey.value = ''
  if (!selectedRegions.value.length) { validationKey.value = 'tenantTraffic.selectRequired'; return null }
  const today = new Date()
  const endDate = localDate(today)
  let dates: [string, string] = [preset.value === 'today' ? endDate : localDate(new Date(today.getFullYear(), today.getMonth(), 1)), endDate]
  if (preset.value === 'custom') {
    if (!customDates.value?.[0] || !customDates.value[1]) { validationKey.value = 'tenantTraffic.dateRequired'; return null }
    dates = [...customDates.value]
  }
  const start = dateValue(dates[0])
  const end = dateValue(dates[1])
  if (!Number.isFinite(start) || !Number.isFinite(end)) validationKey.value = 'tenantTraffic.dateRequired'
  else if (start > end) validationKey.value = 'tenantTraffic.dateOrder'
  else if ((end - start) / 86400000 > 90) validationKey.value = 'tenantTraffic.dateRange'
  else if (start < dateValue(localDate(new Date(today.getFullYear(), today.getMonth() - 3, today.getDate())))) validationKey.value = 'tenantTraffic.dateTooOld'
  if (validationKey.value) return null
  return { tenantIds: [...selectedRegions.value], startDate: dates[0], endDate: dates[1], period: '1d' }
}

async function query() {
  if (loading.value || regionsLoading.value || !tenantId.value) return
  const request = buildQuery()
  if (!request) return
  const version = ++queryVersion
  const context = contextVersion
  const currentTenant = tenantId.value
  queryController?.abort()
  queryController = new AbortController()
  loading.value = true
  queryFailure.value = null
  samples.value = []
  resultQuery.value = null
  updatedAt.value = null
  const [trafficResult, alertResult] = await Promise.allSettled([queryTenantTraffic(request, queryController.signal), getTrafficAlert(currentTenant, queryController.signal)])
  if (disposed || version !== queryVersion || context !== contextVersion) return
  if (alertResult.status === 'fulfilled') applyAlert(alertResult.value)
  else if (!isCancel(alertResult.reason)) { thresholdGB.value = 10240; thresholdSource.value = 'failed' }
  if (trafficResult.status === 'fulfilled') { samples.value = trafficResult.value; resultQuery.value = request; updatedAt.value = new Date() }
  else if (!isCancel(trafficResult.reason)) queryFailure.value = failureFor(trafficResult.reason)
  loading.value = false
}
function goBack() {
  if (window.history.state?.back) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: String(route.query.cloudType || 1) } })
}
watch(tenantId, initialize)
onMounted(initialize)
onBeforeUnmount(() => { disposed = true; ++contextVersion; ++queryVersion; contextController?.abort(); queryController?.abort() })
</script>

<template>
  <section class="traffic-page" :aria-label="t('tenantTraffic.title')">
    <form class="traffic-toolbar" @submit.prevent="query">
      <PageBackButton :title="t('tenantTraffic.back')" @click="goBack" />
      <div class="region-filter">
        <label for="tenant-traffic-regions">{{ t('tenantTraffic.regions') }}</label>
        <el-select id="tenant-traffic-regions" v-model="selectedRegions" multiple filterable collapse-tags collapse-tags-tooltip :max-collapse-tags="2" :loading="regionsLoading" :disabled="loading || regionsLoading || !regions.length" :placeholder="t(regionsLoading ? 'tenantTraffic.regionsLoading' : 'tenantTraffic.selectRegions')" popper-class="tenant-traffic-region-picker" @change="clearValidation">
          <el-option v-for="region in sortedRegions" :key="region.id" :label="regionLabel(region)" :value="region.id" />
        </el-select>
      </div>
      <div class="preset-filter" role="group" :aria-label="t('tenantTraffic.range')">
        <button type="button" :class="{ selected: preset === 'today' }" :aria-pressed="preset === 'today'" :disabled="loading" @click="selectPreset('today')">{{ t('tenantTraffic.today') }}</button>
        <button type="button" :class="{ selected: preset === 'month' }" :aria-pressed="preset === 'month'" :disabled="loading" @click="selectPreset('month')">{{ t('tenantTraffic.month') }}</button>
        <button type="button" :class="{ selected: preset === 'custom' }" :aria-pressed="preset === 'custom'" :disabled="loading" @click="selectPreset('custom')">{{ t('tenantTraffic.custom') }}</button>
      </div>
      <el-date-picker v-if="preset === 'custom'" v-model="customDates" type="daterange" value-format="YYYY-MM-DD" :format="locale === 'en' ? 'MMM D, YYYY' : 'YYYY-MM-DD'" :start-placeholder="t('tenantTraffic.startDate')" :end-placeholder="t('tenantTraffic.endDate')" :range-separator="t('tenantTraffic.to')" :aria-label="t('tenantTraffic.range')" :disabled="loading" class="traffic-dates" popper-class="tenant-traffic-date-picker" @change="clearValidation" />
      <div class="traffic-query-actions" data-page-error-anchor><PrimaryBtn :loading="loading" :disabled="regionsLoading || !regions.length || !tenantId" type="submit"><i class="i-mdi-magnify" aria-hidden="true" />{{ t(loading ? 'tenantTraffic.querying' : 'tenantTraffic.query') }}</PrimaryBtn></div>
    </form>
    <div class="traffic-body">
      <p class="traffic-hint">{{ t('tenantTraffic.dateHint') }}</p>
      <p v-if="validationKey" class="traffic-error" role="alert">{{ t(validationKey) }}</p>
      <PageErrorNotice v-if="regionsFailure"><div><strong>{{ t('tenantTraffic.regionsFailed') }}</strong><p>{{ failureText(regionsFailure) }}</p></div><GhostBtn :disabled="regionsLoading || loading" @click="initialize">{{ t('tenantTraffic.retry') }}</GhostBtn></PageErrorNotice>
      <PageErrorNotice v-if="thresholdSource === 'failed'">{{ thresholdHint }}</PageErrorNotice>
      <PageErrorNotice v-if="queryFailure"><strong>{{ t('tenantTraffic.failed') }}</strong><p>{{ failureText(queryFailure) }}</p></PageErrorNotice>
      <div v-if="loading || regionsLoading" class="traffic-loading-note" role="status" aria-live="polite"><span class="traffic-spinner" aria-hidden="true" /><span>{{ t(regionsLoading ? 'tenantTraffic.regionsLoading' : 'tenantTraffic.loading') }}</span></div>
      <div class="result-context"><span>{{ resultQuery ? resultRangeText : t('tenantTraffic.beforeQuery') }}</span><span>{{ updatedText }}</span></div>
      <div class="traffic-totals" :aria-busy="loading || regionsLoading">
        <article v-for="metric in metrics" :key="metric.id"><span>{{ metric.label }}</span><strong>{{ hasTraffic ? formatBytes(metric.value) : '—' }}</strong></article>
        <article><span>{{ t('tenantTraffic.threshold') }}</span><strong>{{ contextLoaded ? thresholdText : '—' }}</strong><small>{{ contextLoaded ? thresholdHint : t('tenantTraffic.noData') }}</small></article>
      </div>
      <div class="traffic-usages" :aria-busy="loading || regionsLoading">
        <article v-for="metric in metrics" :key="metric.id" class="usage-card">
          <h2>{{ metric.usageLabel }}</h2>
          <div class="usage-content">
            <div class="usage-ring" :class="{ 'is-empty': !hasTraffic }" :style="hasTraffic ? usageStyle(metric.value) : undefined" role="img" :aria-label="usageDescription(metric)"><span>{{ hasTraffic ? percentFormat.format(ratio(metric.value)) : '—' }}</span></div>
            <dl><div><dt>{{ t('tenantTraffic.used') }}</dt><dd>{{ hasTraffic ? formatBytes(metric.value) : '—' }}</dd></div><div><dt>{{ t('tenantTraffic.remaining') }}</dt><dd>{{ hasTraffic ? formatBytes(remaining(metric.value)) : '—' }}</dd></div></dl>
          </div>
        </article>
      </div>
      <section class="trend-section" :aria-label="t('tenantTraffic.trend')" :aria-busy="loading || regionsLoading">
        <h2>{{ t('tenantTraffic.trend') }}</h2>
        <div class="trend-stage">
          <TrafficSeriesChart :points="allPoints" :label="t('tenantTraffic.trendChartLabel')" total bars />
          <div v-if="!hasTraffic" class="trend-empty"><p>{{ moduleEmptyText }}</p></div>
        </div>
      </section>
      <section class="instance-section" :aria-label="t('tenantTraffic.instanceTrends')" :aria-busy="loading || regionsLoading">
        <div class="section-heading"><h2>{{ t('tenantTraffic.instanceTrends') }}</h2><span>{{ t('tenantTraffic.instanceCount', { count: hasTraffic ? numberFormat.format(instanceGroups.length) : '—' }) }}</span></div>
        <MobileRecordList v-if="compact && instanceGroups.length" drilldown :list-id="`traffic-${tenantId}`" :record-keys="instanceGroups.map(instance => instance.id)" :loading="loading">
          <MobileRecordCard v-for="instance in instanceGroups" :key="instance.id" :record-key="instance.id" :summary-title="instance.name" :summary-meta="instance.publicIp || t('tenantTraffic.noIp')">
            <template #identity><h3 class="mobile-record-title">{{ instance.name }}</h3><span class="mobile-record-subtitle">{{ instance.id }}</span></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('tenantTraffic.publicIp') }}</dt><dd>{{ instance.publicIp || t('tenantTraffic.noIp') }}</dd></div></dl>
            <TrafficSeriesChart :points="instance.points" :label="t('tenantTraffic.chartLabel', { name: instance.name })" unit="MB" bars />
          </MobileRecordCard>
        </MobileRecordList>
        <div v-else-if="instanceGroups.length" class="instance-grid">
          <article v-for="instance in instanceGroups" :key="instance.id" class="instance-card"><header><h3 :title="instance.id">{{ instance.name }}</h3><p><span>{{ t('tenantTraffic.publicIp') }}</span> {{ instance.publicIp || t('tenantTraffic.noIp') }}</p></header><TrafficSeriesChart :points="instance.points" :label="t('tenantTraffic.chartLabel', { name: instance.name })" unit="MB" bars /></article>
        </div>
        <div v-else class="instance-placeholder"><i class="i-mdi-chart-bar" aria-hidden="true" /><p>{{ moduleEmptyText }}</p></div>
      </section>
      <p v-if="resultQuery" class="traffic-hint result-note">{{ t('tenantTraffic.reportedOnly') }}</p>
    </div>
  </section>
</template>

<style scoped>
.traffic-page { display: flex; flex-direction: column; min-width: 0; min-height: 0; height: 100%; overflow: hidden; border: 1px solid var(--border); border-radius: var(--r-card); background: var(--bg-card); box-shadow: var(--shadow-card); color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
.traffic-toolbar { display: flex; align-items: center; flex-wrap: wrap; gap: 10px; flex: none; padding: 14px 18px; border-bottom: 1px solid var(--border); }
.traffic-query-actions { display: flex; flex: none; align-items: center; gap: 8px; margin-left: auto; }
.region-filter { display: flex; align-items: center; gap: 9px; min-width: 0; }
.region-filter label { flex: none; font-size: var(--font-size-body); }
.region-filter :deep(.el-select) { width: 250px; }
.preset-filter { display: flex; flex-wrap: wrap; align-items: center; gap: 3px; padding: 3px; border-radius: 11px; background: var(--bg-search); }
.preset-filter button { border: 0; border-radius: 8px; background: transparent; padding: 5px 10px; color: var(--text-primary); font: inherit; cursor: pointer; }
.preset-filter button:hover, .preset-filter button.selected { background: var(--bg-card); box-shadow: var(--shadow-card); }
.preset-filter button.selected { font-weight: 600; }
.preset-filter button:disabled { cursor: default; }
.traffic-toolbar :deep(.traffic-dates) { flex: 0 1 320px; width: 320px; min-width: 245px; }
.traffic-body { flex: 1; min-height: 0; overflow: auto; padding: 14px 18px 20px; }
.traffic-hint { margin: 0 0 14px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.traffic-error { margin: 0 0 14px; padding: 12px 14px; border-radius: var(--r-sm); background: var(--status-danger-bg); color: var(--status-danger); }
.traffic-error p { margin: 4px 0 0; font-size: var(--font-size-secondary); }
.with-action { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.traffic-notice { margin: 0 0 14px; padding: 10px 14px; border-radius: var(--r-sm); background: var(--status-warn-bg); color: var(--text-primary); font-size: var(--font-size-secondary); }
.traffic-page h2, .traffic-page h3 { margin: 0; font-size: var(--font-size-section); font-weight: 600; color: var(--text-primary); }
.traffic-loading-note { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; color: var(--text-primary); font-size: var(--font-size-secondary); }
.traffic-spinner { flex: none; width: 16px; height: 16px; border: 2px solid var(--border); border-right-color: var(--brand); border-radius: 50%; animation: traffic-spin 800ms linear infinite; }
.result-context { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; margin-bottom: 14px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.traffic-totals { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; padding-bottom: 18px; border-bottom: 1px solid var(--border); }
.traffic-totals article { min-width: 0; }
.traffic-totals article > span { display: block; font-size: var(--font-size-body); }
.traffic-totals strong { display: block; margin-top: 6px; font-size: 25px; line-height: 1.3; font-weight: 600; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
.traffic-totals small { display: block; margin-top: 6px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.traffic-usages { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; margin: 18px 0; }
.usage-card { min-width: 0; padding: 16px; border: 1px solid var(--border); border-radius: var(--r-card); }
.usage-content { display: flex; align-items: center; flex-wrap: wrap; gap: 16px; margin-top: 14px; }
.usage-ring { display: grid; place-items: center; position: relative; flex: none; width: 94px; height: 94px; border-radius: 50%; background: conic-gradient(var(--traffic-usage-color) 0deg var(--traffic-used-angle), var(--bg-search) var(--traffic-used-angle) 360deg); }
.usage-ring.is-empty { background: var(--bg-search); }
.usage-ring::before { content: ''; position: absolute; inset: 9px; border-radius: 50%; background: var(--bg-card); }
.usage-ring span { position: relative; font-size: var(--font-size-dialog-title); font-weight: 600; font-variant-numeric: tabular-nums; }
.usage-content dl { margin: 0; min-width: 0; flex: 1; }
.usage-content dl div + div { margin-top: 8px; }
.usage-content dt { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.usage-content dd { margin: 2px 0 0; font-size: var(--font-size-body); font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
.trend-section { padding: 16px; border: 1px solid var(--border); border-radius: var(--r-card); }
.trend-section > h2 { margin-bottom: 16px; }
.trend-stage { position: relative; min-width: 0; }
.trend-empty { position: absolute; inset: 66px 12px 16px; display: grid; place-items: center; padding: 20px; text-align: center; pointer-events: none; }
.trend-empty p { max-width: 480px; margin: 0; padding: 10px 14px; border-radius: var(--r-sm); background: var(--bg-card); color: var(--text-secondary); font-size: var(--font-size-secondary); }
.instance-placeholder { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; min-height: 190px; padding: 24px; border: 1px solid var(--border); border-radius: var(--r-card); text-align: center; }
.instance-placeholder > i { font-size: 28px; color: var(--text-secondary); }
.instance-placeholder p { max-width: 480px; margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.instance-section { margin-top: 22px; }
.section-heading { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; margin-bottom: 12px; }
.section-heading span { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.instance-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.instance-card { min-width: 0; padding: 16px; border: 1px solid var(--border); border-radius: var(--r-card); }
.instance-card header { min-width: 0; margin-bottom: 16px; }
.instance-card h3 { overflow-wrap: anywhere; }
.instance-card header p { margin: 5px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.result-note { margin: 16px 0 0; }
@keyframes traffic-spin { to { transform: rotate(360deg); } }
@media (max-width: 1100px) { .traffic-usages { gap: 10px; } .usage-card { padding: 12px; } .usage-content { gap: 10px; } .usage-ring { width: 80px; height: 80px; } }
@media (max-width: 850px) { .traffic-usages, .instance-grid { grid-template-columns: 1fr; } .traffic-totals { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (max-width: 600px) { .traffic-toolbar { padding: 12px; } .traffic-body { padding: 12px; } .region-filter { flex: 1; } .region-filter :deep(.el-select) { width: 100%; min-width: 0; } .traffic-toolbar :deep(.traffic-dates) { flex-basis: 100%; width: 100%; } .traffic-usages, .instance-grid { gap: 12px; } }
@media (prefers-reduced-motion: reduce) { .traffic-spinner { animation: none; } }
</style>
