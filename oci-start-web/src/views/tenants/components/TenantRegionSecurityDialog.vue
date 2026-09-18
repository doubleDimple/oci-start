<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
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
  id?: string
  type?: string
  protocol: string | number
  source?: string
  ports?: string | null
  icmpType?: string
}
type Direction = 'ingress' | 'egress'

const props = defineProps<{ tenant: TenantRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const { t, n } = useI18n()
const compact = useCompactViewport()
const route = useRoute()
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
const addressLabel = computed(() => t(`tenantSecurity.${direction.value === 'ingress' ? 'source' : 'destination'}`))
function renderError(value: string) { return value.startsWith('tenantSecurity.') ? t(value, { field: addressLabel.value }) : value }
const pageRules = computed(() => {
  const offset = (page.value - 1) * pageSize.value
  // Mutation IDs use the index in the complete response, never the page index.
  return rules.value.slice(offset, offset + pageSize.value).map((rule, index) => ({
    ...rule,
    ruleIndex: offset + index,
  }))
})
const mobileListId = computed(() => `region-security-${props.tenant.id}-${direction.value}`)
const mobileRules = computed(() => typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith(`${mobileListId.value}:`) ? rules.value.map((rule, ruleIndex) => ({ ...rule, ruleIndex })) : pageRules.value)

function messageFor(cause: unknown) {
  const response = (cause as { response?: { data?: unknown } })?.response?.data
  return typeof response === 'string' && response.trim() ? response : tenantError(cause)
}

function protocolValue(protocol: SecurityRule['protocol']) {
  return ({ '6': 'tcp', '17': 'udp', '1': 'icmp' } as Record<string, string>)[String(protocol)] || String(protocol).toLowerCase()
}

function protocolLabel(protocol: SecurityRule['protocol']) {
  const value = protocolValue(protocol)
  return value === 'all' ? t('tenantSecurity.allProtocols') : value === '58' ? 'ICMPv6' : value.toUpperCase()
}

function portsLabel(rule: SecurityRule) {
  const value = protocolValue(rule.protocol)
  if (value === 'icmp' || value === '58') return rule.icmpType ? `${protocolLabel(value)} ${rule.icmpType}` : '—'
  if (value === 'all') return t('tenantSecurity.allPorts')
  if (value === 'tcp' || value === 'udp') return !rule.ports || ['null', 'N/A'].includes(rule.ports) ? t('tenantSecurity.allPorts') : rule.ports
  return rule.ports || '—'
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
    if (!Array.isArray(result)) throw new Error('tenantSecurity.invalidResponse')
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
    await ElMessageBox.confirm(t('tenantSecurity.discardMessage'), t('tenantSecurity.discardTitle'), {
      customClass: 'tenant-region-security-confirm',
      confirmButtonText: t('tenantSecurity.discard'),
      cancelButtonText: t('tenantSecurity.keepEditing'),
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
  if (!form.source.trim()) return 'tenantSecurity.sourceRequired'
  if (!needsPorts.value || !form.ports.trim()) return ''
  const match = form.ports.trim().match(/^(\d{1,5})(?:\s*-\s*(\d{1,5}))?$/)
  if (!match) return 'tenantSecurity.portFormat'
  const min = Number(match[1])
  const max = Number(match[2] || match[1])
  return min < 0 || max > 65535 || min > max ? 'tenantSecurity.portRange' : ''
}

async function saveRule() {
  if (busy.value || loading.value || !editor.value) return
  formError.value = validateForm()
  if (formError.value) return
  busy.value = true
  const wasEditing = editIndex.value !== null
  const payload = {
    id: wasEditing ? rules.value[editIndex.value!]?.id : undefined,
    tenantId: props.tenant.id,
    type: direction.value,
    protocol: form.protocol,
    source: form.source.trim(),
    ports: needsPorts.value ? form.ports.replace(/\s/g, '') : '',
  }
  try {
    if (wasEditing) {
      // Keep the legacy edit contract; do not replace it with a destructive delete/add.
      await tenantPut(`/tenants/security-rules/${props.tenant.id}_${editIndex.value}_${direction.value}`, payload, { timeout: 0 })
    } else {
      await tenantPost('/tenants/security-rules', payload)
    }
    if (disposed) return
    clearEditor()
    ElMessage.success(wasEditing ? t('tenantSecurity.saved') : t('tenantSecurity.added'))
    emit('changed')
    await loadRules()
  } catch (cause) {
    if (disposed) return
    const status = (cause as { response?: { status?: number } })?.response?.status
    formError.value = wasEditing && (status === 404 || status === 405)
      ? 'tenantSecurity.unsupported'
      : status === 409 ? 'tenantSecurity.conflict' : messageFor(cause)
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
      t('tenantSecurity.deleteMessage', { protocol: protocolLabel(rule.protocol), address: rule.source || t('tenantSecurity.currentAddress'), direction: t(`tenantSecurity.${direction.value}`) }),
      t('tenantSecurity.deleteTitle'),
      { customClass: 'tenant-region-security-confirm', confirmButtonText: t('tenantSecurity.delete'), cancelButtonText: t('tenantSecurity.cancel'), type: 'warning', closeOnClickModal: false },
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
    ElMessage.success(t('tenantSecurity.deleted'))
    emit('changed')
    await loadRules()
  } catch (cause) {
    if (!disposed) ElMessage.error(renderError(messageFor(cause)))
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
  direction.value = compact.value && typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith(`region-security-${props.tenant.id}-egress:`) ? 'egress' : 'ingress'
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

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<SecurityRule & { ruleIndex: number }>
</script>

<template>
  <el-dialog
    :model-value="true"
    :title="t('tenantSecurity.title')"
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
        <div class="security-direction" role="group" :aria-label="t('tenantSecurity.direction')">
          <button type="button" :class="{ active: direction === 'ingress' }" :aria-pressed="direction === 'ingress'" :disabled="busy" @click="changeDirection('ingress')">{{ t('tenantSecurity.ingress') }}</button>
          <button type="button" :class="{ active: direction === 'egress' }" :aria-pressed="direction === 'egress'" :disabled="busy" @click="changeDirection('egress')">{{ t('tenantSecurity.egress') }}</button>
        </div>
        <div class="security-actions">
          <GhostBtn :loading="loading" :disabled="busy || editor" @click="loadRules">{{ t('tenantSecurity.refresh') }}</GhostBtn>
          <PrimaryBtn v-if="!editor" :disabled="busy || loading || !!error" @click="addRule"><i class="i-mdi-plus" aria-hidden="true" />{{ t('tenantSecurity.addRule') }}</PrimaryBtn>
        </div>
      </div>

      <form v-if="editor" class="security-editor" @submit.prevent="saveRule">
        <div class="security-fields">
          <label>
            <span>{{ t('tenantSecurity.protocol') }}</span>
            <el-select v-model="form.protocol" popper-class="tenant-region-security-select" :disabled="busy" :aria-label="t('tenantSecurity.protocol')">
              <el-option label="TCP" value="tcp" />
              <el-option label="UDP" value="udp" />
              <el-option label="ICMP" value="icmp" />
              <el-option :label="t('tenantSecurity.allProtocols')" value="all" />
              <el-option v-if="!['tcp', 'udp', 'icmp', 'all'].includes(form.protocol)" :label="protocolLabel(form.protocol)" :value="form.protocol" />
            </el-select>
          </label>
          <label>
            <span>{{ addressLabel }}</span>
            <el-input v-model="form.source" :disabled="busy" :aria-label="addressLabel" placeholder="0.0.0.0/0" autocomplete="off" />
          </label>
          <label>
            <span>{{ t('tenantSecurity.ports') }}</span>
            <el-input v-model="form.ports" :disabled="busy || !needsPorts" :aria-label="t('tenantSecurity.ports')" :placeholder="t(needsPorts ? 'tenantSecurity.portsPlaceholder' : 'tenantSecurity.noPorts')" autocomplete="off" />
          </label>
        </div>
        <p v-if="['tenantSecurity.sourceRequired', 'tenantSecurity.portFormat', 'tenantSecurity.portRange'].includes(formError)" class="security-error" role="alert">{{ renderError(formError) }}</p>
        <PageErrorNotice v-else-if="formError">{{ renderError(formError) }}</PageErrorNotice>
        <div class="security-editor-actions">
          <GhostBtn :disabled="busy" @click="cancelEdit">{{ t('tenantSecurity.cancel') }}</GhostBtn>
          <PrimaryBtn :loading="busy" @click="saveRule">{{ t(editIndex === null ? 'tenantSecurity.add' : 'tenantSecurity.save') }}</PrimaryBtn>
        </div>
      </form>

      <PageErrorNotice v-if="error">
        <p>{{ renderError(error) }}</p>
        <GhostBtn :loading="loading" @click="loadRules">{{ t('tenantSecurity.retry') }}</GhostBtn>
      </PageErrorNotice>
      <MobileRecordList v-else-if="compact" drilldown :list-id="mobileListId" :record-keys="rules.map((rule, index) => String(rule.id || index))" :loading="loading" class="security-mobile-list" :aria-busy="loading">
        <MobileRecordCard v-for="rule in mobileRules" :key="rule.ruleIndex" :record-key="String(rule.id || rule.ruleIndex)" :summary-title="protocolLabel(rule.protocol)" :summary-meta="rule.source || '—'" :summary-status="portsLabel(rule)">
          <template #identity><h3 class="mobile-record-title">{{ protocolLabel(rule.protocol) }} · {{ n(rule.ruleIndex + 1) }}</h3><span class="mobile-record-subtitle">{{ t(`tenantSecurity.${direction}`) }}</span></template>
          <dl class="mobile-record-fields">
            <div class="mobile-record-wide"><dt>{{ addressLabel }}</dt><dd>{{ rule.source || '—' }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('tenantSecurity.portsIcmp') }}</dt><dd>{{ portsLabel(rule) }}</dd></div>
          </dl>
          <template #footer>
            <GhostBtn :disabled="busy || loading || editor" @click="editRule(rule)">{{ t('tenantSecurity.edit') }}</GhostBtn>
            <GhostBtn danger :disabled="busy || loading || editor" @click="deleteRule(rule)">{{ t('tenantSecurity.delete') }}</GhostBtn>
          </template>
        </MobileRecordCard>
        <p v-if="loading || !pageRules.length" class="security-mobile-empty" role="status">{{ t(loading ? 'pageLoading.loading' : 'tenantSecurity.empty') }}</p>
      </MobileRecordList>
      <el-table v-else v-loading="loading" :data="pageRules" row-key="ruleIndex" class="security-table" max-height="min(440px, 52vh)" :empty-text="t('tenantSecurity.empty')">
        <el-table-column label="#" width="54"><template #default="{ row }">{{ n(row.ruleIndex + 1) }}</template></el-table-column>
        <el-table-column :label="t('tenantSecurity.protocol')" min-width="100"><template #default="{ row }">{{ protocolLabel(row.protocol) }}</template></el-table-column>
        <el-table-column prop="source" :label="addressLabel" min-width="180" show-overflow-tooltip />
        <el-table-column :label="t('tenantSecurity.portsIcmp')" min-width="130"><template #default="{ row }">{{ portsLabel(row) }}</template></el-table-column>
        <el-table-column :label="t('tenantSecurity.actions')" width="112" fixed="right">
          <template #default="{ row }">
            <el-button link :disabled="busy || loading || editor" @click="editRule(row)">{{ t('tenantSecurity.edit') }}</el-button>
            <el-button link type="danger" :disabled="busy || loading || editor" @click="deleteRule(row)">{{ t('tenantSecurity.delete') }}</el-button>
          </template>
        </el-table-column>
      </el-table>

      <PagePagination v-if="!error" embedded class="security-pagination" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[5, 10, 20]" :total="rules.length" :disabled="busy || loading">
        <span>{{ t('tenantSecurity.count', { count: n(rules.length) }) }}</span>
      </PagePagination>
    </div>
  </el-dialog>
</template>

<style scoped>
.security-content { min-width: 0; font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
:global(.region-security-dialog) { font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
:global(.region-security-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); font-weight: 600; color: var(--text-primary); }
:global(.tenant-region-security-confirm) { font-family: var(--sans); --el-messagebox-title-color: var(--text-primary); --el-messagebox-content-color: var(--text-primary); --el-messagebox-font-size: var(--font-size-dialog-title); --el-messagebox-content-font-size: var(--font-size-body); }
:global(.tenant-region-security-confirm .el-message-box__title) { font-weight: 600; }
:global(.tenant-region-security-select.el-popper) { font-family: var(--sans); font-size: var(--font-size-body); }
.security-content :deep(.el-button), .security-content :deep(.el-input__inner), .security-content :deep(.el-select__wrapper), .security-content :deep(.el-checkbox__label) { font-size: var(--font-size-body); }
.security-content :deep(.el-empty__description p) { font-size: var(--font-size-secondary); }
.security-toolbar, .security-actions, .security-editor-actions { display: flex; align-items: center; gap: 8px; }
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
.security-fields label > span { font-size: var(--font-size-body); color: var(--text-primary); }
.security-editor-actions { justify-content: flex-end; margin-top: 12px; }
.security-error { color: var(--status-danger); font-size: var(--font-size-secondary); margin: 10px 0 0; overflow-wrap: anywhere; }
.security-error-panel { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 28px 16px; color: var(--status-danger); font-size: var(--font-size-secondary); text-align: center; overflow-wrap: anywhere; }
.security-error-panel p { margin: 0; }
.security-table { font-family: var(--sans); font-size: var(--font-size-body); }
.security-table :deep(th.el-table__cell) { background: var(--bg-card); color: var(--text-secondary); font-size: var(--font-size-body); font-weight: 600; padding-block: 7px; }
.security-table :deep(td.el-table__cell) { padding-block: 9px; }
.security-table :deep(.el-button) { font-size: var(--font-size-body); }
.security-pagination { margin-top: 12px; }
@media (max-width: 760px) {
  :global(.region-security-dialog) { max-height: calc(100dvh - 32px); overflow-y: auto; }
  .security-mobile-list { padding: 0; max-height: 48dvh; overflow-y: auto; overscroll-behavior: contain; }
  .security-mobile-empty { display: grid; place-items: center; min-height: 88px; padding: 16px; margin: 0; text-align: center; line-height: 1.6; }
  .security-mobile-list :deep(.btn), .security-actions :deep(.btn), .security-editor-actions :deep(.btn) { min-height: 44px; }
  .security-direction { width: 100%; }
  .security-direction button { flex: 1; min-height: 42px; white-space: normal; }
  .security-toolbar { flex-wrap: wrap; }
  .security-actions { margin-left: auto; }
  .security-fields { grid-template-columns: minmax(0, 1fr); }
}
@media (prefers-reduced-motion: reduce) {
  .security-direction button { transition: none; }
}
</style>
