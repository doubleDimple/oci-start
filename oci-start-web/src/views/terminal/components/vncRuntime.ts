import type { RfbConstructor } from './vncTypes'

// This is the exact pinned ESM source already used by console_terminal.ftl.
// The repository has no vendored noVNC engine. Loading happens only when the
// user prepares/opens a console; no legacy HTML or iframe is loaded.
const moduleUrl = 'https://cdn.jsdelivr.net/npm/@novnc/novnc@1.4.0/core/rfb.js'
const LOAD_TIMEOUT_MS = 30_000
let runtime: Promise<RfbConstructor> | undefined

export function loadVncRuntime(): Promise<RfbConstructor> {
  if (runtime) return runtime
  let timer: ReturnType<typeof setTimeout> | undefined
  const imported = import(/* @vite-ignore */ moduleUrl).then((module: { default?: unknown }) => {
    const constructor = module.default
    if (typeof constructor !== 'function') throw new Error('vncRuntimeUnavailable')
    const prototype = constructor.prototype as Record<string, unknown> | undefined
    if (!prototype || ['disconnect', 'focus', 'blur', 'sendCredentials', 'sendCtrlAltDel', 'sendKey', 'clipboardPasteFrom']
      .some(method => typeof prototype[method] !== 'function')) throw new Error('vncRuntimeUnavailable')
    return constructor as RfbConstructor
  })
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error('vncRuntimeUnavailable')), LOAD_TIMEOUT_MS)
  })
  runtime = Promise.race([imported, deadline]).catch((cause) => {
    // Release this loader's failure. The browser keeps its own ESM cache, so a
    // failed dependency may still require a page reload before preparing again.
    runtime = undefined
    throw cause
  }).finally(() => { if (timer) clearTimeout(timer) })
  return runtime
}
