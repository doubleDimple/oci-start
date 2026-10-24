<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { init, use, type ECharts } from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, LegendPlainComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import { LegacyGridContainLabel } from 'echarts/features'
import type { EChartsOption } from 'echarts'
import type { NetworkQualityHistory, QualityOperator, QualityType } from '@/api/networkQuality'
import { theme } from '@/composables/useTheme'
import { chromeRevision } from '@/composables/useChrome'
import { readChartTheme } from '@/utils/chartTheme'

use([LineChart, GridComponent, LegendPlainComponent, TooltipComponent, CanvasRenderer, LegacyGridContainLabel])

const props = defineProps<{
  history: NetworkQualityHistory | null
  type: QualityType
  operator?: QualityOperator
}>()
const { t, locale } = useI18n()
const element = ref<HTMLDivElement | null>(null)
const failed = ref(false)
const hasPoints = computed(() => !!props.history?.points.length)
const hasLatency = computed(() => props.history?.points.some(point => point.avgMs !== null) ?? false)
let chart: ECharts | undefined
let observer: ResizeObserver | undefined
let resizeFrame: number | undefined
let disposed = false

function formatTime(value: unknown, full = false): string {
  if (typeof value !== 'number' || !Number.isFinite(value)) return '—'
  return new Intl.DateTimeFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', full ? {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit',
  } : props.history && props.history.hours > 24 ? {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  } : { hour: '2-digit', minute: '2-digit' }).format(value)
}
function number(value: unknown): string {
  return typeof value === 'number' && Number.isFinite(value)
    ? new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', { maximumFractionDigits: 2 }).format(value)
    : '—'
}
function draw(): void {
  if (disposed || !element.value) return
  try {
    if (!chart) chart = init(element.value)
    const palette = readChartTheme()
    const color = { telecom: palette.brand, unicom: palette.info, mobile: palette.warning, custom: palette.secondary }[props.operator ?? 'custom']
    const { fontFamily, bodySize } = palette
    const option: EChartsOption = {
      animation: false,
      backgroundColor: palette.surface,
      textStyle: { color: palette.text, fontFamily, fontSize: bodySize },
      grid: { left: 8, right: 20, top: 52, bottom: 34, containLabel: true },
      legend: { top: 0, left: 4, selectedMode: false,
        textStyle: { color: palette.text, fontFamily, fontSize: bodySize },
        data: [t('networkQuality.chart.latency')] },
      tooltip: {
        trigger: 'axis', renderMode: 'richText', confine: true,
        backgroundColor: palette.surface, borderColor: palette.border,
        textStyle: { color: palette.text, fontFamily, fontSize: bodySize },
        formatter: parameters => {
          const parameter = Array.isArray(parameters) ? parameters[0] : parameters
          const value = parameter?.value
          const time = Array.isArray(value) ? value[0] : null
          const latency = Array.isArray(value) ? value[1] : null
          return `${formatTime(time, true)}\n${t('networkQuality.chart.latency')}: ${number(latency)}${latency == null ? '' : ' ms'}`
        },
      },
      xAxis: {
        type: 'time', name: t('networkQuality.chart.timeAxis'), nameLocation: 'middle', nameGap: 36,
        min: props.history?.from, max: props.history?.to,
        nameTextStyle: { color: palette.text, fontFamily, fontSize: bodySize },
        axisLabel: { color: palette.text, fontFamily, fontSize: bodySize, formatter: (value: number) => formatTime(value), hideOverlap: true },
        axisTick: { show: false }, axisLine: { lineStyle: { color: palette.border } }, splitLine: { show: false },
      },
      yAxis: {
        type: 'value', min: 0, name: t('networkQuality.chart.latencyAxis'),
        nameTextStyle: { color: palette.text, fontFamily, fontSize: bodySize },
        axisLabel: { color: palette.text, fontFamily, fontSize: bodySize, formatter: (value: number) => number(value) },
        splitLine: { lineStyle: { color: palette.border, type: 'dashed' } },
      },
      series: [{
        id: 'latency', name: t('networkQuality.chart.latency'), type: 'line', smooth: false,
        connectNulls: false, symbol: 'circle', showSymbol: true,
        // Isolated successful samples must remain visible between missing results, including long windows.
        symbolSize: (props.history?.points.length ?? 0) <= 60 ? 5 : 3,
        lineStyle: { color, width: 2 }, itemStyle: { color },
        // Every point is a reported execution. Unknowns stay null; no statistics are derived here.
        data: (props.history?.points ?? []).map(point => [point.updatedAt, point.avgMs]),
      }],
    }
    chart.setOption(option, { notMerge: true })
    chart.resize()
    failed.value = false
  } catch { failed.value = true }
}
function scheduleResize(): void {
  if (disposed || resizeFrame !== undefined) return
  resizeFrame = requestAnimationFrame(() => {
    resizeFrame = undefined
    if (!disposed) chart?.resize()
  })
}
watch([() => props.history, () => props.operator, () => props.type, locale, theme, chromeRevision], draw, { flush: 'post' })
onMounted(() => {
  draw()
  if (element.value && typeof ResizeObserver !== 'undefined') {
    observer = new ResizeObserver(scheduleResize)
    observer.observe(element.value)
  }
})
onBeforeUnmount(() => {
  disposed = true
  observer?.disconnect()
  if (resizeFrame !== undefined) cancelAnimationFrame(resizeFrame)
  chart?.dispose()
  chart = undefined
})
</script>

<template>
  <div class="quality-history-chart">
    <el-alert v-if="failed" :title="t('networkQuality.chart.unavailable')" type="warning" :closable="false" show-icon />
    <div class="quality-chart-wrap">
      <div ref="element" class="quality-chart-canvas" role="img" :aria-label="t('networkQuality.chart.latency')" />
      <p v-if="!failed && !hasLatency" class="quality-chart-empty" role="status">
        {{ t(hasPoints ? 'networkQuality.chart.noLatency' : 'networkQuality.chart.noData') }}
      </p>
    </div>
  </div>
</template>

<style scoped>
.quality-history-chart { min-width: 0; color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
.quality-chart-wrap { position: relative; min-width: 0; }
.quality-chart-canvas { width: 100%; height: 300px; }
.quality-chart-empty { position: absolute; inset: 42% 28px auto; margin: 0; color: var(--text-secondary); text-align: center; font-size: var(--font-size-secondary); pointer-events: none; }
@media (max-width: 640px) { .quality-chart-canvas { height: 260px; } }
</style>
