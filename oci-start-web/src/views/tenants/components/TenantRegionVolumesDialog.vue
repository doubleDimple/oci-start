<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { ElMessage, ElMessageBox, type TableInstance } from 'element-plus'
import { tenantCsrfToken, tenantError, tenantGet, tenantPut, type TenantRow } from '@/api/tenant'
import request from '@/api/request'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'

interface BootVolume {
  id: string
  displayName: string
  instanceName?: string | null
  sizeInGBs?: number | null
  vpusPerGB?: number | null
}

const props = defineProps<{ tenant: TenantRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const tenantId = computed(() => String(props.tenant.id))
const tenantName = computed(() => props.tenant.defName || '当前租户')
const heading = ref<HTMLElement>()
const table = ref<TableInstance>()
const volumes = ref<BootVolume[]>([])
const loading = ref(false)
const busy = ref<'save' | 'delete' | ''>('')
const deletingId = ref('')
const error = ref('')
const keyword = ref('')
const page = ref(1)
const pageSize = ref(10)
const editing = ref<BootVolume | null>(null)
const editName = ref('')
const editVpus = ref(10)
const originalVpus = ref(10)
const editError = ref('')
const filteredVolumes = computed(() => {
  const search = keyword.value.trim().toLowerCase()
  return search ? volumes.value.filter(volume => `${volume.displayName || ''} ${volume.instanceName || ''}`.toLowerCase().includes(search)) : volumes.value
})
const pageVolumes = computed(() => filteredVolumes.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
const orphanCount = computed(() => volumes.value.filter(volume => !volume.instanceName).length)
const minimumVpus = computed(() => Math.min(10, originalVpus.value))
let generation = 0
let readController = new AbortController()

function close() {
  if (busy.value) return
  generation++
  readController.abort()
  emit('close')
}

function resetSize() {
  const dialog = heading.value?.closest<HTMLElement>('.tenant-region-volumes-dialog')
  if (!dialog) return
  dialog.style.removeProperty('width')
  dialog.style.removeProperty('height')
}

function clampPage() {
  page.value = Math.max(1, Math.min(page.value, Math.ceil(filteredVolumes.value.length / pageSize.value)))
}

async function loadVolumes() {
  if (loading.value || busy.value) return
  const current = generation
  const id = tenantId.value
  loading.value = true
  error.value = ''
  try {
    const result = await tenantGet<BootVolume[]>('/tenants/boot-volumes', { tenantId: id }, { signal: readController.signal, timeout: 120000 })
    if (current !== generation) return
    if (!Array.isArray(result)) throw new Error('引导卷数据格式异常，请重新加载')
    volumes.value = result
    clampPage()
  } catch (cause) {
    if (current === generation) error.value = tenantError(cause)
  } finally {
    if (current === generation) loading.value = false
  }
}

function startEditing(volume: BootVolume) {
  if (busy.value || loading.value) return
  editing.value = volume
  editName.value = volume.displayName || ''
  const performance = Number(volume.vpusPerGB ?? 10)
  originalVpus.value = Number.isFinite(performance) ? performance : 10
  // Retain a server-provided zero; changing only the name must not increase performance.
  editVpus.value = originalVpus.value
  editError.value = ''
}

function cancelEditing() {
  if (!busy.value) editing.value = null
}

async function saveVolume() {
  const volume = editing.value
  if (!volume || busy.value) return
  editError.value = ''
  const name = editName.value.trim()
  if (!name) { editError.value = '请输入引导卷名称'; return }
  const displayName = name === volume.displayName ? '' : name
  const vpusPerGB = editVpus.value === originalVpus.value ? -1 : editVpus.value
  if (vpusPerGB !== -1 && (!Number.isInteger(vpusPerGB) || vpusPerGB < minimumVpus.value || vpusPerGB > 120 || vpusPerGB % 10 !== 0)) {
    editError.value = `性能值应为 ${minimumVpus.value} 至 120 之间的 10 的倍数`
    return
  }
  if (!displayName && vpusPerGB === -1) { editing.value = null; return }
  const current = generation
  const id = tenantId.value
  busy.value = 'save'
  try {
    const result = await tenantPut<{ success: boolean; message?: string }>(`/tenants/update-volumes/${encodeURIComponent(volume.id)}`, {
      tenantId: id, displayName, vpusPerGB,
    }, { timeout: 120000 })
    if (current !== generation) return
    if (!result?.success) throw new Error(result?.message || '引导卷更新失败')
    if (displayName) volume.displayName = displayName
    if (vpusPerGB !== -1) volume.vpusPerGB = vpusPerGB
    editing.value = null
    clampPage()
    ElMessage.success('引导卷已更新')
    emit('changed')
  } catch (cause) {
    if (current === generation) editError.value = tenantError(cause)
  } finally {
    if (current === generation) busy.value = ''
  }
}

async function deleteVolume(volume: BootVolume) {
  if (volume.instanceName || busy.value || loading.value) return
  const current = generation
  const id = tenantId.value
  const volumeId = volume.id
  busy.value = 'delete'
  deletingId.value = volumeId
  error.value = ''
  try {
    await ElMessageBox.confirm(`确认删除引导卷“${volume.displayName || volumeId}”？删除后，卷内数据将无法恢复。`, '删除引导卷', {
      type: 'warning', confirmButtonText: '确认删除', cancelButtonText: '取消', closeOnClickModal: false,
      confirmButtonClass: 'tenant-region-volume-delete-confirm',
    })
    if (current !== generation) return
    const csrfHeader = document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN'
    const result: unknown = await request.request({
      method: 'DELETE', url: `/tenants/delete-volume/${encodeURIComponent(volumeId)}`,
      data: { tenantId: id }, headers: { 'Content-Type': 'application/json', [csrfHeader]: tenantCsrfToken() },
      timeout: 120000, silent: true,
    })
    if (current !== generation) return
    const response = result as { success?: boolean; message?: string }
    if (!response?.success) throw new Error(response?.message || '引导卷删除失败')
    volumes.value = volumes.value.filter(item => item.id !== volumeId)
    clampPage()
    ElMessage.success('引导卷已删除')
    emit('changed')
  } catch (cause) {
    if (current === generation && cause !== 'cancel' && cause !== 'close') error.value = tenantError(cause)
  } finally {
    if (current === generation) { busy.value = ''; deletingId.value = '' }
  }
}

watch([keyword, pageSize], () => { page.value = 1 })
watch(page, async () => { await nextTick(); table.value?.setScrollTop(0) })
watch(tenantId, () => {
  generation++
  readController.abort()
  readController = new AbortController()
  loading.value = false
  busy.value = ''
  deletingId.value = ''
  error.value = ''
  editing.value = null
  keyword.value = ''
  page.value = 1
  volumes.value = []
  void loadVolumes()
}, { immediate: true })
onBeforeUnmount(() => { generation++; readController.abort() })
</script>

<template>
  <el-dialog :model-value="true" title="引导卷管理" width="min(960px, calc(100vw - 32px))" class="tenant-region-volumes-dialog" align-center append-to-body :close-on-click-modal="false" :close-on-press-escape="!busy" :show-close="!busy" @close="close">
    <template #header="{ titleId }">
      <div ref="heading" class="volume-heading"><span :id="titleId" class="volume-title">引导卷管理</span><span class="volume-context">{{ tenantName }}<span v-if="tenant.region"> · {{ tenant.region }}</span></span></div>
    </template>

    <Transition name="region-volume-switch" mode="out-in">
      <section v-if="!editing" key="list" class="volume-list" :aria-busy="loading || !!busy">
        <div class="volume-toolbar">
          <el-input v-model="keyword" class="volume-search" placeholder="搜索引导卷或实例" clearable :disabled="loading || !!busy" aria-label="搜索引导卷或实例"><template #prefix><span class="i-mdi-magnify" aria-hidden="true" /></template></el-input>
          <div class="volume-toolbar-actions"><span v-if="!loading" class="volume-count">{{ volumes.length }} 块卷<span v-if="orphanCount"> · {{ orphanCount }} 块未关联</span></span><GhostBtn :loading="loading" :disabled="!!busy" @click="loadVolumes"><span class="i-mdi-refresh" aria-hidden="true" />刷新</GhostBtn></div>
        </div>
        <el-alert v-if="error" :title="error" type="error" :closable="false" show-icon class="volume-alert" />
        <div class="volume-table-wrap">
          <el-table ref="table" v-loading="loading" :data="pageVolumes" row-key="id" height="100%" class="volume-table" :empty-text="loading ? '正在读取引导卷…' : error ? '暂时无法读取引导卷，请重试' : keyword ? '未找到匹配的引导卷' : '当前区域暂无引导卷'">
            <el-table-column label="关联实例" min-width="165" show-overflow-tooltip><template #default="{ row }"><span v-if="row.instanceName">{{ row.instanceName }}</span><span v-else class="unattached"><span />未关联实例</span></template></el-table-column>
            <el-table-column prop="displayName" label="引导卷名称" min-width="225" show-overflow-tooltip />
            <el-table-column label="容量 (GB)" width="116" align="right"><template #default="{ row }"><span class="volume-number">{{ row.sizeInGBs ?? '—' }}</span></template></el-table-column>
            <el-table-column label="VPUs/GB" width="110" align="right"><template #default="{ row }"><span class="volume-number">{{ row.vpusPerGB ?? '—' }}</span></template></el-table-column>
            <el-table-column label="操作" width="144" fixed="right"><template #default="{ row }"><div class="volume-row-actions"><el-button link :disabled="loading || !!busy" @click="startEditing(row)">修改</el-button><el-button v-if="!row.instanceName" link type="danger" :loading="busy === 'delete' && deletingId === row.id" :disabled="loading || !!busy" @click="deleteVolume(row)">删除</el-button></div></template></el-table-column>
          </el-table>
        </div>
        <div class="volume-pagination"><span class="volume-count">共 {{ filteredVolumes.length }} 块引导卷</span><el-pagination v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50]" :total="filteredVolumes.length" :disabled="loading || !!busy" :pager-count="5" layout="sizes, prev, pager, next" /></div>
      </section>

      <section v-else key="editor" class="volume-editor" aria-label="修改引导卷">
        <button class="volume-back" type="button" :disabled="!!busy" @click="cancelEditing"><span aria-hidden="true">←</span> 返回引导卷列表</button>
        <div class="volume-editor-intro"><h3>调整名称与性能</h3><p>{{ editing.instanceName || '未关联实例' }}<span> · {{ editing.sizeInGBs ?? '—' }} GB</span></p></div>
        <el-form label-position="top" :disabled="!!busy" @submit.prevent="saveVolume">
          <el-form-item label="引导卷名称" required><el-input v-model="editName" placeholder="输入便于识别的名称" /></el-form-item>
          <div class="volume-performance"><div class="performance-heading"><label id="region-volume-performance-label">性能 · VPUs/GB</label><strong>{{ editVpus }}</strong></div><el-slider v-model="editVpus" :min="minimumVpus" :max="120" :step="10" aria-labelledby="region-volume-performance-label" /><div class="performance-scale"><span>{{ minimumVpus }} VPUs/GB</span><span>120 VPUs/GB</span></div></div>
          <el-alert v-if="editError" :title="editError" type="error" :closable="false" show-icon class="volume-alert" />
          <div class="volume-edit-actions"><GhostBtn :disabled="!!busy" @click="cancelEditing">取消</GhostBtn><PrimaryBtn :loading="busy === 'save'" :disabled="!!busy && busy !== 'save'" @click="saveVolume">确认修改</PrimaryBtn></div>
        </el-form>
      </section>
    </Transition>

    <template #footer><div class="volume-footer"><button type="button" class="volume-reset" :disabled="!!busy" @click="resetSize"><span class="i-mdi-arrow-expand-all" aria-hidden="true" />恢复窗口大小</button><GhostBtn :disabled="!!busy" @click="close">关闭</GhostBtn></div></template>
  </el-dialog>
</template>

<style scoped>
:global(.tenant-region-volumes-dialog) { display: flex; flex-direction: column; height: min(80dvh, 760px); min-height: min(480px, calc(100dvh - 32px)); min-width: min(360px, calc(100vw - 32px)); max-height: calc(100dvh - 32px); max-width: calc(100vw - 32px); overflow: hidden; resize: both; padding: 26px; }
:global(.tenant-region-volumes-dialog .el-dialog__body) { display: flex; flex-direction: column; flex: 1; min-height: 0; overflow: auto; }
:global(.tenant-region-volumes-dialog .el-dialog__header) { padding-bottom: 12px; }
:global(.tenant-region-volumes-dialog .el-dialog__footer) { flex-shrink: 0; padding-top: 18px; }
:global(.tenant-region-volume-delete-confirm) { --el-button-bg-color: var(--status-danger); --el-button-border-color: var(--status-danger); --el-button-hover-bg-color: var(--status-danger); --el-button-hover-border-color: var(--status-danger); }
.volume-heading { display: flex; align-items: baseline; gap: 12px; padding-right: 28px; }
.volume-title { flex-shrink: 0; font-size: 18px; font-weight: 600; line-height: 1.4; }
.volume-context { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12px; color: var(--text-secondary); }
.volume-list { display: flex; flex-direction: column; flex: 1; min-height: 240px; }
.volume-toolbar, .volume-toolbar-actions, .volume-pagination, .volume-footer, .volume-row-actions { display: flex; align-items: center; }
.volume-toolbar { gap: 12px; justify-content: space-between; margin-bottom: 12px; }
.volume-search { width: 270px; max-width: 100%; }
.volume-toolbar-actions { gap: 14px; }
.volume-count { color: var(--text-secondary); font-size: 12px; white-space: nowrap; }
.volume-table-wrap { flex: 1; min-height: 150px; overflow: hidden; border: 1px solid var(--border); border-radius: 14px; }
.volume-table { font-family: var(--sans); }
.volume-table :deep(th.el-table__cell) { background: var(--bg-search); color: var(--text-secondary); font-size: 12px; font-weight: 500; }
.volume-table :deep(td.el-table__cell) { height: 52px; padding-block: 8px; font-size: 13px; }
.volume-table :deep(.el-table__inner-wrapper::before) { display: none; }
.volume-row-actions { gap: 16px; }
.volume-row-actions :deep(.el-button + .el-button) { margin-left: 0; }
.volume-number { font-variant-numeric: tabular-nums; }
.unattached { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; color: var(--text-secondary); }
.unattached > span { width: 5px; height: 5px; border-radius: 50%; background: var(--status-warn); }
.volume-pagination { justify-content: space-between; gap: 12px; padding-top: 18px; }
.volume-pagination :deep(.el-pagination) { --el-pagination-font-size: 12px; flex-wrap: wrap; justify-content: flex-end; }
.volume-alert { margin-bottom: 16px; flex-shrink: 0; }
.volume-editor { width: min(100%, 580px); margin: 0 auto; padding: 4px 0 16px; color: var(--text-primary); }
.volume-back, .volume-reset { display: inline-flex; align-items: center; gap: 7px; border: 0; padding: 0; background: transparent; font: inherit; font-size: 12px; color: var(--text-secondary); cursor: pointer; }
.volume-back { padding: 8px 0; }
.volume-back:hover, .volume-reset:hover { color: var(--text-primary); }
.volume-back:focus-visible, .volume-reset:focus-visible { outline: 2px solid var(--brand); outline-offset: 4px; border-radius: 4px; }
.volume-back:disabled, .volume-reset:disabled { opacity: .5; cursor: default; }
.volume-editor-intro { margin: 18px 0 24px; }
.volume-editor-intro h3 { margin: 0 0 8px; font-size: 21px; font-weight: 600; }
.volume-editor-intro p { margin: 0; color: var(--text-secondary); font-size: 12px; }
.volume-editor :deep(.el-form-item__label) { font-size: 12px; color: var(--text-secondary); }
.volume-editor :deep(.el-input__wrapper) { min-height: 42px; border-radius: 12px; }
.volume-performance { padding: 20px 24px; margin: 22px 0; background: var(--bg-search); border-radius: 16px; }
.performance-heading { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.performance-heading label { font-size: 12px; color: var(--text-secondary); }
.performance-heading strong { font-size: 25px; font-weight: 600; font-variant-numeric: tabular-nums; }
.performance-scale { display: flex; justify-content: space-between; margin-top: 2px; color: var(--text-muted); font-size: 11px; }
.volume-edit-actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; }
.volume-footer { justify-content: space-between; gap: 16px; }
.region-volume-switch-enter-active { transition: opacity .18s ease, transform .22s cubic-bezier(.22, 1, .36, 1); }
.region-volume-switch-leave-active { transition: opacity .12s ease; }
.region-volume-switch-enter-from { opacity: 0; transform: translateY(6px); }
.region-volume-switch-leave-to { opacity: 0; }
@media (max-width: 640px) {
  :global(.tenant-region-volumes-dialog) { padding: 20px; resize: none; }
  .volume-toolbar { align-items: stretch; flex-direction: column; gap: 12px; }
  .volume-search { width: 100%; }
  .volume-toolbar-actions { justify-content: space-between; }
  .volume-pagination { align-items: flex-start; flex-direction: column; }
  .volume-pagination :deep(.el-pagination) { max-width: 100%; justify-content: flex-start; }
  .volume-pagination :deep(.el-pagination__sizes) { margin-right: 4px; }
  .volume-pagination :deep(.el-select) { width: 98px; }
  .volume-pagination :deep(.btn-prev), .volume-pagination :deep(.btn-next), .volume-pagination :deep(.el-pager li) { min-width: 24px; }
}
@media (prefers-reduced-motion: reduce) {
  .region-volume-switch-enter-active, .region-volume-switch-leave-active { transition: none; }
  .region-volume-switch-enter-from { transform: none; }
}
</style>
