<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { chromeRevision } from '@/composables/useChrome'
import { loadTerminalRuntime, loadTerminalWebLinks } from './sshTerminalRuntime'
import { terminalPalette } from './sshTerminalTheme'
import type {
  LocalTerminal, LocalFitAddon, TerminalDisposable, TerminalRuntime, SshTerminalTheme,
  SshTerminalError, SshTerminalShortcut, SshTerminalDimensions, SshTerminalSearch,
  SshTerminalCanvasHandle,
} from './sshTerminalTypes'
import './sshTerminalCanvas.scss'

const props = withDefaults(defineProps<{
  active?: boolean
  inputEnabled?: boolean
  fontSize?: number
  theme?: SshTerminalTheme
  ariaLabel?: string
}>(), { active: true, inputEnabled: false, fontSize: 14, theme: 'system', ariaLabel: 'SSH terminal' })
const emit = defineEmits<{
  data: [data: string]
  resize: [dimensions: SshTerminalDimensions]
  ready: []
  error: [key: SshTerminalError]
  search: [result: SshTerminalSearch]
  shortcut: [shortcut: SshTerminalShortcut]
}>()
const host = ref<HTMLElement>()
const MAX_PENDING_BYTES = 8 * 1024 * 1024
const WRITE_BATCH_BYTES = 32 * 1024
const MAX_PENDING_FRAGMENTS = 8192
interface PendingWrite { data: string | Uint8Array; bytes: number }
let terminal: LocalTerminal | undefined
let runtime: TerminalRuntime | undefined
let fitAddon: LocalFitAddon | undefined
let resizeObserver: ResizeObserver | undefined
let themeObserver: MutationObserver | undefined
let reducedMotion: MediaQueryList | undefined
let fitFrame = 0
let writeFrame = 0
let disposed = false
let failed = false
let outputBlocked = false
let writing = false
let pendingBytes = 0
let inFlightBytes = 0
let pending: (PendingWrite | undefined)[] = []
let pendingIndex = 0
let lastDimensions = ''
let bufferVersion = 0
let searchVersion = -1
let searchQuery = ''
let searchMatches: number[] = []
let searchIndex = -1
const listeners: TerminalDisposable[] = []

function reportError(key: SshTerminalError) {
  if (disposed) return
  if (key !== 'outputOverflow') failed = true
  emit('error', key)
}
function effectiveFontSize() {
  return Number.isFinite(props.fontSize) ? Math.min(24, Math.max(10, Math.round(props.fontSize))) : 14
}
function clearSearch() {
  searchQuery = ''; searchMatches = []; searchIndex = -1; searchVersion = -1
  emit('search', { index: 0, total: 0 })
}
function focus() {
  if (!disposed && props.active && terminal) terminal.focus()
}
function getDimensions(): SshTerminalDimensions | null {
  return terminal ? { cols: terminal.cols, rows: terminal.rows } : null
}
function publishDimensions() {
  const dimensions = getDimensions()
  if (!dimensions) return
  const key = `${dimensions.cols}:${dimensions.rows}`
  if (key !== lastDimensions) { lastDimensions = key; emit('resize', dimensions) }
}
function fit() {
  if (disposed || fitFrame) return
  fitFrame = requestAnimationFrame(() => {
    fitFrame = 0
    if (!terminal || !fitAddon || !host.value || !props.active || disposed || failed) return
    const bounds = host.value.getBoundingClientRect()
    if (bounds.width < 2 || bounds.height < 2) return
    try {
      const dimensions = fitAddon.proposeDimensions()
      if (!dimensions || !Number.isFinite(dimensions.cols) || !Number.isFinite(dimensions.rows)
        || dimensions.cols < 2 || dimensions.rows < 1) return
      fitAddon.fit()
      publishDimensions()
    } catch { reportError('renderFailed') }
  })
}
function updateTheme() {
  if (!terminal || !host.value || disposed) return
  try {
    const palette = terminalPalette(props.theme)
    terminal.options.theme = palette
    terminal.options.fontSize = effectiveFontSize()
    terminal.options.fontFamily = getComputedStyle(host.value).getPropertyValue('--mono').trim()
      || 'SFMono-Regular, Menlo, Monaco, Consolas, monospace'
    terminal.options.cursorBlink = !reducedMotion?.matches
    host.value.style.setProperty('--terminal-background', palette.background || '')
    host.value.style.setProperty('--terminal-foreground', palette.foreground || '')
    fit()
  } catch { reportError('renderFailed') }
}
function scheduleWrite() {
  if (disposed || failed || writing || writeFrame || !terminal) return
  writeFrame = requestAnimationFrame(drain)
}
function drain() {
  writeFrame = 0
  if (disposed || failed || writing || !terminal) return
  const first = pending[pendingIndex]
  if (!first) return
  const fragments: (string | Uint8Array)[] = []
  let bytes = 0
  while (pendingIndex < pending.length) {
    const item = pending[pendingIndex]!
    if (typeof item.data !== typeof first.data || bytes + item.bytes > WRITE_BATCH_BYTES) break
    fragments.push(item.data)
    bytes += item.bytes
    pending[pendingIndex++] = undefined
  }
  let data: string | Uint8Array
  if (typeof first.data === 'string') data = (fragments as string[]).join('')
  else {
    data = new Uint8Array(bytes)
    let offset = 0
    for (const fragment of fragments as Uint8Array[]) { data.set(fragment, offset); offset += fragment.byteLength }
  }
  pendingBytes -= bytes
  inFlightBytes = bytes
  if (pendingIndex === pending.length) { pending = []; pendingIndex = 0 }
  else if (pendingIndex >= 256) { pending = pending.slice(pendingIndex); pendingIndex = 0 }
  writing = true
  const active = terminal
  try {
    active.write(data, () => {
      if (disposed || terminal !== active) return
      writing = false
      inFlightBytes = 0
      ++bufferVersion
      // One <=32 KiB parser batch per animation frame. Input and IME events are
      // emitted immediately, independent of output and Vue's reactive updates.
      scheduleWrite()
    })
  } catch {
    writing = false; inFlightBytes = 0
    pending = []; pendingIndex = 0; pendingBytes = 0
    reportError('renderFailed')
  }
}
function write(data: string | Uint8Array): boolean {
  if (disposed || failed || outputBlocked) return false
  const bytes = typeof data === 'string' ? data.length * 2 : data.byteLength
  if (bytes === 0) return true
  const chunkCount = Math.ceil(bytes / (WRITE_BATCH_BYTES - 2))
  if (bytes + pendingBytes + inFlightBytes > MAX_PENDING_BYTES
    || pending.length - pendingIndex + chunkCount > MAX_PENDING_FRAGMENTS) {
    // Reject this complete payload and latch until reset. Dropping arbitrary
    // ANSI fragments and continuing would silently corrupt the terminal state.
    outputBlocked = true
    emit('error', 'outputOverflow')
    return false
  }
  if (typeof data === 'string') {
    for (let offset = 0; offset < data.length;) {
      let end = Math.min(offset + WRITE_BATCH_BYTES / 2, data.length)
      const last = data.charCodeAt(end - 1)
      if (end < data.length && last >= 0xd800 && last <= 0xdbff) --end
      const chunk = data.slice(offset, end)
      pending.push({ data: chunk, bytes: chunk.length * 2 })
      offset = end
    }
  } else {
    for (let offset = 0; offset < data.byteLength; offset += WRITE_BATCH_BYTES) {
      const chunk = data.slice(offset, offset + WRITE_BATCH_BYTES)
      pending.push({ data: chunk, bytes: chunk.byteLength })
    }
  }
  pendingBytes += bytes
  scheduleWrite()
  return true
}
function clear() {
  if (!terminal || disposed || failed) return
  terminal.clear()
  ++bufferVersion
  clearSearch()
}
function reset() {
  if (disposed || failed) return
  const dimensions = getDimensions()
  cancelAnimationFrame(writeFrame); writeFrame = 0
  pending = []; pendingIndex = 0; pendingBytes = 0; outputBlocked = false
  writing = false; inFlightBytes = 0
  ++bufferVersion
  clearSearch()
  // This local 4.x reset() does not reset every decoder/parser state. A new
  // runtime instance prevents an unfinished OSC/UTF-8/IME sequence from leaking
  // into the next SSH connection. Old write callbacks are identity-guarded.
  if (runtime && host.value) {
    try { createTerminal(dimensions || undefined) } catch { reportError('renderFailed') }
  }
}
function paste(text: string) {
  if (!disposed && props.active && props.inputEnabled && !failed) terminal?.paste(text)
}
function getSelection() { return terminal?.getSelection() || '' }
function selectAll() { terminal?.selectAll() }
function clearSelection() { terminal?.clearSelection() }
function scrollToBottom() { terminal?.scrollToBottom() }
function getBufferText() {
  if (!terminal) return ''
  const buffer = terminal.buffer.active
  const lines: string[] = []
  for (let index = 0; index < buffer.length; index++) {
    const line = buffer.getLine(index)
    if (!line) continue
    const text = line.translateToString(true)
    if (line.isWrapped && lines.length) lines[lines.length - 1] = lines[lines.length - 1]! + text
    else lines.push(text)
  }
  // Export retained, rendered text, not an unbounded raw ANSI transcript.
  return lines.join('\n').replace(/\n+$/, '')
}
function search(query: string, direction?: 1 | -1): SshTerminalSearch {
  if (!terminal || !query) {
    clearSearch()
    terminal?.clearSelection()
    return { index: 0, total: 0 }
  }
  if (query !== searchQuery || searchVersion !== bufferVersion) {
    const previousQuery = searchQuery
    searchQuery = query; searchMatches = []
    const needle = query.toLowerCase()
    const buffer = terminal.buffer.active
    for (let line = 0; line < buffer.length; line++) {
      if (buffer.getLine(line)?.translateToString(true).toLowerCase().includes(needle)) searchMatches.push(line)
    }
    searchIndex = previousQuery === query ? Math.min(searchIndex, searchMatches.length - 1) : -1
    searchVersion = bufferVersion
  }
  if (searchMatches.length) {
    searchIndex = searchIndex < 0 ? (direction === -1 ? searchMatches.length - 1 : 0)
      : direction ? (searchIndex + direction + searchMatches.length) % searchMatches.length : 0
    terminal.scrollToLine(searchMatches[searchIndex]!)
  }
  const result = { index: searchMatches.length ? searchIndex + 1 : 0, total: searchMatches.length }
  emit('search', result)
  return result
}
function keyboard(event: KeyboardEvent) {
  if (event.type !== 'keydown' || event.isComposing) return true
  const key = event.key.toLowerCase()
  const command = event.ctrlKey || event.metaKey
  let action: SshTerminalShortcut | undefined
  if (command && key === 'f') action = 'search'
  else if (key === 'f11') action = 'fullscreen'
  else if (command && (key === '+' || key === '=')) action = 'increaseFont'
  else if (command && key === '-') action = 'decreaseFont'
  else if ((event.ctrlKey && key === 'insert') || (command && key === 'c' && !!getSelection())) action = 'copy'
  else if ((event.shiftKey && key === 'insert') || (event.ctrlKey && event.shiftKey && key === 'v')) action = 'paste'
  if (!action) return true // Ctrl+C without selection and Ctrl+L belong to the shell.
  event.preventDefault()
  event.stopPropagation()
  emit('shortcut', action)
  return false
}
function visibilityChanged() {
  if (document.visibilityState === 'visible') { fit(); scheduleWrite() }
}
function updateInput() {
  if (!terminal) return
  terminal.options.disableStdin = !props.active || !props.inputEnabled
  if (!props.active) terminal.blur()
  else { fit(); if (props.inputEnabled) focus() }
}
function updateLabel() {
  if (terminal?.textarea) terminal.textarea.setAttribute('aria-label', props.ariaLabel)
}
async function installWebLinks(active: LocalTerminal) {
  const WebLinksAddon = await loadTerminalWebLinks()
  // Resets construct a new terminal. A shared in-flight script must never
  // install its late result on a replaced or disposed instance.
  if (!WebLinksAddon || disposed || failed || terminal !== active) return
  let addon: TerminalDisposable | undefined
  try {
    addon = new WebLinksAddon((event, uri) => {
      if (!event.isTrusted || disposed || terminal !== active) return
      try {
        const url = new URL(uri)
        if (url.protocol === 'https:' || url.protocol === 'http:') window.open(url.href, '_blank', 'noopener,noreferrer')
      } catch { /* non-URL terminal output remains plain text */ }
    })
    active.loadAddon(addon)
  } catch {
    try { addon?.dispose() } catch { /* optional enhancement has no terminal error state */ }
  }
}
function createTerminal(dimensions?: SshTerminalDimensions) {
  if (!runtime || !host.value) return
  const previous = terminal
  terminal = undefined
  for (const listener of listeners) listener.dispose()
  listeners.length = 0
  previous?.dispose()
  host.value.replaceChildren()
  const active = new runtime.Terminal({
    ...(dimensions || {}),
    fontSize: effectiveFontSize(), fontFamily: getComputedStyle(host.value).getPropertyValue('--mono').trim()
      || 'SFMono-Regular, Menlo, Monaco, Consolas, monospace',
    scrollback: 5000, allowProposedApi: true, rendererType: 'canvas',
    cursorBlink: !reducedMotion?.matches, convertEol: false, allowTransparency: false,
    disableStdin: !props.active || !props.inputEnabled, logLevel: 'off',
    theme: terminalPalette(props.theme),
  })
  terminal = active
  fitAddon = new runtime.FitAddon()
  active.loadAddon(fitAddon)
  active.open(host.value)
  active.attachCustomKeyEventHandler(keyboard)
  listeners.push(active.onData((data) => {
    if (!disposed && terminal === active && props.active && props.inputEnabled && !failed) emit('data', data)
  }), active.onResize(() => {
    if (!disposed && terminal === active) { ++bufferVersion; publishDimensions() }
  }))
  updateTheme(); updateLabel(); fit(); publishDimensions()
  scheduleWrite()
  if (props.active && props.inputEnabled) focus()
  // Do not await optional URL handling: core readiness and PTY input are
  // independent of its download timeout. Reset instances install it as well.
  void installWebLinks(active)
}

watch(() => [props.active, props.inputEnabled], updateInput)
watch(() => [props.theme, props.fontSize, chromeRevision.value], updateTheme, { flush: 'post' })
watch(() => props.ariaLabel, updateLabel)
onMounted(async () => {
  try {
    runtime = await loadTerminalRuntime()
    if (disposed || !host.value) return
    reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')
    createTerminal()
    resizeObserver = new ResizeObserver(fit)
    resizeObserver.observe(host.value)
    themeObserver = new MutationObserver(updateTheme)
    themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-content-theme'] })
    reducedMotion.addEventListener('change', updateTheme)
    window.addEventListener('resize', fit)
    document.addEventListener('visibilitychange', visibilityChanged)
    if (!failed) emit('ready')
    void document.fonts?.ready.then(() => { if (!disposed) fit() })
  } catch { reportError(terminal ? 'renderFailed' : 'loadFailed') }
})
onBeforeUnmount(() => {
  disposed = true
  cancelAnimationFrame(fitFrame); cancelAnimationFrame(writeFrame)
  resizeObserver?.disconnect(); themeObserver?.disconnect()
  reducedMotion?.removeEventListener('change', updateTheme)
  window.removeEventListener('resize', fit)
  document.removeEventListener('visibilitychange', visibilityChanged)
  for (const listener of listeners) listener.dispose()
  terminal?.dispose()
  terminal = undefined; fitAddon = undefined
  pending = []; pendingIndex = 0; pendingBytes = 0; inFlightBytes = 0
})

defineExpose<SshTerminalCanvasHandle>({
  write, focus, fit, clear, reset, paste, getSelection, selectAll, clearSelection,
  getBufferText, search, getDimensions, scrollToBottom,
})
</script>

<template>
  <div ref="host" class="ssh-terminal-canvas" :aria-label="ariaLabel" />
</template>
