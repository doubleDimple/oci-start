<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { chromeRevision } from '@/composables/useChrome'
import { loadVncRuntime } from './vncRuntime'
import type {
  RfbClient, VncCanvasError, VncCanvasHandle, VncClipboard, VncCredentials,
  VncCredentialsRequired, VncDesktopName, VncDisconnect, VncSecurityFailure,
} from './vncTypes'
import './vncCanvas.scss'

const props = withDefaults(defineProps<{
  url: string | null
  active?: boolean
  viewOnly?: boolean
  scale?: boolean
  ariaLabel?: string
}>(), { active: true, viewOnly: false, scale: false, ariaLabel: 'VNC' })
const emit = defineEmits<{
  loading: [value: boolean]
  connect: []
  disconnect: [event: VncDisconnect]
  credentialsrequired: [event: VncCredentialsRequired]
  securityfailure: [event: VncSecurityFailure]
  clipboard: [event: VncClipboard]
  desktopname: [event: VncDesktopName]
  error: [key: VncCanvasError]
  activity: []
  textpending: [value: boolean]
}>()
const host = ref<HTMLElement>()
const MAX_TEXT_UNITS = 64 * 1024
const TEXT_BATCH_POINTS = 64
let client: RfbClient | undefined
let mount: HTMLElement | undefined
let connected = false
let awaitingCredentials = false
let mounted = false
let disposed = false
let generation = 0
let loadingCount = 0
let fitFrame = 0
let textFrame = 0
let finishText: ((sent: boolean) => void) | undefined
let resizeObserver: ResizeObserver | undefined
let themeObserver: MutationObserver | undefined
let listeners: { name: string; listener: EventListener }[] = []

function reportError(key: VncCanvasError) { if (!disposed) emit('error', key) }
function beginLoading() { if (++loadingCount === 1 && !disposed) emit('loading', true) }
function endLoading() { if (--loadingCount === 0 && !disposed) emit('loading', false) }
function getConnected() { return connected && !!client && !disposed }
function canInput() { return getConnected() && props.active && !props.viewOnly }
function detail(event: Event): Record<string, unknown> {
  const value: unknown = (event as CustomEvent<unknown>).detail
  return value !== null && typeof value === 'object' ? value as Record<string, unknown> : {}
}
function cancelText() {
  if (textFrame) cancelAnimationFrame(textFrame)
  textFrame = 0
  finishText?.(false)
}
function disconnect() {
  ++generation
  cancelText()
  connected = false
  awaitingCredentials = false
  const previous = client
  const previousMount = mount
  client = undefined
  mount = undefined
  if (previous) {
    for (const { name, listener } of listeners) previous.removeEventListener(name, listener)
    try { previous.disconnect() } catch { /* The local renderer is still discarded. */ }
  }
  listeners = []
  // Each RFB owns a separate target. Late noVNC cleanup can only touch its
  // detached target, never the next connection's canvas or DOM children.
  previousMount?.remove()
}
function focus() {
  if (!canInput()) return
  try { client?.focus() } catch { reportError('inputFailed') }
}
function blur() { try { client?.blur() } catch { /* A closing canvas may already be detached. */ } }
function setLabel() {
  const canvas = mount?.querySelector('canvas')
  if (canvas) canvas.setAttribute('aria-label', props.ariaLabel)
}
function updatePresentation() {
  if (!client || !host.value || disposed) return
  // This is the DOM area surrounding the remote pixels, not a canvas palette.
  // Let CSS resolve modern custom colors without changing the framebuffer.
  client.background = getComputedStyle(host.value).backgroundColor
  setLabel()
}
function fit() {
  if (fitFrame || disposed) return
  fitFrame = requestAnimationFrame(() => {
    fitFrame = 0
    if (!client || !host.value || disposed) return
    const bounds = host.value.getBoundingClientRect()
    if (bounds.width < 1 || bounds.height < 1) return
    // noVNC's public setter recalculates local scaling. It never requests a
    // different remote desktop resolution: resizeSession always stays false.
    client.scaleViewport = props.scale
  })
}
function updateInput() {
  if (!client || disposed) return
  if (!props.active || props.viewOnly) {
    cancelText()
    blur()
  }
  client.viewOnly = props.viewOnly || !props.active
  client.focusOnClick = props.active && !props.viewOnly
}
function activity() { if (canInput()) emit('activity') }

async function prepare(): Promise<boolean> {
  if (disposed) return false
  const version = generation
  beginLoading()
  try {
    await loadVncRuntime()
    return !disposed && version === generation
  } catch {
    if (!disposed && version === generation) reportError('loadFailed')
    return false
  } finally { endLoading() }
}
function validUrl(value: string): boolean {
  try {
    const url = new URL(value)
    return ['ws:', 'wss:'].includes(url.protocol) && !!url.hostname
      && !url.username && !url.password && !url.hash
      && !(window.location.protocol === 'https:' && url.protocol !== 'wss:')
  } catch { return false }
}
async function retry(): Promise<boolean> {
  disconnect()
  if (disposed || !mounted || !host.value || !props.url) return false
  const url = props.url
  if (!validUrl(url)) { reportError('invalidUrl'); return false }
  const version = generation
  beginLoading()
  let runtimeReady = false
  try {
    const RFB = await loadVncRuntime()
    runtimeReady = true
    if (disposed || version !== generation || url !== props.url || !host.value) return false
    const target = document.createElement('div')
    target.className = 'vnc-canvas-mount'
    mount = target
    host.value.append(target)
    const current = new RFB(target, url, { shared: true, wsProtocols: ['binary'] })
    client = current
    const currentConnection = () => !disposed && version === generation && client === current
    const listen = (name: string, callback: (event: Event) => void) => {
      const listener: EventListener = event => { if (currentConnection()) callback(event) }
      listeners.push({ name, listener })
      current.addEventListener(name, listener)
    }
    listen('connect', () => {
      connected = true
      awaitingCredentials = false
      updateInput()
      updatePresentation()
      fit()
      emit('connect')
      // Event consumers may immediately open a modal or dispose this session.
      if (currentConnection()) focus()
    })
    listen('disconnect', event => {
      const data = detail(event)
      const result = { clean: data.clean === true, reason: typeof data.reason === 'string' ? data.reason : '' }
      disconnect()
      emit('disconnect', result)
    })
    listen('credentialsrequired', event => {
      const data = detail(event)
      awaitingCredentials = true
      emit('credentialsrequired', { types: Array.isArray(data.types) ? data.types.filter((type): type is string => typeof type === 'string') : [] })
    })
    listen('securityfailure', event => {
      const data = detail(event)
      const result = {
        status: typeof data.status === 'number' && Number.isFinite(data.status) ? data.status : null,
        reason: typeof data.reason === 'string' ? data.reason : '',
      }
      disconnect()
      emit('securityfailure', result)
    })
    listen('clipboard', event => {
      const data = detail(event)
      if (typeof data.text === 'string') emit('clipboard', { text: data.text })
    })
    listen('desktopname', event => {
      const data = detail(event)
      if (typeof data.name === 'string') emit('desktopname', { name: data.name })
    })
    // Scale only the local viewport; keep the guest resolution unchanged.
    // Quality/compression remain engine defaults; the old constructor's extra
    // quality options were not noVNC constructor parameters.
    current.resizeSession = false
    current.scaleViewport = props.scale
    updateInput()
    updatePresentation()
    fit()
    return true
  } catch {
    if (!disposed && version === generation) {
      disconnect()
      reportError(runtimeReady ? 'connectFailed' : 'loadFailed')
    }
    return false
  } finally { endLoading() }
}

function sendCredentials(credentials: VncCredentials): boolean {
  // Credentials must remain available while a modal pauses local input.
  if (!client || disposed || !awaitingCredentials) return false
  const values: VncCredentials = {}
  for (const key of ['username', 'password', 'target'] as const) {
    if (typeof credentials[key] === 'string') values[key] = credentials[key]
  }
  try {
    awaitingCredentials = false
    client.sendCredentials(values)
    return true
  } catch {
    disconnect()
    reportError('connectFailed')
    return false
  }
}
function sendCtrlAltDel(): boolean {
  if (!canInput() || finishText) return false
  try { client!.sendCtrlAltDel(); emit('activity'); return true }
  catch { reportError('inputFailed'); return false }
}
function sendKey(keysym: number, code?: string, down?: boolean): boolean {
  if (!canInput() || finishText) return false
  if (!Number.isInteger(keysym) || keysym <= 0 || keysym > 0x0110ffff) { reportError('inputFailed'); return false }
  try { client!.sendKey(keysym, code, down); emit('activity'); return true }
  catch { reportError('inputFailed'); return false }
}
function clipboardPaste(text: string): boolean {
  if (!canInput() || finishText) return false
  if (text.length > MAX_TEXT_UNITS) { reportError('textTooLarge'); return false }
  try { client!.clipboardPasteFrom(text); emit('activity'); return true }
  catch { reportError('inputFailed'); return false }
}
function textKeysyms(text: string): number[] | null {
  const result: number[] = []
  let afterReturn = false
  for (const character of text) {
    const point = character.codePointAt(0)!
    if (point === 10 && afterReturn) { afterReturn = false; continue }
    afterReturn = point === 13
    if (point === 10 || point === 13) result.push(0xff0d)
    else if (point === 9) result.push(0xff09)
    else if (point === 8) result.push(0xff08)
    else if (point === 27) result.push(0xff1b)
    else if (point === 127) result.push(0xffff)
    else if (point < 32 || (point >= 0xd800 && point <= 0xdfff)) return null
    else result.push(point <= 0xff ? point : 0x01000000 + point)
  }
  return result
}
function sendText(text: string): Promise<boolean> {
  if (!canInput() || finishText) return Promise.resolve(false)
  if (text.length > MAX_TEXT_UNITS) { reportError('textTooLarge'); return Promise.resolve(false) }
  const keysyms = textKeysyms(text)
  if (!keysyms) { reportError('inputFailed'); return Promise.resolve(false) }
  if (!keysyms.length) return Promise.resolve(true)
  const current = client!
  const version = generation
  return new Promise(resolve => {
    let offset = 0
    const finish = (sent: boolean) => {
      if (finishText !== finish) return
      if (textFrame) cancelAnimationFrame(textFrame)
      textFrame = 0
      finishText = undefined
      emit('textpending', false)
      resolve(sent)
    }
    finishText = finish
    emit('textpending', true)
    const batch = () => {
      textFrame = 0
      if (finishText !== finish) return
      if (!canInput() || version !== generation || client !== current) { finish(false); return }
      try {
        const end = Math.min(offset + TEXT_BATCH_POINTS, keysyms.length)
        while (offset < end) {
          const keysym = keysyms[offset++]!
          // No physical scan code: Unicode text must use RFB keysyms even when
          // a server advertises the optional QEMU physical-key extension.
          try { current.sendKey(keysym, undefined, true) }
          finally { current.sendKey(keysym, undefined, false) }
        }
        emit('activity')
      } catch { finish(false); reportError('inputFailed'); return }
      if (offset === keysyms.length) finish(true)
      else textFrame = requestAnimationFrame(batch)
    }
    textFrame = requestAnimationFrame(batch)
  })
}

watch(() => props.url, () => { if (mounted) void retry() })
watch(() => [props.active, props.viewOnly], () => {
  updateInput()
  if (props.active) { fit(); focus() }
}, { flush: 'post' })
watch(() => props.scale, fit, { flush: 'post' })
watch([chromeRevision, () => props.ariaLabel], updatePresentation, { flush: 'post' })
onMounted(() => {
  mounted = true
  if (host.value) {
    resizeObserver = new ResizeObserver(fit)
    resizeObserver.observe(host.value)
  }
  themeObserver = new MutationObserver(updatePresentation)
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-content-theme'] })
  window.addEventListener('resize', fit)
  if (props.url) void retry()
})
onBeforeUnmount(() => {
  disposed = true
  mounted = false
  disconnect()
  if (fitFrame) cancelAnimationFrame(fitFrame)
  resizeObserver?.disconnect()
  themeObserver?.disconnect()
  window.removeEventListener('resize', fit)
  if (loadingCount) emit('loading', false)
})
defineExpose<VncCanvasHandle>({
  prepare, retry, disconnect, focus, blur, fit, getConnected,
  sendCredentials, sendCtrlAltDel, sendKey, sendText, cancelText, clipboardPaste,
})
</script>

<template>
  <div ref="host" class="vnc-canvas" :aria-label="ariaLabel"
    @pointerdown.capture="activity" @keydown.capture="activity" @wheel.capture.passive="activity" />
</template>
