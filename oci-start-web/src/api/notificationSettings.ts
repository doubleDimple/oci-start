import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export type NotificationKind = 'task' | 'telegram' | 'proxy' | 'bark' | 'dingTalk' | 'feishu'
export type NotificationTestKind = Exclude<NotificationKind, 'task'>
export interface NotificationConfigMap {
  task: { enabled: boolean; executeHour: number; enableAccountCheck: boolean; enableBootLog: boolean; enableCostCheck: boolean; hasNotificationSecret: boolean }
  telegram: { enabled: boolean; chatId: string; chatName: string; hasBotToken: boolean }
  proxy: { enabled: boolean; type: string; host: string; port: number; username: string; hasPassword: boolean }
  bark: { enabled: boolean; url: string; hasDeviceKey: boolean }
  dingTalk: { enabled: boolean; hasWebhook: boolean; hasSecret: boolean }
  feishu: { enabled: boolean; hasWebhook: boolean; hasSecret: boolean }
}
export interface NotificationInputMap {
  task: Omit<NotificationConfigMap['task'], 'hasNotificationSecret'> & { notificationSecret: string; keepNotificationSecret: boolean; clearNotificationSecret?: boolean }
  telegram: Omit<NotificationConfigMap['telegram'], 'hasBotToken'> & { botToken: string; keepBotToken: boolean }
  proxy: Omit<NotificationConfigMap['proxy'], 'hasPassword'> & { password: string; keepPassword: boolean }
  bark: Omit<NotificationConfigMap['bark'], 'hasDeviceKey'> & { deviceKey: string; keepDeviceKey: boolean }
  dingTalk: { enabled: boolean; webhook: string; keepWebhook: boolean; secret: string; keepSecret: boolean }
  feishu: { enabled: boolean; webhook: string; keepWebhook: boolean; secret: string; keepSecret: boolean }
}
export interface NotificationSettings extends NotificationConfigMap { serverTimeZone: string }
export interface NotificationResult {
  kind: NotificationKind | 'bot'; action: 'save' | 'test' | 'start'
  connected: boolean | null; notificationAccepted: boolean; botStarted: boolean
}
export type NotificationErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed' | 'timeout' | 'cancelled'
  | 'unauthorized' | 'forbidden' | 'notFound' | 'saveMismatch' | 'testFailed'
export class NotificationApiError extends Error {
  constructor(public key: NotificationErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'NotificationApiError'
  }
}
const BASE = '/api/system'
const savePaths: Record<NotificationKind, string> = {
  task: 'updateTaskConfig', telegram: 'updateTelegramConfig', proxy: 'updateProxyConfig',
  bark: 'updateBarkConfig', dingTalk: 'updateDingTalkConfig', feishu: 'updateFeishuConfig',
}
const testPaths: Record<Exclude<NotificationTestKind, 'proxy'>, string> = {
  telegram: 'testTgTalk', bark: 'testBark', dingTalk: 'testDingTalk', feishu: 'testFeishu',
}
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value) }
function invalid(): never { throw new NotificationApiError('invalidResponse') }
function badInput(): never { throw new NotificationApiError('invalidInput') }
function text(value: unknown): string { return value == null ? '' : typeof value === 'string' ? value : invalid() }
function flag(value: unknown): boolean { return typeof value === 'boolean' ? value : invalid() }
function integer(value: unknown, min: number, max: number): number {
  return typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max ? value : invalid()
}
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try { return JSON.parse(raw) } catch { return raw }
}
const EMPTY_BODY = Symbol('empty-notification-receipt')
function decodeWrite(raw: unknown): unknown { return typeof raw === 'string' && raw.trim() === '' ? EMPTY_BODY : decode(raw) }
const readOptions = { timeout: 30_000, transformResponse: [decode], headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' } }
const writeOptions = { timeout: 0, transformResponse: [decodeWrite] }
export async function loadNotificationSettings(signal?: AbortSignal): Promise<NotificationSettings> {
  try {
    const body: unknown = await tenantGet(`${BASE}/notifyConfigs`, { redacted: true }, { ...readOptions, signal })
    if (!object(body) || body.success !== true || !object(body.data)) return invalid()
    const data = body.data
    const task = data.task, telegram = data.telegram, proxy = data.proxy, bark = data.bark, dingTalk = data.dingTalk, feishu = data.feishu
    if (!object(task) || !object(telegram) || !object(proxy) || !object(bark) || !object(dingTalk) || !object(feishu)) return invalid()
    const serverTimeZone = text(data.serverTimeZone)
    if (!serverTimeZone || serverTimeZone.length > 128) return invalid()
    // Explicit projection never retains token URLs or any legacy secret values.
    return { serverTimeZone,
      task: { enabled: flag(task.enabled), executeHour: integer(task.executeHour, 0, 23), enableAccountCheck: flag(task.enableAccountCheck),
        enableBootLog: flag(task.enableBootLog), enableCostCheck: flag(task.enableCostCheck), hasNotificationSecret: flag(task.hasNotificationSecret) },
      telegram: { enabled: flag(telegram.enabled), chatId: text(telegram.chatId), chatName: text(telegram.chatName), hasBotToken: flag(telegram.hasBotToken) },
      proxy: { enabled: flag(proxy.enabled), type: text(proxy.type), host: text(proxy.host), port: integer(proxy.port, 1, 65535),
        username: text(proxy.username), hasPassword: flag(proxy.hasPassword) },
      bark: { enabled: flag(bark.enabled), url: text(bark.url), hasDeviceKey: flag(bark.hasDeviceKey) },
      dingTalk: { enabled: flag(dingTalk.enabled), hasWebhook: flag(dingTalk.hasWebhook), hasSecret: flag(dingTalk.hasSecret) },
      feishu: { enabled: flag(feishu.enabled), hasWebhook: flag(feishu.hasWebhook), hasSecret: flag(feishu.hasSecret) } }
  } catch (cause) { throw notificationError(cause) }
}
function inputText(value: unknown, trim = true): string {
  if (typeof value !== 'string') return badInput()
  return trim ? value.trim() : value
}
function inputFlag(value: unknown): boolean { return typeof value === 'boolean' ? value : badInput() }
function inputInteger(value: unknown, min: number, max: number): number {
  return typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max ? value : badInput()
}
function httpUrl(value: string): string {
  if (!value) return ''
  let parsed: URL
  try { parsed = new URL(value) } catch { return badInput() }
  if (!['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname || parsed.username || parsed.password || parsed.hash
    || value.includes('#') || /[\s\\\u0000-\u001f\u007f]/.test(value)) return badInput()
  return value
}
export function normalizeNotificationInput<K extends NotificationKind>(kind: K, input: NotificationInputMap[K],
  purpose: 'save' | 'test' = 'save'): NotificationInputMap[K] {
  const enabled = inputFlag(input.enabled)
  let result: NotificationInputMap[NotificationKind]
  if (kind === 'task') {
    const value = input as NotificationInputMap['task'], keepNotificationSecret = inputFlag(value.keepNotificationSecret)
    const clearNotificationSecret = value.clearNotificationSecret === undefined ? false : inputFlag(value.clearNotificationSecret)
    if (keepNotificationSecret && clearNotificationSecret) return badInput()
    result = { enabled, executeHour: inputInteger(value.executeHour, 0, 23), enableAccountCheck: inputFlag(value.enableAccountCheck),
      enableBootLog: inputFlag(value.enableBootLog), enableCostCheck: inputFlag(value.enableCostCheck), keepNotificationSecret, clearNotificationSecret,
      notificationSecret: keepNotificationSecret || clearNotificationSecret ? '' : inputText(value.notificationSecret) }
  } else if (kind === 'telegram') {
    const value = input as NotificationInputMap['telegram'], keepBotToken = inputFlag(value.keepBotToken)
    const botToken = keepBotToken ? '' : inputText(value.botToken, false), chatId = inputText(value.chatId)
    if (enabled && (!chatId || (!keepBotToken && !botToken.trim()))) return badInput()
    result = { enabled, chatId, chatName: inputText(value.chatName), keepBotToken, botToken }
  } else if (kind === 'proxy') {
    const value = input as NotificationInputMap['proxy'], keepPassword = inputFlag(value.keepPassword)
    const type = inputText(value.type).toUpperCase(), host = inputText(value.host)
    if (!['HTTP', 'SOCKS5'].includes(type) || ((enabled || purpose === 'test') && !host)
      || /[\s/?#@\\\u0000-\u001f\u007f]/.test(host) || host.includes('://')) return badInput()
    result = { enabled, type, host, port: inputInteger(value.port, 1, 65535), username: inputText(value.username),
      keepPassword, password: keepPassword ? '' : inputText(value.password, false) }
  } else if (kind === 'bark') {
    const value = input as NotificationInputMap['bark'], keepDeviceKey = inputFlag(value.keepDeviceKey)
    const url = httpUrl(inputText(value.url)), deviceKey = keepDeviceKey ? '' : inputText(value.deviceKey, false)
    if (enabled && (!url || (!keepDeviceKey && !deviceKey.trim()))) return badInput()
    result = { enabled, url, keepDeviceKey, deviceKey }
  } else if (kind === 'dingTalk' || kind === 'feishu') {
    const value = input as NotificationInputMap['dingTalk'], keepWebhook = inputFlag(value.keepWebhook), keepSecret = inputFlag(value.keepSecret)
    const webhook = keepWebhook ? '' : httpUrl(inputText(value.webhook)), secret = keepSecret ? '' : inputText(value.secret, false)
    if (enabled && ((!keepWebhook && !webhook) || (kind === 'dingTalk' && !keepSecret && !secret.trim()))) return badInput()
    if (kind === 'dingTalk' && webhook) {
      const parsed = new URL(webhook)
      if (parsed.protocol !== 'https:' || parsed.hostname !== 'oapi.dingtalk.com' || parsed.pathname !== '/robot/send') return badInput()
    }
    result = { enabled, keepWebhook, webhook, keepSecret, secret }
  } else return badInput()
  return result as NotificationInputMap[K]
}
export function notificationResult(kind: NotificationKind | 'bot', action: NotificationResult['action']): NotificationResult {
  return { kind, action, connected: null, notificationAccepted: false, botStarted: false }
}
async function writeEmpty(url: string, payload?: unknown): Promise<void> {
  try { if (await tenantPost(url, payload, writeOptions) !== EMPTY_BODY) return invalid() }
  catch (cause) { const problem = notificationError(cause); throw new NotificationApiError(problem.key, '', true) }
}
export async function saveNotificationConfig<K extends NotificationKind>(kind: K, input: NotificationInputMap[K]): Promise<NotificationResult> {
  const payload = normalizeNotificationInput(kind, input)
  await writeEmpty(`${BASE}/${savePaths[kind]}`, payload)
  return notificationResult(kind, 'save')
}
export async function testNotification(kind: NotificationTestKind, proxyInput?: NotificationInputMap['proxy'], signal?: AbortSignal): Promise<NotificationResult> {
  if (kind === 'proxy') {
    if (!proxyInput) return badInput()
    const normalized = normalizeNotificationInput('proxy', proxyInput, 'test')
    const payload = { type: normalized.type, host: normalized.host, port: normalized.port }
    try {
      const body: unknown = await tenantPost(`${BASE}/testProxyConnection`, payload, { ...readOptions, signal })
      if (!object(body) || typeof body.success !== 'boolean') return invalid()
      return { ...notificationResult(kind, 'test'), connected: body.success }
    } catch (cause) {
      const body: unknown = isAxiosError(cause) ? cause.response?.data : cause
      // The shared interceptor rejects a 200 success:false response. Here it is
      // the actual negative TCP result, not a configuration write failure.
      if (object(body) && body.success === false && typeof body.message === 'string'
        && body.code === undefined && body.errorKey === undefined
        && (!isAxiosError(cause) || cause.response?.status === 200)) {
        return { ...notificationResult(kind, 'test'), connected: false }
      }
      throw notificationError(cause)
    }
  }
  if (!Object.prototype.hasOwnProperty.call(testPaths, kind)) return badInput()
  // These endpoints really send a notification. Never cancel or automatically retry them.
  await writeEmpty(`${BASE}/${testPaths[kind]}`)
  return { ...notificationResult(kind, 'test'), notificationAccepted: true }
}
export async function startNotificationBot(): Promise<NotificationResult> {
  await writeEmpty('/system/startTgRobot')
  return { ...notificationResult('bot', 'start'), botStarted: true }
}
export function notificationError(cause: unknown): NotificationApiError {
  // Keep only fixed keys; response text and request objects may contain tokens or webhook URLs.
  if (cause instanceof NotificationApiError) return new NotificationApiError(cause.key, '', cause.writeAttempted)
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new NotificationApiError('cancelled')
  if (isAxiosError(cause)) {
    if (cause.response?.status === 401) return new NotificationApiError('unauthorized')
    if (cause.response?.status === 403) return new NotificationApiError('forbidden')
    if (cause.response?.status === 404) return new NotificationApiError('notFound')
    if (['ECONNABORTED', 'ETIMEDOUT'].includes(cause.code ?? '')) return new NotificationApiError('timeout')
  }
  return new NotificationApiError('requestFailed')
}
