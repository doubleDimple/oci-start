<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { Marked } from 'marked'
import DOMPurify from 'dompurify'
import hljs from 'highlight.js/lib/common'

const props = defineProps<{ content: string; streaming?: boolean }>()
const emit = defineEmits<{ copy: [text: string] }>()
const { t } = useI18n()
const markdown = new Marked({ gfm: true, breaks: true })

function safeUrl(value: string, image = false): string | null {
  if (!value.trim()) return null
  try {
    const url = new URL(value, window.location.href)
    if (!['http:', 'https:', ...(image ? [] : ['mailto:'])].includes(url.protocol)) return null
    // A generated image must not silently invoke a same-origin GET action.
    if (image && url.origin === window.location.origin) return null
    return url.href
  } catch { return null }
}

const html = computed(() => {
  let parsed: string
  try { parsed = markdown.parse(props.content, { async: false }) }
  catch { return props.content.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>') }
  const fragment = DOMPurify.sanitize(parsed, {
    RETURN_DOM_FRAGMENT: true,
    ALLOW_DATA_ATTR: false,
    ALLOWED_TAGS: ['p', 'br', 'strong', 'em', 'del', 's', 'blockquote', 'ul', 'ol', 'li', 'pre', 'code', 'span',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'table', 'thead', 'tbody', 'tr', 'th', 'td', 'a', 'img', 'input', 'sup', 'sub'],
    ALLOWED_ATTR: ['href', 'title', 'class', 'src', 'alt', 'start', 'align', 'type', 'checked', 'disabled'],
  })
  fragment.querySelectorAll('a').forEach((link) => {
    const href = safeUrl(link.getAttribute('href') || '')
    if (!href) { link.replaceWith(document.createTextNode(link.textContent || '')); return }
    link.href = href
    link.target = '_blank'
    link.rel = 'noopener noreferrer'
  })
  fragment.querySelectorAll('img').forEach((img) => {
    const src = safeUrl(img.getAttribute('src') || '', true)
    if (!src) { img.replaceWith(document.createTextNode(img.alt)); return }
    img.src = src
    img.loading = 'lazy'
    img.referrerPolicy = 'no-referrer'
  })
  fragment.querySelectorAll('input').forEach((input) => {
    if (input.type !== 'checkbox') { input.remove(); return }
    input.disabled = true
    input.tabIndex = -1
  })
  // Markdown HTML cannot supply our controls or inject application CSS classes.
  fragment.querySelectorAll('[class]').forEach((element) => {
    const language = element.tagName === 'CODE' ? element.className.match(/(?:^|\s)language-([\w#+.-]+)/)?.[1] : ''
    element.removeAttribute('class')
    if (language) element.className = `language-${language}`
  })
  fragment.querySelectorAll('pre > code').forEach((code) => {
    const pre = code.parentElement!
    const language = code.className.match(/language-([\w#+.-]+)/)?.[1] || ''
    const value = code.textContent || ''
    if (!props.streaming && value.length <= 40000) {
      try {
        if (language && hljs.getLanguage(language)) code.innerHTML = hljs.highlight(value, { language, ignoreIllegals: true }).value
        else code.innerHTML = hljs.highlightAuto(value).value
      } catch { code.textContent = value }
    }
    code.className = 'hljs'
    const wrapper = document.createElement('div')
    wrapper.className = 'chat-code-block'
    const header = document.createElement('div')
    header.className = 'chat-code-header'
    const label = document.createElement('span')
    label.textContent = language || t('aiChat.code')
    const button = document.createElement('button')
    button.type = 'button'
    button.dataset.chatCopy = 'true'
    button.textContent = t('aiChat.copyCode')
    button.setAttribute('aria-label', t('aiChat.copyCode'))
    header.append(label, button)
    pre.replaceWith(wrapper)
    wrapper.append(header, pre)
  })
  fragment.querySelectorAll('table').forEach((table) => {
    const wrapper = document.createElement('div')
    wrapper.className = 'chat-markdown-table'
    wrapper.tabIndex = 0
    table.replaceWith(wrapper)
    wrapper.append(table)
  })
  const container = document.createElement('div')
  container.append(fragment)
  return container.innerHTML
})

function handleClick(event: MouseEvent) {
  const target = event.target
  if (!(target instanceof Element)) return
  const button = target.closest<HTMLButtonElement>('button[data-chat-copy]')
  if (!button) return
  const code = button.closest('.chat-code-block')?.querySelector('pre > code')
  if (code) emit('copy', code.textContent || '')
}
</script>

<template><div class="chat-markdown" @click="handleClick" v-html="html" /></template>

<style scoped>
.chat-markdown { min-width: 0; color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); line-height: 1.7; overflow-wrap: anywhere; }
.chat-markdown :deep(p) { margin: 0 0 12px; }
.chat-markdown :deep(p:last-child) { margin-bottom: 0; }
.chat-markdown :deep(h1), .chat-markdown :deep(h2), .chat-markdown :deep(h3), .chat-markdown :deep(h4), .chat-markdown :deep(h5), .chat-markdown :deep(h6) { margin: 20px 0 10px; color: var(--text-primary); font-size: var(--font-size-section); font-weight: 600; line-height: 1.5; }
.chat-markdown :deep(h1:first-child), .chat-markdown :deep(h2:first-child), .chat-markdown :deep(h3:first-child) { margin-top: 0; }
.chat-markdown :deep(a) { color: var(--text-primary); text-decoration: underline; text-underline-offset: 3px; }
.chat-markdown :deep(ul), .chat-markdown :deep(ol) { padding-left: 24px; margin: 10px 0; }
.chat-markdown :deep(li) { margin: 4px 0; }
.chat-markdown :deep(blockquote) { margin: 12px 0; padding: 6px 14px; border-left: 3px solid var(--brand); color: var(--text-secondary); }
.chat-markdown :deep(hr) { margin: 18px 0; border: 0; border-top: 1px solid var(--border); }
.chat-markdown :deep(img) { display: block; max-width: 100%; max-height: 480px; height: auto; margin: 12px 0; border-radius: var(--r-sm); object-fit: contain; }
.chat-markdown :deep(code) { padding: 2px 5px; border-radius: 5px; background: var(--bg-search); color: var(--text-primary); font: var(--font-size-body)/1.6 var(--mono); }
.chat-markdown :deep(.chat-code-block) { margin: 14px 0; border: 1px solid var(--border); border-radius: 12px; overflow: hidden; background: var(--bg-search); }
.chat-markdown :deep(.chat-code-header) { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 8px 12px; border-bottom: 1px solid var(--border); color: var(--text-secondary); font-size: var(--font-size-caption); }
.chat-markdown :deep(.chat-code-header button) { padding: 3px 5px; border: 0; border-radius: 5px; background: transparent; color: var(--text-secondary); font: var(--font-size-body)/1.47 var(--sans); cursor: pointer; }
.chat-markdown :deep(.chat-code-header button:hover) { color: var(--brand); }
.chat-markdown :deep(.chat-code-header button:focus-visible), .chat-markdown :deep(.chat-markdown-table:focus-visible) { outline: 2px solid var(--brand); outline-offset: -2px; }
.chat-markdown :deep(pre) { max-width: 100%; overflow: auto; margin: 0; padding: 14px; white-space: pre; }
.chat-markdown :deep(pre code) { display: block; padding: 0; background: transparent; font-size: var(--font-size-body); }
.chat-markdown :deep(.chat-markdown-table) { max-width: 100%; margin: 14px 0; overflow: auto; border: 1px solid var(--border); border-radius: var(--r-sm); }
.chat-markdown :deep(table) { min-width: 100%; border-collapse: collapse; color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
.chat-markdown :deep(th), .chat-markdown :deep(td) { padding: 10px 12px; border-bottom: 1px solid var(--border); text-align: left; vertical-align: top; }
.chat-markdown :deep(th) { color: var(--text-secondary); font-weight: 600; background: var(--bg-search); }
.chat-markdown :deep(tr:last-child td) { border-bottom: 0; }
.chat-markdown :deep(.hljs-comment), .chat-markdown :deep(.hljs-quote) { color: var(--text-secondary); }
.chat-markdown :deep(.hljs-keyword), .chat-markdown :deep(.hljs-selector-tag), .chat-markdown :deep(.hljs-name), .chat-markdown :deep(.hljs-title), .chat-markdown :deep(.hljs-section) { color: var(--brand); }
.chat-markdown :deep(.hljs-string), .chat-markdown :deep(.hljs-attr), .chat-markdown :deep(.hljs-symbol), .chat-markdown :deep(.hljs-template-tag) { color: var(--status-warn); }
.chat-markdown :deep(.hljs-number), .chat-markdown :deep(.hljs-literal), .chat-markdown :deep(.hljs-built_in), .chat-markdown :deep(.hljs-type) { color: var(--status-info); }
.chat-markdown :deep(.hljs-addition) { background: var(--status-ok-bg); color: var(--status-ok); }
.chat-markdown :deep(.hljs-deletion) { background: var(--status-danger-bg); color: var(--status-danger); }
.chat-markdown :deep(.hljs-emphasis) { font-style: italic; }
.chat-markdown :deep(.hljs-strong) { font-weight: 600; }
</style>
