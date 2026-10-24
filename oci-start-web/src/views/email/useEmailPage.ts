import { onBeforeUnmount, shallowReactive } from 'vue'
import { emailError, type EmailPage } from '@/api/email'

/** Independent, cancellable pagination. Failed reads retain the last usable page. */
export function useEmailPage<T>(size: number, read: (page: number, size: number, signal: AbortSignal) => Promise<EmailPage<T>>) {
  const state = shallowReactive({
    rows: [] as T[], page: 1, size, total: 0, pages: 0,
    loading: false, loaded: false, problem: null as ReturnType<typeof emailError> | null,
  })
  let sequence = 0
  let controller: AbortController | undefined
  let disposed = false
  let requestedPage = 1

  function stop() {
    sequence++
    controller?.abort()
    controller = undefined
    state.loading = false
  }
  function reset() {
    stop()
    state.rows = []
    state.page = requestedPage = 1
    state.total = state.pages = 0
    state.loaded = false
    state.problem = null
  }
  async function load(target = state.page): Promise<void> {
    if (disposed || !Number.isSafeInteger(target) || target < 1) return
    stop()
    const current = sequence
    const active = new AbortController()
    controller = active
    requestedPage = target
    state.loading = true
    state.problem = null
    try {
      const result = await read(target, state.size, active.signal)
      if (disposed || active.signal.aborted || current !== sequence) return
      if (result.totalPages > 0 && target > result.totalPages) {
        await load(result.totalPages)
        return
      }
      state.rows = result.content
      state.page = result.totalPages ? result.number + 1 : 1
      state.pages = result.totalPages
      state.total = result.totalElements
      state.loaded = true
    } catch (cause) {
      if (!disposed && !active.signal.aborted && current === sequence) state.problem = emailError(cause)
    } finally {
      if (!disposed && current === sequence) state.loading = false
    }
  }
  function retry() { return load(requestedPage) }
  onBeforeUnmount(() => { disposed = true; stop() })
  return Object.assign(state, { load, retry, reset, stop })
}
