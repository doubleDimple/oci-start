<script setup lang="ts">
import { ElTableColumn } from 'element-plus'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter, type LocationQueryRaw } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { mobileRecordParents } from '@/composables/useMobileRecords'
import EmailComposeDialog from './components/EmailComposeDialog.vue'
import EmailRecordDetailDialog from './components/EmailRecordDetailDialog.vue'
import { useEmailPage } from './useEmailPage'
import { formatEmailCount, formatEmailTime } from './presentation'
import {
  listEmailTenants, listEmailAvailableTenants, listEmailContacts, listEmailBodies,
  getEmailTenantConfigs, addEmailContact, deleteEmailContact, enableTenantEmail, disableTenantEmail,
  deleteEmailBody, deleteAllEmailBodies, emailError, isEmailWriteUncertain,
  type EmailBody, type EmailContact, type EmailAvailableTenant, type EmailTenantConfig,
} from '@/api/email'

type Section = 'records' | 'services' | 'contacts'
type Action = { kind: 'addContact' } | { kind: 'enable'; tenant: EmailAvailableTenant }
  | { kind: 'disable'; config: EmailTenantConfig } | { kind: 'deleteContact'; contact: EmailContact }
  | { kind: 'deleteBody'; body: EmailBody } | { kind: 'deleteAll' }
const { t, locale } = useI18n()
const router = useRouter()
const route = useRoute()
const compact = useCompactViewport()
const sections: Section[] = ['records', 'services', 'contacts']
const section = ref<Section>(sections.includes(route.query.mobileEmailSection as Section) ? route.query.mobileEmailSection as Section : 'records')
const serviceTab = ref<'enabled' | 'available'>(route.query.mobileEmailService === 'available' ? 'available' : 'enabled')
const keyword = ref(typeof route.query.mobileEmailSearch === 'string' ? route.query.mobileEmailSearch : '')
const committedKeyword = ref(keyword.value.trim())
const requestedMobilePage = Number(route.query.mobileEmailPage)
const initialMobilePage = Number.isSafeInteger(requestedMobilePage) && requestedMobilePage > 0 ? requestedMobilePage : 1
const records = useEmailPage(10, (pageNum, pageSize, signal) => listEmailBodies({ pageNum, pageSize, sort: 'createTime', order: 'desc' }, signal))
const contacts = useEmailPage(10, (pageNum, pageSize, signal) => listEmailContacts({ pageNum, pageSize, sort: 'createTime', order: 'desc' }, signal))
const enabled = useEmailPage(5, (pageNum, pageSize, signal) => listEmailTenants({ pageNum, pageSize, sort: 'createdTime', order: 'desc' }, signal))
const available = useEmailPage(5, (pageNum, pageSize, signal) => listEmailAvailableTenants({ pageNum, pageSize, keyword: committedKeyword.value }, signal))
const activePager = computed(() => section.value === 'records' ? records : section.value === 'contacts' ? contacts : serviceTab.value === 'enabled' ? enabled : available)
const mobileListId = computed(() => `email-${section.value === 'services' ? serviceTab.value : section.value}`)
const mobileRecordKeys = computed(() => (section.value === 'services' && serviceTab.value === 'enabled' ? enabledRows.value : activePager.value.rows).map(row => row.id))
const enabledRows = computed(() => {
  const query = keyword.value.trim().toLocaleLowerCase(locale.value)
  return query ? enabled.rows.filter(row => `${row.tenantName} ${row.senderEmail} ${row.tenantId}`.toLocaleLowerCase(locale.value).includes(query)) : enabled.rows
})
const pageError = computed(() => activePager.value.problem ? errorText(activePager.value.problem) : '')
const pageEmpty = computed(() => t(activePager.value.loading ? 'emailManagement.loading' : pageError.value ? 'emailManagement.loadFailed'
  : section.value === 'records' ? 'emailManagement.recordsEmpty' : section.value === 'contacts' ? 'emailManagement.contactsEmpty'
    : serviceTab.value === 'available' ? 'emailManagement.availableEmpty' : keyword.value.trim() ? 'emailManagement.searchEmpty' : 'emailManagement.servicesEmpty'))
const selectedBody = ref<EmailBody | null>(null)
const composeOpen = ref(false)
const composeBusy = ref(false)
const composer = ref<InstanceType<typeof EmailComposeDialog>>()
const action = ref<Action | null>(null)
const mutationState = ref<'idle' | 'pending' | 'uncertain'>('idle')
const mutationError = ref<ReturnType<typeof emailError> | null>(null)
const mutationNote = ref('')
const validationKey = ref('')
const contactName = ref('')
const contactAddress = ref('')
const domain = ref('')
const busy = computed(() => mutationState.value === 'pending' || composeBusy.value)
const actionTitle = computed(() => action.value ? t(`emailManagement.${action.value.kind}Title`) : '')
const actionDescription = computed(() => {
  const target = action.value
  if (!target) return ''
  if (target.kind === 'enable') return t('emailManagement.enableHint')
  if (target.kind === 'disable') return t('emailManagement.disableHint')
  if (target.kind === 'deleteContact') return t('emailManagement.deleteContactHint', { name: target.contact.name, email: target.contact.email })
  if (target.kind === 'deleteBody') return t('emailManagement.deleteBodyHint', { title: target.body.title || t('emailManagement.unnamed') })
  return target.kind === 'deleteAll' ? t('emailManagement.deleteAllHint') : ''
})
const actionProblem = computed(() => validationKey.value ? t(`emailManagement.${validationKey.value}`) : mutationError.value ? errorText(mutationError.value) : '')
const dangerAction = computed(() => action.value && !['enable', 'addContact'].includes(action.value.kind))
let disposed = false
let mutationSequence = 0
let resettingSearch = false
let searchTimer: ReturnType<typeof setTimeout> | undefined
let verification: AbortController | undefined

function errorText(problem: ReturnType<typeof emailError>) { return problem.detail || t(`emailManagement.errors.${problem.key}`) }
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function count(value: number | null) { return formatEmailCount(value, locale.value) }
function timestamp(value: string) { return formatEmailTime(value, locale.value) }
function tenantName(row: EmailAvailableTenant) { return row.tenancyName || row.defName || row.userName || t('emailManagement.tenantId', { id: row.id }) }
function quotaRatio(row: EmailTenantConfig): number | null {
  return row.dailyEmailLimit != null && row.dailyEmailLimit > 0 && row.todaySentCount != null
    ? Math.min(100, Math.max(0, row.todaySentCount / row.dailyEmailLimit * 100)) : null
}
function openBody(row: EmailBody) {
  selectedBody.value = row
  if (compact.value) void router.replace({ query: { ...route.query, mobileEmailBody: String(row.id), mobileEmailRecipientPage: undefined } })
}
async function closeBody() {
  if (compact.value && route.query.mobileEmailBody) {
    const query: LocationQueryRaw = { ...route.query, mobileEmailBody: undefined, mobileEmailRecipientPage: undefined }
    if (typeof query.mobileRecord === 'string' && query.mobileRecord.startsWith('email-recipients-')) {
      const parents = mobileRecordParents(route.query)
      query.mobileRecord = parents.pop()
      query.mobileRecordParents = parents.length ? parents : undefined
    }
    await router.replace({ query })
  }
  selectedBody.value = null
}
function setSection(value: Section) {
  if (busy.value) return
  section.value = value
  if (!activePager.value.loaded && !activePager.value.loading) void activePager.value.load(1)
}
function setServiceTab(value: 'enabled' | 'available') {
  if (busy.value || serviceTab.value === value) return
  clearTimeout(searchTimer)
  serviceTab.value = value
  resetTenantSearch()
  if (value === 'available') { available.reset(); void available.load(1) }
  else { enabled.reset(); void enabled.load(1) }
}
function resetTenantSearch() {
  clearTimeout(searchTimer)
  resettingSearch = true
  keyword.value = committedKeyword.value = ''
  resettingSearch = false
}
function refresh() {
  if (section.value === 'services') {
    resetTenantSearch()
    void activePager.value.load(1)
  } else void activePager.value.load()
}
function paginate(value: number) { void activePager.value.load(value) }
function openAction(value: Action) {
  if (busy.value) return
  mutationSequence++
  action.value = value
  mutationState.value = 'idle'
  mutationError.value = null
  mutationNote.value = validationKey.value = ''
  contactName.value = contactAddress.value = domain.value = ''
}
function closeAction() {
  if (mutationState.value === 'pending') return
  action.value = null
  verification?.abort()
}
async function refreshRelated(target: Action) {
  if (disposed) return
  if (target.kind === 'addContact' || target.kind === 'deleteContact') await contacts.load(target.kind === 'addContact' ? 1 : contacts.page)
  else if (target.kind === 'enable' || target.kind === 'disable') {
    await Promise.allSettled([enabled.load(), available.loaded ? available.load() : Promise.resolve(), records.load()])
  } else await records.load(target.kind === 'deleteAll' ? 1 : records.page)
}
function inspectLatest() {
  const target = action.value
  closeAction()
  if (target) void refreshRelated(target)
}
async function submitAction() {
  const target = action.value
  if (!target || busy.value || mutationState.value === 'uncertain') return
  validationKey.value = ''
  if (target.kind === 'addContact') {
    if (!contactName.value.trim() || !contactAddress.value.trim()) { validationKey.value = 'required'; return }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactAddress.value.trim())) { validationKey.value = 'invalidEmail'; return }
  }
  if (target.kind === 'enable' && !/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(\.[a-zA-Z]{2,})$/.test(domain.value.trim())) {
    validationKey.value = 'invalidDomain'; return
  }
  const currentMutation = ++mutationSequence
  mutationState.value = 'pending'
  mutationError.value = null
  mutationNote.value = ''
  try {
    let message = ''
    if (target.kind === 'addContact') {
      await addEmailContact({ name: contactName.value, email: contactAddress.value })
      message = 'saved'
    } else if (target.kind === 'deleteContact') {
      await deleteEmailContact(target.contact.id)
      composer.value?.removeContact(target.contact.id)
      message = 'contactDeleted'
    } else if (target.kind === 'deleteBody') {
      await deleteEmailBody(target.body.id)
      if (selectedBody.value?.id === target.body.id) selectedBody.value = null
      message = 'bodyDeleted'
    } else if (target.kind === 'deleteAll') {
      await deleteAllEmailBodies()
      selectedBody.value = null
      message = 'allDeleted'
    } else if (target.kind === 'disable') {
      await disableTenantEmail(target.config.id)
      composer.value?.removeSender(target.config.id)
      selectedBody.value = null
      message = 'disableRecorded'
    } else {
      const requestedDomain = domain.value.trim()
      await enableTenantEmail({ tenantId: target.tenant.id, emailDomain: requestedDomain })
      verification = new AbortController()
      const configs = await getEmailTenantConfigs(target.tenant.id, verification.signal)
      if (disposed) return
      if (!configs.some(config => config.domainName.toLowerCase() === requestedDomain.toLowerCase() && config.active !== false)) {
        mutationState.value = 'uncertain'
        mutationNote.value = 'enableUnconfirmed'
        await refreshRelated(target)
        return
      }
      message = 'enableRecorded'
    }
    if (disposed) return
    mutationState.value = 'idle'
    closeAction()
    if (target.kind === 'disable' || target.kind === 'enable') ElMessage.info(t(`emailManagement.${message}`))
    else ElMessage.success(t(`emailManagement.${message}`))
    await refreshRelated(target)
  } catch (cause) {
    if (disposed) return
    mutationError.value = emailError(cause)
    const uncertain = isEmailWriteUncertain(cause) || target.kind === 'enable' || target.kind === 'disable'
    mutationState.value = uncertain ? 'uncertain' : 'idle'
    if (uncertain) mutationNote.value = 'uncertain'
    await refreshRelated(target)
  } finally {
    if (!disposed && currentMutation === mutationSequence && mutationState.value === 'pending') mutationState.value = 'idle'
  }
}
function afterSend() {
  section.value = 'records'
  void records.load(1)
  void enabled.load()
}
function guardLeaving() {
  if (!busy.value) return true
  ElMessage.warning(t('emailManagement.busyLeave'))
  return false
}
function back() {
  if (!guardLeaving()) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: '1' } })
}
watch(keyword, () => {
  clearTimeout(searchTimer)
  if (resettingSearch || serviceTab.value !== 'available') return
  available.stop()
  searchTimer = setTimeout(() => {
    committedKeyword.value = keyword.value.trim()
    available.reset()
    void available.load(1)
  }, 300)
}, { flush: 'sync' })
watch([section, serviceTab, keyword, () => activePager.value.page, () => activePager.value.loading, busy, compact], () => {
  if (!compact.value || busy.value || activePager.value.loading || !activePager.value.loaded) return
  const values = { mobileEmailSection: section.value, mobileEmailService: serviceTab.value, mobileEmailSearch: keyword.value || undefined, mobileEmailPage: String(activePager.value.page) }
  if (Object.entries(values).every(([key, value]) => route.query[key] === value)) return
  void router.replace({ query: { ...route.query, ...values } })
})
watch([() => route.query.mobileEmailBody, () => records.rows], () => {
  const id = route.query.mobileEmailBody
  if (!id) { if (compact.value) selectedBody.value = null; return }
  const row = records.rows.find(record => String(record.id) === id)
  if (row) selectedBody.value = row
})
onBeforeRouteLeave(guardLeaving)
onBeforeRouteUpdate(guardLeaving)
onMounted(() => {
  void records.load(section.value === 'records' ? initialMobilePage : 1)
  void enabled.load(section.value === 'services' && serviceTab.value === 'enabled' ? initialMobilePage : 1)
  void contacts.load(section.value === 'contacts' ? initialMobilePage : 1)
  if (section.value === 'services' && serviceTab.value === 'available') void available.load(initialMobilePage)
})
onBeforeUnmount(() => { disposed = true; clearTimeout(searchTimer); verification?.abort() })

// Each table supplies a distinct row contract to the shared column component.
const EmailBodyColumn = ElTableColumn<EmailBody>
const EmailContactColumn = ElTableColumn<EmailContact>
const EmailTenantConfigColumn = ElTableColumn<EmailTenantConfig>
const EmailAvailableTenantColumn = ElTableColumn<EmailAvailableTenant>
</script>

<template>
  <section class="email-page" :aria-label="t('emailManagement.title')">
    <div class="email-toolbar">
      <PageBackButton :disabled="busy" @click="back" />
      <div class="email-sections" role="group" :aria-label="t('emailManagement.title')"><button v-for="value in sections" :key="value" type="button" :class="{ active: section === value }" :aria-pressed="section === value" :disabled="busy" @click="setSection(value)">{{ t(`emailManagement.${value}`) }}</button></div>
      <div class="email-tools" data-page-error-anchor>
        <GhostBtn v-if="section === 'contacts'" :disabled="busy" @click="openAction({ kind: 'addContact' })"><i class="i-mdi-plus" aria-hidden="true" />{{ t('emailManagement.addContact') }}</GhostBtn>
        <GhostBtn v-if="section === 'records'" danger :disabled="busy || !records.loaded || records.total === 0" @click="openAction({ kind: 'deleteAll' })">{{ t('emailManagement.deleteAll') }}</GhostBtn>
        <button class="email-icon-button" type="button" :disabled="busy || activePager.loading" :title="t('emailManagement.refresh')" :aria-label="t('emailManagement.refresh')" @click="refresh"><i class="i-mdi-refresh" :class="{ spinning: activePager.loading }" aria-hidden="true" /></button>
        <PrimaryBtn :disabled="busy" @click="composeOpen = true"><i class="i-mdi-email-edit-outline" aria-hidden="true" />{{ t('emailManagement.compose') }}</PrimaryBtn>
      </div>
    </div>
    <div v-if="section === 'services'" class="email-service-tools">
      <div class="email-service-tabs" role="group" :aria-label="t('emailManagement.services')"><button type="button" :class="{ active: serviceTab === 'enabled' }" :aria-pressed="serviceTab === 'enabled'" :disabled="busy" @click="setServiceTab('enabled')">{{ t('emailManagement.enabled') }}</button><button type="button" :class="{ active: serviceTab === 'available' }" :aria-pressed="serviceTab === 'available'" :disabled="busy" @click="setServiceTab('available')">{{ t('emailManagement.available') }}</button></div>
      <el-input v-model="keyword" :placeholder="t(serviceTab === 'enabled' ? 'emailManagement.enabledSearch' : 'emailManagement.availableSearch')" :aria-label="t(serviceTab === 'enabled' ? 'emailManagement.enabledSearch' : 'emailManagement.availableSearch')" :title="serviceTab === 'enabled' ? t('emailManagement.localSearchHint') : undefined" :disabled="busy" clearable class="email-search"><template #prefix><i class="i-mdi-magnify" aria-hidden="true" /></template></el-input>
      <span v-if="serviceTab === 'enabled'" class="email-filter-hint">{{ t('emailManagement.localSearchHint') }}</span>
    </div>
    <PageErrorNotice v-if="pageError" class="email-read-notice"><span>{{ pageError }} <span v-if="activePager.loaded">{{ t('emailManagement.keepPage') }}</span></span><GhostBtn :loading="activePager.loading" @click="activePager.retry()">{{ t('emailManagement.retry') }}</GhostBtn></PageErrorNotice>
    <div class="email-table-stage" :aria-busy="activePager.loading">
      <MobileRecordList v-if="compact" :key="mobileListId" drilldown :list-id="mobileListId" :record-keys="mobileRecordKeys" :loading="activePager.loading">
        <template v-if="section === 'records'">
          <MobileRecordCard v-for="row in records.rows" :key="row.id" :record-key="row.id" :summary-title="row.title || t('emailManagement.unnamed')" :summary-meta="`${row.tenantName || row.senderEmail || '—'} · ${timestamp(row.createTime)}`">
            <template #identity><div class="mobile-record-title">{{ row.title || t('emailManagement.unnamed') }}</div><span class="mobile-record-subtitle">{{ row.tenantName || '—' }}</span></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('emailManagement.sender') }}</dt><dd>{{ row.senderEmail || '—' }}</dd></div><div class="mobile-record-wide"><dt>{{ t('emailManagement.sendTime') }}</dt><dd>{{ timestamp(row.createTime) }}</dd></div><div><dt>{{ t('emailManagement.recipients') }}</dt><dd>{{ count(row.receiveTotal) }}</dd></div><div><dt>{{ t('emailManagement.success') }}</dt><dd>{{ count(row.receiveSuccessTotal) }}</dd></div><div><dt>{{ t('emailManagement.failed') }}</dt><dd>{{ count(row.receiveFailTotal) }}</dd></div></dl>
            <template #footer><button type="button" class="mobile-record-button" @click="openBody(row)">{{ t('emailManagement.details') }}</button><button type="button" class="mobile-record-button" :disabled="busy" @click="openAction({ kind: 'deleteBody', body: { ...row } })">{{ t('emailManagement.delete') }}</button></template>
          </MobileRecordCard>
        </template>
        <template v-else-if="section === 'contacts'">
          <MobileRecordCard v-for="row in contacts.rows" :key="row.id" :record-key="row.id" :summary-title="row.name || t('emailManagement.unnamed')" :summary-meta="row.email">
            <template #identity><div class="mobile-record-title">{{ row.name || t('emailManagement.unnamed') }}</div></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('emailManagement.email') }}</dt><dd>{{ row.email }}</dd></div><div class="mobile-record-wide"><dt>{{ t('emailManagement.createdAt') }}</dt><dd>{{ timestamp(row.createTime) }}</dd></div></dl>
            <template #footer><button type="button" class="mobile-record-button" :disabled="busy" @click="openAction({ kind: 'deleteContact', contact: { ...row } })">{{ t('emailManagement.delete') }}</button></template>
          </MobileRecordCard>
        </template>
        <template v-else-if="serviceTab === 'enabled'">
          <MobileRecordCard v-for="row in enabledRows" :key="row.id" :record-key="row.id" :summary-title="row.tenantName || t('emailManagement.tenantId', { id: row.tenantId })" :summary-meta="row.senderEmail || t('emailManagement.missingSender')" :summary-status="row.active === false ? t('emailManagement.notReady') : ''" summary-tone="warning">
            <template #identity><div class="mobile-record-title">{{ row.tenantName || t('emailManagement.tenantId', { id: row.tenantId }) }}</div></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('emailManagement.sender') }}</dt><dd>{{ row.senderEmail || t('emailManagement.missingSender') }}<span v-if="row.active === false" class="mobile-record-subtitle">{{ t('emailManagement.notReady') }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('emailManagement.domain') }}</dt><dd>{{ row.domainName || '—' }}</dd></div><div class="mobile-record-wide"><dt>{{ t('emailManagement.quota') }}</dt><dd><div class="email-quota"><span>{{ count(row.todaySentCount) }} / {{ count(row.dailyEmailLimit) }}</span><div v-if="quotaRatio(row) !== null" class="email-quota-track" aria-hidden="true"><span :style="{ width: `${quotaRatio(row)}%` }" :class="{ warning: (quotaRatio(row) || 0) >= 75, danger: (quotaRatio(row) || 0) >= 90 }" /></div><small>{{ t('emailManagement.counterDate', { date: row.lastResetDate || '—' }) }}</small></div></dd></div></dl>
            <template #footer><button type="button" class="mobile-record-button" :disabled="busy" @click="openAction({ kind: 'disable', config: { ...row } })">{{ t('emailManagement.disable') }}</button></template>
          </MobileRecordCard>
        </template>
        <template v-else>
          <MobileRecordCard v-for="row in available.rows" :key="row.id" :record-key="row.id" :summary-title="tenantName(row)" :summary-meta="row.region || '—'">
            <template #identity><div class="mobile-record-title">{{ tenantName(row) }}</div></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('emailManagement.region') }}</dt><dd>{{ row.region || '—' }}</dd></div></dl>
            <template #footer><button type="button" class="mobile-record-button" :disabled="busy || row.cloudType !== 1 || row.emailEnable !== 0" @click="openAction({ kind: 'enable', tenant: { ...row } })">{{ t('emailManagement.enable') }}</button></template>
          </MobileRecordCard>
        </template>
        <p v-if="!mobileRecordKeys.length" class="email-mobile-empty" role="status">{{ pageEmpty }}</p>
      </MobileRecordList>
      <el-table v-else-if="section === 'records'" :data="records.rows" height="100%" row-key="id" v-loading="records.loading" :element-loading-text="t('emailManagement.loading')" :empty-text="pageEmpty" table-layout="fixed">
        <EmailBodyColumn :label="t('emailManagement.subject')" min-width="250" show-overflow-tooltip><template #default="{ row }"><button type="button" class="email-subject" @click="selectedBody = row">{{ row.title || t('emailManagement.unnamed') }}</button></template></EmailBodyColumn>
        <EmailBodyColumn :label="t('emailManagement.tenant')" min-width="200" show-overflow-tooltip><template #default="{ row }"><div class="email-cell-lines"><span>{{ row.tenantName || '—' }}</span><small>{{ row.senderEmail || '—' }}</small></div></template></EmailBodyColumn>
        <EmailBodyColumn :label="t('emailManagement.sendTime')" width="185" show-overflow-tooltip><template #default="{ row }"><span :title="t('emailManagement.timeHint')">{{ timestamp(row.createTime) }}</span></template></EmailBodyColumn>
        <EmailBodyColumn :label="t('emailManagement.recipients')" width="120" align="right" header-align="right"><template #default="{ row }">{{ count(row.receiveTotal) }}</template></EmailBodyColumn>
        <EmailBodyColumn :label="t('emailManagement.success')" width="120" align="right" header-align="right"><template #default="{ row }">{{ count(row.receiveSuccessTotal) }}</template></EmailBodyColumn>
        <EmailBodyColumn :label="t('emailManagement.failed')" width="110" align="right" header-align="right"><template #default="{ row }">{{ count(row.receiveFailTotal) }}</template></EmailBodyColumn>
        <EmailBodyColumn :label="t('emailManagement.actions')" width="110" fixed="right" align="center" header-align="center"><template #default="{ row }"><div class="email-row-actions"><button type="button" class="email-icon-button" :title="t('emailManagement.details')" :aria-label="t('emailManagement.details')" @click="selectedBody = row"><i class="i-mdi-text-box-search-outline" aria-hidden="true" /></button><button type="button" class="email-icon-button danger" :disabled="busy" :title="t('emailManagement.delete')" :aria-label="t('emailManagement.delete')" @click="openAction({ kind: 'deleteBody', body: { ...row } })"><i class="i-mdi-trash-can-outline" aria-hidden="true" /></button></div></template></EmailBodyColumn>
      </el-table>
      <el-table v-else-if="section === 'contacts'" :data="contacts.rows" height="100%" row-key="id" v-loading="contacts.loading" :element-loading-text="t('emailManagement.loading')" :empty-text="pageEmpty" table-layout="fixed">
        <EmailContactColumn prop="name" :label="t('emailManagement.name')" min-width="180" show-overflow-tooltip />
        <EmailContactColumn prop="email" :label="t('emailManagement.email')" min-width="280" show-overflow-tooltip />
        <EmailContactColumn :label="t('emailManagement.createdAt')" width="200" show-overflow-tooltip><template #default="{ row }">{{ timestamp(row.createTime) }}</template></EmailContactColumn>
        <EmailContactColumn :label="t('emailManagement.actions')" width="100" fixed="right" align="center" header-align="center"><template #default="{ row }"><button type="button" class="email-icon-button danger" :disabled="busy" :title="t('emailManagement.delete')" :aria-label="t('emailManagement.delete')" @click="openAction({ kind: 'deleteContact', contact: { ...row } })"><i class="i-mdi-trash-can-outline" aria-hidden="true" /></button></template></EmailContactColumn>
      </el-table>
      <el-table v-else-if="serviceTab === 'enabled'" :data="enabledRows" height="100%" row-key="id" v-loading="enabled.loading" :element-loading-text="t('emailManagement.loading')" :empty-text="pageEmpty" table-layout="fixed">
        <EmailTenantConfigColumn :label="t('emailManagement.tenant')" min-width="220" show-overflow-tooltip><template #default="{ row }">{{ row.tenantName || t('emailManagement.tenantId', { id: row.tenantId }) }}</template></EmailTenantConfigColumn>
        <EmailTenantConfigColumn :label="t('emailManagement.sender')" min-width="260" show-overflow-tooltip><template #default="{ row }"><div class="email-cell-lines"><span>{{ row.senderEmail || t('emailManagement.missingSender') }}</span><small v-if="row.active === false">{{ t('emailManagement.notReady') }}</small></div></template></EmailTenantConfigColumn>
        <EmailTenantConfigColumn prop="domainName" :label="t('emailManagement.domain')" min-width="180" show-overflow-tooltip />
        <EmailTenantConfigColumn :label="t('emailManagement.quota')" min-width="245"><template #default="{ row }"><div class="email-quota"><span>{{ count(row.todaySentCount) }} / {{ count(row.dailyEmailLimit) }}</span><div v-if="quotaRatio(row) !== null" class="email-quota-track" aria-hidden="true"><span :style="{ width: `${quotaRatio(row)}%` }" :class="{ warning: (quotaRatio(row) || 0) >= 75, danger: (quotaRatio(row) || 0) >= 90 }" /></div><small>{{ t('emailManagement.counterDate', { date: row.lastResetDate || '—' }) }}</small></div></template></EmailTenantConfigColumn>
        <EmailTenantConfigColumn :label="t('emailManagement.actions')" width="110" fixed="right" align="center" header-align="center"><template #default="{ row }"><button type="button" class="email-text-button danger" :disabled="busy" @click="openAction({ kind: 'disable', config: { ...row } })">{{ t('emailManagement.disable') }}</button></template></EmailTenantConfigColumn>
      </el-table>
      <el-table v-else :data="available.rows" height="100%" row-key="id" v-loading="available.loading" :element-loading-text="t('emailManagement.loading')" :empty-text="pageEmpty" table-layout="fixed">
        <EmailAvailableTenantColumn :label="t('emailManagement.tenant')" min-width="270" show-overflow-tooltip><template #default="{ row }">{{ tenantName(row) }}</template></EmailAvailableTenantColumn>
        <EmailAvailableTenantColumn prop="region" :label="t('emailManagement.region')" min-width="200" show-overflow-tooltip />
        <EmailAvailableTenantColumn :label="t('emailManagement.actions')" width="130" fixed="right" align="center" header-align="center"><template #default="{ row }"><button type="button" class="email-text-button" :disabled="busy || row.cloudType !== 1 || row.emailEnable !== 0" @click="openAction({ kind: 'enable', tenant: { ...row } })"><i class="i-mdi-plus" aria-hidden="true" />{{ t('emailManagement.enable') }}</button></template></EmailAvailableTenantColumn>
      </el-table>
    </div>
    <PagePagination :current-page="activePager.page" :page-size="activePager.size" :total="activePager.total" :disabled="activePager.loading || busy" :aria-label="t('emailManagement.pagination')" @current-change="paginate"><span>{{ activePager.loaded ? t('emailManagement.count', { count: number(activePager.total) }) : t('emailManagement.countUnknown') }}<template v-if="section === 'services' && serviceTab === 'enabled' && keyword.trim()"> · {{ t('emailManagement.filteredPage', { count: number(enabledRows.length) }) }}</template></span></PagePagination>
    <EmailComposeDialog ref="composer" v-model="composeOpen" @sent="afterSend" @busy="composeBusy = $event" />
    <EmailRecordDetailDialog :record="selectedBody" @close="closeBody" />
    <el-dialog :model-value="!!action" :title="actionTitle" width="560px" class="email-action-dialog" append-to-body :close-on-click-modal="false" :close-on-press-escape="mutationState !== 'pending'" :show-close="mutationState !== 'pending'" @update:model-value="closeAction">
      <form v-if="action" id="email-action-form" class="email-action-form" @submit.prevent="submitAction">
        <p v-if="actionDescription" class="email-action-description">{{ actionDescription }}</p>
        <div v-if="action.kind === 'enable'" class="email-action-fields"><p class="email-action-context">{{ tenantName(action.tenant) }}</p><label for="email-enable-domain">{{ t('emailManagement.domain') }}</label><el-input id="email-enable-domain" v-model="domain" :placeholder="t('emailManagement.domainPlaceholder')" :disabled="mutationState !== 'idle'" autocomplete="off" /><p v-if="domain.trim()" class="email-action-note">{{ t('emailManagement.senderPreview', { domain: domain.trim() }) }}</p></div>
        <div v-else-if="action.kind === 'disable'" class="email-action-context">{{ action.config.tenantName }} · {{ action.config.senderEmail || action.config.domainName }}</div>
        <div v-else-if="action.kind === 'addContact'" class="email-action-fields"><label for="email-contact-name">{{ t('emailManagement.name') }}</label><el-input id="email-contact-name" v-model="contactName" :disabled="mutationState !== 'idle'" autocomplete="name" /><label for="email-contact-address">{{ t('emailManagement.email') }}</label><el-input id="email-contact-address" v-model="contactAddress" :disabled="mutationState !== 'idle'" autocomplete="email" /></div>
        <p v-if="mutationState === 'pending'" role="status" class="email-action-note">{{ t('emailManagement.processing') }}</p>
        <PageErrorNotice v-if="actionProblem && !validationKey" class="email-action-notice">{{ actionProblem }}</PageErrorNotice>
        <p v-else-if="actionProblem" class="email-action-error" role="alert">{{ actionProblem }}</p>
        <p v-if="mutationNote" class="email-action-warning" role="status">{{ t(`emailManagement.${mutationNote}`) }}</p>
      </form>
      <template #footer><GhostBtn :disabled="mutationState === 'pending'" @click="closeAction">{{ t(mutationState === 'uncertain' ? 'emailManagement.close' : 'emailManagement.cancel') }}</GhostBtn><GhostBtn v-if="mutationState === 'uncertain'" @click="inspectLatest">{{ t('emailManagement.inspect') }}</GhostBtn><button v-else-if="dangerAction" type="submit" form="email-action-form" class="email-confirm-danger" :disabled="mutationState === 'pending'">{{ t(mutationState === 'pending' ? 'emailManagement.processing' : 'emailManagement.confirm') }}</button><PrimaryBtn v-else type="submit" form="email-action-form" :loading="mutationState === 'pending'">{{ t(action?.kind === 'addContact' ? 'emailManagement.save' : 'emailManagement.enable') }}</PrimaryBtn></template>
    </el-dialog>
  </section>
</template>

<style lang="scss" src="./email.scss" />
