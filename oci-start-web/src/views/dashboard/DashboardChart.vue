<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { init, use, type ECharts, type EChartsCoreOption } from 'echarts/core'
import { LineChart, PieChart, BarChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendPlainComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'

use([LineChart, PieChart, BarChart, GridComponent, TooltipComponent, LegendPlainComponent, CanvasRenderer])
const props = defineProps<{ option: EChartsCoreOption; label: string }>()
const root = ref<HTMLDivElement | null>(null)
let chart: ECharts | undefined
let observer: ResizeObserver | undefined
const motion = window.matchMedia('(prefers-reduced-motion: reduce)')
function render() {
  chart?.setOption({ ...props.option, animation: !motion.matches, animationDuration: 650, animationDurationUpdate: 450, animationEasing: 'cubicOut' }, { replaceMerge: ['series'] })
}
onMounted(() => {
  if (!root.value) return
  chart = init(root.value)
  render()
  observer = new ResizeObserver(() => chart?.resize())
  observer.observe(root.value)
  motion.addEventListener('change', render)
})
watch(() => props.option, render, { deep: false })
onBeforeUnmount(() => {
  observer?.disconnect()
  chart?.dispose()
  motion.removeEventListener('change', render)
})
</script>

<template><div ref="root" class="dashboard-chart" role="img" :aria-label="label" /></template>

<style scoped>
.dashboard-chart { width: 100%; min-width: 0; height: 100%; }
</style>
