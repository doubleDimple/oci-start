import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { fetchBusinessOverview, type BusinessOverview } from '@/api/dashboard'

export function useBusinessOverview() {
  const overview = ref<BusinessOverview | null>(null)
  const days = ref<7 | 30>(7)
  const loading = ref(false)
  const failed = ref(false)
  let mounted = false
  let request: AbortController | undefined
  let timer: number | undefined

  async function refresh(replace = false) {
    if (!mounted || (request && !replace)) return
    request?.abort()
    const controller = new AbortController()
    request = controller
    loading.value = true
    const period = days.value
    try {
      const response = await fetchBusinessOverview(period, controller.signal)
      if (!mounted || controller.signal.aborted || request !== controller) return
      const data = response?.data
      if (!response?.success || !data || data.days !== period || !Number.isFinite(data.instances)
        || !Number.isFinite(data.accounts) || !Array.isArray(data.accountStates) || !Array.isArray(data.instanceStates)
        || !Array.isArray(data.architectures) || !Array.isArray(data.monitoring) || !Array.isArray(data.regionRanking)
        || !Array.isArray(data.tenantRanking) || data.operations?.daily?.length !== period || data.email?.daily?.length !== period
        || !data.launch || !Number.isFinite(data.generatedAt)) throw new Error('Incomplete business overview')
      overview.value = data
      failed.value = false
    } catch {
      if (mounted && !controller.signal.aborted && request === controller) failed.value = true
    } finally {
      if (request === controller) {
        request = undefined
        loading.value = false
      }
    }
  }
  function schedule() {
    window.clearInterval(timer)
    if (mounted && !document.hidden) timer = window.setInterval(() => void refresh(), 60000)
  }
  function visibilityChanged() {
    if (document.hidden) request?.abort()
    else void refresh(true)
    schedule()
  }
  watch(days, () => {
    // Preserve the labelled snapshot while the next period loads so charts can
    // transition directly between real datasets. The view labels it with data.days.
    failed.value = false
    void refresh(true)
  })
  onMounted(() => {
    mounted = true
    void refresh()
    schedule()
    document.addEventListener('visibilitychange', visibilityChanged)
  })
  onBeforeUnmount(() => {
    mounted = false
    request?.abort()
    window.clearInterval(timer)
    document.removeEventListener('visibilitychange', visibilityChanged)
  })
  return { overview, days, loading, failed, refresh }
}
