<script setup lang="ts">
import { hasTenantPermission, isManagedTenant, type TenantPermission } from '@/utils/tenantPermissions'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantPost } from '@/api/tenant'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'

type Row = Record<string, any>
type LoadKey = 'email' | 'social'
const props = defineProps<{ tenant: Row | null; action: string }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const { t, locale } = useI18n()
const compact = useCompactViewport()
const tenantId = computed(() => String(props.tenant?.id ?? ''))
const managed = computed(() => isManagedTenant(props.tenant))
const allowed = (permission: TenantPermission) => hasTenantPermission(props.tenant, permission)
const canManageSecurity = computed(() => allowed('DOMAIN_SECURITY_MANAGE'))
const tenantName = computed(() => props.tenant?.defName || props.tenant?.tenancyName || t('tenantIdentity.currentTenant'))
const visible = computed(() => !!props.tenant && ['email', 'social'].includes(props.action)
  && (props.action === 'social' ? canManageSecurity.value : !managed.value))
const title = computed(() => ['email', 'social'].includes(props.action) ? t(`tenantIdentity.titles.${props.action}`) : '')
const editor = ref('')
const busy = ref(false)
const loading = reactive<Record<LoadKey, boolean>>({ email: false, social: false })
const errors = reactive<Record<LoadKey, unknown>>({ email: null, social: null })
const emailDomain = ref('')
const emailReadOnly = ref(false)
const socialRows = ref<Row[]>([])
const socialTypes = ref<string[]>([])
const socialForm = reactive({ id: '', socialTypeStr: '', clientId: '', clientSecret: '', redirectUrl: '' })
const SOCIAL_PROVIDER_CONSOLES: Record<string, { url: string; labelKey: string; hintKey: string; icon: string }> = {
  google: {
    url: 'https://console.cloud.google.com/apis/credentials',
    labelKey: 'tenantIdentity.actions.openGoogleConsole',
    hintKey: 'tenantIdentity.descriptions.googleConsoleHint',
    icon: 'i-mdi-google',
  },
}
const socialConsole = computed(() => SOCIAL_PROVIDER_CONSOLES[socialForm.socialTypeStr.trim().toLowerCase()] || null)
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

async function mutate(request: () => Promise<any>, success: (data: any) => void | Promise<void>, messageKey = 'tenantIdentity.messages.saved') {
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

function close() {
  if (!busy.value) emit('close')
}

function guardSocialClose(done: () => void) {
  if (!busy.value) done()
}

function closeEditor() {
  editor.value = ''
  socialForm.clientSecret = ''
}

function loadEmail() {
  if (managed.value) return
  return read('email', signal => tenantPost('/email/tenant/get', { tenantId: tenantId.value }, { signal }), result => {
    emailDomain.value = result.data?.[0]?.domainName || ''
  })
}

async function saveEmail() {
  if (managed.value) return
  const domain = emailDomain.value.trim()
  if (!domain || domain.length > 100 || !/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/.test(domain)) {
    ElMessage.warning(t('tenantIdentity.validation.domain'))
    return
  }
  if (!await confirm(t('tenantIdentity.confirmations.configureEmail', { tenant: tenantName.value, domain }), t('tenantIdentity.actions.configureEmail'))) return
  await mutate(() => tenantPost('/tenants/email/enable', { tenantId: tenantId.value, emailDomain: domain }, { timeout: 60000 }), () => { emailReadOnly.value = true }, 'tenantIdentity.messages.emailConfigured')
}

function loadSocial() {
  if (!canManageSecurity.value) return
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
  if (!canManageSecurity.value) return
  Object.assign(socialForm, {
    id: row?.id || '',
    socialTypeStr: row?.socialTypeStr || row?.serviceProviderName || socialTypes.value[0] || '',
    clientId: row?.clientId || '',
    clientSecret: row?.clientSecret || '',
    redirectUrl: row?.redirectUrl || '',
  })
  editor.value = 'social'
}

async function saveSocial() {
  if (!canManageSecurity.value) return
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
  if (!canManageSecurity.value) return
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
  } catch {
    ElMessage.warning(t('tenantIdentity.messages.copyFailed'))
  }
}

watch(() => [props.action, tenantId.value], () => {
  generation += 1
  readController.abort()
  readController = new AbortController()
  Object.keys(loading).forEach(key => {
    loading[key as LoadKey] = false
    errors[key as LoadKey] = null
  })
  busy.value = false
  editor.value = ''
  emailDomain.value = ''
  socialRows.value = []
  socialTypes.value = []
  socialForm.clientSecret = ''
  if (!visible.value) return
  if (props.action === 'social') void loadSocial()
  if (props.action === 'email') {
    emailReadOnly.value = Number(props.tenant?.emailEnable) === 1
    if (emailReadOnly.value) void loadEmail()
  }
}, { immediate: true })

onBeforeUnmount(() => {
  generation += 1
  readController.abort()
})
</script>

<template>
  <el-drawer
    v-if="visible && action === 'social'"
    :model-value="true"
    direction="rtl"
    :size="compact ? 'min(96vw, 520px)' : 'min(860px, 82vw)'"
    class="tenant-social-drawer"
    append-to-body
    destroy-on-close
    :close-on-click-modal="!busy && editor !== 'social'"
    :close-on-press-escape="!busy"
    :show-close="!busy"
    :before-close="guardSocialClose"
    @close="close"
  >
    <template #header>
      <div class="social-drawer-header">
        <span class="social-drawer-icon" aria-hidden="true"><i class="i-mdi-share-variant-outline" /></span>
        <div class="social-drawer-heading">
          <h2 class="social-drawer-title">{{ title }}</h2>
          <p class="social-drawer-subtitle">
            {{ tenantName }}<span v-if="tenant?.region"> · {{ tenant.region }}</span>
          </p>
        </div>
      </div>
    </template>

    <div class="identity-content social-drawer-body" :aria-busy="busy">
      <Transition name="social-view" mode="out-in">
        <section v-if="editor !== 'social'" key="list" class="identity-panel social-panel">
          <div class="social-toolbar-card">
            <p class="secondary">{{ t('tenantIdentity.descriptions.social') }}</p>
            <div class="actions">
              <el-button :disabled="busy || loading.social" @click="loadSocial">{{ t('tenantIdentity.actions.refresh') }}</el-button>
              <el-button type="primary" :disabled="busy || !socialTypes.length" @click="editSocial()">{{ t('tenantIdentity.actions.addSocial') }}</el-button>
            </div>
          </div>
          <PageErrorNotice v-if="errors.social">{{ errorMessage(errors.social) }}</PageErrorNotice>
          <MobileRecordList
            v-if="compact"
            drilldown
            :list-id="`identity-social-${tenantId}`"
            :record-keys="socialRows.map(row => String(row.id))"
            :loading="loading.social"
            class="identity-mobile-list"
          >
            <MobileRecordCard
              v-for="row in socialRows"
              :key="row.id"
              :record-key="String(row.id)"
              :summary-title="row.socialTypeStr || row.serviceProviderName || t('tenantIdentity.status.unknown')"
              :summary-meta="row.clientId || '—'"
              :summary-status="socialStatus(row.socialStatus)"
              :summary-tone="!row.socialStatus || row.socialStatus === 'null' || row.socialStatus === 'active' ? 'success' : 'neutral'"
            >
              <template #identity>
                <h3 class="mobile-record-title">{{ row.socialTypeStr || row.serviceProviderName || t('tenantIdentity.status.unknown') }}</h3>
              </template>
              <dl class="mobile-record-fields">
                <div class="mobile-record-wide"><dt>{{ t('tenantIdentity.labels.clientId') }}</dt><dd>{{ row.clientId || '—' }}</dd></div>
                <div class="mobile-record-wide"><dt>{{ t('tenantIdentity.labels.redirectUrl') }}</dt><dd>{{ row.redirectUrl || '—' }}</dd></div>
                <div class="mobile-record-wide">
                  <dt>{{ t('tenantIdentity.labels.status') }}</dt>
                  <dd>
                    <span class="status-pill" :class="!row.socialStatus || row.socialStatus === 'null' || row.socialStatus === 'active' ? 'is-active' : 'is-inactive'">
                      {{ socialStatus(row.socialStatus) }}
                    </span>
                  </dd>
                </div>
              </dl>
              <template #footer>
                <el-button :disabled="busy || loading.social" @click="editSocial(row)">{{ t('tenantIdentity.actions.edit') }}</el-button>
                <el-button plain :disabled="busy || loading.social" :type="row.socialStatus === 'disabled' ? 'primary' : 'danger'" @click="toggleSocial(row)">
                  {{ t(row.socialStatus === 'disabled' ? 'tenantIdentity.actions.enable' : 'tenantIdentity.actions.disable') }}
                </el-button>
              </template>
            </MobileRecordCard>
            <p v-if="loading.social || !socialRows.length" class="identity-mobile-empty" role="status">
              {{ t(loading.social ? 'pageLoading.loading' : 'tenantIdentity.empty.social') }}
            </p>
          </MobileRecordList>
          <el-table v-else v-loading="loading.social" :data="socialRows" row-key="id" max-height="calc(100dvh - 280px)" class="identity-table" :empty-text="t('tenantIdentity.empty.social')">
            <el-table-column :label="t('tenantIdentity.labels.loginService')" min-width="120">
              <template #default="{ row }">
                <span class="user-name">{{ row.socialTypeStr || row.serviceProviderName || t('tenantIdentity.status.unknown') }}</span>
              </template>
            </el-table-column>
            <el-table-column prop="clientId" :label="t('tenantIdentity.labels.clientId')" min-width="160" show-overflow-tooltip />
            <el-table-column prop="redirectUrl" :label="t('tenantIdentity.labels.redirectUrl')" min-width="210" show-overflow-tooltip />
            <el-table-column :label="t('tenantIdentity.labels.status')" width="100">
              <template #default="{ row }">
                <span class="status-pill" :class="!row.socialStatus || row.socialStatus === 'null' || row.socialStatus === 'active' ? 'is-active' : 'is-inactive'">
                  {{ socialStatus(row.socialStatus) }}
                </span>
              </template>
            </el-table-column>
            <el-table-column :label="t('tenantIdentity.labels.actions')" :width="locale.startsWith('en') ? 156 : 128" fixed="right">
              <template #default="{ row }">
                <div class="table-actions">
                  <el-button link :disabled="busy" @click="editSocial(row)">{{ t('tenantIdentity.actions.edit') }}</el-button>
                  <el-button link :disabled="busy" :type="row.socialStatus === 'disabled' ? 'primary' : 'danger'" @click="toggleSocial(row)">
                    {{ t(row.socialStatus === 'disabled' ? 'tenantIdentity.actions.enable' : 'tenantIdentity.actions.disable') }}
                  </el-button>
                </div>
              </template>
            </el-table-column>
          </el-table>
        </section>

        <section v-else key="editor" class="identity-panel social-editor-panel">
          <div class="section-title">
            <el-button text :disabled="busy" @click="closeEditor">← {{ t('tenantIdentity.actions.backToSocial') }}</el-button>
            <h3>{{ t(socialForm.id ? 'tenantIdentity.actions.editSocial' : 'tenantIdentity.actions.addSocial') }}</h3>
          </div>
          <div class="social-editor-card">
            <el-form label-position="top" :disabled="busy" @submit.prevent="saveSocial">
              <button type="submit" class="drawer-hidden-submit" tabindex="-1" aria-hidden="true" />
              <el-form-item :label="t('tenantIdentity.labels.loginService')" required>
                <el-input v-if="socialForm.id" :model-value="socialForm.socialTypeStr" readonly />
                <el-select v-else v-model="socialForm.socialTypeStr" popper-class="tenant-identity-select" :placeholder="t('tenantIdentity.placeholders.loginService')">
                  <el-option v-for="provider in socialTypes" :key="provider" :label="provider" :value="provider" />
                </el-select>
              </el-form-item>
              <div v-if="socialConsole" class="social-console-bar">
                <div class="social-console-copy">
                  <i :class="socialConsole.icon" aria-hidden="true" />
                  <span>{{ t(socialConsole.hintKey) }}</span>
                </div>
                <a
                  class="social-console-link"
                  :href="socialConsole.url"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <span>{{ t(socialConsole.labelKey) }}</span>
                  <i class="i-mdi-open-in-new" aria-hidden="true" />
                </a>
              </div>
              <el-form-item :label="t('tenantIdentity.labels.clientIdField')" required>
                <el-input v-model="socialForm.clientId" autocomplete="off" />
              </el-form-item>
              <el-form-item :label="t('tenantIdentity.labels.clientSecret')" required :class="{ 'social-last-item': !socialForm.redirectUrl }">
                <el-input v-model="socialForm.clientSecret" type="password" show-password autocomplete="new-password" />
              </el-form-item>
              <el-form-item v-if="socialForm.redirectUrl" :label="t('tenantIdentity.labels.redirectUrl')" class="social-last-item">
                <div class="copy-field">
                  <el-input :model-value="socialForm.redirectUrl" readonly />
                  <el-button @click="copy(socialForm.redirectUrl)">{{ t('tenantIdentity.actions.copy') }}</el-button>
                </div>
                <p class="field-hint">{{ t('tenantIdentity.descriptions.redirectUrl') }}</p>
              </el-form-item>
            </el-form>
          </div>
        </section>
      </Transition>
    </div>

    <template #footer>
      <div class="social-drawer-footer" :class="{ 'is-editing': editor === 'social' }">
        <template v-if="editor === 'social'">
          <el-button :disabled="busy" @click="closeEditor">{{ t('tenantIdentity.actions.cancel') }}</el-button>
          <el-button type="primary" :loading="busy" @click="saveSocial">{{ t('tenantIdentity.actions.saveConfig') }}</el-button>
        </template>
        <el-button v-else :disabled="busy" @click="close">{{ t('tenantIdentity.actions.close') }}</el-button>
      </div>
    </template>
  </el-drawer>

  <el-dialog
    v-else-if="visible"
    :model-value="true"
    :title="title"
    width="min(560px, calc(100vw - 32px))"
    class="tenant-identity-dialog"
    align-center
    append-to-body
    destroy-on-close
    :close-on-click-modal="false"
    :close-on-press-escape="!busy"
    :show-close="!busy"
    @close="close"
  >
    <div class="identity-content" :aria-busy="busy">
      <div class="tenant-context-bar">
        <span class="tenant-context"><span class="context-dot" /><span>{{ tenantName }}</span></span>
      </div>

      <section v-if="action === 'email'" class="identity-panel email-panel" v-loading="loading.email">
        <div class="service-icon i-mdi-email-fast-outline" />
        <h3>{{ t('tenantIdentity.descriptions.emailTitle') }}</h3>
        <p class="secondary">{{ t('tenantIdentity.descriptions.email') }}</p>
        <PageErrorNotice v-if="errors.email">
          <p>{{ errorMessage(errors.email) }}</p>
          <el-button text @click="loadEmail">{{ t('tenantIdentity.actions.reload') }}</el-button>
        </PageErrorNotice>
        <el-form label-position="top" @submit.prevent="saveEmail">
          <el-form-item :label="t('tenantIdentity.labels.emailDomain')" required>
            <el-input v-model="emailDomain" :placeholder="t('tenantIdentity.placeholders.domain')" :maxlength="100" :disabled="emailReadOnly || busy" />
          </el-form-item>
          <p class="field-hint">{{ t('tenantIdentity.descriptions.emailDomain') }}</p>
          <div class="form-actions">
            <el-button :disabled="busy" @click="close">{{ t('tenantIdentity.actions.close') }}</el-button>
            <el-button v-if="emailReadOnly" :disabled="loading.email || !!errors.email" @click="emailReadOnly = false">
              {{ t('tenantIdentity.actions.reconfigure') }}
            </el-button>
            <el-button v-else type="primary" native-type="submit" :loading="busy">
              {{ t('tenantIdentity.actions.configureEmail') }}
            </el-button>
          </div>
        </el-form>
      </section>
    </div>
  </el-dialog>
</template>

<style scoped>
.identity-content { color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.tenant-identity-dialog) { font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
:global(.tenant-identity-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); font-weight: 600; color: var(--text-primary); }
:global(.tenant-social-drawer) { --el-drawer-bg-color: var(--bg-card); background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.tenant-social-drawer .el-drawer__header) { margin: 0; padding: 18px 20px 14px; border-bottom: 1px solid var(--border); color: var(--text-primary); align-items: flex-start; gap: 12px; }
:global(.tenant-social-drawer .el-drawer__close-btn) { width: 36px; height: 36px; border-radius: var(--r-pill); color: var(--text-secondary); flex-shrink: 0; transition: background-color 180ms ease, color 180ms ease; }
:global(.tenant-social-drawer .el-drawer__close-btn:is(:hover, :focus-visible)) { color: var(--brand); background: var(--bg-hover); }
:global(.tenant-social-drawer .el-drawer__body) { min-height: 0; padding: 18px 20px; overflow-y: auto; overscroll-behavior: contain; scrollbar-gutter: stable; background: var(--bg-card); }
:global(.tenant-social-drawer .el-drawer__footer) { padding: 0; border-top: 1px solid var(--border); background: var(--bg-card); }
:global(.tenant-identity-confirm) { font-family: var(--sans); --el-messagebox-title-color: var(--text-primary); --el-messagebox-content-color: var(--text-primary); --el-messagebox-font-size: var(--font-size-dialog-title); --el-messagebox-content-font-size: var(--font-size-body); }
:global(.tenant-identity-confirm .el-message-box__title) { font-weight: 600; }
:global(.tenant-identity-select.el-popper) { font-family: var(--sans); font-size: var(--font-size-body); }
:is(.identity-content, .social-drawer-footer) :deep(.el-button),
.identity-content :deep(.el-input__inner),
.identity-content :deep(.el-select__wrapper),
.identity-content :deep(.el-form-item__label),
.identity-content :deep(.el-table) { font-size: var(--font-size-body); font-family: var(--sans); }
.identity-content :deep(.el-alert__description),
.identity-content :deep(.el-form-item__error),
.identity-content :deep(.el-empty__description p) { font-size: var(--font-size-secondary); }
.social-drawer-header { display: flex; align-items: center; gap: 12px; min-width: 0; }
.social-drawer-icon { width: 38px; height: 38px; border-radius: 10px; background: var(--brand-subtle); color: var(--brand); display: grid; place-items: center; font-size: 20px; flex-shrink: 0; }
.social-drawer-heading { min-width: 0; }
.social-drawer-title { margin: 0; font-size: var(--font-size-dialog-title); font-weight: 600; line-height: 1.35; color: var(--text-primary); }
.social-drawer-subtitle { margin: 2px 0 0; font-size: var(--font-size-secondary); color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.social-drawer-body { display: flex; flex-direction: column; gap: 16px; }
.social-panel { display: flex; flex-direction: column; gap: 16px; }
.social-toolbar-card { display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; padding: 14px 16px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); }
.social-editor-panel { display: flex; flex-direction: column; gap: 16px; }
.social-editor-card { padding: 18px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); }
.social-console-bar { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin: -4px 0 18px; padding: 12px 14px; border-radius: var(--r-sm); background: var(--brand-subtle); border: 1px solid color-mix(in srgb, var(--brand) 22%, var(--border)); }
.social-console-copy { display: flex; align-items: flex-start; gap: 8px; flex: 1 1 220px; min-width: 0; color: var(--text-primary); font-size: var(--font-size-secondary); line-height: 1.5; }
.social-console-copy i { font-size: 17px; color: var(--brand); flex-shrink: 0; margin-top: 2px; }
.social-console-link { display: inline-flex; align-items: center; justify-content: center; gap: 6px; min-height: 32px; padding: 5px 12px; border-radius: var(--r-pill); border: 1px solid var(--border-strong); background: var(--bg-card); color: var(--text-primary); font-size: var(--font-size-secondary); font-weight: 600; text-decoration: none; white-space: nowrap; transition: background-color 180ms ease, border-color 180ms ease, color 180ms ease; }
.social-console-link:hover { background: var(--brand-solid); border-color: var(--brand-solid); color: var(--text-on-solid); }
.social-console-link:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
.social-console-link i { font-size: 15px; flex-shrink: 0; }
.social-last-item { margin-bottom: 0; }
.drawer-hidden-submit { position: absolute; width: 0; height: 0; padding: 0; border: 0; opacity: 0; pointer-events: none; }
.social-drawer-footer { display: flex; align-items: center; justify-content: flex-end; gap: 10px; padding: 12px 20px calc(12px + env(safe-area-inset-bottom)); }
.social-drawer-footer :deep(.el-button + .el-button) { margin-left: 0; }
.tenant-context-bar { margin: 0 0 14px; }
.tenant-context { display: inline-flex; align-items: center; gap: 8px; max-width: 100%; padding: 5px 12px; border-radius: var(--r-pill); background: var(--bg-card-subtle); border: 1px solid var(--border); color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.4; }
.context-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--brand); flex-shrink: 0; }
.identity-panel { min-height: 220px; }
.actions, .form-actions { display: flex; align-items: center; }
.actions { min-width: 0; gap: 8px; flex-wrap: wrap; }
.actions :deep(.el-button + .el-button) { margin-left: 0; }
.secondary, .field-hint { color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; margin: 0; }
:is(.identity-content, .social-drawer-footer) :deep(.el-button) { max-width: 100%; border-radius: var(--r-btn); font-family: var(--sans); line-height: 1.4; white-space: normal; }
:is(.identity-content, .social-drawer-footer) :deep(.el-button:not(.is-link)) { min-height: 32px; height: auto; padding: 5px 13px; font-size: var(--font-size-secondary); font-weight: 500; }
:is(.identity-content, .social-drawer-footer) :deep(.el-button--primary:not(.is-link)) { border-radius: var(--r-pill); padding-inline: 15px; }
.identity-content :deep(.el-input__wrapper),
.identity-content :deep(.el-select__wrapper) { border-radius: var(--r-sm); min-height: 40px; }
.identity-content :deep(.el-select) { width: 100%; }
.identity-content :deep(.el-form-item__label) { color: var(--text-primary); font-weight: 500; }
.identity-table { border: 1px solid var(--border); border-radius: var(--r-sm); overflow: hidden; --el-table-border-color: var(--border); --el-table-bg-color: var(--bg-card); --el-table-tr-bg-color: var(--bg-card); --el-table-row-hover-bg-color: var(--bg-hover); --el-table-text-color: var(--text-primary); --el-table-header-text-color: var(--text-secondary); --el-table-header-bg-color: var(--bg-card-subtle); }
.identity-table :deep(th.el-table__cell) { font-size: var(--font-size-body); font-weight: 600; color: var(--text-secondary); background: var(--bg-card-subtle); }
.identity-table :deep(td.el-table__cell) { padding-block: 12px; background: var(--bg-card); }
.table-actions { display: inline-flex; align-items: center; flex-wrap: nowrap; gap: 12px; white-space: nowrap; }
.table-actions :deep(.el-button + .el-button) { margin-left: 0; }
.table-actions :deep(.el-button.is-link) { min-height: 0; height: auto; padding: 2px 4px; border-radius: var(--r-xs); font-weight: 500; white-space: nowrap; flex-shrink: 0; }
.user-name { font-weight: 500; }
.status-pill { display: inline-flex; align-items: center; gap: 5px; max-width: 100%; border-radius: var(--r-pill); padding: 3px 9px; font-size: var(--font-size-caption); }
.status-pill::before { content: ''; width: 4px; height: 4px; background: currentColor; border-radius: 50%; }
.is-active { background: var(--status-ok-bg); color: var(--status-ok); }
.is-inactive { background: var(--bg-hover); color: var(--text-secondary); }
.section-title { display: flex; flex-direction: column; align-items: flex-start; gap: 6px; }
.section-title > .el-button { padding-left: 0; }
.section-title h3, .email-panel h3 { font-size: var(--font-size-section); font-weight: 600; letter-spacing: -.025em; margin: 0; }
.email-panel h3 { margin-bottom: 8px; }
.form-actions { justify-content: flex-end; flex-wrap: wrap; gap: 10px; padding-top: 22px; margin-top: 14px; border-top: 1px solid var(--border); }
.email-panel { padding-top: 6px; }
.service-icon { font-size: 42px; color: var(--brand); margin-bottom: 18px; }
.email-panel > .secondary { margin-bottom: 28px; }
.field-hint { font-size: var(--font-size-secondary); margin-top: 8px; }
.copy-field { display: flex; gap: 8px; width: 100%; }
.copy-field .el-input { min-width: 0; }
.social-view-enter-active,
.social-view-leave-active { transition: opacity 180ms ease, transform 200ms cubic-bezier(.22, 1, .36, 1); }
.social-view-enter-from { opacity: 0; transform: translateX(12px); }
.social-view-leave-to { opacity: 0; transform: translateX(-8px); }
@media (max-width: 760px) {
  :global(.tenant-identity-dialog .el-dialog__body) { min-height: 0; overflow-y: auto; overscroll-behavior: contain; padding-bottom: calc(8px + env(safe-area-inset-bottom)); }
  :global(.tenant-social-drawer .el-drawer__header) { padding: 16px 16px 14px; }
  :global(.tenant-social-drawer .el-drawer__close-btn) { width: 44px; height: 44px; }
  :global(.tenant-social-drawer .el-drawer__body) { padding: 14px 16px; }
  .social-toolbar-card { padding: 12px; }
  .social-toolbar-card .actions { width: 100%; }
  .social-toolbar-card .actions :deep(.el-button:not(.is-link)) { min-height: 44px; flex: 1 1 auto; }
  .social-editor-card { padding: 14px; }
  .social-console-link { width: 100%; min-height: 44px; }
  .social-drawer-footer { padding: 12px 16px calc(12px + env(safe-area-inset-bottom)); }
  .social-drawer-footer.is-editing { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .social-drawer-footer :deep(.el-button) { width: 100%; min-height: 44px; }
  .identity-mobile-list { padding: 0; max-height: 52dvh; overflow-y: auto; overscroll-behavior: contain; }
  .identity-mobile-empty { display: grid; place-items: center; min-height: 88px; margin: 0; color: var(--text-secondary); font-size: var(--font-size-body); }
  .identity-mobile-list :deep(.el-button) { min-height: 44px; margin-left: 0; }
}
@media (prefers-reduced-motion: reduce) {
  :global(.tenant-social-drawer .el-drawer__close-btn),
  .social-console-link,
  .social-view-enter-active,
  .social-view-leave-active { transition: none; }
}
</style>
