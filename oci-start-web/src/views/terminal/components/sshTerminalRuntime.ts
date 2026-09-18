import type { TerminalRuntime, TerminalWebLinksConstructor } from './sshTerminalTypes'

type RuntimeWindow = Window & {
  Terminal?: TerminalRuntime['Terminal']
  FitAddon?: { FitAddon?: TerminalRuntime['FitAddon'] }
  WebLinksAddon?: { WebLinksAddon?: TerminalWebLinksConstructor }
}
const scripts = new Map<string, Promise<void>>()
let loading: Promise<TerminalRuntime> | undefined

function loadScript(path: string): Promise<void> {
  const existing = scripts.get(path)
  if (existing) return existing
  const promise = new Promise<void>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = path
    script.async = true
    const timer = setTimeout(() => finish(false), 15000)
    function finish(success: boolean) {
      clearTimeout(timer)
      script.onload = script.onerror = null
      if (success) resolve()
      else { script.remove(); scripts.delete(path); reject(new Error('terminalRuntimeUnavailable')) }
    }
    script.onload = () => finish(true)
    script.onerror = () => finish(false)
    document.head.appendChild(script)
  })
  scripts.set(path, promise)
  return promise
}

/**
 * Reuse the repository's local 4.x UMD core and its matching actualCellWidth fit
 * addon. The legacy CSS URL names 4.19.0, but the minified assets contain no
 * package version metadata. Its newer WebGL bundle uses dimensions.device.cell
 * and is deliberately excluded. No CDN, inline legacy page, eval or install.
 */
export function loadTerminalRuntime(): Promise<TerminalRuntime> {
  if (loading) return loading
  loading = (async () => {
    const global = window as RuntimeWindow
    if (typeof global.Terminal !== 'function') await loadScript('/js/xterm.js')
    if (typeof global.FitAddon?.FitAddon !== 'function') await loadScript('/js/xterm-addon-fit.js')
    if (typeof global.Terminal !== 'function' || typeof global.FitAddon?.FitAddon !== 'function') {
      throw new Error('terminalRuntimeUnavailable')
    }
    return { Terminal: global.Terminal, FitAddon: global.FitAddon.FitAddon }
  })().catch((cause) => { loading = undefined; throw cause })
  return loading
}

/** Optional enhancement, requested separately after the core terminal is ready. */
export async function loadTerminalWebLinks(): Promise<TerminalWebLinksConstructor | undefined> {
  const global = window as RuntimeWindow
  try {
    if (typeof global.WebLinksAddon?.WebLinksAddon !== 'function') {
      await loadScript('/js/xterm-addon-web-links.js')
    }
    return typeof global.WebLinksAddon?.WebLinksAddon === 'function' ? global.WebLinksAddon.WebLinksAddon : undefined
  } catch { return undefined }
}
