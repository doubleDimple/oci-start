<script setup lang="ts">
import { computed, defineAsyncComponent, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { isCancel } from 'axios'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { tenantError, tenantGet, type TenantRow } from '@/api/tenant'
import { useShellStore } from '@/stores/shell'
import { usePageMotion } from '@/composables/usePageMotion'
import './tenants.scss'

const TenantRegionSecurityDialog = defineAsyncComponent(() => import('./components/TenantRegionSecurityDialog.vue'))
const TenantRegionVolumesDialog = defineAsyncComponent(() => import('./components/TenantRegionVolumesDialog.vue'))
const TenantRegionMysqlDialog = defineAsyncComponent(() => import('./components/TenantRegionMysqlDialog.vue'))
const route = useRoute()
const router = useRouter()
const shell = useShellStore()
const root = ref<HTMLElement | null>(null)
const searchInput = ref<HTMLInputElement | null>(null)
const tableScroll = ref<HTMLElement | null>(null)
const { revealRows } = usePageMotion(root)
const tenantId = computed(() => {
  const value = String(route.query.tenantId || '')
  return /^[1-9]\d*$/.test(value) ? value : ''
})
const rows = ref<TenantRow[]>([])
const loading = ref(false)
const loaded = ref(false)
const error = ref('')
const keyword = ref('')
const page = ref(1)
const pageSize = ref(20)
const showAllNames = ref(false)
const revealedNames = ref(new Set<string>())
const expandedNames = ref(new Set<string>())
const selected = ref<TenantRow | null>(null)
const action = ref('')
const updatedAt = ref('')
const syncTenant = ref<TenantRow | null>(null)
const syncState = ref<'idle' | 'running' | 'success' | 'error'>('idle')
const syncMessage = ref('')
let listRequest = 0
let syncRequest = 0
let listController: AbortController | undefined
let syncController: AbortController | undefined
let restoreFocus: HTMLElement | null = null
let disposed = false

const filteredRows = computed(() => {
  const query = keyword.value.trim().toLocaleLowerCase()
  if (!query) return rows.value
  return rows.value.filter((row) => [row.region, row.regionEn, row.defName, row.tenancyName]
    .some((value) => String(value || '').toLocaleLowerCase().includes(query)))
})
const visibleRows = computed(() => filteredRows.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
const rangeStart = computed(() => filteredRows.value.length ? (page.value - 1) * pageSize.value + 1 : 0)
const rangeEnd = computed(() => Math.min(page.value * pageSize.value, filteredRows.value.length))

function cloudType(row: TenantRow) {
  return Number(row.cloudType ?? route.query.cloudType ?? shell.cloudType)
}
function maskName(value?: string) {
  if (!value) return '未命名'
  return value.length > 2 ? `${value[0]}***${value.at(-1)}` : '***'
}
function nameVisible(row: TenantRow) {
  return showAllNames.value !== revealedNames.value.has(row.id)
}
function toggleName(row: TenantRow) {
  const next = new Set(revealedNames.value)
  if (next.has(row.id)) next.delete(row.id)
  else next.add(row.id)
  revealedNames.value = next
}
function toggleNames() {
  showAllNames.value = !showAllNames.value
  revealedNames.value = new Set()
}
function toggleCustomName(row: TenantRow) {
  const next = new Set(expandedNames.value)
  if (next.has(row.id)) next.delete(row.id)
  else next.add(row.id)
  expandedNames.value = next
}
function createdAt(row: TenantRow) {
  const value = row.createdAtStr || row.createdAt
  if (!value) return '—'
  if (Array.isArray(value)) return `${value[0]}-${String(value[1]).padStart(2, '0')}-${String(value[2]).padStart(2, '0')} ${String(value[3] || 0).padStart(2, '0')}:${String(value[4] || 0).padStart(2, '0')}`
  return String(value).replace('T', ' ').split('.')[0]
}
function goBack() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && /^\/tenants\/list(?:\?|$)/.test(previous)) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: String(route.query.cloudType || shell.cloudType) } })
}
function navigate(path: string, row?: TenantRow) {
  void router.push({ path, query: {
    cloudType: String(row ? cloudType(row) : route.query.cloudType || shell.cloudType),
    ...(row ? { tenantId: row.id } : {}),
  } })
}
function importApi() { navigate('/tenants/addSpeed') }
function viewInstances(row: TenantRow) { navigate(cloudType(row) === 2 ? '/other/instances/list' : '/oci/list', row) }
async function load() {
  const request = ++listRequest
  listController?.abort()
  error.value = ''
  if (!tenantId.value) {
    rows.value = []
    loading.value = false
    loaded.value = false
    error.value = '请先从租户管理中选择一个账号，再查看它的区域。'
    return
  }
  listController = new AbortController()
  loading.value = true
  try {
    const result = await tenantGet<Record<string, any>[]>('/tenants/regionList/json', { tenantId: tenantId.value }, { signal: listController.signal })
    if (disposed || request !== listRequest) return
    if (!Array.isArray(result)) throw new Error('未能读取区域列表，请重新登录或重试。')
    rows.value = result.map((row) => {
      if (!row || typeof row !== 'object' || (!row.idStr && typeof row.id === 'number' && !Number.isSafeInteger(row.id))) {
        throw new Error('区域账号标识不完整，请更新服务端后重试。')
      }
      const id = String(row.idStr || row.id || '')
      if (!/^[1-9]\d*$/.test(id)) throw new Error('区域账号标识不完整，请刷新后重试。')
      return { ...row, id } as TenantRow
    })
    loaded.value = true
    page.value = Math.min(page.value, Math.max(1, Math.ceil(filteredRows.value.length / pageSize.value)))
    updatedAt.value = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    await nextTick()
    if (!disposed && request === listRequest) revealRows()
  } catch (cause) {
    if (!disposed && request === listRequest && !isCancel(cause)) error.value = tenantError(cause)
  } finally {
    if (!disposed && request === listRequest) loading.value = false
  }
}
function clearSearch() {
  keyword.value = ''
  searchInput.value?.focus()
}
function search() { page.value = 1 }
function changePage(value: number) { page.value = value }
function changePageSize(value: number) {
  pageSize.value = value
  page.value = 1
}

interface RegionAction { id: string; label: string; icon: string; path?: string }
function rowActions(row: TenantRow): RegionAction[] {
  if (cloudType(row) === 2) return [
    { id: 'boot', label: '添加开机', icon: 'i-mdi-plus-circle-outline', path: '/tenants/gcpBootPage' },
    { id: 'sync', label: '同步', icon: 'i-mdi-sync' },
  ]
  if (cloudType(row) !== 1) return []
  const items: RegionAction[] = []
  if (Number(row.supportAI) === 1) items.push({ id: 'chat', label: 'AI 对话', icon: 'i-mdi-brain', path: '/ai/chat' })
  items.push(
    { id: 'sync', label: '同步', icon: 'i-mdi-sync' },
    { id: 'boot', label: '添加开机', icon: 'i-mdi-plus-circle-outline', path: '/tenants/bootPage' },
    { id: 'tasks', label: '查看开机', icon: 'i-mdi-play-circle-outline', path: '/boot/fullBootList' },
    { id: 'volumes', label: '引导卷管理', icon: 'i-mdi-harddisk' },
    { id: 'security', label: '安全规则', icon: 'i-mdi-shield-check-outline' },
    { id: 'instances', label: '实例列表', icon: 'i-mdi-server', path: '/oci/list' },
    { id: 'mysql', label: 'MySQL 管理', icon: 'i-mdi-database-outline' },
  )
  return items
}
function runAction(item: RegionAction, row: TenantRow) {
  if (item.path) navigate(item.path, row)
  else if (item.id === 'sync') void startSync(row)
  else {
    restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
    selected.value = row
    action.value = item.id
  }
}
function restoreActionFocus() {
  void nextTick(() => {
    if (disposed) return
    if (restoreFocus?.isConnected) restoreFocus.focus({ preventScroll: true })
    else tableScroll.value?.focus({ preventScroll: true })
    restoreFocus = null
  })
}
function closeAction() {
  action.value = ''
  selected.value = null
  restoreActionFocus()
}
async function startSync(row: TenantRow) {
  if (syncState.value === 'running') return
  restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
  syncTenant.value = row
  syncState.value = 'running'
  syncMessage.value = '正在同步这个区域的云端资源，请稍候…'
  const request = ++syncRequest
  syncController?.abort()
  syncController = new AbortController()
  try {
    const result = await tenantGet<{ status: string; message?: string }>('/tenants/syncOci', { tenantId: row.id }, { signal: syncController.signal, timeout: 180000 })
    if (disposed || request !== syncRequest) return
    if (result?.status !== 'success') throw new Error(result?.message || '未收到同步完成的响应，请刷新列表确认结果。')
    syncState.value = 'success'
    syncMessage.value = '同步完成，已刷新区域列表。'
    await load()
    if (!disposed && request === syncRequest && error.value) syncMessage.value = '同步已完成，列表刷新失败；关闭后可重新刷新。'
  } catch (cause) {
    if (disposed || request !== syncRequest || isCancel(cause)) return
    syncState.value = 'error'
    syncMessage.value = (cause as { code?: string }).code === 'ECONNABORTED'
      ? '等待响应超时，云端同步可能仍在进行。请稍后刷新列表确认结果。'
      : tenantError(cause)
  }
}
function closeSync() {
  if (syncState.value === 'running') return
  syncTenant.value = null
  syncState.value = 'idle'
  restoreActionFocus()
}
function handleShortcut(event: KeyboardEvent) {
  if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey || action.value || syncTenant.value) return
  const target = event.target as HTMLElement | null
  if (target?.closest('input, textarea, select, [contenteditable="true"], [role="dialog"]')) return
  event.preventDefault()
  searchInput.value?.focus()
}
watch(keyword, () => { page.value = 1 })
watch([page, pageSize, keyword], () => {
  if (tableScroll.value) tableScroll.value.scrollTop = 0
  revealRows()
}, { flush: 'post' })
watch(tenantId, () => {
  syncRequest++
  syncController?.abort()
  syncTenant.value = null
  syncState.value = 'idle'
  selected.value = null
  action.value = ''
  rows.value = []
  loaded.value = false
  keyword.value = ''
  page.value = 1
  showAllNames.value = false
  revealedNames.value = new Set()
  expandedNames.value = new Set()
  updatedAt.value = ''
  void load()
})
onMounted(() => {
  void load()
  document.addEventListener('keydown', handleShortcut)
})
onBeforeUnmount(() => {
  disposed = true
  listRequest++
  syncRequest++
  listController?.abort()
  syncController?.abort()
  document.removeEventListener('keydown', handleShortcut)
})
</script>

<template>
  <div ref="root" class="tenants-page tenant-regions-page">
    <section class="tenant-card" aria-label="租户区域列表" :aria-busy="loading" data-motion-enter>
      <div class="list-toolbar">
        <button type="button" class="toolbar-button region-back" title="返回租户管理" aria-label="返回租户管理" @click="goBack"><i class="i-mdi-arrow-left" aria-hidden="true" /></button>
        <form class="tenant-search" role="search" @submit.prevent="search">
          <i class="i-mdi-magnify" aria-hidden="true" />
          <input ref="searchInput" v-model="keyword" aria-label="搜索区域或账号名称" placeholder="搜索区域或账号名称…" autocomplete="off" @keydown.esc.prevent="clearSearch" />
          <button v-if="keyword" type="button" aria-label="清除搜索" @click="clearSearch"><i class="i-mdi-close-circle" aria-hidden="true" /></button>
          <kbd v-else aria-hidden="true">/</kbd>
        </form>
        <div class="toolbar-actions">
          <button type="button" class="toolbar-button privacy-toggle" :aria-pressed="showAllNames" :title="showAllNames ? '隐藏全部租户名称' : '显示全部租户名称'" :aria-label="showAllNames ? '隐藏全部租户名称' : '显示全部租户名称'" @click="toggleNames"><i :class="showAllNames ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /></button>
          <button type="button" class="toolbar-button" :disabled="loading || !tenantId" :title="updatedAt ? `刷新，上次更新 ${updatedAt}` : '刷新区域列表'" aria-label="刷新区域列表" @click="load"><i class="i-mdi-refresh" :class="{ 'region-spinning': loading }" aria-hidden="true" /></button>
          <PrimaryBtn class="tenant-import" @click="importApi"><i class="i-mdi-plus" aria-hidden="true" />API 导入</PrimaryBtn>
        </div>
      </div>
      <div v-if="error" class="list-error" role="alert">
        <i class="i-mdi-alert-circle-outline" aria-hidden="true" /><div>{{ error }}</div>
        <GhostBtn v-if="tenantId" :disabled="loading" @click="load">重试</GhostBtn>
        <GhostBtn v-else @click="goBack">返回租户</GhostBtn>
      </div>
      <div class="table-stage">
        <div v-if="loading && loaded" class="refresh-track" aria-hidden="true"><span /></div>
        <div ref="tableScroll" class="table-scroll" tabindex="0" aria-label="租户区域表格，可横向滚动">
          <table class="tenant-table">
            <thead><tr>
              <th scope="col" class="region-index">序号</th>
              <th scope="col" class="identity-column">租户 / 自定义名称</th>
              <th scope="col">区域</th>
              <th scope="col">开机任务</th>
              <th scope="col">主区域</th>
              <th scope="col">同步状态</th>
              <th scope="col">创建时间</th>
              <th scope="col" class="row-actions-column">操作</th>
            </tr></thead>
            <tbody v-if="!loaded && loading" aria-hidden="true"><tr v-for="n in 6" :key="n" class="skeleton-row"><td v-for="column in 8" :key="column"><span class="skeleton" /></td></tr></tbody>
            <tbody v-else>
              <tr v-for="(row, index) in visibleRows" :key="`${row.id}-${index}`" data-motion-row>
                <td class="region-index">{{ rangeStart + index }}</td>
                <td>
                  <button type="button" class="edit-name region-custom-name" :class="{ 'is-expanded': expandedNames.has(row.id) }" :title="row.defName || '未设置自定义名称'" :aria-expanded="expandedNames.has(row.id)" @click="toggleCustomName(row)">{{ row.defName || '未设置名称' }}</button>
                  <button type="button" class="private-name" :aria-label="nameVisible(row) ? '隐藏租户名称' : '显示租户名称'" @click="toggleName(row)"><i :class="nameVisible(row) ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /><span>{{ nameVisible(row) ? row.tenancyName || '未命名' : maskName(row.tenancyName) }}</span></button>
                </td>
                <td>
                  <button v-if="[1, 2].includes(cloudType(row))" type="button" class="cell-link region-name" :title="`查看 ${row.region || row.regionEn || '这个区域'} 的实例`" @click="viewInstances(row)">{{ row.region || row.regionEn || '未记录区域' }}</button>
                  <span v-else class="region-name">{{ row.region || row.regionEn || '—' }}</span>
                  <span v-if="row.regionEn && row.regionEn !== row.region" class="cell-secondary">{{ row.regionEn }}</span>
                </td>
                <td><span class="task-state" :class="{ 'task-running': row.openBootFlag }"><i :class="row.openBootFlag ? 'i-mdi-play-circle-outline' : 'i-mdi-minus-circle-outline'" aria-hidden="true" />{{ row.openBootFlag ? '开机中' : '暂无任务' }}</span></td>
                <td><span :class="row.isHomeRegion ? 'region-home' : 'cell-secondary'">{{ row.isHomeRegion ? '主区域' : '否' }}</span></td>
                <td><span class="region-sync-state" :class="{ 'is-synced': row.apiSynced }"><i :class="row.apiSynced ? 'i-mdi-check-circle-outline' : 'i-mdi-minus-circle-outline'" aria-hidden="true" />{{ row.apiSynced ? '已同步' : '未同步' }}</span></td>
                <td class="created-at">{{ createdAt(row) }}</td>
                <td class="row-actions-column">
                  <div v-if="rowActions(row).length" class="row-actions">
                    <button type="button" class="more-button" title="同步区域资源" aria-label="同步区域资源" :disabled="syncState === 'running'" @click="startSync(row)"><i class="i-mdi-sync" aria-hidden="true" /></button>
                    <el-dropdown trigger="click" placement="bottom-end" popper-class="tenant-action-menu" :show-timeout="0" :hide-timeout="80" @command="(item: RegionAction) => runAction(item, row)">
                      <button type="button" class="more-button" title="更多区域操作" aria-label="更多区域操作"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
                      <template #dropdown><el-dropdown-menu><el-dropdown-item v-for="item in rowActions(row)" :key="item.id" :command="item"><i :class="item.icon" aria-hidden="true" /><span>{{ item.label }}</span></el-dropdown-item></el-dropdown-menu></template>
                    </el-dropdown>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
          <div v-if="!loading && !filteredRows.length && !error" class="tenant-empty" role="status">
            <span class="empty-icon"><i :class="keyword.trim() ? 'i-mdi-magnify' : 'i-mdi-earth'" aria-hidden="true" /></span>
            <h3>{{ keyword.trim() ? '没有找到匹配的区域' : '暂无区域记录' }}</h3>
            <p>{{ keyword.trim() ? '试试其他区域名称，或清除搜索查看全部区域。' : '这个账号暂时没有可显示的区域，请返回租户管理检查账号。' }}</p>
            <GhostBtn v-if="keyword.trim()" @click="clearSearch">清除搜索</GhostBtn><GhostBtn v-else @click="goBack">返回租户管理</GhostBtn>
          </div>
        </div>
      </div>
      <footer class="list-footer">
        <p aria-live="polite">{{ loading && !loaded ? '正在读取区域…' : `显示 ${rangeStart}–${rangeEnd}，共 ${filteredRows.length} 个区域` }}</p>
        <el-pagination background :current-page="page" :page-size="pageSize" :total="filteredRows.length" :page-sizes="[10, 20, 50, 100]" :pager-count="5" layout="sizes, prev, pager, next" @current-change="changePage" @size-change="changePageSize" />
      </footer>
    </section>
    <TenantRegionSecurityDialog v-if="action === 'security' && selected" :key="selected.id" :tenant="selected" @close="closeAction" @changed="load" />
    <TenantRegionVolumesDialog v-if="action === 'volumes' && selected" :key="selected.id" :tenant="selected" @close="closeAction" @changed="load" />
    <TenantRegionMysqlDialog v-if="action === 'mysql' && selected" :key="selected.id" :tenant="selected" @close="closeAction" @changed="load" />
    <el-dialog :model-value="Boolean(syncTenant)" title="同步区域资源" width="min(420px, calc(100vw - 32px))" class="tenant-region-sync-dialog" :close-on-click-modal="false" :close-on-press-escape="syncState !== 'running'" :show-close="syncState !== 'running'" @close="closeSync">
      <div class="region-sync-content" role="status" aria-live="polite">
        <i :class="syncState === 'running' ? 'i-mdi-loading region-spinning' : syncState === 'success' ? 'i-mdi-check-circle-outline' : 'i-mdi-alert-circle-outline'" class="sync-icon" aria-hidden="true" />
        <div><strong>{{ syncTenant?.region || syncTenant?.regionEn || '当前区域' }}</strong><p>{{ syncMessage }}</p></div>
      </div>
      <template #footer><GhostBtn :disabled="syncState === 'running'" @click="closeSync">{{ syncState === 'running' ? '同步中…' : '关闭' }}</GhostBtn></template>
    </el-dialog>
  </div>
</template>

<style scoped>
.tenant-regions-page .region-back { flex-shrink: 0; }
.tenant-regions-page .region-index { width: 60px; color: var(--text-muted); font-variant-numeric: tabular-nums; }
.tenant-regions-page .identity-column { width: 210px; min-width: 210px; }
.tenant-regions-page .region-custom-name.is-expanded { max-width: 260px; white-space: normal; overflow-wrap: anywhere; }
.region-home { color: var(--brand); font-size: 12px; }
.region-sync-state { display: inline-flex; align-items: center; gap: 5px; color: var(--text-secondary); font-size: 12px; white-space: nowrap; }
.region-sync-state.is-synced { color: var(--brand); }
.region-sync-content { display: flex; align-items: flex-start; gap: 14px; padding: 8px 0; }
.region-sync-content .sync-icon { flex: none; margin-top: 2px; color: var(--brand); font-size: 25px; }
.region-sync-content strong { font-weight: 600; }
.region-sync-content p { margin: 8px 0 0; color: var(--text-secondary); font-size: 13px; line-height: 1.7; overflow-wrap: anywhere; }
.region-spinning { animation: region-spin 900ms linear infinite; }
@keyframes region-spin { to { transform: rotate(360deg); } }
@media (max-width: 700px) { .tenant-regions-page .tenant-search { flex: 1 1 160px; width: auto; } }
@media (prefers-reduced-motion: reduce) { .region-spinning { animation: none; } }
</style>
