<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import request from '@/api/request'
import {
  tenantCsrfToken,
  tenantError,
  tenantGet,
  tenantPost,
  tenantPut,
  type TenantRow,
} from '@/api/tenant'

interface SecurityRule {
  type?: string
  protocol: string | number
  source?: string
  ports?: string | null
  icmpType?: string
}
type Direction = 'ingress' | 'egress'

const props = defineProps<{ tenant: TenantRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const direction = ref<Direction>('ingress')
const rules = ref<SecurityRule[]>([])
const page = ref(1)
const pageSize = ref(5)
const loading = ref(false)
const busy = ref(false)
const error = ref('')
const editor = ref(false)
const editIndex = ref<number | null>(null)
const form = reactive({ protocol: 'tcp', source: '', ports: '' })
const formError = ref('')
let readController: AbortController | undefined
let readVersion = 0
let disposed = false

const needsPorts = computed(() => form.protocol === 'tcp' || form.protocol === 'udp')
const addressLabel = computed(() => direction.value === 'ingress' ? '来源 CIDR' : '目标 CIDR')
const pageRules = computed(() => {
  const offset = (page.value - 1) * pageSize.value
  // Mutation IDs use the index in the complete response, never the page index.
  return rules.value.slice(offset, offset + pageSize.value).map((rule, index) => ({
    ...rule,
    ruleIndex: offset + index,
  }))
})

function messageFor(cause: unknown) {
  const response = (cause as { response?: { data?: unknown } })?.response?.data
  return typeof response === 'string' && response.trim() ? response : tenantError(cause)
}

function protocolValue(protocol: SecurityRule['protocol']) {
  return ({ '6': 'tcp', '17': 'udp', '1': 'icmp' } as Record<string, string>)[String(protocol)] || String(protocol).toLowerCase()
}

function protocolLabel(protocol: SecurityRule['protocol']) {
  const value = protocolValue(protocol)
  return value === 'all' ? '所有协议' : value.toUpperCase()
}

function portsLabel(rule: SecurityRule) {
  const value = protocolValue(rule.protocol)
  if (value === 'icmp') return rule.icmpType ? `ICMP ${rule.icmpType}` : '—'
  if (value === 'all') return '全部'
  return !rule.ports || ['null', 'N/A'].includes(rule.ports) ? '—' : rule.ports
}

function clearEditor() {
  editor.value = false
  editIndex.value = null
  formError.value = ''
  Object.assign(form, { protocol: 'tcp', source: '', ports: '' })
}

async function loadRules() {
  if (disposed) return
  readController?.abort()
  const version = ++readVersion
  const controller = new AbortController()
  readController = controller
  loading.value = true
  error.value = ''
  try {
    const result = await tenantGet<SecurityRule[]>(
      '/tenants/security-rules',
      { tenantId: props.tenant.id, type: direction.value },
      { signal: controller.signal },
    )
    if (disposed || version !== readVersion) return
    if (!Array.isArray(result)) throw new Error('安全规则返回格式异常，请刷新重试')
    rules.value = result
    page.value = Math.min(page.value, Math.max(1, Math.ceil(result.length / pageSize.value)))
  } catch (cause) {
    if (disposed || version !== readVersion || controller.signal.aborted) return
    rules.value = []
    error.value = messageFor(cause)
  } finally {
    if (!disposed && version === readVersion) loading.value = false
  }
}

async function confirmDiscard() {
  if (!editor.value) return true
  try {
    await ElMessageBox.confirm('尚未保存的规则修改将被舍弃。', '放弃修改？', {
      confirmButtonText: '放弃修改',
      cancelButtonText: '继续编辑',
      type: 'warning',
      closeOnClickModal: false,
    })
    return !disposed
  } catch {
    return false
  }
}

async function changeDirection(value: Direction) {
  if (busy.value || direction.value === value) return
  busy.value = true
  const discard = await confirmDiscard()
  busy.value = false
  if (!discard || disposed) return
  clearEditor()
  rules.value = []
  page.value = 1
  direction.value = value
  void loadRules()
}

function addRule() {
  if (busy.value || loading.value || editor.value || error.value) return
  clearEditor()
  editor.value = true
}

function editRule(rule: SecurityRule & { ruleIndex: number }) {
  if (busy.value || loading.value || editor.value) return
  form.protocol = protocolValue(rule.protocol)
  form.source = rule.source || ''
  form.ports = rule.ports && !['null', 'N/A'].includes(rule.ports) ? rule.ports : ''
  editIndex.value = rule.ruleIndex
  formError.value = ''
  editor.value = true
}

async function cancelEdit() {
  if (busy.value) return
  busy.value = true
  const discard = await confirmDiscard()
  busy.value = false
  if (discard) clearEditor()
}

function validateForm() {
  if (!form.source.trim()) return `请填写${addressLabel.value}`
  if (!needsPorts.value) return ''
  const match = form.ports.trim().match(/^(\d{1,5})(?:\s*-\s*(\d{1,5}))?$/)
  if (!match) return '填写一个端口或连续范围，例如 443 或 8000-8080；不连续端口请分别添加规则。'
  const min = Number(match[1])
  const max = Number(match[2] || match[1])
  return min < 0 || max > 65535 || min > max ? '端口须在 0–65535 之间，范围起点不能大于终点。' : ''
}

async function saveRule() {
  if (busy.value || loading.value || !editor.value) return
  formError.value = validateForm()
  if (formError.value) return
  busy.value = true
  const wasEditing = editIndex.value !== null
  const payload = {
    tenantId: props.tenant.id,
    type: direction.value,
    protocol: form.protocol,
    source: form.source.trim(),
    ports: needsPorts.value ? form.ports.replace(/\s/g, '') : '',
  }
  try {
    if (wasEditing) {
      // Keep the legacy edit contract; do not replace it with a destructive delete/add.
      await tenantPut(`/tenants/security-rules/${props.tenant.id}_${editIndex.value}_${direction.value}`, payload)
    } else {
      await tenantPost('/tenants/security-rules', payload)
    }
    if (disposed) return
    clearEditor()
    ElMessage.success(wasEditing ? '安全规则已保存' : '安全规则已添加')
    emit('changed')
    await loadRules()
  } catch (cause) {
    if (disposed) return
    const status = (cause as { response?: { status?: number } })?.response?.status
    formError.value = wasEditing && (status === 404 || status === 405)
      ? '当前服务暂不支持编辑安全规则，修改尚未保存。'
      : messageFor(cause)
  } finally {
    if (!disposed) busy.value = false
  }
}

async function deleteRule(rule: SecurityRule & { ruleIndex: number }) {
  if (busy.value || loading.value || editor.value) return
  busy.value = true
  const id = `${props.tenant.id}_${rule.ruleIndex}_${direction.value}`
  try {
    await ElMessageBox.confirm(
      `删除 ${protocolLabel(rule.protocol)} · ${rule.source || '当前地址'} 的${direction.value === 'ingress' ? '入站' : '出站'}规则？依赖此规则的网络连接可能中断。`,
      '删除安全规则',
      { confirmButtonText: '删除', cancelButtonText: '取消', type: 'warning', closeOnClickModal: false },
    )
  } catch {
    busy.value = false
    return
  }
  if (disposed) return
  try {
    const csrfHeader = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
    await request.delete(`/tenants/security-rules/${id}`, {
      silent: true,
      timeout: 30000,
      headers: { [csrfHeader]: tenantCsrfToken() },
    })
    if (disposed) return
    ElMessage.success('安全规则已删除')
    emit('changed')
    await loadRules()
  } catch (cause) {
    if (!disposed) ElMessage.error(messageFor(cause))
  } finally {
    if (!disposed) busy.value = false
  }
}

async function beforeClose(done: () => void) {
  if (busy.value) return
  busy.value = true
  const discard = await confirmDiscard()
  busy.value = false
  if (discard) done()
}

function close() {
  disposed = true
  readVersion++
  readController?.abort()
  emit('close')
}

watch(() => props.tenant.id, () => {
  readController?.abort()
  clearEditor()
  rules.value = []
  direction.value = 'ingress'
  page.value = 1
  void loadRules()
}, { immediate: true })

watch(pageSize, () => { page.value = 1 })
watch(needsPorts, (enabled) => {
  if (!enabled) form.ports = ''
})

onBeforeUnmount(() => {
  disposed = true
  readVersion++
  readController?.abort()
})
</script>

<template>
  <el-dialog
    :model-value="true"
    title="安全规则"
    width="min(860px, calc(100vw - 32px))"
    align-center
    class="region-security-dialog"
    :close-on-click-modal="false"
    :close-on-press-escape="!busy"
    :show-close="!busy"
    :before-close="beforeClose"
    @close="close"
  >
    <div class="security-content">
      <div class="security-toolbar">
        <div class="security-direction" role="group" aria-label="规则方向">
          <button type="button" :class="{ active: direction === 'ingress' }" :aria-pressed="direction === 'ingress'" :disabled="busy" @click="changeDirection('ingress')">入站规则</button>
          <button type="button" :class="{ active: direction === 'egress' }" :aria-pressed="direction === 'egress'" :disabled="busy" @click="changeDirection('egress')">出站规则</button>
        </div>
        <div class="security-actions">
          <GhostBtn :loading="loading" :disabled="busy || editor" @click="loadRules">刷新</GhostBtn>
          <PrimaryBtn v-if="!editor" :disabled="busy || loading || !!error" @click="addRule"><i class="i-mdi-plus" aria-hidden="true" />添加规则</PrimaryBtn>
        </div>
      </div>

      <form v-if="editor" class="security-editor" @submit.prevent="saveRule">
        <div class="security-fields">
          <label>
            <span>协议</span>
            <el-select v-model="form.protocol" :disabled="busy" aria-label="协议">
              <el-option label="TCP" value="tcp" />
              <el-option label="UDP" value="udp" />
              <el-option label="ICMP" value="icmp" />
              <el-option label="所有协议" value="all" />
              <el-option v-if="!['tcp', 'udp', 'icmp', 'all'].includes(form.protocol)" :label="protocolLabel(form.protocol)" :value="form.protocol" />
            </el-select>
          </label>
          <label>
            <span>{{ addressLabel }}</span>
            <el-input v-model="form.source" :disabled="busy" :aria-label="addressLabel" placeholder="0.0.0.0/0" autocomplete="off" />
          </label>
          <label>
            <span>端口范围</span>
            <el-input v-model="form.ports" :disabled="busy || !needsPorts" aria-label="端口范围" :placeholder="needsPorts ? '443 或 8000-8080' : '无需填写端口'" autocomplete="off" />
          </label>
        </div>
        <p v-if="formError" class="security-error" role="alert">{{ formError }}</p>
        <div class="security-editor-actions">
          <GhostBtn :disabled="busy" @click="cancelEdit">取消</GhostBtn>
          <PrimaryBtn :loading="busy" @click="saveRule">{{ editIndex === null ? '添加' : '保存' }}</PrimaryBtn>
        </div>
      </form>

      <div v-if="error" class="security-error-panel" role="alert">
        <p>{{ error }}</p>
        <GhostBtn :loading="loading" @click="loadRules">重新加载</GhostBtn>
      </div>
      <el-table v-else v-loading="loading" :data="pageRules" row-key="ruleIndex" class="security-table" max-height="min(440px, 52vh)" empty-text="暂无安全规则">
        <el-table-column label="#" width="54"><template #default="{ row }">{{ row.ruleIndex + 1 }}</template></el-table-column>
        <el-table-column label="协议" min-width="100"><template #default="{ row }">{{ protocolLabel(row.protocol) }}</template></el-table-column>
        <el-table-column prop="source" :label="addressLabel" min-width="180" show-overflow-tooltip />
        <el-table-column label="端口 / ICMP" min-width="130"><template #default="{ row }">{{ portsLabel(row) }}</template></el-table-column>
        <el-table-column label="操作" width="112" fixed="right">
          <template #default="{ row }">
            <el-button link :disabled="busy || loading || editor" @click="editRule(row)">编辑</el-button>
            <el-button link type="danger" :disabled="busy || loading || editor" @click="deleteRule(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>

      <div v-if="!error" class="security-pagination">
        <span>{{ rules.length }} 条规则</span>
        <el-pagination v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[5, 10, 20]" :total="rules.length" :disabled="busy || loading" layout="sizes, prev, pager, next" small />
      </div>
    </div>
  </el-dialog>
</template>

<style scoped>
.security-content { min-width: 0; font-size: var(--font-size-body); }
:global(.region-security-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); }
.security-content :deep(.el-button), .security-content :deep(.el-input__inner), .security-content :deep(.el-select__wrapper), .security-content :deep(.el-checkbox__label) { font-size: var(--font-size-body); }
.security-content :deep(.el-pagination) { --el-pagination-font-size: var(--font-size-body); --el-pagination-font-size-small: var(--font-size-body); }
.security-content :deep(.el-pagination .el-pager li) { font-size: var(--font-size-body); }
.security-content :deep(.el-pagination__total), .security-content :deep(.el-pagination__jump), .security-content :deep(.el-empty__description p) { font-size: var(--font-size-secondary); }
.security-toolbar, .security-actions, .security-editor-actions, .security-pagination { display: flex; align-items: center; gap: 8px; }
.security-toolbar { justify-content: space-between; gap: 12px; margin-bottom: 14px; }
.security-direction { display: inline-flex; padding: 3px; border-radius: var(--r-pill); background: var(--bg-hover); }
.security-direction button { padding: 7px 13px; border: 0; border-radius: var(--r-pill); background: transparent; color: var(--text-secondary); font: inherit; font-size: var(--font-size-body); cursor: pointer; transition: background-color 180ms ease, color 180ms ease; white-space: nowrap; }
.security-direction button.active { background: var(--bg-card); color: var(--text-primary); box-shadow: var(--shadow-card); }
.security-direction button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
.security-direction button:disabled { cursor: default; opacity: .6; }
.security-actions :deep(.btn), .security-editor-actions :deep(.btn) { min-height: 34px; padding: 7px 13px; font-size: var(--font-size-body); }
.security-editor { margin-bottom: 14px; padding: 14px; border: 1px solid var(--border); border-radius: var(--r-sm); }
.security-fields { display: grid; grid-template-columns: 140px minmax(0, 1fr) minmax(0, 1fr); gap: 12px; }
.security-fields label { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.security-fields label > span { font-size: var(--font-size-body); color: var(--text-secondary); }
.security-editor-actions { justify-content: flex-end; margin-top: 12px; }
.security-error { color: var(--status-danger); font-size: var(--font-size-secondary); margin: 10px 0 0; overflow-wrap: anywhere; }
.security-error-panel { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 28px 16px; color: var(--status-danger); font-size: var(--font-size-secondary); text-align: center; overflow-wrap: anywhere; }
.security-error-panel p { margin: 0; }
.security-table { font-family: var(--sans); font-size: var(--font-size-body); }
.security-table :deep(th.el-table__cell) { background: var(--bg-card); color: var(--text-secondary); font-size: var(--font-size-body); font-weight: 500; padding-block: 7px; }
.security-table :deep(td.el-table__cell) { padding-block: 9px; }
.security-table :deep(.el-button) { font-size: var(--font-size-body); }
.security-pagination { justify-content: space-between; padding-top: 12px; }
.security-pagination > span { color: var(--text-secondary); font-size: var(--font-size-secondary); white-space: nowrap; }
@media (max-width: 620px) {
  .security-toolbar { flex-wrap: wrap; }
  .security-actions { margin-left: auto; }
  .security-fields { grid-template-columns: minmax(0, 1fr); }
  .security-pagination { flex-wrap: wrap; }
  .security-pagination :deep(.el-pagination) { max-width: 100%; gap: 3px; flex-wrap: wrap; }
  .security-pagination :deep(.el-pagination__sizes) { margin-right: 4px; }
}
@media (prefers-reduced-motion: reduce) {
  .security-direction button { transition: none; }
}
</style>
