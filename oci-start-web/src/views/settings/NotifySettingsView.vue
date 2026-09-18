<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { normalizeNotificationInput, type NotificationApiError, type NotificationInputMap,
  type NotificationKind } from '@/api/notificationSettings'
import SecuritySecretInput from './security/SecuritySecretInput.vue'
import TelegramAiDialog from './notifications/TelegramAiDialog.vue'
import { useNotificationSettings } from './notifications/useNotificationSettings'
import './notifications/notification-settings.scss'

type SecretMode = 'keep' | 'replace' | 'clear'
type SecretField = { key: string; keep: string; has: string; optional?: boolean }
type Confirmation = { action: 'save' | 'test' | 'start'; kind: NotificationKind | 'bot' }
const sections: { id: NotificationKind; icon: string }[] = [
  { id: 'task', icon: 'i-mdi-calendar-clock-outline' }, { id: 'telegram', icon: 'i-mdi-send-outline' },
  { id: 'proxy', icon: 'i-mdi-server-network-outline' }, { id: 'bark', icon: 'i-mdi-cellphone-message' },
  { id: 'dingTalk', icon: 'i-mdi-bell-outline' }, { id: 'feishu', icon: 'i-mdi-message-outline' },
]
const secretFields: Record<NotificationKind, SecretField[]> = {
  task: [{ key: 'notificationSecret', keep: 'keepNotificationSecret', has: 'hasNotificationSecret', optional: true }],
  telegram: [{ key: 'botToken', keep: 'keepBotToken', has: 'hasBotToken' }],
  proxy: [{ key: 'password', keep: 'keepPassword', has: 'hasPassword', optional: true }],
  bark: [{ key: 'deviceKey', keep: 'keepDeviceKey', has: 'hasDeviceKey' }],
  dingTalk: [{ key: 'webhook', keep: 'keepWebhook', has: 'hasWebhook' }, { key: 'secret', keep: 'keepSecret', has: 'hasSecret' }],
  feishu: [{ key: 'webhook', keep: 'keepWebhook', has: 'hasWebhook' }, { key: 'secret', keep: 'keepSecret', has: 'hasSecret', optional: true }],
}
const { t, locale } = useI18n()
const router = useRouter(), page = useNotificationSettings()
const { settings, loading, loaded, problem, lastUpdated, mutation, canMutate, contextLocked, requiresReview, reviewReady } = page
const active = ref<NotificationKind>('task'), aiOpen = ref(false)
const formHeading = ref<HTMLElement>(), scrollArea = ref<HTMLElement>()
const drafts = reactive<NotificationInputMap>({
  task: { enabled: false, executeHour: 9, enableAccountCheck: false, enableBootLog: false, enableCostCheck: false,
    notificationSecret: '', keepNotificationSecret: false, clearNotificationSecret: false },
  telegram: { enabled: false, chatId: '', chatName: '', botToken: '', keepBotToken: false },
  proxy: { enabled: false, type: 'HTTP', host: '', port: 7890, username: '', password: '', keepPassword: false },
  bark: { enabled: false, url: '', deviceKey: '', keepDeviceKey: false },
  dingTalk: { enabled: false, webhook: '', keepWebhook: false, secret: '', keepSecret: false },
  feishu: { enabled: false, webhook: '', keepWebhook: false, secret: '', keepSecret: false },
})
const modes = reactive<Record<NotificationKind, Record<string, SecretMode>>>({ task: {}, telegram: {}, proxy: {}, bark: {}, dingTalk: {}, feishu: {} })
// Baselines contain only public settings, existence flags and empty secret drafts.
const baseline = reactive<Record<NotificationKind, string>>({ task: '', telegram: '', proxy: '', bark: '', dingTalk: '', feishu: '' })
const confirmation = ref<Confirmation | null>(null), validation = ref(''), discardVisible = ref(false)
let discardAction: (() => void) | undefined, cancelNavigation: (() => void) | undefined
let disposed = false
function snapshot(kind: NotificationKind) { return JSON.stringify({ ...drafts[kind], modes: modes[kind] }) }
const dirty = computed(() => loaded.value && snapshot(active.value) !== baseline[active.value])
const navigationLocked = computed(() => contextLocked.value || !!confirmation.value || aiOpen.value)
const disabled = computed(() => !loaded.value || loading.value || navigationLocked.value || requiresReview.value || !!problem.value)
const enabled = computed({ get: () => drafts[active.value].enabled, set: (value: boolean) => { drafts[active.value].enabled = value } })
const currentSecrets = computed(() => secretFields[active.value])
const storedTestReady = computed(() => {
  const saved = settings.value
  if (!saved || dirty.value) return false
  if (active.value === 'telegram') return !!saved.telegram.chatId && saved.telegram.hasBotToken
  if (active.value === 'bark') return !!saved.bark.url && saved.bark.hasDeviceKey
  if (active.value === 'dingTalk') return saved.dingTalk.hasWebhook && saved.dingTalk.hasSecret
  if (active.value === 'feishu') return saved.feishu.hasWebhook
  return false
})
const updatedLabel = computed(() => lastUpdated.value ? t('notificationSettings.lastUpdated', {
  time: new Intl.DateTimeFormat(locale.value, { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(lastUpdated.value),
}) : t('notificationSettings.notLoaded'))
const successLabel = computed(() => {
  const result = mutation.value.result
  return t(`notificationSettings.${result?.action === 'save' ? 'saved' : result?.action === 'start' ? 'botStarted'
    : result?.kind === 'proxy' ? result.connected ? 'portReachable' : 'portUnreachable' : 'testAccepted'}`)
})
const unknownKey = computed(() => mutation.value.action === 'save' ? 'unknownSave' : mutation.value.action === 'start' ? 'unknownBot' : 'unknownTest')
const confirmTitle = computed(() => {
  const value = confirmation.value
  if (!value) return ''
  if (value.action === 'start') return t('notificationSettings.confirmBotTitle')
  if (value.action === 'test' && value.kind === 'proxy') return t('notificationSettings.confirmProxyTitle')
  return t(`notificationSettings.${value.action === 'save' ? 'confirmSaveTitle' : 'confirmTestTitle'}`, { section: t(`notificationSettings.sections.${value.kind}`) })
})
const confirmHint = computed(() => confirmation.value?.action === 'start' ? t('notificationSettings.confirmBot')
  : confirmation.value?.action === 'save' ? t('notificationSettings.confirmSave')
    : confirmation.value?.kind === 'proxy' ? t('notificationSettings.confirmProxy', { host: drafts.proxy.host.trim(), port: drafts.proxy.port })
      : t('notificationSettings.confirmTest'))
const clearsSecret = computed(() => confirmation.value?.action === 'save' && currentSecrets.value.some(field => modeOf(field) === 'clear'))
function errorLabel(error: NotificationApiError | null) { return error ? t(`notificationSettings.errors.${error.key}`) : '' }
function hasSaved(field: SecretField, kind = active.value): boolean {
  const saved = settings.value?.[kind] as unknown as Record<string, unknown> | undefined
  return saved?.[field.has] === true
}
function modeOf(field: SecretField): SecretMode { return modes[active.value][field.key] ?? 'replace' }
function secretValue(field: SecretField): string {
  const value = (drafts[active.value] as unknown as Record<string, unknown>)[field.key]
  return typeof value === 'string' ? value : ''
}
function updateSecret(field: SecretField, value: string) { Object.assign(drafts[active.value], { [field.key]: value }) }
function updateMode(field: SecretField, value: unknown) {
  if (disabled.value || typeof value !== 'string' || !['keep', 'replace', 'clear'].includes(value)) return
  modes[active.value][field.key] = value as SecretMode
  Object.assign(drafts[active.value], { [field.key]: '', [field.keep]: value === 'keep' })
  if (active.value === 'task') drafts.task.clearNotificationSecret = value === 'clear'
  validation.value = ''
}
function clearSecrets(kind?: NotificationKind) {
  for (const section of kind ? [kind] : sections.map(item => item.id)) {
    for (const field of secretFields[section]) Object.assign(drafts[section], { [field.key]: '' })
  }
}
function resetSection(kind: NotificationKind) {
  if (!settings.value) return
  Object.assign(drafts[kind], settings.value[kind])
  for (const field of secretFields[kind]) {
    const keep = hasSaved(field, kind)
    Object.assign(drafts[kind], { [field.key]: '', [field.keep]: keep })
    modes[kind][field.key] = keep ? 'keep' : 'replace'
  }
  if (kind === 'task') drafts.task.clearNotificationSecret = false
  baseline[kind] = snapshot(kind)
}
function resetAll() { clearSecrets(); sections.forEach(section => resetSection(section.id)); validation.value = '' }
async function refresh() { await page.refresh(); if (!disposed && !problem.value) resetAll() }
function requestDiscard(action: () => void, onCancel?: () => void) {
  if (discardVisible.value) { onCancel?.(); return }
  discardAction = action; cancelNavigation = onCancel; discardVisible.value = true
}
function cancelDiscard() {
  discardVisible.value = false; discardAction = undefined
  const cancel = cancelNavigation; cancelNavigation = undefined; cancel?.()
}
function acceptDiscard() {
  const action = discardAction; discardAction = undefined; cancelNavigation = undefined
  discardVisible.value = false; resetAll(); action?.()
}
function requestRefresh() {
  if (navigationLocked.value) return
  if (dirty.value) requestDiscard(() => { void refresh() })
  else void refresh()
}
async function activate(kind: NotificationKind) {
  resetAll(); active.value = kind
  if (!requiresReview.value) page.clearMutation()
  await nextTick()
  if (scrollArea.value) scrollArea.value.scrollTop = 0
  formHeading.value?.focus({ preventScroll: true })
}
function selectSection(kind: NotificationKind) {
  if (kind === active.value || navigationLocked.value) return
  if (dirty.value) requestDiscard(() => { void activate(kind) })
  else void activate(kind)
}
function back() { if (window.history.state?.back) router.back(); else void router.push('/boot/dashboard') }
function acknowledge() { if (reviewReady.value) { resetAll(); page.acknowledgeReview() } }
function prepare(action: Confirmation['action']) {
  if (!canMutate.value || navigationLocked.value) return
  const kind = active.value
  validation.value = ''
  if (action === 'save') {
    if (!dirty.value) return
    // Replacing an existing value with an empty input must use the explicit clear option.
    if (currentSecrets.value.some(field => modeOf(field) === 'replace' && hasSaved(field)
      && !(kind === 'proxy' && field.key === 'password' ? secretValue(field) : secretValue(field).trim()))) {
      validation.value = 'input'; return
    }
    try { normalizeNotificationInput(kind, drafts[kind]) } catch { validation.value = 'input'; return }
  } else if (action === 'test') {
    if (kind === 'task') return
    if (kind === 'proxy') {
      try { normalizeNotificationInput('proxy', { ...drafts.proxy, password: '', keepPassword: false }, 'test') }
      catch { validation.value = 'proxy'; return }
    } else if (!storedTestReady.value) return
  } else if (kind !== 'telegram' || !storedTestReady.value || !settings.value?.telegram.enabled) return
  confirmation.value = { action, kind: action === 'start' ? 'bot' : kind }
}
function prepareSave() { prepare('save') }
function closeConfirmation() { if (!contextLocked.value) confirmation.value = null }
async function submit() {
  const value = confirmation.value
  if (!value || !canMutate.value) return
  if (value.action === 'save' && value.kind !== 'bot') await page.save(value.kind, drafts[value.kind])
  else if (value.action === 'start') await page.startBot()
  else if (value.kind !== 'bot' && value.kind !== 'task') await page.test(value.kind, value.kind === 'proxy' ? drafts.proxy : undefined)
  if (disposed) return
  confirmation.value = null
  if (value.action === 'save' && value.kind !== 'bot') {
    clearSecrets(value.kind)
    if (['success', 'unknown'].includes(mutation.value.outcome) && (!problem.value || problem.value.key === 'saveMismatch')) resetSection(value.kind)
  }
  if (scrollArea.value) scrollArea.value.scrollTop = 0
}
function openAi() {
  if (navigationLocked.value || requiresReview.value || loading.value) return
  const open = () => { aiOpen.value = true }
  if (dirty.value) requestDiscard(open)
  else open()
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (dirty.value || contextLocked.value || requiresReview.value || aiOpen.value) { event.preventDefault(); event.returnValue = '' }
}
watch(() => [drafts.proxy.type, drafts.proxy.host, drafts.proxy.port], () => {
  // A result for the previous destination must not describe an edited address.
  if (mutation.value.kind === 'proxy' && mutation.value.action === 'test' && !contextLocked.value) page.clearMutation()
})
onBeforeRouteLeave(() => {
  if (navigationLocked.value || requiresReview.value) return false
  if (!dirty.value) return true
  return new Promise<boolean>(resolve => requestDiscard(() => resolve(true), () => resolve(false)))
})
onMounted(() => { window.addEventListener('beforeunload', beforeUnload); void refresh() })
onBeforeUnmount(() => {
  disposed = true; clearSecrets(); cancelNavigation?.(); discardAction = undefined; cancelNavigation = undefined
  window.removeEventListener('beforeunload', beforeUnload)
})
</script>

<template>
  <section class="notification-settings" :aria-label="t('notificationSettings.title')">
    <header class="notification-toolbar" data-page-error-anchor>
      <PageBackButton :disabled="navigationLocked || requiresReview" @click="back" />
      <span class="notification-read-time">{{ loading ? t('notificationSettings.loading') : updatedLabel }}</span>
      <GhostBtn :loading="loading" :disabled="navigationLocked" @click="requestRefresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('notificationSettings.refresh') }}</GhostBtn>
    </header>
    <div class="notification-workspace">
      <nav class="notification-nav" :aria-label="t('notificationSettings.title')">
        <button v-for="section in sections" :key="section.id" type="button" :class="{ 'is-active': active === section.id }"
          :aria-current="active === section.id ? 'page' : undefined" :disabled="navigationLocked" @click="selectSection(section.id)">
          <i :class="section.icon" aria-hidden="true" /><span>{{ t(`notificationSettings.sections.${section.id}`) }}</span>
        </button>
      </nav>
      <div class="notification-content">
        <div ref="scrollArea" class="notification-scroll">
          <div v-if="requiresReview" class="notification-notice is-warning" role="alert">
            <p>{{ t(`notificationSettings.${unknownKey}`) }}</p>
            <p>{{ t(`notificationSettings.${mutation.action === 'save' ? 'reviewSaveHint' : mutation.action === 'start' ? 'reviewBotHint' : 'reviewTestHint'}`) }}</p>
            <div class="notification-actions"><GhostBtn :loading="loading" :disabled="navigationLocked" @click="requestRefresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('notificationSettings.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady" @click="acknowledge"><i class="i-mdi-check" aria-hidden="true" />{{ t('notificationSettings.reviewed') }}</GhostBtn></div>
          </div>
          <PageErrorNotice v-else-if="mutation.outcome === 'success' && !contextLocked && mutation.result?.connected === false"><p>{{ successLabel }}</p><GhostBtn @click="page.clearMutation">{{ t('notificationSettings.dismiss') }}</GhostBtn></PageErrorNotice>
          <div v-else-if="mutation.outcome === 'success' && !contextLocked" class="notification-notice" role="status">
            <p>{{ successLabel }}</p><GhostBtn @click="page.clearMutation">{{ t('notificationSettings.dismiss') }}</GhostBtn>
          </div>
          <PageErrorNotice v-if="problem">{{ errorLabel(problem) }} {{ loaded ? t('notificationSettings.retained') : '' }}</PageErrorNotice>
          <PageErrorNotice v-if="mutation.outcome === 'failed'">{{ errorLabel(mutation.problem) }}</PageErrorNotice>
          <div class="notification-section-title">
            <div><h2 ref="formHeading" tabindex="-1">{{ t(`notificationSettings.sections.${active}`) }}</h2><p>{{ t(`notificationSettings.descriptions.${active}`) }}</p></div>
            <label class="notification-toggle"><span>{{ loaded ? t(`notificationSettings.${enabled ? 'enabled' : 'disabled'}`) : '—' }}</span><input v-model="enabled" type="checkbox" role="switch" :aria-label="t('notificationSettings.enable')" :disabled="disabled" /><span class="notification-switch" aria-hidden="true" /></label>
          </div>
          <form id="notification-settings-form" class="notification-form" :aria-busy="loading || contextLocked" @submit.prevent="prepareSave">
            <fieldset :disabled="disabled">
              <template v-if="active === 'task'">
                <div class="notification-pair">
                  <div class="notification-field"><label for="notification-hour">{{ t('notificationSettings.executeHour') }}</label><el-select id="notification-hour" v-model="drafts.task.executeHour" :disabled="disabled" :teleported="true"><el-option v-for="hour in 24" :key="hour" :value="hour - 1" :label="t('notificationSettings.hour', { hour: String(hour - 1).padStart(2, '0') })" /></el-select></div>
                  <div class="notification-field"><span class="notification-label">{{ t('notificationSettings.timeZone') }}</span><span class="notification-value">{{ settings?.serverTimeZone || '—' }}</span></div>
                </div>
                <div class="notification-field"><span class="notification-label" id="notification-task-items">{{ t('notificationSettings.taskItems') }}</span>
                  <div class="notification-checks" role="group" aria-labelledby="notification-task-items">
                    <label><input v-model="drafts.task.enableAccountCheck" type="checkbox" /><span>{{ t('notificationSettings.accountCheck') }}</span></label>
                    <label><input v-model="drafts.task.enableBootLog" type="checkbox" /><span>{{ t('notificationSettings.bootLog') }}</span></label>
                    <label><input v-model="drafts.task.enableCostCheck" type="checkbox" /><span>{{ t('notificationSettings.costCheck') }}</span></label>
                  </div><small>{{ t('notificationSettings.taskHint') }}</small>
                </div>
              </template>
              <template v-else-if="active === 'telegram'">
                <div class="notification-field"><label for="notification-chat-id">{{ t('notificationSettings.chatId') }}</label><input id="notification-chat-id" v-model="drafts.telegram.chatId" type="text" autocomplete="off" autocapitalize="off" :spellcheck="false" /><small>{{ t('notificationSettings.chatIdHint') }}</small></div>
                <div class="notification-field"><label for="notification-chat-name">{{ t('notificationSettings.chatName') }}</label><input id="notification-chat-name" v-model="drafts.telegram.chatName" type="text" autocomplete="off" :spellcheck="false" /></div>
              </template>
              <template v-else-if="active === 'proxy'">
                <div class="notification-field"><label for="notification-proxy-type">{{ t('notificationSettings.proxyType') }}</label><el-select id="notification-proxy-type" v-model="drafts.proxy.type" :disabled="disabled" :teleported="true"><el-option v-if="!['HTTP', 'SOCKS5'].includes(drafts.proxy.type)" :value="drafts.proxy.type" :label="drafts.proxy.type" disabled /><el-option value="HTTP" label="HTTP" /><el-option value="SOCKS5" label="SOCKS5" /></el-select></div>
                <div class="notification-pair notification-host-port">
                  <div class="notification-field"><label for="notification-proxy-host">{{ t('notificationSettings.proxyHost') }}</label><input id="notification-proxy-host" v-model="drafts.proxy.host" type="text" autocomplete="off" autocapitalize="off" :spellcheck="false" placeholder="127.0.0.1" /></div>
                  <div class="notification-field"><label for="notification-proxy-port">{{ t('notificationSettings.proxyPort') }}</label><input id="notification-proxy-port" v-model.number="drafts.proxy.port" type="number" min="1" max="65535" step="1" inputmode="numeric" /></div>
                </div>
                <div class="notification-field"><label for="notification-proxy-username">{{ t('notificationSettings.proxyUsername') }}</label><input id="notification-proxy-username" v-model="drafts.proxy.username" type="text" autocomplete="off" autocapitalize="off" :spellcheck="false" /></div>
              </template>
              <div v-else-if="active === 'bark'" class="notification-field"><label for="notification-bark-url">{{ t('notificationSettings.barkUrl') }}</label><input id="notification-bark-url" v-model="drafts.bark.url" type="url" autocomplete="off" autocapitalize="off" :spellcheck="false" placeholder="https://api.day.app" /><small>{{ t('notificationSettings.barkHint') }}</small></div>
              <div v-for="field in currentSecrets" :key="`${active}-${field.key}`" class="notification-secret">
                <div class="notification-field">
                  <label :for="`notification-mode-${field.key}`">{{ t(`notificationSettings.${field.key}`) }}<span v-if="field.optional">{{ t('notificationSettings.optional') }}</span></label>
                  <el-select :id="`notification-mode-${field.key}`" :model-value="modeOf(field)" :disabled="disabled" :teleported="true" :aria-label="`${t(`notificationSettings.${field.key}`)} · ${t('notificationSettings.secretMode')}`" @update:model-value="updateMode(field, $event)">
                    <el-option v-if="hasSaved(field)" value="keep" :label="t('notificationSettings.keepSecret')" /><el-option value="replace" :label="t('notificationSettings.replaceSecret')" /><el-option v-if="hasSaved(field)" value="clear" :disabled="enabled && !field.optional" :label="t('notificationSettings.clearSecret')" />
                  </el-select>
                  <small v-if="modeOf(field) !== 'replace'">{{ t(`notificationSettings.${modeOf(field) === 'clear' ? 'clearHint' : 'keepHint'}`) }}</small>
                </div>
                <SecuritySecretInput v-if="modeOf(field) === 'replace'" :id="`notification-secret-${field.key}`" :model-value="secretValue(field)" :disabled="disabled"
                  :label="t('notificationSettings.newValue', { field: t(`notificationSettings.${field.key}`) })" @update:model-value="updateSecret(field, $event)" />
              </div>
            </fieldset>
            <p v-if="validation" class="notification-error" role="alert">{{ t(`notificationSettings.validation.${validation}`) }}</p>
          </form>
          <div v-if="active !== 'task'" class="notification-tools">
            <div class="notification-actions">
              <GhostBtn :disabled="!canMutate || navigationLocked || (active !== 'proxy' && !storedTestReady)" @click="prepare('test')"><i :class="active === 'proxy' ? 'i-mdi-lan-connect' : 'i-mdi-send-outline'" aria-hidden="true" />{{ t(`notificationSettings.${active === 'proxy' ? 'testProxy' : 'test'}`) }}</GhostBtn>
              <template v-if="active === 'telegram'">
                <GhostBtn :disabled="!canMutate || navigationLocked || !storedTestReady || !settings?.telegram.enabled" @click="prepare('start')"><i class="i-mdi-restart" aria-hidden="true" />{{ t('notificationSettings.startBot') }}</GhostBtn>
                <GhostBtn :disabled="navigationLocked || requiresReview || loading" @click="openAi"><i class="i-mdi-creation-outline" aria-hidden="true" />{{ t('notificationSettings.aiConfig') }}</GhostBtn>
              </template>
            </div>
            <p class="notification-help">{{ t(`notificationSettings.${active === 'proxy' ? 'proxyHint' : dirty ? 'savedConfigRequired' : active === 'telegram' ? 'telegramTestHint' : 'testHint'}`) }}</p>
          </div>
        </div>
        <footer class="notification-footer"><span role="status">{{ contextLocked ? t('notificationSettings.submitting') : dirty ? t('notificationSettings.dirty') : '' }}</span><PrimaryBtn type="submit" form="notification-settings-form" :loading="contextLocked && mutation.action === 'save'" :disabled="!canMutate || !dirty || navigationLocked"><i class="i-mdi-check" aria-hidden="true" />{{ t('notificationSettings.save') }}</PrimaryBtn></footer>
      </div>
    </div>
    <el-dialog :model-value="!!confirmation" class="notification-confirm-dialog" :title="confirmTitle" width="520px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!contextLocked" :show-close="!contextLocked" :before-close="closeConfirmation">
      <p>{{ confirmHint }}</p><p v-if="clearsSecret" class="notification-confirm-warning">{{ t('notificationSettings.confirmClear') }}</p><p v-if="contextLocked" role="status">{{ t('notificationSettings.submitting') }}</p>
      <template #footer><GhostBtn :disabled="contextLocked" @click="closeConfirmation">{{ t('notificationSettings.cancel') }}</GhostBtn><PrimaryBtn :loading="contextLocked" :disabled="!canMutate" @click="submit">{{ t('notificationSettings.confirm') }}</PrimaryBtn></template>
    </el-dialog>
    <el-dialog :model-value="discardVisible" class="notification-confirm-dialog" :title="t('notificationSettings.discardTitle')" width="480px" append-to-body :close-on-click-modal="false" :before-close="cancelDiscard">
      <p>{{ t('notificationSettings.discardHint') }}</p><template #footer><GhostBtn @click="cancelDiscard">{{ t('notificationSettings.keepEditing') }}</GhostBtn><PrimaryBtn @click="acceptDiscard">{{ t('notificationSettings.discard') }}</PrimaryBtn></template>
    </el-dialog>
    <TelegramAiDialog v-model="aiOpen" :disabled="contextLocked" />
  </section>
</template>
