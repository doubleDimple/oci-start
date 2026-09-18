<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, shallowRef } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import {
  fetchHeaderAssets, headerAssetError, streamHeaderAssetAnalysis, type HeaderAssetSummary,
} from '@/api/headerAssets'

type AnalysisState = 'idle' | 'running' | 'complete' | 'unconfirmed' | 'cancelled' | 'error'
const emit = defineEmits<{ loaded: [summary: HeaderAssetSummary] }>()
const { t, locale } = useI18n()
const visible = ref(false)
const loading = ref(false)
const summary = shallowRef<HeaderAssetSummary | null>(null)
const loadError = shallowRef<unknown>(null)
const retrievedAt = shallowRef<Date | null>(null)
const analysisState = ref<AnalysisState>('idle')
const analysisError = shallowRef<unknown>(null)
const analysisText = ref('')
const analysisStarted = shallowRef<Date | null>(null)
const output = ref<HTMLElement | null>(null)
const following = ref(true)
const running = computed(() => analysisState.value === 'running')
const canAnalyze = computed(() => Boolean(summary.value?.totalCount) && !loading.value && !running.value && !loadError.value)
const dateFormat = computed(() => new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }))
const numberFormat = computed(() => new Intl.NumberFormat(locale.value))
const costFormat = computed(() => new Intl.NumberFormat(locale.value, { minimumFractionDigits: 2, maximumFractionDigits: 2 }))
const displayCost = computed(() => summary.value ? costFormat.value.format(Number(summary.value.totalCost.replace(',', '.'))) : '—')
const analysisStatus = computed(() => {
  const keys: Record<AnalysisState, string> = {
    idle: 'aiIdle', running: 'aiPending', complete: 'aiComplete', unconfirmed: 'aiUnconfirmed',
    cancelled: 'aiCancelled', error: 'aiFailed',
  }
  return t(`headerAssets.${keys[analysisState.value]}`)
})

let disposed = false
let readVersion = 0
let analysisVersion = 0
let readController: AbortController | undefined
let analysisController: AbortController | undefined

function clearAnalysis() {
  analysisState.value = 'idle'
  analysisText.value = ''
  analysisError.value = null
  analysisStarted.value = null
  following.value = true
}

function stopReceiving(showStatus = true) {
  analysisVersion += 1
  analysisController?.abort()
  analysisController = undefined
  if (running.value && showStatus) analysisState.value = 'cancelled'
}

async function loadSummary() {
  if (disposed || !visible.value || loading.value || running.value) return
  const version = ++readVersion
  readController?.abort()
  const controller = new AbortController()
  readController = controller
  loading.value = true
  loadError.value = null
  clearAnalysis()
  try {
    const result = await fetchHeaderAssets(controller.signal)
    if (disposed || !visible.value || controller.signal.aborted || version !== readVersion) return
    summary.value = result
    retrievedAt.value = new Date()
    emit('loaded', { ...result })
  } catch (error) {
    if (disposed || !visible.value || controller.signal.aborted || version !== readVersion) return
    summary.value = null
    retrievedAt.value = null
    loadError.value = error
  } finally {
    if (!disposed && version === readVersion) {
      loading.value = false
      readController = undefined
    }
  }
}

function open() {
  if (disposed || visible.value) return
  summary.value = null
  retrievedAt.value = null
  loadError.value = null
  clearAnalysis()
  visible.value = true
  void loadSummary()
}

function closeReport() {
  visible.value = false
  readVersion += 1
  readController?.abort()
  readController = undefined
  loading.value = false
  stopReceiving(false)
  clearAnalysis()
}

function followLatest() {
  following.value = true
  if (output.value) output.value.scrollTop = output.value.scrollHeight
}

function trackScroll() {
  const element = output.value
  if (element) following.value = element.scrollHeight - element.scrollTop - element.clientHeight < 32
}

async function startAnalysis() {
  if (disposed || !visible.value || !canAnalyze.value) return
  const version = ++analysisVersion
  analysisController?.abort()
  const controller = new AbortController()
  analysisController = controller
  clearAnalysis()
  analysisState.value = 'running'
  analysisStarted.value = new Date()
  try {
    const result = await streamHeaderAssetAnalysis(controller.signal, text => {
      if (disposed || !visible.value || controller.signal.aborted || version !== analysisVersion) return
      analysisText.value += text
      if (following.value) {
        void nextTick(() => {
          if (!disposed && visible.value && version === analysisVersion && following.value) followLatest()
        })
      }
    })
    if (disposed || !visible.value || controller.signal.aborted || version !== analysisVersion) return
    analysisState.value = result.completed ? 'complete' : 'unconfirmed'
  } catch (error) {
    if (disposed || !visible.value || controller.signal.aborted || version !== analysisVersion) return
    analysisState.value = 'error'
    analysisError.value = error
  } finally {
    if (!disposed && version === analysisVersion) analysisController = undefined
  }
}

onBeforeUnmount(() => {
  disposed = true
  readVersion += 1
  readController?.abort()
  stopReceiving(false)
})

defineExpose({ open })
</script>

<template>
  <el-dialog v-model="visible" class="header-assets-dialog" :title="t('headerAssets.title')" width="min(760px, calc(100vw - 24px))" align-center append-to-body destroy-on-close @close="closeReport">
    <div class="asset-report" :aria-busy="loading || undefined">
      <div class="asset-toolbar">
        <span class="asset-provider">{{ t('headerAssets.provider') }}</span>
        <span v-if="retrievedAt" class="asset-updated">{{ t('headerAssets.updated', { time: dateFormat.format(retrievedAt) }) }}</span>
        <GhostBtn :loading="loading" :disabled="running" :aria-label="t(loadError ? 'headerAssets.retry' : 'headerAssets.refresh')" @click="loadSummary"><i class="i-mdi-refresh" aria-hidden="true" />{{ t(loadError ? 'headerAssets.retry' : 'headerAssets.refresh') }}</GhostBtn>
      </div>

      <div v-if="loading && !summary" class="asset-empty" role="status"><i class="i-mdi-chart-box-outline" aria-hidden="true" /><p>{{ t('headerAssets.loading') }}</p></div>
      <PageErrorNotice v-else-if="loadError" :title="t('headerAssets.loadFailed')">{{ headerAssetError(loadError) }}</PageErrorNotice>
      <template v-else-if="summary">
        <p class="asset-scope">{{ t('headerAssets.scope') }}</p>
        <dl class="asset-metrics">
          <div><dt>{{ t('headerAssets.totalAccounts') }}</dt><dd>{{ numberFormat.format(summary.totalCount) }}</dd></div>
          <div><dt>{{ t('headerAssets.upgradedAccounts') }}</dt><dd>{{ numberFormat.format(summary.upgradeCount) }}</dd></div>
          <div><dt>{{ t('headerAssets.otherAccounts') }}</dt><dd>{{ numberFormat.format(summary.freeCount) }}</dd></div>
          <div><dt>{{ t('headerAssets.localCost') }}</dt><dd>{{ displayCost }}</dd></div>
        </dl>
        <div class="asset-level"><span>{{ t('headerAssets.levelLabel') }}</span><strong>{{ t('headerAssets.level', { level: numberFormat.format(summary.level) }) }}</strong></div>
        <details class="asset-methodology">
          <summary>{{ t('headerAssets.methodology') }}</summary>
          <p>{{ t('headerAssets.countRule', { limit: numberFormat.format(1000) }) }}</p>
          <p>{{ t('headerAssets.upgradeRule') }}</p>
          <p>{{ t('headerAssets.costRule') }}</p>
          <p>{{ t('headerAssets.levelRule') }}</p>
        </details>
        <div v-if="summary.totalCount === 0" class="asset-zero" role="status"><strong>{{ t('headerAssets.empty') }}</strong><p>{{ t('headerAssets.emptyHint') }}</p></div>

        <section class="asset-analysis" :aria-label="t('headerAssets.aiTitle')">
          <div class="analysis-heading"><h3>{{ t('headerAssets.aiTitle') }}</h3><span v-if="analysisStarted">{{ t('headerAssets.aiStarted', { time: dateFormat.format(analysisStarted) }) }}</span></div>
          <p class="asset-hint">{{ t('headerAssets.aiHint') }}</p>
          <PageErrorNotice v-if="analysisState === 'error'" :title="analysisStatus"><p v-if="analysisError">{{ headerAssetError(analysisError) }}</p></PageErrorNotice>
          <div v-else class="analysis-status" :class="`is-${analysisState}`" role="status" aria-live="polite">
            <i v-if="running" class="i-mdi-loading asset-spin" aria-hidden="true" />
            <i v-else-if="analysisState === 'complete'" class="i-mdi-check-circle-outline" aria-hidden="true" />
            <span>{{ summary.totalCount === 0 && analysisState === 'idle' ? t('headerAssets.aiZero') : analysisStatus }}</span>
          </div>
          <pre v-if="analysisText" ref="output" class="analysis-output" tabindex="0" :aria-label="t('headerAssets.aiOutput')" @scroll="trackScroll">{{ analysisText }}</pre>
          <div v-if="analysisText && !following" class="analysis-follow"><button type="button" @click="followLatest">{{ t('headerAssets.followLatest') }}</button></div>
          <p v-if="analysisState !== 'idle'" class="receiving-hint">{{ t('headerAssets.receivingHint') }}</p>
        </section>
      </template>
    </div>
    <template #footer>
      <div class="asset-actions">
        <GhostBtn @click="closeReport">{{ t('headerAssets.close') }}</GhostBtn>
        <GhostBtn v-if="running" @click="stopReceiving()"><i class="i-mdi-stop-circle-outline" aria-hidden="true" />{{ t('headerAssets.aiStop') }}</GhostBtn>
        <PrimaryBtn v-else :disabled="!canAnalyze" @click="startAnalysis"><i class="i-mdi-auto-fix" aria-hidden="true" />{{ t(analysisState === 'idle' ? 'headerAssets.aiStart' : 'headerAssets.aiRetry') }}</PrimaryBtn>
      </div>
    </template>
  </el-dialog>
</template>

<style scoped>
:global(.header-assets-dialog) { max-width: calc(100vw - 24px); font-family: var(--sans); }
:global(.header-assets-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); }
:global(.header-assets-dialog .el-dialog__body) { max-height: min(720px, calc(100dvh - 190px)); overflow: auto; overscroll-behavior: contain; }
.asset-report { color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
.asset-toolbar { display: flex; align-items: center; flex-wrap: wrap; gap: 8px 12px; }
.asset-toolbar :deep(.btn) { min-height: 34px; margin-left: auto; padding: 7px 12px; }
.asset-toolbar i, .asset-actions i { font-size: 16px; }
.asset-provider { padding: 4px 8px; border-radius: 6px; color: var(--brand); background: var(--status-ok-bg); font-size: var(--font-size-caption); font-weight: 500; }
.asset-updated, .asset-scope, .asset-hint, .analysis-heading > span, .receiving-hint { color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; }
.asset-scope { margin: 14px 0 12px; }
.asset-metrics { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin: 0; padding: 14px 0; border-block: 1px solid var(--border); }
.asset-metrics > div { min-width: 0; }
.asset-metrics dt { color: var(--text-secondary); font-size: var(--font-size-body); line-height: 1.5; }
.asset-metrics dd { margin: 7px 0 0; font-size: var(--font-size-section); font-weight: 600; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
.asset-level { display: flex; align-items: center; flex-wrap: wrap; gap: 8px 12px; padding: 13px 0; font-size: var(--font-size-body); }
.asset-level > span:first-child { color: var(--text-secondary); }
.asset-level strong { font-weight: 500; }
.asset-methodology { padding: 10px 12px; border: 1px solid var(--border); border-radius: 9px; }
.asset-methodology summary { color: var(--text-primary); font-size: var(--font-size-body); cursor: pointer; }
.asset-methodology p { margin: 8px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.65; overflow-wrap: anywhere; }
.asset-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; min-height: 180px; color: var(--text-secondary); font-size: var(--font-size-secondary); text-align: center; }
.asset-empty > i { color: var(--brand); font-size: 30px; }
.asset-empty p { margin: 0; }
.asset-zero strong { font-size: var(--font-size-body); font-weight: 500; }
.asset-zero p { margin: 7px 0 0; font-size: var(--font-size-secondary); line-height: 1.6; }
.asset-zero { margin-top: 14px; padding: 12px; border-radius: 9px; background: var(--bg-search); }
.asset-zero p { color: var(--text-secondary); }
.asset-analysis { margin-top: 18px; padding-top: 16px; border-top: 1px solid var(--border); }
.analysis-heading { display: flex; align-items: baseline; justify-content: space-between; flex-wrap: wrap; gap: 6px 12px; }
.analysis-heading h3 { margin: 0; font-size: var(--font-size-section); font-weight: 600; }
.asset-hint { margin: 7px 0 12px; }
.analysis-status { display: flex; align-items: flex-start; gap: 7px; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; }
.analysis-status > i { flex: none; margin-top: 2px; font-size: 16px; }
.analysis-status.is-complete { color: var(--status-ok); }
.analysis-status.is-unconfirmed { color: var(--status-danger); }
.analysis-output { max-height: min(320px, 38dvh); min-height: 120px; overflow: auto; overscroll-behavior: contain; margin: 12px 0 0; padding: 13px 14px; border: 1px solid var(--border); border-radius: 10px; background: var(--bg-search); color: var(--text-primary); font: var(--font-size-body)/1.75 var(--mono); white-space: pre-wrap; overflow-wrap: anywhere; }
.analysis-follow { display: flex; justify-content: flex-end; margin-top: 6px; }
.analysis-follow button { border: 0; padding: 4px 0; background: transparent; color: var(--brand); font: var(--font-size-body) var(--sans); cursor: pointer; }
.analysis-output:focus-visible, .asset-methodology summary:focus-visible, .analysis-follow button:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.receiving-hint { margin: 10px 0 0; }
.asset-actions { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 8px; }
.asset-spin { animation: header-asset-spin 1s linear infinite; }
@keyframes header-asset-spin { to { transform: rotate(360deg); } }
@media (max-width: 600px) {
  .asset-metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
  .asset-updated { order: 1; width: 100%; }
  .asset-actions :deep(.btn) { flex: 1; min-width: 0; white-space: normal; }
}
@media (prefers-reduced-motion: reduce) { .asset-spin { animation: none; } }
</style>
