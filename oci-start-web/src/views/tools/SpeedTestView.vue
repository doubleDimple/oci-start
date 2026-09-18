<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { DELAY_PROBE_TIMEOUT_MS, delayTestError, type DelayRegion } from '@/api/delayTest'
import { englishRegionName } from '@/views/regions/regionCoords'
import { useDelayTest } from './useDelayTest'
import DelayRegionItem from './DelayRegionItem.vue'

const { t, locale } = useI18n()
const router = useRouter()
const compact = useCompactViewport()
const {
  regions, ip, results, runState, running, autoStartPending, counts, best, average, top5,
  loadRegions, loadCurrentIp, start, stop,
} = useDelayTest()
const numberFormatter = computed(() => new Intl.NumberFormat(locale.value))
const englishRegionVariants: Record<string, string> = { 'ap-singapore-2': 'Singapore West', 'eu-madrid-1': 'Madrid 1', 'eu-madrid-3': 'Madrid 3' }
// Directory names do not depend on live measurements; keep each child's props
// stable when another region or the page-level summaries receive an update.
const regionNames = computed(() => new Map(regions.rows.map(region => [region.code, regionName(region)])))
const timeoutSeconds = computed(() => number(DELAY_PROBE_TIMEOUT_MS / 1000))
const currentStatus = computed(() => autoStartPending.value ? 'pending' : runState.value)
const summaryHint = computed(() => average.value == null && ['completed', 'stopped'].includes(runState.value)
  ? t('delayTest.noSuccess') : t('delayTest.validOnly'))
const location = computed(() => {
  const value = ip.value?.location || ''
  if (value === '内网地址') return t('delayTest.privateNetwork')
  if (value === '未知位置') return t('delayTest.unknownLocation')
  return value
})
const regionEmpty = computed(() => t(regions.loading ? 'delayTest.loadingRegions' : regions.problem ? 'delayTest.loadFailed' : 'delayTest.noRegions'))

function number(value: number) { return numberFormatter.value.format(value) }
function latency(value: number) { return t('delayTest.latency', { value: number(value) }) }
function errorText(cause: unknown) { const error = delayTestError(cause); return error.detail || t(`delayTest.errors.${error.key}`) }
function regionName(region: DelayRegion) {
  if (locale.value.startsWith('zh')) return region.simpleName || region.name || region.code
  // The shared region directory supplies English city names. Keep distinct sites
  // within one city distinguishable, as in the server's Chinese short names.
  return englishRegionVariants[region.code] || englishRegionName(region.code)
}
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push('/boot/dashboard')
}
</script>

<template>
  <section class="delay-test-page">
    <div class="delay-toolbar">
      <PageBackButton @click="back" />
      <span class="delay-run-status" role="status"><i v-if="running || autoStartPending" class="i-mdi-loading spinning" aria-hidden="true" />{{ t(`delayTest.run.${currentStatus}`) }}</span>
      <div class="delay-toolbar-actions" data-page-error-anchor><GhostBtn :disabled="running" :loading="regions.loading" @click="loadRegions"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('delayTest.refreshRegions') }}</GhostBtn><GhostBtn v-if="running || autoStartPending" @click="stop"><i class="i-mdi-stop" aria-hidden="true" />{{ t('delayTest.stop') }}</GhostBtn><PrimaryBtn :disabled="regions.loading || !!regions.problem || !regions.loaded || !regions.rows.length" :loading="running" @click="start"><i v-if="!running" class="i-mdi-lightning-bolt-outline" aria-hidden="true" />{{ t(runState === 'idle' ? 'delayTest.start' : 'delayTest.restart') }}</PrimaryBtn></div>
    </div>
    <div class="delay-content">
      <div class="delay-summary">
        <section class="delay-stat" :aria-label="t('delayTest.currentIp')">
          <h2 class="delay-stat-label"><span :title="t('delayTest.currentIpHint')">{{ t('delayTest.currentIp') }}</span><button type="button" class="delay-icon-button" :disabled="ip.loading" :title="t('delayTest.reloadIp')" :aria-label="t('delayTest.reloadIp')" @click="loadCurrentIp"><i class="i-mdi-refresh" :class="{ spinning: ip.loading }" aria-hidden="true" /></button></h2>
          <p v-if="ip.value?.ip" class="delay-stat-value delay-stat-ip">{{ ip.value.ip }}</p>
          <p v-else class="delay-stat-message">{{ t(ip.loading ? 'delayTest.loadingIp' : ip.problem ? 'delayTest.loadFailed' : 'delayTest.ipUnknown') }}</p>
          <p v-if="location" class="delay-note">{{ location }}</p>
          <PageErrorNotice v-if="ip.problem">{{ errorText(ip.problem) }}</PageErrorNotice>
        </section>
        <section class="delay-stat" :aria-label="t('delayTest.best')"><h2 class="delay-stat-label">{{ t('delayTest.best') }}</h2><p class="delay-stat-value region-name" :title="best?.code">{{ best ? regionName(best) : t('delayTest.noValue') }}</p><p v-if="best && best.latencyMs != null" class="delay-stat-value">{{ latency(best.latencyMs) }}</p><p class="delay-note">{{ summaryHint }}</p></section>
        <section class="delay-stat" :aria-label="t('delayTest.average')"><h2 class="delay-stat-label">{{ t('delayTest.average') }}</h2><p class="delay-stat-value">{{ average == null ? t('delayTest.noValue') : latency(average) }}</p><p class="delay-note">{{ summaryHint }}</p></section>
      </div>
      <div class="delay-method"><p class="delay-note">{{ t('delayTest.method') }}</p><p class="delay-note">{{ t('delayTest.measurementHint', { seconds: timeoutSeconds }) }}</p></div>
      <section class="delay-ranking" :aria-label="t('delayTest.topFive')">
        <div class="delay-section-title"><h2>{{ t('delayTest.topFive') }}</h2><span class="delay-note">{{ t('delayTest.topFiveHint') }}</span></div>
        <ol v-if="top5.length" class="delay-rank-list"><li v-for="(row, index) in top5" :key="row.code" class="delay-rank-item" :title="row.code"><span class="delay-rank-number">{{ number(index + 1) }}</span><span class="delay-rank-name">{{ regionName(row) }}</span><span class="delay-rank-time">{{ latency(row.latencyMs) }}</span></li></ol>
        <p v-else class="delay-note">{{ t(running || autoStartPending || runState === 'idle' ? 'delayTest.rankingPending' : 'delayTest.noFastRegions') }}</p>
      </section>
      <section :aria-label="t('delayTest.regions')">
        <div class="delay-section-title"><h2>{{ t('delayTest.regions') }} <span class="delay-note">{{ t('delayTest.regionCount', { count: regions.loaded ? number(regions.rows.length) : '—' }) }}</span></h2><div class="delay-legend"><span><i class="fast" aria-hidden="true" />{{ t('delayTest.fastRange') }}</span><span><i class="medium" aria-hidden="true" />{{ t('delayTest.mediumRange') }}</span><span><i class="slow" aria-hidden="true" />{{ t('delayTest.slowRange') }}</span></div></div>
        <PageErrorNotice v-if="regions.problem"><span>{{ errorText(regions.problem) }}</span><GhostBtn :disabled="running" :loading="regions.loading" @click="loadRegions">{{ t('delayTest.retry') }}</GhostBtn></PageErrorNotice>
        <MobileRecordList v-if="compact" drilldown list-id="speed-regions" :record-keys="results.map(row => row.code)" :loading="regions.loading" :aria-busy="regions.loading">
          <MobileRecordCard v-for="row in results" :key="row.code" :record-key="row.code" :summary-title="regionNames.get(row.code) || row.code" :summary-meta="row.code" :summary-status="row.status === 'success' && row.latencyMs != null ? latency(row.latencyMs) : t(`delayTest.state.${row.status}`)" :summary-tone="row.status === 'failed' ? 'danger' : row.status === 'timeout' ? 'warning' : row.status === 'success' && row.latencyMs != null ? row.latencyMs < 150 ? 'success' : 'warning' : 'neutral'">
            <template #identity><h2 class="mobile-record-title">{{ regionNames.get(row.code) || row.code }}</h2><span class="mobile-record-subtitle">{{ row.endpoint }}</span></template>
            <DelayRegionItem :row="row" :name="regionNames.get(row.code) || row.code" :number-formatter="numberFormatter" />
            <p v-for="(sample, index) in row.samples" :key="index" class="delay-note">{{ t('delayTest.sample', { index: number(index + 1), result: sample.status === 'success' && sample.latencyMs != null ? latency(sample.latencyMs) : t(`delayTest.state.${sample.status}`) }) }}</p>
          </MobileRecordCard>
          <p v-if="!results.length" class="delay-empty" role="status">{{ regionEmpty }}</p>
        </MobileRecordList>
        <div v-else class="delay-region-grid" :aria-busy="regions.loading">
          <p v-if="!results.length" class="delay-empty" role="status">{{ regionEmpty }}</p>
          <DelayRegionItem v-for="row in results" :key="row.code" :row="row" :name="regionNames.get(row.code) || row.code" :number-formatter="numberFormatter" />
        </div>
        <p class="delay-note">{{ t('delayTest.barHint') }}</p>
      </section>
    </div>
    <div class="delay-footer">
      <div v-if="counts.total" class="delay-progress"><span>{{ t('delayTest.progress', { completed: number(counts.completed), total: number(counts.total) }) }}</span><progress :value="counts.completed" :max="counts.total" :aria-label="t('delayTest.progressLabel')" /></div>
      <span v-else>{{ t(regions.loaded && !regions.rows.length ? 'delayTest.noRegions' : 'delayTest.notStarted') }}</span>
      <span v-if="counts.total">{{ t('delayTest.counts', { success: number(counts.success), timeout: number(counts.timeout), failed: number(counts.errors), cancelled: number(counts.cancelled) }) }}</span>
    </div>
  </section>
</template>

<style lang="scss" src="./delay-test.scss" />
