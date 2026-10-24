<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  emailError, isEmailWriteUncertain, listEmailContacts, listEmailTenants, sendEmail,
  type EmailContact, type EmailTenantConfig,
} from '@/api/email'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{ 'update:modelValue': [value: boolean]; sent: []; busy: [value: boolean] }>()
const { t, n } = useI18n()
type Failure = ReturnType<typeof emailError>
type SendState = 'draft' | 'sending' | 'processed' | 'uncertain' | 'failed'
const subject = ref('')
const content = ref('')
const senderId = ref('')
const chosenSender = ref<EmailTenantConfig | null>(null)
const sendState = ref<SendState>('draft')
const sendFailure = ref<Failure | null>(null)
const reviewed = ref(false)
const draftSelectionUpdated = ref(false)
const resultElement = ref<HTMLElement | null>(null)
const validation = ref({ subject: '', content: '', sender: '', recipients: '' })
const sending = computed(() => sendState.value === 'sending')
const locked = computed(() => sendState.value !== 'draft')
const hasResult = computed(() => ['processed', 'uncertain', 'failed'].includes(sendState.value))

const senders = ref<EmailTenantConfig[]>([])
const senderPage = ref(0)
const senderPages = ref(0)
const senderTotal = ref(0)
const senderLoading = ref(false)
const senderFailure = ref<Failure | null>(null)
const senderOptions = computed(() => chosenSender.value && !senders.value.some((row) => row.id === chosenSender.value?.id)
  ? [chosenSender.value, ...senders.value] : senders.value)
let senderRetryPage = 1
let senderRevision = 0
let senderController: AbortController | undefined

const contacts = ref<EmailContact[]>([])
const contactPage = ref(1)
const contactTotal = ref(0)
const contactPageSize = 10
const contactLoading = ref(false)
const contactFailure = ref<Failure | null>(null)
const searchField = ref<'name' | 'email'>('name')
const searchText = ref('')
let appliedSearch: { name?: string; email?: string } = {}
const selected = ref(new Map<string, EmailContact>())
const selectedContacts = computed(() => [...selected.value.values()])
const showSelected = ref(false)
let contactRetryPage = 1
let contactRevision = 0
let contactController: AbortController | undefined

const collecting = ref(false)
const collected = ref(0)
const collectTotal = ref<number | null>(null)
const collectFailure = ref<Failure | null>(null)
const collectionChanged = ref(false)
const contactLocked = computed(() => locked.value || collecting.value)
let collectionRevision = 0
let collectionController: AbortController | undefined
let disposed = false

function failureText(failure: Failure | null) {
  if (!failure) return ''
  return failure.detail || t(`emailCompose.errors.${failure.key}`)
}
function senderLabel(row: EmailTenantConfig) {
  const owner = row.tenantName || row.tenantId
  const status = row.active === false ? t('emailCompose.inactive') : row.active === null ? t('emailCompose.unknownState') : ''
  return [row.senderEmail || row.domainName || row.id, owner, status].filter(Boolean).join(' · ')
}
function displayCount(value: number | null) { return value === null ? '—' : n(value) }
function changeSender(value: string) {
  senderId.value = value
  chosenSender.value = senderOptions.value.find((row) => row.id === value) || null
  validation.value.sender = ''
}

async function loadSenders(page = 1) {
  senderController?.abort()
  const revision = ++senderRevision
  const controller = new AbortController()
  senderController = controller
  senderRetryPage = page
  senderLoading.value = true
  senderFailure.value = null
  try {
    const result = await listEmailTenants({ pageNum: page, pageSize: 20, sort: 'id', order: 'asc' }, controller.signal)
    if (disposed || revision !== senderRevision || !props.modelValue) return
    const rows = new Map<string, EmailTenantConfig>((page === 1 ? [] : senders.value).map((row) => [row.id, row]))
    for (const row of result.content) rows.set(row.id, row)
    senders.value = [...rows.values()]
    senderPage.value = result.number + 1
    senderPages.value = result.totalPages
    senderTotal.value = result.totalElements
    const current = result.content.find((row) => row.id === senderId.value)
    if (current) chosenSender.value = current
  } catch (cause) {
    if (!disposed && revision === senderRevision && !controller.signal.aborted) senderFailure.value = emailError(cause)
  } finally {
    if (!disposed && revision === senderRevision) senderLoading.value = false
  }
}

async function loadContacts(page = 1): Promise<void> {
  contactController?.abort()
  const revision = ++contactRevision
  const controller = new AbortController()
  contactController = controller
  contactRetryPage = page
  contactLoading.value = true
  contactFailure.value = null
  try {
    const result = await listEmailContacts({ pageNum: page, pageSize: contactPageSize, sort: 'id', order: 'asc', ...appliedSearch }, controller.signal)
    if (disposed || revision !== contactRevision || !props.modelValue) return
    if (page > 1 && !result.content.length && result.number >= result.totalPages) {
      await loadContacts(Math.max(1, result.totalPages))
      return
    }
    contacts.value = result.content
    contactPage.value = result.number + 1
    contactTotal.value = result.totalElements
    for (const row of result.content) if (selected.value.has(row.id)) selected.value.set(row.id, row)
  } catch (cause) {
    if (!disposed && revision === contactRevision && !controller.signal.aborted) contactFailure.value = emailError(cause)
  } finally {
    if (!disposed && revision === contactRevision) contactLoading.value = false
  }
}
function searchContacts(reset = false) {
  if (contactLocked.value) return
  if (reset) searchText.value = ''
  appliedSearch = searchText.value.trim() ? { [searchField.value]: searchText.value.trim() } : {}
  void loadContacts(1)
}
function toggleContact(row: EmailContact) {
  if (contactLocked.value) return
  if (selected.value.has(row.id)) selected.value.delete(row.id)
  else selected.value.set(row.id, row)
  validation.value.recipients = ''
}
function selectPage() {
  if (contactLocked.value || contactLoading.value || contactFailure.value) return
  for (const row of contacts.value) selected.value.set(row.id, row)
  validation.value.recipients = ''
}
function clearRecipients() {
  if (contactLocked.value) return
  selected.value = new Map()
  showSelected.value = false
  validation.value.recipients = ''
}
function cancelCollection() {
  ++collectionRevision
  collectionController?.abort()
  collecting.value = false
}

// The parent calls these only after a deletion on this page is confirmed.
// Invalidate reads so an older page or in-progress full selection cannot restore it.
function removeContact(id: string) {
  if (sending.value || disposed) return
  ++contactRevision
  contactController?.abort()
  contactLoading.value = false
  cancelCollection()
  if (selected.value.delete(id)) {
    draftSelectionUpdated.value = true
    validation.value.recipients = ''
  }
  contacts.value = contacts.value.filter((row) => row.id !== id)
  if (!selected.value.size) showSelected.value = false
}
function removeSender(id: string) {
  if (sending.value || disposed) return
  ++senderRevision
  senderController?.abort()
  senderLoading.value = false
  if (senderId.value === id || chosenSender.value?.id === id) {
    senderId.value = ''
    chosenSender.value = null
    validation.value.sender = ''
    draftSelectionUpdated.value = true
  }
  senders.value = senders.value.filter((row) => row.id !== id)
}
defineExpose({ removeContact, removeSender })

async function selectAllContacts() {
  if (contactLocked.value || contactLoading.value) return
  const revision = ++collectionRevision
  const controller = new AbortController()
  collectionController = controller
  collecting.value = true
  collected.value = 0
  collectTotal.value = null
  collectFailure.value = null
  collectionChanged.value = false
  const changed = Symbol('contactsChanged')
  const all = new Map<string, EmailContact>()
  let expectedTotal: number | undefined
  let expectedPages: number | undefined
  try {
    // Keep the existing selection until every real page has been read. Sorting by
    // the unique ID also avoids ties at page boundaries during this traversal.
    for (let page = 1; ; page++) {
      const result = await listEmailContacts({ pageNum: page, pageSize: 100, sort: 'id', order: 'asc' }, controller.signal)
      if (disposed || revision !== collectionRevision || !props.modelValue) return
      if (expectedTotal === undefined) {
        expectedTotal = result.totalElements
        expectedPages = result.totalPages
        collectTotal.value = expectedTotal
      }
      if (result.number !== page - 1 || result.totalElements !== expectedTotal || result.totalPages !== expectedPages) throw changed
      for (const row of result.content) {
        if (all.has(row.id)) throw changed
        all.set(row.id, row)
      }
      collected.value = all.size
      if (page >= result.totalPages) break
      if (!result.content.length) throw changed
    }
    if (all.size !== expectedTotal) throw changed
    selected.value = all
    validation.value.recipients = ''
  } catch (cause) {
    if (!disposed && revision === collectionRevision && !controller.signal.aborted) {
      if (cause === changed) collectionChanged.value = true
      else collectFailure.value = emailError(cause)
    }
  } finally {
    if (!disposed && revision === collectionRevision) collecting.value = false
  }
}

function stopReads() {
  ++senderRevision
  ++contactRevision
  senderController?.abort()
  contactController?.abort()
  senderLoading.value = false
  contactLoading.value = false
  cancelCollection()
}
function close() {
  if (sending.value) return
  stopReads()
  emit('update:modelValue', false)
}
function beforeClose(done: () => void) {
  if (sending.value) return
  stopReads()
  done()
}
function onVisibility(value: boolean) {
  if (!value) close()
}
function resumeDraft() {
  if (!reviewed.value || !hasResult.value) return
  sendState.value = 'draft'
  sendFailure.value = null
  reviewed.value = false
  void loadSenders(1)
  void loadContacts(contactPage.value)
}
async function submit() {
  if (locked.value || collecting.value || senderLoading.value || contactLoading.value || disposed) return
  validation.value = {
    subject: subject.value.trim() ? '' : 'subject',
    content: content.value.trim() ? '' : 'content',
    sender: !senderId.value || !chosenSender.value ? 'sender' : chosenSender.value.active === false ? 'inactive' : '',
    recipients: selected.value.size ? '' : 'recipients',
  }
  if (Object.values(validation.value).some(Boolean)) return
  const input = {
    title: subject.value.trim(), content: content.value.trim(), tenantEmailConfigId: senderId.value,
    emailReceiveIds: [...selected.value.keys()],
  }
  stopReads()
  draftSelectionUpdated.value = false
  sendState.value = 'sending'
  sendFailure.value = null
  reviewed.value = false
  emit('busy', true)
  try {
    // This synchronous endpoint can send partially before failing and has no
    // idempotency key or cancellation endpoint. Never abort or retry the write.
    await sendEmail(input)
    if (!disposed) sendState.value = 'processed'
  } catch (cause) {
    if (!disposed) {
      sendFailure.value = emailError(cause)
      sendState.value = isEmailWriteUncertain(cause) ? 'uncertain' : 'failed'
    }
  } finally {
    if (!disposed) {
      emit('busy', false)
      // Records may exist even when the response failed, including partial sends.
      emit('sent')
    }
  }
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (!sending.value) return
  event.preventDefault()
  event.returnValue = ''
}
window.addEventListener('beforeunload', beforeUnload)
watch(sendState, async (state) => {
  if (state === 'draft') return
  await nextTick()
  if (!disposed && props.modelValue) resultElement.value?.scrollIntoView({ block: 'nearest' })
})
watch(() => props.modelValue, (open) => {
  if (!open) {
    stopReads()
    return
  }
  reviewed.value = false
  if (!sending.value) {
    void loadSenders(1)
    void loadContacts(contactPage.value)
  }
}, { immediate: true })
onBeforeUnmount(() => {
  disposed = true
  stopReads()
  window.removeEventListener('beforeunload', beforeUnload)
  // The parent guards navigation during sending. If forcibly unmounted, leave
  // the remote request alone; aborting a response cannot undo sent messages.
  emit('busy', false)
})
</script>

<template>
  <el-dialog :model-value="modelValue || sending" :title="t('emailCompose.title')" width="780px" align-center append-to-body class="email-compose-dialog" :close-on-click-modal="false" :close-on-press-escape="!sending" :show-close="!sending" :before-close="beforeClose" @update:model-value="onVisibility">
    <form id="email-compose-form" class="compose-form" @submit.prevent="submit">
      <p v-if="draftSelectionUpdated" class="compose-note" role="status">{{ t('emailCompose.selectionUpdated') }}</p>
      <div class="compose-field">
        <label for="email-compose-subject">{{ t('emailCompose.subject') }} <span aria-hidden="true">*</span></label>
        <el-input id="email-compose-subject" v-model="subject" :disabled="locked" :placeholder="t('emailCompose.subjectPlaceholder')" :aria-invalid="!!validation.subject" aria-required="true" @input="validation.subject = ''" @keydown.enter.prevent />
        <p v-if="validation.subject" class="compose-error" role="alert">{{ t(`emailCompose.validation.${validation.subject}`) }}</p>
      </div>
      <div class="compose-field">
        <label for="email-compose-content">{{ t('emailCompose.content') }} <span aria-hidden="true">*</span></label>
        <el-input id="email-compose-content" v-model="content" type="textarea" :rows="6" :disabled="locked" :placeholder="t('emailCompose.contentPlaceholder')" :aria-invalid="!!validation.content" aria-required="true" @input="validation.content = ''" />
        <p v-if="validation.content" class="compose-error" role="alert">{{ t(`emailCompose.validation.${validation.content}`) }}</p>
        <p class="compose-note">{{ t('emailCompose.contentHint') }}</p>
      </div>
      <div class="compose-field">
        <label for="email-compose-sender">{{ t('emailCompose.sender') }} <span aria-hidden="true">*</span></label>
        <el-select id="email-compose-sender" :model-value="senderId" :disabled="locked" :loading="senderLoading" :placeholder="t('emailCompose.senderPlaceholder')" :aria-invalid="!!validation.sender" aria-required="true" @update:model-value="changeSender">
          <el-option v-for="row in senderOptions" :key="row.id" :value="row.id" :label="senderLabel(row)" :disabled="row.active === false" />
        </el-select>
        <p v-if="validation.sender" class="compose-error" role="alert">{{ t(`emailCompose.validation.${validation.sender}`) }}</p>
        <div class="compose-inline">
          <span v-if="senderPage && !senderFailure" class="compose-note">{{ t('emailCompose.senderLoaded', { loaded: n(senders.length), total: n(senderTotal) }) }}</span>
          <GhostBtn v-if="senderPage < senderPages" :disabled="locked || senderLoading" @click="loadSenders(senderPage + 1)">{{ t('emailCompose.moreSenders') }}</GhostBtn>
          <GhostBtn :loading="senderLoading" :disabled="locked" @click="loadSenders(1)">{{ t('emailCompose.refreshSenders') }}</GhostBtn>
        </div>
        <PageErrorNotice v-if="senderFailure"><span>{{ failureText(senderFailure) }}</span><GhostBtn :disabled="locked || senderLoading" @click="loadSenders(senderRetryPage)">{{ t('emailCompose.retry') }}</GhostBtn></PageErrorNotice>
        <p v-else-if="!senderLoading && !senderOptions.length" class="compose-note">{{ t('emailCompose.senderEmpty') }}</p>
        <p v-if="chosenSender" class="compose-note">{{ t('emailCompose.senderQuota', { sent: displayCount(chosenSender.todaySentCount), limit: displayCount(chosenSender.dailyEmailLimit), date: chosenSender.lastResetDate || '—' }) }}</p>
      </div>

      <section class="compose-recipients" :aria-label="t('emailCompose.recipients')">
        <div class="compose-recipient-heading"><span>{{ t('emailCompose.recipients') }} <span aria-hidden="true">*</span></span><span class="compose-note" aria-live="polite">{{ t('emailCompose.selectedCount', { count: n(selected.size) }) }}</span></div>
        <div class="compose-search">
          <el-select v-model="searchField" :disabled="contactLocked" :aria-label="t('emailCompose.searchBy')"><el-option value="name" :label="t('emailCompose.contactName')" /><el-option value="email" :label="t('emailCompose.contactEmail')" /></el-select>
          <el-input v-model="searchText" :disabled="contactLocked" :placeholder="t('emailCompose.searchPlaceholder')" :aria-label="t('emailCompose.searchPlaceholder')" clearable @keydown.enter.prevent="searchContacts()" />
          <GhostBtn :loading="contactLoading" :disabled="contactLocked" @click="searchContacts()">{{ t('emailCompose.search') }}</GhostBtn>
          <GhostBtn :disabled="contactLocked || contactLoading" @click="searchContacts(true)">{{ t('emailCompose.resetSearch') }}</GhostBtn>
        </div>
        <div class="compose-inline compose-selection-actions">
          <GhostBtn :disabled="contactLocked || contactLoading || !!contactFailure || !contacts.length" @click="selectPage">{{ t('emailCompose.selectPage') }}</GhostBtn>
          <GhostBtn :disabled="contactLocked || contactLoading" @click="selectAllContacts">{{ t('emailCompose.selectAll') }}</GhostBtn>
          <GhostBtn :disabled="contactLocked || !selected.size" @click="clearRecipients">{{ t('emailCompose.clearRecipients') }}</GhostBtn>
          <GhostBtn v-if="selected.size" @click="showSelected = !showSelected">{{ t(`emailCompose.${showSelected ? 'hideSelection' : 'reviewSelection'}`) }}</GhostBtn>
        </div>
        <div v-if="collecting" class="compose-inline" role="status"><span class="compose-note">{{ collectTotal === null ? t('emailCompose.loading') : t('emailCompose.collecting', { loaded: n(collected), total: n(collectTotal) }) }}</span><GhostBtn @click="cancelCollection">{{ t('emailCompose.cancelCollect') }}</GhostBtn></div>
        <PageErrorNotice v-if="collectFailure || collectionChanged"><span>{{ t('emailCompose.collectFailed') }} {{ collectionChanged ? t('emailCompose.listChanged') : failureText(collectFailure) }}</span><GhostBtn :disabled="contactLocked || contactLoading" @click="selectAllContacts">{{ t('emailCompose.retry') }}</GhostBtn></PageErrorNotice>
        <PageErrorNotice v-if="contactFailure"><span>{{ failureText(contactFailure) }}</span><GhostBtn :disabled="contactLocked || contactLoading" @click="loadContacts(contactRetryPage)">{{ t('emailCompose.retry') }}</GhostBtn></PageErrorNotice>
        <div class="compose-contact-list" :aria-busy="contactLoading">
          <p v-if="contactLoading" class="compose-list-state" role="status">{{ t('emailCompose.loading') }}</p>
          <p v-else-if="!contacts.length && !contactFailure" class="compose-list-state">{{ t('emailCompose.contactEmpty') }}</p>
          <template v-else-if="!contactFailure">
            <label v-for="row in contacts" :key="row.id" class="compose-contact" :class="{ 'is-selected': selected.has(row.id) }">
              <input type="checkbox" :checked="selected.has(row.id)" :disabled="contactLocked" :aria-label="t('emailCompose.recipientLabel', { name: row.name, email: row.email })" @change="toggleContact(row)">
              <span class="compose-contact-name">{{ row.name || '—' }}</span><span class="compose-contact-email">{{ row.email }}</span>
            </label>
          </template>
        </div>
        <PagePagination v-if="!contactLoading && !contactFailure" embedded :current-page="contactPage" :page-size="contactPageSize" :total="contactTotal" :disabled="contactLocked" :aria-label="t('emailCompose.pagination')" @current-change="loadContacts"><span>{{ t('emailCompose.totalContacts', { count: n(contactTotal) }) }}</span></PagePagination>
        <div v-if="showSelected && selected.size" class="compose-selected-list">
          <div v-for="row in selectedContacts" :key="row.id" class="compose-selected-contact"><span>{{ row.name || '—' }} · {{ row.email }}</span><button type="button" :disabled="contactLocked" :aria-label="t('emailCompose.removeRecipient', { name: row.name || row.email })" :title="t('emailCompose.removeRecipient', { name: row.name || row.email })" @click="toggleContact(row)"><i class="i-mdi-close" aria-hidden="true" /></button></div>
        </div>
        <p v-if="validation.recipients" class="compose-error" role="alert">{{ t(`emailCompose.validation.${validation.recipients}`) }}</p>
        <p class="compose-note">{{ t('emailCompose.selectionHint') }}</p>
      </section>
      <p v-if="sending" ref="resultElement" class="compose-status" role="status">{{ t('emailCompose.sendingHint') }}</p>
      <div v-else-if="hasResult" ref="resultElement" class="compose-result" :class="{ 'has-warning': sendState !== 'processed' }" role="status">
        <strong>{{ t(`emailCompose.${sendState}`) }}</strong>
        <p>{{ t(`emailCompose.${sendState}Hint`) }}</p>
        <PageErrorNotice v-if="sendFailure">{{ failureText(sendFailure) }}</PageErrorNotice>
        <label class="compose-reviewed"><input v-model="reviewed" type="checkbox"><span>{{ t('emailCompose.reviewed') }}</span></label>
        <GhostBtn :disabled="!reviewed" @click="resumeDraft">{{ t('emailCompose.resume') }}</GhostBtn>
      </div>
      <p class="compose-note">{{ t('emailCompose.draftHint') }}</p>
    </form>
    <template #footer>
      <GhostBtn :disabled="sending" @click="close">{{ t('emailCompose.close') }}</GhostBtn>
      <PrimaryBtn v-if="!hasResult" type="submit" form="email-compose-form" :loading="sending" :disabled="locked || collecting || senderLoading || contactLoading">{{ t(`emailCompose.${sending ? 'sending' : 'send'}`) }}</PrimaryBtn>
    </template>
  </el-dialog>
</template>

<style>
.email-compose-dialog { max-width: calc(100vw - 24px); padding: 24px; background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
.email-compose-dialog .el-dialog__title { color: var(--text-primary); font-size: var(--font-size-dialog-title); font-weight: 600; }
.email-compose-dialog .el-dialog__body { max-height: min(72vh, 820px); overflow-y: auto; padding-right: 4px; color: var(--text-primary); }
.email-compose-dialog .el-dialog__footer { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 8px; }
.email-compose-dialog .compose-form { display: grid; gap: 18px; }
.email-compose-dialog .compose-field { display: grid; gap: 8px; }
.email-compose-dialog .compose-field > label, .email-compose-dialog .compose-recipient-heading { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; }
.email-compose-dialog .el-input, .email-compose-dialog .el-textarea, .email-compose-dialog .el-select { font-family: var(--sans); font-size: var(--font-size-body); }
.email-compose-dialog .el-select { width: 100%; }
.email-compose-dialog .compose-note { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); font-weight: 400; line-height: 1.6; }
.email-compose-dialog .compose-inline { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; }
.email-compose-dialog .compose-inline .btn, .email-compose-dialog .compose-search .btn { padding: 6px 12px; min-height: 34px; font-weight: 500; }
.email-compose-dialog .compose-error { margin: 0; color: var(--status-danger); font-size: var(--font-size-secondary); line-height: 1.6; overflow-wrap: anywhere; }
.email-compose-dialog .compose-recipients { display: grid; gap: 10px; min-width: 0; }
.email-compose-dialog .compose-recipient-heading { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; }
.email-compose-dialog .compose-search { display: grid; grid-template-columns: 104px minmax(100px, 1fr) auto auto; gap: 8px; }
.email-compose-dialog .compose-contact-list { min-height: 90px; max-height: 250px; overflow-y: auto; border: 1px solid var(--border); border-radius: 12px; }
.email-compose-dialog .compose-contact { display: grid; grid-template-columns: 18px minmax(80px, .8fr) minmax(150px, 1.5fr); align-items: center; gap: 10px; padding: 11px 12px; color: var(--text-primary); font-size: var(--font-size-body); line-height: 1.5; cursor: pointer; }
.email-compose-dialog .compose-contact + .compose-contact { border-top: 1px solid var(--border); }
.email-compose-dialog .compose-contact:hover, .email-compose-dialog .compose-contact.is-selected { background: var(--bg-hover); }
.email-compose-dialog input[type="checkbox"] { width: 16px; height: 16px; margin: 0; accent-color: var(--brand); flex-shrink: 0; }
.email-compose-dialog input[type="checkbox"]:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.email-compose-dialog input[type="checkbox"]:disabled { cursor: default; }
.email-compose-dialog .compose-contact-name, .email-compose-dialog .compose-contact-email { overflow-wrap: anywhere; }
.email-compose-dialog .compose-list-state { margin: 0; padding: 22px 14px; color: var(--text-secondary); font-size: var(--font-size-body); line-height: 1.6; }
.email-compose-dialog .compose-selected-list { display: grid; gap: 4px; max-height: 180px; overflow-y: auto; padding: 10px 12px; border: 1px solid var(--border); border-radius: 12px; background: var(--bg-search); }
.email-compose-dialog .compose-selected-contact { display: flex; align-items: center; justify-content: space-between; gap: 10px; color: var(--text-primary); font-size: var(--font-size-body); }
.email-compose-dialog .compose-selected-contact > span { overflow-wrap: anywhere; }
.email-compose-dialog .compose-selected-contact button { display: inline-flex; align-items: center; justify-content: center; width: 30px; height: 30px; flex-shrink: 0; border: 1px solid var(--border); border-radius: 50%; background: var(--bg-card); color: var(--text-primary); font: inherit; cursor: pointer; }
.email-compose-dialog .compose-selected-contact button:disabled { opacity: .55; cursor: default; }
.email-compose-dialog .compose-selected-contact button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
.email-compose-dialog .compose-status, .email-compose-dialog .compose-result { margin: 0; padding: 14px; border: 1px solid var(--border); border-radius: 12px; background: var(--bg-search); color: var(--text-primary); font-size: var(--font-size-body); line-height: 1.6; }
.email-compose-dialog .compose-result { display: grid; gap: 10px; }
.email-compose-dialog .compose-result.has-warning { border-color: var(--status-warn); }
.email-compose-dialog .compose-result p { margin: 0; }
.email-compose-dialog .compose-result > .btn { justify-self: start; }
.email-compose-dialog .compose-reviewed { display: flex; align-items: flex-start; gap: 9px; color: var(--text-primary); font-size: var(--font-size-body); cursor: pointer; }
.email-compose-dialog .compose-reviewed input { margin-top: 4px; }
@media (max-width: 580px) {
  .email-compose-dialog { padding: 18px; }
  .email-compose-dialog .compose-search { grid-template-columns: 96px minmax(0, 1fr); }
  .email-compose-dialog .compose-contact { grid-template-columns: 18px minmax(0, 1fr); gap: 3px 10px; }
  .email-compose-dialog .compose-contact input { grid-row: span 2; }
  .email-compose-dialog .compose-contact-email { grid-column: 2; }
}
</style>
