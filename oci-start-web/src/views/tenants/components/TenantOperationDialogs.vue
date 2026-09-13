<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantGet, tenantPost } from '@/api/tenant'

type Tenant = Record<string, any>
interface CheckResult {
  totalAccounts: number
  activeAccounts: number
  inactiveAccounts: number
  inactiveAccountNames: string[]
}

const props = withDefaults(defineProps<{ tenant: Tenant | null; action: string; cloudType?: number }>(), { cloudType: 1 })
const emit = defineEmits<{ close: []; changed: [] }>()
const { t } = useI18n()
const supportedActions = ['proxy', 'traffic', 'import', 'export', 'batchCheck', 'transfer']
const title = computed(() => supportedActions.includes(props.action) ? t(`tenantOperations.titles.${props.action}`) : '')
const label = computed(() => supportedActions.includes(props.action) ? t(`tenantOperations.labels.${props.action}`) : '')
const visible = computed(() => supportedActions.includes(props.action))
const tenantName = computed(() => props.tenant?.defName || props.tenant?.tenancyName || props.tenant?.userName || '')
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const errorText = computed(() => localizeMessage(error.value))
const loadFailed = ref(false)
const proxyMode = ref('bind')
const proxyList = ref<Tenant[]>([])
const selectedProxyId = ref<string | number | null>(null)
const proxy = reactive({ customName: '', proxyType: 'HTTP', proxyHost: '', proxyPort: undefined as number | undefined, proxyUsername: '', proxyPassword: '', forceProxy: false })
const traffic = reactive({ statisticsEnabled: false, threshold: undefined as number | undefined, autoShutdown: false })
const transferAmount = ref<number | undefined>()
const fileInput = ref<HTMLInputElement>()
const importFile = ref<File | null>(null)
const importRecords = ref<Record<string, unknown>[] | null>(null)
const readingFile = ref(false)
const dragging = ref(false)
const verifyCode = ref('')
const codeSent = ref(false)
const sendingCode = ref(false)
const checkState = ref<'idle' | 'running' | 'complete' | 'error'>('idle')
const checkTotal = ref(0)
const checkProcessed = ref(0)
const checkMessage = ref('tenantOperations.check.idle')
const checkLogs = ref<string[]>([])
const logPanel = ref<HTMLElement>()
const checkResult = ref<CheckResult | null>(null)
const checkStatusText = computed(() => localizeMessage(checkMessage.value, { processed: checkProcessed.value, total: checkResult.value?.totalAccounts ?? checkTotal.value }))
const percentage = computed(() => checkState.value === 'complete' ? 100 : checkTotal.value ? Math.min(100, Math.floor(checkProcessed.value / checkTotal.value * 100)) : 0)
const unresolvedCount = computed(() => checkResult.value ? Math.max(0, checkResult.value.totalAccounts - checkResult.value.activeAccounts - checkResult.value.inactiveAccounts) : 0)
const submitDisabled = computed(() => loading.value || readingFile.value || sendingCode.value || loadFailed.value || (props.action === 'import' && !importRecords.value) || (props.action === 'export' && codeSent.value && !/^\d{6}$/.test(verifyCode.value)))
const submitLabel = computed(() => {
  if (props.action === 'proxy') return t(proxyMode.value === 'create' ? 'tenantOperations.actions.createAndBind' : 'tenantOperations.actions.saveBinding')
  if (props.action === 'import') return t('tenantOperations.actions.import')
  if (props.action === 'export') return t(codeSent.value ? 'tenantOperations.actions.verifyDownload' : 'tenantOperations.actions.sendCode')
  if (props.action === 'transfer') return t('tenantOperations.actions.confirmTransfer')
  return t('tenantOperations.actions.save')
})
let generation = 0
let fileGeneration = 0
let controller: AbortController | null = null
let eventSource: EventSource | null = null
let logFrame = 0
let queuedLogs: string[] = []

function localizeMessage(message: string, params: Record<string, string | number> = {}) {
  return message.startsWith('tenantOperations.') ? t(message, params) : message
}

function messageOf(reason: any, fallback = 'tenantOperations.errors.default') {
  const body = reason?.response?.data
  return typeof body === 'string' ? body : body?.message || body?.msg || reason?.message || reason?.msg || fallback
}

function stopStream() {
  eventSource?.close()
  eventSource = null
  if (logFrame) cancelAnimationFrame(logFrame)
  logFrame = 0
  if (queuedLogs.length) checkLogs.value.push(...queuedLogs.splice(0))
}

function cleanup() {
  generation++
  fileGeneration++
  controller?.abort()
  controller = null
  stopStream()
}

function close() {
  if (saving.value || sendingCode.value) return
  cleanup()
  emit('close')
}

function queueLog(message: string) {
  queuedLogs.push(message)
  if (logFrame) return
  logFrame = requestAnimationFrame(async () => {
    logFrame = 0
    const panel = logPanel.value
    const follow = !panel || panel.scrollHeight - panel.scrollTop - panel.clientHeight < 56
    checkLogs.value.push(...queuedLogs.splice(0))
    await nextTick()
    if (follow && logPanel.value) logPanel.value.scrollTop = logPanel.value.scrollHeight
  })
}

async function loadConfiguration() {
  if (!['proxy', 'traffic'].includes(props.action) || !props.tenant?.id) return
  const current = generation
  loading.value = true
  error.value = ''
  loadFailed.value = false
  const config = { silent: true, signal: controller?.signal }
  try {
    if (props.action === 'proxy') {
      const results = await Promise.allSettled([
        tenantPost('/vpnProxy/findByTenant', { tenantId: props.tenant.id }, config),
        tenantPost('/vpnProxy/pageList', { pageNum: 1, pageSize: 200 }, config),
      ])
      if (current !== generation) return
      const [boundResult, pageResult] = results
      if (boundResult.status === 'rejected') throw boundResult.reason
      if (pageResult.status === 'rejected') throw pageResult.reason
      const bound = boundResult.value?.data
      const page = pageResult.value?.data
      proxyList.value = page?.content || []
      // A bound proxy may be outside the first page; preserve it as a selectable option.
      if (bound?.id && !proxyList.value.some(item => String(item.id) === String(bound.id))) proxyList.value.unshift(bound)
      selectedProxyId.value = bound?.id ?? null
    } else {
      const result = await tenantGet(`/tenants/traffic-alert/${encodeURIComponent(props.tenant.id)}`, undefined, config)
      if (current !== generation) return
      traffic.statisticsEnabled = result?.statisticsEnabled === true
      traffic.threshold = result?.threshold ?? undefined
      traffic.autoShutdown = result?.autoShutdown === true
    }
  } catch (reason) {
    if (current !== generation) return
    loadFailed.value = true
    error.value = messageOf(reason, 'tenantOperations.errors.loadConfiguration')
  } finally {
    if (current === generation) loading.value = false
  }
}

watch(() => [props.action, props.tenant?.id], () => {
  cleanup()
  controller = new AbortController()
  loading.value = false
  saving.value = false
  error.value = ''
  loadFailed.value = false
  proxyMode.value = 'bind'
  proxyList.value = []
  selectedProxyId.value = null
  Object.assign(proxy, { customName: '', proxyType: 'HTTP', proxyHost: '', proxyPort: undefined, proxyUsername: '', proxyPassword: '', forceProxy: false })
  Object.assign(traffic, { statisticsEnabled: false, threshold: undefined, autoShutdown: false })
  transferAmount.value = undefined
  importFile.value = null
  importRecords.value = null
  readingFile.value = false
  dragging.value = false
  verifyCode.value = ''
  codeSent.value = false
  sendingCode.value = false
  checkState.value = 'idle'
  checkTotal.value = 0
  checkProcessed.value = 0
  checkMessage.value = 'tenantOperations.check.idle'
  checkLogs.value = []
  checkResult.value = null
  if (['proxy', 'traffic', 'transfer'].includes(props.action) && !props.tenant?.id) {
    loadFailed.value = true
    error.value = 'tenantOperations.errors.missingTenant'
    return
  }
  void loadConfiguration()
}, { immediate: true })

async function selectFile(file?: File) {
  if (!file || saving.value) return
  const current = ++fileGeneration
  readingFile.value = true
  error.value = ''
  importRecords.value = null
  importFile.value = file
  try {
    const data: unknown = JSON.parse(await file.text())
    if (current !== fileGeneration) return
    if (!Array.isArray(data) || !data.length || data.some(record => !record || typeof record !== 'object' || Array.isArray(record))) {
      throw new Error('tenantOperations.errors.invalidImport')
    }
    importRecords.value = data
  } catch (reason) {
    if (current === fileGeneration) error.value = reason instanceof SyntaxError ? 'tenantOperations.errors.invalidJson' : messageOf(reason, 'tenantOperations.errors.readFile')
  } finally {
    if (current === fileGeneration) readingFile.value = false
  }
}

function onFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  void selectFile(input.files?.[0])
  input.value = ''
}

function onDrop(event: DragEvent) {
  dragging.value = false
  void selectFile(event.dataTransfer?.files[0])
}

async function sendCode() {
  if (sendingCode.value || saving.value) return
  const current = generation
  sendingCode.value = true
  error.value = ''
  try {
    await tenantPost('/tenants/verify/sendExportCode', undefined, { silent: true, signal: controller?.signal })
    if (current !== generation) return
    codeSent.value = true
    verifyCode.value = ''
    ElMessage.success(t('tenantOperations.export.codeSent'))
  } catch (reason) {
    if (current === generation) error.value = messageOf(reason, 'tenantOperations.errors.sendCode')
  } finally {
    if (current === generation) sendingCode.value = false
  }
}

async function submit() {
  if (saving.value || submitDisabled.value) return
  error.value = ''
  if (props.action === 'export' && !codeSent.value) return sendCode()
  if (props.action === 'proxy' && proxyMode.value === 'create') {
    if (!proxy.proxyHost.trim()) { error.value = 'tenantOperations.errors.proxyHost'; return }
    if (!proxy.proxyPort || !Number.isInteger(proxy.proxyPort) || proxy.proxyPort < 1 || proxy.proxyPort > 65535) {
      error.value = 'tenantOperations.errors.proxyPort'; return
    }
  }
  if (props.action === 'traffic' && (!traffic.threshold || !Number.isFinite(traffic.threshold) || traffic.threshold <= 0)) {
    error.value = 'tenantOperations.errors.threshold'; return
  }
  const current = generation
  // Hold the submission guard through confirmation to prevent overlapping operations.
  saving.value = true
  try {
    if (props.action === 'transfer' || (props.action === 'traffic' && traffic.statisticsEnabled && traffic.autoShutdown)) {
      await ElMessageBox.confirm(
        props.action === 'transfer' ? t('tenantOperations.transfer.confirmMessage') : t('tenantOperations.traffic.confirmMessage', { threshold: traffic.threshold ?? 0 }),
        t(props.action === 'transfer' ? 'tenantOperations.actions.confirmTransfer' : 'tenantOperations.traffic.confirmTitle'),
        { confirmButtonText: t('tenantOperations.actions.confirm'), cancelButtonText: t('tenantOperations.actions.cancel'), type: 'warning' },
      )
      if (current !== generation) return
    }
    const config = { silent: true, signal: controller?.signal, timeout: 120000 }
    if (props.action === 'proxy') {
      if (proxyMode.value === 'bind') {
        await tenantPost('/vpnProxy/bindTenant', { tenantId: props.tenant!.id, id: selectedProxyId.value }, config)
      } else {
        await tenantPost('/vpnProxy/saveOrUpdate', {
          customName: proxy.customName.trim(), proxyType: proxy.proxyType, proxyHost: proxy.proxyHost.trim(), proxyPort: proxy.proxyPort,
          proxyUsername: proxy.proxyUsername.trim() || null, proxyPassword: proxy.proxyPassword.trim() || null,
          availableStatus: 1, forceProxy: proxy.forceProxy ? 1 : 0, tenantIds: [props.tenant!.id], tenantId: props.tenant!.id,
        }, config)
      }
    } else if (props.action === 'traffic') {
      await tenantPost('/tenants/traffic-alert', {
        tenantId: props.tenant!.id, statisticsEnabled: traffic.statisticsEnabled,
        threshold: traffic.threshold, autoShutdown: traffic.statisticsEnabled ? traffic.autoShutdown : false,
      }, config)
    } else if (props.action === 'transfer') {
      await tenantPost('/tenants/transfer', { tenantId: props.tenant!.id, transferAmount: String(Math.max(0, transferAmount.value || 0)) }, config)
    } else if (props.action === 'import') {
      await tenantPost('/tenants/import', importRecords.value, config)
    } else if (props.action === 'export') {
      const result = await tenantGet(props.tenant ? '/tenants/exportByTenant' : '/tenants/export', props.tenant ? { id: props.tenant.id } : undefined, {
        ...config, headers: { 'X-Verify-Code': verifyCode.value },
      })
      if (current !== generation) return
      if (!Array.isArray(result)) throw new Error('tenantOperations.errors.exportFormat')
      const url = URL.createObjectURL(new Blob([JSON.stringify(result, null, 2)], { type: 'application/json' }))
      const anchor = document.createElement('a')
      anchor.href = url
      anchor.download = props.tenant ? `tenant_${props.tenant.id}_data.json` : 'all_tenants_data.json'
      document.body.appendChild(anchor)
      anchor.click()
      anchor.remove()
      URL.revokeObjectURL(url)
    }
    if (current !== generation) return
    ElMessage.success(t(props.action === 'export' ? 'tenantOperations.export.success' : props.action === 'import' ? 'tenantOperations.import.success' : 'tenantOperations.saved'))
    if (props.action !== 'export') emit('changed')
    saving.value = false
    close()
  } catch (reason) {
    if (current === generation && reason !== 'cancel' && reason !== 'close') error.value = messageOf(reason)
  } finally {
    if (current === generation) saving.value = false
  }
}

function startCheck() {
  if (checkState.value === 'running') return
  stopStream()
  error.value = ''
  checkState.value = 'running'
  checkResult.value = null
  checkLogs.value = []
  checkTotal.value = 0
  checkProcessed.value = 0
  checkMessage.value = 'tenantOperations.check.connecting'
  const current = generation
  const source = new EventSource('/tenants/checkAccountsStream', { withCredentials: true })
  eventSource = source
  source.addEventListener('start', event => {
    if (current !== generation) return
    try {
      const data = JSON.parse((event as MessageEvent).data)
      checkTotal.value = Number(data.total) || 0
      checkMessage.value = data.message || 'tenantOperations.check.checking'
      queueLog(data.message ? String(data.message) : t('tenantOperations.check.checking'))
    } catch { queueLog(String((event as MessageEvent).data)) }
  })
  source.addEventListener('progress', event => {
    if (current !== generation) return
    checkProcessed.value++
    checkMessage.value = checkTotal.value ? 'tenantOperations.check.progressWithTotal' : 'tenantOperations.check.progress'
    queueLog(String((event as MessageEvent).data))
  })
  source.addEventListener('complete', event => {
    if (current !== generation) return
    stopStream()
    try {
      const result = JSON.parse((event as MessageEvent).data)
      if (![result.totalAccounts, result.activeAccounts, result.inactiveAccounts].every(value => typeof value === 'number')) throw new Error('tenantOperations.errors.checkFormat')
      checkResult.value = { ...result, inactiveAccountNames: Array.isArray(result.inactiveAccountNames) ? result.inactiveAccountNames : [] }
      checkState.value = 'complete'
      checkMessage.value = 'tenantOperations.check.complete'
      emit('changed')
    } catch (reason) {
      checkState.value = 'error'
      error.value = messageOf(reason, 'tenantOperations.errors.checkResult')
    }
  })
  source.addEventListener('error', event => {
    if (current !== generation || checkState.value !== 'running') return
    stopStream()
    checkState.value = 'error'
    error.value = String((event as MessageEvent).data || 'tenantOperations.errors.stream')
    checkMessage.value = 'tenantOperations.check.interrupted'
  })
}

onBeforeUnmount(cleanup)
</script>

<template>
  <el-dialog :model-value="visible" :title="label" width="620px" class="tenant-operation-dialog" align-center append-to-body destroy-on-close :close-on-click-modal="false" :close-on-press-escape="!saving && !sendingCode" :show-close="!saving && !sendingCode" @close="close">
    <template #header>
      <div class="operation-heading">
        <span class="operation-eyebrow">{{ label }}</span>
        <h2>{{ title }}</h2>
        <p v-if="tenantName">{{ tenantName }}</p>
      </div>
    </template>

    <div class="operation-body" :aria-busy="loading || saving">
      <el-alert v-if="error" :title="errorText" type="error" :closable="false" show-icon class="operation-error" role="alert" />
      <div v-if="loadFailed" class="retry-row"><el-button @click="loadConfiguration">{{ t('tenantOperations.actions.reload') }}</el-button></div>
      <el-skeleton v-if="loading" :rows="4" animated />

      <template v-else-if="action === 'proxy'">
        <div class="mode-switch" :aria-label="t('tenantOperations.proxy.mode')">
          <button type="button" :class="{ active: proxyMode === 'bind' }" :aria-pressed="proxyMode === 'bind'" :disabled="saving" @click="proxyMode = 'bind'">{{ t('tenantOperations.proxy.selectExisting') }}</button>
          <button type="button" :class="{ active: proxyMode === 'create' }" :aria-pressed="proxyMode === 'create'" :disabled="saving" @click="proxyMode = 'create'">{{ t('tenantOperations.actions.createAndBind') }}</button>
        </div>
        <Transition name="operation-swap" mode="out-in">
          <div v-if="proxyMode === 'bind'" key="bind" class="proxy-choices">
            <button type="button" class="proxy-choice" :class="{ selected: selectedProxyId === null }" :aria-pressed="selectedProxyId === null" :disabled="saving || loadFailed" @click="selectedProxyId = null">
              <span class="choice-indicator" /><span class="choice-copy"><strong>{{ t('tenantOperations.proxy.globalPool') }}</strong><small>{{ t('tenantOperations.proxy.globalPoolHint') }}</small></span>
            </button>
            <button v-for="item in proxyList" :key="item.id" type="button" class="proxy-choice" :class="{ selected: String(selectedProxyId) === String(item.id) }" :aria-pressed="String(selectedProxyId) === String(item.id)" :disabled="saving || loadFailed" @click="selectedProxyId = item.id">
              <span class="choice-indicator" />
              <span class="choice-copy">
                <strong>{{ item.customName || `${item.proxyType} ${item.proxyHost}:${item.proxyPort}` }}</strong>
                <small>{{ item.proxyType }} · {{ item.proxyHost }}:{{ item.proxyPort }} · {{ t([1, true, '1'].includes(item.forceProxy) ? 'tenantOperations.proxy.forced' : 'tenantOperations.proxy.optional') }}<template v-if="item.tenantName"> · {{ item.tenantName }}</template></small>
              </span>
              <span class="connection-status" :class="{ available: item.availableStatus === 1 }">{{ t(item.availableStatus === 1 ? 'tenantOperations.proxy.available' : 'tenantOperations.proxy.unavailable') }}</span>
            </button>
            <p v-if="!proxyList.length && !loadFailed" class="quiet-note">{{ t('tenantOperations.proxy.empty') }}</p>
          </div>
          <el-form v-else key="create" label-position="top" :disabled="saving || loadFailed" class="operation-form" @submit.prevent="submit">
            <el-form-item :label="t('tenantOperations.proxy.customName')"><el-input v-model="proxy.customName" maxlength="128" :placeholder="t('tenantOperations.proxy.namePlaceholder')" /></el-form-item>
            <div class="form-grid">
              <el-form-item :label="t('tenantOperations.proxy.type')"><el-select v-model="proxy.proxyType"><el-option :label="t('tenantOperations.proxy.http')" value="HTTP" /><el-option :label="t('tenantOperations.proxy.https')" value="HTTPS" /></el-select></el-form-item>
              <el-form-item :label="t('tenantOperations.proxy.policy')"><el-select v-model="proxy.forceProxy"><el-option :label="t('tenantOperations.proxy.optional')" :value="false" /><el-option :label="t('tenantOperations.proxy.forced')" :value="true" /></el-select></el-form-item>
              <el-form-item :label="t('tenantOperations.proxy.host')" required><el-input v-model="proxy.proxyHost" :placeholder="t('tenantOperations.proxy.hostPlaceholder')" /></el-form-item>
              <el-form-item :label="t('tenantOperations.proxy.port')" required><el-input-number v-model="proxy.proxyPort" :min="1" :max="65535" :precision="0" :controls="false" :placeholder="t('tenantOperations.proxy.portPlaceholder')" /></el-form-item>
              <el-form-item :label="t('tenantOperations.proxy.username')"><el-input v-model="proxy.proxyUsername" :placeholder="t('tenantOperations.proxy.optionalPlaceholder')" autocomplete="off" /></el-form-item>
              <el-form-item :label="t('tenantOperations.proxy.password')"><el-input v-model="proxy.proxyPassword" type="password" show-password :placeholder="t('tenantOperations.proxy.optionalPlaceholder')" autocomplete="new-password" /></el-form-item>
            </div>
            <p class="quiet-note">{{ t('tenantOperations.proxy.createHint') }}</p>
          </el-form>
        </Transition>
      </template>

      <el-form v-else-if="action === 'traffic'" label-position="top" :disabled="saving || loadFailed" class="operation-form" @submit.prevent="submit">
        <div class="setting-row"><div><strong>{{ t('tenantOperations.traffic.statistics') }}</strong><p>{{ t('tenantOperations.traffic.statisticsHint') }}</p></div><el-switch v-model="traffic.statisticsEnabled" :aria-label="t('tenantOperations.traffic.enableStatistics')" /></div>
        <el-form-item :label="t('tenantOperations.traffic.threshold')" required class="threshold-field"><el-input-number v-model="traffic.threshold" :min="0" :controls="false" :placeholder="t('tenantOperations.traffic.thresholdPlaceholder')" /><span class="field-hint">{{ t('tenantOperations.traffic.thresholdHint') }}</span></el-form-item>
        <div class="setting-row"><div><strong>{{ t('tenantOperations.traffic.autoShutdown') }}</strong><p>{{ t('tenantOperations.traffic.autoShutdownHint') }}</p></div><el-switch v-model="traffic.autoShutdown" :disabled="!traffic.statisticsEnabled" :aria-label="t('tenantOperations.traffic.autoShutdown')" /></div>
      </el-form>

      <div v-else-if="action === 'import'">
        <input ref="fileInput" class="file-input" type="file" accept="application/json,.json" :aria-label="t('tenantOperations.import.fileLabel')" @change="onFileChange" />
        <button type="button" class="file-drop" :class="{ dragging, ready: importRecords }" :disabled="saving || readingFile" @click="fileInput?.click()" @dragover.prevent="dragging = true" @dragleave.prevent="dragging = false" @drop.prevent="onDrop">
          <span class="file-symbol" :class="importRecords ? 'i-mdi-file-check-outline' : 'i-mdi-file-upload-outline'" aria-hidden="true" />
          <strong>{{ readingFile ? t('tenantOperations.import.reading') : importFile?.name || t('tenantOperations.import.selectFile') }}</strong>
          <span>{{ importRecords ? t('tenantOperations.import.ready', { count: importRecords.length }) : t('tenantOperations.import.fileHint') }}</span>
          <span class="file-action">{{ t(importFile ? 'tenantOperations.import.replaceFile' : 'tenantOperations.import.browse') }} <span aria-hidden="true">↗</span></span>
        </button>
        <p class="quiet-note">{{ t('tenantOperations.import.hint') }}</p>
      </div>

      <div v-else-if="action === 'export'" class="export-panel">
        <div class="export-scope"><span class="i-mdi-shield-check-outline" aria-hidden="true" /><div><strong>{{ t(tenant ? 'tenantOperations.export.singleScope' : 'tenantOperations.export.allScope') }}</strong><p>{{ t('tenantOperations.export.scopeHint') }}</p></div></div>
        <Transition name="operation-swap" mode="out-in">
          <div v-if="codeSent" key="code" class="verification-field">
            <label for="tenant-export-code">{{ t('tenantOperations.export.codeLabel') }}</label>
            <el-input id="tenant-export-code" v-model="verifyCode" inputmode="numeric" autocomplete="one-time-code" maxlength="6" :placeholder="t('tenantOperations.export.codePlaceholder')" :disabled="saving || sendingCode" @keyup.enter="submit" />
            <div class="verification-hint"><span>{{ t('tenantOperations.export.codeHint') }}</span><el-button link :loading="sendingCode" :disabled="saving" @click="sendCode">{{ t('tenantOperations.actions.resend') }}</el-button></div>
          </div>
          <p v-else key="intro" class="quiet-note">{{ t('tenantOperations.export.hint') }}</p>
        </Transition>
      </div>

      <div v-else-if="action === 'batchCheck'" class="check-panel">
        <template v-if="checkState === 'idle'">
          <div class="check-intro"><span class="i-mdi-pulse" aria-hidden="true" /><strong>{{ t('tenantOperations.check.introTitle') }}</strong><p>{{ t('tenantOperations.check.intro') }}</p></div>
        </template>
        <template v-else>
          <div class="check-progress"><span role="status">{{ checkStatusText }}</span><strong>{{ percentage }}<small>%</small></strong></div>
          <el-progress :percentage="percentage" :show-text="false" :stroke-width="6" :status="checkState === 'error' ? 'exception' : undefined" />
          <div v-if="checkResult" class="check-summary" aria-live="polite">
            <div><strong>{{ checkResult.totalAccounts }}</strong><span>{{ t('tenantOperations.check.total') }}</span></div><div class="healthy"><strong>{{ checkResult.activeAccounts }}</strong><span>{{ t('tenantOperations.check.active') }}</span></div><div :class="{ unhealthy: checkResult.inactiveAccounts > 0 }"><strong>{{ checkResult.inactiveAccounts }}</strong><span>{{ t('tenantOperations.check.inactive') }}</span></div>
          </div>
          <p v-if="unresolvedCount" class="quiet-note">{{ t('tenantOperations.check.unresolved', { count: unresolvedCount }) }}</p>
          <div v-if="checkResult?.inactiveAccountNames.length" class="inactive-accounts"><strong>{{ t('tenantOperations.check.inactive') }}</strong><span v-for="(name, index) in checkResult.inactiveAccountNames" :key="index">{{ name }}</span></div>
          <div ref="logPanel" class="check-log" tabindex="0" :aria-label="t('tenantOperations.check.logs')"><p v-for="(line, index) in checkLogs" :key="index">{{ line }}</p><p v-if="!checkLogs.length" class="waiting-line">{{ t('tenantOperations.check.waiting') }}</p></div>
          <p v-if="checkState === 'running'" class="quiet-note">{{ t('tenantOperations.check.closeHint') }}</p>
        </template>
      </div>

      <el-form v-else-if="action === 'transfer'" label-position="top" :disabled="saving" class="operation-form" @submit.prevent="submit">
        <p class="quiet-note">{{ t('tenantOperations.transfer.hint') }}</p>
        <el-form-item :label="t('tenantOperations.transfer.amount')"><el-input-number v-model="transferAmount" :min="0" :precision="2" :controls="false" :placeholder="t('tenantOperations.transfer.amountPlaceholder')" /></el-form-item>
      </el-form>
    </div>

    <template #footer>
      <div class="operation-footer">
        <el-button :disabled="saving || sendingCode" @click="close">{{ t(action === 'batchCheck' && checkState !== 'idle' ? 'tenantOperations.actions.close' : 'tenantOperations.actions.cancel') }}</el-button>
        <el-button v-if="action === 'batchCheck' && checkState === 'idle'" type="primary" @click="startCheck">{{ t('tenantOperations.actions.startCheck') }}</el-button>
        <el-button v-else-if="action !== 'batchCheck'" type="primary" :loading="saving || sendingCode" :disabled="submitDisabled" @click="submit">{{ submitLabel }}</el-button>
      </div>
    </template>
  </el-dialog>
</template>

<style scoped>
:global(.tenant-operation-dialog) { max-width: calc(100vw - 32px); padding: 26px; font-size: var(--font-size-body); }
:global(.tenant-operation-dialog .el-button), :global(.tenant-operation-dialog .el-input__inner), :global(.tenant-operation-dialog .el-select__wrapper), :global(.tenant-operation-dialog .el-form-item__label), :global(.tenant-operation-dialog .el-radio__label), :global(.tenant-operation-dialog .el-checkbox__label) { font-size: var(--font-size-body); }
:global(.tenant-operation-dialog .el-alert__title) { font-size: var(--font-size-body); }
:global(.tenant-operation-dialog .el-alert__description), :global(.tenant-operation-dialog .el-form-item__error) { font-size: var(--font-size-secondary); }
:global(.tenant-operation-dialog .el-dialog__body) { max-height: calc(100dvh - 250px); overflow-y: auto; overscroll-behavior: contain; }
.operation-heading { padding: 5px 24px 6px 0; }
.operation-eyebrow { color: var(--brand); font-size: var(--font-size-caption); font-weight: 600; letter-spacing: .04em; }
.operation-heading h2 { margin: 8px 0 0; font-size: var(--font-size-dialog-title); line-height: 1.3; font-weight: 600; letter-spacing: -.03em; }
.operation-heading p { margin: 9px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.operation-body { min-height: 150px; color: var(--text-primary); font-size: var(--font-size-body); }
.operation-error { margin-bottom: 16px; }
.retry-row { display: flex; justify-content: flex-end; margin-bottom: 14px; }
.quiet-note { margin: 16px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.7; }
.mode-switch { display: flex; padding: 4px; gap: 4px; margin-bottom: 18px; border-radius: 13px; background: var(--bg-search); }
.mode-switch button { flex: 1; min-width: 0; border: 0; border-radius: 10px; padding: 10px; background: transparent; color: var(--text-secondary); font: inherit; font-size: var(--font-size-body); overflow-wrap: anywhere; cursor: pointer; transition: background .2s, color .2s, transform .2s; }
.mode-switch button.active { background: var(--bg-card); color: var(--text-primary); box-shadow: var(--shadow-card); }
.mode-switch button:active { transform: scale(.98); }
.proxy-choices { max-height: 340px; overflow-y: auto; overscroll-behavior: contain; padding: 1px; }
.proxy-choice { width: 100%; display: flex; align-items: center; gap: 12px; padding: 16px; margin-bottom: 8px; border: 1px solid var(--border); border-radius: 14px; background: var(--bg-card); color: var(--text-primary); font: inherit; text-align: left; cursor: pointer; transition: background .2s, border-color .2s, transform .2s; }
.proxy-choice:hover { background: var(--bg-hover); }
.proxy-choice:active { transform: scale(.992); }
.proxy-choice.selected { border-color: var(--brand); background: var(--status-ok-bg); }
.choice-indicator { width: 18px; height: 18px; flex-shrink: 0; border: 1px solid var(--border-strong); border-radius: 50%; display: grid; place-items: center; }
.selected .choice-indicator { border-color: var(--brand); }
.selected .choice-indicator::after { content: ''; width: 8px; height: 8px; border-radius: 50%; background: var(--brand); }
.choice-copy { min-width: 0; flex: 1; display: flex; flex-direction: column; gap: 5px; }
.choice-copy strong { font-size: var(--font-size-body); font-weight: 600; overflow-wrap: anywhere; }
.choice-copy small { color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.55; overflow-wrap: anywhere; }
.connection-status { white-space: nowrap; color: var(--text-muted); font-size: var(--font-size-caption); }
.connection-status.available { color: var(--status-ok); }
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0 16px; }
.operation-form :deep(.el-form-item) { margin-bottom: 16px; }
.operation-form :deep(.el-form-item__label) { font-size: var(--font-size-body); color: var(--text-secondary); }
.operation-form :deep(.el-input-number), .operation-form :deep(.el-select) { width: 100%; }
.operation-form :deep(.el-input-number .el-input__inner) { text-align: left; }
.setting-row { display: flex; align-items: center; justify-content: space-between; gap: 24px; padding: 16px 0; }
.setting-row > div { min-width: 0; }
.setting-row strong { font-size: var(--font-size-body); font-weight: 600; }
.setting-row p { color: var(--text-secondary); font-size: var(--font-size-secondary); margin: 6px 0 0; line-height: 1.6; }
.setting-row :deep(.el-switch) { flex-shrink: 0; }
.threshold-field { margin-top: 10px; padding: 20px; border-radius: 14px; background: var(--bg-search); }
.field-hint { display: block; margin-top: 6px; font-size: var(--font-size-secondary); color: var(--text-muted); }
.file-input { display: none; }
.file-drop { width: 100%; min-height: 230px; display: flex; align-items: center; justify-content: center; flex-direction: column; gap: 10px; padding: 24px; border: 1px dashed var(--border-strong); border-radius: 18px; background: var(--bg-search); color: var(--text-primary); font: inherit; cursor: pointer; transition: transform .25s, background .25s, border-color .25s; }
.file-drop:hover, .file-drop.dragging { border-color: var(--brand); background: var(--status-ok-bg); }
.file-drop.dragging { transform: scale(1.01); }
.file-drop.ready { border-style: solid; border-color: var(--brand); }
.file-drop strong { font-size: var(--font-size-body); font-weight: 600; overflow-wrap: anywhere; max-width: 100%; }
.file-drop > span:not(.file-symbol) { font-size: var(--font-size-secondary); color: var(--text-secondary); }
.file-symbol { width: 40px; height: 40px; margin-bottom: 8px; color: var(--brand); }
.file-drop .file-action { color: var(--brand) !important; margin-top: 8px; }
.file-drop > span.file-action { font-size: var(--font-size-body); }
.export-scope { padding: 20px; display: flex; gap: 14px; background: var(--bg-search); border-radius: 16px; }
.export-scope > span { width: 28px; height: 28px; flex-shrink: 0; color: var(--brand); }
.export-scope > div { min-width: 0; overflow-wrap: anywhere; }
.export-scope strong { font-size: var(--font-size-body); font-weight: 600; }
.export-scope p { font-size: var(--font-size-secondary); color: var(--text-secondary); margin: 7px 0 0; line-height: 1.65; }
.verification-field { margin-top: 24px; }
.verification-field label { display: block; margin-bottom: 10px; font-size: var(--font-size-body); color: var(--text-secondary); }
.verification-field :deep(.el-input__inner) { height: 46px; font-size: var(--font-size-body); letter-spacing: .16em; font-variant-numeric: tabular-nums; }
.verification-field :deep(.el-input__inner::placeholder) { font-size: var(--font-size-body); letter-spacing: 0; }
.verification-hint { display: flex; justify-content: space-between; align-items: center; gap: 10px; margin-top: 10px; color: var(--text-muted); font-size: var(--font-size-secondary); }
.verification-hint > .el-button { flex-shrink: 0; }
.check-intro { text-align: center; padding: 20px 28px; }
.check-intro > span { display: block; width: 48px; height: 48px; margin: 0 auto 22px; color: var(--brand); }
.check-intro strong { font-size: var(--font-size-section); font-weight: 600; letter-spacing: -.02em; }
.check-intro p { color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.8; margin: 13px 0 0; }
.check-progress { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
.check-progress > span { min-width: 0; font-size: var(--font-size-secondary); color: var(--text-secondary); overflow-wrap: anywhere; }
.check-progress strong { flex-shrink: 0; font-size: 26px; font-weight: 600; font-variant-numeric: tabular-nums; }
.check-progress small { font-size: var(--font-size-secondary); margin-left: 2px; color: var(--text-secondary); }
.check-summary { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin-top: 20px; }
.check-summary > div { display: flex; flex-direction: column; gap: 6px; padding: 16px; border-radius: 14px; background: var(--bg-search); }
.check-summary strong { font-size: 27px; font-weight: 600; font-variant-numeric: tabular-nums; }
.check-summary span { font-size: var(--font-size-secondary); color: var(--text-secondary); overflow-wrap: anywhere; }
.check-summary .healthy strong { color: var(--status-ok); }
.check-summary .unhealthy strong { color: var(--status-danger); }
.inactive-accounts { margin-top: 16px; padding: 14px; background: var(--status-danger-bg); border-radius: 12px; color: var(--text-primary); display: flex; flex-wrap: wrap; gap: 8px 12px; font-size: var(--font-size-body); overflow-wrap: anywhere; }
.inactive-accounts strong { width: 100%; font-weight: 600; color: var(--status-danger); }
.check-log { max-height: 260px; min-height: 130px; overflow: auto; overscroll-behavior: contain; margin-top: 20px; padding: 16px; border: 1px solid var(--border); border-radius: 14px; background: var(--bg-search); font-family: var(--mono); font-size: var(--font-size-secondary); line-height: 1.9; }
.check-log p { margin: 0 0 4px; overflow-wrap: anywhere; white-space: pre-wrap; }
.waiting-line { color: var(--text-muted); }
.operation-footer { display: flex; flex-wrap: wrap; align-items: center; justify-content: flex-end; gap: 10px; padding-top: 6px; }
.operation-footer :deep(.el-button) { min-width: 92px; max-width: 100%; margin-left: 0; border-radius: var(--r-pill); min-height: 38px; height: auto; padding-block: 9px; white-space: normal; line-height: 1.3; }
.operation-body button:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.operation-body button:disabled { cursor: default; opacity: .6; }
.operation-swap-enter-active, .operation-swap-leave-active { transition: opacity .18s ease, transform .22s cubic-bezier(.22, 1, .36, 1); }
.operation-swap-enter-from { opacity: 0; transform: translateY(7px); }
.operation-swap-leave-to { opacity: 0; transform: translateY(-4px); }
@media (max-width: 600px) {
  .operation-heading h2 { font-size: var(--font-size-dialog-title); }
  .form-grid { grid-template-columns: 1fr; }
  .check-summary > div { padding: 12px; }
  .verification-hint { align-items: flex-start; flex-direction: column; }
  .check-intro { padding: 16px 0; }
}
@media (prefers-reduced-motion: reduce) {
  .operation-swap-enter-active, .operation-swap-leave-active, .proxy-choice, .mode-switch button, .file-drop { transition: none; }
  .operation-swap-enter-from, .operation-swap-leave-to, .proxy-choice:active, .mode-switch button:active, .file-drop.dragging { transform: none; }
  .check-panel :deep(.el-progress-bar__inner) { transition: none; }
}
</style>
