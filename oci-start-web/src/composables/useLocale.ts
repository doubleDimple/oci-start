import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { applyDocumentLocale, LOCALE_STORAGE_KEY, type AppLocale } from '@/i18n'

const SPRING_LANG: Record<AppLocale, string> = {
  zh: 'zh_CN',
  en: 'en_US',
}

export function useLocale() {
  const { locale, t } = useI18n()
  const current = computed(() => locale.value as AppLocale)

  function setLocale(code: AppLocale) {
    locale.value = code
    localStorage.setItem(LOCALE_STORAGE_KEY, code)
    applyDocumentLocale(code)
    const url = new URL(window.location.href)
    url.searchParams.set('lang', SPRING_LANG[code])
    window.history.replaceState({}, '', url.toString())
    fetch(`${url.pathname}${url.search}`, { credentials: 'include' }).catch(() => undefined)
  }

  return { t, locale: current, setLocale }
}
