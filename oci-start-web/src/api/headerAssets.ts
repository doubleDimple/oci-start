import { isAxiosError } from 'axios'
import { i18n } from '@/i18n'
import { tenantCsrfToken, tenantGet } from './tenant'
import { checkSession, handleSessionResponse } from '@/utils/session'

export interface HeaderAssetSummary {
  totalCount: number
  upgradeCount: number
  freeCount: number
  totalCost: string
  level: number
  levelTitle: string
}

type AssetErrorKey = 'invalidResponse' | 'requestFailed' | 'networkError' | 'timeout'
  | 'cancelled' | 'unauthorized' | 'aiUnavailable' | 'streamTooLarge'

class HeaderAssetError extends Error {
  constructor(readonly key: AssetErrorKey) {
    super(key)
    this.name = 'HeaderAssetError'
  }
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function count(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
}

export async function fetchHeaderAssets(signal?: AbortSignal): Promise<HeaderAssetSummary> {
  const body = await tenantGet<unknown>('/tenants/asset/analysis', { cloudType: 1 }, { signal })
  const data = record(body) && body.success === true ? body.data : null
  if (!record(data)
    || !count(data.totalCount) || !count(data.upgradeCount) || !count(data.freeCount)
    || data.upgradeCount + data.freeCount !== data.totalCount
    || typeof data.totalCost !== 'string' || !/^-?\d+(?:[.,]\d+)?$/.test(data.totalCost)
    || !Number.isFinite(Number(data.totalCost.replace(',', '.')))
    || !count(data.level) || data.level < 1 || data.level > 5
    || typeof data.levelTitle !== 'string') {
    throw new HeaderAssetError('invalidResponse')
  }
  return {
    totalCount: data.totalCount, upgradeCount: data.upgradeCount, freeCount: data.freeCount,
    totalCost: data.totalCost, level: data.level, levelTitle: data.levelTitle,
  }
}

/** The endpoint always audits OCI. A closed stream alone is not a success acknowledgement. */
export async function streamHeaderAssetAnalysis(
  signal: AbortSignal,
  onText: (text: string) => void,
): Promise<{ completed: boolean }> {
  const controller = new AbortController()
  const abort = () => controller.abort()
  signal.addEventListener('abort', abort, { once: true })
  if (signal.aborted) abort()
  let timedOut = false
  const timer = window.setTimeout(() => { timedOut = true; controller.abort() }, 300000)
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined
  try {
    const headers = new Headers({ Accept: 'text/event-stream', 'X-Requested-With': 'XMLHttpRequest' })
    const csrf = tenantCsrfToken()
    const csrfHeader = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
    if (csrf) headers.set(csrfHeader, csrf)
    const response = await fetch('/tenants/analyze', {
      method: 'GET', credentials: 'include', cache: 'no-store', headers, signal: controller.signal,
    })
    handleSessionResponse({ status: response.status, url: response.url })
    if (response.type === 'opaqueredirect') void checkSession()
    if (response.status === 401) throw new HeaderAssetError('unauthorized')
    if (!response.ok) {
      const body: unknown = await response.json().catch(() => null)
      handleSessionResponse({ body })
      const message = backendMessage(body)
      if (message) throw new Error(message)
      throw new HeaderAssetError('requestFailed')
    }
    if (!response.body || !response.headers.get('content-type')?.toLowerCase().includes('text/event-stream')) {
      if (response.headers.get('content-type')?.split(';')[0]?.trim().toLowerCase() === 'application/json') {
        const body: unknown = await response.json().catch(() => null)
        handleSessionResponse({ body })
      }
      throw new HeaderAssetError('invalidResponse')
    }
    reader = response.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''
    let dataLines: string[] = []
    let eventName = ''
    let completed = false
    let textLength = 0
    let pendingLength = 0
    const maximumLength = 2 * 1024 * 1024

    const dispatch = () => {
      if (!dataLines.length) { eventName = ''; return }
      const text = dataLines.join('\n')
      const event = eventName
      dataLines = []
      eventName = ''
      pendingLength = 0
      textLength += text.length + 1
      if (textLength > maximumLength) throw new HeaderAssetError('streamTooLarge')
      onText(text.endsWith('\n') ? text : `${text}\n`)
      // These exact payloads are emitted by ChatAiServiceImpl, not inferred from arbitrary AI prose.
      if (text.trim() === '✔ 资产评估报告生成完毕。') completed = true
      if (text.trim() === 'data:AI配置缺失' || text.trim() === 'AI配置缺失') {
        throw new HeaderAssetError('aiUnavailable')
      }
      if (event === 'error') {
        if (text) throw new Error(text)
        throw new HeaderAssetError('requestFailed')
      }
    }
    const consumeLine = (line: string) => {
      if (!line) { dispatch(); return }
      if (line.startsWith(':')) return
      const colon = line.indexOf(':')
      const field = colon < 0 ? line : line.slice(0, colon)
      const value = colon < 0 ? '' : line.slice(colon + 1).replace(/^ /, '')
      if (field === 'data') {
        pendingLength += value.length + 1
        if (pendingLength > maximumLength) throw new HeaderAssetError('streamTooLarge')
        dataLines.push(value)
      }
      else if (field === 'event') eventName = value
    }
    const consumeBuffer = (final = false) => {
      let match: RegExpExecArray | null
      while ((match = /\r\n|\r|\n/.exec(buffer))) {
        // Preserve a CR at a chunk boundary so the following LF belongs to the same line ending.
        if (!final && match[0] === '\r' && match.index === buffer.length - 1) break
        const line = buffer.slice(0, match.index)
        buffer = buffer.slice(match.index + match[0].length)
        consumeLine(line)
      }
      if (buffer.length > maximumLength) throw new HeaderAssetError('streamTooLarge')
    }

    while (!completed) {
      const result = await reader.read()
      if (result.done) {
        buffer += decoder.decode()
        consumeBuffer(true)
        // An event without its final blank line is incomplete; it cannot confirm completion.
        break
      }
      buffer += decoder.decode(result.value, { stream: true })
      consumeBuffer()
      if (controller.signal.aborted) throw new HeaderAssetError('cancelled')
    }
    return { completed }
  } catch (error) {
    if (timedOut) throw new HeaderAssetError('timeout')
    if (signal.aborted) throw new HeaderAssetError('cancelled')
    throw error
  } finally {
    window.clearTimeout(timer)
    signal.removeEventListener('abort', abort)
    if (reader) {
      await reader.cancel().catch(() => undefined)
      reader.releaseLock()
    }
    controller.abort()
  }
}

function backendMessage(value: unknown): string {
  if (typeof value === 'string') return value.trimStart().startsWith('<') ? '' : value
  if (!record(value)) return ''
  for (const key of ['message', 'error', 'msg']) {
    const text = value[key]
    if (typeof text === 'string' && text) return text
  }
  return ''
}

export function headerAssetError(error: unknown): string {
  if (error instanceof HeaderAssetError) return i18n.global.t(`headerAssets.${error.key}`)
  if (isAxiosError(error)) {
    if (error.response?.status === 401) return i18n.global.t('headerAssets.unauthorized')
    const message = backendMessage(error.response?.data)
    if (message) return message
    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') return i18n.global.t('headerAssets.timeout')
    if (error.code === 'ERR_NETWORK' || (!error.response && error.request)) return i18n.global.t('headerAssets.networkError')
    return i18n.global.t('headerAssets.requestFailed')
  }
  if (error instanceof TypeError) return i18n.global.t('headerAssets.networkError')
  if (error instanceof Error && error.message) return error.message
  return backendMessage(error) || i18n.global.t('headerAssets.requestFailed')
}
