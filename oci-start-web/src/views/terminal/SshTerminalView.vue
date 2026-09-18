<script setup lang="ts">
import { computed, defineAsyncComponent, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { getSshConfig, isSshSaveUncertain, normalizeSshCredentials, saveSshConfig, sshError, type SshCredentials } from '@/api/ssh'
import { useSshSession } from './useSshSession'
import SshTerminalCanvas from './components/SshTerminalCanvas.vue'
import type { SshTerminalCanvasHandle, SshTerminalDimensions, SshTerminalError, SshTerminalSearch, SshTerminalShortcut, SshTerminalTheme } from './components/sshTerminalTypes'
import './ssh-terminal.scss'

const SftpPanel = defineAsyncComponent(() => import('./components/SftpPanel.vue'))
const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const pageRoot = ref<HTMLElement>()
const terminal = ref<SshTerminalCanvasHandle>()
const searchInput = ref<HTMLInputElement>()
const menuRoot = ref<HTMLElement>()
const settingsForm = ref<HTMLFormElement>()
const transfer = ref<{ focusUpload(): void; focusDownload(): void }>()
const draft = reactive<SshCredentials>({ host: '', username: '', port: 22, password: '' })
const settingsOpen = ref(false)
const settingsBlocking = ref(false)
const passwordVisible = ref(false)
const configLoading = ref(false)
const configProblem = ref('')
const saving = ref(false)
const saveProblem = ref('')
const saveState = ref<'idle' | 'saved' | 'uncertain'>('idle')
const validation = ref('')
const ready = ref(false)
const rendererKey = ref(0)
const rendererProblem = ref<SshTerminalError | ''>('')
const hasOutput = ref(false)
const dimensions = ref({ cols: 0, rows: 0 })
const themes: SshTerminalTheme[] = ['system', 'matrix', 'tokyonight', 'dracula', 'nord', 'monokai', 'solarizedLight', 'highContrast']
function preference(key: string) { try { return localStorage.getItem(key) } catch { return null } }
const storedSize = Number(preference('terminal.fontSize'))
const fontSize = ref(Number.isInteger(storedSize) && storedSize >= 10 && storedSize <= 24 ? storedSize : 14)
const storedTheme = preference('terminal.theme') as SshTerminalTheme
const terminalTheme = ref<SshTerminalTheme>(themes.includes(storedTheme) ? storedTheme : 'system')
const searchOpen = ref(false)
const searchQuery = ref('')
const searchResult = ref<SshTerminalSearch>({ index: 0, total: 0 })
const filesOpen = ref(false)
const filesMounted = ref(false)
const pendingTransfer = ref<'upload' | 'download' | null>(null)
const transferBusy = ref(false)
const fullscreen = ref(false)
const menu = ref<{ x: number; y: number } | null>(null)
const leaveOpen = ref(false)
let resolveLeave: ((value: boolean) => void) | undefined
let configController: AbortController | undefined
let configVersion = 0
let disposed = false
const downloadUrls = new Map<string, ReturnType<typeof setTimeout>>()
const session = useSshSession({ onOutput(text) {
  if (!terminal.value?.write(text)) {
    rendererProblem.value ||= 'renderFailed'
    session.disconnect()
    return
  }
  if (!hasOutput.value) hasOutput.value = true
} })
const { state, connected, connecting, profile, connectionKey, problem } = session
const instanceId = computed(() => typeof route.query.instanceId === 'string' ? route.query.instanceId : '')
const invalidScope = computed(() => {
  if (route.query.instanceId === undefined) return route.path.startsWith('/oci/')
  const id = instanceId.value
  return !/^[1-9]\d{0,18}$/.test(id) || (id.length === 19 && id > '9223372036854775807')
})
const draftLocked = computed(() => configLoading.value || saving.value || connecting.value || connected.value || transferBusy.value)
const connectDisabled = computed(() => !ready.value || !!rendererProblem.value || invalidScope.value || configLoading.value || saving.value || transferBusy.value || connecting.value)
const credentialsReady = computed(() => {
  try { normalizeSshCredentials(draft); return true } catch { return false }
})
const target = computed(() => {
  if (configLoading.value) return t('sshTerminal.loadingConfig')
  const value = (connected.value || connecting.value) && profile.value ? profile.value : draft
  const host = value.host.trim()
  if (!host) return t('sshTerminal.noTarget')
  const address = host.includes(':') && !host.startsWith('[') ? `[${host}]` : host
  return `${value.username.trim() ? `${value.username.trim()}@` : ''}${address}:${value.port}`
})
const settingsProblem = computed(() => validation.value || saveProblem.value || configProblem.value)
const stateLabel = computed(() => t(`sshTerminal.states.${state.value}`))
const menuItems = ['copy', 'paste', 'selectAll', 'clear', 'copyCommand', 'downloadLog', 'upload', 'download'] as const
type MenuAction = typeof menuItems[number]
function feedback(type: 'success' | 'info' | 'warning', key: string) {
  ElMessage({ type, message: t(`sshTerminal.${key}`), appendTo: pageRoot.value || document.body })
}

function goBack() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous && previous !== route.fullPath) router.back()
  else void router.push(route.path.startsWith('/oci/') ? '/oci/list' : '/vps/instances/list')
}
async function loadConfig() {
  if (!instanceId.value || invalidScope.value || draftLocked.value) return
  configController?.abort()
  const controller = configController = new AbortController()
  const version = ++configVersion
  configLoading.value = true
  configProblem.value = ''
  try {
    const config = await getSshConfig(instanceId.value, controller.signal)
    if (disposed || version !== configVersion) return
    if (config) {
      Object.assign(draft, config)
      saveProblem.value = ''
      saveState.value = 'idle'
      validation.value = ''
      if (!credentialsReady.value) openSettings()
    } else { configProblem.value = 'configMissing'; openSettings() }
  } catch (cause) {
    if (!disposed && version === configVersion && !controller.signal.aborted) {
      configProblem.value = sshError(cause).key
      openSettings()
    }
  } finally {
    if (!disposed && version === configVersion) configLoading.value = false
  }
}
async function saveConfig() {
  if (!instanceId.value || invalidScope.value || draftLocked.value || saveState.value === 'uncertain') return
  saving.value = true
  saveProblem.value = ''
  validation.value = ''
  try {
    await saveSshConfig(instanceId.value, { username: draft.username, port: draft.port, password: draft.password })
    if (!disposed) { saveState.value = 'saved'; feedback('success', 'saved') }
  } catch (cause) {
    if (!disposed) {
      saveProblem.value = sshError(cause).key
      saveState.value = isSshSaveUncertain(cause) ? 'uncertain' : 'idle'
    }
  } finally { if (!disposed) saving.value = false }
}
function connect() {
  if (connectDisabled.value || connected.value) return
  let credentials: SshCredentials
  try { credentials = normalizeSshCredentials(draft) } catch { validation.value = 'invalidInput'; openSettings(); return }
  validation.value = ''
  if (!session.connect(credentials)) return
  terminal.value?.reset()
  hasOutput.value = false
  searchResult.value = { index: 0, total: 0 }
  closeSettings()
  nextTick(() => terminal.value?.fit())
}
function disconnect() {
  if (transferBusy.value) return
  session.disconnect()
}
function reconnect() {
  if (transferBusy.value || saving.value) return
  session.disconnect()
  connect()
}
function terminalReady() {
  ready.value = true
  rendererProblem.value = ''
  const size = terminal.value?.getDimensions()
  if (size) resizeTerminal(size)
}
function terminalError(key: SshTerminalError) {
  rendererProblem.value = key
  ready.value = false
  session.disconnect()
}
function retryRenderer() { rendererProblem.value = ''; ready.value = false; hasOutput.value = false; rendererKey.value++ }
function resizeTerminal(size: SshTerminalDimensions) { dimensions.value = size; session.resize(size.cols, size.rows) }
function openSettings() {
  closeMenu()
  passwordVisible.value = false
  settingsBlocking.value = true
  settingsOpen.value = true
}
function closeSettings() {
  if (saving.value) return
  passwordVisible.value = false
  settingsOpen.value = false
}
function settingsVisibility(value: boolean) { if (value) openSettings(); else closeSettings() }
function beforeSettingsClose(done: () => void) { if (!saving.value) { closeSettings(); done() } }
function focusSettings() {
  if (disposed || !settingsOpen.value || leaveOpen.value) return
  const form = settingsForm.value
  const input = form?.querySelector<HTMLInputElement>('input:enabled:invalid') || form?.querySelector<HTMLInputElement>('input:enabled')
  input?.focus()
}
function restoreTerminalFocus() {
  nextTick(() => {
    if (disposed || settingsBlocking.value || leaveOpen.value) return
    terminal.value?.fit()
    if (connected.value) terminal.value?.focus()
  })
}
function settingsClosed() {
  if (settingsOpen.value) return
  settingsBlocking.value = false
  restoreTerminalFocus()
}
function toggleSearch() {
  searchOpen.value = !searchOpen.value
  if (searchOpen.value) nextTick(() => searchInput.value?.focus())
  else { terminal.value?.clearSelection(); terminal.value?.focus() }
}
function runSearch(direction?: 1 | -1) { searchResult.value = terminal.value?.search(searchQuery.value, direction) || { index: 0, total: 0 } }
function searchKey(event: KeyboardEvent) {
  if (event.key === 'Enter') { event.preventDefault(); runSearch(event.shiftKey ? -1 : 1) }
  else if (event.key === 'Escape') { event.preventDefault(); toggleSearch() }
}
function closeFiles() { filesOpen.value = false; pendingTransfer.value = null; terminal.value?.focus() }
function toggleFiles() { filesMounted.value = true; filesOpen.value = !filesOpen.value; pendingTransfer.value = null }
function focusPendingTransfer() {
  if (disposed || !filesOpen.value || !transfer.value || !pendingTransfer.value) return
  if (pendingTransfer.value === 'upload') transfer.value.focusUpload()
  else transfer.value.focusDownload()
  pendingTransfer.value = null
}
async function openTransfer(kind: 'upload' | 'download') {
  pendingTransfer.value = kind
  filesMounted.value = filesOpen.value = true
  await nextTick()
  focusPendingTransfer()
}
function changeFont(delta: number) { fontSize.value = Math.max(10, Math.min(24, fontSize.value + delta)) }
function clearTerminal() { terminal.value?.clear(); searchResult.value = { index: 0, total: 0 }; terminal.value?.focus() }
async function copyText(value: string) {
  if (!value) { feedback('info', 'nothingSelected'); return }
  try { await navigator.clipboard.writeText(value); if (!disposed) feedback('success', 'copied') }
  catch { if (!disposed) feedback('warning', 'clipboardFailed') }
}
function copySelection() { void copyText(terminal.value?.getSelection() || '') }
function copyPassword() { void copyText(draft.password) }
function copyCommand() {
  const value = profile.value || draft
  if (!value.host.trim() || !value.username.trim() || !Number.isInteger(value.port) || value.port < 1 || value.port > 65535) {
    feedback('info', 'errors.invalidInput'); return
  }
  const quote = (text: string) => "'" + text.replace(/'/g, "'\\''") + "'"
  void copyText(`ssh -p ${value.port} -l ${quote(value.username.trim())} -- ${quote(value.host.trim())}`)
}
async function paste() {
  if (!connected.value) return
  const key = connectionKey.value
  try {
    const text = await navigator.clipboard.readText()
    if (!disposed && key === connectionKey.value && connected.value) { terminal.value?.paste(text); terminal.value?.focus() }
  } catch { if (!disposed) feedback('info', 'pasteFailed') }
}
function downloadLog() {
  const text = terminal.value?.getBufferText() || ''
  if (!text.trim()) { feedback('info', 'noOutput'); return }
  const url = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = `ssh-terminal-${new Date().toISOString().replace(/[:.]/g, '-')}.txt`
  link.click()
  downloadUrls.set(url, setTimeout(() => { URL.revokeObjectURL(url); downloadUrls.delete(url) }, 30000))
}
async function toggleFullscreen() {
  try {
    if (document.fullscreenElement === pageRoot.value) await document.exitFullscreen()
    else await pageRoot.value?.requestFullscreen()
  } catch { if (!disposed) feedback('info', 'fullscreenFailed') }
}
function fullscreenChanged() { fullscreen.value = document.fullscreenElement === pageRoot.value; nextTick(() => terminal.value?.fit()) }
function shortcut(action: SshTerminalShortcut) {
  if (action === 'search') toggleSearch()
  else if (action === 'fullscreen') void toggleFullscreen()
  else if (action === 'increaseFont') changeFont(1)
  else if (action === 'decreaseFont') changeFont(-1)
  else if (action === 'copy') copySelection()
  else if (action === 'paste') void paste()
}
function showMenu(event: MouseEvent) {
  event.preventDefault()
  menu.value = { x: Math.max(8, Math.min(event.clientX, window.innerWidth - 232)), y: Math.max(8, Math.min(event.clientY, window.innerHeight - 352)) }
  nextTick(() => menuRoot.value?.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus())
}
function closeMenu() { menu.value = null }
function outsideMenu(event: PointerEvent) { if (menu.value && !menuRoot.value?.contains(event.target as Node)) closeMenu() }
function menuDisabled(action: MenuAction) {
  if (action === 'paste' || action === 'upload' || action === 'download') return !connected.value
  if (action === 'copy') return !terminal.value?.getSelection()
  return !ready.value
}
function menuAction(action: MenuAction) {
  closeMenu()
  if (action === 'copy') copySelection()
  else if (action === 'paste') void paste()
  else if (action === 'selectAll') terminal.value?.selectAll()
  else if (action === 'clear') clearTerminal()
  else if (action === 'copyCommand') copyCommand()
  else if (action === 'downloadLog') downloadLog()
  else void openTransfer(action)
  if (action !== 'upload' && action !== 'download') nextTick(() => terminal.value?.focus())
}
function menuKey(event: KeyboardEvent) {
  if (event.key === 'Escape') { event.preventDefault(); closeMenu(); terminal.value?.focus(); return }
  if (event.key === 'Tab') { closeMenu(); return }
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return
  event.preventDefault()
  const buttons = Array.from(menuRoot.value?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)') || [])
  const index = buttons.indexOf(document.activeElement as HTMLButtonElement)
  const target = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length
  buttons[target]?.focus()
}
function finishLeave(allowed: boolean) {
  if (allowed) session.disconnect()
  leaveOpen.value = false
  resolveLeave?.(allowed)
  resolveLeave = undefined
}
function stay() { finishLeave(false) }
function leave() { finishLeave(true) }
function leaveVisibility(value: boolean) { if (!value) stay() }
function canLeave(): boolean | Promise<boolean> {
  if (saving.value || transferBusy.value) { feedback('info', 'finishTransfer'); return false }
  if (!connected.value && !connecting.value) return true
  if (resolveLeave) return false
  closeMenu()
  leaveOpen.value = true
  return new Promise(resolve => { resolveLeave = resolve })
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (connected.value || connecting.value || saving.value || transferBusy.value) { event.preventDefault(); event.returnValue = '' }
}
onBeforeRouteLeave(canLeave)
onBeforeRouteUpdate(canLeave)
watch(transfer, focusPendingTransfer, { flush: 'post' })
watch(connected, (value) => { if (value) restoreTerminalFocus() })
watch(state, (value, previous) => {
  if (value === 'error' && previous === 'connecting' && !rendererProblem.value) openSettings()
}, { flush: 'sync' })
watch(fontSize, (value) => { try { localStorage.setItem('terminal.fontSize', String(value)) } catch { /* Preferences are optional. */ } })
watch(terminalTheme, (value) => { try { localStorage.setItem('terminal.theme', value) } catch { /* Preferences are optional. */ } })
watch([() => route.path, () => route.query.instanceId], () => {
  ++configVersion
  configController?.abort()
  configLoading.value = false
  if (state.value !== 'idle') session.disconnect()
  Object.assign(draft, { host: '', username: '', port: 22, password: '' })
  configProblem.value = saveProblem.value = validation.value = ''
  saveState.value = 'idle'
  passwordVisible.value = false
  closeSettings()
  if (!instanceId.value && !invalidScope.value) openSettings()
  filesOpen.value = filesMounted.value = false
  pendingTransfer.value = null
  searchQuery.value = ''
  hasOutput.value = false
  terminal.value?.reset()
  void loadConfig()
}, { immediate: true })
onMounted(() => {
  document.addEventListener('fullscreenchange', fullscreenChanged)
  document.addEventListener('pointerdown', outsideMenu)
  window.addEventListener('beforeunload', beforeUnload)
})
onBeforeUnmount(() => {
  disposed = true
  ++configVersion
  configController?.abort()
  resolveLeave?.(false)
  document.removeEventListener('fullscreenchange', fullscreenChanged)
  document.removeEventListener('pointerdown', outsideMenu)
  window.removeEventListener('beforeunload', beforeUnload)
  for (const [url, timer] of downloadUrls) { clearTimeout(timer); URL.revokeObjectURL(url) }
  downloadUrls.clear()
  draft.password = ''
})
</script>

<template>
  <section ref="pageRoot" class="ssh-workspace" :aria-label="t('sshTerminal.terminal')">
    <header class="ssh-toolbar">
      <PageBackButton @click="goBack" />
      <span class="ssh-state" :class="`is-${state}`" role="status"><span class="ssh-state-dot" />{{ stateLabel }}</span>
      <span class="ssh-target" :title="target">{{ target }}</span>
      <div class="ssh-connection-actions" data-page-error-anchor>
        <GhostBtn aria-haspopup="dialog" :aria-expanded="settingsOpen" @click="openSettings"><i class="i-mdi-tune" aria-hidden="true" />{{ t('sshTerminal.settings') }}</GhostBtn>
        <GhostBtn v-if="connected" :disabled="transferBusy || saving" :title="t('sshTerminal.reconnect')" @click="reconnect"><i class="i-mdi-refresh" aria-hidden="true" /><span>{{ t('sshTerminal.reconnect') }}</span></GhostBtn>
        <GhostBtn v-if="connected || connecting" :disabled="transferBusy" @click="disconnect">{{ t(connecting ? 'sshTerminal.cancelConnect' : 'sshTerminal.disconnect') }}</GhostBtn>
        <PrimaryBtn v-else :disabled="connectDisabled" @click="connect"><i class="i-mdi-console" aria-hidden="true" />{{ t('sshTerminal.connect') }}</PrimaryBtn>
      </div>
    </header>

    <div v-if="invalidScope" class="ssh-notice" role="alert">{{ t('sshTerminal.invalidScope') }}</div>
    <template v-else-if="!settingsOpen && (problem || settingsProblem)">
      <div v-if="validation || settingsProblem === 'invalidInput' || settingsProblem === 'configMissing'" class="ssh-notice ssh-notice-summary" role="alert"><span>{{ t(`sshTerminal.errors.${validation || settingsProblem}`) }}</span><GhostBtn @click="openSettings">{{ t('sshTerminal.settings') }}</GhostBtn></div>
      <div v-if="saveState === 'uncertain' && saveProblem" class="ssh-notice ssh-notice-summary" role="alert"><span>{{ t('sshTerminal.verifyBeforeRetry') }}</span><GhostBtn @click="openSettings">{{ t('sshTerminal.settings') }}</GhostBtn></div>
      <PageErrorNotice v-if="problem || settingsProblem && settingsProblem !== 'invalidInput' && settingsProblem !== 'configMissing'"><span v-if="problem">{{ t(`sshTerminal.errors.${problem.key}`) }} <span v-if="problem.detail">{{ problem.detail }}</span></span><span v-if="settingsProblem && settingsProblem !== 'invalidInput' && settingsProblem !== 'configMissing'">{{ t(`sshTerminal.errors.${settingsProblem}`) }}</span><GhostBtn @click="openSettings">{{ t('sshTerminal.settings') }}</GhostBtn></PageErrorNotice>
    </template>
    <PageErrorNotice v-if="rendererProblem"><span>{{ t(`sshTerminal.rendererErrors.${rendererProblem}`) }}</span><GhostBtn @click="retryRenderer">{{ t('sshTerminal.retryRenderer') }}</GhostBtn></PageErrorNotice>

    <div class="ssh-tools">
      <div class="ssh-tools-group">
        <button type="button" class="ssh-tool" :class="{ 'is-active': searchOpen }" :disabled="!ready" :title="t('sshTerminal.searchHint')" :aria-expanded="searchOpen" @click="toggleSearch"><i class="i-mdi-magnify" aria-hidden="true" /><span>{{ t('sshTerminal.search') }}</span></button>
        <button type="button" class="ssh-tool" :class="{ 'is-active': filesOpen }" :aria-expanded="filesOpen" @click="toggleFiles"><i class="i-mdi-folder-outline" aria-hidden="true" /><span>{{ t('sshTerminal.files') }}</span><span v-if="transferBusy" class="ssh-busy-dot" /></button>
        <button type="button" class="ssh-tool" :disabled="!ready" :title="t('sshTerminal.actions.clear')" @click="clearTerminal"><i class="i-mdi-broom" aria-hidden="true" /><span>{{ t('sshTerminal.actions.clear') }}</span></button>
        <button type="button" class="ssh-icon" :title="t('sshTerminal.actions.copyCommand')" :aria-label="t('sshTerminal.actions.copyCommand')" @click="copyCommand"><i class="i-mdi-console-line" aria-hidden="true" /></button>
        <button type="button" class="ssh-icon" :disabled="!ready" :title="t('sshTerminal.logHint')" :aria-label="t('sshTerminal.actions.downloadLog')" @click="downloadLog"><i class="i-mdi-download-outline" aria-hidden="true" /></button>
      </div>
      <div class="ssh-tools-group">
        <div class="ssh-font-control"><button type="button" class="ssh-icon" :disabled="fontSize <= 10" :title="t('sshTerminal.smaller')" :aria-label="t('sshTerminal.smaller')" @click="changeFont(-1)"><i class="i-mdi-minus" aria-hidden="true" /></button><span>{{ fontSize }}</span><button type="button" class="ssh-icon" :disabled="fontSize >= 24" :title="t('sshTerminal.larger')" :aria-label="t('sshTerminal.larger')" @click="changeFont(1)"><i class="i-mdi-plus" aria-hidden="true" /></button></div>
        <el-select v-model="terminalTheme" class="ssh-theme-select" popper-class="ssh-theme-popper" :teleported="false" :aria-label="t('sshTerminal.theme')" :title="t('sshTerminal.theme')"><el-option v-for="theme in themes" :key="theme" :value="theme" :label="t(`sshTerminal.themes.${theme}`)" /></el-select>
        <button type="button" class="ssh-icon" :title="t(fullscreen ? 'sshTerminal.exitFullscreen' : 'sshTerminal.fullscreen')" :aria-label="t(fullscreen ? 'sshTerminal.exitFullscreen' : 'sshTerminal.fullscreen')" @click="toggleFullscreen"><i :class="fullscreen ? 'i-mdi-fullscreen-exit' : 'i-mdi-fullscreen'" aria-hidden="true" /></button>
      </div>
    </div>
    <div v-show="searchOpen" class="ssh-search">
      <i class="i-mdi-magnify" aria-hidden="true" />
      <input ref="searchInput" v-model="searchQuery" :placeholder="t('sshTerminal.searchPlaceholder')" :aria-label="t('sshTerminal.searchPlaceholder')" :spellcheck="false" @input="runSearch()" @keydown="searchKey" />
      <span role="status">{{ searchResult.total ? t('sshTerminal.searchCount', { index: searchResult.index, total: searchResult.total }) : t('sshTerminal.noMatches') }}</span>
      <button type="button" class="ssh-icon" :disabled="!searchResult.total" :title="t('sshTerminal.previousMatch')" :aria-label="t('sshTerminal.previousMatch')" @click="runSearch(-1)"><i class="i-mdi-chevron-up" aria-hidden="true" /></button>
      <button type="button" class="ssh-icon" :disabled="!searchResult.total" :title="t('sshTerminal.nextMatch')" :aria-label="t('sshTerminal.nextMatch')" @click="runSearch(1)"><i class="i-mdi-chevron-down" aria-hidden="true" /></button>
      <button type="button" class="ssh-icon" :title="t('sshTerminal.closeSearch')" :aria-label="t('sshTerminal.closeSearch')" @click="toggleSearch"><i class="i-mdi-close" aria-hidden="true" /></button>
    </div>

    <div class="ssh-stage">
      <div class="ssh-terminal-main" @contextmenu="showMenu">
        <SshTerminalCanvas :key="rendererKey" ref="terminal" :active="!settingsBlocking && !leaveOpen" :input-enabled="connected && !settingsBlocking && !leaveOpen" :font-size="fontSize" :theme="terminalTheme" :aria-label="t('sshTerminal.terminal')" @data="session.sendInput" @resize="resizeTerminal" @ready="terminalReady" @error="terminalError" @search="searchResult = $event" @shortcut="shortcut" />
        <div v-if="!rendererProblem && !hasOutput && !connected" class="ssh-terminal-overlay is-passive"><i class="i-mdi-console" aria-hidden="true" /><p>{{ t(!ready ? 'sshTerminal.loadingTerminal' : connecting ? 'sshTerminal.connectingHint' : credentialsReady ? 'sshTerminal.readyHint' : 'sshTerminal.emptyHint') }}</p></div>
      </div>
      <aside v-if="filesMounted" v-show="filesOpen" class="ssh-files" :aria-label="t('sshTerminal.files')"><div class="ssh-files-heading" data-page-error-anchor><span>{{ t('sshTerminal.files') }}</span><button type="button" class="ssh-icon" :title="t('sshTerminal.closeFiles')" :aria-label="t('sshTerminal.closeFiles')" @click="closeFiles"><i class="i-mdi-close" aria-hidden="true" /></button></div><SftpPanel ref="transfer" :visible="filesOpen" :connected="connected" :credentials="profile" :connection-key="connectionKey" @busy="transferBusy = $event" /></aside>
    </div>
    <footer class="ssh-footer"><span>{{ t('sshTerminal.keyboardHint') }}</span><div><span v-if="dimensions.cols">{{ dimensions.cols }} × {{ dimensions.rows }}</span><button type="button" :disabled="!ready" @click="terminal?.scrollToBottom()">{{ t('sshTerminal.latest') }}<i class="i-mdi-arrow-down" aria-hidden="true" /></button></div></footer>
    <div v-if="menu" ref="menuRoot" class="ssh-context-menu" role="menu" :aria-label="t('sshTerminal.contextMenu')" :style="{ left: `${menu.x}px`, top: `${menu.y}px` }" @keydown="menuKey"><button v-for="action in menuItems" :key="action" type="button" role="menuitem" :disabled="menuDisabled(action)" @click="menuAction(action)">{{ t(`sshTerminal.actions.${action}`) }}</button></div>
    <el-dialog :model-value="settingsOpen" :title="t('sshTerminal.settings')" width="560px" align-center :append-to-body="false" :close-on-click-modal="false" :close-on-press-escape="!saving" :show-close="!saving" :before-close="beforeSettingsClose" class="ssh-settings-dialog" @update:model-value="settingsVisibility" @opened="focusSettings" @closed="settingsClosed" @close-auto-focus="restoreTerminalFocus">
      <form id="ssh-connection-settings" ref="settingsForm" class="ssh-settings" novalidate @submit.prevent="connect">
        <p v-if="connected || connecting" class="ssh-settings-hint">{{ t('sshTerminal.connectedSettingsHint') }}</p>
        <div class="ssh-fields">
          <label class="ssh-field ssh-host"><span>{{ t('sshTerminal.host') }}</span><input v-model="draft.host" :disabled="draftLocked" :placeholder="t('sshTerminal.hostPlaceholder')" required autocomplete="off" autocapitalize="off" :spellcheck="false" /></label>
          <label class="ssh-field"><span>{{ t('sshTerminal.username') }}</span><input v-model="draft.username" :disabled="draftLocked" required autocomplete="off" autocapitalize="off" :spellcheck="false" /></label>
          <label class="ssh-field ssh-port"><span>{{ t('sshTerminal.port') }}</span><input v-model.number="draft.port" :disabled="draftLocked" required type="number" min="1" max="65535" step="1" inputmode="numeric" /></label>
          <label class="ssh-field ssh-password"><span>{{ t('sshTerminal.password') }}</span><span class="ssh-password-control"><input v-model="draft.password" :disabled="draftLocked" required :type="passwordVisible ? 'text' : 'password'" autocomplete="new-password" :spellcheck="false" /><button type="button" class="ssh-icon" :aria-label="t(passwordVisible ? 'sshTerminal.hidePassword' : 'sshTerminal.showPassword')" :title="t(passwordVisible ? 'sshTerminal.hidePassword' : 'sshTerminal.showPassword')" @click="passwordVisible = !passwordVisible"><i :class="passwordVisible ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button><button type="button" class="ssh-icon" :disabled="!draft.password" :title="t('sshTerminal.copyPassword')" :aria-label="t('sshTerminal.copyPassword')" @click="copyPassword"><i class="i-mdi-content-copy" aria-hidden="true" /></button></span></label>
        </div>
        <div v-if="configProblem === 'configMissing'" class="ssh-notice" role="alert">{{ t(`sshTerminal.errors.${configProblem}`) }}</div>
        <PageErrorNotice v-else-if="settingsOpen && configProblem">{{ t(`sshTerminal.errors.${configProblem}`) }}</PageErrorNotice>
        <div v-if="validation" class="ssh-notice" role="alert">{{ t(`sshTerminal.errors.${validation}`) }}</div>
        <div v-if="saveProblem === 'invalidInput'" class="ssh-notice" role="alert">{{ t(`sshTerminal.errors.${saveProblem}`) }}</div>
        <PageErrorNotice v-else-if="settingsOpen && saveProblem">{{ t(`sshTerminal.errors.${saveProblem}`) }}</PageErrorNotice>
        <div v-if="saveState === 'uncertain' && saveProblem" class="ssh-notice" role="alert">{{ t('sshTerminal.verifyBeforeRetry') }}</div>
        <PageErrorNotice v-if="settingsOpen && problem">{{ t(`sshTerminal.errors.${problem.key}`) }} <span v-if="problem.detail">{{ problem.detail }}</span></PageErrorNotice>
        <div v-if="instanceId && !invalidScope" class="ssh-config-footer"><span>{{ configLoading ? t('sshTerminal.loadingConfig') : t('sshTerminal.saveHint') }}</span><div><GhostBtn :disabled="draftLocked" @click="loadConfig">{{ t(saveState === 'uncertain' ? 'sshTerminal.verifySave' : 'sshTerminal.reloadConfig') }}</GhostBtn><GhostBtn :disabled="draftLocked || saveState === 'uncertain'" :loading="saving" @click="saveConfig">{{ t('sshTerminal.save') }}</GhostBtn></div></div>
      </form>
      <template #footer>
        <GhostBtn :disabled="saving" @click="closeSettings">{{ t('sshTerminal.closeSettings') }}</GhostBtn>
        <GhostBtn v-if="connecting" :disabled="transferBusy" @click="disconnect">{{ t('sshTerminal.cancelConnect') }}</GhostBtn>
        <PrimaryBtn v-else-if="!connected" type="submit" form="ssh-connection-settings" :disabled="connectDisabled"><i class="i-mdi-console" aria-hidden="true" />{{ t('sshTerminal.connect') }}</PrimaryBtn>
      </template>
    </el-dialog>
    <el-dialog :model-value="leaveOpen" :title="t('sshTerminal.leaveTitle')" width="420px" :close-on-click-modal="false" :show-close="false" class="ssh-leave-dialog" @update:model-value="leaveVisibility"><p>{{ t('sshTerminal.leaveHint') }}</p><template #footer><GhostBtn @click="stay">{{ t('sshTerminal.stay') }}</GhostBtn><PrimaryBtn @click="leave">{{ t('sshTerminal.leave') }}</PrimaryBtn></template></el-dialog>
  </section>
</template>
