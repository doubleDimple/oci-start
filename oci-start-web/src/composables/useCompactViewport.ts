import { onBeforeUnmount, ref } from 'vue'

/** Match the shared mobile console breakpoint, including live orientation changes. */
export function useCompactViewport() {
  const query = typeof window === 'undefined' ? undefined : window.matchMedia('(max-width: 760px)')
  const compact = ref(query?.matches ?? false)
  const update = (event: MediaQueryListEvent) => { compact.value = event.matches }
  query?.addEventListener('change', update)
  onBeforeUnmount(() => query?.removeEventListener('change', update))
  return compact
}
