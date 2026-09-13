<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantError, tenantGet, tenantPost, type TenantRow } from '@/api/tenant'

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

const props = defineProps<{ tenant: TenantRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const tenantId = computed(() => String(props.tenant.id))
const tenantLabel = computed(() =>
  [props.tenant.defName || '当前租户', props.tenant.region].filter(Boolean).join(' · '),
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

const actionLabels: Record<MysqlAction, string> = {
  syncAll: '正在从云端同步…',
  syncOne: '正在更新实例信息…',
  create: '正在提交创建请求…',
  reset: '正在重置认证…',
  bind: '正在绑定公网 IP…',
  delete: '正在提交删除请求…',
}
const busyText = computed(() => busy.value ? actionLabels[busy.value] : '')

function close() {
  if (!busy.value) emit('close')
}

function nameOf(row: MysqlInstance) {
  return row.displayName || '未命名实例'
}

function statusOf(row: MysqlInstance) {
  const value = String(row.dbStatus || '').toUpperCase()
  const labels: Record<string, string> = {
    ACTIVE: '运行中', CREATING: '创建中', UPDATING: '更新中',
    INACTIVE: '已停止', DELETING: '删除中', DELETED: '已删除', FAILED: '失败',
  }
  return labels[value] || row.dbStatus || '未知'
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
    if (!Array.isArray(result.data)) throw new Error('未能读取 MySQL 实例列表，请刷新重试')
    rows.value = result.data.map(row => {
      if (!row || row.id == null || (typeof row.id === 'number' && !Number.isSafeInteger(row.id))) {
        throw new Error('实例标识不完整，请刷新后重试')
      }
      return { ...row, id: String(row.id) }
    })
    revealedPasswords.value = new Set()
  } catch (error) {
    if (current === generation && version === readVersion && !controller.signal.aborted) {
      readError.value = tenantError(error)
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
    ElMessage.success(`${label}已复制`)
  } catch {
    ElMessage.warning('复制失败，请选中文本手动复制')
  }
}

function copyOcid(row: MysqlInstance) { void copy(row.dbId, 'OCID') }
function copyPassword(row: MysqlInstance) { void copy(row.dbPassword, '密码') }
function copyUsername(row: MysqlInstance) { void copy(row.dbName, '用户名') }
function copyEndpoint(row: MysqlInstance) {
  if (row.dbPublicUrl) void copy(`${row.dbPublicUrl}:${row.dbPort ?? 3306}`, '连接地址')
}

function confirmationFor(action: MysqlAction, row?: MysqlInstance) {
  const name = row ? nameOf(row) : '当前租户'
  if (action === 'create') {
    return {
      title: '创建 MySQL 实例',
      message: '为当前租户创建 MySQL Free Tier 实例？系统会自动生成管理员账号和密码，创建通常需要 15–20 分钟。',
    }
  }
  if (action === 'reset') {
    return { title: '重置认证', message: `重置“${name}”的管理员密码？系统将生成随机新密码，原密码会立即失效。` }
  }
  if (action === 'bind') {
    return { title: '绑定公网 IP', message: `为“${name}”绑定公网 IP？数据库将通过公网负载均衡器提供访问。` }
  }
  if (action === 'delete') {
    return { title: '删除 MySQL 实例', message: `永久删除“${name}”？数据库实例及关联的公网负载均衡器将被删除，此操作无法撤销。` }
  }
  return null
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
          type: 'warning',
          confirmButtonText: action === 'delete' ? '确认删除' : '确认',
          cancelButtonText: '取消',
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
    if (action === 'create') {
      notice.value = result.message && result.message !== 'success'
        ? result.message
        : '创建请求已提交，请稍后同步查看实例状态。'
    } else {
      const message = result.message && result.message !== 'success'
        ? result.message
        : action === 'delete' ? '删除请求已处理，请以列表状态为准' : '操作已完成'
      ElMessage.success(message)
    }
    emit('changed')
    await loadMysql()
  } catch (error) {
    if (current === generation) {
      const code = (error as { code?: string })?.code
      actionError.value = code === 'ECONNABORTED' || code === 'ETIMEDOUT'
        ? '请求等待超时，云端可能仍在处理。请先刷新或同步实例状态，再决定是否重试。'
        : tenantError(error)
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
</script>

<template>
  <el-dialog
    :model-value="true"
    title="MySQL 管理"
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
          <el-button :disabled="!!busy || loading" @click="refresh">刷新</el-button>
          <el-button :loading="busy === 'syncAll'" :disabled="!!busy && busy !== 'syncAll'" @click="syncAll">从云端同步</el-button>
          <el-button type="primary" :loading="busy === 'create'" :disabled="!!busy && busy !== 'create'" @click="createMysql">创建实例</el-button>
        </div>
      </div>

      <el-alert v-if="readError" :title="readError" type="error" :closable="false" show-icon>
        <el-button text :disabled="!!busy" @click="refresh">重新加载</el-button>
      </el-alert>
      <el-alert v-if="actionError" :title="actionError" type="error" :closable="false" show-icon />
      <el-alert v-if="notice" :title="notice" type="success" :closable="false" show-icon />

      <el-table
        v-loading="loading"
        :data="rows"
        row-key="id"
        class="mysql-table"
        max-height="min(56vh, 560px)"
        empty-text="暂无 MySQL 实例"
      >
        <el-table-column label="实例" min-width="170">
          <template #default="{ row }">
            <button class="copy-name" :disabled="!row.dbId" :title="row.dbId ? '复制 OCID' : undefined" @click="copyOcid(row)">
              {{ nameOf(row) }}
            </button>
            <div class="cell-secondary">{{ row.dbVersion || '版本未知' }}</div>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="104">
          <template #default="{ row }">
            <span class="mysql-status" :class="statusClass(row)">{{ statusOf(row) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="公网连接" min-width="188">
          <template #default="{ row }">
            <button v-if="row.dbPublicUrl" class="copy-endpoint" title="复制连接地址" @click="copyEndpoint(row)">{{ row.dbPublicUrl }}</button>
            <span v-else class="cell-secondary">未绑定</span>
            <div class="cell-secondary">端口 {{ row.dbPort ?? 3306 }}</div>
          </template>
        </el-table-column>
        <el-table-column label="登录凭据" min-width="268">
          <template #default="{ row }">
            <button v-if="row.dbName" class="copy-username" title="复制用户名" @click="copyUsername(row)">{{ row.dbName }}</button>
            <span v-else class="cell-secondary">未获取用户名</span>
            <div class="secret-row">
              <code class="secret-value">{{ row.dbPassword ? (revealedPasswords.has(row.id) ? row.dbPassword : '••••••••') : '未获取密码' }}</code>
              <button
                class="icon-button"
                :disabled="!row.dbPassword"
                :aria-label="`${revealedPasswords.has(row.id) ? '隐藏' : '显示'} ${nameOf(row)} 密码`"
                :aria-pressed="revealedPasswords.has(row.id)"
                :title="revealedPasswords.has(row.id) ? '隐藏密码' : '显示密码'"
                @click="togglePassword(row)"
              >
                <span :class="revealedPasswords.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />
              </button>
              <button class="icon-button" :disabled="!row.dbPassword" :aria-label="`复制 ${nameOf(row)} 密码`" title="复制密码" @click="copyPassword(row)">
                <span class="i-mdi-content-copy" aria-hidden="true" />
              </button>
            </div>
          </template>
        </el-table-column>
        <el-table-column prop="shapeName" label="规格" min-width="150" show-overflow-tooltip />
        <el-table-column label="存储" width="88">
          <template #default="{ row }">{{ row.dataStorageSizeInGBs == null ? '—' : `${row.dataStorageSizeInGBs} GB` }}</template>
        </el-table-column>
        <el-table-column label="操作" width="72" fixed="right">
          <template #default="{ row }">
            <el-dropdown trigger="click" :disabled="!!busy" @command="handleCommand($event, row)">
              <el-button text :disabled="!!busy" :loading="!!busy && busyRowId === row.id" :aria-label="`${nameOf(row)} 的操作`" title="实例操作">
                <span class="i-mdi-dots-horizontal" aria-hidden="true" />
              </el-button>
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item command="syncOne">更新实例信息</el-dropdown-item>
                  <el-dropdown-item command="reset">重置认证</el-dropdown-item>
                  <el-dropdown-item command="bind">绑定公网 IP</el-dropdown-item>
                  <el-dropdown-item command="delete" divided class="mysql-delete-action">删除实例</el-dropdown-item>
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
:global(.tenant-region-mysql-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); }
.mysql-content :deep(.el-button), .mysql-content :deep(.el-input__inner), .mysql-content :deep(.el-select__wrapper), .mysql-content :deep(.el-form-item__label), .mysql-content :deep(.el-table) { font-size: var(--font-size-body); }
.mysql-content :deep(.el-alert__title) { font-size: var(--font-size-body); }
.mysql-content :deep(.el-alert__description), .mysql-content :deep(.el-form-item__error), .mysql-content :deep(.el-empty__description p) { font-size: var(--font-size-secondary); }
.mysql-toolbar { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 16px; }
.tenant-label { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.toolbar-actions { display: flex; flex-shrink: 0; align-items: center; gap: 8px; }
.toolbar-actions :deep(.el-button + .el-button) { margin-left: 0; }
.mysql-content :deep(.el-alert) { margin-bottom: 14px; border-radius: var(--r-sm); }
.mysql-table { border: 1px solid var(--border); border-radius: var(--r-sm); }
.mysql-table :deep(th.el-table__cell) { padding-block: 8px; background: var(--bg-hover); color: var(--text-secondary); font-size: var(--font-size-body); font-weight: 500; }
.mysql-table :deep(td.el-table__cell) { padding-block: 10px; }
.cell-secondary { margin-top: 3px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.copy-name, .copy-endpoint, .copy-username, .icon-button { border: 0; background: transparent; color: var(--text-primary); font: inherit; cursor: pointer; }
.copy-name, .copy-endpoint, .copy-username { display: block; max-width: 100%; padding: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; text-align: left; }
.copy-name { font-weight: 500; }
.copy-endpoint, .copy-username { font-family: var(--mono); font-size: var(--font-size-body); }
.copy-name:hover, .copy-endpoint:hover, .copy-username:hover { color: var(--brand); }
.copy-name:disabled { cursor: default; color: var(--text-primary); }
.mysql-status { display: inline-flex; align-items: center; gap: 6px; color: var(--text-secondary); font-size: var(--font-size-body); white-space: nowrap; }
.mysql-status::before { content: ''; width: 5px; height: 5px; border-radius: 50%; background: currentColor; }
.mysql-status.is-active { color: var(--status-ok); }
.mysql-status.is-failed { color: var(--status-danger); }
.secret-row { display: flex; align-items: center; gap: 4px; min-width: 0; margin-top: 3px; }
.secret-value { max-width: 178px; overflow: auto; color: var(--text-secondary); font-family: var(--mono); font-size: var(--font-size-secondary); white-space: nowrap; scrollbar-width: thin; }
.icon-button { display: inline-flex; flex-shrink: 0; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: var(--r-sm); color: var(--text-secondary); }
.icon-button > span { width: 15px; height: 15px; }
.icon-button:hover:not(:disabled) { background: var(--bg-hover); color: var(--brand); }
.icon-button:disabled { cursor: default; opacity: .4; }
.mysql-delete-action { color: var(--status-danger); }
.busy-status { margin: 12px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
@media (max-width: 640px) {
  .mysql-toolbar { flex-wrap: wrap; }
  .tenant-label { flex-basis: 100%; }
  .toolbar-actions { flex-wrap: wrap; gap: 6px; }
}
</style>
