<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import VersionStatusRing from './VersionStatusRing.vue'
import {
  executeHeaderUpdate, fetchHeaderVersion, headerVersionProblem, headerVersionSnapshot,
  headerVersionUpdateState, headerVersionUpdateProblem, headerVersionUpdateStartedAt, type HeaderVersionProblem,
} from '@/api/headerVersion'

const { t } = useI18n()
const visible = ref(false)
const confirmationVisible = ref(false)
const info = headerVersionSnapshot
const loading = ref(false)
const loadProblem = ref<HeaderVersionProblem | null>(null)
const updateProblem = headerVersionUpdateProblem
const updateState = headerVersionUpdateState
const targetVersion = ref<string | null>(null)
const supportExpanded = ref(false)
const copyState = ref<'idle' | 'copying' | 'copied' | 'failed'>('idle')
const supportAddress = 'TMHTdWVm6ThvhihWqM1ViSDKMMsGcCBHtT'
const supportMethods = [
  { name: 'wechat', alt: 'wechatQr', src: '/images/weixin.JPG' },
  { name: 'binance', alt: 'binanceQr', src: '/images/binance_qr.jpg' },
]

let disposed = false
let readGeneration = 0
let readController: AbortController | undefined

const starting = computed(() => updateState.value === 'starting')
const submitted = computed(() => updateState.value === 'started' || updateState.value === 'unknown')
const canUpdate = computed(() => !!info.value?.needUpdate && !loading.value && !loadProblem.value && !starting.value && !submitted.value)
const updateLabel = computed(() => info.value?.latestVersion
  ? t('headerVersion.updateAvailableVersion', { version: info.value.latestVersion })
  : t('headerVersion.updateAvailable'))
const deploymentLabel = computed(() => {
  const type = info.value?.deployType
  if (type === 'SSH') return t('headerVersion.deploySsh')
  if (type === 'DOCKER') return t('headerVersion.deployDocker')
  return type || t('headerVersion.unavailable')
})
const stateTitle = computed(() => {
  if (starting.value) return t('headerVersion.startingTitle')
  if (updateState.value === 'started') return t('headerVersion.startedTitle')
  if (updateState.value === 'unknown') return t('headerVersion.unknownTitle')
  return t('headerVersion.failedTitle')
})
const stateHint = computed(() => {
  if (starting.value) return t('headerVersion.startingHint')
  if (updateState.value === 'started') return t('headerVersion.startedHint')
  if (updateState.value === 'unknown') return t('headerVersion.unknownHint')
  return problemText(updateProblem.value)
})
const summaryTitle = computed(() => updateState.value !== 'idle' ? stateTitle.value
  : loading.value && !info.value ? t('headerVersion.loading') : !info.value ? t('headerVersion.unavailable')
    : t(info.value.needUpdate ? 'headerVersion.discoveredUpdate' : 'headerVersion.noUpdate'))

function problemText(problem: HeaderVersionProblem | null): string {
  return problem ? problem.detail || t(`headerVersion.${problem.key}`) : ''
}

async function readVersion() {
  if (disposed || starting.value) return
  const generation = ++readGeneration
  const previousSnapshot = info.value
  readController?.abort()
  const controller = new AbortController()
  readController = controller
  loading.value = true
  loadProblem.value = null
  try {
    await fetchHeaderVersion(controller.signal)
  } catch (error) {
    if (!disposed && generation === readGeneration && !controller.signal.aborted && info.value === previousSnapshot) {
      loadProblem.value = headerVersionProblem(error)
    }
  } finally {
    if (!disposed && generation === readGeneration) loading.value = false
  }
}

function open() {
  visible.value = true
  void readVersion()
}

function close() {
  visible.value = false
}

function requestUpdate() {
  if (!canUpdate.value) return
  targetVersion.value = info.value?.latestVersion || null
  confirmationVisible.value = true
}

async function confirmUpdate() {
  if (!canUpdate.value || !confirmationVisible.value) return
  confirmationVisible.value = false
  try {
    await executeHeaderUpdate()
  } catch {
    // The shared update state retains the result even after this header is unmounted.
  }
}

function onSupportToggle(event: Event) {
  supportExpanded.value = (event.currentTarget as HTMLDetailsElement).open
}

function onQrKeydown(event: KeyboardEvent) {
  if (event.key !== 'Enter' && event.key !== ' ') return
  event.preventDefault()
  // ElImage opens its viewer from the inner image click, but has no keyboard handler.
  const image = (event.currentTarget as HTMLElement).querySelector<HTMLImageElement>('img')
  image?.click()
}

async function copyAddress() {
  if (copyState.value === 'copying') return
  copyState.value = 'copying'
  try {
    await navigator.clipboard.writeText(supportAddress)
    if (!disposed) copyState.value = 'copied'
  } catch {
    if (!disposed) copyState.value = 'failed'
  }
}

defineExpose({ open })
watch(info, (next, previous) => {
  loadProblem.value = null
  if (confirmationVisible.value && (!next?.needUpdate
    || (next.latestVersion || null) !== targetVersion.value
    || next.deployType !== previous?.deployType)) {
    confirmationVisible.value = false
  }
})
onMounted(() => { void readVersion() })
onBeforeUnmount(() => {
  disposed = true
  ++readGeneration
  readController?.abort()
  // The bounded update request is owned by the shared API state and survives route changes.
})
</script>

<template>
  <button v-if="info?.needUpdate" type="button" class="header-update-button" :title="updateLabel" :aria-label="updateLabel" @click="open">
    <i class="i-mdi-tray-arrow-up" aria-hidden="true" />
    <span>{{ t('headerVersion.updateAvailable') }}</span>
  </button>

  <el-dialog
    v-model="visible" class="version-dialog" :title="t('headerVersion.dialogTitle')" width="min(720px, calc(100vw - 32px))" align-center
    append-to-body :close-on-click-modal="!starting" :close-on-press-escape="!starting" :show-close="!starting"
  >
    <div class="version-content">
      <PageErrorNotice v-if="loadProblem" :title="t('headerVersion.loadFailed')">
        <div>
          <p>{{ problemText(loadProblem) }}</p>
          <p v-if="info">{{ t('headerVersion.retainedInfo') }}</p>
        </div>
      </PageErrorNotice>

      <div class="version-hero">
        <VersionStatusRing :active="visible" :info="info" :state="updateState" :started-at="headerVersionUpdateStartedAt" :loading="loading" />
        <div class="version-summary">
          <div class="version-summary-status" :class="{ 'has-update': info?.needUpdate }" role="status">
            <span class="version-status-mark"><i :class="starting ? 'i-mdi-loading version-spin' : updateState === 'failed' || updateState === 'unknown' ? 'i-mdi-information-outline' : info?.needUpdate ? 'i-mdi-tray-arrow-up' : 'i-mdi-check'" aria-hidden="true" /></span>
            <strong>{{ summaryTitle }}</strong>
          </div>
          <dl class="version-facts" :aria-busy="loading">
            <div><dt>{{ t('headerVersion.currentVersion') }}</dt><dd>{{ info?.currentVersion || t('headerVersion.unavailable') }}</dd></div>
            <div><dt>{{ t('headerVersion.latestVersion') }}</dt><dd class="version-target">{{ info?.latestVersion || t('headerVersion.unavailable') }}</dd></div>
            <div><dt>{{ t('headerVersion.deployType') }}</dt><dd><i :class="info?.deployType === 'DOCKER' ? 'i-mdi-docker' : 'i-mdi-console'" aria-hidden="true" />{{ deploymentLabel }}</dd></div>
          </dl>
          <p class="version-source"><i class="i-mdi-source-branch" aria-hidden="true" />{{ t('headerVersion.cachedHint') }}</p>
        </div>
      </div>

      <PageErrorNotice v-if="updateState === 'failed'" :title="stateTitle">{{ stateHint }}</PageErrorNotice>
      <div v-else-if="updateState !== 'idle'" class="version-notice" :class="`is-${updateState}`" role="status" aria-live="polite">
        <i class="i-mdi-information-outline" aria-hidden="true" /><p>{{ stateHint }}</p>
      </div>

      <nav class="version-links" :aria-label="t('headerVersion.projectLinks')">
        <a href="https://github.com/doubleDimple/oci-start" target="_blank" rel="noopener noreferrer"><i class="i-mdi-github" aria-hidden="true" />{{ t('headerVersion.repository') }}</a>
        <a href="https://github.com/doubleDimple/oci-start/releases" target="_blank" rel="noopener noreferrer"><i class="i-mdi-source-branch" aria-hidden="true" />{{ t('headerVersion.releases') }}</a>
        <a href="https://t.me/+M7XhteVCMMU5ZDhh" target="_blank" rel="noopener noreferrer"><i class="i-mdi-telegram" aria-hidden="true" />{{ t('headerVersion.community') }}</a>
      </nav>

      <details class="version-support" @toggle="onSupportToggle">
        <summary><i class="i-mdi-chevron-right" aria-hidden="true" /><span>{{ t('headerVersion.support') }}</span><span class="version-byline">{{ t('headerVersion.author') }}</span></summary>
        <div v-if="supportExpanded" class="version-support-body">
          <p class="support-hint">{{ t('headerVersion.supportHint') }}</p>
          <div class="support-methods">
            <div v-for="method in supportMethods" :key="method.name" class="support-method">
              <el-image class="support-qr" :src="method.src" :alt="t(`headerVersion.${method.alt}`)" :preview-src-list="[method.src]" preview-teleported fit="contain" role="button" tabindex="0" :aria-label="t(`headerVersion.${method.alt}`)" @keydown="onQrKeydown">
                <template #error><PageErrorNotice :title="t(`headerVersion.${method.alt}`)">{{ t('headerVersion.imageUnavailable') }}</PageErrorNotice></template>
              </el-image>
              <strong>{{ t(`headerVersion.${method.name}`) }}</strong>
            </div>
          </div>
          <div class="support-address">
            <label for="header-version-support-address">{{ t('headerVersion.address') }}</label>
            <input id="header-version-support-address" :value="supportAddress" readonly spellcheck="false" />
            <button type="button" class="version-text-button" :disabled="copyState === 'copying'" @click="copyAddress">
              <i class="i-mdi-content-copy" aria-hidden="true" />
              {{ copyState === 'copied' ? t('headerVersion.copied') : t('headerVersion.copyAddress') }}
            </button>
            <PageErrorNotice v-if="copyState === 'failed'">{{ t('headerVersion.copyFailed') }}</PageErrorNotice>
            <span v-else-if="copyState === 'copied'" class="version-sr-only" role="status">{{ t('headerVersion.copied') }}</span>
          </div>
        </div>
      </details>
    </div>
    <template #footer>
      <div class="version-actions">
        <GhostBtn v-if="!submitted" :loading="loading" :disabled="starting" @click="readVersion"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('headerVersion.readAgain') }}</GhostBtn>
        <div class="version-actions-end">
          <GhostBtn :disabled="starting" @click="close">{{ t('headerVersion.close') }}</GhostBtn>
          <a v-if="submitted" class="version-login-link" href="/login">{{ t('headerVersion.returnLogin') }}</a>
          <PrimaryBtn v-else-if="info?.needUpdate" :loading="starting" :disabled="!canUpdate" @click="requestUpdate"><i v-if="!starting" class="i-mdi-tray-arrow-up" aria-hidden="true" />{{ t('headerVersion.update') }}</PrimaryBtn>
        </div>
      </div>
    </template>
  </el-dialog>

  <el-dialog v-model="confirmationVisible" class="version-confirm-dialog" :title="t('headerVersion.confirmTitle')" width="min(460px, calc(100vw - 32px))" align-center append-to-body :close-on-click-modal="false">
    <div class="version-confirm">
      <div class="confirm-version-route">
        <div><span>{{ t('headerVersion.currentVersion') }}</span><strong>{{ info?.currentVersion || t('headerVersion.unavailable') }}</strong></div>
        <i class="i-mdi-arrow-right" aria-hidden="true" />
        <div><span>{{ t('headerVersion.latestVersion') }}</span><strong>{{ targetVersion || t('headerVersion.unavailable') }}</strong></div>
      </div>
      <p>{{ t('headerVersion.confirmDescription') }}</p>
      <p v-if="targetVersion" class="confirm-target">{{ t('headerVersion.confirmVersion', { version: targetVersion }) }}</p>
      <p class="confirm-hint">{{ t('headerVersion.confirmHint') }}</p>
    </div>
    <template #footer>
      <div class="version-actions-end">
        <GhostBtn @click="confirmationVisible = false">{{ t('headerVersion.cancel') }}</GhostBtn>
        <PrimaryBtn :disabled="!canUpdate" @click="confirmUpdate">{{ t('headerVersion.confirmUpdate') }}</PrimaryBtn>
      </div>
    </template>
  </el-dialog>
</template>

<style scoped lang="scss">
:global(.el-dialog.version-dialog) { --el-dialog-padding-primary: 24px; overflow: hidden; }
:global(.version-dialog .el-dialog__header) { padding-bottom: 14px; }
:global(.version-dialog .el-dialog__footer) { padding-top: 20px; }
.header-update-button {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  min-height: 34px;
  padding: 6px 11px;
  border: 1px solid color-mix(in srgb, var(--brand) 25%, var(--border));
  border-radius: var(--r-pill);
  background: var(--brand-subtle);
  color: var(--brand);
  font: 600 var(--font-size-body)/1.4 var(--sans);
  cursor: pointer;
  white-space: nowrap;
  transition: background-color 160ms ease, border-color 160ms ease;
  &:hover { background: var(--bg-hover); border-color: var(--brand); }
}
.version-content, .version-confirm, .version-actions, .version-actions-end {
  min-width: 0;
  color: var(--text-primary);
  font: var(--font-size-body)/1.5 var(--sans);
}
.version-content { max-height: 65vh; max-height: 65dvh; overflow: auto; overscroll-behavior: contain; scrollbar-width: thin; }
.version-hero { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); align-items: center; gap: 32px; padding: 8px 0 24px; }
.version-summary { min-width: 0; }
.version-summary-status { display: flex; align-items: center; gap: 9px; margin-bottom: 22px; font-size: 16px; line-height: 1.5; strong { font-weight: 600; } }
.version-status-mark { display: flex; align-items: center; justify-content: center; flex-shrink: 0; width: 32px; height: 32px; border-radius: 10px; background: var(--brand-subtle); color: var(--brand); font-size: 18px; }
.version-source { display: flex; gap: 7px; margin: 20px 0 0; color: var(--text-secondary); font-size: 12px; line-height: 1.6; i { flex-shrink: 0; margin-top: 3px; } }
.version-byline { margin-left: auto; color: var(--text-secondary); font-size: 12px; font-weight: 400; }
.version-notice {
  display: flex;
  gap: 10px;
  padding: 13px;
  margin-bottom: 18px;
  border-radius: var(--r-sm);
  background: var(--brand-subtle);
  color: var(--text-primary);
  > i { flex-shrink: 0; margin-top: 3px; color: var(--brand); }
  p { margin: 0; font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
  &.is-unknown { background: var(--status-warn-bg); > i { color: var(--status-warn); } }
}
.support-hint { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.version-facts {
  display: grid;
  gap: 14px;
  margin: 0;
  > div { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; min-width: 0; }
  dt { color: var(--text-secondary); font-size: var(--font-size-secondary); }
  dd { display: flex; align-items: center; justify-content: flex-end; gap: 6px; max-width: 65%; margin: 0; overflow-wrap: anywhere; font-weight: 550; font-variant-numeric: tabular-nums; text-align: right; i { flex-shrink: 0; color: var(--text-secondary); } }
  .version-target { color: var(--brand); }
}
.version-links {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin: 0 0 20px;
  a { display: inline-flex; flex: 1; justify-content: center; align-items: center; gap: 7px; padding: 11px 10px; border-radius: var(--r-sm); background: var(--bg-search); color: var(--text-primary); text-decoration: none; white-space: nowrap; font-size: var(--font-size-secondary); transition: background-color 160ms ease, color 160ms ease; i { font-size: 17px; } }
  a:hover { background: var(--brand-subtle); color: var(--brand); }
}
.version-support { border-top: 1px solid var(--border); padding-top: 14px;
  summary { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; min-height: 30px; cursor: pointer; font-weight: 500; font-size: var(--font-size-secondary); list-style: none; &::-webkit-details-marker { display: none; } > i { color: var(--text-secondary); transition: transform 180ms ease; } }
  &[open] summary > i { transform: rotate(90deg); }
}
.version-support-body { padding-top: 8px; }
.support-hint { margin: 0 0 14px; }
.support-methods { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.support-method { min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 8px; strong { font-weight: 600; } }
.support-qr { width: min(144px, 100%); height: 144px; border: 1px solid var(--border); border-radius: var(--r-sm); }
.support-address {
  display: grid;
  gap: 7px;
  margin-top: 18px;
  label { color: var(--text-secondary); }
  input { box-sizing: border-box; width: 100%; min-width: 0; padding: 9px 11px; border: 1px solid var(--border); border-radius: var(--r-sm); color: var(--text-primary); background: var(--bg-search); font: var(--font-size-body)/1.5 var(--mono); }
  .version-text-button { justify-self: start; }
}
.version-text-button { display: inline-flex; align-items: center; gap: 6px; border: 0; padding: 5px 0; background: transparent; color: var(--brand); font: inherit; cursor: pointer; &:disabled { cursor: default; opacity: .6; } }
.version-actions { display: flex; width: 100%; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; }
.version-actions-end { display: flex; justify-content: flex-end; align-items: center; flex-wrap: wrap; gap: 8px; margin-inline-start: auto; }
.version-login-link { display: inline-flex; align-items: center; justify-content: center; min-height: 40px; box-sizing: border-box; padding: 9px 16px; border-radius: var(--r-pill); background: var(--brand-solid); color: var(--text-on-solid); text-decoration: none; font-weight: 600; &:hover { background: var(--brand-solid-hover); } }
.version-confirm { p { margin: 0 0 14px; } .confirm-target { font-weight: 600; } .confirm-hint { margin-bottom: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); } }
.confirm-version-route { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); align-items: center; gap: 18px; padding: 18px; margin-bottom: 20px; border-radius: var(--r-sm); background: var(--brand-subtle); > div { display: grid; gap: 5px; min-width: 0; } span { color: var(--text-secondary); font-size: var(--font-size-secondary); } strong { font-size: 20px; font-weight: 600; overflow-wrap: anywhere; font-variant-numeric: tabular-nums; } > div:last-child strong, > i { color: var(--brand); } > i { font-size: 22px; } }
.header-update-button:focus-visible, .version-links a:focus-visible, .version-support summary:focus-visible, .version-text-button:focus-visible, .support-address input:focus-visible, .version-login-link:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.support-qr :deep(img:focus-visible) { outline: 2px solid var(--brand); outline-offset: -3px; }
.version-spin { animation: version-spin 800ms linear infinite; }
.version-sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; border: 0; }
@keyframes version-spin { to { transform: rotate(360deg); } }
@media (max-width: 600px) { .version-hero { grid-template-columns: minmax(0, 1fr); gap: 24px; padding-top: 0; } .version-summary-status { margin-bottom: 16px; font-size: 15px; } .version-source { margin-top: 16px; } .version-facts { gap: 10px; } .version-links { gap: 6px; } .version-links a { padding: 10px 7px; gap: 5px; } .version-byline { font-size: 11px; } }
@media (max-width: 520px) { .version-actions > :deep(.btn) { flex: 1; } .version-actions-end { width: 100%; > :deep(.btn), > .version-login-link { flex: 1; white-space: nowrap; } } }
@media (prefers-reduced-motion: reduce) { .header-update-button, .version-links a, .version-support summary > i { transition: none; } .version-spin { animation: none; } }
</style>
