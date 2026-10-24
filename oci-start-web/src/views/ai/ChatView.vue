<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { checkSession } from '@/utils/session'
import { ElMessage, type InputInstance } from 'element-plus'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import ChatMessageContent from './ChatMessageContent.vue'
import {
  AiChatResponseError, aiChatServerError, disposeAiChatSocket, getAiChatModels, getAiChatTenant,
  isAiChatTenantId, openAiChatSocket, parseAiChatEvent, sendAiChatRequest,
  type AiChatEvent, type AiChatModel, type AiChatTenant,
} from '@/api/aiChat'

type Connection = 'loading' | 'connecting' | 'initializing' | 'ready' | 'disconnected' | 'closed' | 'error'
type Activity = 'idle' | 'replying' | 'clearing' | 'closing'
type MessageStatus = 'waiting' | 'streaming' | 'complete' | 'interrupted' | 'error'
interface Message { id: number; role: 'user' | 'assistant' | 'boundary'; content: string; createdAt: number; model: string; status: MessageStatus; errorKey?: string }

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const tenantId = computed(() => typeof route.query.tenantId === 'string' && isAiChatTenantId(route.query.tenantId) ? route.query.tenantId : '')
const tenant = ref<AiChatTenant | null>(null)
const metadataFailed = ref(false)
const models = ref<AiChatModel[]>([])
const modelId = ref('')
const modelsLoading = ref(false)
const modelErrorKey = ref('')
const modelErrorText = ref('')
const connection = ref<Connection>('loading')
const activity = ref<Activity>('idle')
const errorKey = ref('')
const errorText = ref('')
const messages = ref<Message[]>([])
const draft = ref('')
const useHistory = ref(true)
const followTail = ref(true)
const composer = ref<InputInstance>()
const transcript = ref<HTMLElement>()
const confirmation = ref<'clear' | 'close' | ''>('')
const selectedModel = computed(() => models.value.find((model) => model.id === modelId.value))
const contextLabel = computed(() => tenant.value?.name || t('aiChat.tenantId', { id: tenantId.value }))
const statusLabel = computed(() => t(`aiChat.state.${activity.value !== 'idle' ? activity.value : modelsLoading.value ? 'loading' : connection.value}`))
const errorMessage = computed(() => errorText.value || (errorKey.value ? t(`aiChat.${errorKey.value}`) : ''))
const modelError = computed(() => modelErrorText.value || (modelErrorKey.value ? t(`aiChat.${modelErrorKey.value}`) : ''))
const connecting = computed(() => ['loading', 'connecting', 'initializing'].includes(connection.value))
const controlsLocked = computed(() => activity.value !== 'idle' || connecting.value || modelsLoading.value)
const canSend = computed(() => connection.value === 'ready' && activity.value === 'idle' && !modelsLoading.value && !modelError.value && !!selectedModel.value && !!draft.value.trim())
const canPrepare = computed(() => !!tenantId.value && !controlsLocked.value)
const confirming = computed(() => activity.value === 'clearing' || activity.value === 'closing')
const preparing = computed(() => connecting.value || modelsLoading.value)
const starters = ['code', 'debug', 'write'] as const
let disposed = false
let contextVersion = 0
let modelVersion = 0
let socketVersion = 0
let nextMessageId = 1
let socket: WebSocket | undefined
let modelController: AbortController | undefined
let metadataController: AbortController | undefined
let handshakeTimer: ReturnType<typeof setTimeout> | undefined
let replyTimer: ReturnType<typeof setTimeout> | undefined
let actionTimer: ReturnType<typeof setTimeout> | undefined
let heartbeatTimer: ReturnType<typeof setInterval> | undefined
let flushTimer: ReturnType<typeof setTimeout> | undefined
let lastPacketAt = 0
let activeReplyId: number | null = null
let pendingChunks = ''

function modelLabel(model: AiChatModel) { return `${model.displayName || model.id} (${model.version || t('aiChat.latest')})` }
function timeLabel(value: number) { return new Date(value).toLocaleTimeString(locale.value === 'en' ? 'en-US' : 'zh-CN', { hour: '2-digit', minute: '2-digit' }) }
function goBack() {
  if (confirming.value) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous && previous !== route.fullPath) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: String(route.query.cloudType || '1') } })
}
function scrollToLatest(force = false) {
  if (force) followTail.value = true
  if (followTail.value) void nextTick(() => { if (!disposed && followTail.value && transcript.value) transcript.value.scrollTop = transcript.value.scrollHeight })
}
function trackScroll() {
  const area = transcript.value
  if (area) followTail.value = area.scrollHeight - area.scrollTop - area.clientHeight < 90
}
function activeReply() { return messages.value.find((message) => message.id === activeReplyId) }
function flushChunks() {
  clearTimeout(flushTimer)
  flushTimer = undefined
  const reply = activeReply()
  if (reply && pendingChunks) { reply.content += pendingChunks; reply.status = 'streaming'; scrollToLatest() }
  pendingChunks = ''
}
function stopSocket() {
  flushChunks()
  socketVersion++
  disposeAiChatSocket(socket)
  socket = undefined
  clearTimeout(handshakeTimer)
  clearTimeout(replyTimer)
  clearTimeout(actionTimer)
  clearInterval(heartbeatTimer)
  handshakeTimer = replyTimer = actionTimer = undefined
  heartbeatTimer = undefined
}
function disconnect(key: string, message = '', status: MessageStatus = 'interrupted') {
  stopSocket()
  const reply = activeReply()
  if (reply) { reply.status = status; reply.errorKey = key }
  activeReplyId = null
  activity.value = 'idle'
  confirmation.value = ''
  connection.value = 'disconnected'
  errorKey.value = key
  errorText.value = message
}
function armReplyTimeout() { clearTimeout(replyTimer); replyTimer = setTimeout(() => disconnect('replyTimeout'), 300000) }
function receive(event: AiChatEvent) {
  if (event.type === 'heartbeat' || event.type === 'pong') return
  if (event.type === 'init') {
    if (connection.value !== 'initializing') return
    clearTimeout(handshakeTimer)
    if (event.status !== 'success') { disconnect('initializationFailed', event.message, 'error'); return }
    connection.value = 'ready'
    errorKey.value = errorText.value = ''
    if (messages.value.length) messages.value.push({ id: nextMessageId++, role: 'boundary', content: '', createdAt: Date.now(), model: '', status: 'complete' })
    scrollToLatest()
    void nextTick(() => composer.value?.focus())
    return
  }
  if (event.type === 'error') {
    const key = activity.value === 'clearing' ? 'clearFailed' : activity.value === 'closing' ? 'closeFailed' : connection.value === 'initializing' ? 'initializationFailed' : 'replyFailed'
    disconnect(key, event.message, 'error')
    return
  }
  if (event.type === 'system' && activity.value === 'clearing') {
    if (event.status !== 'success') { disconnect('clearFailed', event.message); return }
    clearTimeout(actionTimer)
    messages.value = []
    activity.value = 'idle'
    confirmation.value = ''
    ElMessage.success(t('aiChat.cleared'))
    return
  }
  if (event.type === 'close_session' && activity.value === 'closing') {
    if (event.status !== 'success') { disconnect('closeFailed', event.message); return }
    stopSocket()
    activeReplyId = null
    messages.value = []
    draft.value = ''
    activity.value = 'idle'
    connection.value = 'closed'
    confirmation.value = ''
    return
  }
  if (activity.value !== 'replying') return
  if (event.type === 'typing') { armReplyTimeout(); return }
  if (event.type === 'chat' && event.role === 'assistant') {
    if (typeof event.message !== 'string') { disconnect('protocolError'); return }
    const reply = activeReply()
    if (!reply) return
    armReplyTimeout()
    if (event.isChunk) {
      pendingChunks += event.message
      if (!flushTimer) flushTimer = setTimeout(flushChunks, 90)
    } else { flushChunks(); reply.content = event.message; reply.status = 'streaming'; scrollToLatest() }
    return
  }
  if (event.type === 'chat_end') {
    flushChunks()
    clearTimeout(replyTimer)
    const reply = activeReply()
    if (event.status !== 'success') { disconnect('replyFailed', event.message, 'error'); return }
    if (reply) {
      // Only the server's chat_end finishes a reply. Socket EOF never does.
      reply.status = reply.content.trim() ? 'complete' : 'error'
      if (!reply.content.trim()) reply.errorKey = 'emptyReply'
    }
    activeReplyId = null
    activity.value = 'idle'
    scrollToLatest()
    void nextTick(() => composer.value?.focus())
  }
}

function connect() {
  if (disposed || !tenantId.value || !selectedModel.value || modelError.value || modelsLoading.value || activity.value !== 'idle' || ['connecting', 'initializing'].includes(connection.value)) return
  stopSocket()
  errorKey.value = errorText.value = ''
  connection.value = 'connecting'
  const version = socketVersion
  const currentTenant = tenantId.value
  const initialModel = selectedModel.value.id
  try {
    const currentSocket = openAiChatSocket()
    socket = currentSocket
    const active = () => !disposed && socketVersion === version && socket === currentSocket && tenantId.value === currentTenant
    handshakeTimer = setTimeout(() => { if (active()) disconnect('initializationTimeout') }, 30000)
    currentSocket.onopen = () => {
      if (!active()) return
      connection.value = 'initializing'
      lastPacketAt = Date.now()
      try { sendAiChatRequest(currentSocket, { type: 'init', tenant: { tenantId: currentTenant, modelId: initialModel } }) }
      catch { disconnect('connectionFailed'); return }
      heartbeatTimer = setInterval(() => {
        if (!active()) return
        if (Date.now() - lastPacketAt > 90000) { disconnect('disconnected'); return }
        try { sendAiChatRequest(currentSocket, { type: 'ping' }) } catch { disconnect('disconnected') }
      }, 30000)
    }
    currentSocket.onmessage = (event) => {
      if (!active()) return
      lastPacketAt = Date.now()
      try { receive(parseAiChatEvent(event.data)) } catch { disconnect('protocolError') }
    }
    currentSocket.onerror = () => {
      if (!active()) return
      void checkSession()
      disconnect(connection.value === 'connecting' ? 'connectionFailed' : 'disconnected')
    }
    currentSocket.onclose = () => {
      if (!active()) return
      void checkSession()
      disconnect(activity.value === 'closing' ? 'closeFailed' : activity.value === 'clearing' ? 'clearFailed' : 'disconnected')
    }
  } catch { disconnect('connectionFailed') }
}

async function refreshModels(autoConnect = false) {
  if (!tenantId.value || disposed || activity.value !== 'idle') return
  const version = ++modelVersion
  const context = contextVersion
  modelController?.abort()
  const controller = new AbortController()
  modelController = controller
  modelsLoading.value = true
  modelErrorKey.value = modelErrorText.value = ''
  try {
    const result = await getAiChatModels(tenantId.value, controller.signal)
    if (disposed || context !== contextVersion || version !== modelVersion) return
    models.value = result
    if (!result.some((model) => model.id === modelId.value)) modelId.value = result[0]?.id || ''
    if (!result.length) {
      modelErrorKey.value = 'noModels'
      if (socket) disconnect('noModels')
      else connection.value = 'error'
    }
  } catch (cause) {
    if (disposed || context !== contextVersion || version !== modelVersion || controller.signal.aborted) return
    modelErrorKey.value = cause instanceof AiChatResponseError ? 'invalidModels' : 'modelsFailed'
    modelErrorText.value = aiChatServerError(cause)
    if (!socket) connection.value = 'error'
  } finally {
    if (!disposed && context === contextVersion && version === modelVersion) {
      modelsLoading.value = false
      if (autoConnect && !modelError.value && selectedModel.value) connect()
    }
  }
}
async function readTenant(context: number) {
  metadataController?.abort()
  const controller = new AbortController()
  metadataController = controller
  try {
    const result = await getAiChatTenant(tenantId.value, controller.signal)
    if (disposed || context !== contextVersion) return
    tenant.value = result
    metadataFailed.value = !result
  } catch { if (!disposed && context === contextVersion && !controller.signal.aborted) metadataFailed.value = true }
}
function cancelPreparation() {
  if (!preparing.value || disposed) return
  ++modelVersion
  modelController?.abort()
  modelController = undefined
  modelsLoading.value = false
  if (connecting.value) {
    stopSocket()
    connection.value = 'disconnected'
  }
  void nextTick(() => composer.value?.focus())
}
function retryPreparation() {
  if (!canPrepare.value || disposed) return
  if (!selectedModel.value || modelError.value) void refreshModels(true)
  else connect()
}
function useStarter(key: typeof starters[number]) {
  if (!tenantId.value || confirming.value || draft.value.trim()) return
  draft.value = t(`aiChat.starters.${key}.prompt`)
  void nextTick(() => composer.value?.focus())
}
function menuAction(command: string) {
  if (command === 'refresh' && tenantId.value && !controlsLocked.value) void refreshModels(connection.value !== 'ready')
  else if (command === 'clear' || command === 'close') openConfirmation(command)
}
function resetContext() {
  const context = ++contextVersion
  modelVersion++
  modelController?.abort()
  metadataController?.abort()
  stopSocket()
  activeReplyId = null
  messages.value = []
  followTail.value = true
  draft.value = ''
  models.value = []
  modelId.value = ''
  tenant.value = null
  modelsLoading.value = metadataFailed.value = false
  modelErrorKey.value = modelErrorText.value = errorKey.value = errorText.value = ''
  confirmation.value = ''
  activity.value = 'idle'
  connection.value = tenantId.value ? 'loading' : 'error'
  if (!tenantId.value) { errorKey.value = 'invalidTenant'; return }
  void readTenant(context)
  void refreshModels(true)
}
function send() {
  if (!canSend.value || !socket || disposed || confirmation.value) return
  const content = draft.value.trim()
  const model = selectedModel.value!
  errorKey.value = errorText.value = ''
  activity.value = 'replying'
  const now = Date.now()
  messages.value.push({ id: nextMessageId++, role: 'user', content, createdAt: now, model: '', status: 'complete' })
  const reply: Message = { id: nextMessageId++, role: 'assistant', content: '', createdAt: now, model: model.displayName || model.id, status: 'waiting' }
  messages.value.push(reply)
  activeReplyId = reply.id
  try {
    sendAiChatRequest(socket, { type: 'chat', message: content, tenantId: tenantId.value, modelId: model.id, useHistory: useHistory.value })
    draft.value = ''
    armReplyTimeout()
  } catch { disconnect('sendFailed', '', 'error') }
  scrollToLatest(true)
}
function handleKeydown(event: Event | KeyboardEvent) {
  if (!(event instanceof KeyboardEvent)) return
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing && event.keyCode !== 229) { event.preventDefault(); send() }
}
function stopReceiving() { if (activity.value === 'replying') disconnect('stopped') }
function openConfirmation(action: 'clear' | 'close') {
  if (confirming.value || connecting.value || modelsLoading.value || (action === 'clear' && activity.value !== 'idle')) return
  confirmation.value = action
}
function closeConfirmation() { if (!confirming.value) confirmation.value = '' }
function confirmAction() {
  if (!confirmation.value || confirming.value || disposed) return
  const action = confirmation.value
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    messages.value = []
    if (action === 'close') { stopSocket(); draft.value = ''; connection.value = 'closed' }
    confirmation.value = ''
    errorKey.value = errorText.value = ''
    return
  }
  clearTimeout(replyTimer)
  activity.value = action === 'clear' ? 'clearing' : 'closing'
  try {
    sendAiChatRequest(socket, action === 'clear' ? { type: 'clear' } : { type: 'close_session', reason: 'user_requested' })
    actionTimer = setTimeout(() => disconnect(action === 'clear' ? 'clearFailed' : 'closeFailed'), 10000)
  } catch { disconnect(action === 'clear' ? 'clearFailed' : 'closeFailed') }
}
async function copyText(content: string) {
  try {
    if (navigator.clipboard?.writeText && window.isSecureContext) await navigator.clipboard.writeText(content)
    else {
      const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null
      const field = document.createElement('textarea')
      field.value = content
      field.readOnly = true
      field.style.position = 'fixed'
      field.style.opacity = '0'
      field.style.pointerEvents = 'none'
      document.body.appendChild(field)
      try { field.select(); if (!document.execCommand('copy')) throw new Error('copy_failed') }
      finally { field.remove(); previous?.focus({ preventScroll: true }) }
    }
    if (!disposed) ElMessage.success(t('aiChat.copied'))
  }
  catch { if (!disposed) ElMessage.error(t('aiChat.copyFailed')) }
}
function beforeUnload() { stopSocket() }
watch(tenantId, resetContext, { immediate: true })
window.addEventListener('beforeunload', beforeUnload)
onBeforeUnmount(() => {
  disposed = true
  contextVersion++
  modelVersion++
  modelController?.abort()
  metadataController?.abort()
  stopSocket()
  window.removeEventListener('beforeunload', beforeUnload)
})
</script>

<template>
  <div class="ai-chat-page">
    <section class="ai-chat-workspace" :aria-label="t('aiChat.label')">
      <header class="chat-toolbar">
        <PageBackButton :disabled="confirming" @click="goBack" />
        <div class="chat-context" :title="metadataFailed ? t('aiChat.metadataFailed') : contextLabel"><strong>{{ tenantId ? contextLabel : t('aiChat.tenant') }}</strong><span v-if="tenant?.region">{{ tenant.region }}</span><span v-else-if="tenantId">{{ t('aiChat.tenantId', { id: tenantId }) }}</span></div>
        <div class="chat-model-control">
          <label class="chat-sr-only" for="chat-model">{{ t('aiChat.model') }}</label>
          <el-select id="chat-model" v-model="modelId" filterable :loading="modelsLoading" :disabled="controlsLocked || !models.length" :placeholder="t(modelsLoading ? 'aiChat.loadingModels' : 'aiChat.selectModel')" :aria-label="t('aiChat.model')" popper-class="ai-chat-model-popper"><el-option v-for="model in models" :key="model.id" :value="model.id" :label="modelLabel(model)"><div class="chat-model-option"><span>{{ modelLabel(model) }}</span><small v-if="model.vendor">{{ model.vendor }}</small></div></el-option></el-select>
        </div>
        <div class="chat-toolbar-actions" data-page-error-anchor>
          <GhostBtn class="chat-new" :disabled="!messages.length || controlsLocked" :title="t('aiChat.newChat')" :aria-label="t('aiChat.newChat')" @click="openConfirmation('clear')"><i class="i-mdi-plus" aria-hidden="true" /><span>{{ t('aiChat.newChat') }}</span></GhostBtn>
          <el-dropdown trigger="click" placement="bottom-end" popper-class="ai-chat-menu" :show-timeout="0" @command="menuAction">
            <button class="chat-icon-button" type="button" :aria-label="t('aiChat.moreActions')" :title="t('aiChat.moreActions')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
            <template #dropdown><el-dropdown-menu>
              <el-dropdown-item command="refresh" :disabled="!tenantId || controlsLocked"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('aiChat.refreshModels') }}</el-dropdown-item>
              <el-dropdown-item command="clear" :disabled="!messages.length || controlsLocked"><i class="i-mdi-delete-outline" aria-hidden="true" />{{ t('aiChat.clear') }}</el-dropdown-item>
              <el-dropdown-item command="close" divided :disabled="connecting || confirming || modelsLoading || connection === 'closed'"><i class="i-mdi-close" aria-hidden="true" />{{ t('aiChat.close') }}</el-dropdown-item>
            </el-dropdown-menu></template>
          </el-dropdown>
        </div>
      </header>
      <PageErrorNotice v-if="modelError"><span>{{ modelError }}</span><GhostBtn :disabled="modelsLoading || activity !== 'idle'" @click="refreshModels(connection !== 'ready')">{{ t('aiChat.refreshModels') }}</GhostBtn></PageErrorNotice>
      <PageErrorNotice v-if="errorMessage && errorKey !== 'stopped'">{{ errorMessage }}</PageErrorNotice>
      <div class="chat-transcript-stage">
        <div ref="transcript" class="chat-transcript" tabindex="0" :aria-label="t('aiChat.transcript')" @scroll.passive="trackScroll">
          <div class="chat-reading-column" :class="{ 'is-empty': !messages.length }">
            <div v-if="!messages.length" class="chat-empty">
              <i class="i-mdi-creation-outline" aria-hidden="true" />
              <h2>{{ t(connection === 'closed' ? 'aiChat.state.closed' : 'aiChat.emptyTitle') }}</h2>
              <p>{{ t('aiChat.emptyHint') }}</p>
              <div v-if="tenantId && !draft.trim()" class="chat-starters" role="group" :aria-label="t('aiChat.suggestionsLabel')">
                <button v-for="starter in starters" :key="starter" type="button" :disabled="confirming" @click="useStarter(starter)">{{ t(`aiChat.starters.${starter}.label`) }}<i class="i-mdi-arrow-top-right" aria-hidden="true" /></button>
              </div>
            </div>
            <template v-for="message in messages" :key="message.id">
              <div v-if="message.role === 'boundary'" class="chat-session-boundary"><strong>{{ t('aiChat.sessionBoundary') }}</strong><span>{{ t('aiChat.previousHistory') }}</span></div>
              <article v-else class="chat-message" :class="`is-${message.role}`" :aria-label="t(`aiChat.${message.role}`)">
                <div class="chat-message-main">
                  <div v-if="message.role === 'assistant'" class="chat-message-heading"><span class="chat-avatar" aria-hidden="true"><i class="i-mdi-creation-outline" /></span><strong>{{ message.model || t('aiChat.assistant') }}</strong></div>
                  <p v-if="message.role === 'user'" class="chat-user-text">{{ message.content }}</p>
                  <ChatMessageContent v-else-if="message.content" :content="message.content" :streaming="message.status === 'streaming'" @copy="copyText" @rendered="scrollToLatest()" />
                  <p v-if="message.status === 'waiting' || message.status === 'streaming'" class="chat-reply-state" role="status"><span class="chat-thinking" aria-hidden="true"><span /><span /><span /></span>{{ t(message.status === 'waiting' ? 'aiChat.thinking' : 'aiChat.streaming') }}</p>
                  <p v-else-if="message.status === 'interrupted' || message.status === 'error'" class="chat-reply-state"><i class="i-mdi-alert-circle-outline" aria-hidden="true" />{{ t(`aiChat.${message.errorKey === 'emptyReply' ? 'emptyReply' : message.status === 'error' ? 'failed' : 'incomplete'}`) }}</p>
                  <div class="chat-message-actions">
                    <button v-if="message.content" class="chat-icon-button" type="button" :aria-label="t('aiChat.copyMessage')" :title="t('aiChat.copyMessage')" @click="copyText(message.content)"><i class="i-mdi-content-copy" aria-hidden="true" /></button>
                    <time :datetime="new Date(message.createdAt).toISOString()">{{ timeLabel(message.createdAt) }}</time>
                  </div>
                </div>
              </article>
            </template>
          </div>
        </div>
        <GhostBtn v-if="!followTail && messages.length" class="chat-latest" @click="scrollToLatest(true)"><i class="i-mdi-arrow-down" aria-hidden="true" />{{ t('aiChat.latestMessages') }}</GhostBtn>
      </div>
      <footer class="chat-composer">
        <div class="chat-composer-column">
          <div class="chat-connection-row">
            <div class="chat-connection" :class="{ 'is-ready': connection === 'ready', 'is-error': !!modelError || (!!errorMessage && errorKey !== 'stopped') }" role="status"><span v-if="preparing" class="chat-spinner" aria-hidden="true" /><span v-else class="connection-dot" aria-hidden="true" />{{ statusLabel }}</div>
            <button v-if="preparing" class="chat-text-button" type="button" @click="cancelPreparation">{{ t('aiChat.cancelPreparation') }}</button>
            <button v-else-if="connection !== 'ready' || modelError" class="chat-text-button" type="button" :disabled="!canPrepare" @click="retryPreparation"><i class="i-mdi-refresh" aria-hidden="true" />{{ t(modelError || !selectedModel ? 'aiChat.retryPreparation' : connection === 'closed' ? 'aiChat.startSession' : 'aiChat.connect') }}</button>
          </div>
          <form class="chat-compose-box" @submit.prevent="send">
            <el-input ref="composer" v-model="draft" type="textarea" :autosize="{ minRows: 2, maxRows: 7 }" :disabled="!tenantId || confirming" :placeholder="t('aiChat.inputPlaceholder')" :aria-label="t('aiChat.input')" @keydown="handleKeydown" />
            <div class="chat-compose-actions">
              <el-checkbox v-model="useHistory" :disabled="activity !== 'idle'" :title="t('aiChat.historyHint')">{{ t('aiChat.useHistory') }}</el-checkbox>
              <button v-if="activity === 'replying'" class="chat-send is-stop" type="button" :title="t('aiChat.stopHint')" :aria-label="t('aiChat.stop')" @click="stopReceiving"><i class="i-mdi-stop" aria-hidden="true" /></button>
              <PrimaryBtn v-else class="chat-send" type="submit" :disabled="!canSend" :title="t('aiChat.send')" :aria-label="t('aiChat.send')"><i class="i-mdi-arrow-up" aria-hidden="true" /></PrimaryBtn>
            </div>
          </form>
          <div class="chat-compose-hints"><span v-if="errorKey === 'stopped'" role="status">{{ errorMessage }}</span><span v-else>{{ t(preparing ? 'aiChat.preparationHint' : 'aiChat.historyHint') }}</span><span class="chat-keyboard-hint">{{ t('aiChat.keyboardHint') }}</span></div>
        </div>
      </footer>
    </section>
    <el-dialog :model-value="!!confirmation" :title="t(confirmation === 'clear' ? 'aiChat.clearTitle' : 'aiChat.closeTitle')" width="min(460px, calc(100vw - 32px))" align-center class="ai-chat-confirm" :close-on-click-modal="false" :close-on-press-escape="!confirming" :show-close="!confirming" @close="closeConfirmation"><p>{{ t(confirmation === 'clear' ? 'aiChat.clearDescription' : 'aiChat.closeDescription') }}</p><template #footer><GhostBtn :disabled="confirming" @click="closeConfirmation">{{ t('aiChat.cancel') }}</GhostBtn><PrimaryBtn :loading="confirming" @click="confirmAction">{{ t(confirmation === 'clear' ? 'aiChat.clear' : 'aiChat.close') }}</PrimaryBtn></template></el-dialog>
  </div>
</template>

<style src="./chat.scss" lang="scss"></style>
