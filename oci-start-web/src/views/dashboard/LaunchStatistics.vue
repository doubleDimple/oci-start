<script setup lang="ts">
import { computed, toRefs } from 'vue'
import { useI18n } from 'vue-i18n'
import type { DashboardStats } from '@/api/dashboard'
import { chromeRevision } from '@/composables/useChrome'
import { readChartTheme } from '@/utils/chartTheme'
import { finite } from './useDashboard'
import { outcomesOption } from './dashboardCharts'
import DashboardChart from './DashboardChart.vue'
import AnimatedNumber from './AnimatedNumber.vue'
const props = defineProps<{ stats: DashboardStats | null; statsError: boolean }>()
const { stats, statsError } = toRefs(props)
const { t, locale } = useI18n()
const tr = (key: string) => t(`dashboardMonitor.${key}`)
const palette = computed(() => { void chromeRevision.value; return readChartTheme() })
const number = (value: unknown, decimals = 1) => finite(value) === null ? '—' : Number(Number(value).toFixed(decimals)).toLocaleString(locale.value)
const percent = (value: unknown) => finite(value) === null ? '—' : `${number(value)}%`
const taskKpis = computed(() => [
  { key: 'accounts', value: finite(stats.value?.totalApiCalls), icon: 'i-mdi-key-outline' },
  { key: 'bootCount', value: finite(stats.value?.totalBootInstances), icon: 'i-mdi-server-outline' },
  { key: 'attempts', value: finite(stats.value?.totalAttempts), icon: 'i-mdi-sync' },
  { key: 'successes', value: finite(stats.value?.successfulAttempts), icon: 'i-mdi-check-circle-outline' },
  { key: 'failures', value: finite(stats.value?.failCounts), icon: 'i-mdi-close-circle-outline' },
])
const outcomes = computed(() => {
  const total = finite(stats.value?.totalAttempts), success = finite(stats.value?.successfulAttempts), fail = finite(stats.value?.failCounts)
  if (total === null || success === null || fail === null || success + fail > total) return null
  return [{ name: tr('successes'), value: success, color: palette.value.info }, { name: tr('failures'), value: fail, color: palette.value.danger }, { name: tr('unclassified'), value: total - success - fail, color: palette.value.border }]
})
const outcomesChart = computed(() => outcomesOption(outcomes.value ?? [], palette.value))
const successRate = computed(() => {
  const total = finite(stats.value?.totalAttempts), success = finite(stats.value?.successfulAttempts)
  return total !== null && total > 0 && success !== null && outcomes.value ? success / total * 100 : null
})
</script>
<template>
      <section class="monitor-panel launch-panel" >
        <header class="panel-heading"><h2>{{ tr('launch') }} <span class="launch-period">{{ t('dashboardBusiness.cumulative') }}</span></h2><span v-if="statsError" class="stats-error" role="status">{{ tr('statsFailed') }}</span><span v-else class="success-rate">{{ tr('successRate') }} <strong>{{ percent(successRate) }}</strong></span></header>
        <div class="launch-kpis"><div v-for="item in taskKpis" :key="item.key" class="launch-kpi"><span><i :class="item.icon" aria-hidden="true" />{{ item.key === 'accounts' ? t('dashboardBusiness.accounts') : tr(item.key) }}</span><strong><AnimatedNumber :value="item.value" :format="value => number(value, 0)" /></strong></div></div>
        <div v-if="outcomes" class="outcomes"><div class="outcomes-heading"><span>{{ tr('resultSplit') }}</span><div class="chart-legend"><span v-for="item in outcomes" :key="item.name"><i class="legend-dot" :style="{ background: item.color }" />{{ item.name }} <b>{{ number(item.value, 0) }}</b></span></div></div><div class="outcomes-chart"><DashboardChart :option="outcomesChart" :label="outcomes.map(item => `${item.name}: ${item.value}`).join(', ')" /></div></div>
        <p v-else-if="stats && !statsError" class="stats-error">{{ tr('inconsistent') }}</p>
      <RouterLink class="launch-link" to="/boot/fullBootList">{{ t('dashboardBusiness.tasksLink') }} <i class="i-mdi-arrow-right" aria-hidden="true" /></RouterLink></section>
</template>
<style src="./launchStatistics.scss" lang="scss" scoped />
