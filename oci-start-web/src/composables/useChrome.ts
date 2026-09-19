import { computed, reactive, ref } from 'vue'
import type { ThemeName } from './useTheme'

const STORAGE_KEY = 'oci_chrome_theme_v2'
const LEGACY_KEY = 'oci_chrome_colors'

export interface ContentPalette {
  id: string
  nameKey: string
  mode: 'light' | 'dark'
  page: string         // Canvas background (--bg-page)
  card: string         // Container / Card background (--bg-card)
  cardSubtle: string   // Sub-card / table header (--bg-card-subtle)
  search: string       // Input wrapper background (--bg-search)
  hover: string        // Hover state (--bg-hover)
  border: string       // Border (--border)
  borderStrong: string // Strong border (--border-strong)
  textPrimary: string  // Primary text (--text-primary)
  textSecondary: string// Secondary text (--text-secondary)
  textMuted: string    // Muted text (--text-muted)
  shadowCard: string   // Card shadow (--shadow-card)
}

export interface SidebarTheme {
  id: string
  nameKey: string
  color: string
  isLight: boolean
}

export const SIDEBAR_PRESETS: SidebarTheme[] = [
  { id: 'obsidian', nameKey: 'chrome.sidebarObsidian', color: '#18181b', isLight: false },
  { id: 'black', nameKey: 'chrome.sidebarBlack', color: '#000000', isLight: false },
  { id: 'forest', nameKey: 'chrome.sidebarForest', color: '#0d4d3f', isLight: false },
  { id: 'navy', nameKey: 'chrome.sidebarNavy', color: '#0f172a', isLight: false },
  { id: 'espresso', nameKey: 'chrome.sidebarEspresso', color: '#29180e', isLight: false },
  { id: 'light', nameKey: 'chrome.sidebarLight', color: '#ffffff', isLight: true },
]

export const CONTENT_PRESETS: ContentPalette[] = [
  {
    id: 'slate',
    nameKey: 'chrome.presetSlate',
    mode: 'light',
    page: '#f1f5f9',
    card: '#ffffff',
    cardSubtle: '#f8fafc',
    search: '#e2e8f0',
    hover: '#f1f5f9',
    border: '#cbd5e1',
    borderStrong: '#94a3b8',
    textPrimary: '#0f172a',
    textSecondary: '#475569',
    textMuted: '#94a3b8',
    shadowCard: '0 1px 3px rgba(0, 0, 0, 0.06), 0 4px 12px -2px rgba(0, 0, 0, 0.05)',
  },
  {
    id: 'pure',
    nameKey: 'chrome.presetPure',
    mode: 'light',
    page: '#ffffff',
    card: '#f8fafc',
    cardSubtle: '#f1f5f9',
    search: '#ffffff',
    hover: '#eef2f6',
    border: '#e2e8f0',
    borderStrong: '#cbd5e1',
    textPrimary: '#0f172a',
    textSecondary: '#475569',
    textMuted: '#94a3b8',
    shadowCard: '0 1px 3px rgba(0, 0, 0, 0.04)',
  },
  {
    id: 'azure',
    nameKey: 'chrome.presetAzure',
    mode: 'light',
    page: '#eef2f8',
    card: '#ffffff',
    cardSubtle: '#f4f7fb',
    search: '#dde6f2',
    hover: '#e8f0fa',
    border: '#c7d7ea',
    borderStrong: '#9cb7da',
    textPrimary: '#0c1a2e',
    textSecondary: '#3e5473',
    textMuted: '#7d95b5',
    shadowCard: '0 2px 12px rgba(16, 42, 77, 0.05)',
  },
  {
    id: 'ivory',
    nameKey: 'chrome.presetIvory',
    mode: 'light',
    page: '#f7f4ed',
    card: '#ffffff',
    cardSubtle: '#fbf9f4',
    search: '#ede8dc',
    hover: '#f3ede1',
    border: '#dcd4c3',
    borderStrong: '#baa992',
    textPrimary: '#292524',
    textSecondary: '#57534e',
    textMuted: '#a8a29e',
    shadowCard: '0 2px 10px rgba(41, 37, 36, 0.04)',
  },
  {
    id: 'midnight',
    nameKey: 'chrome.presetMidnight',
    mode: 'dark',
    page: '#0b0f19',
    card: '#131b2e',
    cardSubtle: '#19233c',
    search: '#1c2742',
    hover: '#243254',
    border: '#243356',
    borderStrong: '#3b5288',
    textPrimary: '#f8fafc',
    textSecondary: '#cbd5e1',
    textMuted: '#8193b2',
    shadowCard: '0 4px 20px rgba(0, 0, 0, 0.45)',
  },
  {
    id: 'onyx',
    nameKey: 'chrome.presetOnyx',
    mode: 'dark',
    page: '#000000',
    card: '#161618',
    cardSubtle: '#1e1e22',
    search: '#26262b',
    hover: '#2c2c33',
    border: '#36363d',
    borderStrong: '#4d4d57',
    textPrimary: '#f5f5f7',
    textSecondary: '#d2d2d7',
    textMuted: '#86868b',
    shadowCard: '0 4px 20px rgba(0, 0, 0, 0.65)',
  },
  {
    id: 'aurora',
    nameKey: 'chrome.presetAurora',
    mode: 'dark',
    page: '#061a14',
    card: '#0e2a22',
    cardSubtle: '#14382e',
    search: '#164034',
    hover: '#1e5243',
    border: '#215f4e',
    borderStrong: '#2f866e',
    textPrimary: '#f0fdf4',
    textSecondary: '#bbf7d0',
    textMuted: '#6ee7b7',
    shadowCard: '0 4px 20px rgba(6, 26, 20, 0.5)',
  },
]

export const SIDEBAR_SWATCHES = SIDEBAR_PRESETS.map(s => s.color)
export const PAGE_SWATCHES = CONTENT_PRESETS.map(p => p.page)

export interface ChromePreference {
  sidebar: string
  page: string
  preset: string
  sidebarPreset: string
}

type ChromeStore = Record<ThemeName, ChromePreference>

const DEFAULT_LIGHT: ChromePreference = {
  sidebar: '#18181b',
  page: '#f1f5f9',
  preset: 'slate',
  sidebarPreset: 'obsidian',
}

const DEFAULT_DARK: ChromePreference = {
  sidebar: '#18181b',
  page: '#0b0f19',
  preset: 'midnight',
  sidebarPreset: 'obsidian',
}

let sessionStore: ChromeStore | undefined

export const chrome = reactive({
  sidebar: DEFAULT_LIGHT.sidebar,
  page: DEFAULT_LIGHT.page,
  preset: DEFAULT_LIGHT.preset,
  sidebarPreset: DEFAULT_LIGHT.sidebarPreset,
})

export const activeContentPreset = computed(() => chrome.preset)
export const activeSidebarPreset = computed(() => chrome.sidebarPreset)

// Canvas charts repaint after CSS palette changes
export const chromeRevision = ref(0)

function blankStore(): ChromeStore {
  return {
    light: { ...DEFAULT_LIGHT },
    dark: { ...DEFAULT_DARK },
  }
}

export function hexToRgb(hex: string): { r: number; g: number; b: number } | null {
  const n = hex.replace('#', '')
  if (!/^[\da-f]{6}$/i.test(n)) return null
  return {
    r: parseInt(n.slice(0, 2), 16),
    g: parseInt(n.slice(2, 4), 16),
    b: parseInt(n.slice(4, 6), 16),
  }
}

export function rgbToHsl(r: number, g: number, b: number): { h: number; s: number; l: number } {
  r /= 255
  g /= 255
  b /= 255
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  let h = 0
  let s = 0
  const l = (max + min) / 2

  if (max !== min) {
    const d = max - min
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    switch (max) {
      case r:
        h = ((g - b) / d + (g < b ? 6 : 0)) / 6
        break
      case g:
        h = ((b - r) / d + 2) / 6
        break
      case b:
        h = ((r - g) / d + 4) / 6
        break
    }
  }
  return {
    h: Math.round(h * 360),
    s: Math.round(s * 100),
    l: Math.round(l * 100),
  }
}

export function hslToHex(h: number, s: number, l: number): string {
  s /= 100
  l /= 100
  const a = s * Math.min(l, 1 - l)
  const f = (n: number) => {
    const k = (n + h / 30) % 12
    const color = l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1)
    return Math.round(255 * Math.max(0, Math.min(1, color)))
      .toString(16)
      .padStart(2, '0')
  }
  return `#${f(0)}${f(8)}${f(4)}`
}

export function getLuminance(hex: string): number {
  const rgb = hexToRgb(hex)
  if (!rgb) return 0.5
  const linear = (channel: number) => {
    const c = channel / 255
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
}

export function isLightColor(hex: string): boolean {
  return getLuminance(hex) >= 0.42
}

/**
 * Enterprise smart color derivation engine:
 * Derives a complete, coordinated surface hierarchy from any arbitrary canvas hex.
 */
export function deriveCustomPalette(hex: string): ContentPalette {
  const normHex = norm(hex) || '#f1f5f9'
  const rgb = hexToRgb(normHex) || { r: 241, g: 245, b: 249 }
  const hsl = rgbToHsl(rgb.r, rgb.g, rgb.b)
  const isLight = isLightColor(normHex)

  if (isLight) {
    // Pure or near pure white canvas (L >= 99% or #ffffff): Card gets a subtle surface and clear border so it never blends into the white canvas
    if (normHex === '#ffffff' || hsl.l >= 99) {
      return {
        id: 'custom',
        nameKey: 'chrome.presetCustom',
        mode: 'light',
        page: normHex,
        card: '#f8fafc',
        cardSubtle: '#f1f5f9',
        search: '#ffffff',
        hover: '#eef2f6',
        border: '#e2e8f0',
        borderStrong: '#cbd5e1',
        textPrimary: '#0f172a',
        textSecondary: '#475569',
        textMuted: '#94a3b8',
        shadowCard: '0 1px 3px rgba(0, 0, 0, 0.04)',
      }
    }
    // Standard light: Card floats cleanly as #ffffff on top of the tinted/gray canvas
    return {
      id: 'custom',
      nameKey: 'chrome.presetCustom',
      mode: 'light',
      page: normHex,
      card: '#ffffff',
      cardSubtle: hslToHex(hsl.h, Math.min(hsl.s, 18), 97),
      search: hslToHex(hsl.h, hsl.s, Math.max(0, hsl.l - 7)),
      hover: hslToHex(hsl.h, hsl.s, Math.max(0, hsl.l - 4)),
      border: hslToHex(hsl.h, Math.min(hsl.s, 25), Math.max(0, hsl.l - 15)),
      borderStrong: hslToHex(hsl.h, Math.min(hsl.s, 30), Math.max(0, hsl.l - 26)),
      textPrimary: '#0f172a',
      textSecondary: '#475569',
      textMuted: '#94a3b8',
      shadowCard: '0 2px 10px rgba(0, 0, 0, 0.05)',
    }
  }

  // Dark mode: Cards are elevated layers (+10% lightness) with matching hue
  const cardLightness = Math.min(80, hsl.l + 10)
  const searchLightness = Math.min(85, hsl.l + 13)
  const hoverLightness = Math.min(88, hsl.l + 17)
  const borderLightness = Math.min(90, hsl.l + 20)
  const borderStrongLightness = Math.min(92, hsl.l + 28)

  return {
    id: 'custom',
    nameKey: 'chrome.presetCustom',
    mode: 'dark',
    page: normHex,
    card: hslToHex(hsl.h, Math.min(hsl.s, 35), cardLightness),
    cardSubtle: hslToHex(hsl.h, Math.min(hsl.s, 35), cardLightness + 4),
    search: hslToHex(hsl.h, Math.min(hsl.s, 35), searchLightness),
    hover: hslToHex(hsl.h, Math.min(hsl.s, 35), hoverLightness),
    border: hslToHex(hsl.h, Math.min(hsl.s, 30), borderLightness),
    borderStrong: hslToHex(hsl.h, Math.min(hsl.s, 35), borderStrongLightness),
    textPrimary: '#f8fafc',
    textSecondary: '#cbd5e1',
    textMuted: '#94a3b8',
    shadowCard: '0 4px 20px rgba(0, 0, 0, 0.45)',
  }
}

function readStore(): ChromeStore {
  if (sessionStore) return sessionStore
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<ChromeStore> | null
      sessionStore = {
        light: {
          sidebar: norm(parsed?.light?.sidebar) || DEFAULT_LIGHT.sidebar,
          page: norm(parsed?.light?.page) || DEFAULT_LIGHT.page,
          preset: parsed?.light?.preset || DEFAULT_LIGHT.preset,
          sidebarPreset: parsed?.light?.sidebarPreset || DEFAULT_LIGHT.sidebarPreset,
        },
        dark: {
          sidebar: norm(parsed?.dark?.sidebar) || DEFAULT_DARK.sidebar,
          page: norm(parsed?.dark?.page) || DEFAULT_DARK.page,
          preset: parsed?.dark?.preset || DEFAULT_DARK.preset,
          sidebarPreset: parsed?.dark?.sidebarPreset || DEFAULT_DARK.sidebarPreset,
        },
      }
      return sessionStore
    }
    // Backward compatibility with legacy storage key
    const legacyRaw = localStorage.getItem(LEGACY_KEY)
    if (legacyRaw) {
      const parsed = JSON.parse(legacyRaw) as Partial<Record<ThemeName, { sidebar?: string; page?: string }>> | null
      sessionStore = {
        light: {
          sidebar: norm(parsed?.light?.sidebar) || DEFAULT_LIGHT.sidebar,
          page: norm(parsed?.light?.page) || DEFAULT_LIGHT.page,
          preset: DEFAULT_LIGHT.preset,
          sidebarPreset: DEFAULT_LIGHT.sidebarPreset,
        },
        dark: {
          sidebar: norm(parsed?.dark?.sidebar) || DEFAULT_DARK.sidebar,
          page: norm(parsed?.dark?.page) || DEFAULT_DARK.page,
          preset: DEFAULT_DARK.preset,
          sidebarPreset: DEFAULT_DARK.sidebarPreset,
        },
      }
      return sessionStore
    }
    return (sessionStore = blankStore())
  } catch {
    return (sessionStore = blankStore())
  }
}

function writeStore(store: ChromeStore) {
  sessionStore = store
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store))
  } catch {
    /* ignore */
  }
}

function setVar(name: string, value: string | null) {
  const el = document.documentElement
  if (value) el.style.setProperty(name, value)
  else el.style.removeProperty(name)
}

function currentTheme(): ThemeName {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light'
}

export function getCurrentContentPalette(): ContentPalette {
  const mode = currentTheme()
  const store = readStore()
  const current = store[mode]

  if (current.preset && current.preset !== 'custom') {
    const found = CONTENT_PRESETS.find(p => p.id === current.preset)
    if (found) return found
  }
  if (current.page) {
    return deriveCustomPalette(current.page)
  }
  return CONTENT_PRESETS.find(p => p.id === (mode === 'dark' ? 'midnight' : 'slate')) || CONTENT_PRESETS[0]
}

export function applyChrome() {
  const mode = currentTheme()
  const store = readStore()
  const current = store[mode]
  const palette = getCurrentContentPalette()

  chrome.sidebar = current.sidebar
  chrome.page = current.page || palette.page
  chrome.preset = current.preset || palette.id
  chrome.sidebarPreset = current.sidebarPreset || 'custom'

  const root = document.documentElement
  root.setAttribute('data-content-theme', palette.mode)
  root.setAttribute('data-content-custom', 'true')
  root.classList.toggle('dark', palette.mode === 'dark')

  // Set all core layout & content surface tokens
  setVar('--bg-app', palette.page)
  setVar('--bg-page', palette.page)
  setVar('--bg-card', palette.card)
  setVar('--bg-card-subtle', palette.cardSubtle)
  setVar('--bg-search', palette.search)
  setVar('--bg-hover', palette.hover)
  setVar('--border', palette.border)
  setVar('--border-strong', palette.borderStrong)
  setVar('--text-primary', palette.textPrimary)
  setVar('--text-secondary', palette.textSecondary)
  setVar('--text-muted', palette.textMuted)
  setVar('--shadow-card', palette.shadowCard)

  // Synchronize Element Plus surface variables to current skin
  setVar('--el-bg-color', palette.card)
  setVar('--el-bg-color-page', palette.page)
  setVar('--el-bg-color-overlay', palette.card)
  setVar('--el-fill-color', palette.search)
  setVar('--el-fill-color-light', palette.hover)
  setVar('--el-fill-color-blank', palette.card)
  setVar('--el-border-color', palette.border)
  setVar('--el-border-color-light', palette.border)
  setVar('--el-table-bg-color', palette.card)
  setVar('--el-table-tr-bg-color', palette.card)
  setVar('--el-table-header-bg-color', palette.cardSubtle)
  setVar('--el-table-row-hover-bg-color', palette.hover)
  setVar('--el-text-color-primary', palette.textPrimary)
  setVar('--el-text-color-regular', palette.textPrimary)
  setVar('--el-text-color-secondary', palette.textSecondary)
  setVar('--el-text-color-placeholder', palette.textMuted)

  // Synchronize sidebar tokens
  const sidebarColor = current.sidebar || (mode === 'dark' ? '#18181b' : '#1d1d1f')
  setVar('--bg-sidebar', sidebarColor)
  if (isLightColor(sidebarColor)) {
    setVar('--text-on-dark', '#0f172a')
    setVar('--text-on-dark-muted', '#64748b')
  } else {
    setVar('--text-on-dark', '#f5f5f7')
    setVar('--text-on-dark-muted', '#a1a1a6')
  }

  chromeRevision.value += 1
}

function saveCurrent(patch: Partial<ChromePreference>) {
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

export function setSidebarPreset(presetId: string) {
  const found = SIDEBAR_PRESETS.find(s => s.id === presetId)
  if (found) {
    saveCurrent({ sidebar: found.color, sidebarPreset: found.id })
  }
}

export function setSidebarColor(hex: string) {
  const color = norm(hex)
  if (color) {
    const matched = SIDEBAR_PRESETS.find(s => s.color.toLowerCase() === color.toLowerCase())
    saveCurrent({ sidebar: color, sidebarPreset: matched ? matched.id : 'custom' })
  }
}

export function setContentPreset(presetId: string) {
  const found = CONTENT_PRESETS.find(p => p.id === presetId)
  if (found) {
    saveCurrent({ page: found.page, preset: found.id })
  }
}

export function setCustomPageColor(hex: string) {
  const color = norm(hex)
  if (color) {
    const matched = CONTENT_PRESETS.find(p => p.page.toLowerCase() === color.toLowerCase())
    saveCurrent({ page: color, preset: matched ? matched.id : 'custom' })
  }
}

export function setPageColor(hex: string) {
  setCustomPageColor(hex)
}

export function resetChrome() {
  const store = readStore()
  const mode = currentTheme()
  store[mode] = mode === 'dark' ? { ...DEFAULT_DARK } : { ...DEFAULT_LIGHT }
  writeStore(store)
  applyChrome()
}
