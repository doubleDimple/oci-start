import { isAxiosError, isCancel } from 'axios'
import request from './request'
import { tenantCsrfToken, tenantGet, tenantPost, tenantPut } from './tenant'

export interface MemoRecord {
  id: string; title: string; summary: string; content: string; htmlContent: string | null
  createTime: string | null; updateTime: string | null; revision: string | null
}
export interface MemoInput { title: string; summary: string; content: string; htmlContent: string | null }
export type MemoErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout' | 'cancelled'
  | 'unauthorized' | 'forbidden' | 'notFound' | 'conflict'
export class MemoApiError extends Error {
  constructor(public key: MemoErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'MemoApiError'
  }
}
export const MEMO_TEXT_LIMIT_BYTES = 65_535
export const MEMO_TITLE_LIMIT = 255
export const MEMO_SUMMARY_LIMIT = 200
export function memoUtf8Bytes(value: string): number { return new TextEncoder().encode(value).length }
const MAX_LONG = '9223372036854775807'
const BASE = '/api/memos'
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function invalid(): never { throw new MemoApiError('invalidResponse') }
function badInput(): never { throw new MemoApiError('invalidInput') }
export function isMemoId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d*$/.test(value)
    && (value.length < MAX_LONG.length || (value.length === MAX_LONG.length && value <= MAX_LONG))
}
export function isMemoRevision(value: unknown): value is string { return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value) }
function id(value: unknown): string {
  const candidate = typeof value === 'number' && Number.isSafeInteger(value) ? String(value) : value
  return isMemoId(candidate) ? candidate : invalid()
}
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalid() }
function localTime(value: unknown): string | null {
  if (value == null) return null
  // Preserve the server's local calendar value. There is no UTC offset in this contract.
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(value) ? value : invalid()
}
function parseMemo(value: unknown): MemoRecord {
  if (!object(value)) return invalid()
  return { id: id(value.id), title: text(value.title), summary: text(value.summary), content: text(value.content),
    htmlContent: value.htmlContent == null ? null : text(value.htmlContent), createTime: localTime(value.createTime),
    updateTime: localTime(value.updateTime), revision: null }
}
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g,
      (token: string, number?: string) => number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token))
  } catch { return raw }
}
const EMPTY_BODY = Symbol('empty-memo-receipt')
function decodeWrite(raw: unknown): unknown { return typeof raw === 'string' && raw.trim() === '' ? EMPTY_BODY : decode(raw) }
const readOptions = { timeout: 30_000, transformResponse: [decode], headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' } }
const writeOptions = { timeout: 0, transformResponse: [decodeWrite] }
export async function listMemos(signal?: AbortSignal): Promise<MemoRecord[]> {
  try {
    const body: unknown = await tenantGet(BASE, undefined, { ...readOptions, signal })
    if (!Array.isArray(body)) return invalid()
    const rows = body.map(parseMemo)
    if (new Set(rows.map(row => row.id)).size !== rows.length) return invalid()
    return rows
  } catch (cause) { throw memoError(cause) }
}
export async function getMemo(memoId: string, signal?: AbortSignal): Promise<MemoRecord> {
  if (!isMemoId(memoId)) return badInput()
  try {
    const body: unknown = await tenantGet(`${BASE}/${memoId}`, { guarded: true }, { ...readOptions, signal })
    if (!object(body) || !isMemoRevision(body.revision)) return invalid()
    const memo = parseMemo(body.memo)
    if (memo.id !== memoId) return invalid()
    return { ...memo, revision: body.revision }
  } catch (cause) { throw memoError(cause) }
}
export function normalizeMemoInput(input: MemoInput): MemoInput {
  if (!input || typeof input.title !== 'string' || typeof input.summary !== 'string' || typeof input.content !== 'string'
    || (input.htmlContent !== null && typeof input.htmlContent !== 'string')) return badInput()
  const title = input.title.trim(), summary = input.summary.trim(), content = input.content
  if (!title || title.length > MEMO_TITLE_LIMIT || summary.length > MEMO_SUMMARY_LIMIT || !content.trim()
    || memoUtf8Bytes(content) > MEMO_TEXT_LIMIT_BYTES
    || (input.htmlContent !== null && memoUtf8Bytes(input.htmlContent) > MEMO_TEXT_LIMIT_BYTES)) return badInput()
  return { title, summary, content, htmlContent: input.htmlContent }
}
async function mutation<T>(send: () => Promise<unknown>, parse: (body: unknown) => T): Promise<T> {
  try { return parse(await send()) }
  catch (cause) {
    const body: unknown = isAxiosError(cause) ? cause.response?.data : null
    if (isAxiosError(cause) && object(body)) {
      const status = cause.response?.status
      // Only these endpoint-specific pre-write rejections prove that no mutation occurred.
      if ((status === 400 && body.errorKey === 'invalidInput') || (status === 404 && body.errorKey === 'notFound')
        || (status === 409 && body.errorKey === 'conflict')) throw new MemoApiError(body.errorKey, '', false)
    }
    const failure = memoError(cause)
    throw new MemoApiError(failure.key, '', true)
  }
}
export async function createMemo(input: MemoInput): Promise<MemoRecord> {
  const payload = normalizeMemoInput(input)
  return mutation(() => tenantPost(BASE, payload, writeOptions), parseMemo)
}
export async function updateMemo(memoId: string, input: MemoInput, revision: string): Promise<MemoRecord> {
  if (!isMemoId(memoId) || !isMemoRevision(revision)) return badInput()
  const payload = normalizeMemoInput(input)
  return mutation(() => tenantPut(`${BASE}/${memoId}`, payload, { ...writeOptions, headers: { 'If-Match': revision } }), body => {
    const result = parseMemo(body)
    if (result.id !== memoId) return invalid()
    return result
  })
}
export async function deleteMemo(memoId: string, revision: string): Promise<void> {
  if (!isMemoId(memoId) || !isMemoRevision(revision)) return badInput()
  const headers: Record<string, string> = { 'If-Match': revision }
  const token = tenantCsrfToken()
  if (token) headers[document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'] = token
  await mutation(() => request.delete(`${BASE}/${memoId}`, { ...writeOptions, headers, silent: true }), body => {
    if (body !== EMPTY_BODY) return invalid()
  })
}
export function memoError(cause: unknown): MemoApiError {
  // Do not expose raw memo contents, response bodies or request objects through errors.
  if (cause instanceof MemoApiError) return new MemoApiError(cause.key, '', cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new MemoApiError('cancelled')
  if (isAxiosError(cause)) {
    const status = cause.response?.status
    if (status === 400) return new MemoApiError('invalidInput')
    if (status === 401) return new MemoApiError('unauthorized')
    if (status === 403) return new MemoApiError('forbidden')
    // A proxy/route 404 is not evidence that the selected note was deleted.
    if (status === 404) return new MemoApiError(object(cause.response?.data)
      && cause.response.data.errorKey === 'notFound' ? 'notFound' : 'requestFailed')
    if (status === 409) return new MemoApiError('conflict')
    if (['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code ?? '')) return new MemoApiError('timeout')
  }
  return new MemoApiError('requestFailed')
}
