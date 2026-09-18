<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { init, use, type ECharts } from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { LegacyGridContainLabel } from 'echarts/features'
import type { EChartsOption } from 'echarts'
import { costCategory, type OciCostCategory, type OciCostRow } from '@/api/ociCost'
import { theme } from '@/composables/useTheme'
import { chromeRevision } from '@/composables/useChrome'
import { readChartTheme } from '@/utils/chartTheme'

use([LineChart, GridComponent, TooltipComponent, CanvasRenderer, LegacyGridContainLabel])

const props = defineProps<{ rows: OciCostRow[] }>()
const { t, locale } = useI18n()
const chartElement = ref<HTMLDivElement | null>(null)
const failed = ref(false)
const categories: OciCostCategory[] = ['compute', 'storage', 'network', 'other']
const selected = ref<Record<OciCostCategory, boolean>>({ compute: true, storage: true, network: true, other: true })
const hasSelection = computed(() => categories.some(category => selected.value[category]))
let chart: ECharts | undefined
let resizeObserver: ResizeObserver | undefined
let disposed = false

function formatDay(day: string) {
  return new Intl.DateTimeFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
    .format(new Date(`${day}T00:00:00Z`))
}

function money(value: unknown) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return '—'
  return new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', {
    style: 'currency', currency: 'USD', minimumFractionDigits: 6, maximumFractionDigits: 6,
  }).format(value)
}

function draw() {
  if (disposed || !chartElement.value) return
  try {
    if (!chart) chart = init(chartElement.value)
    const palette = readChartTheme()
    const { fontFamily, bodySize } = palette
    const axisNumbers = new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', { maximumFractionDigits: 6 })
    const colors = {
      compute: palette.brand, storage: palette.info,
      network: palette.warning, other: palette.secondary,
    }
    const daily = new Map<string, Record<OciCostCategory, number>>()
    for (const row of props.rows) {
      let amounts = daily.get(row.day)
      if (!amounts) {
        amounts = { compute: 0, storage: 0, network: 0, other: 0 }
        daily.set(row.day, amounts)
      }
      amounts[costCategory(row.resourceType)] += row.cost
    }
    const days = [...daily.keys()].sort()
    const option: EChartsOption = {
      animation: false,
      backgroundColor: palette.surface,
      textStyle: { fontFamily, fontSize: bodySize, color: palette.text },
      grid: { left: 4, right: 18, top: 30, bottom: 12, containLabel: true },
      tooltip: {
        trigger: 'axis', renderMode: 'richText', confine: true,
        backgroundColor: palette.surface, borderColor: palette.border,
        textStyle: { fontFamily, fontSize: bodySize, color: palette.text },
        valueFormatter: money,
      },
      xAxis: {
        type: 'category', data: days, boundaryGap: false,
        axisLabel: { color: palette.text, fontFamily, fontSize: bodySize, formatter: formatDay, hideOverlap: true, margin: 12 },
        axisTick: { show: false }, axisLine: { lineStyle: { color: palette.border } },
      },
      yAxis: {
        type: 'value', name: 'USD',
        nameTextStyle: { color: palette.text, fontFamily, fontSize: bodySize },
        axisLabel: { color: palette.text, fontFamily, fontSize: bodySize, formatter: (value: number) => axisNumbers.format(value) },
        splitLine: { lineStyle: { color: palette.border, type: 'dashed' } },
      },
      series: categories.filter(category => selected.value[category]).map(category => ({
        id: category, name: t(`ociCost.categories.${category}`), type: 'line', smooth: true,
        symbol: 'circle', showSymbol: days.length < 32, symbolSize: 5,
        itemStyle: { color: colors[category] }, lineStyle: { color: colors[category], width: 2 },
        data: days.map(day => Number(daily.get(day)![category].toFixed(6))),
      })),
    }
    chart.setOption(option, { notMerge: true })
    chart.resize()
    failed.value = false
  } catch {
    failed.value = true
  }
}

function resize() { chart?.resize() }
watch([() => props.rows, locale, theme, chromeRevision], draw, { flush: 'post' })
watch(selected, draw, { deep: true, flush: 'post' })
onMounted(() => {
  draw()
  if (chartElement.value) {
    resizeObserver = new ResizeObserver(resize)
    resizeObserver.observe(chartElement.value)
  }
})
onBeforeUnmount(() => {
  disposed = true
  resizeObserver?.disconnect()
  chart?.dispose()
  chart = undefined
})
</script>

<template>
  <div class="cost-trend">
    <div class="chart-toolbar">
      <slot name="heading" />
      <div class="trend-legend" role="group" :aria-label="t('ociCost.trendLegend')">
        <button
          v-for="category in categories" :key="category" type="button"
          :class="['legend-item', category, { muted: !selected[category] }]"
          :aria-pressed="selected[category]" :title="t('ociCost.trendToggle', { category: t(`ociCost.categories.${category}`) })"
          @click="selected[category] = !selected[category]"
        ><span class="legend-dot" aria-hidden="true" />{{ t(`ociCost.categories.${category}`) }}</button>
      </div>
    </div>
    <PageErrorNotice v-if="failed">{{ t('ociCost.chartUnavailable') }}</PageErrorNotice>
    <div class="chart-wrap">
      <div ref="chartElement" class="cost-chart" role="img" :aria-label="t('ociCost.trendAria')" />
      <p v-if="!hasSelection && !failed" class="chart-empty" role="status">{{ t('ociCost.noSeries') }}</p>
    </div>
  </div>
</template>

<style scoped>
.cost-trend { min-width: 0; color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
.chart-toolbar { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px 20px; margin-bottom: 10px; }
.trend-legend { display: flex; align-items: center; justify-content: flex-end; gap: 8px 18px; flex-wrap: wrap; }
.legend-item { display: inline-flex; align-items: center; gap: 7px; min-height: 28px; border: 0; padding: 4px 0; background: transparent; color: var(--text-primary); font: inherit; white-space: nowrap; cursor: pointer; }
.legend-item:focus-visible { outline: 2px solid var(--brand); outline-offset: 4px; border-radius: 4px; }
.legend-item.muted { color: var(--text-secondary); text-decoration: line-through; }
.legend-item.muted .legend-dot { opacity: .3; }
.legend-dot { width: 9px; height: 9px; border-radius: 50%; background: var(--text-secondary); }
.compute .legend-dot { background: var(--brand); }
.storage .legend-dot { background: var(--status-info); }
.network .legend-dot { background: var(--status-warn); }
.chart-wrap { position: relative; min-width: 0; }
.cost-chart { width: 100%; height: 300px; }
.chart-empty { position: absolute; inset: 40% 12px auto; text-align: center; color: var(--text-secondary); font-size: var(--font-size-secondary); pointer-events: none; }
@media (max-width: 640px) {
  .trend-legend { justify-content: flex-start; gap: 8px 16px; }
  .cost-chart { height: 260px; }
}
</style>
