<script setup lang="ts">
import { hasTenantPermission, isManagedTenant, type TenantPermission } from '@/utils/tenantPermissions'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantGet, tenantPost } from '@/api/tenant'
import PagePagination from '@/components/PagePagination.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import '../tenants.scss'

type Row = Record<string, any>
type LoadKey = 'users' | 'groups' | 'notifications' | 'mfa' | 'policy'

const props = withDefaults(defineProps<{
  tenant: Row | null
  loadingTenant?: boolean
  tenantError?: string
}>(), {
  loadingTenant: false,
  tenantError: '',
})
const emit = defineEmits<{ changed: []; retryTenant: [] }>()

const { t, locale } = useI18n()
const compact = useCompactViewport()
const route = useRoute()

const tenantId = computed(() => String(props.tenant?.id ?? ''))
const managed = computed(() => isManagedTenant(props.tenant))
const allowed = (permission: TenantPermission) => hasTenantPermission(props.tenant, permission)
const canReadUsers = computed(() => !!props.tenant && allowed('USER_READ'))
const canManageSecurity = computed(() => !!props.tenant && allowed('DOMAIN_SECURITY_MANAGE'))
const canManageDomainUsers = computed(() => !!props.tenant && allowed('DOMAIN_USER_MANAGE'))
const tenantName = computed(() => props.tenant?.defName || props.tenant?.tenancyName || t('tenantIdentity.currentTenant'))

const tab = ref<'users' | 'notifications' | 'mfa'>('users')
const editor = ref('')
const keyword = ref('')
const userDrawerVisible = computed(() => canReadUsers.value && editor.value === 'user')
const policyDrawerVisible = computed(() => canReadUsers.value && editor.value === 'policy')
const busy = ref(false)
const hasStateAction = computed(() => users.value.some(canChangeUserState))
const actionsColumnStyle = computed(() => {
  const width = locale.value.startsWith('en')
    ? (hasStateAction.value ? '268px' : '196px')
    : (hasStateAction.value ? '230px' : '160px')
  return { minWidth: width, width }
})

const loading = reactive<Record<LoadKey, boolean>>({
  users: false,
  groups: false,
  notifications: false,
  mfa: false,
  policy: false,
})
const errors = reactive<Record<LoadKey, unknown>>({
  users: null,
  groups: null,
  notifications: null,
  mfa: null,
  policy: null,
})

const users = ref<Row[]>([])
const usersLoaded = ref(false)
const page = ref(1)
const pageSize = ref(10)

const filteredUsers = computed(() => {
  const q = keyword.value.trim().toLowerCase()
  if (!q) return users.value
  return users.value.filter(row =>
    [row.domain, row.username, displayUsername(row.username), row.email]
      .some(value => String(value || '').toLowerCase().includes(q)),
  )
})

const pageUsers = computed(() =>
  filteredUsers.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value),
)
const usersListId = computed(() => `identity-users-${tenantId.value}`)
const recipientsListId = computed(() => `identity-recipients-${tenantId.value}`)
const mobileUsers = computed(() =>
  typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith(`${usersListId.value}:`)
    ? filteredUsers.value
    : pageUsers.value,
)

const groups = ref<Row[]>([])
const groupsReady = ref(false)
const userForm = reactive({ username: '', email: '', groupId: '', useEmail: false })
const recipients = ref<string[]>([])
const recipientsLoaded = ref(false)
const notificationEmail = ref('')
const mfa = ref<Row | null>(null)
const policies = ref<Row[]>([])
const policyReady = ref(false)
const policyForm = reactive({ enablePasswordExpiry: false, expiryDays: 120 })
const credentials = ref<Row | null>(null)
const passwordResetNotice = ref('')

const mfaFactors = computed(() => [
  {
    key: 'emailEnabled',
    name: t('tenantIdentity.factors.email'),
    description: t('tenantIdentity.factors.emailDescription'),
    icon: 'i-mdi-email-outline',
  },
  {
    key: 'pushEnabled',
    name: t('tenantIdentity.factors.push'),
    description: t('tenantIdentity.factors.pushDescription'),
    icon: 'i-mdi-cellphone-check',
  },
  {
    key: 'totpEnabled',
    name: t('tenantIdentity.factors.totp'),
    description: t('tenantIdentity.factors.totpDescription'),
    icon: 'i-mdi-shield-key-outline',
  },
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
    if (current === generation && readVersions[key] === version && error?.code !== 'ERR_CANCELED') {
      errors[key] = error
    }
  } finally {
    if (current === generation && readVersions[key] === version) loading[key] = false
  }
}

async function confirm(message: string, heading: string) {
  if (confirming || busy.value) return false
  confirming = true
  try {
    await ElMessageBox.confirm(message, heading, {
      customClass: 'tenant-identity-confirm',
      confirmButtonText: t('tenantIdentity.actions.confirm'),
      cancelButtonText: t('tenantIdentity.actions.cancel'),
      type: 'warning',
      closeOnClickModal: false,
    })
    return true
  } catch {
    return false
  } finally {
    confirming = false
  }
}

async function mutate(
  request: () => Promise<any>,
  success: (data: any) => void | Promise<void>,
  messageKey = 'tenantIdentity.messages.saved',
) {
  if (busy.value) return
  const current = generation
  busy.value = true
  try {
    const result = await request()
    if (current !== generation) return
    if (messageKey) ElMessage.success(t(messageKey))
    emit('changed')
    await success(result)
  } catch (error) {
    if (current === generation) ElMessage.error(errorMessage(error))
  } finally {
    if (current === generation) busy.value = false
  }
}

function clampPage() {
  const totalPages = Math.max(1, Math.ceil(filteredUsers.value.length / pageSize.value))
  page.value = Math.max(1, Math.min(page.value, totalPages))
}

function loadUsers() {
  if (!canReadUsers.value || !tenantId.value) return
  return read(
    'users',
    signal => tenantGet<Row[]>('/tenants/oracle-users', { tenantId: tenantId.value }, { signal }),
    data => {
      users.value = Array.isArray(data) ? data : []
      usersLoaded.value = true
      clampPage()
    },
  )
}

function loadGroups() {
  if (managed.value || !allowed('USER_CREATE') || !tenantId.value) return
  groupsReady.value = false
  return read(
    'groups',
    signal => tenantPost<Row[]>('/tenants/groups', { tenantId: tenantId.value }, { signal }),
    data => {
      groups.value = Array.isArray(data) ? data : []
      groupsReady.value = true
    },
  )
}

function addUser() {
  if (!allowed('USER_CREATE')) return
  Object.assign(userForm, { username: '', email: '', groupId: '', useEmail: false })
  editor.value = 'user'
  if (!managed.value) void loadGroups()
}

async function createUser() {
  if (!allowed('USER_CREATE') || busy.value || (!managed.value && (!groupsReady.value || !groups.value.length))) return
  const email = userForm.email.trim()
  const username = userForm.useEmail ? email : userForm.username.trim()
  if (!username || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || (!managed.value && !userForm.groupId)) {
    ElMessage.warning(t('tenantIdentity.validation.user'))
    return
  }
  const groupName = groups.value.find(group => group.groupId === userForm.groupId)?.groupName || ''
  await mutate(
    () => tenantPost('/tenants/oracle-users', {
      tenantId: tenantId.value,
      username,
      email,
      ...(managed.value ? {} : { groupId: userForm.groupId }),
    }),
    async result => {
      editor.value = ''
      if (!managed.value) {
        credentials.value = {
          username: result.username,
          email: result.email,
          group: groupName,
          password: result.password,
        }
      }
      page.value = 1
      await loadUsers()
    },
    'tenantIdentity.messages.userCreated',
  )
}

async function resetPassword(user: Row) {
  if (!canResetUserPassword(user)) return
  const key = managed.value ? 'tenantIdentity.confirmations.resetPasswordManaged' : 'tenantIdentity.confirmations.resetPassword'
  if (!await confirm(t(key, { username: displayUsername(user.username) }), t('tenantIdentity.actions.resetPassword'))) return
  passwordResetNotice.value = ''
  await mutate(
    () => tenantPost('/tenants/oracle-users/resetPassword', {
      tenantId: tenantId.value,
      userId: user.id,
      userName: user.username,
    }, { timeout: 30000 }),
    result => {
      const data = result.data || {}
      if (data.success === false) throw new Error(data.message || t('tenantIdentity.messages.error'))
      if (typeof data.temporaryPassword === 'string' && data.temporaryPassword) {
        credentials.value = {
          username: data.loginUser || displayUsername(user.username),
          password: data.temporaryPassword,
          resetTime: data.resetTime,
        }
        ElMessage.success(t('tenantIdentity.messages.passwordReset'))
      } else {
        credentials.value = null
        passwordResetNotice.value = data.message
          || t(data.emailSent === true ? 'tenantIdentity.messages.passwordResetEmail' : 'tenantIdentity.messages.passwordResetAccepted')
        ElMessage.success(passwordResetNotice.value)
      }
    },
    '',
  )
}

async function deleteUser(user: Row) {
  if (!canDeleteUser(user)) return
  if (!await confirm(t('tenantIdentity.confirmations.deleteUser', { username: displayUsername(user.username) }), t('tenantIdentity.actions.deleteUser'))) return
  await mutate(
    () => tenantPost('/tenants/oracle-users/deleteUser', { tenantId: tenantId.value, userId: user.id }),
    loadUsers,
    'tenantIdentity.messages.userDeleted',
  )
}

function canResetUserPassword(user: Row) {
  return managed.value ? user.canResetPassword === true : allowed('USER_PASSWORD_RESET')
}

function canDeleteUser(user: Row) {
  return managed.value ? user.canDelete === true : allowed('USER_DELETE')
}

function canChangeUserState(user: Row) {
  return typeof user.active === 'boolean' && user.canManage === true && (!managed.value || canManageDomainUsers.value)
}

async function changeUserState(user: Row) {
  if (!canChangeUserState(user)) return
  const active = !user.active
  const confirmKey = active ? 'tenantIdentity.confirmations.enableUser' : 'tenantIdentity.confirmations.disableUser'
  const titleKey = active ? 'tenantIdentity.actions.enableUser' : 'tenantIdentity.actions.disableUser'
  if (!await confirm(t(confirmKey, { username: displayUsername(user.username) }), t(titleKey))) return
  await mutate(
    () => tenantPost('/tenants/oracle-users/state', { tenantId: tenantId.value, userId: user.id, active }),
    loadUsers,
    active ? 'tenantIdentity.messages.userEnabled' : 'tenantIdentity.messages.userDisabled',
  )
}

function isUserActive(user: Row) {
  return user.active === true || (user.active == null && user.lifecycleState === 'Active')
}

function userStatusLabel(user: Row) {
  if (typeof user.active === 'boolean') return t(user.active ? 'tenantIdentity.status.enabled' : 'tenantIdentity.status.disabled')
  return userStatus(user.lifecycleState)
}

function displayUsername(value = '') {
  return value.split('/').pop() || '—'
}

function userStatus(value?: string) {
  const key = String(value || '').toLowerCase()
  return ['active', 'inactive', 'creating', 'updating', 'deleting', 'deleted', 'failed', 'locked'].includes(key)
    ? t(`tenantIdentity.status.${key}`)
    : value || t('tenantIdentity.status.unknown')
}

function closeEditor() {
  editor.value = ''
  notificationEmail.value = ''
}

function guardDrawerClose(done: () => void) {
  if (!busy.value) done()
}

function handleDrawerClose(type: 'user' | 'policy') {
  if (!busy.value && editor.value === type) closeEditor()
}

function loadPolicy() {
  if (!canManageSecurity.value || !tenantId.value) return
  policyReady.value = false
  return read(
    'policy',
    signal => tenantPost('/tenants/oracle-users/getPasspolicy', { tenantId: tenantId.value }, { signal }),
    result => {
      policies.value = Array.isArray(result.data) ? result.data : []
      policyForm.enablePasswordExpiry = policies.value.some(policy => policy.enablePasswordExpiry)
      const days = policies.value.filter(policy => policy.expiryDays != null).map(policy => Number(policy.expiryDays))
      policyForm.expiryDays = days.length ? Math.min(...days) : 120
      policyReady.value = true
    },
  )
}

function openPolicy() {
  if (!canManageSecurity.value) return
  editor.value = 'policy'
  void loadPolicy()
}

async function savePolicy() {
  if (!canManageSecurity.value || busy.value || !policyReady.value) return
  const days = Number(policyForm.expiryDays)
  if (policyForm.enablePasswordExpiry && (!Number.isInteger(days) || days < 0 || days > 365)) {
    ElMessage.warning(t('tenantIdentity.validation.expiryDays'))
    return
  }
  await mutate(
    () => tenantPost('/tenants/oracle-users/password-policy', {
      tenantId: tenantId.value,
      enablePasswordExpiry: policyForm.enablePasswordExpiry,
      expiryDays: policyForm.enablePasswordExpiry ? days : null,
    }),
    () => { editor.value = '' },
    'tenantIdentity.messages.policySaved',
  )
}

function loadRecipients() {
  if (!canManageSecurity.value || !tenantId.value) return
  return read(
    'notifications',
    signal => tenantPost('/tenants/notification/recipients', { tenantId: tenantId.value }, { signal }),
    result => {
      recipients.value = result.recipients || []
      recipientsLoaded.value = true
    },
  )
}

async function updateRecipient(removeEmail?: string) {
  if (!canManageSecurity.value) return
  const email = notificationEmail.value.trim().toLowerCase()
  if (!removeEmail && !/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(email)) {
    ElMessage.warning(t('tenantIdentity.validation.email'))
    return
  }
  if (removeEmail && !await confirm(t('tenantIdentity.confirmations.removeRecipient', { email: removeEmail }), t('tenantIdentity.actions.removeRecipient'))) return
  await mutate(
    async () => {
      const latest = await tenantPost('/tenants/notification/recipients', { tenantId: tenantId.value })
      const current: string[] = latest.recipients || []
      if (!removeEmail && current.some(item => item.toLowerCase() === email)) {
        throw new Error(t('tenantIdentity.validation.duplicateRecipient'))
      }
      const emails = removeEmail ? current.filter(item => item !== removeEmail) : [...current, email]
      if (!emails.length) throw new Error(t('tenantIdentity.validation.lastRecipient'))
      return tenantPost('/tenants/notification/update', { tenantId: tenantId.value, emails })
    },
    async () => {
      notificationEmail.value = ''
      editor.value = ''
      await loadRecipients()
    },
    removeEmail ? 'tenantIdentity.messages.recipientRemoved' : 'tenantIdentity.messages.recipientAdded',
  )
}

function loadMfa() {
  if (!canManageSecurity.value || !tenantId.value) return
  return read(
    'mfa',
    signal => tenantGet('/tenants/mfa/status', { tenantId: tenantId.value }, { signal }),
    result => { mfa.value = result.data || {} },
  )
}

async function updateEmailMfa(enableEmail: boolean) {
  if (!canManageSecurity.value) return
  const action = enableEmail ? 'enableEmailMfa' : 'disableEmailMfa'
  if (!await confirm(t(`tenantIdentity.confirmations.${action}`), t(`tenantIdentity.actions.${action}`))) return
  await mutate(
    () => tenantPost('/tenants/mfa/email', { tenantId: tenantId.value, enableEmail }),
    loadMfa,
    'tenantIdentity.messages.emailMfaSaved',
  )
}

async function resetMfa() {
  if (!canManageSecurity.value) return
  if (!await confirm(t('tenantIdentity.confirmations.resetMfa'), t('tenantIdentity.actions.resetMfa'))) return
  await mutate(
    () => tenantPost(
      '/tenants/resetAccountFactor',
      new URLSearchParams({ tenantId: tenantId.value }),
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
    ),
    loadMfa,
    'tenantIdentity.messages.mfaReset',
  )
}

async function copy(value: string) {
  try {
    await navigator.clipboard.writeText(value)
    ElMessage.success(t('tenantIdentity.messages.copied'))
  } catch {
    ElMessage.warning(t('tenantIdentity.messages.copyFailed'))
  }
}

function copyCredentials() {
  const data = credentials.value
  if (!data) return
  const line = (label: string, value: string) => t('tenantIdentity.credentialLine', { label: t(`tenantIdentity.labels.${label}`), value })
  void copy([
    line('username', data.username),
    data.email && line('email', data.email),
    data.group && line('userGroup', data.group),
    line('temporaryPassword', data.password),
  ].filter(Boolean).join('\n'))
}

function refreshCurrentTab() {
  if (tab.value === 'users') void loadUsers()
  else if (tab.value === 'notifications') void loadRecipients()
  else void loadMfa()
}

function handlePageSizeChange(nextSize: number) {
  pageSize.value = nextSize
  page.value = 1
}

watch(keyword, () => {
  page.value = 1
})

watch(() => tenantId.value, () => {
  generation += 1
  readController.abort()
  readController = new AbortController()
  Object.keys(loading).forEach(key => {
    loading[key as LoadKey] = false
    errors[key as LoadKey] = null
  })
  busy.value = false
  editor.value = ''
  tab.value = 'users'
  keyword.value = ''
  page.value = 1
  users.value = []
  usersLoaded.value = false
  groups.value = []
  groupsReady.value = false
  policies.value = []
  policyReady.value = false
  recipients.value = []
  recipientsLoaded.value = false
  mfa.value = null
  credentials.value = null
  passwordResetNotice.value = ''
  notificationEmail.value = ''
  if (canReadUsers.value) void loadUsers()
}, { immediate: true })

watch(tab, value => {
  editor.value = ''
  if (!canReadUsers.value) return
  if (value === 'notifications') void loadRecipients()
  if (value === 'mfa') void loadMfa()
})

watch(() => [route.query.mobileRecord, tenantId.value], () => {
  if (!compact.value || !canReadUsers.value || busy.value) return
  const selectedRecord = route.query.mobileRecord
  if (typeof selectedRecord !== 'string') return
  if (canManageSecurity.value && selectedRecord.startsWith(`${recipientsListId.value}:`)) tab.value = 'notifications'
  else if (selectedRecord.startsWith(`${usersListId.value}:`)) tab.value = 'users'
}, { immediate: true })

onBeforeUnmount(() => {
  generation += 1
  readController.abort()
})

defineExpose({
  addUser,
  openPolicy,
  createUser,
  savePolicy,
  handleDrawerClose,
  userForm,
  policyForm,
})
</script>

<template>
  <div class="identity-workspace" :aria-busy="loadingTenant || busy || loading.users || loading.notifications || loading.mfa">
    <section class="tenant-card identity-card" data-motion-enter :aria-label="t('tenantIdentity.titles.users')">
      <div class="list-toolbar identity-toolbar">
        <div class="identity-toolbar-lead">
          <span class="tenant-context" :title="tenantName">
            <span class="context-dot" />
            <span class="context-name">{{ tenantName }}</span>
          </span>
          <div class="identity-tab-bar" role="tablist" :aria-label="t('tenantIdentity.titles.users')">
            <button
              type="button"
              role="tab"
              class="identity-tab-btn"
              :class="{ 'is-active': tab === 'users' }"
              :aria-selected="tab === 'users'"
              :disabled="busy"
              @click="tab = 'users'"
            >
              <i class="i-mdi-account-group-outline" aria-hidden="true" />
              <span>{{ t('tenantIdentity.tabs.users') }}</span>
            </button>
            <button
              v-if="canManageSecurity"
              type="button"
              role="tab"
              class="identity-tab-btn"
              :class="{ 'is-active': tab === 'notifications' }"
              :aria-selected="tab === 'notifications'"
              :disabled="busy"
              @click="tab = 'notifications'"
            >
              <i class="i-mdi-email-check-outline" aria-hidden="true" />
              <span>{{ t('tenantIdentity.tabs.notifications') }}</span>
            </button>
            <button
              v-if="canManageSecurity"
              type="button"
              role="tab"
              class="identity-tab-btn"
              :class="{ 'is-active': tab === 'mfa' }"
              :aria-selected="tab === 'mfa'"
              :disabled="busy"
              @click="tab = 'mfa'"
            >
              <i class="i-mdi-shield-key-outline" aria-hidden="true" />
              <span>{{ t('tenantIdentity.tabs.mfa') }}</span>
            </button>
          </div>
          <form v-if="tab === 'users'" class="tenant-search identity-search" role="search" @submit.prevent>
            <i class="i-mdi-magnify" aria-hidden="true" />
            <input
              v-model="keyword"
              :placeholder="`${t('tenantIdentity.labels.username')} / ${t('tenantIdentity.labels.email')}`"
              :aria-label="t('tenantIdentity.labels.username')"
              autocomplete="off"
              @keydown.esc.prevent="keyword = ''"
            />
            <button v-if="keyword" type="button" :aria-label="t('tenant.list.clearSearch')" @click="keyword = ''">
              <i class="i-mdi-close-circle" />
            </button>
          </form>
        </div>

        <div class="toolbar-actions" data-page-error-anchor>
          <button
            type="button"
            class="toolbar-button"
            :aria-label="tab === 'mfa' ? t('tenantIdentity.actions.refreshStatus') : t('tenantIdentity.actions.refresh')"
            :title="tab === 'mfa' ? t('tenantIdentity.actions.refreshStatus') : t('tenantIdentity.actions.refresh')"
            :disabled="loadingTenant || busy || loading.users || loading.notifications || loading.mfa"
            @click="refreshCurrentTab"
          >
            <i
              class="i-mdi-refresh"
              :class="{ 'is-spinning': loadingTenant || loading.users || loading.notifications || loading.mfa }"
              aria-hidden="true"
            />
          </button>
          <template v-if="tab === 'users'">
            <GhostBtn v-if="canManageSecurity" :disabled="!tenant || busy" @click="openPolicy">
              <i class="i-mdi-shield-lock-outline" aria-hidden="true" />
              {{ t('tenantIdentity.actions.passwordPolicy') }}
            </GhostBtn>
            <PrimaryBtn v-if="allowed('USER_CREATE')" :disabled="!tenant || busy" @click="addUser">
              <i class="i-mdi-account-plus-outline" aria-hidden="true" />
              {{ t('tenantIdentity.actions.addUser') }}
            </PrimaryBtn>
          </template>
          <template v-else-if="tab === 'notifications' && canManageSecurity">
            <PrimaryBtn v-if="editor !== 'notification'" :disabled="!tenant || busy" @click="editor = 'notification'">
              <i class="i-mdi-email-plus-outline" aria-hidden="true" />
              {{ t('tenantIdentity.actions.addRecipient') }}
            </PrimaryBtn>
          </template>
        </div>
      </div>

      <div v-if="tenantError" class="identity-notice-wrap">
        <PageErrorNotice>
          <div>
            <strong>{{ t('tenant.list.refreshFailed') }}</strong>
            <p>{{ tenantError }}</p>
          </div>
          <GhostBtn @click="emit('retryTenant')">{{ t('tenant.common.retry') }}</GhostBtn>
        </PageErrorNotice>
      </div>

      <template v-else-if="loadingTenant && !tenant">
        <div
          v-loading="true"
          class="identity-loading-state"
          role="status"
          :aria-label="t('tenantIdentity.loading.users')"
          :element-loading-text="t('tenantIdentity.loading.users')"
        />
      </template>

      <template v-else-if="canReadUsers">
        <div v-if="passwordResetNotice && tab === 'users'" class="identity-notice-wrap">
          <el-alert :title="passwordResetNotice" type="success" :closable="true" show-icon @close="passwordResetNotice = ''" />
        </div>

        <Transition name="identity-panel" mode="out-in">
          <div v-if="tab === 'users'" key="users" class="identity-tab-pane">
            <div v-if="errors.users" class="identity-notice-wrap">
              <PageErrorNotice>
                <p>{{ errorMessage(errors.users) }}</p>
                <GhostBtn @click="loadUsers">{{ t('tenant.common.retry') }}</GhostBtn>
              </PageErrorNotice>
            </div>

            <div
              v-loading="loading.users"
              class="table-stage identity-table-stage"
              :class="{ 'is-refreshing': loading.users && usersLoaded }"
              :element-loading-text="t('tenantIdentity.loading.users')"
            >
              <div v-if="loading.users && usersLoaded" class="refresh-track" aria-hidden="true"><span /></div>
              <div class="table-scroll" tabindex="0" :aria-label="t('tenantIdentity.tabs.users')">
                <template v-if="compact">
                  <MobileRecordList
                    drilldown
                    :list-id="usersListId"
                    :record-keys="filteredUsers.map(row => String(row.id))"
                    :loading="loading.users"
                    class="identity-mobile-list"
                  >
                    <MobileRecordCard
                      v-for="row in mobileUsers"
                      :key="row.id"
                      :record-key="String(row.id)"
                      :summary-title="displayUsername(row.username)"
                      :summary-meta="row.email || row.domain || '—'"
                      :summary-status="userStatusLabel(row)"
                      :summary-tone="isUserActive(row) ? 'success' : 'neutral'"
                    >
                      <template #identity><h3 class="mobile-record-title">{{ displayUsername(row.username) }}</h3></template>
                      <dl class="mobile-record-fields">
                        <div class="mobile-record-wide"><dt>{{ t('tenantIdentity.labels.domain') }}</dt><dd>{{ row.domain || '—' }}</dd></div>
                        <div class="mobile-record-wide"><dt>{{ t('tenantIdentity.labels.email') }}</dt><dd>{{ row.email || '—' }}</dd></div>
                        <div>
                          <dt>{{ t('tenantIdentity.labels.status') }}</dt>
                          <dd>
                            <span class="tenant-status" :class="isUserActive(row) ? 'status-active' : 'status-inactive'">
                              <span />{{ userStatusLabel(row) }}
                            </span>
                          </dd>
                        </div>
                        <div class="mobile-record-wide"><dt>{{ t('tenantIdentity.labels.createdAt') }}</dt><dd>{{ row.timeCreated || '—' }}</dd></div>
                        <div class="mobile-record-wide"><dt>{{ t('tenantIdentity.labels.lastLogin') }}</dt><dd>{{ row.lastSuccessfulLoginTime || '—' }}</dd></div>
                      </dl>
                      <template #footer>
                        <el-button
                          v-if="canChangeUserState(row)"
                          :type="row.active ? 'warning' : 'primary'"
                          plain
                          :disabled="busy || loading.users"
                          @click="changeUserState(row)"
                        >
                          {{ t(row.active ? 'tenantIdentity.actions.disableUser' : 'tenantIdentity.actions.enableUser') }}
                        </el-button>
                        <el-button v-if="canResetUserPassword(row)" :disabled="busy || loading.users" @click="resetPassword(row)">
                          {{ t('tenantIdentity.actions.resetPassword') }}
                        </el-button>
                        <el-button v-if="canDeleteUser(row)" type="danger" plain :disabled="busy || loading.users" @click="deleteUser(row)">
                          {{ t('tenantIdentity.actions.delete') }}
                        </el-button>
                      </template>
                    </MobileRecordCard>
                  </MobileRecordList>
                </template>

                <table v-else class="tenant-table identity-table">
                  <thead>
                    <tr>
                      <th scope="col">{{ t('tenantIdentity.labels.domain') }}</th>
                      <th scope="col">{{ t('tenantIdentity.labels.username') }}</th>
                      <th scope="col">{{ t('tenantIdentity.labels.email') }}</th>
                      <th scope="col">{{ t('tenantIdentity.labels.status') }}</th>
                      <th scope="col">{{ t('tenantIdentity.labels.createdAt') }}</th>
                      <th scope="col">{{ t('tenantIdentity.labels.lastLogin') }}</th>
                      <th scope="col" class="row-actions-column identity-actions-col" :style="actionsColumnStyle">{{ t('tenantIdentity.labels.actions') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <template v-if="loading.users && !usersLoaded">
                      <tr v-for="n in 4" :key="`skeleton-${n}`" class="skeleton-row">
                        <td><span class="skeleton" /></td>
                        <td><span class="skeleton skeleton-name" /></td>
                        <td><span class="skeleton" /></td>
                        <td><span class="skeleton" /></td>
                        <td><span class="skeleton" /></td>
                        <td><span class="skeleton" /></td>
                        <td class="row-actions-column identity-actions-col" :style="actionsColumnStyle"><span class="skeleton" /></td>
                      </tr>
                    </template>
                    <tr v-for="row in pageUsers" v-else :key="row.id">
                      <td><span class="identity-cell-text">{{ row.domain || '—' }}</span></td>
                      <td><span class="user-name" :title="displayUsername(row.username)">{{ displayUsername(row.username) }}</span></td>
                      <td><span class="identity-email-text" :title="row.email || ''">{{ row.email || '—' }}</span></td>
                      <td>
                        <span class="tenant-status" :class="isUserActive(row) ? 'status-active' : 'status-inactive'">
                          <span />{{ userStatusLabel(row) }}
                        </span>
                      </td>
                      <td><span class="created-at">{{ row.timeCreated || '—' }}</span></td>
                      <td><span class="created-at">{{ row.lastSuccessfulLoginTime || '—' }}</span></td>
                      <td class="row-actions-column identity-actions-col" :style="actionsColumnStyle">
                        <div class="table-actions">
                          <el-button
                            v-if="canChangeUserState(row)"
                            link
                            :type="row.active ? 'warning' : 'primary'"
                            :disabled="busy"
                            @click="changeUserState(row)"
                          >
                            {{ t(row.active ? 'tenantIdentity.actions.disableUser' : 'tenantIdentity.actions.enableUser') }}
                          </el-button>
                          <el-button v-if="canResetUserPassword(row)" link :disabled="busy" @click="resetPassword(row)">
                            {{ t('tenantIdentity.actions.resetPassword') }}
                          </el-button>
                          <el-button v-if="canDeleteUser(row)" link type="danger" :disabled="busy" @click="deleteUser(row)">
                            {{ t('tenantIdentity.actions.delete') }}
                          </el-button>
                          <span v-if="!canChangeUserState(row) && !canResetUserPassword(row) && !canDeleteUser(row)" class="secondary">—</span>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>

                <div v-if="!loading.users && !filteredUsers.length" class="tenant-empty" role="status">
                  <div class="empty-icon"><i class="i-mdi-account-search-outline" aria-hidden="true" /></div>
                  <h3>{{ t('tenantIdentity.empty.users') }}</h3>
                  <p>{{ t('tenantIdentity.descriptions.users') }}</p>
                </div>
              </div>
            </div>

            <PagePagination
              v-model:current-page="page"
              :page-size="pageSize"
              :page-sizes="[5, 10, 20, 50]"
              :total="filteredUsers.length"
              :disabled="busy"
              @size-change="handlePageSizeChange"
            >
              <p aria-live="polite">{{ t('tenantIdentity.counts.users', { count: filteredUsers.length }) }}</p>
            </PagePagination>
          </div>

          <div v-else-if="tab === 'notifications' && canManageSecurity" key="notifications" class="identity-tab-pane">
            <div v-if="errors.notifications" class="identity-notice-wrap">
              <PageErrorNotice>
                <p>{{ errorMessage(errors.notifications) }}</p>
                <GhostBtn @click="loadRecipients">{{ t('tenant.common.retry') }}</GhostBtn>
              </PageErrorNotice>
            </div>

            <div class="identity-subpanel">
              <el-form v-if="editor === 'notification'" class="notification-form" label-position="top" @submit.prevent="updateRecipient()">
                <el-form-item :label="t('tenantIdentity.labels.notificationEmail')" required>
                  <el-input v-model="notificationEmail" type="email" :placeholder="t('tenantIdentity.placeholders.email')" :disabled="busy" />
                </el-form-item>
                <div class="actions">
                  <el-button :disabled="busy" @click="closeEditor">{{ t('tenantIdentity.actions.cancel') }}</el-button>
                  <el-button type="primary" native-type="submit" :loading="busy">{{ t('tenantIdentity.actions.add') }}</el-button>
                </div>
              </el-form>
            </div>

            <div
              v-loading="loading.notifications"
              class="table-stage identity-table-stage"
              :class="{ 'is-refreshing': loading.notifications && recipientsLoaded }"
              :element-loading-text="t('tenantIdentity.loading.notifications')"
            >
              <div v-if="loading.notifications && recipientsLoaded" class="refresh-track" aria-hidden="true"><span /></div>
              <div class="table-scroll" tabindex="0" :aria-label="t('tenantIdentity.tabs.notifications')">
                <template v-if="compact">
                  <MobileRecordList
                    drilldown
                    :list-id="recipientsListId"
                    :record-keys="recipients"
                    :loading="loading.notifications"
                    class="identity-mobile-list"
                  >
                    <MobileRecordCard
                      v-for="(email, index) in recipients"
                      :key="email"
                      :record-key="email"
                      :summary-title="email"
                      :summary-status="t('tenantIdentity.status.normal')"
                      summary-tone="success"
                    >
                      <template #identity><h3 class="mobile-record-title">{{ email }}</h3></template>
                      <dl class="mobile-record-fields">
                        <div><dt>{{ t('tenantIdentity.labels.index') }}</dt><dd>{{ index + 1 }}</dd></div>
                        <div>
                          <dt>{{ t('tenantIdentity.labels.status') }}</dt>
                          <dd><span class="tenant-status status-active"><span />{{ t('tenantIdentity.status.normal') }}</span></dd>
                        </div>
                        <div class="mobile-record-wide"><dt>{{ t('tenantIdentity.labels.notificationEmail') }}</dt><dd>{{ email }}</dd></div>
                      </dl>
                      <template #footer>
                        <el-button type="danger" plain :disabled="busy || loading.notifications" @click="updateRecipient(email)">
                          {{ t('tenantIdentity.actions.remove') }}
                        </el-button>
                      </template>
                    </MobileRecordCard>
                  </MobileRecordList>
                </template>

                <table v-else class="tenant-table identity-table">
                  <thead>
                    <tr>
                      <th scope="col" style="width: 84px">{{ t('tenantIdentity.labels.index') }}</th>
                      <th scope="col">{{ t('tenantIdentity.labels.notificationEmail') }}</th>
                      <th scope="col" style="width: 120px">{{ t('tenantIdentity.labels.status') }}</th>
                      <th scope="col" class="row-actions-column" style="width: 120px; min-width: 120px">{{ t('tenantIdentity.labels.actions') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="(email, index) in recipients" :key="email">
                      <td>{{ index + 1 }}</td>
                      <td><span class="user-name">{{ email }}</span></td>
                      <td><span class="tenant-status status-active"><span />{{ t('tenantIdentity.status.normal') }}</span></td>
                      <td class="row-actions-column" style="width: 120px; min-width: 120px">
                        <div class="table-actions">
                          <el-button link type="danger" :disabled="busy" @click="updateRecipient(email)">
                            {{ t('tenantIdentity.actions.remove') }}
                          </el-button>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>

                <div v-if="!loading.notifications && !recipients.length" class="tenant-empty" role="status">
                  <div class="empty-icon"><i class="i-mdi-email-outline" aria-hidden="true" /></div>
                  <h3>{{ t('tenantIdentity.empty.recipients') }}</h3>
                  <p>{{ t('tenantIdentity.descriptions.notifications') }}</p>
                </div>
              </div>
            </div>

            <div class="identity-card-footer">
              <p class="secondary">{{ t('tenantIdentity.counts.recipients', { count: recipients.length }) }}</p>
            </div>
          </div>

          <div v-else-if="canManageSecurity" key="mfa" class="identity-tab-pane">
            <div
              class="identity-mfa-stage"
              v-loading="loading.mfa"
              :element-loading-text="t('tenantIdentity.loading.mfa')"
            >
              <div v-if="errors.mfa" class="identity-notice-wrap-inline">
                <PageErrorNotice>
                  <p>{{ errorMessage(errors.mfa) }}</p>
                  <GhostBtn @click="loadMfa">{{ t('tenant.common.retry') }}</GhostBtn>
                </PageErrorNotice>
              </div>
              <p class="identity-stage-desc">{{ t('tenantIdentity.descriptions.mfa') }}</p>
              <div class="factor-list">
                <div v-for="factor in mfaFactors" :key="factor.key" class="factor-row">
                  <div class="factor-icon"><i :class="factor.icon" aria-hidden="true" /></div>
                  <div class="factor-label">
                    <strong>{{ factor.name }}</strong>
                    <p class="secondary">{{ factor.description }}</p>
                  </div>
                  <span class="tenant-status" :class="mfa?.[factor.key] ? 'status-active' : 'status-inactive'">
                    <span />{{ t(mfa ? (mfa[factor.key] ? 'tenantIdentity.status.enabled' : 'tenantIdentity.status.notEnabled') : 'tenantIdentity.status.pending') }}
                  </span>
                </div>
              </div>
              <div class="form-actions spread">
                <el-button :disabled="busy" @click="resetMfa">{{ t('tenantIdentity.actions.resetMfa') }}</el-button>
                <div class="actions">
                  <el-button :disabled="busy || !mfa" @click="updateEmailMfa(false)">{{ t('tenantIdentity.actions.disableEmailMfa') }}</el-button>
                  <el-button type="primary" :disabled="busy || !mfa" :loading="busy" @click="updateEmailMfa(true)">{{ t('tenantIdentity.actions.enableEmailMfa') }}</el-button>
                </div>
              </div>
            </div>
          </div>
        </Transition>
      </template>
    </section>

    <el-drawer
      :model-value="userDrawerVisible"
      :title="t('tenantIdentity.actions.addUser')"
      class="identity-drawer identity-user-drawer"
      direction="rtl"
      :size="compact ? 'min(94vw, 460px)' : '500px'"
      append-to-body
      destroy-on-close
      :close-on-click-modal="false"
      :close-on-press-escape="!busy"
      :show-close="!busy"
      :before-close="guardDrawerClose"
      @close="handleDrawerClose('user')"
    >
      <template #header>
        <div class="identity-drawer-header">
          <div class="identity-drawer-icon"><i class="i-mdi-account-plus-outline" aria-hidden="true" /></div>
          <div class="identity-drawer-heading">
            <h3 class="identity-drawer-title">{{ t('tenantIdentity.actions.addUser') }}</h3>
            <p class="identity-drawer-subtitle">{{ tenantName }}</p>
          </div>
        </div>
      </template>
      <div class="identity-drawer-body" v-loading="loading.groups">
        <div class="drawer-intro-banner">
          <i class="i-mdi-information-outline" aria-hidden="true" />
          <p>{{ managed ? t('tenantIdentity.descriptions.restrictedNewUser') : t('tenantIdentity.descriptions.newUser') }}</p>
        </div>
        <PageErrorNotice v-if="errors.groups">
          <p>{{ errorMessage(errors.groups) }}</p>
          <el-button text @click="loadGroups">{{ t('tenantIdentity.actions.reloadGroups') }}</el-button>
        </PageErrorNotice>
        <div class="drawer-section-card">
          <div class="drawer-section-label">{{ t('tenantIdentity.labels.accountInfo') }}</div>
          <el-form class="drawer-form" label-position="top" :disabled="busy" @submit.prevent="createUser">
            <button type="submit" class="drawer-hidden-submit" tabindex="-1" aria-hidden="true" />
            <el-form-item :label="t('tenantIdentity.labels.username')" required>
              <el-input
                :model-value="userForm.useEmail ? userForm.email : userForm.username"
                :disabled="userForm.useEmail"
                :placeholder="t('tenantIdentity.placeholders.username')"
                autocomplete="off"
                @update:model-value="userForm.username = $event"
              />
            </el-form-item>
            <div class="drawer-toggle-strip">
              <el-checkbox v-model="userForm.useEmail">{{ t('tenantIdentity.labels.useEmail') }}</el-checkbox>
            </div>
            <el-form-item :label="t('tenantIdentity.labels.email')" required :class="{ 'drawer-last-item': managed }">
              <el-input v-model="userForm.email" type="email" :placeholder="t('tenantIdentity.placeholders.email')" />
            </el-form-item>
            <el-form-item v-if="!managed" :label="t('tenantIdentity.labels.userGroup')" required class="drawer-last-item">
              <el-select v-model="userForm.groupId" popper-class="tenant-identity-select" :placeholder="t('tenantIdentity.placeholders.group')" :disabled="!groupsReady">
                <el-option v-for="group in groups" :key="group.groupId" :label="group.groupName" :value="group.groupId" />
              </el-select>
            </el-form-item>
          </el-form>
        </div>
      </div>
      <template #footer>
        <div class="identity-drawer-footer">
          <el-button :disabled="busy" @click="handleDrawerClose('user')">{{ t('tenantIdentity.actions.cancel') }}</el-button>
          <el-button type="primary" :loading="busy" :disabled="!managed && (!groupsReady || !groups.length)" @click="createUser">
            {{ t('tenantIdentity.actions.createUser') }}
          </el-button>
        </div>
      </template>
    </el-drawer>

    <el-drawer
      :model-value="policyDrawerVisible"
      :title="t('tenantIdentity.actions.passwordPolicy')"
      class="identity-drawer identity-policy-drawer"
      direction="rtl"
      :size="compact ? 'min(94vw, 460px)' : '500px'"
      append-to-body
      destroy-on-close
      :close-on-click-modal="false"
      :close-on-press-escape="!busy"
      :show-close="!busy"
      :before-close="guardDrawerClose"
      @close="handleDrawerClose('policy')"
    >
      <template #header>
        <div class="identity-drawer-header">
          <div class="identity-drawer-icon"><i class="i-mdi-shield-lock-outline" aria-hidden="true" /></div>
          <div class="identity-drawer-heading">
            <h3 class="identity-drawer-title">{{ t('tenantIdentity.actions.passwordPolicy') }}</h3>
            <p class="identity-drawer-subtitle">{{ tenantName }}</p>
          </div>
        </div>
      </template>
      <div class="identity-drawer-body" v-loading="loading.policy">
        <div class="drawer-intro-banner">
          <i class="i-mdi-information-outline" aria-hidden="true" />
          <p>{{ t('tenantIdentity.descriptions.policy') }}</p>
        </div>
        <PageErrorNotice v-if="errors.policy">
          <p>{{ errorMessage(errors.policy) }}</p>
          <el-button text @click="loadPolicy">{{ t('tenantIdentity.actions.reload') }}</el-button>
        </PageErrorNotice>
        <div v-if="policies.length" class="drawer-section-card">
          <div class="drawer-section-label">{{ t('tenantIdentity.labels.currentPolicies') }}</div>
          <div class="policy-list">
            <div v-for="(policy, index) in policies" :key="index" class="policy-row">
              <span class="policy-name">{{ policy.name || t('tenantIdentity.labels.policy', { index: index + 1 }) }}</span>
              <span class="policy-badge" :class="policy.enablePasswordExpiry ? 'is-expiring' : 'is-permanent'">
                {{ policy.enablePasswordExpiry ? t('tenantIdentity.status.expiresIn', { days: policy.expiryDays ?? 0 }) : t('tenantIdentity.status.neverExpires') }}
              </span>
            </div>
          </div>
        </div>
        <div class="drawer-section-card">
          <div class="drawer-section-label">{{ t('tenantIdentity.labels.policySettings') }}</div>
          <el-form class="drawer-form" label-position="top" :disabled="busy || !policyReady" @submit.prevent="savePolicy">
            <button type="submit" class="drawer-hidden-submit" tabindex="-1" aria-hidden="true" />
            <div class="setting-row">
              <div class="setting-copy">
                <strong>{{ t('tenantIdentity.labels.enablePasswordExpiry') }}</strong>
                <p class="secondary">{{ t('tenantIdentity.descriptions.passwordExpiry') }}</p>
              </div>
              <el-switch v-model="policyForm.enablePasswordExpiry" :aria-label="t('tenantIdentity.labels.enablePasswordExpiry')" />
            </div>
            <div v-if="policyForm.enablePasswordExpiry" class="policy-expiry-field">
              <el-form-item :label="t('tenantIdentity.labels.expiryDays')" class="drawer-last-item">
                <el-input-number v-model="policyForm.expiryDays" class="policy-days-input" :min="0" :max="365" :precision="0" />
                <p class="field-hint">{{ t('tenantIdentity.validation.expiryDays') }}</p>
              </el-form-item>
            </div>
          </el-form>
        </div>
      </div>
      <template #footer>
        <div class="identity-drawer-footer">
          <el-button :disabled="busy" @click="handleDrawerClose('policy')">{{ t('tenantIdentity.actions.cancel') }}</el-button>
          <el-button type="primary" :loading="busy" :disabled="!policyReady" @click="savePolicy">
            {{ t('tenantIdentity.actions.savePolicy') }}
          </el-button>
        </div>
      </template>
    </el-drawer>

    <el-dialog
      :model-value="!!credentials"
      :title="t('tenantIdentity.actions.saveCredentials')"
      width="min(520px, calc(100vw - 32px))"
      class="tenant-identity-credentials"
      align-center
      append-to-body
      :close-on-click-modal="false"
      @close="credentials = null"
    >
      <div v-if="credentials" class="identity-content credential-panel">
        <el-alert :title="t('tenantIdentity.descriptions.credentials')" type="warning" :closable="false" show-icon />
        <el-form label-position="top">
          <el-form-item :label="t('tenantIdentity.labels.username')">
            <div class="copy-field">
              <el-input :model-value="credentials.username" readonly />
              <el-button @click="copy(credentials.username)">{{ t('tenantIdentity.actions.copy') }}</el-button>
            </div>
          </el-form-item>
          <el-form-item v-if="credentials.email" :label="t('tenantIdentity.labels.email')">
            <el-input :model-value="credentials.email" readonly />
          </el-form-item>
          <el-form-item v-if="credentials.group" :label="t('tenantIdentity.labels.userGroup')">
            <el-input :model-value="credentials.group" readonly />
          </el-form-item>
          <el-form-item :label="t('tenantIdentity.labels.temporaryPassword')">
            <div class="copy-field">
              <el-input :model-value="credentials.password" readonly />
              <el-button @click="copy(credentials.password)">{{ t('tenantIdentity.actions.copy') }}</el-button>
            </div>
          </el-form-item>
          <p v-if="credentials.resetTime" class="secondary">{{ t('tenantIdentity.labels.resetTime', { time: credentials.resetTime }) }}</p>
        </el-form>
        <div class="form-actions">
          <el-button @click="credentials = null">{{ t('tenantIdentity.actions.savedClose') }}</el-button>
          <el-button type="primary" @click="copyCredentials">{{ t('tenantIdentity.actions.copyAllCredentials') }}</el-button>
        </div>
      </div>
    </el-dialog>
  </div>
</template>

<style scoped>
.identity-workspace {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-width: 0;
  min-height: 0;
  color: var(--text-primary);
  font-family: var(--sans);
  font-size: var(--font-size-body);
}

.identity-card {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-width: 0;
  min-height: 0;
}

.identity-tab-pane {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-width: 0;
  min-height: 0;
}

.identity-toolbar {
  border-bottom: 1px solid var(--border);
  gap: 12px 16px;
}

.identity-toolbar-lead {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px 12px;
  min-width: 0;
  flex: 1 1 420px;
}

.tenant-context {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  max-width: 240px;
  min-height: 36px;
  padding: 0 12px;
  border-radius: var(--r-pill);
  background: var(--bg-card-subtle);
  border: 1px solid var(--border);
  color: var(--text-primary);
  font-size: var(--font-size-secondary);
  font-weight: 500;
}

.context-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--brand);
  flex-shrink: 0;
}

.context-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.identity-tab-bar {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px;
  padding: 3px;
  background: var(--bg-search);
  border: 1px solid var(--border);
  border-radius: var(--r-pill);
}

.identity-tab-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 28px;
  padding: 0 12px;
  border: 0;
  border-radius: var(--r-pill);
  background: transparent;
  color: var(--text-secondary);
  font: inherit;
  font-size: var(--font-size-secondary);
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  transition: color 160ms ease, background-color 160ms ease, box-shadow 160ms ease;
}

.identity-tab-btn i {
  font-size: 15px;
}

.identity-tab-btn:hover:not(:disabled) {
  color: var(--text-primary);
}

.identity-tab-btn.is-active {
  background: var(--bg-card);
  color: var(--brand);
  font-weight: 600;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
}

.identity-search {
  max-width: 260px;
  flex: 1 1 180px;
}

.identity-notice-wrap {
  padding: 12px 20px 0;
}

.identity-notice-wrap-inline {
  margin-bottom: 16px;
}

.identity-loading-state {
  position: relative;
  display: grid;
  place-items: center;
  flex: 1;
  width: 100%;
  min-height: 280px;
  padding: 24px;
}

.identity-table-stage {
  min-height: 240px;
}

.identity-subpanel {
  padding: 0 20px;
}

.identity-subpanel:empty {
  display: none;
}

.identity-actions-col {
  min-width: 224px;
  width: 224px;
}

.identity-cell-text,
.identity-email-text {
  display: block;
  max-width: 280px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-name {
  display: block;
  max-width: 220px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 600;
  color: var(--text-primary);
}

.table-actions {
  display: inline-flex;
  align-items: center;
  flex-wrap: nowrap;
  gap: 12px;
  white-space: nowrap;
}

.table-actions :deep(.el-button + .el-button) {
  margin-left: 0;
}

.table-actions :deep(.el-button.is-link) {
  min-height: 0;
  height: auto;
  padding: 2px 4px;
  border-radius: var(--r-xs);
  font-weight: 500;
  white-space: nowrap;
  flex-shrink: 0;
}

.table-actions :deep(.el-button > span) {
  white-space: nowrap;
  overflow-wrap: normal;
  word-break: keep-all;
}

.identity-card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 20px;
  border-top: 1px solid var(--border);
  background: var(--bg-card);
}

.identity-mfa-stage {
  padding: 20px;
  overflow-y: auto;
  flex: 1;
}

.identity-stage-desc {
  margin: 0 0 16px;
  color: var(--text-secondary);
  font-size: var(--font-size-secondary);
}

.notification-form {
  display: flex;
  gap: 12px;
  align-items: center;
  flex-wrap: wrap;
  padding: 16px 18px;
  margin-top: 16px;
  margin-bottom: 12px;
  background: var(--bg-card-subtle);
  border: 1px solid var(--border);
  border-radius: var(--r-card);
}

.notification-form .el-form-item {
  flex: 1;
  min-width: 220px;
  margin-bottom: 0;
}

.notification-form .actions {
  display: flex;
  gap: 8px;
  padding-top: 25px;
}

.factor-list {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--r-card);
  overflow: hidden;
}

.factor-row,
.policy-row,
.setting-row,
.form-actions {
  display: flex;
  align-items: center;
}

.factor-row {
  gap: 16px;
  padding: 18px 20px;
}

.factor-row + .factor-row,
.policy-row + .policy-row {
  border-top: 1px solid var(--border);
}

.factor-icon {
  width: 40px;
  height: 40px;
  border-radius: var(--r-sm);
  background: var(--brand-subtle);
  color: var(--brand);
  display: grid;
  place-items: center;
  font-size: 20px;
  flex-shrink: 0;
}

.factor-label {
  flex: 1;
  min-width: 0;
  overflow-wrap: anywhere;
}

.factor-label strong,
.setting-row strong {
  font-size: var(--font-size-body);
  font-weight: 500;
}

.factor-label p,
.setting-row p {
  margin-top: 4px;
}

.form-actions {
  justify-content: flex-end;
  flex-wrap: wrap;
  gap: 10px;
  padding-top: 20px;
  margin-top: 18px;
  border-top: 1px solid var(--border);
}

.form-actions.spread {
  justify-content: space-between;
}

.form-actions .actions {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.secondary,
.field-hint {
  color: var(--text-secondary);
  font-size: var(--font-size-secondary);
  line-height: 1.6;
  margin: 0;
}

.field-hint {
  margin-top: 8px;
}

.copy-field {
  display: flex;
  gap: 8px;
  width: 100%;
}

.copy-field .el-input {
  min-width: 0;
}

:global(.tenant-identity-credentials),
:global(.identity-drawer) {
  font-family: var(--sans);
  font-size: var(--font-size-body);
  color: var(--text-primary);
}

:global(.tenant-identity-credentials .el-dialog__title) {
  font-size: var(--font-size-dialog-title);
  font-weight: 600;
  color: var(--text-primary);
}

:global(.identity-drawer) {
  --el-drawer-bg-color: var(--bg-card);
  background: var(--bg-card);
}

:global(.identity-drawer .el-drawer__header) {
  margin: 0;
  padding: 18px 20px;
  border-bottom: 1px solid var(--border);
  color: var(--text-primary);
  align-items: flex-start;
  gap: 12px;
}

:global(.identity-drawer .el-drawer__close-btn) {
  width: 36px;
  height: 36px;
  border-radius: var(--r-pill);
  color: var(--text-secondary);
  flex-shrink: 0;
  transition: background-color 180ms ease, color 180ms ease;
}

:global(.identity-drawer .el-drawer__close-btn:is(:hover, :focus-visible)) {
  color: var(--brand);
  background: var(--bg-hover);
}

:global(.identity-drawer .el-drawer__body) {
  min-height: 0;
  padding: 20px;
  overflow-y: auto;
  overscroll-behavior: contain;
  scrollbar-gutter: stable;
  background: var(--bg-card);
}

:global(.identity-drawer .el-drawer__footer) {
  padding: 0;
  border-top: 1px solid var(--border);
  background: var(--bg-card);
}

:global(.tenant-identity-confirm) {
  font-family: var(--sans);
  --el-messagebox-title-color: var(--text-primary);
  --el-messagebox-content-color: var(--text-primary);
  --el-messagebox-font-size: var(--font-size-dialog-title);
  --el-messagebox-content-font-size: var(--font-size-body);
}

:global(.tenant-identity-confirm .el-message-box__title) {
  font-weight: 600;
}

:global(.tenant-identity-select.el-popper) {
  font-family: var(--sans);
  font-size: var(--font-size-body);
}

:is(.identity-drawer-body, .identity-drawer-footer) :deep(.el-button),
.identity-drawer-body :deep(.el-input__inner),
.identity-drawer-body :deep(.el-select__wrapper),
.identity-drawer-body :deep(.el-form-item__label),
.identity-drawer-body :deep(.el-checkbox__label) {
  font-size: var(--font-size-body);
  font-family: var(--sans);
}

:is(.identity-drawer-body, .identity-drawer-footer) :deep(.el-button) {
  max-width: 100%;
  border-radius: var(--r-btn);
  line-height: 1.4;
  white-space: normal;
  transition: transform 180ms ease, background-color 180ms ease, border-color 180ms ease;
}

:is(.identity-drawer-body, .identity-drawer-footer) :deep(.el-button:not(.is-link)) {
  min-height: 36px;
  height: auto;
  padding: 7px 16px;
  font-weight: 500;
}

.identity-drawer-footer :deep(.el-button + .el-button) {
  margin-left: 0;
}

.identity-drawer-footer :deep(.el-button--primary:not(.is-link)) {
  border-radius: var(--r-pill);
  padding-inline: 18px;
}

.identity-drawer-body :deep(.el-input__wrapper),
.identity-drawer-body :deep(.el-select__wrapper) {
  border-radius: var(--r-sm);
  min-height: 40px;
}

.identity-drawer-body :deep(.el-input),
.identity-drawer-body :deep(.el-select) {
  width: 100%;
  --el-input-bg-color: var(--bg-card);
  --el-fill-color-blank: var(--bg-card);
  --el-border-color: var(--border);
  --el-border-color-hover: var(--border-strong);
}

.identity-drawer-body :deep(.el-form-item__label) {
  color: var(--text-primary);
  font-weight: 500;
}

.identity-drawer-body :deep(.el-switch) {
  --el-switch-on-color: var(--brand);
  --el-switch-off-color: var(--border-strong);
  flex-shrink: 0;
}

.identity-drawer-header {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}

.identity-drawer-icon {
  width: 38px;
  height: 38px;
  border-radius: 10px;
  background: var(--brand-subtle);
  color: var(--brand);
  display: grid;
  place-items: center;
  font-size: 20px;
  flex-shrink: 0;
}

.identity-drawer-heading {
  min-width: 0;
}

.identity-drawer-title {
  margin: 0;
  font-size: var(--font-size-dialog-title);
  font-weight: 600;
  line-height: 1.35;
  color: var(--text-primary);
}

.identity-drawer-subtitle {
  margin: 2px 0 0;
  font-size: var(--font-size-secondary);
  color: var(--text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.identity-drawer-body {
  display: flex;
  flex-direction: column;
  gap: 16px;
  color: var(--text-primary);
  font-family: var(--sans);
  font-size: var(--font-size-body);
}

.drawer-intro-banner {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 12px 14px;
  border-radius: var(--r-sm);
  background: var(--brand-subtle);
  border: 1px solid color-mix(in srgb, var(--brand) 22%, var(--border));
  color: var(--text-primary);
  font-size: var(--font-size-secondary);
  line-height: 1.55;
}

.drawer-intro-banner i {
  font-size: 18px;
  color: var(--brand);
  flex-shrink: 0;
  margin-top: 2px;
}

.drawer-intro-banner p {
  margin: 0;
}

.drawer-section-card {
  background: var(--bg-card-subtle);
  border: 1px solid var(--border);
  border-radius: var(--r-card);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.drawer-section-label {
  font-size: var(--font-size-caption);
  font-weight: 600;
  letter-spacing: .04em;
  color: var(--text-secondary);
}

.drawer-form {
  position: relative;
}

.drawer-last-item {
  margin-bottom: 0;
}

.drawer-hidden-submit {
  position: absolute;
  width: 0;
  height: 0;
  padding: 0;
  border: 0;
  opacity: 0;
  pointer-events: none;
}

.drawer-toggle-strip {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--r-sm);
  padding: 8px 12px;
  margin-bottom: 16px;
}

.drawer-toggle-strip :deep(.el-checkbox) {
  margin-bottom: 0;
  min-height: 24px;
}

.policy-days-input {
  width: 100%;
  max-width: 220px;
  --el-component-size: 40px;
  --el-fill-color-light: var(--bg-card-subtle);
  --el-border-color: var(--border);
}

.policy-days-input :deep(.el-input__wrapper) {
  min-height: 40px;
}

.policy-days-input :deep(.el-input-number__decrease),
.policy-days-input :deep(.el-input-number__increase) {
  background: var(--bg-card-subtle);
  color: var(--text-primary);
  border-color: var(--border);
}

.policy-days-input :deep(.el-input-number__decrease:hover),
.policy-days-input :deep(.el-input-number__increase:hover) {
  color: var(--brand);
}

.identity-drawer-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  padding: 14px 20px;
}

.setting-row {
  justify-content: space-between;
  gap: 16px;
  padding: 2px 0;
}

.setting-copy {
  min-width: 0;
}

.policy-expiry-field {
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
}

.policy-list {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--r-sm);
  overflow: hidden;
}

.policy-row {
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px 12px;
  padding: 12px 14px;
  font-size: var(--font-size-body);
}

.policy-name {
  font-weight: 500;
  color: var(--text-primary);
  overflow-wrap: anywhere;
}

.policy-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  max-width: 100%;
  border-radius: var(--r-pill);
  padding: 3px 10px;
  font-size: var(--font-size-caption);
  font-weight: 500;
}

.policy-badge.is-expiring {
  background: var(--brand-subtle);
  color: var(--brand);
}

.policy-badge.is-permanent {
  background: var(--bg-hover);
  color: var(--text-secondary);
}

.credential-panel :deep(.el-alert) {
  margin-bottom: 18px;
  border-radius: var(--r-sm);
}

.credential-panel :deep(.el-input__inner) {
  font-family: var(--sans);
  color: var(--text-primary);
}

.identity-panel-enter-active {
  transition: opacity 200ms ease, transform 260ms cubic-bezier(.2, .8, .2, 1);
}

.identity-panel-leave-active {
  transition: opacity 110ms ease, transform 110ms ease;
}

.identity-panel-enter-from {
  opacity: 0;
  transform: translateY(7px);
}

.identity-panel-leave-to {
  opacity: 0;
  transform: translateY(-3px);
}

@media (max-width: 760px) {
  .identity-toolbar-lead {
    flex-basis: 100%;
  }

  .tenant-context {
    max-width: 100%;
  }

  .identity-tab-bar {
    width: 100%;
    overflow-x: auto;
  }

  .identity-tab-btn {
    min-height: 36px;
    flex: 1 0 auto;
    justify-content: center;
  }

  .identity-search {
    max-width: none;
    flex-basis: 100%;
  }

  .identity-notice-wrap,
  .identity-subpanel,
  .identity-mfa-stage {
    padding-inline: 12px;
  }

  .identity-card-footer {
    padding: 12px;
  }

  .identity-mobile-list {
    padding: 0;
  }

  .identity-mobile-list :deep(.el-button) {
    min-height: 44px;
    margin-left: 0;
  }

  .notification-form {
    padding: 14px;
  }

  .notification-form .el-form-item {
    min-width: 0;
    flex-basis: 100%;
  }

  .notification-form .actions {
    width: 100%;
    justify-content: flex-end;
    padding-top: 4px;
  }

  .form-actions.spread {
    flex-direction: column;
    align-items: stretch;
  }

  .form-actions.spread > :deep(.el-button) {
    width: 100%;
  }

  .form-actions.spread .actions {
    width: 100%;
    display: grid;
    grid-template-columns: 1fr 1fr;
  }

  :global(.identity-drawer .el-drawer__header) {
    padding: 16px 16px 14px;
  }

  :global(.identity-drawer .el-drawer__close-btn) {
    width: 44px;
    height: 44px;
  }

  :global(.identity-drawer .el-drawer__body) {
    padding: 16px;
  }

  .drawer-section-card {
    padding: 14px;
  }

  .drawer-toggle-strip {
    min-height: 44px;
    display: flex;
    align-items: center;
  }

  .policy-days-input {
    max-width: none;
    width: 100%;
    --el-component-size: 44px;
  }

  .policy-days-input :deep(.el-input__wrapper) {
    min-height: 44px;
  }

  .identity-drawer-footer {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    padding: 12px 16px calc(12px + env(safe-area-inset-bottom));
  }

  .identity-drawer-footer :deep(.el-button) {
    width: 100%;
    min-height: 44px;
    margin-left: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .identity-panel-enter-active,
  .identity-panel-leave-active,
  .identity-tab-btn,
  :is(.identity-drawer-footer, .identity-drawer-body) :deep(.el-button),
  :global(.identity-drawer .el-drawer__close-btn) {
    transition: none;
  }
}
</style>
