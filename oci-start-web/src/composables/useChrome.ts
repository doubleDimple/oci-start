import { reactive } from 'vue'
import type { ThemeName } from './useTheme'

const STORAGE_KEY = 'oci_chrome_colors'

export const SIDEBAR_SWATCHES = ['#1d1d1f', '#000000', '#0d4d3f', '#16324a', '#3d2314']
export const PAGE_SWATCHES = ['#f5f5f7', '#ffffff', '#eef1f4', '#f7f3ea', '#000000']

type ChromePair = { sidebar: string; page: string }
type ChromeStore = Record<ThemeName, ChromePair>

const EMPTY: ChromePair = { sidebar: '', page: '' }

export const chrome = reactive({
  sidebar: '',
  page: '',
})

function blankStore(): ChromeStore {
  return { light: { ...EMPTY }, dark: { ...EMPTY } }
}

function readStore(): ChromeStore {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return blankStore()
    const parsed = JSON.parse(raw) as Partial<ChromeStore>
    return {
      light: { sidebar: parsed.light?.sidebar || '', page: parsed.light?.page || '' },
      dark: { sidebar: parsed.dark?.sidebar || '', page: parsed.dark?.page || '' },
    }
  } catch {
    return blankStore()
  }
}

function writeStore(store: ChromeStore) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store))
  } catch {
    /* ignore */
  }
}

function hexToRgb(hex: string) {
  const n = hex.replace('#', '')
  if (n.length !== 6) return null
  return {
    r: parseInt(n.slice(0, 2), 16) / 255,
    g: parseInt(n.slice(2, 4), 16) / 255,
    b: parseInt(n.slice(4, 6), 16) / 255,
  }
}

function isLightColor(hex: string) {
  const rgb = hexToRgb(hex)
  if (!rgb) return false
  return 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b > 0.55
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
  const stored = readStore()[currentTheme()]
  chrome.sidebar = stored.sidebar
  chrome.page = stored.page
  setVar('--bg-sidebar', stored.sidebar || null)
  setVar('--bg-page', stored.page || null)
  if (stored.sidebar) {
    if (isLightColor(stored.sidebar)) {
      setVar('--text-on-dark', '#1d1d1f')
      setVar('--text-on-dark-muted', '#6e6e73')
    } else {
      setVar('--text-on-dark', '#f5f5f7')
      setVar('--text-on-dark-muted', '#a1a1a6')
    }
  } else {
    setVar('--text-on-dark', null)
    setVar('--text-on-dark-muted', null)
  }
}

function saveCurrent(patch: Partial<ChromePair>) {
  const store = readStore()
  const name = currentTheme()
  store[name] = { ...store[name], ...patch }
  writeStore(store)
  applyChrome()
}

function norm(hex: string) {
  const v = hex.trim().toLowerCase()
  return v.startsWith('#') ? v : `#${v}`
}

export function setSidebarColor(hex: string) {
  saveCurrent({ sidebar: norm(hex) })
}

export function setPageColor(hex: string) {
  saveCurrent({ page: norm(hex) })
}

export function resetChrome() {
  saveCurrent({ sidebar: '', page: '' })
}
