import { ref } from 'vue'
import { applyChrome } from './useChrome'

const STORAGE_KEY = 'oci_theme'
export type ThemeName = 'light' | 'dark'
export type ThemePreference = ThemeName | 'system'

export const theme = ref<ThemeName>('light')
export const themeMode = ref<ThemePreference>('light')
const systemTheme = window.matchMedia('(prefers-color-scheme: dark)')
let listening = false

function readStored(): ThemePreference {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved === 'system') return 'system'
    return saved === 'dark' ? 'dark' : 'light'
  } catch {
    return 'light'
  }
}

function applyToDocument(name: ThemeName) {
  document.documentElement.setAttribute('data-theme', name)
  document.documentElement.classList.toggle('dark', name === 'dark')
  applyChrome()
}

export function applyStoredTheme() {
  themeMode.value = readStored()
  resolveTheme()
  if (!listening) {
    systemTheme.addEventListener('change', onSystemChange)
    listening = true
  }
}

function resolveTheme() {
  theme.value = themeMode.value === 'system' ? (systemTheme.matches ? 'dark' : 'light') : themeMode.value
  applyToDocument(theme.value)
}

function onSystemChange() {
  if (themeMode.value === 'system') resolveTheme()
}

export function setTheme(mode: ThemePreference) {
  themeMode.value = mode
  resolveTheme()
  try {
    localStorage.setItem(STORAGE_KEY, mode)
  } catch {
    /* ignore */
  }
}

export function toggleTheme() {
  setTheme(theme.value === 'dark' ? 'light' : 'dark')
}

if (import.meta.hot) import.meta.hot.dispose(() => systemTheme.removeEventListener('change', onSystemChange))
