<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { loadMemoImage, memoDisplayHtml, memoDocument, memoFromEditor, memoImageHtml,
  memoUrl, memoWithinLimit, updateMemoImageLabels, type MemoDocument } from './memoContent'

const props = withDefaults(defineProps<{ value: MemoDocument; disabled?: boolean }>(), { disabled: false })
const emit = defineEmits<{ 'update:value': [value: MemoDocument]; 'entry-change': [open: boolean] }>()
const { t } = useI18n()
const body = ref<HTMLElement>(), urlInput = ref<HTMLInputElement>()
const entry = ref<'link' | 'image' | null>(null), url = ref(''), alt = ref(''), problem = ref('')
const composing = ref(false), format = ref('p')
const pressed = reactive<Record<string, boolean>>({})
const commands = [
  { key: 'bold', command: 'bold', icon: 'i-mdi-format-bold' },
  { key: 'italic', command: 'italic', icon: 'i-mdi-format-italic' },
  { key: 'underline', command: 'underline', icon: 'i-mdi-format-underline' },
  { key: 'strike', command: 'strikeThrough', icon: 'i-mdi-format-strikethrough' },
  { key: 'bulletList', command: 'insertUnorderedList', icon: 'i-mdi-format-list-bulleted' },
  { key: 'orderedList', command: 'insertOrderedList', icon: 'i-mdi-format-list-numbered' },
  { key: 'outdent', command: 'outdent', icon: 'i-mdi-format-indent-decrease' },
  { key: 'indent', command: 'indent', icon: 'i-mdi-format-indent-increase' },
]
const labels = computed(() => ({ load: t('memo.editor.loadImage'), blocked: t('memo.editor.imageBlocked'), failed: t('memo.editor.imageFailed') }))
const locked = computed(() => props.disabled || composing.value || !!entry.value)
let selection: Range | null = null
let formatSelection: Range | null = null
let formatOpen = false, documentRevision = 0, formatRevision = 0
let emittedHtml: string | null = null
let deferredValue: MemoDocument | null = null
let disposed = false

function captureSelection() {
  const current = window.getSelection()
  if (!body.value || !current?.rangeCount) return
  const range = current.getRangeAt(0)
  if (!body.value.contains(range.commonAncestorContainer)) return
  selection = range.cloneRange()
  if (composing.value) return
  for (const item of commands) {
    try { pressed[item.command] = document.queryCommandState(item.command) } catch { pressed[item.command] = false }
  }
  try {
    const currentFormat = String(document.queryCommandValue('formatBlock')).toLowerCase().replace(/[<>]/g, '')
    format.value = ['h1', 'h2', 'h3', 'blockquote', 'pre'].includes(currentFormat) ? currentFormat : 'p'
  } catch { format.value = 'p' }
}
function restoreSelection() {
  const element = body.value
  if (!element) return false
  element.focus({ preventScroll: true })
  const current = window.getSelection()
  if (!current) return false
  if (!selection || !element.contains(selection.commonAncestorContainer)) {
    selection = document.createRange(); selection.selectNodeContents(element); selection.collapse(false)
  }
  current.removeAllRanges(); current.addRange(selection)
  return true
}
function publish() {
  if (!body.value || composing.value || disposed) return
  const value = memoFromEditor(body.value)
  problem.value = memoWithinLimit(value) ? '' : 'contentTooLarge'
  emittedHtml = value.html
  emit('update:value', value)
  // Native undo can restore an older placeholder label; update only its presentation text.
  updateMemoImageLabels(body.value, labels.value)
  captureSelection()
}
function command(name: string, value?: string) {
  if (locked.value || !restoreSelection()) return
  try {
    document.execCommand('styleWithCSS', false, 'false')
    document.execCommand(name, false, value)
    publish()
  } catch { problem.value = 'pasteRejected' }
}
function captureFormatSelection() {
  if (locked.value || formatOpen) return
  captureSelection()
  formatSelection = selection?.cloneRange() ?? null
  formatRevision = documentRevision
}
function formatVisibility(open: boolean) {
  if (open) captureFormatSelection()
  formatOpen = open
}
async function changeFormat(value: unknown) {
  if (typeof value !== 'string' || !['p', 'h2', 'h3', 'blockquote', 'pre'].includes(value) || locked.value) return
  const saved = formatSelection?.cloneRange() ?? selection?.cloneRange() ?? null
  const revision = formatRevision
  // ElSelect focuses its own input after emitting change. Restore the saved
  // editor range after that synchronous focus, including teleported options.
  await nextTick()
  if (disposed || locked.value || revision !== documentRevision || !body.value) return
  if (saved && !body.value.contains(saved.commonAncestorContainer)) return
  selection = saved
  command('formatBlock', value)
  formatSelection = null
}
function insertHtml(html: string) {
  if (!restoreSelection()) return
  try {
    document.execCommand('insertHTML', false, html)
    publish()
  } catch { problem.value = 'pasteRejected' }
}
function paste(event: ClipboardEvent) {
  event.preventDefault()
  if (locked.value || !event.clipboardData) return
  const plain = event.clipboardData.getData('text/plain')
  const rich = event.clipboardData.getData('text/html')
  if ((!plain && !rich) || rich.length > 262140 || plain.length > 65535) { problem.value = 'pasteRejected'; return }
  const value = memoDocument(rich, plain)
  if (!memoWithinLimit(value)) { problem.value = 'contentTooLarge'; return }
  insertHtml(memoDisplayHtml(value.html, value.text, labels.value))
}
function drop(event: DragEvent) { event.preventDefault(); if (!props.disabled) problem.value = 'pasteRejected' }
function editorKeydown(event: KeyboardEvent) {
  // The owning page prevents the default line break when it handles its save shortcut.
  if ((event.isComposing || composing.value) && (event.ctrlKey || event.metaKey) && event.key === 'Enter') event.stopPropagation()
}
function compositionEnd() {
  composing.value = false
  if (deferredValue) { const value = deferredValue; deferredValue = null; hydrate(value) }
  else publish()
}
async function openEntry(kind: 'link' | 'image') {
  if (locked.value) return
  captureSelection(); entry.value = kind; url.value = ''; alt.value = ''; problem.value = ''
  await nextTick()
  if (!disposed) urlInput.value?.focus()
}
async function cancelEntry() {
  if (props.disabled) return
  entry.value = null; url.value = ''; alt.value = ''; problem.value = ''
  await nextTick()
  if (!disposed && !props.disabled) restoreSelection()
}
async function applyEntry() {
  if (props.disabled || !entry.value) return
  const kind = entry.value
  const href = memoUrl(url.value, kind === 'image')
  if (!href) { problem.value = 'invalidUrl'; return }
  const description = alt.value.trim()
  entry.value = null
  url.value = ''; alt.value = ''
  // Wait until Vue has restored contenteditable before invoking a browser edit command.
  await nextTick()
  if (disposed || props.disabled || !restoreSelection()) return
  if (kind === 'image') {
    const html = memoImageHtml(href, description)
    insertHtml(memoDisplayHtml(html, '', labels.value))
  } else if (selection?.collapsed) {
    const node = document.createElement('a')
    node.href = href; node.textContent = href; node.target = '_blank'; node.rel = 'noopener noreferrer'
    insertHtml(node.outerHTML)
  } else command('createLink', href)
}
function entryKeydown(event: KeyboardEvent) {
  if (event.isComposing) return
  if (event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); void applyEntry() }
  else if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); void cancelEntry() }
}
function clickContent(event: MouseEvent) {
  if (!body.value) return
  if (loadMemoImage(event, body.value, () => labels.value)) return
  // An editing gesture must not navigate away from an unsaved memo.
  if (event.target instanceof Element && event.target.closest('a')) event.preventDefault()
}
function toolbarKeydown(event: KeyboardEvent) {
  if (event.key === 'Enter') event.stopPropagation()
  if (!(event.target instanceof HTMLButtonElement) || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
  const toolbar = event.currentTarget as HTMLElement
  const items = Array.from(toolbar.querySelectorAll<HTMLButtonElement>('button:not(:disabled)'))
  const index = items.indexOf(event.target)
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1
    : (index + (event.key === 'ArrowLeft' ? -1 : 1) + items.length) % items.length
  event.preventDefault(); items[next]?.focus()
}
function hydrate(value: MemoDocument) {
  if (!body.value || composing.value) return
  body.value.innerHTML = memoDisplayHtml(value.html, value.text, labels.value)
  ++documentRevision; selection = null; formatSelection = null; problem.value = ''; emittedHtml = null
}
watch(() => [props.value.html, props.value.text] as const, () => {
  if (props.value.html === emittedHtml) return
  if (composing.value) { deferredValue = { ...props.value }; return }
  hydrate(props.value)
})
watch(() => props.disabled, disabled => { if (disabled) { entry.value = null; url.value = ''; alt.value = '' } })
watch(() => !!entry.value, open => emit('entry-change', open), { flush: 'sync', immediate: true })
watch(labels, value => { if (body.value) updateMemoImageLabels(body.value, value) }, { flush: 'post' })
onMounted(() => { hydrate(props.value); document.addEventListener('selectionchange', captureSelection) })
onBeforeUnmount(() => { disposed = true; selection = null; formatSelection = null; deferredValue = null; emit('entry-change', false); document.removeEventListener('selectionchange', captureSelection) })
</script>

<template>
  <div class="memo-rich-editor" :class="{ 'is-disabled': disabled }">
    <div class="memo-editor-toolbar" role="toolbar" :aria-label="t('memo.editor.toolbar')" @keydown="toolbarKeydown">
      <el-select :model-value="format" class="memo-format-select" :disabled="locked" :aria-label="t('memo.editor.toolbar')"
        @pointerdown.capture="captureFormatSelection" @focus="captureFormatSelection" @visible-change="formatVisibility" @change="changeFormat">
        <el-option v-if="format === 'h1'" value="h1" disabled :label="t('memo.editor.heading2')" />
        <el-option value="p" :label="t('memo.editor.paragraph')" /><el-option value="h2" :label="t('memo.editor.heading2')" />
        <el-option value="h3" :label="t('memo.editor.heading3')" /><el-option value="blockquote" :label="t('memo.editor.quote')" /><el-option value="pre" :label="t('memo.editor.code')" />
      </el-select>
      <button v-for="item in commands" :key="item.key" type="button" :disabled="locked" :class="{ 'is-active': pressed[item.command] }"
        :title="t(`memo.editor.${item.key}`)" :aria-label="t(`memo.editor.${item.key}`)" :aria-pressed="['indent', 'outdent'].includes(item.command) ? undefined : !!pressed[item.command]"
        @mousedown.prevent @click="command(item.command)"><i :class="item.icon" aria-hidden="true" /></button>
      <span class="memo-toolbar-separator" aria-hidden="true" />
      <button type="button" :disabled="locked" :title="t('memo.editor.link')" :aria-label="t('memo.editor.link')" @mousedown.prevent @click="openEntry('link')"><i class="i-mdi-link-variant" aria-hidden="true" /></button>
      <button type="button" :disabled="locked" :title="t('memo.editor.image')" :aria-label="t('memo.editor.image')" @mousedown.prevent @click="openEntry('image')"><i class="i-mdi-image-outline" aria-hidden="true" /></button>
      <button type="button" :disabled="locked" :title="t('memo.editor.removeFormat')" :aria-label="t('memo.editor.removeFormat')" @mousedown.prevent @click="command('removeFormat')"><i class="i-mdi-format-clear" aria-hidden="true" /></button>
      <button type="button" :disabled="locked" :title="t('memo.editor.undo')" :aria-label="t('memo.editor.undo')" @mousedown.prevent @click="command('undo')"><i class="i-mdi-undo" aria-hidden="true" /></button>
      <button type="button" :disabled="locked" :title="t('memo.editor.redo')" :aria-label="t('memo.editor.redo')" @mousedown.prevent @click="command('redo')"><i class="i-mdi-redo" aria-hidden="true" /></button>
    </div>
    <div v-if="entry" class="memo-editor-entry" @keydown="entryKeydown">
      <label>{{ t(entry === 'link' ? 'memo.editor.linkUrl' : 'memo.editor.imageUrl') }}<input ref="urlInput" v-model="url" type="url" :disabled="disabled" autocomplete="off" autocapitalize="off" :spellcheck="false" placeholder="https://" maxlength="4096" /></label>
      <label v-if="entry === 'image'">{{ t('memo.editor.imageAlt') }}<input v-model="alt" type="text" :disabled="disabled" autocomplete="off" maxlength="500" /></label>
      <small>{{ t(entry === 'link' ? 'memo.editor.linkHint' : 'memo.editor.imageHint') }}</small>
      <div><button type="button" :disabled="disabled" @click="cancelEntry">{{ t('memo.editor.cancel') }}</button><button type="button" :disabled="disabled" @click="applyEntry">{{ t('memo.editor.apply') }}</button></div>
    </div>
    <div ref="body" class="memo-editor-body" :contenteditable="!disabled && !entry" role="textbox" aria-multiline="true" :aria-label="t('memo.editor.label')"
      :aria-disabled="disabled || !!entry" :data-placeholder="t('memo.editor.placeholder')" :spellcheck="true"
      @input="publish" @compositionstart="composing = true" @compositionend="compositionEnd"
      @paste="paste" @drop="drop" @dragover.prevent @keydown="editorKeydown" @click="clickContent" />
    <p v-if="problem" class="memo-editor-problem" role="alert">{{ t(`memo.editor.${problem}`) }}</p>
  </div>
</template>

<style scoped>
.memo-rich-editor { min-width: 0; color: var(--text-primary); font: 400 var(--font-size-body)/1.65 var(--sans); border: 1px solid var(--border-strong); border-radius: 8px; overflow: hidden; background: var(--bg-card); }
.memo-editor-toolbar { display: flex; align-items: center; flex-wrap: wrap; gap: 3px; padding: 7px; border-bottom: 1px solid var(--border); background: var(--bg-search); }
.memo-editor-toolbar button, .memo-editor-entry button { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; min-height: 32px; border: 0; border-radius: 5px; background: transparent; color: var(--text-primary); font: inherit; cursor: pointer; }
.memo-editor-toolbar button:hover:not(:disabled), .memo-editor-toolbar button.is-active, .memo-editor-entry button:hover:not(:disabled) { background: var(--bg-hover); }
.memo-editor-toolbar button.is-active { box-shadow: inset 0 -2px var(--brand); }
.memo-editor-toolbar i { display: block; width: 18px; height: 18px; }
.memo-format-select { flex: none; width: 150px; min-width: 0; margin-right: 4px; }
.memo-toolbar-separator { width: 1px; height: 18px; background: var(--border-strong); margin: 0 4px; }
.memo-editor-toolbar :disabled, .memo-editor-entry :disabled { opacity: .5; cursor: default; }
.memo-editor-toolbar :focus-visible, .memo-editor-entry :focus-visible { outline: 2px solid var(--brand); outline-offset: -2px; }
.memo-editor-entry { display: grid; gap: 10px; padding: 12px; border-bottom: 1px solid var(--border); }
.memo-editor-entry label { display: grid; gap: 5px; min-width: 0; font-size: var(--font-size-body); }
.memo-editor-entry input { min-width: 0; height: 36px; box-sizing: border-box; padding: 6px 9px; border: 1px solid var(--border-strong); border-radius: 5px; background: var(--bg-card); color: var(--text-primary); font: inherit; }
.memo-editor-entry small { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.memo-editor-entry > div { display: flex; gap: 8px; justify-content: flex-end; }
.memo-editor-entry button { padding: 5px 12px; border: 1px solid var(--border-strong); }
.memo-editor-body { min-height: 240px; max-height: 65vh; overflow: auto; padding: 16px; outline: none; overflow-wrap: anywhere; white-space: pre-wrap; }
.memo-editor-body:focus { box-shadow: inset 0 0 0 2px var(--brand); }
.memo-editor-body:empty::before { content: attr(data-placeholder); color: var(--text-muted); pointer-events: none; }
.is-disabled .memo-editor-body { background: var(--bg-search); }
.memo-editor-problem { margin: 0; padding: 10px 14px; border-top: 1px solid var(--border); color: var(--status-danger); font-size: var(--font-size-secondary); }
.memo-editor-body :deep(p), .memo-editor-body :deep(div) { margin: 0 0 10px; }
.memo-editor-body :deep(h1), .memo-editor-body :deep(h2) { font: 600 var(--font-size-dialog-title)/1.5 var(--sans); margin: 18px 0 10px; }
.memo-editor-body :deep(h3) { font: 600 var(--font-size-section)/1.5 var(--sans); margin: 16px 0 8px; }
.memo-editor-body :deep(blockquote) { margin: 12px 0; padding: 4px 14px; border-left: 3px solid var(--border-strong); color: var(--text-primary); }
.memo-editor-body :deep(pre) { padding: 12px; background: var(--bg-search); white-space: pre-wrap; border-radius: 5px; }
.memo-editor-body :deep(code), .memo-editor-body :deep(pre) { font: 400 var(--font-size-body)/1.65 var(--mono); }
.memo-editor-body :deep(ul), .memo-editor-body :deep(ol) { padding-left: 24px; margin: 10px 0; }
.memo-editor-body :deep(a) { color: var(--text-primary); text-decoration: underline; text-underline-offset: 3px; }
.memo-editor-body :deep(.memo-image-placeholder) { display: inline-flex; flex-wrap: wrap; align-items: center; gap: 8px; max-width: 100%; padding: 8px 10px; margin: 8px 0; border: 1px dashed var(--border-strong); border-radius: 5px; color: var(--text-secondary); font: 400 var(--font-size-secondary)/1.6 var(--sans); }
.memo-editor-body :deep(.memo-image-placeholder button) { padding: 4px 8px; border: 1px solid var(--border-strong); border-radius: 5px; background: var(--bg-card); color: var(--text-primary); font: inherit; cursor: pointer; }
.memo-editor-body :deep(.memo-image-placeholder button:focus-visible) { outline: 2px solid var(--brand); outline-offset: 2px; }
.memo-editor-body :deep(img) { display: block; max-width: 100%; max-height: 420px; object-fit: contain; }
@media (max-width: 600px) { .memo-editor-body { padding: 12px; min-height: 220px; } .memo-editor-toolbar { gap: 2px; } }
</style>
