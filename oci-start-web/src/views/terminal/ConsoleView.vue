<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageLoading from '@/components/PageLoading.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { consoleError, getConsoleMetadata, isConsoleInstanceId, restartConsoleInstance, type ConsoleMetadata, type ConsoleApiError } from '@/api/console'
import { useConsoleSession } from './useConsoleSession'
import VncCanvas from './components/VncCanvas.vue'
import type { VncCanvasHandle } from './components/vncTypes'
import './console-terminal.scss'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const pageRoot = ref<HTMLElement>()
const canvas = ref<VncCanvasHandle>()
const logBox = ref<HTMLElement>()
const metadata = ref<ConsoleMetadata | null>(null)
const metadataLoading = ref(false)
const metadataProblem = ref<ConsoleApiError | null>(null)
const runtimeLoading = ref(false)
const rendererProblem = ref('')
const securityReason = ref('')
const desktopName = ref('')
const fitScreen = ref(false)
const viewOnly = ref(false)
const fullscreen = ref(false)
const detailsOpen = ref(false)
const followOutput = ref(true)
const createOpen = ref(false)
const preparingClient = ref(false)
const credentialsOpen = ref(false)
const credentialTypes = ref<string[]>([])
const credentialPassword = ref('')
const credentialUsername = ref('')
const credentialTarget = ref('')
const textOpen = ref(false)
const textDraft = ref('')
const textPending = ref(false)
const textOutcome = ref<'idle' | 'sent' | 'interrupted'>('idle')
const restartOpen = ref(false)
const restartState = ref<'idle' | 'sending' | 'accepted' | 'uncertain' | 'failed'>('idle')
const restartProblem = ref<ConsoleApiError | null>(null)
const restartReviewed = ref(false)
const leaveOpen = ref(false)
let leaveResolver: ((allowed: boolean) => void) | undefined
let metadataController: AbortController | undefined
let metadataVersion = 0
let disposed = false
let credentialsKey = -1
let textVersion = 0
const session = useConsoleSession()
const { state, problem, vncUrl, command, connectionId, output, key: sessionKey, connected, connecting, outputTruncated, idleRemainingSeconds, idleWarning } = session
const instanceId = computed(() => typeof route.params.instanceId === 'string' ? route.params.instanceId : '')
const invalidScope = computed(() => !isConsoleInstanceId(instanceId.value))
const hasSession = computed(() => connecting.value || connected.value || state.value === 'manual')
const writing = computed(() => restartState.value === 'sending' || textPending.value)
const busy = computed(() => writing.value || preparingClient.value)
const idleTime = computed(() => `${Math.floor(idleRemainingSeconds.value / 60)}:${String(idleRemainingSeconds.value % 60).padStart(2, '0')}`)
const canCreate = computed(() => !!metadata.value && !invalidScope.value && !metadataLoading.value && !busy.value && !connecting.value)
const canRestart = computed(() => connected.value && !!metadata.value && !invalidScope.value && !metadataLoading.value && !busy.value)
const connectionLoading = computed(() => preparingClient.value || connecting.value)
const statusLabel = computed(() => t(`vnc.states.${preparingClient.value ? 'loadingClient' : state.value}`))
const instanceLabel = computed(() => metadata.value?.instanceName || metadata.value?.instanceIp || instanceId.value || '—')
const modalOpen = computed(() => createOpen.value || credentialsOpen.value || textOpen.value || restartOpen.value || leaveOpen.value)
const canvasActive = computed(() => !createOpen.value && !credentialsOpen.value && !restartOpen.value && !leaveOpen.value)

function feedback(type: 'success' | 'info' | 'warning', key: string) {
  if (!disposed) ElMessage({ type, message: t(`vnc.${key}`), appendTo: pageRoot.value || document.body })
}
function goBack() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous && previous !== route.fullPath) router.back()
  else void router.push('/oci/list')
}
async function loadMetadata() {
  if (invalidScope.value || metadataLoading.value || hasSession.value || busy.value) return
  metadataController?.abort()
  const controller = metadataController = new AbortController()
  const version = ++metadataVersion
  metadataLoading.value = true
  metadataProblem.value = null
  try {
    const result = await getConsoleMetadata(instanceId.value, controller.signal)
    if (!disposed && version === metadataVersion) metadata.value = result
  } catch (cause) {
    if (!disposed && version === metadataVersion && !controller.signal.aborted) {
      metadata.value = null
      metadataProblem.value = consoleError(cause)
    }
  } finally { if (!disposed && version === metadataVersion) metadataLoading.value = false }
}
function requestCreate() { if (canCreate.value) createOpen.value = true }
function createVisibility(value: boolean) { if (!value && !preparingClient.value) createOpen.value = false }
async function createConnection() {
  if (!canCreate.value || !metadata.value || preparingClient.value) return
  const context = { ...metadata.value }
  const version = metadataVersion
  preparingClient.value = true
  rendererProblem.value = securityReason.value = ''
  try {
    // Resolve the existing noVNC runtime before asking the backend to replace a
    // cloud console connection. A failed client load must not create resources.
    if (!await canvas.value?.prepare() || disposed || version !== metadataVersion) return
    stopSession()
    desktopName.value = ''
    viewOnly.value = false
    createOpen.value = false
    session.start(context)
  } finally { if (!disposed) preparingClient.value = false }
}
function stopSession() {
  ++textVersion
  if (textPending.value) textOutcome.value = 'interrupted'
  canvas.value?.cancelText()
  canvas.value?.disconnect()
  session.stop()
  credentialsOpen.value = false
  credentialPassword.value = credentialUsername.value = credentialTarget.value = ''
}
function disconnect() { if (!busy.value) stopSession() }
function clientConnected() { session.markVncConnected(sessionKey.value) }
function clientDisconnected(event: { clean: boolean; reason: string }) {
  if (hasSession.value) session.markVncDisconnected(event.reason, sessionKey.value)
  credentialsOpen.value = false
  credentialPassword.value = ''
}
function clientError(error: string) {
  if (error === 'textTooLarge' || error === 'inputFailed') { rendererProblem.value = error; return }
  rendererProblem.value = error
  if (hasSession.value) session.markVncDisconnected('', sessionKey.value)
}
function securityFailure(event: { status: number | null; reason: string }) {
  securityReason.value = event.reason
  rendererProblem.value = 'securityFailure'
  stopSession()
}
function requireCredentials(event: { types: string[] }) {
  if (!connecting.value) return
  const types = event.types.length ? event.types : ['password']
  if (types.some(type => !['password', 'username', 'target'].includes(type))) { clientError('unsupportedCredentials'); return }
  credentialTypes.value = types
  credentialPassword.value = credentialUsername.value = credentialTarget.value = ''
  credentialsKey = sessionKey.value
  session.credentialsPause(true, credentialsKey)
  credentialsOpen.value = true
}
function submitCredentials() {
  if (!credentialsOpen.value || credentialsKey !== sessionKey.value) return
  const values: { password?: string; username?: string; target?: string } = {}
  if (credentialTypes.value.includes('password')) values.password = credentialPassword.value
  if (credentialTypes.value.includes('username')) values.username = credentialUsername.value
  if (credentialTypes.value.includes('target')) values.target = credentialTarget.value
  if (!canvas.value?.sendCredentials(values)) return
  credentialsOpen.value = false
  credentialPassword.value = credentialUsername.value = credentialTarget.value = ''
  session.credentialsPause(false, credentialsKey)
}
function cancelCredentials() { credentialsOpen.value = false; stopSession() }
function credentialsVisibility(value: boolean) { if (!value && credentialsOpen.value) cancelCredentials() }
function toggleDetails() { detailsOpen.value = !detailsOpen.value; scrollOutput() }
function closeDetails() { detailsOpen.value = false; focusCanvas() }
function focusCanvas() { nextTick(() => canvas.value?.focus()) }
function scrollOutput() { if (detailsOpen.value && followOutput.value) nextTick(() => { if (logBox.value) logBox.value.scrollTop = logBox.value.scrollHeight }) }
async function copyCommand() {
  if (!command.value) return
  try { await navigator.clipboard.writeText(command.value); feedback('success', 'copied') }
  catch { feedback('warning', 'copyFailed') }
  if (!disposed) focusCanvas()
}
function ctrlAltDel() {
  if (!connected.value || viewOnly.value || modalOpen.value || textPending.value) return
  if (canvas.value?.sendCtrlAltDel()) session.touch()
  focusCanvas()
}
function openText() {
  if (!connected.value || viewOnly.value) return
  textOpen.value = true
}
async function sendText() {
  if (!connected.value || viewOnly.value || textPending.value || !textDraft.value || textOutcome.value !== 'idle') return
  const version = ++textVersion
  const key = sessionKey.value
  const sent = await canvas.value?.sendText(textDraft.value)
  if (disposed || version !== textVersion) return
  textOutcome.value = sent && key === sessionKey.value && connected.value ? 'sent' : 'interrupted'
  session.touch()
}
function cancelText() {
  ++textVersion
  canvas.value?.cancelText()
  textOutcome.value = 'interrupted'
}
function prepareText() {
  textDraft.value = ''
  textOutcome.value = 'idle'
  if (rendererProblem.value === 'textTooLarge' || rendererProblem.value === 'inputFailed') rendererProblem.value = ''
}
function closeText() { if (!textPending.value) { textOpen.value = false; focusCanvas() } }
function textVisibility(value: boolean) { if (!value) closeText() }
function requestRestart() { if (canRestart.value) restartOpen.value = true }
function restartVisibility(value: boolean) { if (!value && restartState.value !== 'sending') restartOpen.value = false }
async function restartInstance() {
  if (!metadata.value || !canRestart.value || !['idle', 'failed'].includes(restartState.value)) return
  restartState.value = 'sending'
  restartProblem.value = null
  restartReviewed.value = false
  try {
    await restartConsoleInstance({ ...metadata.value })
    if (!disposed) restartState.value = 'accepted'
  } catch (cause) {
    if (!disposed) {
      const error = consoleError(cause)
      restartProblem.value = error
      restartState.value = error.writeAttempted ? 'uncertain' : 'failed'
    }
  }
  session.touch()
}
function prepareRestart() {
  if (!restartReviewed.value || !canRestart.value) return
  restartState.value = 'idle'
  restartProblem.value = null
  restartReviewed.value = false
}
async function toggleFullscreen() {
  try {
    if (document.fullscreenElement === pageRoot.value) await document.exitFullscreen()
    else await pageRoot.value?.requestFullscreen()
  } catch { feedback('info', 'fullscreenFailed') }
}
function fullscreenChanged() { fullscreen.value = document.fullscreenElement === pageRoot.value; nextTick(() => canvas.value?.fit()) }
function finishLeave(allowed: boolean) {
  if (allowed) stopSession()
  leaveOpen.value = false
  leaveResolver?.(allowed)
  leaveResolver = undefined
}
function stay() { finishLeave(false) }
function leave() { finishLeave(true) }
function leaveVisibility(value: boolean) { if (!value) stay() }
function canLeave(): boolean | Promise<boolean> {
  if (busy.value) { feedback('info', 'finishOperation'); return false }
  if (!hasSession.value) return true
  if (leaveResolver) return false
  leaveOpen.value = true
  return new Promise(resolve => { leaveResolver = resolve })
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (hasSession.value || busy.value) { event.preventDefault(); event.returnValue = '' }
}
onBeforeRouteLeave(canLeave)
onBeforeRouteUpdate((to, from) => to.path === from.path && to.params.instanceId === from.params.instanceId ? true : canLeave())
// Close the binary channel in the same turn as a control error or timeout.
watch(sessionKey, () => canvas.value?.disconnect(), { flush: 'sync' })
watch(output, scrollOutput)
watch(followOutput, scrollOutput)
watch(connected, value => { if (value) focusCanvas() })
watch(hasSession, value => { if (!value) { credentialsOpen.value = false; credentialPassword.value = ''; if (textPending.value) cancelText() } })
watch([() => route.path, () => route.params.instanceId], () => {
  ++metadataVersion
  metadataController?.abort()
  metadataLoading.value = false
  stopSession()
  session.reset()
  metadata.value = null
  metadataProblem.value = restartProblem.value = null
  rendererProblem.value = securityReason.value = desktopName.value = ''
  detailsOpen.value = textOpen.value = restartOpen.value = createOpen.value = false
  restartState.value = textOutcome.value = 'idle'
  textDraft.value = ''
  void loadMetadata()
}, { immediate: true })
onMounted(() => { document.addEventListener('fullscreenchange', fullscreenChanged); window.addEventListener('beforeunload', beforeUnload) })
onBeforeUnmount(() => {
  disposed = true
  ++metadataVersion
  ++textVersion
  metadataController?.abort()
  canvas.value?.cancelText()
  leaveResolver?.(false)
  credentialPassword.value = textDraft.value = ''
  document.removeEventListener('fullscreenchange', fullscreenChanged)
  window.removeEventListener('beforeunload', beforeUnload)
})
</script>

<template>
  <section ref="pageRoot" class="vnc-page" :aria-label="t('vnc.title')" @pointerdown.capture="session.touch" @pointermove.capture="session.touch" @keydown.capture="session.touch" @wheel.passive="session.touch">
    <header class="vnc-toolbar">
      <PageBackButton @click="goBack" />
      <div class="vnc-instance"><strong :title="instanceLabel">{{ instanceLabel }}</strong><span v-if="metadata?.instanceIp" :title="metadata.instanceIp">{{ metadata.instanceIp }}</span></div>
      <span class="vnc-state" :class="`is-${state}`" role="status"><span />{{ statusLabel }}</span>
      <div class="vnc-actions" data-page-error-anchor><GhostBtn :disabled="!canRestart" danger @click="requestRestart">{{ t('vnc.restart') }}</GhostBtn><GhostBtn v-if="hasSession" :disabled="busy" :title="t('vnc.disconnectHint')" @click="disconnect">{{ t(connecting ? 'vnc.cancelConnection' : 'vnc.disconnect') }}</GhostBtn><PrimaryBtn :disabled="!canCreate" :loading="preparingClient" @click="requestCreate">{{ t(hasSession ? 'vnc.recreate' : 'vnc.create') }}</PrimaryBtn></div>
    </header>
    <div v-if="invalidScope" class="vnc-notice" role="alert">{{ t('vnc.invalidScope') }}</div>
    <div v-else-if="metadataLoading" class="vnc-notice" role="status">{{ t('vnc.loadingMetadata') }}</div>
    <PageErrorNotice v-if="metadataProblem"><span>{{ t(`vnc.errors.${metadataProblem.key}`) }} {{ metadataProblem.detail }}</span><GhostBtn :disabled="metadataLoading || hasSession || busy" @click="loadMetadata">{{ t('vnc.reloadMetadata') }}</GhostBtn></PageErrorNotice>
    <PageErrorNotice v-if="problem">{{ t(`vnc.errors.${problem.key}`) }} <span>{{ problem.detail }}</span></PageErrorNotice>
    <div v-if="rendererProblem === 'textTooLarge'" class="vnc-notice" role="alert">{{ t(`vnc.rendererErrors.${rendererProblem}`) }}</div>
    <PageErrorNotice v-else-if="rendererProblem">{{ t(`vnc.rendererErrors.${rendererProblem}`) }} <span>{{ securityReason }}</span></PageErrorNotice>
    <div v-if="idleWarning" class="vnc-notice" role="status">{{ t('vnc.idleWarning') }}</div>
    <div class="vnc-tools">
      <div class="vnc-tools-group"><div class="vnc-scale" role="group" :aria-label="t('vnc.scale')"><button type="button" :aria-pressed="fitScreen" :class="{ selected: fitScreen }" @click="fitScreen = true">{{ t('vnc.fit') }}</button><button type="button" :aria-pressed="!fitScreen" :class="{ selected: !fitScreen }" @click="fitScreen = false">{{ t('vnc.originalSize') }}</button></div><label class="vnc-check"><input v-model="viewOnly" type="checkbox" :disabled="textPending" /><span>{{ t('vnc.viewOnly') }}</span></label></div>
      <div class="vnc-tools-group"><button type="button" class="vnc-tool" :disabled="!connected || viewOnly || textPending" @click="ctrlAltDel">Ctrl + Alt + Del</button><button type="button" class="vnc-tool" :disabled="!connected || viewOnly" @click="openText"><i class="i-mdi-keyboard-outline" aria-hidden="true" />{{ t('vnc.sendText') }}</button><button type="button" class="vnc-tool" :aria-expanded="detailsOpen" @click="toggleDetails"><i class="i-mdi-text-box-outline" aria-hidden="true" />{{ t('vnc.details') }}</button><button type="button" class="vnc-icon" :title="t(fullscreen ? 'vnc.exitFullscreen' : 'vnc.fullscreen')" :aria-label="t(fullscreen ? 'vnc.exitFullscreen' : 'vnc.fullscreen')" @click="toggleFullscreen"><i :class="fullscreen ? 'i-mdi-fullscreen-exit' : 'i-mdi-fullscreen'" aria-hidden="true" /></button></div>
    </div>
    <div class="vnc-stage">
      <div class="vnc-screen" :aria-busy="connectionLoading">
        <VncCanvas :key="sessionKey" ref="canvas" :url="vncUrl" :active="canvasActive" :view-only="viewOnly" :scale="fitScreen" :aria-label="t('vnc.remoteScreen')" @loading="runtimeLoading = $event" @connect="clientConnected" @disconnect="clientDisconnected" @credentialsrequired="requireCredentials" @securityfailure="securityFailure" @error="clientError" @activity="session.touch" @desktopname="desktopName = $event.name" @textpending="textPending = $event" />
        <PageLoading :visible="connectionLoading" :label="statusLabel" />
        <div v-if="!connected && !connectionLoading" class="vnc-placeholder" role="status"><i class="i-mdi-monitor" aria-hidden="true" /><p>{{ t(state === 'manual' ? 'vnc.manualHint' : 'vnc.emptyHint') }}</p></div>
      </div>
      <aside v-show="detailsOpen" class="vnc-details" :aria-label="t('vnc.details')"><header><strong>{{ t('vnc.details') }}</strong><button type="button" class="vnc-icon" :title="t('vnc.closeDetails')" :aria-label="t('vnc.closeDetails')" @click="closeDetails"><i class="i-mdi-close" aria-hidden="true" /></button></header><div v-if="connectionId" class="vnc-connection-id"><span>{{ t('vnc.connectionId') }}</span><span>{{ connectionId }}</span></div><div v-if="command" class="vnc-command"><span>{{ t('vnc.commandHint') }}</span><code>{{ command }}</code><GhostBtn @click="copyCommand">{{ t('vnc.copyCommand') }}</GhostBtn></div><div class="vnc-log-heading"><span>{{ t('vnc.connectionLog') }}</span><label class="vnc-check"><input v-model="followOutput" type="checkbox" /><span>{{ t('vnc.followOutput') }}</span></label></div><p v-if="outputTruncated" class="vnc-log-hint">{{ t('vnc.outputTruncated') }}</p><pre ref="logBox" class="vnc-log" tabindex="0">{{ output || t('vnc.noLogs') }}</pre></aside>
    </div>
    <footer class="vnc-footer"><span :title="desktopName || t('vnc.inputHint')">{{ desktopName || t('vnc.inputHint') }}</span><span v-if="connected" :class="{ 'is-warning': idleWarning }">{{ t('vnc.idleCountdown', { time: idleTime }) }}</span><span v-else>{{ t('vnc.disconnectHint') }}</span></footer>

    <el-dialog :model-value="createOpen" :title="t(hasSession ? 'vnc.recreate' : 'vnc.create')" width="460px" :close-on-click-modal="false" :close-on-press-escape="!preparingClient" :show-close="!preparingClient" class="vnc-dialog" @update:model-value="createVisibility"><p>{{ t('vnc.createConfirm', { name: instanceLabel }) }}</p><p>{{ t('vnc.createHint') }}</p><PageErrorNotice v-if="createOpen && rendererProblem">{{ t(`vnc.rendererErrors.${rendererProblem}`) }}</PageErrorNotice><p v-if="runtimeLoading || preparingClient" role="status">{{ t('vnc.preparingClient') }}</p><template #footer><GhostBtn :disabled="preparingClient" @click="createVisibility(false)">{{ t('vnc.cancel') }}</GhostBtn><PrimaryBtn :disabled="!canCreate" :loading="preparingClient" @click="createConnection">{{ t('vnc.confirmCreate') }}</PrimaryBtn></template></el-dialog>
    <el-dialog :model-value="credentialsOpen" :title="t('vnc.credentialsTitle')" width="420px" :close-on-click-modal="false" class="vnc-dialog" @update:model-value="credentialsVisibility"><form id="vnc-credentials" class="vnc-form" @submit.prevent="submitCredentials"><label v-if="credentialTypes.includes('username')"><span>{{ t('vnc.username') }}</span><input v-model="credentialUsername" autocomplete="off" /></label><label v-if="credentialTypes.includes('target')"><span>{{ t('vnc.target') }}</span><input v-model="credentialTarget" autocomplete="off" /></label><label v-if="credentialTypes.includes('password')"><span>{{ t('vnc.password') }}</span><input v-model="credentialPassword" type="password" autocomplete="new-password" /></label><p>{{ t('vnc.credentialsHint') }}</p></form><template #footer><GhostBtn @click="cancelCredentials">{{ t('vnc.cancelConnection') }}</GhostBtn><button type="submit" form="vnc-credentials" class="vnc-primary">{{ t('vnc.authenticate') }}</button></template></el-dialog>
    <el-dialog :model-value="textOpen" :title="t('vnc.sendText')" width="520px" :close-on-click-modal="false" :close-on-press-escape="!textPending" :show-close="!textPending" class="vnc-dialog" @update:model-value="textVisibility"><div class="vnc-form"><label><span>{{ t('vnc.textLabel') }}</span><textarea v-model="textDraft" rows="7" maxlength="65536" :disabled="textPending || textOutcome !== 'idle'" :placeholder="t('vnc.textPlaceholder')" :spellcheck="false" /></label><p>{{ t('vnc.textHint') }}</p><p v-if="textOutcome !== 'idle'" role="status">{{ t(`vnc.textOutcomes.${textOutcome}`) }}</p><p v-if="rendererProblem === 'textTooLarge'" role="alert">{{ t(`vnc.rendererErrors.${rendererProblem}`) }}</p><PageErrorNotice v-else-if="textOpen && rendererProblem === 'inputFailed'">{{ t(`vnc.rendererErrors.${rendererProblem}`) }}</PageErrorNotice></div><template #footer><GhostBtn v-if="textPending" @click="cancelText">{{ t('vnc.cancelSending') }}</GhostBtn><GhostBtn v-else @click="closeText">{{ t('vnc.close') }}</GhostBtn><GhostBtn v-if="textOutcome !== 'idle' && !textPending" @click="prepareText">{{ t('vnc.newText') }}</GhostBtn><PrimaryBtn v-else :disabled="!connected || viewOnly || !textDraft || textPending" :loading="textPending" @click="sendText">{{ t('vnc.send') }}</PrimaryBtn></template></el-dialog>
    <el-dialog :model-value="restartOpen" :title="t('vnc.restart')" width="470px" :close-on-click-modal="false" :close-on-press-escape="restartState !== 'sending'" :show-close="restartState !== 'sending'" class="vnc-dialog" @update:model-value="restartVisibility"><p v-if="restartState === 'idle' || restartState === 'failed'">{{ t('vnc.restartConfirm', { name: instanceLabel }) }}</p><p v-else role="status">{{ t(`vnc.restartStates.${restartState}`) }}</p><PageErrorNotice v-if="restartOpen && restartProblem">{{ t(`vnc.errors.${restartProblem.key}`) }} {{ restartProblem.detail }}</PageErrorNotice><label v-if="restartState === 'accepted' || restartState === 'uncertain'" class="vnc-check"><input v-model="restartReviewed" type="checkbox" /><span>{{ t('vnc.restartReviewed') }}</span></label><template #footer><GhostBtn :disabled="restartState === 'sending'" @click="restartVisibility(false)">{{ t('vnc.close') }}</GhostBtn><GhostBtn v-if="restartState === 'accepted' || restartState === 'uncertain'" :disabled="!restartReviewed || !canRestart" @click="prepareRestart">{{ t('vnc.restartAgain') }}</GhostBtn><PrimaryBtn v-else :disabled="restartState === 'sending' || !canRestart" :loading="restartState === 'sending'" @click="restartInstance">{{ t('vnc.confirmRestart') }}</PrimaryBtn></template></el-dialog>
    <el-dialog :model-value="leaveOpen" :title="t('vnc.leaveTitle')" width="420px" :close-on-click-modal="false" :show-close="false" class="vnc-dialog" @update:model-value="leaveVisibility"><p>{{ t('vnc.leaveHint') }}</p><template #footer><GhostBtn @click="stay">{{ t('vnc.stay') }}</GhostBtn><PrimaryBtn @click="leave">{{ t('vnc.leave') }}</PrimaryBtn></template></el-dialog>
  </section>
</template>
