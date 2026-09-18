<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { isAxiosError } from 'axios'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantGet, tenantPost, type TenantRow } from '@/api/tenant'

interface MysqlInstance {
  id: string
  dbId?: string
  displayName?: string
  dbVersion?: string
  dbStatus?: string
  dbPublicUrl?: string
  dbPrivateUrl?: string
  dbPort?: number
  dbName?: string
  dbPassword?: string
  shapeName?: string
  dataStorageSizeInGBs?: number
}

type MysqlAction = 'syncAll' | 'syncOne' | 'create' | 'reset' | 'bind' | 'delete'
type MysqlResponse = { success: boolean; message?: string; data?: MysqlInstance[] }

const { t, te, locale } = useI18n()
const compact = useCompactViewport()
const numberFormat = computed(() => new Intl.NumberFormat(locale.value))
function number(value: number) { return numberFormat.value.format(value) }
function message(value: string) { return value.startsWith('tenantRegions.') ? t(value) : value }
function requestError(cause: unknown) {
  if (isAxiosError(cause)) return cause.response?.data?.message || 'tenantRegions.common.requestFailed'
  const value = cause as { message?: string; msg?: string }
  return value?.message || value?.msg || 'tenantRegions.common.requestFailed'
}
const props = defineProps<{ tenant: TenantRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const tenantId = computed(() => String(props.tenant.id))
const tenantLabel = computed(() =>
  [props.tenant.defName || t('tenantRegions.common.currentTenant'), props.tenant.region].filter(Boolean).join(' · '),
)
const rows = ref<MysqlInstance[]>([])
const loading = ref(false)
const busy = ref<MysqlAction | ''>('')
const busyRowId = ref('')
const readError = ref('')
const actionError = ref('')
const notice = ref('')
const revealedPasswords = ref<Set<string>>(new Set())
let generation = 0
let readVersion = 0
let readController: AbortController | null = null

const busyText = computed(() => busy.value ? t(`tenantRegions.mysql.progress.${busy.value}`) : '')

function close() {
  if (!busy.value) emit('close')
}

function nameOf(row: MysqlInstance) {
  return row.displayName || t('tenantRegions.mysql.unnamed')
}

function statusOf(row: MysqlInstance) {
  const value = String(row.dbStatus || '').toUpperCase()
  const key = `tenantRegions.mysql.states.${value}`
  return value && te(key) ? t(key) : row.dbStatus || t('tenantRegions.mysql.states.unknown')
}

function statusClass(row: MysqlInstance) {
  const value = String(row.dbStatus || '').toUpperCase()
  if (value === 'ACTIVE') return 'is-active'
  if (value === 'FAILED') return 'is-failed'
  return ''
}

async function loadMysql() {
  const current = generation
  const version = ++readVersion
  readController?.abort()
  const controller = new AbortController()
  readController = controller
  loading.value = true
  readError.value = ''
  try {
    const result = await tenantGet<MysqlResponse>(
      '/tenants/mysql-info',
      { tenantId: tenantId.value },
      { signal: controller.signal },
    )
    if (current !== generation || version !== readVersion) return
    if (!result?.success) throw new Error(result?.message || 'tenantRegions.mysql.invalidResponse')
    if (!Array.isArray(result.data)) throw new Error('tenantRegions.mysql.invalidResponse')
    rows.value = result.data.map(row => {
      if (!row || row.id == null || (typeof row.id === 'number' && !Number.isSafeInteger(row.id))) {
        throw new Error('tenantRegions.mysql.invalidId')
      }
      const id = String(row.id)
      if (!/^[1-9]\d*$/.test(id)) throw new Error('tenantRegions.mysql.invalidId')
      return { ...row, id }
    })
    revealedPasswords.value = new Set()
  } catch (error) {
    if (current === generation && version === readVersion && !controller.signal.aborted) {
      readError.value = requestError(error)
    }
  } finally {
    if (current === generation && version === readVersion) loading.value = false
  }
}

function refresh() {
  if (!busy.value) void loadMysql()
}

function togglePassword(row: MysqlInstance) {
  const next = new Set(revealedPasswords.value)
  if (next.has(row.id)) next.delete(row.id)
  else next.add(row.id)
  revealedPasswords.value = next
}

async function copy(value: string | undefined, label: string) {
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
    ElMessage.success(t('tenantRegions.mysql.copied', { label }))
  } catch {
    ElMessage.warning(t('tenantRegions.mysql.copyFailed'))
  }
}

function copyOcid(row: MysqlInstance) { void copy(row.dbId, 'OCID') }
function copyPassword(row: MysqlInstance) { void copy(row.dbPassword, t('tenantRegions.mysql.password')) }
function copyUsername(row: MysqlInstance) { void copy(row.dbName, t('tenantRegions.mysql.username')) }
function copyEndpoint(row: MysqlInstance) {
  if (row.dbPublicUrl) void copy(`${row.dbPublicUrl}:${row.dbPort ?? 3306}`, t('tenantRegions.mysql.endpoint'))
}

function confirmationFor(action: MysqlAction, row?: MysqlInstance) {
  const name = row ? nameOf(row) : t('tenantRegions.common.currentTenant')
  const titleKeys: Partial<Record<MysqlAction, string>> = {
    create: 'createTitle', reset: 'reset', bind: 'bind', delete: 'deleteTitle',
  }
  const title = titleKeys[action]
  return title ? {
    title: t(`tenantRegions.mysql.${title}`),
    message: t(`tenantRegions.mysql.${action}Message`, { name }),
  } : null
}

async function execute(action: MysqlAction, row?: MysqlInstance) {
  if (busy.value || (['syncOne', 'reset', 'bind', 'delete'].includes(action) && !row)) return
  const current = generation
  const selectedTenantId = tenantId.value
  const id = row?.id || ''
  busy.value = action
  busyRowId.value = id
  actionError.value = ''
  notice.value = ''
  try {
    const confirmation = confirmationFor(action, row)
    if (confirmation) {
      try {
        await ElMessageBox.confirm(confirmation.message, confirmation.title, {
          customClass: 'tenant-region-mysql-confirm',
          type: 'warning',
          confirmButtonText: t(action === 'delete' ? 'tenantRegions.common.confirmDelete' : 'tenantRegions.common.confirm'),
          cancelButtonText: t('tenantRegions.common.cancel'),
          closeOnClickModal: false,
        })
      } catch { return }
    }
    if (current !== generation) return

    let result: MysqlResponse
    const cloudConfig = { timeout: 360000 }
    const formConfig = {
      ...cloudConfig,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    }
    switch (action) {
      case 'syncAll':
        result = await tenantPost('/tenants/sync-mysql', undefined, {
          ...cloudConfig, params: { tenantId: selectedTenantId },
        })
        break
      case 'syncOne':
        result = await tenantPost('/tenants/sync-single-mysql', undefined, {
          ...cloudConfig, params: { id },
        })
        break
      case 'create':
        result = await tenantPost('/tenants/mysql-create', new URLSearchParams({ tenantId: selectedTenantId }), formConfig)
        break
      case 'reset':
        result = await tenantPost('/tenants/mysql-reset-auth', new URLSearchParams({ id, tenantId: selectedTenantId }), formConfig)
        break
      case 'bind':
        result = await tenantPost('/tenants/bind-public-ip', undefined, {
          ...cloudConfig, params: { id },
        })
        break
      case 'delete':
        result = await tenantPost('/tenants/mysql-action', {
          tenantId: selectedTenantId, id, action: 'delete',
        }, cloudConfig)
        break
    }
    if (current !== generation) return
    if (!result?.success) throw new Error(result?.message || 'tenantRegions.mysql.actionFailed')
    if (action === 'create') {
      notice.value = result.message && result.message !== 'success'
        ? result.message
        : 'tenantRegions.mysql.createSubmitted'
    } else {
      const message = result.message && result.message !== 'success'
        ? result.message
        : t(action === 'delete' ? 'tenantRegions.mysql.deleted' : 'tenantRegions.mysql.done')
      ElMessage.success(message)
    }
    emit('changed')
    await loadMysql()
  } catch (error) {
    if (current === generation) {
      const code = (error as { code?: string })?.code
      actionError.value = code === 'ECONNABORTED' || code === 'ETIMEDOUT'
        ? 'tenantRegions.mysql.timeout'
        : requestError(error)
    }
  } finally {
    if (current === generation) {
      busy.value = ''
      busyRowId.value = ''
    }
  }
}

function syncAll() { void execute('syncAll') }
function createMysql() { void execute('create') }
function handleCommand(command: MysqlAction, row: MysqlInstance) { void execute(command, row) }

watch(tenantId, () => {
  generation += 1
  readController?.abort()
  rows.value = []
  revealedPasswords.value = new Set()
  busy.value = ''
  busyRowId.value = ''
  actionError.value = ''
  notice.value = ''
  void loadMysql()
}, { immediate: true })

onBeforeUnmount(() => {
  generation += 1
  readController?.abort()
  revealedPasswords.value.clear()
  rows.value = []
})

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<MysqlInstance>
</script>

<template>
  <el-dialog
    :model-value="true"
    :title="t('tenantRegions.mysql.title')"
    width="min(1160px, calc(100vw - 32px))"
    class="tenant-region-mysql-dialog"
    align-center
    :close-on-click-modal="false"
    :close-on-press-escape="!busy"
    :show-close="!busy"
    @close="close"
  >
    <div class="mysql-content" :aria-busy="!!busy || loading">
      <div class="mysql-toolbar">
        <span class="tenant-label">{{ tenantLabel }}</span>
        <div class="toolbar-actions">
          <el-button :disabled="!!busy || loading" @click="refresh">{{ t('tenantRegions.common.refresh') }}</el-button>
          <el-button :loading="busy === 'syncAll'" :disabled="!!busy && busy !== 'syncAll'" @click="syncAll">{{ t('tenantRegions.mysql.syncAll') }}</el-button>
          <el-button type="primary" :loading="busy === 'create'" :disabled="!!busy && busy !== 'create'" @click="createMysql">{{ t('tenantRegions.mysql.create') }}</el-button>
        </div>
      </div>

      <PageErrorNotice v-if="readError">
        <p>{{ message(readError) }}</p>
        <el-button text :disabled="!!busy" @click="refresh">{{ t('tenantRegions.common.reload') }}</el-button>
      </PageErrorNotice>
      <PageErrorNotice v-if="actionError">{{ message(actionError) }}</PageErrorNotice>
      <el-alert v-if="notice" :title="message(notice)" type="success" :closable="false" show-icon />

      <MobileRecordList v-if="compact" drilldown :list-id="`region-mysql-${tenantId}`" :record-keys="rows.map(row => row.id)" :loading="loading" class="mysql-mobile-list">
        <MobileRecordCard v-for="row in rows" :key="row.id" :record-key="row.id" :summary-title="nameOf(row)" :summary-meta="row.shapeName || row.dbVersion || t('tenantRegions.mysql.unknownVersion')" :summary-status="statusOf(row)" :summary-tone="statusClass(row) === 'is-active' ? 'success' : statusClass(row) === 'is-failed' ? 'danger' : 'neutral'">
          <template #identity>
            <button type="button" class="copy-name mobile-record-title" :disabled="!row.dbId" :title="row.dbId ? t('tenantRegions.mysql.copyOcid') : undefined" @click="copyOcid(row)">{{ nameOf(row) }}</button>
            <span class="mobile-record-subtitle">{{ row.dbVersion || t('tenantRegions.mysql.unknownVersion') }}</span>
          </template>
          <dl class="mobile-record-fields">
            <div class="mobile-record-wide"><dt>{{ t('tenantRegions.mysql.status') }}</dt><dd><span class="mysql-status" :class="statusClass(row)">{{ statusOf(row) }}</span></dd></div>
            <div><dt>{{ t('tenantRegions.mysql.shape') }}</dt><dd>{{ row.shapeName || '—' }}</dd></div>
            <div><dt>{{ t('tenantRegions.mysql.storage') }}</dt><dd>{{ row.dataStorageSizeInGBs == null ? '—' : `${number(row.dataStorageSizeInGBs)} GB` }}</dd></div>
          </dl>
          <section class="mysql-mobile-details">
            <dl class="mobile-record-fields">
              <div class="mobile-record-wide"><dt>OCID</dt><dd><button v-if="row.dbId" type="button" class="copy-endpoint" :title="t('tenantRegions.mysql.copyOcid')" @click="copyOcid(row)">{{ row.dbId }}</button><span v-else>—</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('tenantRegions.mysql.publicConnection') }}</dt><dd><button v-if="row.dbPublicUrl" type="button" class="copy-endpoint" :title="t('tenantRegions.mysql.copyEndpoint')" @click="copyEndpoint(row)">{{ row.dbPublicUrl }}</button><span v-else>{{ t('tenantRegions.mysql.unbound') }}</span><span class="mobile-record-subtitle">{{ t('tenantRegions.mysql.port', { port: String(row.dbPort ?? 3306) }) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('tenantRegions.mysql.username') }}</dt><dd><button v-if="row.dbName" type="button" class="copy-username" :title="t('tenantRegions.mysql.copyUsername')" @click="copyUsername(row)">{{ row.dbName }}</button><span v-else>{{ t('tenantRegions.mysql.usernameMissing') }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('tenantRegions.mysql.password') }}</dt><dd class="secret-row">
                <code class="secret-value">{{ row.dbPassword ? (revealedPasswords.has(row.id) ? row.dbPassword : '••••••••') : t('tenantRegions.mysql.passwordMissing') }}</code>
                <button type="button" class="icon-button" :disabled="!row.dbPassword" :aria-label="t(revealedPasswords.has(row.id) ? 'tenantRegions.mysql.hideNamedPassword' : 'tenantRegions.mysql.showNamedPassword', { name: nameOf(row) })" :aria-pressed="revealedPasswords.has(row.id)" @click="togglePassword(row)"><span :class="revealedPasswords.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button>
                <button type="button" class="icon-button" :disabled="!row.dbPassword" :aria-label="t('tenantRegions.mysql.copyNamedPassword', { name: nameOf(row) })" @click="copyPassword(row)"><span class="i-mdi-content-copy" aria-hidden="true" /></button>
              </dd></div>
            </dl>
          </section>
          <template #footer>
            <GhostBtn :disabled="!!busy || loading" :loading="busy === 'syncOne' && busyRowId === row.id" @click="execute('syncOne', row)">{{ t('tenantRegions.mysql.syncOne') }}</GhostBtn>
            <GhostBtn :disabled="!!busy || loading" :loading="busy === 'reset' && busyRowId === row.id" @click="execute('reset', row)">{{ t('tenantRegions.mysql.reset') }}</GhostBtn>
            <GhostBtn :disabled="!!busy || loading" :loading="busy === 'bind' && busyRowId === row.id" @click="execute('bind', row)">{{ t('tenantRegions.mysql.bind') }}</GhostBtn>
            <GhostBtn danger :disabled="!!busy || loading" :loading="busy === 'delete' && busyRowId === row.id" @click="execute('delete', row)">{{ t('tenantRegions.mysql.delete') }}</GhostBtn>
          </template>
        </MobileRecordCard>
        <p v-if="loading || (!rows.length && !readError)" class="mysql-mobile-empty" role="status">{{ t(loading ? 'pageLoading.loading' : 'tenantRegions.mysql.empty') }}</p>
      </MobileRecordList>
      <el-table
        v-else
        v-loading="loading"
        :data="rows"
        row-key="id"
        class="mysql-table"
        max-height="min(56vh, 560px)"
        :empty-text="t('tenantRegions.mysql.empty')"
      >
        <el-table-column :label="t('tenantRegions.mysql.instance')" min-width="170">
          <template #default="{ row }">
            <button class="copy-name" :disabled="!row.dbId" :title="row.dbId ? t('tenantRegions.mysql.copyOcid') : undefined" @click="copyOcid(row)">
              {{ nameOf(row) }}
            </button>
            <div class="cell-secondary">{{ row.dbVersion || t('tenantRegions.mysql.unknownVersion') }}</div>
          </template>
        </el-table-column>
        <el-table-column :label="t('tenantRegions.mysql.status')" width="104">
          <template #default="{ row }">
            <span class="mysql-status" :class="statusClass(row)">{{ statusOf(row) }}</span>
          </template>
        </el-table-column>
        <el-table-column :label="t('tenantRegions.mysql.publicConnection')" min-width="188">
          <template #default="{ row }">
            <button v-if="row.dbPublicUrl" class="copy-endpoint" :title="t('tenantRegions.mysql.copyEndpoint')" @click="copyEndpoint(row)">{{ row.dbPublicUrl }}</button>
            <span v-else class="cell-secondary">{{ t('tenantRegions.mysql.unbound') }}</span>
            <div class="cell-secondary">{{ t('tenantRegions.mysql.port', { port: String(row.dbPort ?? 3306) }) }}</div>
          </template>
        </el-table-column>
        <el-table-column :label="t('tenantRegions.mysql.credentials')" min-width="268">
          <template #default="{ row }">
            <button v-if="row.dbName" class="copy-username" :title="t('tenantRegions.mysql.copyUsername')" @click="copyUsername(row)">{{ row.dbName }}</button>
            <span v-else class="cell-secondary">{{ t('tenantRegions.mysql.usernameMissing') }}</span>
            <div class="secret-row">
              <code class="secret-value">{{ row.dbPassword ? (revealedPasswords.has(row.id) ? row.dbPassword : '••••••••') : t('tenantRegions.mysql.passwordMissing') }}</code>
              <button
                class="icon-button"
                :disabled="!row.dbPassword"
                :aria-label="t(revealedPasswords.has(row.id) ? 'tenantRegions.mysql.hideNamedPassword' : 'tenantRegions.mysql.showNamedPassword', { name: nameOf(row) })"
                :aria-pressed="revealedPasswords.has(row.id)"
                :title="revealedPasswords.has(row.id) ? t('tenantRegions.mysql.hidePassword') : t('tenantRegions.mysql.showPassword')"
                @click="togglePassword(row)"
              >
                <span :class="revealedPasswords.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />
              </button>
              <button class="icon-button" :disabled="!row.dbPassword" :aria-label="t('tenantRegions.mysql.copyNamedPassword', { name: nameOf(row) })" :title="t('tenantRegions.mysql.copyPassword')" @click="copyPassword(row)">
                <span class="i-mdi-content-copy" aria-hidden="true" />
              </button>
            </div>
          </template>
        </el-table-column>
        <el-table-column prop="shapeName" :label="t('tenantRegions.mysql.shape')" min-width="150" show-overflow-tooltip />
        <el-table-column :label="t('tenantRegions.mysql.storage')" width="88">
          <template #default="{ row }">{{ row.dataStorageSizeInGBs == null ? '—' : `${number(row.dataStorageSizeInGBs)} GB` }}</template>
        </el-table-column>
        <el-table-column :label="t('tenantRegions.common.actions')" width="72" fixed="right">
          <template #default="{ row }">
            <el-dropdown trigger="click" popper-class="tenant-region-mysql-menu" :disabled="!!busy" @command="handleCommand($event, row)">
              <el-button text :disabled="!!busy" :loading="!!busy && busyRowId === row.id" :aria-label="t('tenantRegions.mysql.namedActions', { name: nameOf(row) })" :title="t('tenantRegions.mysql.actions')">
                <span class="i-mdi-dots-horizontal" aria-hidden="true" />
              </el-button>
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item command="syncOne">{{ t('tenantRegions.mysql.syncOne') }}</el-dropdown-item>
                  <el-dropdown-item command="reset">{{ t('tenantRegions.mysql.reset') }}</el-dropdown-item>
                  <el-dropdown-item command="bind">{{ t('tenantRegions.mysql.bind') }}</el-dropdown-item>
                  <el-dropdown-item command="delete" divided class="mysql-delete-action">{{ t('tenantRegions.mysql.delete') }}</el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
          </template>
        </el-table-column>
      </el-table>
      <p v-if="busyText" class="busy-status" role="status" aria-live="polite">{{ busyText }}</p>
    </div>
  </el-dialog>
</template>

<style scoped>
.mysql-content { min-width: 0; color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.tenant-region-mysql-dialog) { font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
:global(.tenant-region-mysql-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); font-weight: 600; color: var(--text-primary); }
:global(.tenant-region-mysql-confirm) { font-family: var(--sans); --el-messagebox-title-color: var(--text-primary); --el-messagebox-content-color: var(--text-primary); --el-messagebox-font-size: var(--font-size-dialog-title); --el-messagebox-content-font-size: var(--font-size-body); }
:global(.tenant-region-mysql-confirm .el-message-box__title) { font-weight: 600; }
:global(.tenant-region-mysql-menu.el-popper) { font-family: var(--sans); font-size: var(--font-size-body); }
:global(.tenant-region-mysql-menu .el-dropdown-menu__item) { font-family: var(--sans); font-size: var(--font-size-body); }
.mysql-content :deep(.el-button), .mysql-content :deep(.el-input__inner), .mysql-content :deep(.el-select__wrapper), .mysql-content :deep(.el-form-item__label), .mysql-content :deep(.el-table) { font-size: var(--font-size-body); }
.mysql-content :deep(.el-alert__title) { font-size: var(--font-size-body); }
.mysql-content :deep(.el-alert__description), .mysql-content :deep(.el-form-item__error), .mysql-content :deep(.el-empty__description p) { font-size: var(--font-size-secondary); }
.mysql-toolbar { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 16px; }
.tenant-label { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.toolbar-actions { display: flex; flex-shrink: 0; align-items: center; gap: 8px; }
.toolbar-actions :deep(.el-button + .el-button) { margin-left: 0; }
.mysql-content :deep(.el-alert) { margin-bottom: 14px; border-radius: var(--r-sm); }
.mysql-table { border: 1px solid var(--border); border-radius: var(--r-sm); }
.mysql-table :deep(th.el-table__cell) { padding-block: 8px; background: var(--bg-hover); color: var(--text-secondary); font-size: var(--font-size-body); font-weight: 600; }
.mysql-table :deep(td.el-table__cell) { padding-block: 10px; }
.cell-secondary { margin-top: 3px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.copy-name, .copy-endpoint, .copy-username, .icon-button { border: 0; background: transparent; color: var(--text-primary); font: inherit; cursor: pointer; }
.copy-name, .copy-endpoint, .copy-username { display: block; max-width: 100%; padding: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; text-align: left; }
.copy-name { font-weight: 500; }
.copy-endpoint, .copy-username { font-family: var(--sans); font-size: var(--font-size-body); }
.copy-name:hover, .copy-endpoint:hover, .copy-username:hover { color: var(--brand); }
.copy-name:disabled { cursor: default; color: var(--text-primary); }
.mysql-status { display: inline-flex; align-items: center; gap: 6px; color: var(--text-secondary); font-size: var(--font-size-body); white-space: nowrap; }
.mysql-status::before { content: ''; width: 5px; height: 5px; border-radius: 50%; background: currentColor; }
.mysql-status.is-active { color: var(--status-ok); }
.mysql-status.is-failed { color: var(--status-danger); }
.secret-row { display: flex; align-items: center; gap: 4px; min-width: 0; margin-top: 3px; }
.secret-value { max-width: 178px; overflow: auto; color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); white-space: nowrap; scrollbar-width: thin; }
.icon-button { display: inline-flex; flex-shrink: 0; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: var(--r-sm); color: var(--text-secondary); }
.icon-button > span { width: 15px; height: 15px; }
.icon-button:hover:not(:disabled) { background: var(--bg-hover); color: var(--brand); }
.icon-button:disabled { cursor: default; opacity: .4; }
:global(.tenant-region-mysql-menu .mysql-delete-action:not(.is-disabled)) { color: var(--status-danger); }
.busy-status { margin: 12px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
@media (max-width: 760px) {
  :global(.tenant-region-mysql-dialog) { max-height: calc(100dvh - 32px); overflow-y: auto; }
  .mysql-mobile-list { padding: 0; max-height: 58dvh; overflow-y: auto; overscroll-behavior: contain; }
  .mysql-mobile-empty { display: grid; place-items: center; min-height: 88px; padding: 16px; margin: 0; text-align: center; line-height: 1.6; }
  .mysql-mobile-list :deep(.btn) { min-height: 44px; white-space: normal; }
  .mysql-mobile-list .copy-name, .mysql-mobile-list .copy-endpoint, .mysql-mobile-list .copy-username { min-height: 40px; white-space: normal; overflow-wrap: anywhere; }
  .mysql-mobile-list .secret-value { flex: 1; min-width: 0; max-width: none; white-space: normal; overflow-wrap: anywhere; }
  .mysql-mobile-list .icon-button { width: 44px; height: 44px; }
  .mysql-mobile-details { margin-top: 14px; padding-top: 14px; border-top: 1px solid var(--border); }
  .mysql-mobile-list button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; border-radius: var(--r-sm); }
  .mysql-toolbar { flex-wrap: wrap; min-width: 0; max-width: 100%; }
  .tenant-label { flex-basis: 100%; white-space: normal; overflow-wrap: anywhere; }
  .toolbar-actions { flex: 1 1 100%; width: 100%; max-width: 100%; flex-wrap: wrap; gap: 6px; min-width: 0; }
  .toolbar-actions :deep(.el-button) { flex: 0 1 auto; max-width: 100%; height: auto; min-height: 44px; white-space: normal; }
  .toolbar-actions :deep(.el-button > span) { min-width: 0; overflow-wrap: anywhere; }
}
</style>
