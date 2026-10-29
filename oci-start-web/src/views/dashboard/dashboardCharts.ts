import type { EChartsCoreOption } from 'echarts/core'
import type { ChartTheme } from '@/utils/chartTheme'
import type { MetricKey, MonitorSample } from './useDashboard'

export interface SeriesSpec { key: MetricKey; name: string; color: string }
export function trendOption(samples: MonitorSample[], series: SeriesSpec[], palette: Readonly<ChartTheme>, locale: string, unit = '%', compact = false): EChartsCoreOption {
  const first = samples[0]?.at
  const last = samples.at(-1)?.at
  const single = samples.length <= 1
  const time = (value: number) => new Date(value).toLocaleTimeString(locale, { hour12: false, hour: '2-digit', minute: '2-digit' })
  return {
    textStyle: { fontFamily: palette.fontFamily, color: palette.secondary, fontSize: 12 },
    grid: compact ? { left: 3, right: 3, top: 6, bottom: 3 } : { left: 12, right: 18, top: 24, bottom: 8, containLabel: true },
    tooltip: { show: !compact, trigger: 'axis', renderMode: 'richText', confine: true, backgroundColor: palette.surface, borderColor: palette.border, textStyle: { color: palette.text, fontFamily: palette.fontFamily, fontSize: 12 }, valueFormatter: (value: unknown) => typeof value === 'number' ? `${Number(value.toFixed(2)).toLocaleString(locale)}${unit === '%' ? '%' : unit ? ` ${unit}` : ''}` : '—' },
    xAxis: { type: 'time', show: !compact, min: first === undefined ? undefined : single ? first - 60000 : first, max: last === undefined ? undefined : single ? last + 5000 : last, splitNumber: 4, boundaryGap: false, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: palette.muted, fontSize: 11, formatter: time, hideOverlap: true }, splitLine: { show: false } },
    yAxis: { type: 'value', show: !compact, min: 0, max: unit === '%' ? 100 : undefined, interval: unit === '%' ? 25 : undefined, splitNumber: 3, axisLabel: { color: palette.muted, fontSize: 11, formatter: (value: number) => unit === '%' ? `${value}%` : value >= 1000 ? `${Number((value / 1000).toFixed(1))}k` : String(value) }, splitLine: { lineStyle: { type: 'dashed', color: palette.border, opacity: .5 } } },
    series: series.map((item, index) => ({ id: item.key, name: item.name, type: 'line', smooth: .18, connectNulls: false, showSymbol: single, symbol: 'circle', symbolSize: compact ? 4 : 7, lineStyle: { color: item.color, width: compact ? 1.8 : 2.5, type: index === 2 ? 'dashed' : 'solid' }, itemStyle: { color: item.color }, areaStyle: { color: item.color, opacity: compact ? .1 : .045 }, emphasis: { focus: 'series' }, data: samples.map(sample => [sample.at, sample[item.key]]) })),
  }
}

export function capacityOption(used: number | null, total: number | null, names: [string, string], color: string, palette: Readonly<ChartTheme>): EChartsCoreOption {
  const valid = total !== null && total > 0 && used !== null && used <= total
  return {
    tooltip: { show: valid, trigger: 'item', renderMode: 'richText', confine: true, formatter: '{b}: {d}%', backgroundColor: palette.surface, borderColor: palette.border, textStyle: { color: palette.text, fontFamily: palette.fontFamily } },
    series: [{ id: 'capacity', type: 'pie', radius: ['73%', '89%'], center: ['50%', '50%'], startAngle: 90, padAngle: valid && used! > 0 && used! < total! ? 3 : 0, label: { show: false }, silent: !valid, emphasis: { scale: false }, itemStyle: { borderRadius: 5 }, data: valid ? [{ name: names[0], value: used, itemStyle: { color } }, { name: names[1], value: total - used!, itemStyle: { color: palette.border, opacity: .28 } }] : [{ value: 1, itemStyle: { color: palette.border, opacity: .2 } }] }],
  }
}

export function outcomesOption(values: { name: string; value: number; color: string }[], palette: Readonly<ChartTheme>): EChartsCoreOption {
  return {
    grid: { left: 0, right: 0, top: 4, bottom: 4 },
    tooltip: { trigger: 'item', renderMode: 'richText', confine: true, backgroundColor: palette.surface, borderColor: palette.border, textStyle: { color: palette.text }, formatter: '{a}: {c}' },
    xAxis: { type: 'value', show: false, max: values.reduce((sum, item) => sum + item.value, 0) || 1 },
    yAxis: { type: 'category', data: [''], show: false },
    series: values.map(item => ({ name: item.name, type: 'bar', stack: 'outcome', barWidth: 14, itemStyle: { color: item.color }, data: [item.value] })),
  }
}
