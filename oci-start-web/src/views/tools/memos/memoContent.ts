import DOMPurify from 'dompurify'

export interface MemoDocument { html: string; text: string }
export interface MemoImageLabels { load: string; blocked: string; failed: string }
export const MEMO_CONTENT_MAX_BYTES = 65535

const tags = ['p', 'br', 'div', 'h1', 'h2', 'h3', 'strong', 'b', 'em', 'i', 'u', 's', 'strike',
  'blockquote', 'pre', 'code', 'ul', 'ol', 'li', 'a', 'img']
const blockTags = new Set(['P', 'DIV', 'H1', 'H2', 'H3', 'BLOCKQUOTE', 'PRE', 'UL', 'OL', 'LI'])

/** Templates keep image and other resource nodes inert during parsing and cleaning. */
function template(html: string): HTMLTemplateElement {
  const node = document.createElement('template')
  node.innerHTML = html
  return node
}

export function memoUrl(value: string, image = false, allowEmbedded = false): string | null {
  if (value.includes('\\')) return null
  const candidate = value.trim()
  if (!candidate || /[\u0000-\u0020\u007f]/.test(candidate)) return null
  if (image && allowEmbedded && /^data:image\/(?:png|jpeg|gif|webp);base64,[A-Za-z0-9+/]+={0,2}$/i.test(candidate)) {
    return candidate
  }
  try {
    const url = new URL(candidate)
    if (!image && url.protocol === 'mailto:' && url.pathname) return url.href
    if (!['http:', 'https:'].includes(url.protocol) || !url.hostname || url.username || url.password || (image && url.hash)) return null
    return url.href
  } catch { return null }
}

export function sanitizeMemoHtml(html: string): string {
  const node = template(html)
  const wrapper = node.content.ownerDocument.createElement('div')
  wrapper.append(...Array.from(node.content.childNodes))
  node.content.append(wrapper)
  // Remove fetch attributes before the fragment is passed to a third-party DOM cleaner.
  wrapper.querySelectorAll('img').forEach(image => {
    image.setAttribute('data-memo-source', image.getAttribute('src') || '')
    image.removeAttribute('src'); image.removeAttribute('srcset')
  })
  DOMPurify.sanitize(wrapper, {
    IN_PLACE: true, ALLOWED_TAGS: tags, ALLOWED_ATTR: ['href', 'alt', 'title', 'data-memo-source'],
    ALLOW_DATA_ATTR: false, ALLOW_ARIA_ATTR: false,
  })
  wrapper.querySelectorAll('a').forEach(link => {
    const href = memoUrl(link.getAttribute('href') || '')
    if (!href) { link.replaceWith(...Array.from(link.childNodes)); return }
    link.setAttribute('href', href)
    link.setAttribute('target', '_blank'); link.setAttribute('rel', 'noopener noreferrer')
  })
  wrapper.querySelectorAll('img').forEach(image => {
    const src = memoUrl(image.getAttribute('data-memo-source') || '', true, true)
    if (!src) { image.replaceWith(node.ownerDocument.createTextNode(image.getAttribute('alt') || '')); return }
    image.setAttribute('src', src)
  })
  wrapper.querySelectorAll('[data-memo-source]').forEach(element => element.removeAttribute('data-memo-source'))
  return wrapper.innerHTML
}

export function memoText(html: string): string {
  const node = template(html)
  const parts: { value: string; synthetic: boolean }[] = []
  function text(value: string) { if (value) parts.push({ value, synthetic: false }) }
  function newline() {
    if (parts.length && !parts[parts.length - 1]?.value.endsWith('\n')) parts.push({ value: '\n', synthetic: true })
  }
  function visit(current: Node) {
    if (current.nodeType === Node.TEXT_NODE) { text(current.textContent || ''); return }
    if (!(current instanceof Element)) { current.childNodes.forEach(visit); return }
    if (current.tagName === 'BR') { text('\n'); return }
    if (current.tagName === 'IMG') { text(current.getAttribute('alt') || ''); return }
    const block = blockTags.has(current.tagName)
    if (block) newline()
    current.childNodes.forEach(visit)
    if (block) newline()
  }
  node.content.childNodes.forEach(visit)
  // Only discard our final block separator. User spaces, code indentation and BRs are real content.
  if (parts[parts.length - 1]?.synthetic) parts.pop()
  return parts.map(part => part.value).join('')
}

export function memoPlainHtml(text: string): string {
  const escaped = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  return escaped ? `<p>${escaped.replace(/\r\n?/g, '\n').replace(/\n/g, '<br>')}</p>` : ''
}

export function memoDocument(html: string | null | undefined, text: string): MemoDocument {
  const safe = sanitizeMemoHtml(html?.trim() ? html : memoPlainHtml(text))
  return { html: safe, text: memoText(safe) }
}

export function memoWithinLimit(value: MemoDocument): boolean {
  const encoder = new TextEncoder()
  return encoder.encode(value.html).length <= MEMO_CONTENT_MAX_BYTES && encoder.encode(value.text).length <= MEMO_CONTENT_MAX_BYTES
}

export function memoImageHtml(src: string, alt: string): string {
  const node = template('')
  const image = node.content.ownerDocument.createElement('img')
  image.setAttribute('src', src); image.setAttribute('alt', alt)
  node.content.append(image)
  return node.innerHTML
}

/** The only image DOM inserted into the page is an inert placeholder until a click. */
export function memoDisplayHtml(html: string | null | undefined, text: string, labels: MemoImageLabels): string {
  const node = template(memoDocument(html, text).html)
  node.content.querySelectorAll('img').forEach(image => {
    const holder = node.content.ownerDocument.createElement('span')
    holder.className = 'memo-image-placeholder'
    holder.setAttribute('contenteditable', 'false')
    holder.dataset.memoImage = image.getAttribute('src') || ''
    holder.dataset.memoAlt = image.getAttribute('alt') || ''
    if (image.hasAttribute('title')) holder.dataset.memoTitle = image.getAttribute('title') || ''
    holder.dataset.memoState = 'idle'
    const label = node.content.ownerDocument.createElement('span')
    label.dataset.memoImageLabel = 'true'
    label.textContent = image.getAttribute('alt') || labels.blocked
    const button = node.content.ownerDocument.createElement('button')
    button.type = 'button'; button.textContent = labels.load
    holder.append(label, button)
    image.replaceWith(holder)
  })
  return node.innerHTML
}

function writeMemoImageLabels(holder: HTMLElement, labels: MemoImageLabels) {
  const label = holder.querySelector<HTMLElement>('[data-memo-image-label]')
  if (label && !holder.dataset.memoAlt) {
    if (label.textContent !== labels.blocked) label.textContent = labels.blocked
    label.hidden = holder.dataset.memoState === 'loaded'
  }
  const button = holder.querySelector<HTMLButtonElement>('button')
  const text = holder.dataset.memoState === 'failed' ? labels.failed : labels.load
  if (button && button.textContent !== text) button.textContent = text
}

/** Localized preview controls can change without replacing editable nodes or touching undo history. */
export function updateMemoImageLabels(root: HTMLElement, labels: MemoImageLabels): void {
  root.querySelectorAll<HTMLElement>('.memo-image-placeholder[data-memo-image]').forEach(holder => writeMemoImageLabels(holder, labels))
}

/** UI labels, preview controls and loaded image state never enter the saved HTML. */
export function memoFromEditor(element: HTMLElement): MemoDocument {
  const node = template(element.innerHTML)
  node.content.querySelectorAll<HTMLElement>('[data-memo-image]').forEach(holder => {
    const src = memoUrl(holder.dataset.memoImage || '', true, true)
    if (!src) { holder.remove(); return }
    const image = node.content.ownerDocument.createElement('img')
    image.setAttribute('src', src); image.setAttribute('alt', holder.dataset.memoAlt || '')
    if (holder.hasAttribute('data-memo-title')) image.setAttribute('title', holder.dataset.memoTitle || '')
    holder.replaceWith(image)
  })
  return memoDocument(node.innerHTML, '')
}

export function loadMemoImage(event: MouseEvent, root: HTMLElement, labels: () => MemoImageLabels): boolean {
  if (!(event.target instanceof Element)) return false
  const button = event.target.closest<HTMLButtonElement>('.memo-image-placeholder > button')
  const holder = button?.parentElement
  if (!button || !holder || !root.contains(holder)) return false
  event.preventDefault(); event.stopPropagation()
  const src = memoUrl(holder.dataset.memoImage || '', true, true)
  if (!src || button.disabled) return true
  button.disabled = true
  holder.dataset.memoState = 'loading'
  writeMemoImageLabels(holder, labels())
  const image = document.createElement('img')
  image.alt = holder.dataset.memoAlt || ''
  if (holder.hasAttribute('data-memo-title')) image.title = holder.dataset.memoTitle || ''
  image.referrerPolicy = 'no-referrer'
  image.onload = () => {
    if (root.contains(holder)) {
      holder.dataset.memoState = 'loaded'; holder.append(image); button.remove(); writeMemoImageLabels(holder, labels())
    }
  }
  image.onerror = () => {
    if (root.contains(holder)) {
      holder.dataset.memoState = 'failed'; button.disabled = false; writeMemoImageLabels(holder, labels())
    }
  }
  // This assignment is deliberately reachable only from the user's preview click.
  image.src = src
  return true
}
