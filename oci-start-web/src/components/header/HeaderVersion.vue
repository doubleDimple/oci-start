<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import {
  executeHeaderUpdate, fetchHeaderVersion, headerVersionProblem, headerVersionSnapshot,
  headerVersionUpdateState, headerVersionUpdateProblem, type HeaderVersionProblem,
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
    v-model="visible" :title="t('headerVersion.about')" width="min(600px, calc(100vw - 32px))"
    append-to-body :close-on-click-modal="!starting" :close-on-press-escape="!starting" :show-close="!starting"
  >
    <div class="version-content">
      <div class="version-byline">{{ t('headerVersion.author') }}</div>

      <div v-if="updateState !== 'idle'" class="version-notice" :class="`is-${updateState}`" role="status" aria-live="polite">
        <i :class="starting ? 'i-mdi-loading version-spin' : submitted ? 'i-mdi-information-outline' : 'i-mdi-alert-circle-outline'" aria-hidden="true" />
        <div>
          <strong>{{ stateTitle }}</strong>
          <p>{{ stateHint }}</p>
          <p v-if="updateState === 'started'">{{ t('headerVersion.estimatedWait') }}</p>
        </div>
      </div>

      <div v-if="loadProblem" class="version-notice is-failed" role="alert">
        <i class="i-mdi-alert-circle-outline" aria-hidden="true" />
        <div>
          <strong>{{ t('headerVersion.loadFailed') }}</strong>
          <p>{{ problemText(loadProblem) }}</p>
          <p v-if="info">{{ t('headerVersion.retainedInfo') }}</p>
        </div>
      </div>
      <p v-if="loading && !info" class="version-loading" role="status">{{ t('headerVersion.loading') }}</p>
      <dl class="version-facts" :aria-busy="loading">
        <div><dt>{{ t('headerVersion.currentVersion') }}</dt><dd>{{ info?.currentVersion || t('headerVersion.unavailable') }}</dd></div>
        <div><dt>{{ t('headerVersion.latestVersion') }}</dt><dd>{{ info?.latestVersion || t('headerVersion.unavailable') }}</dd></div>
        <div><dt>{{ t('headerVersion.deployType') }}</dt><dd>{{ deploymentLabel }}</dd></div>
      </dl>
      <div class="version-cache-row">
        <span v-if="info" class="version-status" :class="{ 'has-update': info.needUpdate }">
          {{ info.needUpdate ? t('headerVersion.updateAvailable') : t('headerVersion.noUpdate') }}
        </span>
        <span>{{ t('headerVersion.cachedHint') }}</span>
      </div>

      <nav class="version-links" :aria-label="t('headerVersion.projectLinks')">
        <a href="https://github.com/doubleDimple/oci-start" target="_blank" rel="noopener noreferrer"><i class="i-mdi-github" aria-hidden="true" />{{ t('headerVersion.repository') }}</a>
        <a href="https://github.com/doubleDimple/oci-start/releases" target="_blank" rel="noopener noreferrer"><i class="i-mdi-source-branch" aria-hidden="true" />{{ t('headerVersion.releases') }}</a>
        <a href="https://t.me/+M7XhteVCMMU5ZDhh" target="_blank" rel="noopener noreferrer"><i class="i-mdi-telegram" aria-hidden="true" />{{ t('headerVersion.community') }}</a>
      </nav>

      <details class="version-support" @toggle="onSupportToggle">
        <summary>{{ t('headerVersion.support') }}</summary>
        <div v-if="supportExpanded" class="version-support-body">
          <p class="support-hint">{{ t('headerVersion.supportHint') }}</p>
          <div class="support-methods">
            <div v-for="method in supportMethods" :key="method.name" class="support-method">
              <el-image class="support-qr" :src="method.src" :alt="t(`headerVersion.${method.alt}`)" :preview-src-list="[method.src]" preview-teleported fit="contain" role="button" tabindex="0" :aria-label="t(`headerVersion.${method.alt}`)" @keydown="onQrKeydown">
                <template #error><span class="qr-error">{{ t('headerVersion.imageUnavailable') }}</span></template>
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
            <p v-if="copyState === 'failed'" class="copy-error" role="alert">{{ t('headerVersion.copyFailed') }}</p>
            <span v-else-if="copyState === 'copied'" class="version-sr-only" role="status">{{ t('headerVersion.copied') }}</span>
          </div>
        </div>
      </details>
    </div>
    <template #footer>
      <div class="version-actions">
        <GhostBtn v-if="!submitted" :loading="loading" :disabled="starting" @click="readVersion">{{ t('headerVersion.readAgain') }}</GhostBtn>
        <div class="version-actions-end">
          <GhostBtn :disabled="starting" @click="close">{{ t('headerVersion.close') }}</GhostBtn>
          <a v-if="submitted" class="version-login-link" href="/login">{{ t('headerVersion.returnLogin') }}</a>
          <PrimaryBtn v-else-if="info?.needUpdate" :loading="starting" :disabled="!canUpdate" @click="requestUpdate">{{ t('headerVersion.update') }}</PrimaryBtn>
        </div>
      </div>
    </template>
  </el-dialog>

  <el-dialog v-model="confirmationVisible" :title="t('headerVersion.confirmTitle')" width="min(460px, calc(100vw - 32px))" append-to-body :close-on-click-modal="false">
    <div class="version-confirm">
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
.header-update-button {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  min-height: 34px;
  padding: 6px 11px;
  border: 1px solid color-mix(in srgb, var(--brand) 25%, var(--border));
  border-radius: var(--r-pill);
  background: var(--status-ok-bg);
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
.version-content { max-height: 65vh; max-height: 65dvh; overflow: auto; overscroll-behavior: contain; }
.version-byline { margin-bottom: 18px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.version-notice {
  display: flex;
  gap: 10px;
  padding: 13px;
  margin-bottom: 16px;
  border-radius: var(--r-sm);
  background: var(--status-info-bg);
  color: var(--text-primary);
  > i { margin-top: 3px; color: var(--status-info); }
  strong { font-weight: 600; }
  p { margin: 4px 0 0; font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
  &.is-failed { background: var(--status-danger-bg); > i { color: var(--status-danger); } }
  &.is-unknown { background: var(--status-warn-bg); > i { color: var(--status-warn); } }
  &.is-started { background: var(--status-ok-bg); > i { color: var(--status-ok); } }
}
.version-loading, .support-hint { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.version-facts {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px 20px;
  margin: 0;
  padding: 16px;
  border: 1px solid var(--border);
  border-radius: var(--r-sm);
  > div { min-width: 0; }
  > div:last-child { grid-column: 1 / -1; }
  dt { margin-bottom: 4px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
  dd { margin: 0; overflow-wrap: anywhere; font-weight: 600; }
}
.version-cache-row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-top: 12px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.version-status { padding: 2px 7px; border-radius: var(--r-pill); background: var(--bg-search); font-size: var(--font-size-caption); &.has-update { color: var(--status-ok); background: var(--status-ok-bg); } }
.version-links {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin: 20px 0;
  a { display: inline-flex; align-items: center; gap: 7px; padding: 8px 10px; border: 1px solid var(--border); border-radius: var(--r-sm); color: var(--text-primary); text-decoration: none; transition: background-color 160ms ease; }
  a:hover { background: var(--bg-hover); }
}
.version-support { border-top: 1px solid var(--border); padding-top: 14px; summary { cursor: pointer; font-weight: 600; } }
.version-support-body { padding-top: 8px; }
.support-hint { margin: 0 0 14px; }
.support-methods { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.support-method { min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 8px; strong { font-weight: 600; } }
.support-qr { width: min(144px, 100%); height: 144px; border: 1px solid var(--border); border-radius: var(--r-sm); }
.qr-error { display: grid; width: 100%; height: 100%; place-content: center; padding: 10px; color: var(--text-secondary); background: var(--bg-search); font-size: var(--font-size-secondary); text-align: center; }
.support-address {
  display: grid;
  gap: 7px;
  margin-top: 18px;
  label { color: var(--text-secondary); }
  input { box-sizing: border-box; width: 100%; min-width: 0; padding: 9px 11px; border: 1px solid var(--border); border-radius: var(--r-sm); color: var(--text-primary); background: var(--bg-search); font: var(--font-size-body)/1.5 var(--mono); }
  .version-text-button { justify-self: start; }
}
.version-text-button { display: inline-flex; align-items: center; gap: 6px; border: 0; padding: 5px 0; background: transparent; color: var(--brand); font: inherit; cursor: pointer; &:disabled { cursor: default; opacity: .6; } }
.copy-error { margin: 0; color: var(--status-danger); font-size: var(--font-size-secondary); }
.version-actions { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; }
.version-actions-end { display: flex; justify-content: flex-end; align-items: center; flex-wrap: wrap; gap: 8px; margin-inline-start: auto; }
.version-login-link { display: inline-flex; align-items: center; justify-content: center; min-height: 40px; box-sizing: border-box; padding: 9px 16px; border-radius: var(--r-pill); background: var(--brand); color: var(--nav-active-fg); text-decoration: none; font-weight: 600; &:hover { background: var(--brand-hover); } }
.version-confirm { p { margin: 0 0 14px; } .confirm-target { font-weight: 600; } .confirm-hint { margin-bottom: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); } }
.header-update-button:focus-visible, .version-links a:focus-visible, .version-support summary:focus-visible, .version-text-button:focus-visible, .support-address input:focus-visible, .version-login-link:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.support-qr :deep(img:focus-visible) { outline: 2px solid var(--brand); outline-offset: -3px; }
.version-spin { animation: version-spin 800ms linear infinite; }
.version-sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; border: 0; }
@keyframes version-spin { to { transform: rotate(360deg); } }
@media (max-width: 520px) { .version-actions > :deep(.btn) { flex: 1; } .version-actions-end { width: 100%; > :deep(.btn), > .version-login-link { flex: 1; white-space: normal; } } }
@media (prefers-reduced-motion: reduce) { .header-update-button, .version-links a { transition: none; } .version-spin { animation: none; } }
</style>
