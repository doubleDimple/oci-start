import { isAxiosError } from 'axios'
import { i18n } from '@/i18n'
import { tenantPost } from './tenant'

export interface HeaderMessage {
  businessId: string
  subject: string
  content: string
  messageType: string
  readStatus: 0 | 1 | null
  createTime: string
}

export interface HeaderMessagePage {
  content: HeaderMessage[]
  totalElements: number
  totalPages: number
  pageNum: number
}

class HeaderMessageError extends Error {
  constructor(readonly translationKey: 'headerMessages.invalidResponse' | 'headerMessages.requestFailed') {
    super(translationKey)
    this.name = 'HeaderMessageError'
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function requireId(value: unknown): asserts value is string {
  if (!nonEmpty(value)) throw new HeaderMessageError('headerMessages.requestFailed')
}

function count(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new HeaderMessageError('headerMessages.invalidResponse')
  }
  return value
}

function nullableText(value: unknown): string {
  if (value === null || value === undefined) return ''
  if (typeof value !== 'string') throw new HeaderMessageError('headerMessages.invalidResponse')
  return value
}

function message(value: unknown): HeaderMessage {
  if (!isObject(value) || !nonEmpty(value.businessId)) throw new HeaderMessageError('headerMessages.invalidResponse')
  if (value.readStatus !== 0 && value.readStatus !== 1 && value.readStatus !== null && value.readStatus !== undefined) {
    throw new HeaderMessageError('headerMessages.invalidResponse')
  }
  return {
    businessId: value.businessId,
    subject: nullableText(value.subject),
    content: nullableText(value.content),
    messageType: nullableText(value.messageType),
    readStatus: value.readStatus === 0 ? 0 : value.readStatus === 1 ? 1 : null,
    createTime: nullableText(value.createTime),
  }
}

async function post(path: string, data: unknown, signal?: AbortSignal): Promise<Record<string, unknown>> {
  const body = await tenantPost<unknown>(`/sysMessage/${path}`, data, { signal })
  if (!isObject(body) || body.success !== true) throw new HeaderMessageError('headerMessages.invalidResponse')
  return body
}

export async function getHeaderUnreadCount(signal?: AbortSignal): Promise<number> {
  const body = await post('countUnread', {}, signal)
  return count(body.data)
}

export async function getHeaderMessages(pageNum: number, signal?: AbortSignal): Promise<HeaderMessagePage> {
  if (!Number.isInteger(pageNum) || pageNum < 1 || pageNum > 2147483647) throw new HeaderMessageError('headerMessages.requestFailed')
  // The service uses pageNum (one based), defaults to createTime DESC, and ignores readStatus.
  const body = await post('list', { pageNum, pageSize: 5 }, signal)
  const data = body.data
  if (!isObject(data) || !Array.isArray(data.content)) throw new HeaderMessageError('headerMessages.invalidResponse')
  const totalElements = count(data.totalElements)
  const totalPages = count(data.totalPages)
  if (count(data.number) !== pageNum - 1 || count(data.size) !== 5 || data.content.length > 5) {
    throw new HeaderMessageError('headerMessages.invalidResponse')
  }
  const content = data.content.map(message)
  if (new Set(content.map(item => item.businessId)).size !== content.length || totalPages !== Math.ceil(totalElements / 5)) {
    throw new HeaderMessageError('headerMessages.invalidResponse')
  }
  return { content, totalElements, totalPages, pageNum }
}

export async function getHeaderMessage(businessId: string, signal?: AbortSignal): Promise<HeaderMessage | null> {
  requireId(businessId)
  // Reading the detail marks the message as read for the shared message center.
  const body = await post('get', { businessId }, signal)
  if (body.data === null) return null
  const result = message(body.data)
  if (result.businessId !== businessId) throw new HeaderMessageError('headerMessages.invalidResponse')
  return result
}

export async function readAllHeaderMessages(signal?: AbortSignal): Promise<void> {
  // This endpoint has no request body and marks every message as read.
  await post('read', undefined, signal)
}

export async function deleteHeaderMessage(businessId: string, signal?: AbortSignal): Promise<void> {
  requireId(businessId)
  await post('del', { businessId }, signal)
}

function backendMessage(body: unknown): string {
  if (typeof body === 'string') return nonEmpty(body) && !body.trimStart().startsWith('<') ? body : ''
  if (!isObject(body)) return ''
  for (const key of ['error', 'message', 'msg']) {
    const value = body[key]
    if (nonEmpty(value)) return value
  }
  return ''
}

export function headerMessagesError(error: unknown): string {
  if (error instanceof HeaderMessageError) return i18n.global.t(error.translationKey)
  if (isAxiosError(error)) {
    const serverMessage = backendMessage(error.response?.data)
    if (serverMessage) return serverMessage
    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') return i18n.global.t('headerMessages.timeoutError')
    if (error.code === 'ERR_CANCELED') return i18n.global.t('headerMessages.requestFailed')
    if (error.code === 'ERR_NETWORK' || (!error.response && error.request)) return i18n.global.t('headerMessages.networkError')
    return i18n.global.t('headerMessages.requestFailed')
  }
  return backendMessage(error) || i18n.global.t('headerMessages.requestFailed')
}
