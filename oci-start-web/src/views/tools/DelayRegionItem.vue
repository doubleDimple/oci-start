<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { DELAY_PROBE_TIMEOUT_MS } from '@/api/delayTest'
import type { DelayRegionResult } from './useDelayTest'

const props = defineProps<{ row: DelayRegionResult; name: string; numberFormatter: Intl.NumberFormat }>()
const { t } = useI18n()

// Only this row's measurements, the locale and the shared formatter invalidate
// its text. Page summaries and other regions can update without reformatting it.
const presentation = computed(() => {
  const row = props.row
  const number = (value: number) => props.numberFormatter.format(value)
  const hasLatency = row.status === 'success' && row.latencyMs != null
  const tone = row.latencyMs == null ? '' : row.latencyMs < 150 ? 'fast' : row.latencyMs < 300 ? 'medium' : 'slow'
  const sampleHint = row.samples.map((sample, index) => t('delayTest.sample', {
    index: number(index + 1),
    result: sample.status === 'success' && sample.latencyMs != null
      ? t('delayTest.latency', { value: number(sample.latencyMs) }) : t(`delayTest.state.${sample.status}`),
  })).join('\n')
  let explanation = ''
  if (row.status === 'timeout') explanation = t('delayTest.timeoutHint', { seconds: number(DELAY_PROBE_TIMEOUT_MS / 1000) })
  else if (row.status === 'failed') explanation = t('delayTest.failedHint')
  else if (row.status === 'cancelled') explanation = t('delayTest.cancelledHint')
  return {
    testing: row.status === 'testing', hasLatency, tone, sampleHint,
    latency: hasLatency ? number(row.latencyMs!) : '',
    status: row.status === 'testing' && row.attempt === 2 ? t('delayTest.waitingSecond') : t(`delayTest.state.${row.status}`),
    resultHint: [explanation, sampleHint].filter(Boolean).join('\n'),
    toneLabel: hasLatency ? t(`delayTest.${tone}`) : '',
    sampleCount: hasLatency ? t('delayTest.sampleCount', { count: number(row.samples.filter(sample => sample.status === 'success').length) }) : '',
    currentSample: row.status === 'testing' ? t('delayTest.sample', { index: number(row.attempt || 1), result: t('delayTest.state.testing') }) : '',
    barWidth: hasLatency ? `${Math.min(100, Math.max(0, row.latencyMs! / 500 * 100))}%` : '0%',
  }
})
</script>

<template>
  <article class="delay-region" :class="{ testing: presentation.testing }">
    <header class="delay-region-header"><h3 :title="row.endpoint">{{ name }}</h3><span class="delay-region-code" :title="row.code">{{ row.code }}</span></header>
    <p class="delay-region-value" :title="presentation.resultHint"><template v-if="presentation.hasLatency"><strong>{{ presentation.latency }}</strong><span>ms</span></template><span v-else>{{ presentation.status }}</span></p>
    <div class="delay-region-detail"><template v-if="presentation.hasLatency"><span>{{ presentation.toneLabel }}</span><span :title="presentation.sampleHint">{{ presentation.sampleCount }}</span></template><span v-else-if="presentation.testing">{{ presentation.currentSample }}</span></div>
    <div class="delay-latency-bar" aria-hidden="true"><span v-if="presentation.hasLatency" :class="presentation.tone" :style="{ width: presentation.barWidth }" /></div>
  </article>
</template>
