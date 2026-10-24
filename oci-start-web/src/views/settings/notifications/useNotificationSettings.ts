import { computed, onBeforeUnmount, ref, shallowRef } from 'vue'
import {
  NotificationApiError, loadNotificationSettings, normalizeNotificationInput, notificationError,
  saveNotificationConfig, startNotificationBot, testNotification,
  type NotificationConfigMap, type NotificationInputMap, type NotificationKind,
  type NotificationResult, type NotificationSettings, type NotificationTestKind,
} from '@/api/notificationSettings'

export interface NotificationMutation {
  kind: NotificationKind | 'bot' | null; action: 'save' | 'test' | 'start' | null
  pending: boolean; outcome: 'idle' | 'success' | 'unknown' | 'failed'
  result: NotificationResult | null; problem: NotificationApiError | null
}
function emptyMutation(): NotificationMutation { return { kind: null, action: null, pending: false, outcome: 'idle', result: null, problem: null } }
const secretFields = ['notificationSecret', 'botToken', 'password', 'deviceKey', 'webhook', 'secret'] as const

/** The page owns drafts, confirmation dialogs, route guards and the first read. */
export function useNotificationSettings() {
  const settings = shallowRef<NotificationSettings | null>(null)
  const loading = ref(false), loaded = computed(() => settings.value !== null)
  const problem = shallowRef<NotificationApiError | null>(null), lastUpdated = ref<number | null>(null)
  const mutation = shallowRef<NotificationMutation>(emptyMutation())
  const requiresReview = ref(false), readRevision = ref(0), reviewAfterRevision = ref(0)
  const contextLocked = computed(() => mutation.value.pending)
  const canMutate = computed(() => loaded.value && !loading.value && !problem.value && !contextLocked.value
    && !requiresReview.value && ['idle', 'failed'].includes(mutation.value.outcome))
  const reviewReady = computed(() => requiresReview.value && loaded.value && !loading.value && !problem.value
    && !contextLocked.value && readRevision.value >= reviewAfterRevision.value)
  let disposed = false, readSequence = 0
  let readController: AbortController | undefined, proxyTestController: AbortController | undefined
  const sensitiveSnapshots = new Set<Record<string, unknown>>()
  function release(snapshot: object): void {
    const value = snapshot as Record<string, unknown>
    for (const key of secretFields) if (Object.prototype.hasOwnProperty.call(value, key)) value[key] = ''
    sensitiveSnapshots.delete(value)
  }
  function own(snapshot: object): void { sensitiveSnapshots.add(snapshot as Record<string, unknown>) }
  function cancelRead(): void { ++readSequence; readController?.abort(); readController = undefined; loading.value = false }
  async function load(): Promise<void> {
    if (disposed) return
    cancelRead()
    const sequence = readSequence, controller = new AbortController()
    readController = controller; loading.value = true; problem.value = null
    const current = () => !disposed && sequence === readSequence && readController === controller && !controller.signal.aborted
    try {
      const result = await loadNotificationSettings(controller.signal)
      if (current()) { settings.value = result; lastUpdated.value = Date.now(); ++readRevision.value }
    } catch (cause) { if (current()) problem.value = notificationError(cause) }
    finally { if (current()) { loading.value = false; readController = undefined } }
  }
  async function refresh(): Promise<void> { if (!contextLocked.value) await load() }
  function clearMutation(): void { if (!contextLocked.value) mutation.value = emptyMutation() }
  function acknowledgeReview(): void {
    if (!reviewReady.value) return
    requiresReview.value = false; clearMutation()
  }
  function expectedConfig<K extends NotificationKind>(kind: K, input: NotificationInputMap[K]): NotificationConfigMap[K] {
    const original = settings.value![kind]
    const value = input as unknown as Record<string, unknown>, saved = original as unknown as Record<string, unknown>
    const expected: Record<string, unknown> = {}
    // Only the known redacted baseline keys can enter the comparison snapshot.
    const existence: Record<string, readonly [string, string]> = {
      hasNotificationSecret: ['keepNotificationSecret', 'notificationSecret'], hasBotToken: ['keepBotToken', 'botToken'],
      hasPassword: ['keepPassword', 'password'], hasDeviceKey: ['keepDeviceKey', 'deviceKey'],
      hasWebhook: ['keepWebhook', 'webhook'], hasSecret: ['keepSecret', 'secret'],
    }
    for (const key of Object.keys(saved)) {
      const pair = existence[key]
      const keepEmptyTaskSecret = key === 'hasNotificationSecret' && value.clearNotificationSecret !== true && !value.notificationSecret
      expected[key] = pair ? value[pair[0]] === true || keepEmptyTaskSecret ? saved[key]
        : typeof value[pair[1]] === 'string' && (value[pair[1]] as string).length > 0 : value[key]
    }
    return expected as unknown as NotificationConfigMap[K]
  }
  function matches<K extends NotificationKind>(kind: K, expected: NotificationConfigMap[K]): boolean {
    if (!settings.value) return false
    const current = settings.value[kind]
    return (Object.keys(expected) as (keyof typeof expected)[]).every(key => current[key] === expected[key])
  }
  function validateStoredSecrets<K extends NotificationKind>(kind: K, input: NotificationInputMap[K]): void {
    if (!input.enabled || !settings.value) return
    const original = settings.value[kind] as unknown as Record<string, unknown>
    const value = input as unknown as Record<string, unknown>
    const required: Partial<Record<NotificationKind, readonly string[]>> = {
      telegram: ['BotToken'], bark: ['DeviceKey'], dingTalk: ['Webhook', 'Secret'], feishu: ['Webhook'],
    }
    for (const name of required[kind] ?? []) {
      if (value[`keep${name}`] === true && original[`has${name}`] !== true) throw new NotificationApiError('invalidInput')
    }
  }
  async function perform(kind: NotificationKind | 'bot', action: NotificationMutation['action'],
    send: () => Promise<NotificationResult>, verify?: () => boolean): Promise<void> {
    if (disposed || !canMutate.value) return
    cancelRead()
    mutation.value = { kind, action, pending: true, outcome: 'idle', problem: null, result: null }
    let readBack = false
    try {
      const result = await send()
      if (disposed) return
      mutation.value = { ...mutation.value, outcome: 'success', result }
      readBack = action === 'save'
    } catch (cause) {
      if (disposed) return
      const failure = notificationError(cause)
      mutation.value = { ...mutation.value, outcome: failure.writeAttempted ? 'unknown' : 'failed', problem: failure }
      if (failure.writeAttempted) {
        requiresReview.value = true; reviewAfterRevision.value = readRevision.value + 1; readBack = true
      }
    } finally {
      if (!disposed) {
        if (readBack) {
          await load()
          // A configuration read cannot confirm message delivery or bot runtime state.
          // The UI explicitly asks the user to check those destinations before acknowledgement.
          if (!disposed && mutation.value.outcome === 'success' && !problem.value && verify && !verify()) {
            problem.value = new NotificationApiError('saveMismatch')
          }
        }
        if (!disposed) mutation.value = { ...mutation.value, pending: false }
      }
    }
  }
  async function save<K extends NotificationKind>(kind: K, input: NotificationInputMap[K]): Promise<void> {
    if (!canMutate.value || disposed) return
    let snapshot: NotificationInputMap[K]
    try { snapshot = normalizeNotificationInput(kind, { ...input }); validateStoredSecrets(kind, snapshot) }
    catch (cause) { mutation.value = { ...emptyMutation(), kind, action: 'save', outcome: 'failed', problem: notificationError(cause) }; return }
    own(snapshot)
    const expected = expectedConfig(kind, snapshot)
    try {
      await perform(kind, 'save', async () => {
        try { return await saveNotificationConfig(kind, snapshot) } finally { release(snapshot) }
      }, () => matches(kind, expected))
    } finally { release(snapshot) }
  }
  async function test(kind: NotificationTestKind, input?: NotificationInputMap['proxy']): Promise<void> {
    if (!canMutate.value || disposed) return
    if (kind !== 'proxy') { await perform(kind, 'test', () => testNotification(kind)); return }
    let snapshot: NotificationInputMap['proxy']
    try {
      if (!input) throw new NotificationApiError('invalidInput')
      // TCP probing does not use a password, username or saved enable switch.
      snapshot = normalizeNotificationInput('proxy', { ...input, password: '', keepPassword: false }, 'test')
    } catch (cause) { mutation.value = { ...emptyMutation(), kind, action: 'test', outcome: 'failed', problem: notificationError(cause) }; return }
    const controller = new AbortController()
    proxyTestController = controller
    try { await perform(kind, 'test', () => testNotification(kind, snapshot, controller.signal)) }
    finally { if (proxyTestController === controller) proxyTestController = undefined }
  }
  async function startBot(): Promise<void> { await perform('bot', 'start', startNotificationBot) }
  onBeforeUnmount(() => {
    disposed = true; cancelRead(); proxyTestController?.abort(); proxyTestController = undefined
    for (const snapshot of sensitiveSnapshots) release(snapshot)
    settings.value = null; mutation.value = emptyMutation()
  })
  return { settings, loading, loaded, problem, lastUpdated, refresh, mutation, canMutate, contextLocked,
    requiresReview, reviewReady, acknowledgeReview, clearMutation, save, test, startBot }
}
