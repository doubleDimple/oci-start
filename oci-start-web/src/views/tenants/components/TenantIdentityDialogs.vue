<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantGet, tenantPost } from '@/api/tenant'

type Row = Record<string, any>
type LoadKey = 'users' | 'groups' | 'notifications' | 'mfa' | 'policy' | 'email' | 'social'
const props = defineProps<{ tenant: Row | null; action: string }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const { t, locale } = useI18n()
const tenantId = computed(() => String(props.tenant?.id ?? ''))
const tenantName = computed(() => props.tenant?.defName || props.tenant?.tenancyName || t('tenantIdentity.currentTenant'))
const visible = computed(() => !!props.tenant && ['users', 'email', 'social'].includes(props.action))
const title = computed(() => ['users', 'email', 'social'].includes(props.action) ? t(`tenantIdentity.titles.${props.action}`) : '')
const tab = ref('users')
const editor = ref('')
const busy = ref(false)
const loading = reactive<Record<LoadKey, boolean>>({ users: false, groups: false, notifications: false, mfa: false, policy: false, email: false, social: false })
const errors = reactive<Record<LoadKey, unknown>>({ users: null, groups: null, notifications: null, mfa: null, policy: null, email: null, social: null })
const users = ref<Row[]>([])
const page = ref(1)
const pageSize = 5
const pageUsers = computed(() => users.value.slice((page.value - 1) * pageSize, page.value * pageSize))
const groups = ref<Row[]>([])
const groupsReady = ref(false)
const userForm = reactive({ username: '', email: '', groupId: '', useEmail: false })
const recipients = ref<string[]>([])
const notificationEmail = ref('')
const mfa = ref<Row | null>(null)
const policies = ref<Row[]>([])
const policyReady = ref(false)
const policyForm = reactive({ enablePasswordExpiry: false, expiryDays: 120 })
const credentials = ref<Row | null>(null)
const emailDomain = ref('')
const emailReadOnly = ref(false)
const socialRows = ref<Row[]>([])
const socialTypes = ref<string[]>([])
const socialForm = reactive({ id: '', socialTypeStr: '', clientId: '', clientSecret: '', redirectUrl: '' })
const mfaFactors = computed(() => [
  { key: 'emailEnabled', name: t('tenantIdentity.factors.email'), description: t('tenantIdentity.factors.emailDescription'), icon: 'i-mdi-email-outline' },
  { key: 'pushEnabled', name: t('tenantIdentity.factors.push'), description: t('tenantIdentity.factors.pushDescription'), icon: 'i-mdi-cellphone-check' },
  { key: 'totpEnabled', name: t('tenantIdentity.factors.totp'), description: t('tenantIdentity.factors.totpDescription'), icon: 'i-mdi-shield-key-outline' },
])
let generation = 0
let confirming = false
let readController = new AbortController()
const readVersions: Partial<Record<LoadKey, number>> = {}

function errorMessage(error: any): string {
  if (error?.translationKey) return t(error.translationKey, { reason: errorMessage(error.cause) })
  return String(error?.response?.data?.message || error?.message || error?.msg || t('tenantIdentity.messages.error'))
}

async function read<T>(key: LoadKey, request: (signal: AbortSignal) => Promise<T>, apply: (data: T) => void) {
  const current = generation
  const version = (readVersions[key] || 0) + 1
  readVersions[key] = version
  loading[key] = true
  errors[key] = null
  try {
    const data = await request(readController.signal)
    if (current === generation && readVersions[key] === version) apply(data)
  } catch (error: any) {
    if (current === generation && readVersions[key] === version && error?.code !== 'ERR_CANCELED') errors[key] = error
  } finally {
    if (current === generation && readVersions[key] === version) loading[key] = false
  }
}

async function confirm(message: string, heading: string) {
  if (confirming || busy.value) return false
  confirming = true
  try {
    await ElMessageBox.confirm(message, heading, { confirmButtonText: t('tenantIdentity.actions.confirm'), cancelButtonText: t('tenantIdentity.actions.cancel'), type: 'warning', closeOnClickModal: false })
    return true
  } catch { return false }
  finally { confirming = false }
}

async function mutate(request: () => Promise<any>, success: (data: any) => void | Promise<void>, messageKey = 'tenantIdentity.messages.saved') {
  if (busy.value) return
  const current = generation
  busy.value = true
  try {
    const result = await request()
    if (current !== generation) return
    ElMessage.success(t(messageKey))
    emit('changed')
    await success(result)
  } catch (error) {
    if (current === generation) ElMessage.error(errorMessage(error))
  } finally {
    if (current === generation) busy.value = false
  }
}

function close() {
  if (!busy.value) emit('close')
}

function loadUsers() {
  return read('users', signal => tenantGet<Row[]>('/tenants/oracle-users', { tenantId: tenantId.value }, { signal }), data => {
    users.value = Array.isArray(data) ? data : []
    page.value = Math.max(1, Math.min(page.value, Math.ceil(users.value.length / pageSize)))
  })
}

function loadGroups() {
  groupsReady.value = false
  return read('groups', signal => tenantPost<Row[]>('/tenants/groups', { tenantId: tenantId.value }, { signal }), data => {
    groups.value = Array.isArray(data) ? data : []
    groupsReady.value = true
  })
}

function addUser() {
  Object.assign(userForm, { username: '', email: '', groupId: '', useEmail: false })
  editor.value = 'user'
  void loadGroups()
}

async function createUser() {
  const email = userForm.email.trim()
  const username = userForm.useEmail ? email : userForm.username.trim()
  if (!username || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !userForm.groupId) {
    ElMessage.warning(t('tenantIdentity.validation.user'))
    return
  }
  const groupName = groups.value.find(group => group.groupId === userForm.groupId)?.groupName || ''
  await mutate(() => tenantPost('/tenants/oracle-users', { tenantId: tenantId.value, username, email, groupId: userForm.groupId }), async result => {
    editor.value = ''
    credentials.value = { username: result.username, email: result.email, group: groupName, password: result.password }
    page.value = 1
    await loadUsers()
  }, 'tenantIdentity.messages.userCreated')
}

async function resetPassword(user: Row) {
  if (!await confirm(t('tenantIdentity.confirmations.resetPassword', { username: displayUsername(user.username) }), t('tenantIdentity.actions.resetPassword'))) return
  await mutate(() => tenantPost('/tenants/oracle-users/resetPassword', { tenantId: tenantId.value, userId: user.id, userName: user.username }, { timeout: 30000 }), result => {
    const data = result.data || {}
    credentials.value = { username: data.loginUser || displayUsername(user.username), password: data.temporaryPassword || '', resetTime: data.resetTime }
  }, 'tenantIdentity.messages.passwordReset')
}

async function deleteUser(user: Row) {
  if (!await confirm(t('tenantIdentity.confirmations.deleteUser', { username: displayUsername(user.username) }), t('tenantIdentity.actions.deleteUser'))) return
  await mutate(() => tenantPost('/tenants/oracle-users/deleteUser', { tenantId: tenantId.value, userId: user.id }), loadUsers, 'tenantIdentity.messages.userDeleted')
}

function displayUsername(value: string = '') { return value.split('/').pop() || '—' }

function userStatus(value?: string) {
  const key = String(value || '').toLowerCase()
  return ['active', 'inactive', 'creating', 'updating', 'deleting', 'deleted', 'failed', 'locked'].includes(key)
    ? t(`tenantIdentity.status.${key}`)
    : value || t('tenantIdentity.status.unknown')
}

function closeEditor() {
  editor.value = ''
  notificationEmail.value = ''
  socialForm.clientSecret = ''
}

function loadPolicy() {
  policyReady.value = false
  return read('policy', signal => tenantPost('/tenants/oracle-users/getPasspolicy', { tenantId: tenantId.value }, { signal }), result => {
    policies.value = Array.isArray(result.data) ? result.data : []
    policyForm.enablePasswordExpiry = policies.value.some(policy => policy.enablePasswordExpiry)
    const days = policies.value.filter(policy => policy.expiryDays != null).map(policy => Number(policy.expiryDays))
    policyForm.expiryDays = days.length ? Math.min(...days) : 120
    policyReady.value = true
  })
}

function openPolicy() {
  editor.value = 'policy'
  void loadPolicy()
}

async function savePolicy() {
  const days = Number(policyForm.expiryDays)
  if (policyForm.enablePasswordExpiry && (!Number.isInteger(days) || days < 0 || days > 365)) {
    ElMessage.warning(t('tenantIdentity.validation.expiryDays'))
    return
  }
  await mutate(() => tenantPost('/tenants/oracle-users/password-policy', {
    tenantId: tenantId.value,
    enablePasswordExpiry: policyForm.enablePasswordExpiry,
    expiryDays: policyForm.enablePasswordExpiry ? days : null,
  }), () => { editor.value = '' }, 'tenantIdentity.messages.policySaved')
}

function loadRecipients() {
  return read('notifications', signal => tenantPost('/tenants/notification/recipients', { tenantId: tenantId.value }, { signal }), result => {
    recipients.value = result.recipients || []
  })
}

async function updateRecipient(removeEmail?: string) {
  const email = notificationEmail.value.trim().toLowerCase()
  if (!removeEmail && !/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(email)) {
    ElMessage.warning(t('tenantIdentity.validation.email'))
    return
  }
  if (removeEmail && !await confirm(t('tenantIdentity.confirmations.removeRecipient', { email: removeEmail }), t('tenantIdentity.actions.removeRecipient'))) return
  await mutate(async () => {
    // 修改前重新读取完整列表，避免用过期列表覆盖其他收件人。
    const latest = await tenantPost('/tenants/notification/recipients', { tenantId: tenantId.value })
    const current: string[] = latest.recipients || []
    if (!removeEmail && current.some(item => item.toLowerCase() === email)) throw new Error(t('tenantIdentity.validation.duplicateRecipient'))
    const emails = removeEmail ? current.filter(item => item !== removeEmail) : [...current, email]
    if (!emails.length) throw new Error(t('tenantIdentity.validation.lastRecipient'))
    return tenantPost('/tenants/notification/update', { tenantId: tenantId.value, emails })
  }, async () => {
    notificationEmail.value = ''
    editor.value = ''
    await loadRecipients()
  }, removeEmail ? 'tenantIdentity.messages.recipientRemoved' : 'tenantIdentity.messages.recipientAdded')
}

function loadMfa() {
  return read('mfa', signal => tenantGet('/tenants/mfa/status', { tenantId: tenantId.value }, { signal }), result => { mfa.value = result.data || {} })
}

async function updateEmailMfa(enableEmail: boolean) {
  const action = enableEmail ? 'enableEmailMfa' : 'disableEmailMfa'
  if (!await confirm(t(`tenantIdentity.confirmations.${action}`), t(`tenantIdentity.actions.${action}`))) return
  await mutate(() => tenantPost('/tenants/mfa/email', { tenantId: tenantId.value, enableEmail }), loadMfa, 'tenantIdentity.messages.emailMfaSaved')
}

async function resetMfa() {
  if (!await confirm(t('tenantIdentity.confirmations.resetMfa'), t('tenantIdentity.actions.resetMfa'))) return
  await mutate(() => tenantPost('/tenants/resetAccountFactor', new URLSearchParams({ tenantId: tenantId.value }), { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }), loadMfa, 'tenantIdentity.messages.mfaReset')
}

function loadEmail() {
  return read('email', signal => tenantPost('/email/tenant/get', { tenantId: tenantId.value }, { signal }), result => {
    emailDomain.value = result.data?.[0]?.domainName || ''
  })
}

async function saveEmail() {
  const domain = emailDomain.value.trim()
  if (!domain || domain.length > 100 || !/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/.test(domain)) {
    ElMessage.warning(t('tenantIdentity.validation.domain'))
    return
  }
  if (!await confirm(t('tenantIdentity.confirmations.configureEmail', { tenant: tenantName.value, domain }), t('tenantIdentity.actions.configureEmail'))) return
  await mutate(() => tenantPost('/tenants/email/enable', { tenantId: tenantId.value, emailDomain: domain }, { timeout: 60000 }), () => { emailReadOnly.value = true }, 'tenantIdentity.messages.emailConfigured')
}

function loadSocial() {
  return read('social', async signal => {
    const results = await Promise.allSettled([
      tenantPost('/social/list', { tenantId: tenantId.value, cloudType: Number(props.tenant?.cloudType || 1) }, { signal }),
      tenantPost('/social/availableLoginTypes', undefined, { signal }),
    ])
    const listResult = results[0]
    const typesResult = results[1]
    if (listResult.status === 'rejected') throw listResult.reason
    return {
      rows: listResult.value.data || [],
      types: typesResult.status === 'fulfilled' ? typesResult.value.data || [] : [],
      typeError: typesResult.status === 'rejected' ? { translationKey: 'tenantIdentity.messages.socialTypesFailed', cause: typesResult.reason } : null,
    }
  }, result => {
    socialRows.value = result.rows
    socialTypes.value = result.types
    errors.social = result.typeError
  })
}

function editSocial(row?: Row) {
  Object.assign(socialForm, {
    id: row?.id || '', socialTypeStr: row?.socialTypeStr || row?.serviceProviderName || socialTypes.value[0] || '',
    clientId: row?.clientId || '', clientSecret: row?.clientSecret || '', redirectUrl: row?.redirectUrl || '',
  })
  editor.value = 'social'
}

async function saveSocial() {
  if (!socialForm.socialTypeStr || !socialForm.clientId.trim() || !socialForm.clientSecret.trim()) {
    ElMessage.warning(t('tenantIdentity.validation.social'))
    return
  }
  await mutate(() => tenantPost(socialForm.id ? '/social/update' : '/social/add', {
    id: socialForm.id || null,
    tenantId: tenantId.value,
    cloudType: Number(props.tenant?.cloudType || 1),
    socialTypeStr: socialForm.socialTypeStr,
    clientId: socialForm.clientId.trim(),
    clientSecret: socialForm.clientSecret.trim(),
  }), async () => {
    editor.value = ''
    socialForm.clientSecret = ''
    await loadSocial()
  }, 'tenantIdentity.messages.socialSaved')
}

async function toggleSocial(row: Row) {
  const enable = row.socialStatus === 'disabled'
  const provider = row.socialTypeStr || row.serviceProviderName
  if (!await confirm(t(enable ? 'tenantIdentity.confirmations.enableSocial' : 'tenantIdentity.confirmations.disableSocial', { provider }), t('tenantIdentity.actions.changeLoginStatus'))) return
  await mutate(() => tenantPost(enable ? '/social/enable' : '/social/disable', {
    id: row.id,
    tenantId: tenantId.value,
    cloudType: Number(props.tenant?.cloudType || 1),
    socialTypeStr: provider,
    ...(!enable ? { socialStatus: 'disabled' } : {}),
  }), loadSocial, enable ? 'tenantIdentity.messages.socialEnabled' : 'tenantIdentity.messages.socialDisabled')
}

function socialStatus(status: string | null) {
  if (!status || status === 'null' || status === 'active') return t('tenantIdentity.status.enabled')
  return ['disabled', 'inactive'].includes(status) ? t(`tenantIdentity.status.${status}`) : status
}

async function copy(value: string) {
  try {
    await navigator.clipboard.writeText(value)
    ElMessage.success(t('tenantIdentity.messages.copied'))
  } catch { ElMessage.warning(t('tenantIdentity.messages.copyFailed')) }
}

function copyCredentials() {
  const data = credentials.value
  if (!data) return
  const line = (label: string, value: string) => t('tenantIdentity.credentialLine', { label: t(`tenantIdentity.labels.${label}`), value })
  void copy([line('username', data.username), data.email && line('email', data.email), data.group && line('userGroup', data.group), line('temporaryPassword', data.password)].filter(Boolean).join('\n'))
}

watch(() => [props.action, tenantId.value], () => {
  generation += 1
  readController.abort()
  readController = new AbortController()
  Object.keys(loading).forEach(key => { loading[key as LoadKey] = false; errors[key as LoadKey] = null })
  busy.value = false
  editor.value = ''
  tab.value = 'users'
  page.value = 1
  users.value = []
  groups.value = []
  groupsReady.value = false
  policies.value = []
  policyReady.value = false
  recipients.value = []
  mfa.value = null
  credentials.value = null
  notificationEmail.value = ''
  emailDomain.value = ''
  socialRows.value = []
  socialTypes.value = []
  socialForm.clientSecret = ''
  if (!visible.value) return
  if (props.action === 'users') void loadUsers()
  if (props.action === 'social') void loadSocial()
  if (props.action === 'email') {
    emailReadOnly.value = Number(props.tenant?.emailEnable) === 1
    if (emailReadOnly.value) void loadEmail()
  }
}, { immediate: true })

watch(tab, value => {
  editor.value = ''
  if (!visible.value || props.action !== 'users') return
  if (value === 'notifications') void loadRecipients()
  if (value === 'mfa') void loadMfa()
})

onBeforeUnmount(() => { generation += 1; readController.abort() })
</script>

<template>
  <el-dialog :model-value="visible" :title="title" :width="action === 'email' ? 'min(560px, calc(100vw - 32px))' : 'min(1040px, calc(100vw - 32px))'" class="tenant-identity-dialog" align-center destroy-on-close :close-on-click-modal="false" :close-on-press-escape="!busy" :show-close="!busy" @close="close">
    <div class="identity-content" :aria-busy="busy">
      <p class="tenant-context"><span class="context-dot" />{{ tenantName }}</p>

      <template v-if="action === 'users'">
        <el-tabs v-model="tab" class="identity-tabs">
          <el-tab-pane :label="t('tenantIdentity.tabs.users')" name="users" :disabled="busy" />
          <el-tab-pane :label="t('tenantIdentity.tabs.notifications')" name="notifications" :disabled="busy" />
          <el-tab-pane :label="t('tenantIdentity.tabs.mfa')" name="mfa" :disabled="busy" />
        </el-tabs>
        <Transition name="identity-panel" mode="out-in">
          <section v-if="tab === 'users'" :key="'users-' + editor" class="identity-panel">
            <template v-if="!editor">
              <div class="toolbar"><p class="secondary">{{ t('tenantIdentity.descriptions.users') }}</p><div class="actions"><el-button :disabled="busy || loading.users" @click="loadUsers">{{ t('tenantIdentity.actions.refresh') }}</el-button><el-button :disabled="busy" @click="openPolicy">{{ t('tenantIdentity.actions.passwordPolicy') }}</el-button><el-button type="primary" :disabled="busy" @click="addUser">{{ t('tenantIdentity.actions.addUser') }}</el-button></div></div>
              <el-alert v-if="errors.users" :title="errorMessage(errors.users)" type="error" :closable="false" show-icon />
              <el-table v-loading="loading.users" :data="pageUsers" row-key="id" class="identity-table" max-height="440" :empty-text="t('tenantIdentity.empty.users')">
                <el-table-column prop="domain" :label="t('tenantIdentity.labels.domain')" min-width="105" show-overflow-tooltip />
                <el-table-column :label="t('tenantIdentity.labels.username')" min-width="135" show-overflow-tooltip><template #default="{ row }"><span class="user-name">{{ displayUsername(row.username) }}</span></template></el-table-column>
                <el-table-column prop="email" :label="t('tenantIdentity.labels.email')" min-width="185" show-overflow-tooltip />
                <el-table-column :label="t('tenantIdentity.labels.status')" width="88"><template #default="{ row }"><span class="status-pill" :class="row.lifecycleState === 'Active' ? 'is-active' : 'is-inactive'">{{ userStatus(row.lifecycleState) }}</span></template></el-table-column>
                <el-table-column prop="timeCreated" :label="t('tenantIdentity.labels.createdAt')" min-width="165" show-overflow-tooltip />
                <el-table-column :label="t('tenantIdentity.labels.lastLogin')" min-width="165" show-overflow-tooltip><template #default="{ row }">{{ row.lastSuccessfulLoginTime || '—' }}</template></el-table-column>
                <el-table-column :label="t('tenantIdentity.labels.actions')" :width="locale.startsWith('en') ? 188 : 146" fixed="right"><template #default="{ row }"><el-button link :disabled="busy" @click="resetPassword(row)">{{ t('tenantIdentity.actions.resetPassword') }}</el-button><el-button link type="danger" :disabled="busy" @click="deleteUser(row)">{{ t('tenantIdentity.actions.delete') }}</el-button></template></el-table-column>
              </el-table>
              <div class="table-footer"><span class="secondary">{{ t('tenantIdentity.counts.users', { count: users.length }) }}</span><el-pagination v-model:current-page="page" :page-size="pageSize" :total="users.length" :disabled="busy" layout="prev, pager, next" /></div>
            </template>
            <div v-else-if="editor === 'user'" class="form-panel" v-loading="loading.groups">
              <div class="section-title"><el-button text :disabled="busy" @click="closeEditor">← {{ t('tenantIdentity.actions.backToUsers') }}</el-button><h3>{{ t('tenantIdentity.actions.addUser') }}</h3><p class="secondary">{{ t('tenantIdentity.descriptions.newUser') }}</p></div>
              <el-alert v-if="errors.groups" :title="errorMessage(errors.groups)" type="error" :closable="false" show-icon><el-button text @click="loadGroups">{{ t('tenantIdentity.actions.reloadGroups') }}</el-button></el-alert>
              <el-form label-position="top" :disabled="busy" @submit.prevent="createUser">
                <div class="form-grid"><el-form-item :label="t('tenantIdentity.labels.username')" required><el-input :model-value="userForm.useEmail ? userForm.email : userForm.username" @update:model-value="userForm.username = $event" :disabled="userForm.useEmail" :placeholder="t('tenantIdentity.placeholders.username')" autocomplete="off" /></el-form-item><el-form-item :label="t('tenantIdentity.labels.email')" required><el-input v-model="userForm.email" type="email" :placeholder="t('tenantIdentity.placeholders.email')" /></el-form-item></div>
                <el-checkbox v-model="userForm.useEmail">{{ t('tenantIdentity.labels.useEmail') }}</el-checkbox>
                <el-form-item :label="t('tenantIdentity.labels.userGroup')" required><el-select v-model="userForm.groupId" :placeholder="t('tenantIdentity.placeholders.group')" :disabled="!groupsReady"><el-option v-for="group in groups" :key="group.groupId" :label="group.groupName" :value="group.groupId" /></el-select></el-form-item>
                <div class="form-actions"><el-button :disabled="busy" @click="closeEditor">{{ t('tenantIdentity.actions.cancel') }}</el-button><el-button type="primary" native-type="submit" :loading="busy" :disabled="!groupsReady || !groups.length">{{ t('tenantIdentity.actions.createUser') }}</el-button></div>
              </el-form>
            </div>
            <div v-else-if="editor === 'policy'" class="form-panel" v-loading="loading.policy">
              <div class="section-title"><el-button text :disabled="busy" @click="closeEditor">← {{ t('tenantIdentity.actions.backToUsers') }}</el-button><h3>{{ t('tenantIdentity.actions.passwordPolicy') }}</h3><p class="secondary">{{ t('tenantIdentity.descriptions.policy') }}</p></div>
              <el-alert v-if="errors.policy" :title="errorMessage(errors.policy)" type="error" :closable="false" show-icon><el-button text @click="loadPolicy">{{ t('tenantIdentity.actions.reload') }}</el-button></el-alert>
              <div v-if="policies.length" class="policy-list"><div v-for="(policy, index) in policies" :key="index" class="policy-row"><span>{{ policy.name || t('tenantIdentity.labels.policy', { index: index + 1 }) }}</span><span class="secondary">{{ policy.enablePasswordExpiry ? t('tenantIdentity.status.expiresIn', { days: policy.expiryDays ?? 0 }) : t('tenantIdentity.status.neverExpires') }}</span></div></div>
              <el-form label-position="top" :disabled="busy || !policyReady" @submit.prevent="savePolicy"><div class="setting-row"><div><strong>{{ t('tenantIdentity.labels.enablePasswordExpiry') }}</strong><p class="secondary">{{ t('tenantIdentity.descriptions.passwordExpiry') }}</p></div><el-switch v-model="policyForm.enablePasswordExpiry" :aria-label="t('tenantIdentity.labels.enablePasswordExpiry')" /></div><el-form-item v-if="policyForm.enablePasswordExpiry" :label="t('tenantIdentity.labels.expiryDays')"><el-input-number v-model="policyForm.expiryDays" :min="0" :max="365" :precision="0" /></el-form-item><div class="form-actions"><el-button :disabled="busy" @click="closeEditor">{{ t('tenantIdentity.actions.cancel') }}</el-button><el-button type="primary" native-type="submit" :loading="busy" :disabled="!policyReady">{{ t('tenantIdentity.actions.savePolicy') }}</el-button></div></el-form>
            </div>
          </section>

          <section v-else-if="tab === 'notifications'" key="notifications" class="identity-panel">
            <div class="toolbar"><p class="secondary">{{ t('tenantIdentity.descriptions.notifications') }}</p><div class="actions"><el-button :disabled="busy || loading.notifications" @click="loadRecipients">{{ t('tenantIdentity.actions.refresh') }}</el-button><el-button v-if="editor !== 'notification'" type="primary" :disabled="busy" @click="editor = 'notification'">{{ t('tenantIdentity.actions.addRecipient') }}</el-button></div></div>
            <el-alert v-if="errors.notifications" :title="errorMessage(errors.notifications)" type="error" :closable="false" show-icon />
            <el-form v-if="editor === 'notification'" class="notification-form" label-position="top" @submit.prevent="updateRecipient()"><el-form-item :label="t('tenantIdentity.labels.notificationEmail')" required><el-input v-model="notificationEmail" type="email" :placeholder="t('tenantIdentity.placeholders.email')" :disabled="busy" /></el-form-item><div class="actions"><el-button :disabled="busy" @click="closeEditor">{{ t('tenantIdentity.actions.cancel') }}</el-button><el-button type="primary" native-type="submit" :loading="busy">{{ t('tenantIdentity.actions.add') }}</el-button></div></el-form>
            <el-table v-loading="loading.notifications" :data="recipients.map(email => ({ email }))" row-key="email" class="identity-table" :empty-text="t('tenantIdentity.empty.recipients')"><el-table-column type="index" :label="t('tenantIdentity.labels.index')" width="70" /><el-table-column prop="email" :label="t('tenantIdentity.labels.notificationEmail')" min-width="210" show-overflow-tooltip /><el-table-column :label="t('tenantIdentity.labels.status')" width="90"><template #default><span class="status-pill is-active">{{ t('tenantIdentity.status.normal') }}</span></template></el-table-column><el-table-column :label="t('tenantIdentity.labels.actions')" width="90"><template #default="{ row }"><el-button link type="danger" :disabled="busy" @click="updateRecipient(row.email)">{{ t('tenantIdentity.actions.remove') }}</el-button></template></el-table-column></el-table>
            <div class="table-footer secondary">{{ t('tenantIdentity.counts.recipients', { count: recipients.length }) }}</div>
          </section>

          <section v-else key="mfa" class="identity-panel" v-loading="loading.mfa">
            <div class="toolbar"><p class="secondary">{{ t('tenantIdentity.descriptions.mfa') }}</p><el-button :disabled="busy || loading.mfa" @click="loadMfa">{{ t('tenantIdentity.actions.refreshStatus') }}</el-button></div>
            <el-alert v-if="errors.mfa" :title="errorMessage(errors.mfa)" type="error" :closable="false" show-icon />
            <div class="factor-list"><div v-for="factor in mfaFactors" :key="factor.key" class="factor-row"><div class="factor-icon" :class="factor.icon" /><div class="factor-label"><strong>{{ factor.name }}</strong><p class="secondary">{{ factor.description }}</p></div><span class="status-pill" :class="mfa?.[factor.key] ? 'is-active' : 'is-inactive'">{{ t(mfa ? (mfa[factor.key] ? 'tenantIdentity.status.enabled' : 'tenantIdentity.status.notEnabled') : 'tenantIdentity.status.pending') }}</span></div></div>
            <div class="form-actions spread"><el-button :disabled="busy" @click="resetMfa">{{ t('tenantIdentity.actions.resetMfa') }}</el-button><div class="actions"><el-button :disabled="busy || !mfa" @click="updateEmailMfa(false)">{{ t('tenantIdentity.actions.disableEmailMfa') }}</el-button><el-button type="primary" :disabled="busy || !mfa" :loading="busy" @click="updateEmailMfa(true)">{{ t('tenantIdentity.actions.enableEmailMfa') }}</el-button></div></div>
          </section>
        </Transition>
      </template>

      <section v-else-if="action === 'email'" class="identity-panel email-panel" v-loading="loading.email">
        <div class="service-icon i-mdi-email-fast-outline" /><h3>{{ t('tenantIdentity.descriptions.emailTitle') }}</h3><p class="secondary">{{ t('tenantIdentity.descriptions.email') }}</p>
        <el-alert v-if="errors.email" :title="errorMessage(errors.email)" type="error" :closable="false" show-icon><el-button text @click="loadEmail">{{ t('tenantIdentity.actions.reload') }}</el-button></el-alert>
        <el-form label-position="top" @submit.prevent="saveEmail"><el-form-item :label="t('tenantIdentity.labels.emailDomain')" required><el-input v-model="emailDomain" :placeholder="t('tenantIdentity.placeholders.domain')" :maxlength="100" :disabled="emailReadOnly || busy" /></el-form-item><p class="field-hint">{{ t('tenantIdentity.descriptions.emailDomain') }}</p><div class="form-actions"><el-button :disabled="busy" @click="close">{{ t('tenantIdentity.actions.close') }}</el-button><el-button v-if="emailReadOnly" :disabled="loading.email || !!errors.email" @click="emailReadOnly = false">{{ t('tenantIdentity.actions.reconfigure') }}</el-button><el-button v-else type="primary" native-type="submit" :loading="busy">{{ t('tenantIdentity.actions.configureEmail') }}</el-button></div></el-form>
      </section>

      <section v-else-if="action === 'social'" class="identity-panel">
        <template v-if="editor !== 'social'">
          <div class="toolbar"><p class="secondary">{{ t('tenantIdentity.descriptions.social') }}</p><div class="actions"><el-button :disabled="busy || loading.social" @click="loadSocial">{{ t('tenantIdentity.actions.refresh') }}</el-button><el-button type="primary" :disabled="busy || !socialTypes.length" @click="editSocial()">{{ t('tenantIdentity.actions.addSocial') }}</el-button></div></div>
          <el-alert v-if="errors.social" :title="errorMessage(errors.social)" type="error" :closable="false" show-icon />
          <el-table v-loading="loading.social" :data="socialRows" row-key="id" class="identity-table" :empty-text="t('tenantIdentity.empty.social')"><el-table-column :label="t('tenantIdentity.labels.loginService')" min-width="130"><template #default="{ row }"><span class="user-name">{{ row.socialTypeStr || row.serviceProviderName || t('tenantIdentity.status.unknown') }}</span></template></el-table-column><el-table-column prop="clientId" :label="t('tenantIdentity.labels.clientId')" min-width="170" show-overflow-tooltip /><el-table-column prop="redirectUrl" :label="t('tenantIdentity.labels.redirectUrl')" min-width="230" show-overflow-tooltip /><el-table-column :label="t('tenantIdentity.labels.status')" width="100"><template #default="{ row }"><span class="status-pill" :class="!row.socialStatus || row.socialStatus === 'null' || row.socialStatus === 'active' ? 'is-active' : 'is-inactive'">{{ socialStatus(row.socialStatus) }}</span></template></el-table-column><el-table-column :label="t('tenantIdentity.labels.actions')" :width="locale.startsWith('en') ? 154 : 126" fixed="right"><template #default="{ row }"><el-button link :disabled="busy" @click="editSocial(row)">{{ t('tenantIdentity.actions.edit') }}</el-button><el-button link :disabled="busy" :type="row.socialStatus === 'disabled' ? 'primary' : 'danger'" @click="toggleSocial(row)">{{ t(row.socialStatus === 'disabled' ? 'tenantIdentity.actions.enable' : 'tenantIdentity.actions.disable') }}</el-button></template></el-table-column></el-table>
        </template>
        <div v-else class="form-panel"><div class="section-title"><el-button text :disabled="busy" @click="closeEditor">← {{ t('tenantIdentity.actions.backToSocial') }}</el-button><h3>{{ t(socialForm.id ? 'tenantIdentity.actions.editSocial' : 'tenantIdentity.actions.addSocial') }}</h3></div><el-form label-position="top" :disabled="busy" @submit.prevent="saveSocial"><el-form-item :label="t('tenantIdentity.labels.loginService')" required><el-input v-if="socialForm.id" :model-value="socialForm.socialTypeStr" readonly /><el-select v-else v-model="socialForm.socialTypeStr" :placeholder="t('tenantIdentity.placeholders.loginService')"><el-option v-for="provider in socialTypes" :key="provider" :label="provider" :value="provider" /></el-select></el-form-item><el-form-item :label="t('tenantIdentity.labels.clientIdField')" required><el-input v-model="socialForm.clientId" autocomplete="off" /></el-form-item><el-form-item :label="t('tenantIdentity.labels.clientSecret')" required><el-input v-model="socialForm.clientSecret" type="password" show-password autocomplete="new-password" /></el-form-item><el-form-item v-if="socialForm.redirectUrl" :label="t('tenantIdentity.labels.redirectUrl')"><div class="copy-field"><el-input :model-value="socialForm.redirectUrl" readonly /><el-button @click="copy(socialForm.redirectUrl)">{{ t('tenantIdentity.actions.copy') }}</el-button></div><p class="field-hint">{{ t('tenantIdentity.descriptions.redirectUrl') }}</p></el-form-item><div class="form-actions"><el-button :disabled="busy" @click="closeEditor">{{ t('tenantIdentity.actions.cancel') }}</el-button><el-button type="primary" native-type="submit" :loading="busy">{{ t('tenantIdentity.actions.saveConfig') }}</el-button></div></el-form></div>
      </section>
    </div>
  </el-dialog>

  <el-dialog :model-value="!!credentials && visible" :title="t('tenantIdentity.actions.saveCredentials')" width="min(520px, calc(100vw - 32px))" align-center append-to-body :close-on-click-modal="false" @close="credentials = null">
    <div v-if="credentials" class="identity-content credential-panel"><el-alert :title="t('tenantIdentity.descriptions.credentials')" type="warning" :closable="false" show-icon /><el-form label-position="top"><el-form-item :label="t('tenantIdentity.labels.username')"><div class="copy-field"><el-input :model-value="credentials.username" readonly /><el-button @click="copy(credentials.username)">{{ t('tenantIdentity.actions.copy') }}</el-button></div></el-form-item><el-form-item v-if="credentials.email" :label="t('tenantIdentity.labels.email')"><el-input :model-value="credentials.email" readonly /></el-form-item><el-form-item v-if="credentials.group" :label="t('tenantIdentity.labels.userGroup')"><el-input :model-value="credentials.group" readonly /></el-form-item><el-form-item :label="t('tenantIdentity.labels.temporaryPassword')"><div class="copy-field"><el-input :model-value="credentials.password" readonly /><el-button @click="copy(credentials.password)">{{ t('tenantIdentity.actions.copy') }}</el-button></div></el-form-item><p v-if="credentials.resetTime" class="secondary">{{ t('tenantIdentity.labels.resetTime', { time: credentials.resetTime }) }}</p></el-form><div class="form-actions"><el-button @click="credentials = null">{{ t('tenantIdentity.actions.savedClose') }}</el-button><el-button type="primary" @click="copyCredentials">{{ t('tenantIdentity.actions.copyAllCredentials') }}</el-button></div></div>
  </el-dialog>
</template>

<style scoped>
.identity-content { color: var(--text-primary); font-family: var(--sans); }
.tenant-context { display: flex; align-items: center; gap: 8px; margin: 0 0 20px; color: var(--text-secondary); font-size: 13px; }
.context-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--brand); }
.identity-tabs { margin-bottom: 10px; }
.identity-tabs :deep(.el-tabs__item) { font-weight: 500; padding: 0 24px; font-size: 14px; }
.identity-tabs :deep(.el-tabs__nav-wrap::after) { height: 1px; }
.identity-panel { min-height: 220px; }
.toolbar, .actions, .form-actions, .table-footer, .setting-row, .factor-row, .policy-row { display: flex; align-items: center; }
.toolbar { justify-content: space-between; gap: 16px; margin-bottom: 22px; flex-wrap: wrap; }
.actions { min-width: 0; gap: 8px; flex-wrap: wrap; }
.actions :deep(.el-button + .el-button) { margin-left: 0; }
.secondary, .field-hint { color: var(--text-secondary); font-size: 13px; line-height: 1.6; margin: 0; }
.identity-content :deep(.el-button) { max-width: 100%; min-height: 32px; height: auto; border-radius: var(--r-btn); font-family: var(--sans); line-height: 1.4; white-space: normal; transition: transform 180ms ease, background-color 180ms ease, border-color 180ms ease; }
.identity-content :deep(.el-button > span) { min-width: 0; overflow-wrap: anywhere; }
.identity-content :deep(.el-button:not(.is-disabled):active) { transform: scale(.97); }
.identity-content :deep(.el-button--primary:not(.is-link)) { border-radius: var(--r-pill); padding-inline: 20px; }
.identity-content :deep(.el-input__wrapper), .identity-content :deep(.el-select__wrapper) { border-radius: var(--r-sm); min-height: 40px; }
.identity-content :deep(.el-input__inner), .identity-content :deep(.el-form-item__label), .identity-content :deep(.el-table) { font-family: var(--sans); }
.identity-content :deep(.el-alert) { margin-bottom: 20px; border-radius: var(--r-sm); }
.identity-content :deep(.el-select) { width: 100%; }
.identity-content :deep(.el-checkbox) { margin-bottom: 16px; }
.identity-content :deep(.el-form-item__label) { color: var(--text-primary); }
.identity-table { border: 1px solid var(--border); border-radius: var(--r-sm); }
.identity-table :deep(th.el-table__cell) { font-size: 12px; font-weight: 500; color: var(--text-secondary); background: var(--bg-hover); }
.identity-table :deep(td.el-table__cell) { padding-block: 13px; }
.user-name { font-weight: 500; }
.status-pill { display: inline-flex; align-items: center; gap: 5px; max-width: 100%; border-radius: var(--r-pill); padding: 3px 9px; font-size: 11px; overflow-wrap: anywhere; }
.status-pill::before { content: ''; width: 4px; height: 4px; background: currentColor; border-radius: 50%; }
.is-active { background: var(--status-ok-bg); color: var(--status-ok); }
.is-inactive { background: var(--bg-hover); color: var(--text-secondary); }
.table-footer { justify-content: space-between; gap: 12px; padding-top: 16px; flex-wrap: wrap; }
.form-panel { max-width: 660px; margin-inline: auto; padding-bottom: 2px; }
.section-title { margin-bottom: 24px; }
.section-title > .el-button { padding-left: 0; margin-bottom: 12px; }
.section-title h3, .email-panel h3 { font-size: 23px; font-weight: 600; letter-spacing: -.025em; margin: 0 0 8px; }
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.form-actions { justify-content: flex-end; flex-wrap: wrap; gap: 10px; padding-top: 24px; margin-top: 12px; border-top: 1px solid var(--border); }
.spread { justify-content: space-between; }
.setting-row { justify-content: space-between; gap: 20px; padding: 18px 0 24px; }
.setting-row strong, .factor-label strong { font-size: 14px; font-weight: 500; }
.setting-row p, .factor-label p { margin-top: 5px; }
.policy-list, .factor-list { border: 1px solid var(--border); border-radius: var(--r-card); overflow: hidden; }
.policy-row { justify-content: space-between; flex-wrap: wrap; gap: 8px 16px; padding: 14px 16px; font-size: 13px; }
.policy-row + .policy-row, .factor-row + .factor-row { border-top: 1px solid var(--border); }
.factor-row { gap: 16px; padding: 22px; }
.factor-icon { font-size: 24px; color: var(--brand); flex-shrink: 0; }
.factor-label { flex: 1; min-width: 0; overflow-wrap: anywhere; }
.notification-form { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; padding: 18px; margin-bottom: 20px; background: var(--bg-hover); border-radius: var(--r-card); }
.notification-form .el-form-item { flex: 1; min-width: 210px; margin-bottom: 0; }
.notification-form .actions { padding-top: 25px; }
.email-panel { padding-top: 6px; }
.service-icon { font-size: 42px; color: var(--brand); margin-bottom: 18px; }
.email-panel > .secondary { margin-bottom: 28px; }
.field-hint { font-size: 12px; margin-top: 8px; }
.copy-field { display: flex; gap: 8px; width: 100%; }
.copy-field .el-input { min-width: 0; }
.credential-panel :deep(.el-input__inner) { font-family: var(--mono); }
.identity-panel-enter-active { transition: opacity 200ms ease, transform 260ms cubic-bezier(.2,.8,.2,1); }
.identity-panel-leave-active { transition: opacity 110ms ease, transform 110ms ease; }
.identity-panel-enter-from { opacity: 0; transform: translateY(7px); }
.identity-panel-leave-to { opacity: 0; transform: translateY(-3px); }
@media (max-width: 640px) {
  .toolbar { gap: 12px; }
  .toolbar > .secondary { width: 100%; }
  .form-grid { grid-template-columns: 1fr; gap: 0; }
  .factor-row { padding: 16px 12px; gap: 12px; }
  .factor-label p { font-size: 12px; }
  .form-actions.spread { flex-wrap: wrap; }
  .identity-tabs :deep(.el-tabs__item) { padding-inline: 16px; }
}
@media (prefers-reduced-motion: reduce) {
  .identity-panel-enter-active, .identity-panel-leave-active, .identity-content :deep(.el-button) { transition: none; }
  .identity-panel-enter-from, .identity-panel-leave-to, .identity-content :deep(.el-button:not(.is-disabled):active) { transform: none; }
}
</style>
