<script setup lang="ts">
import {
  ref,
  reactive,
  computed,
  onMounted,
  onBeforeUnmount,
  nextTick,
} from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import {
  fetchAuditLogs,
  deleteAuditLog,
  batchDeleteAuditLogs,
  clearAllAuditLogs,
  type AuditLogRow,
} from '@/api/auditLogs'
import './audit-logs.scss'

const { t, locale } = useI18n()
const router = useRouter()
const route = useRoute()
const numberFormat = computed(() => new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN'))

const root = ref<HTMLElement | null>(null)
const searchInput = ref<HTMLInputElement | null>(null)
const tableScroll = ref<HTMLElement | null>(null)

const loading = ref(false)
const loaded = ref(false)
const rows = ref<AuditLogRow[]>([])
const total = ref(0)
const selectedIds = ref<number[]>([])

// Query params
const keyword = ref('')
const submittedKeyword = ref('')
const method = ref('')
const status = ref<'' | number>('')
const page = ref(1)
const size = ref(15)

// Date Range (default: last 30 days)
const oneMonthAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
const now = new Date()
function formatYMD(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}
const dateRange = ref<[string, string]>([formatYMD(oneMonthAgo), formatYMD(now)])

const dateShortcuts = [
  {
    text: '最近一天',
    value: () => {
      const end = new Date()
      const start = new Date()
      start.setTime(start.getTime() - 3600 * 1000 * 24)
      return [formatYMD(start), formatYMD(end)]
    },
  },
  {
    text: '最近一周',
    value: () => {
      const end = new Date()
      const start = new Date()
      start.setTime(start.getTime() - 3600 * 1000 * 24 * 7)
      return [formatYMD(start), formatYMD(end)]
    },
  },
  {
    text: '最近一个月',
    value: () => {
      const end = new Date()
      const start = new Date()
      start.setTime(start.getTime() - 3600 * 1000 * 24 * 30)
      return [formatYMD(start), formatYMD(end)]
    },
  },
]

// Detail Dialog
const detailVisible = ref(false)
const currentDetail = ref<AuditLogRow | null>(null)

// Custom Dialog States
const clearDialogVisible = ref(false)
const clearConfirmInput = ref('')
const clearing = ref(false)

const batchDeleteDialogVisible = ref(false)
const batchDeleting = ref(false)

const singleDeleteDialogVisible = ref(false)
const rowToDelete = ref<AuditLogRow | null>(null)
const singleDeleting = ref(false)

function handleOpenSingleDeleteDialog(row: AuditLogRow) {
  rowToDelete.value = row
  singleDeleteDialogVisible.value = true
}

async function handleExecuteSingleDelete() {
  if (!rowToDelete.value || singleDeleting.value) return
  singleDeleting.value = true
  try {
    const id = rowToDelete.value.id
    await deleteAuditLog(id)
    ElMessage.success(t('auditLogs.deleteSuccess') || '删除成功')
    singleDeleteDialogVisible.value = false
    selectedIds.value = selectedIds.value.filter(item => item !== id)
    rowToDelete.value = null
    void load()
  } catch {
    // handled
  } finally {
    singleDeleting.value = false
  }
}

const allSelected = computed(() => {
  return rows.value.length > 0 && rows.value.every(r => selectedIds.value.includes(r.id))
})

const someSelected = computed(() => {
  return selectedIds.value.length > 0 && !allSelected.value
})

function isSelected(id: number) {
  return selectedIds.value.includes(id)
}

function toggleSelectAll(event: Event) {
  const checked = (event.target as HTMLInputElement).checked
  if (checked) {
    selectedIds.value = Array.from(new Set([...selectedIds.value, ...rows.value.map(r => r.id)]))
  } else {
    const currentIds = new Set(rows.value.map(r => r.id))
    selectedIds.value = selectedIds.value.filter(id => !currentIds.has(id))
  }
}

function toggleSelect(id: number) {
  const index = selectedIds.value.indexOf(id)
  if (index >= 0) {
    selectedIds.value.splice(index, 1)
  } else {
    selectedIds.value.push(id)
  }
}

const hasActiveFilter = computed(() => {
  return !!submittedKeyword.value || !!method.value || status.value !== '' || !isDefaultDateRange()
})

function isDefaultDateRange(): boolean {
  if (!dateRange.value || !dateRange.value[0] || !dateRange.value[1]) return false
  return dateRange.value[0] === formatYMD(oneMonthAgo) && dateRange.value[1] === formatYMD(now)
}

const filterSummary = computed(() => {
  const parts: string[] = []
  if (submittedKeyword.value) parts.push(`关键字 "${submittedKeyword.value}"`)
  if (method.value) parts.push(`方式 ${method.value}`)
  if (status.value !== '') parts.push(`状态 ${status.value === 1 ? '成功' : '失败'}`)
  if (dateRange.value && dateRange.value[0]) parts.push(`${dateRange.value[0]} 至 ${dateRange.value[1]}`)
  return parts.join(' · ')
})

const rangeStart = computed(() => (total.value === 0 ? 0 : (page.value - 1) * size.value + 1))
const rangeEnd = computed(() => Math.min(page.value * size.value, total.value))

async function load(refresh = false) {
  loading.value = true
  try {
    const startDate = dateRange.value && dateRange.value[0] ? `${dateRange.value[0]} 00:00:00` : undefined
    const endDate = dateRange.value && dateRange.value[1] ? `${dateRange.value[1]} 23:59:59` : undefined

    const res = await fetchAuditLogs({
      page: page.value,
      size: size.value,
      keyword: submittedKeyword.value || undefined,
      method: method.value || undefined,
      status: status.value !== '' ? status.value : undefined,
      startDate,
      endDate,
    })

    if (res && res.data) {
      rows.value = res.data.content || []
      total.value = res.data.totalElements || 0
      loaded.value = true
    }
  } catch (error) {
    console.error('加载审计日志失败', error)
  } finally {
    loading.value = false
  }
}

function handleSearchSubmit() {
  submittedKeyword.value = keyword.value.trim()
  page.value = 1
  void load()
}

function clearSearch() {
  keyword.value = ''
  submittedKeyword.value = ''
  page.value = 1
  void load()
}

function resetFilters() {
  keyword.value = ''
  submittedKeyword.value = ''
  method.value = ''
  status.value = ''
  dateRange.value = [formatYMD(oneMonthAgo), formatYMD(now)]
  page.value = 1
  selectedIds.value = []
  void load()
}

function handleFilterChange() {
  page.value = 1
  void load()
}

function changePage(newPage: number) {
  page.value = newPage
  void load()
}

function changeSize(newSize: number) {
  size.value = newSize
  page.value = 1
  void load()
}

function openDetail(row: AuditLogRow) {
  currentDetail.value = row
  detailVisible.value = true
}

async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text)
    ElMessage.success(t('auditLogs.copySuccess') || '复制成功')
  } catch {
    ElMessage.error('复制失败')
  }
}


function handleOpenClearDialog() {
  clearConfirmInput.value = ''
  clearDialogVisible.value = true
}

async function handleExecuteClear() {
  if (clearConfirmInput.value.trim() !== 'CLEAR' || clearing.value) return
  clearing.value = true
  try {
    await clearAllAuditLogs()
    ElMessage.success(t('auditLogs.clearSuccess') || '审计日志已清空')
    clearDialogVisible.value = false
    selectedIds.value = []
    page.value = 1
    void load(true)
  } catch {
    // handled
  } finally {
    clearing.value = false
  }
}

function handleOpenBatchDeleteDialog() {
  if (selectedIds.value.length === 0) return
  batchDeleteDialogVisible.value = true
}

async function handleExecuteBatchDelete() {
  if (selectedIds.value.length === 0 || batchDeleting.value) return
  batchDeleting.value = true
  try {
    await batchDeleteAuditLogs(selectedIds.value)
    ElMessage.success(t('auditLogs.batchDeleteSuccess') || '批量删除成功')
    batchDeleteDialogVisible.value = false
    selectedIds.value = []
    void load(true)
  } catch {
    // handled
  } finally {
    batchDeleting.value = false
  }
}

function costClass(ms: number) {
  if (ms < 500) return 'fast'
  if (ms < 1500) return 'medium'
  return 'slow'
}

function formatJson(str: string): string {
  if (!str) return ''
  try {
    return JSON.stringify(JSON.parse(str), null, 2)
  } catch {
    return str
  }
}

function handleShortcut(event: KeyboardEvent) {
  if (
    event.key !== '/' ||
    event.ctrlKey ||
    event.metaKey ||
    event.altKey ||
    ['INPUT', 'TEXTAREA'].includes((event.target as HTMLElement)?.tagName)
  ) {
    return
  }
  event.preventDefault()
  searchInput.value?.focus()
}

onMounted(() => {
  void load()
  document.addEventListener('keydown', handleShortcut)
})

onBeforeUnmount(() => {
  document.removeEventListener('keydown', handleShortcut)
})
</script>

<template>
  <div ref="root" class="tenants-page audit-logs-page">
    <section
      class="tenant-card"
      data-motion-enter
      :aria-label="t('auditLogs.title')"
      :aria-busy="loading"
    >
      <!-- 顶部工具栏（对齐租户管理 list-toolbar 样式） -->
      <div class="list-toolbar">
        <form class="tenant-search" role="search" @submit.prevent="handleSearchSubmit">
          <i class="i-mdi-magnify" aria-hidden="true" />
          <input
            ref="searchInput"
            v-model="keyword"
            placeholder="搜索操作标题、路径、操作人、IP…"
            autocomplete="off"
            @keydown.esc.prevent="clearSearch"
          />
          <button v-if="keyword" type="button" title="清空搜索" @click="clearSearch">
            <i class="i-mdi-close-circle" />
          </button>
          <kbd v-else aria-hidden="true">/</kbd>
        </form>

        <!-- 最近一个月日期范围快捷选择 -->
        <el-date-picker
          v-model="dateRange"
          type="daterange"
          range-separator="-"
          start-placeholder="开始日期"
          end-placeholder="结束日期"
          :shortcuts="dateShortcuts"
          format="YYYY-MM-DD"
          value-format="YYYY-MM-DD"
          :clearable="false"
          class="audit-date-picker"
          @change="handleFilterChange"
        />

        <!-- 请求方式选择 -->
        <el-select
          v-model="method"
          placeholder="请求方式"
          clearable
          class="audit-select"
          @change="handleFilterChange"
        >
          <el-option label="全部方式" value="" />
          <el-option label="GET" value="GET" />
          <el-option label="POST" value="POST" />
          <el-option label="PUT" value="PUT" />
          <el-option label="DELETE" value="DELETE" />
        </el-select>

        <!-- 状态选择 -->
        <el-select
          v-model="status"
          placeholder="状态"
          clearable
          class="audit-select"
          @change="handleFilterChange"
        >
          <el-option label="全部状态" value="" />
          <el-option label="成功" :value="1" />
          <el-option label="失败" :value="0" />
        </el-select>

        <div class="toolbar-actions" data-page-error-anchor>
          <button
            class="toolbar-button"
            :aria-label="t('auditLogs.reset')"
            :title="loading ? '正在刷新…' : '刷新'"
            :disabled="loading"
            @click="load(true)"
          >
            <i class="i-mdi-refresh" :class="{ 'is-spinning': loading }" aria-hidden="true" />
          </button>

          <button
            v-if="selectedIds.length > 0"
            class="toolbar-button batch-delete-btn"
            :title="`批量删除选中 (${selectedIds.length})`"
            @click="handleOpenBatchDeleteDialog"
          >
            <i class="i-mdi-delete-sweep-outline" aria-hidden="true" />
          </button>

          <PrimaryBtn
            class="tenant-import danger-btn"
            title="清空系统中全部审计记录"
            @click="handleOpenClearDialog"
          >
            <i class="i-mdi-trash-can-outline" aria-hidden="true" />
            <span>一键清空</span>
          </PrimaryBtn>
        </div>
      </div>

      <!-- 搜索/筛选上下文提示条 -->
      <div v-if="hasActiveFilter" class="search-context">
        <span>已应用筛选：{{ filterSummary }}（找到 {{ total }} 条记录）</span>
        <button @click="resetFilters">重置筛选<i class="i-mdi-close" /></button>
      </div>

      <!-- 表格区域（对齐租户管理 table-stage 与 tenant-table 样式） -->
      <div class="table-stage" :class="{ 'is-refreshing': loading && loaded }">
        <div v-if="loading && loaded" class="refresh-track" aria-hidden="true">
          <span />
        </div>

        <div ref="tableScroll" class="table-scroll" tabindex="0">
          <table class="tenant-table audit-table">
            <thead>
              <tr>
                <th scope="col" style="width: 44px; text-align: center; padding-left: 14px;">
                  <input
                    type="checkbox"
                    :checked="allSelected"
                    :indeterminate="someSelected"
                    class="audit-checkbox"
                    @change="toggleSelectAll"
                  />
                </th>
                <th scope="col" style="width: 65px;">ID</th>
                <th scope="col" class="identity-column">操作模块 / 描述</th>
                <th scope="col" style="width: 85px;">方式</th>
                <th scope="col" style="min-width: 180px;">请求路径</th>
                <th scope="col" style="width: 100px;">操作人</th>
                <th scope="col" style="width: 125px;">客户端 IP</th>
                <th scope="col" style="width: 110px;">归属地</th>
                <th scope="col" style="width: 85px;">状态</th>
                <th scope="col" style="width: 80px;">耗时</th>
                <th scope="col" style="width: 155px;">记录时间</th>
                <th scope="col" class="row-actions-column">操作</th>
              </tr>
            </thead>

            <!-- 骨架屏加载 -->
            <tbody v-if="!loaded && loading" aria-hidden="true">
              <tr v-for="n in 8" :key="n" class="skeleton-row">
                <td v-for="c in 12" :key="c">
                  <span class="skeleton" :class="{ 'skeleton-name': c === 3 }" />
                </td>
              </tr>
            </tbody>

            <!-- 数据行 -->
            <tbody v-else>
              <tr
                v-for="row in rows"
                :key="row.id"
                data-motion-row
                :class="{ 'row-selected': isSelected(row.id) }"
              >
                <td style="text-align: center; padding-left: 14px;">
                  <input
                    type="checkbox"
                    :checked="isSelected(row.id)"
                    class="audit-checkbox"
                    @change="toggleSelect(row.id)"
                  />
                </td>
                <td>
                  <span class="cell-secondary">#{{ row.id }}</span>
                </td>
                <td class="identity-column">
                  <div class="tenant-identity">
                    <div
                      class="proxy-button"
                      :class="row.status === 1 ? 'proxy-bound' : 'proxy-force'"
                      style="cursor: default;"
                      :title="row.status === 1 ? '操作正常' : '操作异常'"
                    >
                      <i :class="row.status === 1 ? 'i-mdi-shield-check-outline' : 'i-mdi-shield-alert-outline'" />
                    </div>
                    <div class="identity-text">
                      <button class="edit-name" :title="row.title" @click="openDetail(row)">
                        {{ row.title || '-' }}<i class="i-mdi-information-outline" />
                      </button>
                      <span class="private-name" :title="row.actionMethod">
                        <span>{{ row.actionMethod }}</span>
                      </span>
                    </div>
                  </div>
                </td>
                <td>
                  <span class="method-tag" :class="row.method?.toLowerCase()">
                    {{ row.method }}
                  </span>
                </td>
                <td>
                  <span class="audit-uri" :title="row.requestUri">
                    {{ row.requestUri }}
                  </span>
                </td>
                <td>
                  <span class="operator-badge" :title="row.username">{{ row.username }}</span>
                </td>
                <td>
                  <span class="ip-text">{{ row.ip }}</span>
                </td>
                <td>
                  <span class="cell-secondary" :title="row.location">{{ row.location || '未知' }}</span>
                </td>
                <td>
                  <span
                    class="tenant-status"
                    :class="row.status === 1 ? 'status-active' : 'status-inactive'"
                  >
                    <span />{{ row.status === 1 ? '成功' : '失败' }}
                  </span>
                </td>
                <td>
                  <span class="cost-text" :class="costClass(row.costTime)">{{ row.costTime }}ms</span>
                </td>
                <td>
                  <time class="created-at">{{ row.createTime }}</time>
                </td>
                <td class="row-actions-column">
                  <div class="row-actions">
                    <button
                      class="boot-button"
                      title="查看详情"
                      aria-label="查看详情"
                      @click="openDetail(row)"
                    >
                      <i class="i-mdi-eye-outline" />
                    </button>
                    <button
                      class="more-button danger-btn"
                      title="删除记录"
                      aria-label="删除记录"
                      @click="handleOpenSingleDeleteDialog(row)"
                    >
                      <i class="i-mdi-delete-outline" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>

          <!-- 空状态 -->
          <div v-if="!loading && !rows.length" class="tenant-empty" role="status">
            <span class="empty-icon">
              <i :class="submittedKeyword ? 'i-mdi-magnify' : 'i-mdi-shield-check-outline'" />
            </span>
            <h3>{{ submittedKeyword ? '未找到匹配的审计记录' : '暂无审计日志记录' }}</h3>
            <p>{{ submittedKeyword ? '请尝试调整搜索关键字或筛选条件。' : '当前系统暂无最近一个月的操作与访问审计日志。' }}</p>
            <GhostBtn v-if="hasActiveFilter" @click="resetFilters">重置筛选条件</GhostBtn>
          </div>
        </div>
      </div>

      <!-- 分页栏（对齐租户管理 PagePagination 布局） -->
      <PagePagination
        :current-page="page"
        :page-size="size"
        :total="total"
        :page-sizes="[10, 15, 30, 50, 100]"
        @current-change="changePage"
        @size-change="changeSize"
      >
        <p aria-live="polite">
          {{
            loading && !loaded
              ? '正在读取审计记录…'
              : `显示第 ${rangeStart} - ${rangeEnd} 条，共 ${numberFormat.format(total)} 条审计记录`
          }}
        </p>
      </PagePagination>
    </section>

    <!-- 详情弹窗（对齐租户管理 tenant-edit-dialog 风格） -->
    <el-dialog
      v-model="detailVisible"
      :title="`审计日志详情 · #${currentDetail?.id || ''}`"
      width="640px"
      class="tenant-edit-dialog audit-detail-dialog"
      destroy-on-close
    >
      <div v-if="currentDetail">
        <p class="edit-description">
          记录该接口调用的完整上下文信息，包括客户端环境、网络归属、调用参数及异常追踪。
        </p>

        <div class="detail-grid">
          <div class="detail-item">
            <label>操作标题</label>
            <span><strong>{{ currentDetail.title || '-' }}</strong></span>
          </div>
          <div class="detail-item">
            <label>请求方式与状态</label>
            <span>
              <span class="method-tag" :class="currentDetail.method?.toLowerCase()">{{ currentDetail.method }}</span>
              &nbsp;
              <span class="tenant-status" :class="currentDetail.status === 1 ? 'status-active' : 'status-inactive'">
                <span />{{ currentDetail.status === 1 ? '成功' : '失败' }} (HTTP {{ currentDetail.responseStatus }})
              </span>
            </span>
          </div>
          <div class="detail-item full-width">
            <label>请求路径</label>
            <code>{{ currentDetail.requestUri }}</code>
          </div>
          <div class="detail-item full-width">
            <label>后端执行方法</label>
            <code>{{ currentDetail.actionMethod }}</code>
          </div>
          <div class="detail-item">
            <label>操作人</label>
            <span class="operator-badge">{{ currentDetail.username }}</span>
          </div>
          <div class="detail-item">
            <label>耗时</label>
            <span class="cost-text" :class="costClass(currentDetail.costTime)">{{ currentDetail.costTime }} ms</span>
          </div>
          <div class="detail-item">
            <label>客户端 IP</label>
            <span class="ip-text">{{ currentDetail.ip }}</span>
          </div>
          <div class="detail-item">
            <label>IP 归属地</label>
            <span>{{ currentDetail.location || '未知' }}</span>
          </div>
          <div class="detail-item full-width">
            <label>记录时间</label>
            <time class="created-at">{{ currentDetail.createTime }}</time>
          </div>
          <div v-if="currentDetail.userAgent" class="detail-item full-width">
            <label>User-Agent</label>
            <span style="font-size: 11px; word-break: break-all; color: var(--text-secondary);">
              {{ currentDetail.userAgent }}
            </span>
          </div>
        </div>

        <div v-if="currentDetail.params" class="detail-code-block">
          <div class="code-header">
            <span>请求参数</span>
            <button type="button" @click="copyText(currentDetail.params)">
              <i class="i-mdi-content-copy" aria-hidden="true" />
              <span>复制参数</span>
            </button>
          </div>
          <pre><code>{{ formatJson(currentDetail.params) }}</code></pre>
        </div>

        <div v-if="currentDetail.errorMsg" class="detail-code-block">
          <div class="code-header">
            <span style="color: var(--status-danger);">错误异常追踪</span>
            <button type="button" style="color: var(--status-danger);" @click="copyText(currentDetail.errorMsg)">
              <i class="i-mdi-content-copy" aria-hidden="true" />
              <span>复制错误</span>
            </button>
          </div>
          <pre class="is-error"><code>{{ currentDetail.errorMsg }}</code></pre>
        </div>
      </div>

      <template #footer>
        <GhostBtn @click="detailVisible = false">关闭</GhostBtn>
      </template>
    </el-dialog>

    <!-- 一键清空专属企业级危险操作弹窗 -->
    <el-dialog
      v-model="clearDialogVisible"
      title="清空审计日志确认"
      width="500px"
      class="tenant-edit-dialog audit-clear-dialog"
      destroy-on-close
    >
      <div class="clear-dialog-content">
        <div class="clear-warning-box">
          <div class="warning-icon">
            <i class="i-mdi-alert-octagon-outline" aria-hidden="true" />
          </div>
          <div class="warning-text">
            <h4>高危操作：系统审计记录全量清除</h4>
            <p>此操作将永久清空系统中现存的全部访问与操作审计记录。清除后数据无法恢复，请确认是否继续。</p>
          </div>
        </div>

        <div class="clear-stats">
          <div class="stat-item">
            <span>待清空日志总数</span>
            <strong style="color: var(--status-danger);">{{ numberFormat.format(total) }} 条</strong>
          </div>
          <div class="stat-item">
            <span>影响范围</span>
            <strong>全部历史接口访问日志</strong>
          </div>
        </div>

        <div class="clear-confirm-input">
          <label for="clear-verify-text">
            请输入 <b>CLEAR</b> 以确认执行清空：
          </label>
          <el-input
            id="clear-verify-text"
            v-model="clearConfirmInput"
            placeholder="输入 CLEAR 确认"
            clearable
            autocomplete="off"
            @keyup.enter="handleExecuteClear"
          />
        </div>
      </div>

      <template #footer>
        <div class="clear-dialog-footer">
          <GhostBtn :disabled="clearing" @click="clearDialogVisible = false">取消</GhostBtn>
          <PrimaryBtn
            class="danger-btn"
            :disabled="clearConfirmInput.trim() !== 'CLEAR' || clearing"
            :loading="clearing"
            @click="handleExecuteClear"
          >
            <i class="i-mdi-trash-can-outline" aria-hidden="true" />
            <span>{{ clearing ? '正在清空…' : '确认全量清空' }}</span>
          </PrimaryBtn>
        </div>
      </template>
    </el-dialog>

    <!-- 批量删除专属确认弹窗 -->
    <el-dialog
      v-model="batchDeleteDialogVisible"
      title="批量删除确认"
      width="480px"
      class="tenant-edit-dialog audit-clear-dialog"
      destroy-on-close
    >
      <div class="clear-dialog-content">
        <div
          class="clear-warning-box"
          style="background: rgba(245, 158, 11, 0.08); border-color: rgba(245, 158, 11, 0.25); color: var(--status-warn, #f59e0b);"
        >
          <div class="warning-icon" style="background: rgba(245, 158, 11, 0.16);">
            <i class="i-mdi-delete-sweep-outline" aria-hidden="true" />
          </div>
          <div class="warning-text">
            <h4 style="color: var(--status-warn, #d97706);">批量删除选中的审计记录</h4>
            <p style="color: var(--text-secondary);">
              即将从数据库中删除选中的 <strong>{{ selectedIds.length }}</strong> 条审计记录，删除后数据不可恢复。
            </p>
          </div>
        </div>

        <div class="clear-stats">
          <div class="stat-item">
            <span>待删除条数</span>
            <strong style="color: var(--status-warn, #d97706);">{{ selectedIds.length }} 项</strong>
          </div>
          <div class="stat-item">
            <span>操作类型</span>
            <strong>批量永久移除</strong>
          </div>
        </div>
      </div>

      <template #footer>
        <div class="clear-dialog-footer">
          <GhostBtn :disabled="batchDeleting" @click="batchDeleteDialogVisible = false">取消</GhostBtn>
          <PrimaryBtn
            class="danger-btn"
            :loading="batchDeleting"
            @click="handleExecuteBatchDelete"
          >
            <i class="i-mdi-delete-outline" aria-hidden="true" />
            <span>{{ batchDeleting ? '正在删除…' : `确认删除 (${selectedIds.length}) 项` }}</span>
          </PrimaryBtn>
        </div>
      </template>
    </el-dialog>

    <!-- 单条删除专属确认弹窗 -->
    <el-dialog
      v-model="singleDeleteDialogVisible"
      title="删除审计记录确认"
      width="480px"
      class="tenant-edit-dialog audit-clear-dialog"
      destroy-on-close
    >
      <div v-if="rowToDelete" class="clear-dialog-content">
        <div
          class="clear-warning-box"
          style="background: rgba(239, 68, 68, 0.08); border-color: rgba(239, 68, 68, 0.25); color: var(--status-danger);"
        >
          <div class="warning-icon" style="background: rgba(239, 68, 68, 0.16);">
            <i class="i-mdi-trash-can-outline" aria-hidden="true" />
          </div>
          <div class="warning-text">
            <h4 style="color: var(--status-danger);">确认删除此条审计记录？</h4>
            <p style="color: var(--text-secondary);">
              此操作将永久移除该条操作与访问审计记录，删除后数据不可恢复。
            </p>
          </div>
        </div>

        <div class="clear-stats">
          <div class="stat-item">
            <span>记录编号</span>
            <strong>#{{ rowToDelete.id }}</strong>
          </div>
          <div class="stat-item">
            <span>操作模块</span>
            <strong :title="rowToDelete.title">{{ rowToDelete.title || '-' }}</strong>
          </div>
          <div class="stat-item">
            <span>请求方式 / 状态</span>
            <strong>
              <span class="method-tag" :class="rowToDelete.method?.toLowerCase()">{{ rowToDelete.method }}</span>
              &nbsp;
              <span :style="{ color: rowToDelete.status === 1 ? 'var(--status-success)' : 'var(--status-danger)' }">
                {{ rowToDelete.status === 1 ? '成功' : '失败' }}
              </span>
            </strong>
          </div>
          <div class="stat-item">
            <span>操作人员</span>
            <strong>{{ rowToDelete.username }}</strong>
          </div>
          <div class="stat-item full-width">
            <span>请求路径</span>
            <code>{{ rowToDelete.requestUri }}</code>
          </div>
        </div>
      </div>

      <template #footer>
        <div class="clear-dialog-footer">
          <GhostBtn :disabled="singleDeleting" @click="singleDeleteDialogVisible = false">取消</GhostBtn>
          <PrimaryBtn
            class="danger-btn"
            :loading="singleDeleting"
            @click="handleExecuteSingleDelete"
          >
            <i class="i-mdi-trash-can-outline" aria-hidden="true" />
            <span>{{ singleDeleting ? '正在删除…' : '确认删除' }}</span>
          </PrimaryBtn>
        </div>
      </template>
    </el-dialog>
  </div>
</template>
