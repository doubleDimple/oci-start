import { onScopeDispose, reactive, ref } from 'vue'
import request from '@/api/request'

export function usePagedQuery(url: string) {
  const loading = ref(false)
  const rows = ref<any[]>([])
  const page = ref(1)
  const size = ref(10)
  const total = ref(0)
  const keyword = ref('')
  let requestVersion = 0

  onScopeDispose(() => { requestVersion += 1 })

  async function load(extra: Record<string, unknown> = {}) {
    const current = ++requestVersion
    loading.value = true
    try {
      const res: any = await request.get(url, {
        params: {
          page: Math.max(0, page.value - 1),
          size: size.value,
          keyword: keyword.value || undefined,
          ...extra,
        },
      })
      if (current !== requestVersion) return
      const body = res?.data && Array.isArray(res.data.content) ? res.data : res
      rows.value = body.content || body.data || (Array.isArray(body) ? body : [])
      total.value = Number(body.totalElements ?? rows.value.length)
    } catch {
      // The shared request interceptor reports failures; keep the last successful page.
    } finally {
      if (current === requestVersion) loading.value = false
    }
  }

  return reactive({ loading, rows, page, size, total, keyword, load })
}
