import { ref } from 'vue'
import { applyChrome } from './useChrome'

const STORAGE_KEY = 'oci_theme'
export type ThemeName = 'light' | 'dark'

export const theme = ref<ThemeName>('light')

function readStored(): ThemeName {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved === 'system') {
      return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'
    }
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
  theme.value = readStored()
  applyToDocument(theme.value)
}

export function toggleTheme() {
  theme.value = theme.value === 'dark' ? 'light' : 'dark'
  applyToDocument(theme.value)
  try {
    localStorage.setItem(STORAGE_KEY, theme.value)
  } catch {
    /* ignore */
  }
}
