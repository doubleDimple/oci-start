import { isAxiosError } from 'axios'
import { i18n } from '@/i18n'
import request from './request'
import { tenantPost } from './tenant'

export interface SubscribedRegion {
  regionKey: string
  regionName: string
  status: string
  isHomeRegion: boolean
}

export interface AvailableRegion {
  key: string
  name: string
  cnName: string
}

export interface RegionSummary {
  totalRegions: number
  subscribedRegions: number
  unsubscribedRegions: number
}

export interface SubscriptionDetail {
  regionKey: string
  success: boolean
  message: string
}

export interface SubscriptionResult {
  success: boolean
  message: string
  details: SubscriptionDetail[]
}

export interface SubscriptionStatus {
  regionKey: string
  status: string
  subscribed: boolean
}

type Body = Record<string, unknown>
type ErrorKey = 'tenantSubscription.responseError' | 'tenantSubscription.requestFailed'

class SubscriptionValidationError extends Error {
  readonly translationKey: ErrorKey
  readonly details: SubscriptionDetail[]
  readonly cause: unknown

  constructor(key: ErrorKey, body?: unknown, details: SubscriptionDetail[] = []) {
    super(i18n.global.t(key))
    this.name = 'SubscriptionValidationError'
    this.translationKey = key
    this.cause = body
    // Retain confirmed fields for diagnosis, but never return an incomplete batch as completed.
    this.details = details
  }
}

function isBody(value: unknown): value is Body {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function responseError(body: unknown, details: SubscriptionDetail[] = []): never {
  throw new SubscriptionValidationError('tenantSubscription.responseError', body, details)
}

function text(value: unknown, allowEmpty = false): value is string {
  return typeof value === 'string' && (allowEmpty || value.trim().length > 0)
}

function requireIdentifiers(tenantId: string, regionKeys: string[] = []) {
  if (!text(tenantId) || regionKeys.some(key => !text(key)) || new Set(regionKeys).size !== regionKeys.length) {
    throw new SubscriptionValidationError('tenantSubscription.requestFailed')
  }
}

function statusValue(value: unknown, body: unknown): string {
  const status = isBody(value) ? value.value : value
  if (!text(status)) responseError(body)
  return status
}

function count(value: unknown, body: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value) || value < 0) responseError(body)
  return value
}

async function get(url: string, tenantId: string, signal?: AbortSignal, regionKey?: string): Promise<unknown> {
  requireIdentifiers(tenantId, regionKey === undefined ? [] : [regionKey])
  // FAILED is a valid subscription status, so do not use tenantGet's status-error heuristic.
  return request.get(url, {
    params: regionKey === undefined ? { tenantId } : { tenantId, regionKey },
    signal,
    silent: true,
    timeout: 30000,
  })
}

export async function getSubscribedRegions(tenantId: string, signal?: AbortSignal): Promise<SubscribedRegion[]> {
  const body = await get('/tenants/subscribed-regions-data', tenantId, signal)
  if (!Array.isArray(body)) responseError(body)
  return body.map(value => {
    if (!isBody(value) || !text(value.regionKey) || !text(value.regionName) || typeof value.isHomeRegion !== 'boolean') responseError(body)
    return {
      regionKey: value.regionKey,
      regionName: value.regionName,
      status: statusValue(value.status, body),
      isHomeRegion: value.isHomeRegion,
    }
  })
}

export async function getAvailableRegions(tenantId: string, signal?: AbortSignal): Promise<AvailableRegion[]> {
  const body = await get('/tenants/unsubscribed-regions', tenantId, signal)
  if (!Array.isArray(body)) responseError(body)
  return body.map(value => {
    if (!isBody(value) || !text(value.key) || !text(value.name) || !text(value.cnName)) responseError(body)
    return { key: value.key, name: value.name, cnName: value.cnName }
  })
}

export async function getRegionSummary(tenantId: string, signal?: AbortSignal): Promise<RegionSummary> {
  const body = await get('/tenants/region-summary', tenantId, signal)
  if (!isBody(body)) responseError(body)
  return {
    totalRegions: count(body.totalRegions, body),
    subscribedRegions: count(body.subscribedRegions, body),
    unsubscribedRegions: count(body.unsubscribedRegions, body),
  }
}

export async function getSubscriptionStatus(tenantId: string, regionKey: string, signal?: AbortSignal): Promise<SubscriptionStatus> {
  requireIdentifiers(tenantId, [regionKey])
  const body = await get('/tenants/check-subscription-status', tenantId, signal, regionKey)
  if (!isBody(body) || typeof body.subscribed !== 'boolean') responseError(body)
  const status = statusValue(body.status, body)
  // The controller omits regionKey only in its explicit NOT_SUBSCRIBED branch.
  const unsubscribedWithoutKey = body.regionKey === undefined && !body.subscribed && status === 'NOT_SUBSCRIBED'
  if (body.regionKey !== regionKey && !unsubscribedWithoutKey) responseError(body)
  return { regionKey, status, subscribed: body.subscribed }
}

function parseResult(body: unknown, requestedKeys: string[]): SubscriptionResult {
  if (!isBody(body) || typeof body.success !== 'boolean' || !text(body.message, true) || !Array.isArray(body.details)) responseError(body)
  const details: SubscriptionDetail[] = []
  for (const value of body.details) {
    if (!isBody(value) || !text(value.regionKey) || typeof value.success !== 'boolean' || !text(value.message, true)) responseError(body, details)
    details.push({ regionKey: value.regionKey, success: value.success, message: value.message })
  }
  const requested = new Set(requestedKeys)
  const returned = new Set(details.map(detail => detail.regionKey))
  if (details.length !== requestedKeys.length || returned.size !== details.length || details.some(detail => !requested.has(detail.regionKey))) {
    responseError(body, details)
  }
  // Per-region outcomes are authoritative when the aggregate flag disagrees.
  return { success: details.every(detail => detail.success), message: body.message, details }
}

function rejectedResultBody(error: unknown): error is Body {
  // The interceptor rejects a business response with success:false as the raw JSON body.
  // HTTP/network failures remain AxiosErrors and must never be promoted into a batch result.
  if (isAxiosError(error) || error instanceof Error || !isBody(error)) return false
  if ('response' in error || 'request' in error || 'config' in error || !('success' in error)) return false
  if ('code' in error && error.code !== undefined && error.code !== null && error.code !== '') {
    const code = String(error.code).trim().toLowerCase()
    if (!['0', '200', 'success', 'ok'].includes(code)) return false
  }
  return true
}

export async function subscribeRegions(tenantId: string, regionKeys: string[], signal?: AbortSignal): Promise<SubscriptionResult> {
  requireIdentifiers(tenantId, regionKeys)
  if (!regionKeys.length) throw new SubscriptionValidationError('tenantSubscription.requestFailed')
  const requestedKeys = [...regionKeys]
  let body: unknown
  try {
    body = await tenantPost<unknown>('/tenants/subscribe-regions', { tenantId, regionKeys: requestedKeys }, {
      signal,
      // The server waits up to 30 minutes per region and handles the batch sequentially.
      // Aborting this client request does not cancel the server-side subscription.
      timeout: 0,
    })
  } catch (error) {
    if (!rejectedResultBody(error)) throw error
    body = error
  }
  return parseResult(body, requestedKeys)
}

function backendMessage(body: unknown): string {
  if (typeof body === 'string') return body.trim() && !body.trimStart().startsWith('<') ? body : ''
  if (!isBody(body)) return ''
  for (const key of ['error', 'message', 'msg']) {
    const value = body[key]
    if (text(value)) return value
  }
  return ''
}

export function subscriptionError(error: unknown): string {
  if (error instanceof SubscriptionValidationError) return i18n.global.t(error.translationKey)
  if (isAxiosError(error)) {
    const message = backendMessage(error.response?.data)
    if (message) return message
    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') return i18n.global.t('tenantSubscription.timeoutError')
    if (error.code === 'ERR_CANCELED') return i18n.global.t('tenantSubscription.requestFailed')
    if (error.code === 'ERR_NETWORK' || (!error.response && error.request)) return i18n.global.t('tenantSubscription.networkError')
    return i18n.global.t('tenantSubscription.requestFailed')
  }
  return backendMessage(error) || i18n.global.t('tenantSubscription.requestFailed')
}
