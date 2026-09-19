<script setup lang="ts">
import { ElTableColumn as BaseTableColumn, ElMessage } from 'element-plus'
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

function number(value: string | number) {
  return new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US').format(typeof value === 'string' ? BigInt(value) : value)
}
function date(value: string) {
  if (!value) return '—'
  const parsed = new Date(`${value.replace(' ', 'T')}Z`)
  return Number.isFinite(parsed.getTime()) ? new Intl.DateTimeFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', { dateStyle: 'medium', timeStyle: 'medium', timeZone: 'UTC' }).format(parsed) : value
}
function status(value: number) {
  return value === 0 ? t('bootTasks.statuses.stopped') : value === 1 ? t('bootTasks.statuses.running') : value === 2 ? t('bootTasks.statuses.completed') : t('bootTasks.statuses.unknown', { status: value })
}
function togglePassword(id: string) {
  const next = new Set(revealed.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  revealed.value = next
}
async function copyPassword(password: string) {
  if (!password) return
  try {
    await navigator.clipboard.writeText(password)
    ElMessage.success(t('bootTasks.copiedPassword'))
  } catch {
    ElMessage.error(t('bootTasks.copyFailed'))
  }
}
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
  } catch (cause) {
    if (!disposed && !active.signal.aborted && current === generation) problem.value = bootTaskError(cause)
  } finally {
    if (!disposed && current === generation) loading.value = false
  }
}
function openAction(action: BootTaskAction, target: BootTaskDetail) {
  if (!loading.value && !hasOverlay.value) operation.value = { action, target }
}
function changed() {
  emit('changed')
  void load()
}
function setBusy(value: boolean) {
  operationBusy.value = value
  emit('busy', value)
}
function close() {
  if (!operationBusy.value && !hasOverlay.value) emit('close')
}

watch(pageSize, () => {
  page.value = 1
  revealed.value = new Set()
})
watch(page, () => {
  revealed.value = new Set()
})
onMounted(load)
onBeforeUnmount(() => {
  disposed = true
  generation++
  controller?.abort()
  rows.value = []
  revealed.value = new Set()
  logTask.value = null
  operation.value = null
})

// Column slots cannot infer the parent table's row type.
const ElTableColumn = BaseTableColumn<BootTaskDetail>
</script>

<template>
  <el-dialog
    :model-value="true"
    class="boot-task-details-dialog"
    width="min(1200px, calc(100vw - 32px))"
    append-to-body
    :close-on-click-modal="false"
    :close-on-press-escape="!hasOverlay"
    :show-close="!hasOverlay"
    @close="close"
  >
    <template #header>
      <div class="dialog-header">
        <div class="header-icon">
          <i class="i-mdi-server-outline" aria-hidden="true" />
        </div>
        <div class="header-text">
          <h3 class="dialog-title">{{ t('bootTasks.detailsTitle') }}</h3>
          <p class="dialog-subtitle">{{ t('bootTasks.detailsHint') }}</p>
        </div>
      </div>
    </template>

    <div class="details-content">
      <!-- 概览指标卡片 -->
      <div class="group-overview-card">
        <div class="overview-header">
          <div class="overview-info">
            <div class="overview-name-row">
              <span class="overview-title" :title="group.defName || group.tenancyName || group.id">
                {{ group.defName || group.tenancyName || group.id }}
              </span>
              <el-tag :type="group.openBootFlag ? 'success' : 'info'" size="small" effect="light" class="overview-tag">
                <i :class="group.openBootFlag ? 'i-mdi-play-circle-outline' : 'i-mdi-stop-circle-outline'" />
                {{ t(group.openBootFlag ? 'bootTasks.statuses.active' : 'bootTasks.statuses.idle') }}
              </el-tag>
              <el-tag size="small" effect="plain" class="overview-tag arch-tag">{{ group.architecture }}</el-tag>
            </div>
            <div class="overview-meta">
              <span v-if="group.regionName" class="meta-item" :title="group.regionName">
                <i class="i-mdi-earth" aria-hidden="true" />
                {{ group.regionName }}
              </span>
              <span class="meta-item">
                <i class="i-mdi-identifier" aria-hidden="true" />
                ID: {{ group.id }}
              </span>
              <span v-if="group.createdAt" class="meta-item">
                <i class="i-mdi-clock-outline" aria-hidden="true" />
                {{ date(group.createdAt) }}
              </span>
            </div>
          </div>
          <GhostBtn :loading="loading" :disabled="hasOverlay" class="overview-refresh-btn" @click="load">
            <i class="i-mdi-refresh" aria-hidden="true" />
            {{ t('bootTasks.refresh') }}
          </GhostBtn>
        </div>

        <div class="overview-stats-grid">
          <div class="stat-card">
            <span class="stat-label">{{ t('bootTasks.overviewConfigCount') }}</span>
            <span class="stat-value">{{ number(rows.length) }}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">{{ t('bootTasks.overviewTotalCount') }}</span>
            <span class="stat-value">{{ number(group.totalCount || 0) }}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">{{ t('bootTasks.overviewCurrentCount') }}</span>
            <span class="stat-value">{{ number(group.currentAttemptCount || 0) }}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">{{ t('bootTasks.overviewYesterdayCount') }}</span>
            <span class="stat-value">{{ number(group.yesterdayAttemptCount || 0) }}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">{{ t('bootTasks.overviewFailCount') }}</span>
            <span class="stat-value stat-fail">{{ number(group.failCount || 0) }}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">{{ t('bootTasks.overviewSuccessCount') }}</span>
            <span class="stat-value stat-success">{{ number(group.successCount || 0) }}</span>
          </div>
        </div>
      </div>

      <PageErrorNotice v-if="error" class="details-error-notice">{{ error }}</PageErrorNotice>

      <!-- 移动端列表展示 -->
      <MobileRecordList v-if="compact" drilldown :list-id="mobileListId" :record-keys="rows.map(row => row.id)" :loading="loading" class="details-mobile-list">
        <MobileRecordCard v-for="row in mobileRows" :key="row.id" :record-key="row.id" :summary-title="[row.operatingSystem, row.operatingSystemVersion].filter(Boolean).join(' ') || row.id" :summary-meta="`${row.architecture} · ${row.id}`" :summary-status="status(row.status)" :summary-tone="row.status === 1 ? 'success' : row.status === 2 ? 'neutral' : 'warning'">
          <template #identity><h3 class="mobile-record-title">{{ [row.operatingSystem, row.operatingSystemVersion].filter(Boolean).join(' ') || '—' }}</h3></template>
          <dl class="mobile-record-fields">
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.index') }}</dt><dd>#{{ row.id }}</dd></div>
            <div v-for="field in (['yesterdayAttemptCount', 'currentAttemptCount', 'failCount'] as const)" :key="field"><dt>{{ t(`bootTasks.columns.${field}`) }}</dt><dd>{{ number(row[field]) }}</dd></div>
            <div><dt>{{ t('bootTasks.columns.status') }}</dt><dd><el-tag :type="row.status === 1 ? 'success' : row.status === 2 ? 'info' : 'warning'">{{ status(row.status) }}</el-tag></dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.config') }}</dt><dd>{{ t('bootTasks.configValue', { ocpu: number(row.ocpu), memory: number(row.memory), disk: number(row.disk), architecture: row.architecture }) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.dayGap') }}</dt><dd>{{ row.dayGap || t('bootTasks.allDay') }}</dd></div>
            <div><dt>{{ t('bootTasks.columns.loopTime') }}</dt><dd>{{ t('bootTasks.seconds', { count: number(row.loopTime) }) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.password') }}</dt><dd class="secret"><span>{{ row.rootPassword ? revealed.has(row.id) ? row.rootPassword : '••••••••' : '—' }}</span><button v-if="row.rootPassword" class="icon-button" type="button" :aria-label="t(revealed.has(row.id) ? 'bootTasks.hidePassword' : 'bootTasks.showPassword')" :aria-pressed="revealed.has(row.id)" @click="togglePassword(row.id)"><i :class="revealed.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button><button v-if="row.rootPassword" class="icon-button" type="button" :title="t('bootTasks.copyPassword')" :aria-label="t('bootTasks.copyPassword')" @click="copyPassword(row.rootPassword)"><i class="i-mdi-content-copy" aria-hidden="true" /></button></dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.createdAt') }}</dt><dd>{{ date(row.createdAt) }}</dd></div>
          </dl>
          <template #footer>
            <div class="row-actions">
              <button v-if="row.status === 1" type="button" class="boot-button" :title="t('bootTasks.actions.detailStop')" :aria-label="t('bootTasks.actions.detailStop')" :disabled="hasOverlay || loading" @click="openAction('detailStop', row)"><i class="i-mdi-stop-circle-outline" aria-hidden="true" /></button>
              <button v-else type="button" class="boot-button" :title="t('bootTasks.actions.detailStart')" :aria-label="t('bootTasks.actions.detailStart')" :disabled="hasOverlay || loading" @click="openAction('detailStart', row)"><i class="i-mdi-play-outline" aria-hidden="true" /></button>
              <button type="button" class="boot-button" :title="t('bootTasks.actions.logs')" :aria-label="t('bootTasks.actions.logs')" :disabled="hasOverlay || loading" @click="logTask = { id: row.id, bootId: row.bootId }"><i class="i-mdi-file-document-outline" aria-hidden="true" /></button>
              <button type="button" class="boot-button" :title="t('bootTasks.actions.edit')" :aria-label="t('bootTasks.actions.edit')" :disabled="hasOverlay || loading" @click="openAction('edit', row)"><i class="i-mdi-pencil-outline" aria-hidden="true" /></button>
              <button type="button" class="more-button danger-btn" :title="t('bootTasks.actions.detailDelete')" :aria-label="t('bootTasks.actions.detailDelete')" :disabled="hasOverlay || loading" @click="openAction('detailDelete', row)"><i class="i-mdi-delete-outline" aria-hidden="true" /></button>
            </div>
          </template>
        </MobileRecordCard>
        <p v-if="loading || !rows.length" class="details-mobile-empty" role="status">{{ loading ? t('bootTasks.loading') : error || t('bootTasks.noDetails') }}</p>
      </MobileRecordList>

      <!-- 桌面端表格 (列宽充裕，支持横向平滑滚动) -->
      <el-table
        v-else
        :data="pageRows"
        row-key="id"
        :empty-text="loading ? t('bootTasks.loading') : error || t('bootTasks.noDetails')"
        :aria-busy="loading"
        max-height="480"
        class="details-table"
      >
        <el-table-column prop="id" :label="t('bootTasks.columns.index')" width="160" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="id-badge">#{{ row.id }}</span>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.system')" width="200" show-overflow-tooltip>
          <template #default="{ row }">
            <div class="system-cell" :title="[row.operatingSystem, row.operatingSystemVersion].filter(Boolean).join(' ') || '—'">
              <i class="i-mdi-linux" aria-hidden="true" />
              <span>{{ [row.operatingSystem, row.operatingSystemVersion].filter(Boolean).join(' ') || '—' }}</span>
            </div>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.config')" width="320" show-overflow-tooltip>
          <template #default="{ row }">
            <div class="spec-cell">
              <span class="spec-primary">{{ row.ocpu }}C / {{ row.memory }}GB · {{ row.disk }}GB</span>
              <span class="spec-arch">{{ row.architecture }}</span>
            </div>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.dayGap')" width="160" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="time-window" :class="{ 'is-allday': !row.dayGap }">
              <i class="i-mdi-clock-time-four-outline" aria-hidden="true" />
              {{ row.dayGap || t('bootTasks.allDay') }}
            </span>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.loopTime')" width="140">
          <template #default="{ row }">
            <span class="interval-tag">{{ t('bootTasks.seconds', { count: number(row.loopTime) }) }}</span>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.yesterdayAttemptCount')" width="140" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="count-cell">{{ number(row.yesterdayAttemptCount) }}</span>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.currentAttemptCount')" width="140" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="count-cell">{{ number(row.currentAttemptCount) }}</span>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.failCount')" width="130" show-overflow-tooltip>
          <template #default="{ row }">
            <span :class="Number(row.failCount) > 0 ? 'count-fail' : 'count-cell'">
              {{ number(row.failCount) }}
            </span>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.status')" width="170">
          <template #default="{ row }">
            <el-tag :type="row.status === 1 ? 'success' : row.status === 2 ? 'info' : 'warning'" size="small">
              <span v-if="row.status === 1" class="status-pulse-dot" />
              {{ status(row.status) }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.password')" width="280">
          <template #default="{ row }">
            <div class="secret">
              <code class="password-code" :title="revealed.has(row.id) ? row.rootPassword : '••••••••'">
                {{ row.rootPassword ? revealed.has(row.id) ? row.rootPassword : '••••••••' : '—' }}
              </code>
              <button
                v-if="row.rootPassword"
                class="icon-button"
                type="button"
                :aria-label="t(revealed.has(row.id) ? 'bootTasks.hidePassword' : 'bootTasks.showPassword')"
                :title="t(revealed.has(row.id) ? 'bootTasks.hidePassword' : 'bootTasks.showPassword')"
                :aria-pressed="revealed.has(row.id)"
                @click="togglePassword(row.id)"
              >
                <i :class="revealed.has(row.id) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />
              </button>
              <button
                v-if="row.rootPassword"
                class="icon-button copy-pwd-btn"
                type="button"
                :title="t('bootTasks.copyPassword')"
                :aria-label="t('bootTasks.copyPassword')"
                @click="copyPassword(row.rootPassword)"
              >
                <i class="i-mdi-content-copy" aria-hidden="true" />
              </button>
            </div>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.createdAt')" width="210" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="created-date">{{ date(row.createdAt) }}</span>
          </template>
        </el-table-column>
        <el-table-column :label="t('bootTasks.columns.actions')" fixed="right" width="180" align="left" header-align="left">
          <template #default="{ row }">
            <div class="row-actions">
              <!-- 启动 / 停止 动态切换 -->
              <button
                v-if="row.status === 1"
                type="button"
                class="boot-button"
                :title="t('bootTasks.actions.detailStop')"
                :aria-label="t('bootTasks.actions.detailStop')"
                :disabled="hasOverlay || loading"
                @click="openAction('detailStop', row)"
              >
                <i class="i-mdi-stop-circle-outline" aria-hidden="true" />
              </button>
              <button
                v-else
                type="button"
                class="boot-button"
                :title="t('bootTasks.actions.detailStart')"
                :aria-label="t('bootTasks.actions.detailStart')"
                :disabled="hasOverlay || loading"
                @click="openAction('detailStart', row)"
              >
                <i class="i-mdi-play-outline" aria-hidden="true" />
              </button>

              <!-- 实时日志 -->
              <button
                type="button"
                class="boot-button"
                :title="t('bootTasks.actions.logs')"
                :aria-label="t('bootTasks.actions.logs')"
                :disabled="hasOverlay || loading"
                @click="logTask = { id: row.id, bootId: row.bootId }"
              >
                <i class="i-mdi-file-document-outline" aria-hidden="true" />
              </button>

              <!-- 编辑配置 -->
              <button
                type="button"
                class="boot-button"
                :title="t('bootTasks.actions.edit')"
                :aria-label="t('bootTasks.actions.edit')"
                :disabled="hasOverlay || loading"
                @click="openAction('edit', row)"
              >
                <i class="i-mdi-pencil-outline" aria-hidden="true" />
              </button>

              <!-- 删除配置 (红底危险操作按钮) -->
              <button
                type="button"
                class="more-button danger-btn"
                :title="t('bootTasks.actions.detailDelete')"
                :aria-label="t('bootTasks.actions.detailDelete')"
                :disabled="hasOverlay || loading"
                @click="openAction('detailDelete', row)"
              >
                <i class="i-mdi-delete-outline" aria-hidden="true" />
              </button>
            </div>
          </template>
        </el-table-column>
      </el-table>

      <PagePagination v-if="rows.length" embedded class="details-pagination" v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50, 100]" :total="rows.length" :disabled="loading || hasOverlay">
        <span>{{ t('bootTasks.detailRecords', { count: number(rows.length) }) }}</span>
      </PagePagination>
    </div>

    <template #footer>
      <GhostBtn :disabled="hasOverlay" @click="close">{{ t('bootTasks.close') }}</GhostBtn>
    </template>
  </el-dialog>
  <BootTaskActionDialog v-if="operation" :key="`${operation.action}:${operation.target.id}`" :action="operation.action" :target="operation.target" @close="operation = null" @changed="changed" @busy="setBusy" />
  <BootTaskLogDrawer v-if="logTask" :task-id="logTask.id" :scheduler-id="logTask.bootId" @close="logTask = null" />
</template>

<style scoped>
.details-content {
  color: var(--text-primary);
  font: var(--font-size-body)/1.5 var(--sans);
}

/* 弹窗自定义 Header */
.dialog-header {
  display: flex;
  align-items: center;
  gap: 12px;
}
.header-icon {
  display: grid;
  place-items: center;
  width: 38px;
  height: 38px;
  border-radius: 10px;
  background: color-mix(in srgb, var(--brand) 12%, transparent);
  color: var(--brand);
  font-size: 20px;
  flex-shrink: 0;
}
.header-icon i {
  width: 22px;
  height: 22px;
  font-size: 22px;
  line-height: 1;
}
.header-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.dialog-title {
  margin: 0;
  font-size: var(--font-size-dialog-title, 18px);
  font-weight: 600;
  color: var(--text-primary);
}
.dialog-subtitle {
  margin: 0;
  font-size: var(--font-size-secondary, 13px);
  color: var(--text-secondary);
}

/* 概览信息卡片 */
.group-overview-card {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px 16px;
  margin-bottom: 14px;
  border-radius: 12px;
  border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
  background: var(--bg-hover, rgba(0, 0, 0, 0.02));
}

.overview-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}

.overview-info {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.overview-name-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.overview-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
}

.overview-tag {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-weight: 500;
}

.arch-tag {
  font-family: var(--font-family-mono, monospace);
  font-weight: 600;
}

.overview-meta {
  display: flex;
  align-items: center;
  gap: 14px;
  flex-wrap: wrap;
  font-size: var(--font-size-secondary, 12px);
  color: var(--text-secondary);
}

.meta-item {
  display: inline-flex;
  align-items: center;
  gap: 5px;
}

.overview-refresh-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
  padding: 6px 12px;
}

/* 概览统计小卡片 */
.overview-stats-grid {
  display: grid;
  grid-template-columns: repeat(6, 1fr);
  gap: 8px;
}

.stat-card {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 8px 10px;
  border-radius: 8px;
  background: var(--bg-card);
  border: 1px solid color-mix(in srgb, var(--border) 60%, transparent);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.02);
  min-width: 0;
}

.stat-label {
  font-size: 11px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.stat-value {
  font-size: 16px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
  white-space: nowrap;
}

.stat-fail {
  color: var(--status-danger, #ef4444);
}

.stat-success {
  color: var(--status-success, #10b981);
}

/* 详情表格核心样式：彻底禁止任何字段或表头换行，保证平滑横向滚动 */
.details-table {
  width: 100%;
}

.details-table :deep(th.el-table__cell .cell),
.details-table :deep(td.el-table__cell .cell) {
  white-space: nowrap !important;
  word-break: keep-all !important;
  word-wrap: normal !important;
}

.details-table :deep(.el-table__body-wrapper) {
  overflow-x: auto;
}

.details-table :deep(.el-tag) {
  white-space: nowrap !important;
}

/* 表格内字段装饰 */
.id-badge {
  font-family: var(--font-family-mono, monospace);
  font-size: 12px;
  font-weight: 600;
  color: var(--text-secondary);
  white-space: nowrap;
}

.system-cell {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-weight: 500;
  white-space: nowrap;
}
.system-cell span {
  white-space: nowrap;
}
.system-cell i {
  font-size: 16px;
  color: var(--brand);
  flex-shrink: 0;
}

.spec-cell {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  flex-wrap: nowrap;
  white-space: nowrap;
}
.spec-primary {
  font-weight: 500;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.spec-arch {
  font-size: 11px;
  padding: 1px 6px;
  border-radius: 4px;
  background: var(--bg-hover);
  color: var(--text-secondary);
  white-space: nowrap;
  flex-shrink: 0;
}

.time-window {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  white-space: nowrap;
}
.time-window.is-allday {
  color: var(--status-success);
}

.interval-tag {
  display: inline-block;
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  font-size: 12px;
  white-space: nowrap;
}

.count-cell {
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
  white-space: nowrap;
}
.count-fail {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  color: var(--status-danger);
  white-space: nowrap;
}

.status-pulse-dot {
  display: inline-block;
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--status-ok, #10b981);
  margin-right: 4px;
  flex-shrink: 0;
  animation: pulse-dot 1.5s ease-in-out infinite;
}
@keyframes pulse-dot {
  0%, 100% { transform: scale(0.9); opacity: 0.6; }
  50% { transform: scale(1.3); opacity: 1; }
}

.secret {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  flex-wrap: nowrap;
  white-space: nowrap;
}
.password-code {
  font-family: var(--font-family-mono, monospace);
  font-size: 12px;
  padding: 2px 6px;
  border-radius: 5px;
  background: var(--bg-search, rgba(0, 0, 0, 0.04));
  border: 1px solid color-mix(in srgb, var(--border) 60%, transparent);
  white-space: nowrap;
  max-width: 140px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.created-date {
  font-variant-numeric: tabular-nums;
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
}

/* 操作列按钮标准样式 (32px 方形 9px 圆角) */
.row-actions {
  display: inline-flex;
  justify-content: flex-start;
  align-items: center;
  gap: 6px;
  flex-wrap: nowrap;
  white-space: nowrap;
}

.row-actions button,
.icon-button {
  flex-shrink: 0;
  display: inline-flex;
  justify-content: center;
  align-items: center;
  width: 32px;
  height: 32px;
  padding: 0;
  box-sizing: border-box;
  border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
  border-radius: 9px;
  background: var(--bg-card);
  color: var(--text-primary);
  font: inherit;
  font-size: 15px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.16s ease;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}

.row-actions button:hover:not(:disabled),
.icon-button:hover:not(:disabled) {
  color: var(--brand);
  background: var(--status-ok-bg);
  border-color: color-mix(in srgb, var(--brand) 30%, transparent);
  box-shadow: 0 2px 8px color-mix(in srgb, var(--brand) 12%, transparent);
  transform: translateY(-1px);
}

.row-actions button:active:not(:disabled),
.icon-button:active:not(:disabled) {
  transform: scale(0.94);
}

.row-actions button:disabled,
.icon-button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
  box-shadow: none;
}

.row-actions .danger-btn {
  background: var(--status-danger) !important;
  border-color: var(--status-danger) !important;
  color: #ffffff !important;
}

.row-actions .danger-btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--status-danger) 85%, black) !important;
  border-color: color-mix(in srgb, var(--status-danger) 85%, black) !important;
  color: #ffffff !important;
  box-shadow: 0 2px 8px color-mix(in srgb, var(--status-danger) 25%, transparent) !important;
}

.details-pagination {
  margin-top: 16px;
}
.details-error-notice {
  margin-bottom: 12px;
}

@media (max-width: 900px) {
  .overview-stats-grid { grid-template-columns: repeat(3, 1fr); }
}

@media (max-width: 760px) {
  :global(.boot-task-details-dialog) { max-height: calc(100dvh - 28px); overflow-y: auto; }
  .details-mobile-list { padding: 0; max-height: 55dvh; overflow-y: auto; overscroll-behavior: contain; }
  .details-mobile-empty { display: grid; place-items: center; min-height: 88px; margin: 0; color: var(--text-secondary); }
  .overview-stats-grid { grid-template-columns: repeat(2, 1fr); }
  .details-mobile-list .secret { min-width: 0; flex-wrap: wrap; }
}
</style>
