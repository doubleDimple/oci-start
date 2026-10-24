<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { init, use, type ECharts } from 'echarts/core'
import { BarChart, LineChart } from 'echarts/charts'
import { AriaComponent, GridComponent, LegendPlainComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { LegacyGridContainLabel } from 'echarts/features'
import { theme } from '@/composables/useTheme'
import { chromeRevision } from '@/composables/useChrome'
import { readChartTheme } from '@/utils/chartTheme'
import type { TrafficPoint } from '@/api/tenantTraffic'

use([BarChart, LineChart, AriaComponent, GridComponent, LegendPlainComponent, TooltipComponent, CanvasRenderer, LegacyGridContainLabel])

const props = withDefaults(defineProps<{
  points: TrafficPoint[]
  label: string
  unit?: 'GB' | 'MB'
  bars?: boolean
  total?: boolean
}>(), { unit: 'GB', bars: false, total: false })
const { t, locale } = useI18n()
const root = ref<HTMLDivElement | null>(null)
let chart: ECharts | null = null
let resizeObserver: ResizeObserver | null = null
let intersectionObserver: IntersectionObserver | null = null
let visible = false
const selectedSeries = { ingress: true, egress: true, total: true }
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')

function formatDate(value: string) {
  const normalized = /Z$|[+-]\d{2}:?\d{2}$/.test(value) ? value : `${value}Z`
  const date = new Date(normalized)
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat(locale.value === 'en' ? 'en-US' : 'zh-CN', {
    month: 'short', day: 'numeric', timeZone: 'UTC',
  }).format(date)
}

function render() {
  if (!root.value || !visible) return
  if (!chart) {
    chart = init(root.value, undefined, { renderer: 'canvas' })
    chart.on('legendselectchanged', (event) => {
      const selected = (event as { selected: Record<string, boolean> }).selected
      for (const key of ['ingress', 'egress', 'total'] as const) selectedSeries[key] = selected[t(`tenantTraffic.${key}`)] !== false
    })
  }
  const palette = readChartTheme()
  const { fontFamily, text, secondary, bodySize, secondarySize } = palette
  const grid = palette.border
  const divisor = props.unit === 'MB' ? 1024 ** 2 : 1024 ** 3
  const numbers = new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN', { maximumFractionDigits: 3 })
  const series = [
    { id: 'ingress' as const, name: t('tenantTraffic.ingress'), data: props.points.map((point) => point.ingressBytes / divisor) },
    { id: 'egress' as const, name: t('tenantTraffic.egress'), data: props.points.map((point) => point.egressBytes / divisor) },
    ...(props.total ? [{ id: 'total' as const, name: t('tenantTraffic.total'), data: props.points.map((point) => (point.ingressBytes + point.egressBytes) / divisor) }] : []),
  ]
  chart.setOption({
    animation: !reducedMotion.matches,
    animationDuration: 220,
    color: [palette.brand, palette.info, secondary],
    textStyle: { fontFamily, color: text, fontSize: bodySize },
    aria: { enabled: true, label: { description: props.label } },
    legend: { top: 0, selected: Object.fromEntries(series.map(item => [item.name, selectedSeries[item.id]])), textStyle: { color: text, fontFamily, fontSize: bodySize } },
    tooltip: {
      trigger: 'axis', renderMode: 'richText',
      axisPointer: { type: props.bars ? 'shadow' : 'line' },
      backgroundColor: palette.surface, borderColor: grid,
      textStyle: { color: text, fontFamily, fontSize: bodySize },
      valueFormatter: (value: unknown) => `${numbers.format(Number(value) || 0)} ${props.unit}`,
    },
    grid: { left: 10, right: 16, top: 66, bottom: 16, containLabel: true },
    xAxis: {
      type: 'category', boundaryGap: props.bars,
      data: props.points.map((point) => point.timePoint),
      axisLabel: { color: secondary, fontFamily, fontSize: secondarySize, formatter: formatDate, hideOverlap: true },
      axisLine: { lineStyle: { color: grid } }, axisTick: { show: false },
    },
    yAxis: {
      type: 'value', name: `${t('tenantTraffic.traffic')} (${props.unit})`, min: 0,
      nameTextStyle: { color: secondary, fontFamily, fontSize: secondarySize },
      axisLabel: { show: props.points.length > 0, color: secondary, fontFamily, fontSize: secondarySize, formatter: (value: number) => numbers.format(value) },
      splitLine: { lineStyle: { color: grid, opacity: 0.45 } },
    },
    series: series.map((item) => ({
      ...item, type: props.bars ? 'bar' : 'line', smooth: !props.bars,
      showSymbol: props.points.length < 3, symbolSize: 5,
      ...(props.bars ? { barMaxWidth: 32, itemStyle: { borderRadius: [3, 3, 0, 0] } } : { lineStyle: { width: 2 } }),
    })),
  }, { notMerge: true })
}

function resize() {
  if (visible) {
    if (!chart) render()
    chart?.resize()
  }
}

watch([() => props.points, () => props.label, () => props.unit, () => props.bars, () => props.total, locale, theme, chromeRevision], render, { flush: 'post' })
onMounted(() => {
  if (!root.value) return
  resizeObserver = new ResizeObserver(resize)
  resizeObserver.observe(root.value)
  intersectionObserver = new IntersectionObserver(([entry]) => {
    visible = !!entry?.isIntersecting
    if (visible) { render(); resize() }
  }, { rootMargin: '160px' })
  intersectionObserver.observe(root.value)
  reducedMotion.addEventListener('change', render)
})
onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  intersectionObserver?.disconnect()
  reducedMotion.removeEventListener('change', render)
  chart?.dispose()
  chart = null
})
</script>

<template>
  <div ref="root" class="traffic-chart" role="img" :aria-label="label" />
</template>

<style scoped>
.traffic-chart { width: 100%; height: 310px; min-width: 0; font-family: var(--sans); }
@media (max-width: 700px) { .traffic-chart { height: 280px; } }
</style>
