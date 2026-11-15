import type { EChartsCoreOption } from 'echarts/core'
import type { ChartTheme } from '@/utils/chartTheme'
import type { MetricKey, MonitorSample } from './useDashboard'
import { linePointer, tooltip } from './businessCharts'

export interface SeriesSpec { key: MetricKey; name: string; color: string }

/** Value + unit for tooltips; KiB/s switches to MiB/s like the metric cards. */
function formatValue(value: number, unit: string, locale: string) {
  const fixed = (n: number) => Number(n.toFixed(2)).toLocaleString(locale)
  if (unit === '%') return `${fixed(value)}%`
  if (unit === 'KiB/s') return value >= 1024 ? `${fixed(value / 1024)} MiB/s` : `${fixed(value)} KiB/s`
  return unit ? `${fixed(value)} ${unit}` : Math.round(value).toLocaleString(locale)
}
function axisValue(value: number, unit: string) {
  if (unit === '%') return `${value}%`
  if (unit === 'KiB/s') return value >= 1024 ? `${Number((value / 1024).toFixed(1))}M` : String(value)
  return value >= 1000 ? `${Number((value / 1000).toFixed(1))}k` : String(value)
}

export function trendOption(samples: MonitorSample[], series: SeriesSpec[], palette: Readonly<ChartTheme>, locale: string, unit = '%', compact = false): EChartsCoreOption {
  const first = samples[0]?.at
  const last = samples.at(-1)?.at
  const single = samples.length <= 1
  const time = (value: number) => new Date(value).toLocaleTimeString(locale, { hour12: false, hour: '2-digit', minute: '2-digit' })
  return {
    textStyle: { fontFamily: palette.fontFamily, color: palette.secondary, fontSize: 12 },
    grid: compact ? { left: 3, right: 3, top: 6, bottom: 3 } : { left: 6, right: 12, top: 22, bottom: 6, containLabel: true },
    tooltip: { ...tooltip(palette), show: !compact, trigger: 'axis', axisPointer: linePointer(palette), valueFormatter: (value: unknown) => typeof value === 'number' ? formatValue(value, unit, locale) : '—' },
    xAxis: { type: 'time', show: !compact, min: first === undefined ? undefined : single ? first - 60000 : first, max: last === undefined ? undefined : single ? last + 5000 : last, splitNumber: 4, boundaryGap: false, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: palette.muted, fontSize: 11, formatter: time, hideOverlap: true }, splitLine: { show: false } },
    yAxis: { type: 'value', show: !compact, min: 0, max: unit === '%' ? 100 : undefined, interval: unit === '%' ? 25 : undefined, splitNumber: 3, axisLabel: { color: palette.muted, fontSize: 11, formatter: (value: number) => axisValue(value, unit) }, splitLine: { lineStyle: { type: 'dashed', color: palette.border, opacity: .5 } } },
    series: series.map((item, index) => ({
      id: item.key, name: item.name, type: 'line', smooth: .25, smoothMonotone: 'x', connectNulls: false,
      showSymbol: single, symbol: 'circle', symbolSize: compact ? 4 : 6,
      lineStyle: { color: item.color, width: compact ? 1.8 : 2.5, type: index === 2 ? 'dashed' : 'solid' },
      itemStyle: { color: item.color }, areaStyle: { color: item.color, opacity: compact ? .1 : index === 0 ? .08 : .025 },
      emphasis: { focus: 'series' }, data: samples.map(sample => [sample.at, sample[item.key]]),
    })),
  }
}

/**
 * Processes and threads differ by an order of magnitude; each line gets its own
 * hidden axis (with headroom) so both stay readable. Tooltip shows real values.
 */
export function activityOption(samples: MonitorSample[], series: SeriesSpec[], palette: Readonly<ChartTheme>, locale: string): EChartsCoreOption {
  const base = trendOption(samples, series, palette, locale, '', true) as { series: Record<string, unknown>[]; tooltip: Record<string, unknown> }
  return {
    ...base,
    grid: { left: 3, right: 3, top: 10, bottom: 3 },
    tooltip: { ...base.tooltip, show: true },
    yAxis: series.map(() => ({ type: 'value', show: false, min: 0, max: (extent: { max: number }) => Math.max(1, extent.max) * 1.18 })),
    series: base.series.map((item, index) => ({ ...item, yAxisIndex: index })),
  }
}

export function capacityOption(used: number | null, total: number | null, names: [string, string], color: string, palette: Readonly<ChartTheme>): EChartsCoreOption {
  const valid = total !== null && total > 0 && used !== null && used <= total
  return {
    tooltip: { ...tooltip(palette), show: valid, trigger: 'item', formatter: '{b}: {d}%' },
    series: [{ id: 'capacity', type: 'pie', radius: ['72%', '91%'], center: ['50%', '50%'], startAngle: 90, padAngle: valid && used! > 0 && used! < total! ? 3 : 0, label: { show: false }, labelLine: { show: false }, silent: !valid, emphasis: { scale: true, scaleSize: 4 }, itemStyle: { borderRadius: 5 }, data: valid ? [{ name: names[0], value: used, itemStyle: { color } }, { name: names[1], value: total - used!, itemStyle: { color: palette.border, opacity: .3 } }] : [{ value: 1, itemStyle: { color: palette.border, opacity: .3 } }] }],
  }
}

/** One stacked bar on a faint track; only the outer ends are rounded. */
export function outcomesOption(values: { name: string; value: number; color: string }[], palette: Readonly<ChartTheme>, locale: string): EChartsCoreOption {
  const total = values.reduce((sum, item) => sum + item.value, 0)
  const visible = values.map((item, index) => item.value > 0 ? index : -1).filter(index => index >= 0)
  const head = visible[0], tail = visible.at(-1)
  const radius = (index: number) => { const left = index === head ? 6 : 0, right = index === tail ? 6 : 0; return [left, right, right, left] }
  return {
    grid: { left: 0, right: 0, top: 0, bottom: 0 },
    tooltip: { ...tooltip(palette), trigger: 'item', formatter: (item: { seriesName: string; value: number }) => `${item.seriesName}: ${item.value.toLocaleString(locale)} (${total ? Number((item.value / total * 100).toFixed(1)).toLocaleString(locale) : 0}%)` },
    xAxis: { type: 'value', show: false, min: 0, max: total || 1 },
    yAxis: { type: 'category', data: [''], show: false },
    series: values.map((item, index) => ({
      id: item.name, name: item.name, type: 'bar', stack: 'outcome', barWidth: 12,
      showBackground: index === 0, backgroundStyle: { color: palette.border, opacity: .12, borderRadius: 6 },
      itemStyle: { color: item.color, opacity: index === 2 ? .55 : 1, borderRadius: radius(index) },
      emphasis: { itemStyle: { opacity: .85 } }, animationDelay: index * 120,
      data: [item.value],
    })),
  }
}
