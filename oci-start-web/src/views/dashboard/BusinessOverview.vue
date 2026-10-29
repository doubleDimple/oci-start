<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { chromeRevision } from '@/composables/useChrome'
import { usePageMotion } from '@/composables/usePageMotion'
import { readChartTheme } from '@/utils/chartTheme'
import type { BusinessBucket } from '@/api/dashboard'
import { useBusinessOverview } from './useBusinessOverview'
import { distributionOption, rankingOption, businessActivityOption, type BusinessSlice } from './businessCharts'
import { finite } from './useDashboard'
import AnimatedNumber from './AnimatedNumber.vue'
import DashboardChart from './DashboardChart.vue'
import LaunchStatistics from './LaunchStatistics.vue'

const { t, locale } = useI18n()
const tr = (key: string, params: Record<string, string | number> = {}) => t(`dashboardBusiness.${key}`, params)
const root = ref<HTMLElement | null>(null)
usePageMotion(root)
const { overview, days, loading, failed, refresh } = useBusinessOverview()
const palette = computed(() => { void chromeRevision.value; return readChartTheme() })
const distribution = ref<'state' | 'architecture' | 'monitoring'>('state')
const displayDays = computed(() => overview.value?.days ?? days.value)
const number = (value: unknown) => finite(value) === null ? '—' : Number(value).toLocaleString(locale.value, { maximumFractionDigits: 0 })
const ratio = (count: number | null, total: number | null) => count !== null && total !== null && total > 0 ? `${(count / total * 100).toLocaleString(locale.value, { maximumFractionDigits: 1 })}%` : '—'
const count = (buckets: BusinessBucket[] | undefined, key: string): number | null => buckets ? buckets.find(bucket => bucket.key === key)?.count ?? 0 : null
const active = computed(() => count(overview.value?.accountStates, 'active'))
const inactive = computed(() => count(overview.value?.accountStates, 'inactive'))
const online = computed(() => count(overview.value?.monitoring, 'online'))
const stale = computed(() => count(overview.value?.monitoring, 'stale'))
const installed = computed(() => online.value === null || stale.value === null ? null : online.value + stale.value)
const cards = computed(() => [
  { key: 'accounts', value: overview.value?.accounts ?? null, icon: 'i-mdi-account-key-outline', color: palette.value.brand, to: '/tenants/list', first: tr('activeCount', { count: number(active.value) }), second: tr('inactiveCount', { count: number(inactive.value) }) },
  { key: 'instances', value: overview.value?.instances ?? null, icon: 'i-mdi-server-outline', color: palette.value.info, to: '/oci/list', first: tr('runningCount', { count: number(count(overview.value?.instanceStates, 'running')) }), second: tr('regionsCount', { count: number(overview.value?.regions) }) },
  { key: 'probes', value: installed.value, icon: 'i-mdi-access-point', color: palette.value.tertiary, to: '/vps/instances/list', first: tr('onlineCount', { count: number(online.value) }), second: tr('coverage', { rate: ratio(installed.value, overview.value?.instances ?? null) }) },
  { key: 'operations', value: overview.value?.operations.total ?? null, icon: 'i-mdi-chart-timeline-variant', color: palette.value.brand, to: '/system/auditLogs', first: tr('periodCount', { days: displayDays.value }), second: tr('errorCount', { count: number(overview.value?.operations.failed) }) },
])
const capacities = computed(() => [
  { key: 'regionTotal', value: overview.value?.regions ?? null, unit: '', icon: 'i-mdi-map-marker-radius-outline', hint: '', partial: false },
  ...([
    ['ocpus', 'ocpus', 'knownCpuInstances', 'OCPU', 'i-mdi-chip'],
    ['memory', 'memoryGiB', 'knownMemoryInstances', 'GiB', 'i-mdi-memory'],
    ['volumes', 'bootVolumeGiB', 'knownVolumeInstances', 'GiB', 'i-mdi-database-outline'],
  ] as const).map(([key, field, known, unit, icon]) => ({ key, value: overview.value && (overview.value[known] > 0 || overview.value.instances === 0) ? overview.value[field] : null, unit, icon, partial: !!overview.value && overview.value[known] > 0 && overview.value[known] < overview.value.instances, hint: overview.value ? tr('known', { known: overview.value[known], total: overview.value.instances }) : '' })),
])
const accountSlices = computed<BusinessSlice[]>(() => (overview.value?.accountStates ?? []).map(bucket => ({ key: bucket.key, name: tr(bucket.key === 'unknown' ? 'unchecked' : bucket.key), value: bucket.count, color: bucket.key === 'active' ? palette.value.brand : bucket.key === 'inactive' ? palette.value.danger : palette.value.muted })))
const instanceSlices = computed<BusinessSlice[]>(() => {
  const source = distribution.value === 'state' ? overview.value?.instanceStates : distribution.value === 'architecture' ? overview.value?.architectures : overview.value?.monitoring
  const colors: Record<string, string> = { running: palette.value.brand, stopped: palette.value.info, transitioning: palette.value.tertiary, unknown: palette.value.muted, arm: palette.value.brand, x86: palette.value.info, online: palette.value.info, stale: palette.value.danger, uninstalled: palette.value.muted }
  return (source ?? []).map(bucket => ({ key: bucket.key, name: tr(bucket.key === 'stale' ? 'staleProbe' : bucket.key), value: bucket.count, color: colors[bucket.key] ?? palette.value.muted }))
})
const instanceChart = computed(() => distributionOption(instanceSlices.value, palette.value))
const accountChart = computed(() => distributionOption(accountSlices.value, palette.value, true))
const describe = (name: string, slices: BusinessSlice[]) => tr('chartDescription', { name, values: overview.value ? slices.map(slice => `${slice.name} ${number(slice.value)}`).join('，') : tr('loading') })
const ranks = computed(() => [
  { key: 'regionRanking', buckets: (overview.value?.regionRanking ?? []).map(bucket => ({ ...bucket, label: bucket.key === 'unknown' ? tr('unknownRegion') : bucket.label })), color: palette.value.brand, to: '/oci/list', link: 'instancesLink' },
  { key: 'tenantRanking', buckets: (overview.value?.tenantRanking ?? []).map(bucket => ({ ...bucket, label: bucket.label || tr('tenantFallback', { id: bucket.key }) })), color: palette.value.info, to: '/tenants/list', link: 'tenantsLink' },
].map(rank => ({ ...rank, chart: rankingOption(rank.buckets, palette.value, rank.color, locale.value), description: tr('chartDescription', { name: tr(rank.key), values: rank.buckets.map(bucket => `${bucket.label} ${number(bucket.count)}`).join('，') }) })))
const emailLabels = computed<[string, string, string]>(() => [tr('success'), tr('failed'), tr('pending')])
const operationLabels = computed<[string, string, string]>(() => [tr('normalRecord'), tr('errorRecord'), tr('pending')])
const trends = computed(() => [
  { key: 'activity', data: overview.value?.operations ?? null, to: '/system/auditLogs', link: 'auditLink', totalLabel: 'total', labels: operationLabels.value, rateLabel: 'normalRate' },
  { key: 'email', data: overview.value?.email ?? null, to: '/email/management', link: 'emailLink', totalLabel: 'emailTotal', labels: emailLabels.value, rateLabel: 'rate' },
].map(trend => ({ ...trend, chart: businessActivityOption(trend.data, trend.labels, palette.value, locale.value, trend.key === 'email'), description: `${tr(trend.key)}，${tr('days', { days: displayDays.value })}，${trend.labels.map((label, i) => `${label} ${number(trend.data?.[(['success', 'failed', 'unknown'] as const)[i]!] ?? null)}`).join('，')}` })))
const notices = computed(() => [
  { key: 'invalidAccounts', value: inactive.value, to: '/tenants/list' },
  { key: 'staleProbes', value: stale.value, to: '/vps/instances/list' },
  { key: 'failedOperations', value: overview.value?.operations.failed ?? null, to: '/system/auditLogs' },
  { key: 'failedEmails', value: overview.value?.email.failed ?? null, to: '/email/management' },
].filter(notice => notice.value !== null && notice.value > 0))
const updated = computed(() => overview.value ? new Date(overview.value.generatedAt).toLocaleTimeString(locale.value, { hour12: false }) : '')
</script>

<template>
  <div ref="root" class="monitor-dashboard business-dashboard" :aria-busy="loading">
    <div class="monitor-toolbar" data-motion-enter>
      <div class="business-scope"><span class="oci-badge"><i class="i-mdi-cloud-outline" aria-hidden="true" />{{ tr('scope') }}</span><span class="business-sync" :class="{ failed }" role="status"><span class="live-dot" />{{ tr(failed ? 'stale' : loading ? 'loading' : 'synced') }}</span></div>
      <div class="monitor-controls business-controls"><div class="time-window" role="group" :aria-label="tr('period')"><button v-for="period in ([7, 30] as const)" :key="period" type="button" :aria-pressed="days === period" @click="days = period">{{ tr('days', { days: period }) }}</button></div><button type="button" class="monitor-icon-button" :disabled="loading" :aria-label="tr('refresh')" :title="tr('refresh')" @click="refresh()"><i class="i-mdi-refresh" :class="{ refreshing: loading }" aria-hidden="true" /></button></div>
    </div>
    <div v-if="failed" class="monitor-notice" role="status"><i class="i-mdi-alert-circle-outline" aria-hidden="true" /><span>{{ tr(overview ? 'refreshFailed' : 'unavailable') }}</span><button type="button" :disabled="loading" @click="refresh()">{{ tr('retry') }}</button></div>

    <div class="business-kpis">
      <RouterLink v-for="card in cards" :key="card.key" :to="card.to" class="business-kpi" :data-business-kpi="card.key" data-motion-enter>
        <div class="business-kpi-heading"><span>{{ tr(card.key) }}</span><i :class="card.icon" :style="{ color: card.color }" aria-hidden="true" /></div>
        <strong class="business-kpi-value"><AnimatedNumber :value="card.value" :format="number" /><i class="i-mdi-arrow-top-right" aria-hidden="true" /></strong>
        <div class="business-kpi-details"><span>{{ card.first }}</span><span>{{ card.second }}</span></div>
      </RouterLink>
    </div>
    <dl class="business-capacities" :aria-label="tr('snapshot')" data-motion-enter>
      <div v-for="item in capacities" :key="item.key" class="capacity-card" :data-capacity="item.key" :title="item.hint">
        <dt><span>{{ tr(item.key) }}</span><span class="capacity-icon" aria-hidden="true"><i :class="item.icon" /></span></dt>
        <dd class="capacity-value"><AnimatedNumber :value="item.value" :format="number" /><span v-if="item.unit" class="capacity-unit">{{ item.unit }}</span><span v-if="item.partial" class="capacity-partial">{{ tr('partial') }}</span><span v-if="item.hint" class="sr-only">{{ item.hint }}</span></dd>
      </div>
    </dl>

    <div class="business-grid">
      <section class="monitor-panel distribution-panel" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr('distribution') }}</h2><span class="business-tag">{{ tr('current') }}</span></header>
        <div class="distribution-switch" role="group" :aria-label="tr('distribution')"><button v-for="view in (['state', 'architecture', 'monitoring'] as const)" :key="view" type="button" :aria-pressed="distribution === view" @click="distribution = view">{{ tr(view) }}</button></div>
        <div class="business-donut-layout"><div class="business-ring"><DashboardChart :option="instanceChart" :label="describe(tr(distribution), instanceSlices)" /><div class="ring-label"><strong><AnimatedNumber :value="overview?.instances ?? null" :format="number" /></strong><span>{{ tr('totalInstances') }}</span></div></div><ul class="business-legend"><li v-for="slice in instanceSlices" :key="slice.key"><span><i class="legend-dot" :style="{ background: slice.color }" />{{ slice.name }}</span><strong>{{ number(slice.value) }}</strong><small>{{ ratio(slice.value, overview?.instances ?? null) }}</small></li><li v-if="!overview" class="business-placeholder">{{ tr(failed ? 'unavailable' : 'loading') }}</li></ul></div>
        <footer class="business-panel-footer"><span>{{ overview?.instances === 0 ? tr('noInstances') : distribution === 'monitoring' ? tr('probeNote') : '' }}</span><RouterLink :to="distribution === 'monitoring' ? '/vps/instances/list' : '/oci/list'">{{ tr(distribution === 'monitoring' ? 'probesLink' : 'instancesLink') }}<i class="i-mdi-arrow-right" aria-hidden="true" /></RouterLink></footer>
      </section>

      <section v-for="rank in ranks" :key="rank.key" class="monitor-panel ranking-panel" :class="rank.key" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr(rank.key) }}</h2><span class="business-tag">{{ tr('top') }}</span></header>
        <div class="business-rank-chart"><DashboardChart :option="rank.chart" :label="rank.description" /><span v-if="!rank.buckets.length" class="business-chart-empty">{{ tr(loading ? 'loading' : failed && !overview ? 'unavailable' : 'noRanking') }}</span></div>
        <footer class="business-panel-footer"><span>{{ tr('unit') }}</span><RouterLink :to="rank.to">{{ tr(rank.link) }}<i class="i-mdi-arrow-right" aria-hidden="true" /></RouterLink></footer>
      </section>

      <section class="monitor-panel account-panel" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr('accountHealth') }}</h2><RouterLink class="business-text-link" to="/tenants/list">{{ tr('tenantsLink') }}<i class="i-mdi-arrow-top-right" aria-hidden="true" /></RouterLink></header>
        <div class="business-account-layout"><div class="business-health-ring"><DashboardChart :option="accountChart" :label="describe(tr('accountHealth'), accountSlices)" /><div class="ring-label"><strong>{{ ratio(active, overview?.accounts ?? null) }}</strong><span>{{ tr('activeRate') }}</span></div></div><ul class="business-legend"><li v-for="slice in accountSlices" :key="slice.key"><span><i class="legend-dot" :style="{ background: slice.color }" />{{ slice.name }}</span><strong>{{ number(slice.value) }}</strong><small>{{ ratio(slice.value, overview?.accounts ?? null) }}</small></li><li v-if="!overview" class="business-placeholder">{{ tr(failed ? 'unavailable' : 'loading') }}</li></ul></div>
        <footer class="business-panel-footer"><span>{{ overview?.accounts === 0 ? tr('noTenants') : tr('accounts') }}</span><strong>{{ number(overview?.accounts) }}</strong></footer>
      </section>

      <section v-for="trend in trends" :key="trend.key" class="monitor-panel business-trend-panel" :data-business-trend="trend.key" data-motion-enter>
        <header class="panel-heading"><h2>{{ tr(trend.key) }}</h2><RouterLink class="business-text-link" :to="trend.to">{{ tr(trend.link) }}<i class="i-mdi-arrow-top-right" aria-hidden="true" /></RouterLink></header>
        <div class="business-trend-summary"><div><span>{{ tr(trend.totalLabel) }}</span><strong><AnimatedNumber :value="trend.data?.total ?? null" :format="number" /></strong></div><div><span>{{ tr(trend.rateLabel) }}</span><strong>{{ ratio(trend.data?.success ?? null, trend.data?.total ?? null) }}</strong></div><span class="business-tag">{{ tr('days', { days: displayDays }) }}</span></div>
        <div class="business-trend-chart"><DashboardChart :option="trend.chart" :label="trend.description" /><span v-if="!trend.data?.total" class="business-chart-empty">{{ tr(loading ? 'loading' : failed && !overview ? 'unavailable' : 'noRecords') }}</span></div>
        <div class="business-trend-legend"><span v-for="(label, index) in trend.labels" :key="label"><i class="legend-dot" :style="{ background: [palette.brand, palette.danger, palette.muted][index] }" />{{ label }}<strong>{{ number(trend.data?.[(['success', 'failed', 'unknown'] as const)[index]!]) }}</strong></span></div>
      </section>

      <LaunchStatistics :stats="overview?.launch ?? null" :stats-error="failed" data-motion-enter />
    </div>
    <div v-if="notices.length" class="business-attention" data-motion-enter><span><i class="i-mdi-alert-circle-outline" aria-hidden="true" />{{ tr('review') }}</span><RouterLink v-for="notice in notices" :key="notice.key" :to="notice.to">{{ tr(notice.key, { count: number(notice.value) }) }}<i class="i-mdi-chevron-right" aria-hidden="true" /></RouterLink></div>
    <footer class="business-footer"><span>{{ tr('source') }}</span><span v-if="overview">{{ tr('activitySource', { zone: overview.timeZone }) }}</span><time v-if="overview" :datetime="new Date(overview.generatedAt).toISOString()">{{ tr('updated', { time: updated }) }}</time></footer>
  </div>
</template>

<style src="./dashboard.scss" lang="scss" scoped />
<style src="./business.scss" lang="scss" scoped />
