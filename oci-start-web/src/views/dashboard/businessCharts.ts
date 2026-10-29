import type { EChartsCoreOption } from 'echarts/core'
import type { ChartTheme } from '@/utils/chartTheme'
import type { BusinessActivity, BusinessBucket } from '@/api/dashboard'

export interface BusinessSlice { key: string; name: string; value: number; color: string }
function tooltip(palette: Readonly<ChartTheme>) {
  return { renderMode: 'richText' as const, confine: true, backgroundColor: palette.surface, borderColor: palette.border, padding: 12, textStyle: { color: palette.text, fontFamily: palette.fontFamily, fontSize: 12 } }
}

export function distributionOption(slices: BusinessSlice[], palette: Readonly<ChartTheme>, half = false): EChartsCoreOption {
  const total = slices.reduce((sum, slice) => sum + slice.value, 0)
  return {
    tooltip: { ...tooltip(palette), show: total > 0, trigger: 'item', formatter: '{b}: {c} ({d}%)' },
    series: [{ id: 'distribution', type: 'pie', radius: half ? ['78%', '98%'] : ['72%', '91%'], center: half ? ['50%', '78%'] : ['50%', '50%'],
      startAngle: half ? 180 : 90, endAngle: half ? 0 : 'auto', padAngle: total > 0 ? 3 : 0, minAngle: 0,
      avoidLabelOverlap: true, label: { show: false }, labelLine: { show: false },
      emphasis: { scale: true, scaleSize: 4 }, itemStyle: { borderRadius: 5 }, silent: !total,
      data: total ? slices.map(slice => ({ id: slice.key, name: slice.name, value: slice.value, itemStyle: { color: slice.color } }))
        : [{ value: 1, itemStyle: { color: palette.border, opacity: .3 } }],
    }],
  }
}

export function rankingOption(buckets: BusinessBucket[], palette: Readonly<ChartTheme>, color: string, locale: string): EChartsCoreOption {
  return {
    textStyle: { color: palette.secondary, fontFamily: palette.fontFamily, fontSize: 12 },
    grid: { left: 128, right: 34, top: 8, bottom: 14 },
    tooltip: { ...tooltip(palette), trigger: 'axis', axisPointer: { type: 'shadow', shadowStyle: { color: palette.border, opacity: .08 } }, valueFormatter: (value: unknown) => Number(value).toLocaleString(locale) },
    xAxis: { type: 'value', show: false, min: 0, max: Math.max(1, ...buckets.map(bucket => bucket.count)) * 1.15 },
    yAxis: { type: 'category', inverse: true, data: buckets.map(bucket => bucket.label), axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: palette.secondary, width: 114, overflow: 'truncate', margin: 12, fontSize: 11 } },
    series: [{ id: 'ranking', name: '', type: 'bar', data: buckets.map(bucket => ({ id: bucket.key, value: bucket.count })), barWidth: 13,
      showBackground: true, backgroundStyle: { color: palette.border, opacity: .12, borderRadius: 4 },
      itemStyle: { color, borderRadius: 4 }, label: { show: true, position: 'right', color: palette.text, fontFamily: palette.fontFamily, fontSize: 12, formatter: (item: { value: unknown }) => Number(item.value).toLocaleString(locale) },
      emphasis: { itemStyle: { opacity: .8 } }, animationDelay: (index: number) => index * 45,
    }],
  }
}

export function businessActivityOption(activity: BusinessActivity | null, labels: [string, string, string], palette: Readonly<ChartTheme>, locale: string, bar = false): EChartsCoreOption {
  const days = activity?.daily ?? []
  return {
    textStyle: { fontFamily: palette.fontFamily, color: palette.secondary, fontSize: 12 },
    grid: { left: 6, right: 12, top: 22, bottom: 6, containLabel: true },
    tooltip: { ...tooltip(palette), trigger: 'axis', valueFormatter: (value: unknown) => Number(value).toLocaleString(locale) },
    xAxis: { type: 'category', data: days.map(day => day.date), boundaryGap: bar, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: palette.muted, fontSize: 11, hideOverlap: true, formatter: (date: string) => date.slice(5).replace('-', '/') } },
    yAxis: { type: 'value', min: 0, minInterval: 1, splitNumber: 3, axisLabel: { color: palette.muted, fontSize: 11 }, splitLine: { lineStyle: { color: palette.border, opacity: .5, type: 'dashed' } } },
    series: (['success', 'failed', 'unknown'] as const).map((key, index) => ({
      id: key, name: labels[index], type: bar ? 'bar' : 'line', smooth: .25, smoothMonotone: 'x',
      showSymbol: days.length <= 7, symbol: 'circle', symbolSize: 5, barMaxWidth: 23,
      stack: bar ? 'mail' : undefined, lineStyle: { width: 2.5, type: index === 2 ? 'dashed' : 'solid' },
      areaStyle: bar ? undefined : { opacity: index === 0 ? .08 : .025 },
      itemStyle: { color: [palette.brand, palette.danger, palette.muted][index], borderRadius: bar ? 2 : undefined },
      emphasis: { focus: 'series' }, data: days.map(day => day[key]), animationDelay: bar ? (i: number) => Math.min(i * 18, 280) : 0,
    })),
  }
}
