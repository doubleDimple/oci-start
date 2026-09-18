import { reactive, ref } from 'vue'
import type { ThemeName } from './useTheme'

const STORAGE_KEY = 'oci_chrome_colors'

export const SIDEBAR_SWATCHES = ['#1d1d1f', '#000000', '#0d4d3f', '#16324a', '#3d2314']
export const PAGE_SWATCHES = ['#f5f5f7', '#ffffff', '#eef1f4', '#f7f3ea', '#000000']

type ChromePair = { sidebar: string; page: string }
type ChromeStore = Record<ThemeName, ChromePair>

const EMPTY: ChromePair = { sidebar: '', page: '' }
let sessionStore: ChromeStore | undefined

export const chrome = reactive({
  sidebar: '',
  page: '',
})

// Canvas charts need an explicit repaint after the document's CSS palette changes.
export const chromeRevision = ref(0)

function blankStore(): ChromeStore {
  return { light: { ...EMPTY }, dark: { ...EMPTY } }
}

function readStore(): ChromeStore {
  if (sessionStore) return sessionStore
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return (sessionStore = blankStore())
    const parsed = JSON.parse(raw) as Partial<ChromeStore> | null
    sessionStore = {
      light: { sidebar: norm(parsed?.light?.sidebar), page: norm(parsed?.light?.page) },
      dark: { sidebar: norm(parsed?.dark?.sidebar), page: norm(parsed?.dark?.page) },
    }
    return sessionStore
  } catch {
    return (sessionStore = blankStore())
  }
}

function writeStore(store: ChromeStore) {
  // Preferences still apply for this session if browser storage is unavailable.
  sessionStore = store
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store))
  } catch {
    /* ignore */
  }
}

function hexToRgb(hex: string) {
  const n = hex.replace('#', '')
  if (!/^[\da-f]{6}$/i.test(n)) return null
  return {
    r: parseInt(n.slice(0, 2), 16) / 255,
    g: parseInt(n.slice(2, 4), 16) / 255,
    b: parseInt(n.slice(4, 6), 16) / 255,
  }
}

function isLightColor(hex: string) {
  const rgb = hexToRgb(hex)
  if (!rgb) return false
  const linear = (channel: number) => channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
  const luminance = 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
  // Select the palette whose foreground contrasts best with the chosen page color.
  return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
}

function setVar(name: string, value: string | null) {
  const el = document.documentElement
  if (value) el.style.setProperty(name, value)
  else el.style.removeProperty(name)
}

function currentTheme(): ThemeName {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light'
}

export function applyChrome() {
  const mode = currentTheme()
  const stored = readStore()[mode]
  const contentTheme = stored.page ? (isLightColor(stored.page) ? 'light' : 'dark') : mode
  const root = document.documentElement
  chrome.sidebar = stored.sidebar
  chrome.page = stored.page
  root.setAttribute('data-content-theme', contentTheme)
  if (stored.page) root.setAttribute('data-content-custom', 'true')
  else root.removeAttribute('data-content-custom')
  root.classList.toggle('dark', contentTheme === 'dark')
  setVar('--bg-sidebar', stored.sidebar || null)
  setVar('--bg-page', stored.page || null)
  if (stored.sidebar) {
    if (isLightColor(stored.sidebar)) {
      setVar('--text-on-dark', '#000000')
      setVar('--text-on-dark-muted', '#000000')
    } else {
      setVar('--text-on-dark', '#f5f5f7')
      setVar('--text-on-dark-muted', '#a1a1a6')
    }
  } else {
    setVar('--text-on-dark', null)
    setVar('--text-on-dark-muted', null)
  }
  chromeRevision.value += 1
}

function saveCurrent(patch: Partial<ChromePair>) {
  const store = readStore()
  const name = currentTheme()
  store[name] = { ...store[name], ...patch }
  writeStore(store)
  applyChrome()
}

function norm(hex: unknown): string {
  if (typeof hex !== 'string') return ''
  const v = hex.trim().toLowerCase().replace(/^#/, '')
  return /^[\da-f]{6}$/.test(v) ? `#${v}` : ''
}

export function setSidebarColor(hex: string) {
  const color = norm(hex)
  if (color) saveCurrent({ sidebar: color })
}

export function setPageColor(hex: string) {
  const color = norm(hex)
  if (color) saveCurrent({ page: color })
}

export function resetChrome() {
  saveCurrent({ sidebar: '', page: '' })
}
