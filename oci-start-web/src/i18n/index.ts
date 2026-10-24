import { createI18n } from 'vue-i18n'
import zh from './zh'
import en from './en'

export const LOCALE_STORAGE_KEY = 'lang'
export type AppLocale = 'zh' | 'en'

export function resolveInitialLocale(): AppLocale {
  const urlLang = new URLSearchParams(window.location.search).get('lang')
  if (urlLang === 'en' || urlLang === 'en_US') return 'en'
  if (urlLang === 'zh' || urlLang === 'zh_CN' || urlLang === 'zh_TW') return 'zh'
  try {
    const saved = localStorage.getItem(LOCALE_STORAGE_KEY)
    if (saved === 'en' || saved === 'en_US') return 'en'
  } catch { /* default language */ }
  return 'zh'
}

export function applyDocumentLocale(locale: string) {
  document.documentElement.setAttribute('lang', locale === 'zh' ? 'zh-CN' : 'en')
}

const initial = resolveInitialLocale()

export const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: initial,
  fallbackLocale: 'en',
  messages: { zh, en },
})

applyDocumentLocale(initial)
