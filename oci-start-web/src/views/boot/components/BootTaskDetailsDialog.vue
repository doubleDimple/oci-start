<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { bootTaskError, getBootTaskDetails, type BootTaskAction, type BootTaskDetail, type BootTaskError, type BootTaskGroup } from '@/api/bootTasks'
import GhostBtn from '@/components/GhostBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import BootTaskActionDialog from './BootTaskActionDialog.vue'
import BootTaskLogDrawer from './BootTaskLogDrawer.vue'

const props = defineProps<{ group: BootTaskGroup }>()
const emit = defineEmits<{ close: []; changed: []; busy: [value: boolean] }>()
const { t, locale } = useI18n()
const compact = useCompactViewport()
const route = useRoute()
const rows = ref<BootTaskDetail[]>([])
const loading = ref(false)
const problem = ref<BootTaskError | null>(null)
const revealed = ref(new Set<string>())
const page = ref(1)
const pageSize = ref(20)
const operation = ref<{ action: BootTaskAction; target: BootTaskDetail } | null>(null)
const operationBusy = ref(false)
const logTask = ref<{ id: string; bootId: string } | null>(null)
let controller: AbortController | undefined
let generation = 0
let disposed = false
const pageRows = computed(() => rows.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
const mobileListId = computed(() => `boot-task-details-${props.group.id}-${props.group.architecture}`)
const mobileRows = computed(() => typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith(`${mobileListId.value}:`) ? rows.value : pageRows.value)
const error = computed(() => problem.value ? problem.value.detail || t(`bootTasks.errors.${problem.value.key}`) : '')
const hasOverlay = computed(() => operation.value !== null || !!logTask.value)
function number(value: string | number) { return new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US').format(typeof value === 'string' ? BigInt(value) : value) }
function date(value: string) {
  if (!value) return '—'
  const parsed = new Date(`${value.replace(' ', 'T')}Z`)
  return Number.isFinite(parsed.getTime()) ? new Intl.DateTimeFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', { dateStyle: 'medium', timeStyle: 'medium', timeZone: 'UTC' }).format(parsed) : value
}
function status(value: number) { return value === 0 ? t('bootTasks.statuses.stopped') : value === 1 ? t('bootTasks.statuses.running') : value === 2 ? t('bootTasks.statuses.completed') : t('bootTasks.statuses.unknown', { status: value }) }
function togglePassword(id: string) { const next = new Set(revealed.value); if (next.has(id)) next.delete(id); else next.add(id); revealed.value = next }
async function load() {
  controller?.abort()
  const active = new AbortController()
  controller = active
  const current = ++generation
  loading.value = true
  problem.value = null
  rows.value = []
  revealed.value = new Set()
  try {
    const result = await getBootTaskDetails(props.group, active.signal)
    if (disposed || active.signal.aborted || current !== generation) return
    rows.value = result
    page.value = Math.max(1, Math.min(page.value, Math.ceil(result.length / pageSize.value)))
  } catch (cause) { if (!disposed && !active.signal.aborted && current === generation) problem.value = bootTaskError(cause) }
  finally { if (!disposed && current === generation) loading.value = false }
}
function openAction(action: BootTaskAction, target: BootTaskDetail) { if (!loading.value && !hasOverlay.value) operation.value = { action, target } }
function changed() { emit('changed'); void load() }
function setBusy(value: boolean) { operationBusy.value = value; emit('busy', value) }
function close() { if (!operationBusy.value && !hasOverlay.value) emit('close') }
watch(pageSize, () => { page.value = 1; revealed.value = new Set() })
watch(page, () => { revealed.value = new Set() })
onMounted(load)
onBeforeUnmount(() => { disposed = true; generation++; controller?.abort(); rows.value = []; revealed.value = new Set(); logTask.value = null; operation.value = null })

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<BootTaskDetail>
</script>

<template>
  <el-dialog :model-value="true" :title="t('bootTasks.detailsTitle')" class="boot-task-details" width="min(1480px, calc(100vw - 28px))" append-to-body :close-on-click-modal="false" :close-on-press-escape="!hasOverlay" :show-close="!hasOverlay" @close="close">
    <div class="details-content">
      <div class="toolbar"><p>{{ t('bootTasks.target', { id: group.id, architecture: group.architecture }) }}</p><GhostBtn :loading="loading" :disabled="hasOverlay" @click="load">{{ t('bootTasks.refresh') }}</GhostBtn></div>
      <p class="note">{{ t('bootTasks.detailsHint') }}</p>
      <PageErrorNotice v-if="error" class="details-error-notice">{{ error }}</PageErrorNotice>
      <MobileRecordList v-if="compact" drilldown :list-id="mobileListId" :record-keys="rows.map(row => row.id)" :loading="loading" class="details-mobile-list">
        <MobileRecordCard v-for="row in mobileRows" :key="row.id" :record-key="row.id" :summary-title="[row.operatingSystem, row.operatingSystemVersion].filter(Boolean).join(' ') || row.id" :summary-meta="`${row.architecture} · ${row.id}`" :summary-status="status(row.status)" :summary-tone="row.status === 1 ? 'success' : row.status === 2 ? 'neutral' : 'warning'">
          <template #identity><h3 class="mobile-record-title">{{ [row.operatingSystem, row.operatingSystemVersion].filter(Boolean).join(' ') || '—' }}</h3></template>
          <dl class="mobile-record-fields">
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.index') }}</dt><dd>{{ row.id }}</dd></div>
            <div v-for="field in (['yesterdayAttemptCount', 'currentAttemptCount', 'failCount'] as const)" :key="field"><dt>{{ t(`bootTasks.columns.${field}`) }}</dt><dd>{{ number(row[field]) }}</dd></div>
            <div><dt>{{ t('bootTasks.columns.status') }}</dt><dd><el-tag :type="row.status === 1 ? 'success' : row.status === 2 ? 'info' : 'warning'">{{ status(row.status) }}</el-tag></dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.config') }}</dt><dd>{{ t('bootTasks.configValue', { ocpu: number(row.ocpu), memory: number(row.memory), disk: number(row.disk), architecture: row.architecture }) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.dayGap') }}</dt><dd>{{ row.dayGap || t('bootTasks.allDay') }}</dd></div>
            <div><dt>{{ t('bootTasks.columns.loopTime') }}</dt><dd>{{ t('bootTasks.seconds', { count: number(row.loopTime) }) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.password') }}</dt><dd class="secret"><span>{{ row.rootPassword ? revealed.has(row.id) ? row.rootPassword : '••••••••' : '—' }}</span><button v-if="row.rootPassword" class="icon-button" type="button" :aria-label="t(revealed.has(row.id) ? 'bootTasks.hidePassword' : 'bootTasks.showPassword')" :aria-pressed="revealed.has(row.id)" @click="togglePassword(row.id)"><i :class="revealed.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.createdAt') }}</dt><dd>{{ date(row.createdAt) }}</dd></div>
          </dl>
          <template #footer><div class="row-actions">
            <button type="button" :disabled="hasOverlay || loading || row.status !== 0" @click="openAction('detailStart', row)">{{ t('bootTasks.actions.detailStart') }}</button>
            <button type="button" :disabled="hasOverlay || loading || row.status !== 1" @click="openAction('detailStop', row)">{{ t('bootTasks.actions.detailStop') }}</button>
            <button type="button" :disabled="hasOverlay || loading" @click="logTask = { id: row.id, bootId: row.bootId }">{{ t('bootTasks.actions.logs') }}</button>
            <button type="button" :disabled="hasOverlay || loading" @click="openAction('edit', row)">{{ t('bootTasks.actions.edit') }}</button>
            <button type="button" class="danger" :disabled="hasOverlay || loading" @click="openAction('detailDelete', row)">{{ t('bootTasks.actions.detailDelete') }}</button>
          </div></template>
        </MobileRecordCard>
        <p v-if="loading || !rows.length" class="details-mobile-empty" role="status">{{ loading ? t('bootTasks.loading') : error || t('bootTasks.noDetails') }}</p>
      </MobileRecordList>
      <el-table v-else :data="pageRows" row-key="id" :empty-text="loading ? t('bootTasks.loading') : error || t('bootTasks.noDetails')" :aria-busy="loading" max-height="520">
        <el-table-column prop="id" :label="t('bootTasks.columns.index')" width="180" show-overflow-tooltip />
        <el-table-column v-for="field in (['yesterdayAttemptCount', 'currentAttemptCount', 'failCount'] as const)" :key="field" :label="t(`bootTasks.columns.${field}`)" min-width="115" show-overflow-tooltip><template #default="{ row }">{{ number(row[field]) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.system')" min-width="160" show-overflow-tooltip><template #default="{ row }">{{ [row.operatingSystem, row.operatingSystemVersion].filter(Boolean).join(' ') || '—' }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.config')" min-width="280" show-overflow-tooltip><template #default="{ row }">{{ t('bootTasks.configValue', { ocpu: number(row.ocpu), memory: number(row.memory), disk: number(row.disk), architecture: row.architecture }) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.dayGap')" min-width="140"><template #default="{ row }">{{ row.dayGap || t('bootTasks.allDay') }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.loopTime')" min-width="130"><template #default="{ row }">{{ t('bootTasks.seconds', { count: number(row.loopTime) }) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.password')" min-width="190"><template #default="{ row }"><div class="secret"><span>{{ row.rootPassword ? revealed.has(row.id) ? row.rootPassword : '••••••••' : '—' }}</span><button v-if="row.rootPassword" class="icon-button" type="button" :aria-label="t(revealed.has(row.id) ? 'bootTasks.hidePassword' : 'bootTasks.showPassword')" :aria-pressed="revealed.has(row.id)" @click="togglePassword(row.id)"><i :class="revealed.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></div></template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.status')" min-width="160"><template #default="{ row }"><el-tag :type="row.status === 1 ? 'success' : row.status === 2 ? 'info' : 'warning'">{{ status(row.status) }}</el-tag></template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.createdAt')" min-width="210" show-overflow-tooltip><template #default="{ row }">{{ date(row.createdAt) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.actions')" fixed="right" width="340"><template #default="{ row }"><div class="row-actions">
          <button type="button" :disabled="hasOverlay || loading || row.status !== 0" @click="openAction('detailStart', row)">{{ t('bootTasks.actions.detailStart') }}</button>
          <button type="button" :disabled="hasOverlay || loading || row.status !== 1" @click="openAction('detailStop', row)">{{ t('bootTasks.actions.detailStop') }}</button>
          <button type="button" :disabled="hasOverlay || loading" @click="logTask = { id: row.id, bootId: row.bootId }">{{ t('bootTasks.actions.logs') }}</button>
          <button type="button" :disabled="hasOverlay || loading" @click="openAction('edit', row)">{{ t('bootTasks.actions.edit') }}</button>
          <button type="button" class="danger" :disabled="hasOverlay || loading" @click="openAction('detailDelete', row)">{{ t('bootTasks.actions.detailDelete') }}</button>
        </div></template></el-table-column>
      </el-table>
      <PagePagination v-if="rows.length" embedded class="details-pagination" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50, 100]" :total="rows.length" :disabled="loading || hasOverlay"><span>{{ t('bootTasks.records', { count: number(rows.length) }) }}</span></PagePagination>
    </div>
    <template #footer><GhostBtn :disabled="hasOverlay" @click="close">{{ t('bootTasks.close') }}</GhostBtn></template>
  </el-dialog>
  <BootTaskActionDialog v-if="operation" :key="`${operation.action}:${operation.target.id}`" :action="operation.action" :target="operation.target" @close="operation = null" @changed="changed" @busy="setBusy" />
  <BootTaskLogDrawer v-if="logTask" :task-id="logTask.id" :scheduler-id="logTask.bootId" @close="logTask = null" />
</template>

<style scoped>
.details-content { color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); }
.toolbar { display: flex; justify-content: space-between; align-items: center; gap: 16px; flex-wrap: wrap; }
.toolbar p { margin: 0; overflow-wrap: anywhere; }.note { font-size: var(--font-size-secondary); color: var(--text-secondary); }
.details-error-notice { margin-bottom: 14px; }.details-content :deep(.el-table th.el-table__cell .cell) { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; }
.details-pagination { margin-top: 18px; }
.secret { display: flex; align-items: center; gap: 8px; }.secret span { overflow-wrap: anywhere; font-family: var(--sans); }
.icon-button, .row-actions button { color: var(--text-primary); background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--r-pill); font: var(--font-size-body)/1.4 var(--sans); cursor: pointer; padding: 6px 10px; }
.icon-button { display: inline-flex; padding: 6px; border: 0; }.icon-button i { width: 18px; height: 18px; }
.row-actions { display: flex; gap: 7px; flex-wrap: wrap; }.row-actions button { white-space: nowrap; }.row-actions button:hover, .icon-button:hover { background: var(--bg-hover); }.row-actions .danger { color: var(--status-danger); }
.row-actions button:disabled { opacity: .5; cursor: default; }.row-actions button:focus-visible, .icon-button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
@media (max-width: 760px) {
  :global(.boot-task-details) { max-height: calc(100dvh - 28px); overflow-y: auto; }
  .details-mobile-list { padding: 0; max-height: 55dvh; overflow-y: auto; overscroll-behavior: contain; }
  .details-mobile-empty { display: grid; place-items: center; min-height: 88px; margin: 0; color: var(--text-secondary); }
  .details-mobile-list .row-actions button { min-height: 44px; max-width: 100%; white-space: normal; overflow-wrap: anywhere; }
  .details-mobile-list .icon-button { min-width: 44px; min-height: 44px; flex-shrink: 0; align-items: center; justify-content: center; }
  .details-mobile-list .secret { min-width: 0; flex-wrap: wrap; }
}
</style>
