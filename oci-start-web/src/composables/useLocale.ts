import { computed, onBeforeUnmount, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { applyDocumentLocale, LOCALE_STORAGE_KEY, type AppLocale } from '@/i18n'
import { fetchUserInfo } from '@/api/user'

const SPRING_LANG: Record<AppLocale, string> = {
  zh: 'zh_CN',
  en: 'en_US',
}

export function useLocale() {
  const { locale, t } = useI18n()
  const current = computed(() => locale.value as AppLocale)
  const syncing = ref(false)
  const router = useRouter()
  const route = useRoute()
  let controller: AbortController | undefined

  async function setLocale(code: AppLocale): Promise<boolean> {
    if (syncing.value || current.value === code) return true
    syncing.value = true
    controller = new AbortController()
    try {
      // This read-only endpoint passes Spring's LocaleChangeInterceptor and sets
      // its HttpOnly language cookie without reloading a business page.
      const res = await fetchUserInfo({ lang: SPRING_LANG[code], signal: controller.signal })
      if (controller.signal.aborted || !res?.success) return false
      locale.value = code
      try { localStorage.setItem(LOCALE_STORAGE_KEY, code) } catch { /* session only */ }
      applyDocumentLocale(code)
      await router.replace({ query: { ...route.query, lang: SPRING_LANG[code] } })
      return true
    } catch {
      return false
    } finally {
      syncing.value = false
    }
  }

  onBeforeUnmount(() => controller?.abort())
  return { t, locale: current, setLocale, syncing }
}
