<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { isCancel } from 'axios'
import { ElMessage } from 'element-plus'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import {
  getGcpInstances, runGcpInstanceAction, isGcpTenantId, gcpInstancesServerError,
  GcpInstancesResponseError, type GcpInstanceRow, type GcpInstanceAction, type GcpInstancePage,
} from '@/api/gcpInstances'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const rows = ref<GcpInstanceRow[]>([])
const total = ref(0)
const loading = ref(false)
const loaded = ref(false)
const listError = ref<unknown>(null)
const updatedAt = ref<Date | null>(null)
const revealed = ref(new Set<string>())
const compactViewport = ref(false)
let viewportQuery: MediaQueryList | undefined
function updateViewport() { compactViewport.value = viewportQuery?.matches ?? false }
const pageSizes = [10, 20, 50, 100]
const tenantId = computed(() => route.query.tenantId == null ? '0' : typeof route.query.tenantId === 'string' ? route.query.tenantId : '')
const cloudType = computed(() => route.query.cloudType == null ? 2 : typeof route.query.cloudType === 'string' ? Number(route.query.cloudType) : NaN)
const invalidScope = computed(() => !isGcpTenantId(tenantId.value) || ![2, 3, 4].includes(cloudType.value))
const page = computed(() => {
  const value = Number(route.query.page ?? 0)
  return Number.isSafeInteger(value) && value >= 0 && value <= 2147483646 ? value : 0
})
const size = computed(() => pageSizes.includes(Number(route.query.size)) ? Number(route.query.size) : 20)
const scopeKey = computed(() => JSON.stringify([route.path, route.query.tenantId, route.query.cloudType]))
const queryKey = computed(() => JSON.stringify([scopeKey.value, page.value, size.value]))
const scopeLabel = computed(() => tenantId.value === '0' ? t('gcpInstances.allTenants') : t('gcpInstances.tenantScope', { id: tenantId.value }))
const refreshTime = computed(() => updatedAt.value ? t('gcpInstances.lastUpdated', {
  time: new Intl.DateTimeFormat(locale.value, { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(updatedAt.value),
}) : '')
const range = computed(() => t('gcpInstances.range', {
  start: number(rows.value.length ? page.value * size.value + 1 : 0),
  end: number(rows.value.length ? page.value * size.value + rows.value.length : 0), total: number(total.value),
}))

interface Operation {
  action: GcpInstanceAction
  row: GcpInstanceRow
  scope: string
  stage: 'confirm' | 'pending' | 'result'
  acknowledged: boolean
  responded: boolean
  error: unknown
  reread: boolean
  readFailed: boolean
  current: GcpInstanceRow | null
}
const operation = ref<Operation | null>(null)
const busy = computed(() => operation.value?.stage === 'pending')
const dialogOpen = computed({
  get: () => !!operation.value,
  set: (value: boolean) => { if (!value && !busy.value) operation.value = null },
})
const resultKey = computed(() => {
  const value = operation.value
  if (!value?.responded) return 'resultUnknown'
  if (value.action === 'delete') return 'deleteSubmitted'
  if (value.action === 'refresh') return value.reread && value.current ? 'refreshed' : 'refreshUnconfirmed'
  return value.reread && value.current?.publicIp && value.current.publicIp !== '0.0.0.0' && value.current.publicIp !== value.row.publicIp
    ? 'ipChanged' : 'ipUnconfirmed'
})
const resultTone = computed(() => !operation.value?.responded ? 'error' : resultKey.value === 'ipChanged' || resultKey.value === 'refreshed' ? 'normal' : 'warning')

let disposed = false
let listSequence = 0
let displayedQuery = ''
let listController: AbortController | undefined
let operationController: AbortController | undefined

function number(value: number | null): string { return value == null ? '—' : new Intl.NumberFormat(locale.value).format(value) }
function instanceName(row: GcpInstanceRow): string { return row.instanceName || t('gcpInstances.unnamed') }
function tenantName(row: GcpInstanceRow): string { return !row.defName || row.defName === '未设置' ? t('gcpInstances.unset') : row.defName }
function provider(value: number | null): string { return value === 2 ? 'GCP' : value === 3 ? 'Azure' : value === 4 ? 'AWS' : t('gcpInstances.unknown') }
function stateCode(row: GcpInstanceRow): string { return row.status === 0 ? 'stopped' : row.status === 1 ? 'starting' : row.status === 2 ? 'running' : 'unknown' }
function stateLabel(row: GcpInstanceRow): string { return t(`gcpInstances.states.${stateCode(row)}`) }
function errorMessage(cause: unknown): string {
  return gcpInstancesServerError(cause) || t(cause instanceof GcpInstancesResponseError ? 'gcpInstances.invalidResponse' : 'gcpInstances.loadFailed')
}
function togglePassword(row: GcpInstanceRow) {
  const next = new Set(revealed.value)
  if (next.has(row.bootId)) next.delete(row.bootId)
  else next.add(row.bootId)
  revealed.value = next
}
async function copy(value: string) {
  if (!value) return
  try {
    if (navigator.clipboard?.writeText && window.isSecureContext) await navigator.clipboard.writeText(value)
    else {
      // The legacy application also supports HTTP deployments where Clipboard API is unavailable.
      const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null
      const field = document.createElement('textarea')
      field.value = value
      field.readOnly = true
      field.style.position = 'fixed'
      field.style.opacity = '0'
      field.style.pointerEvents = 'none'
      document.body.appendChild(field)
      try { field.select(); if (!document.execCommand('copy')) throw new Error('copy_failed') }
      finally { field.remove(); previous?.focus({ preventScroll: true }) }
    }
    if (!disposed) ElMessage.success(t('gcpInstances.copied'))
  } catch { if (!disposed) ElMessage.error(t('gcpInstances.copyFailed')) }
}

async function load(): Promise<GcpInstancePage | null> {
  const sequence = ++listSequence
  const key = queryKey.value
  listController?.abort()
  listError.value = null
  if (displayedQuery !== key) {
    rows.value = []
    total.value = 0
    loaded.value = false
    updatedAt.value = null
    revealed.value = new Set()
  }
  if (invalidScope.value) { loading.value = false; return null }
  const controller = new AbortController()
  listController = controller
  loading.value = true
  try {
    const result = await getGcpInstances({ tenantId: tenantId.value, cloudType: cloudType.value, page: page.value, size: size.value }, controller.signal)
    if (disposed || sequence !== listSequence || key !== queryKey.value) return null
    rows.value = result.rows
    total.value = result.total
    displayedQuery = key
    loaded.value = true
    updatedAt.value = new Date()
    if (page.value > 0 && page.value >= Math.max(1, result.totalPages)) {
      // A deletion may remove the last page. The route watcher reads the remaining page.
      void router.replace({ query: { ...route.query, page: String(Math.max(0, result.totalPages - 1)) } })
    }
    return result
  } catch (cause) {
    if (!disposed && sequence === listSequence && key === queryKey.value && !isCancel(cause)) listError.value = cause
    return null
  } finally {
    if (!disposed && sequence === listSequence) loading.value = false
  }
}
function changePage(value: number) {
  if (busy.value || loading.value || value === page.value + 1) return
  void router.replace({ query: { ...route.query, page: String(value - 1) } })
}
function changeSize(value: number) {
  if (busy.value || loading.value || value === size.value) return
  void router.replace({ query: { ...route.query, page: '0', size: String(value) } })
}
function goBack() {
  if (busy.value) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous && previous !== route.fullPath) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: String([2, 3, 4].includes(cloudType.value) ? cloudType.value : 2) } })
}
function openOperation(action: GcpInstanceAction, row: GcpInstanceRow) {
  if (operation.value || loading.value || listError.value || row.cloudType !== 2 || (action === 'changeIp' && row.status !== 2)) return
  operation.value = {
    action, row: { ...row }, scope: scopeKey.value, stage: 'confirm', acknowledged: false,
    responded: false, error: null, reread: false, readFailed: false, current: null,
  }
}
async function rereadOperation() {
  const selected = operation.value
  if (!selected || loading.value || disposed) return
  selected.readFailed = false
  const result = await load()
  if (disposed || operation.value !== selected || selected.scope !== scopeKey.value) return
  selected.reread = !!result
  selected.readFailed = !result
  selected.current = result?.rows.find(row => row.bootId === selected.row.bootId) || null
}
async function confirmOperation() {
  const selected = operation.value
  if (!selected || selected.stage !== 'confirm' || (selected.action === 'delete' && !selected.acknowledged) || selected.scope !== scopeKey.value) return
  const current = rows.value.find(row => row.bootId === selected.row.bootId)
  if (!current || current.cloudType !== 2 || (selected.action === 'changeIp' && current.status !== 2)) { operation.value = null; return }
  selected.row = { ...current }
  selected.stage = 'pending'
  const controller = new AbortController()
  operationController = controller
  try {
    await runGcpInstanceAction(selected.action, selected.row, tenantId.value, controller.signal)
    if (disposed || operation.value !== selected || selected.scope !== scopeKey.value) return
    selected.responded = true
  } catch (cause) {
    if (disposed || operation.value !== selected || selected.scope !== scopeKey.value || isCancel(cause)) return
    selected.error = cause
  } finally {
    if (!disposed && operation.value === selected && selected.scope === scopeKey.value) {
      // Never retry the mutation automatically, including after a timeout or ambiguous reply.
      // Even a failed reply can follow a partially applied operation, so reread persisted values.
      selected.stage = 'result'
      operationController = undefined
      await rereadOperation()
    }
  }
}

watch(scopeKey, () => {
  operationController?.abort()
  operationController = undefined
  operation.value = null
})
watch(queryKey, () => { void load() }, { immediate: true })
onMounted(() => {
  viewportQuery = window.matchMedia('(max-width: 760px)')
  updateViewport()
  viewportQuery.addEventListener('change', updateViewport)
})
onBeforeUnmount(() => {
  disposed = true
  listSequence++
  listController?.abort()
  operationController?.abort()
  viewportQuery?.removeEventListener('change', updateViewport)
  operation.value = null
  rows.value = []
  revealed.value.clear()
})

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<GcpInstanceRow>
</script>

<template>
  <div class="gcp-instances-page">
    <ListCard class="gcp-instances-card" :aria-label="t('gcpInstances.label')">
      <template #toolbar>
        <PageBackButton :disabled="busy" @click="goBack" />
        <span class="gcp-scope">{{ scopeLabel }}</span>
        <span v-if="!invalidScope" class="gcp-provider">{{ provider(cloudType) }}</span>
        <span v-if="refreshTime" class="gcp-refresh-time">{{ refreshTime }}</span>
        <GhostBtn :loading="loading" :disabled="busy || invalidScope" @click="load">{{ t('gcpInstances.refreshList') }}</GhostBtn>
        <span data-page-error-anchor />
      </template>
      <PageErrorNotice v-if="invalidScope || listError">
        <span>{{ invalidScope ? t('gcpInstances.invalidScope') : errorMessage(listError) }}<br v-if="loaded && listError" />{{ loaded && listError ? t('gcpInstances.staleRows') : '' }}</span>
        <GhostBtn v-if="!invalidScope" :disabled="busy" :loading="loading" @click="load">{{ t('gcpInstances.retry') }}</GhostBtn>
      </PageErrorNotice>
      <div class="gcp-table-wrap" :aria-busy="loading">
        <MobileRecordList v-if="compactViewport" drilldown list-id="gcp-instances" :record-keys="rows.map(row => row.bootId)" :loading="loading">
          <MobileRecordCard v-for="row in rows" :key="row.bootId" :record-key="row.bootId" :summary-title="instanceName(row)" :summary-meta="`${tenantName(row)} · ${row.zone || provider(row.cloudType)}`" :summary-status="stateLabel(row)" :summary-tone="row.status === 2 ? 'success' : row.status === 1 ? 'warning' : 'neutral'">
            <template #identity><div class="mobile-record-title">{{ instanceName(row) }}</div><span class="mobile-record-subtitle">{{ row.zone || provider(row.cloudType) }}</span></template>
            <dl class="mobile-record-fields">
              <div><dt>{{ t('gcpInstances.tenant') }}</dt><dd>{{ tenantName(row) }}</dd></div><div><dt>{{ t('gcpInstances.cloud') }}</dt><dd>{{ provider(row.cloudType) }}</dd></div>
              <div><dt>{{ t('gcpInstances.status') }}</dt><dd>{{ stateLabel(row) }}</dd></div><div><dt>{{ t('gcpInstances.architecture') }}</dt><dd>{{ row.architecture || t('gcpInstances.unknown') }}</dd></div>
              <div><dt>{{ t('gcpInstances.resources') }}</dt><dd>{{ t('gcpInstances.resourcesValue', { cpu: number(row.ocpu), memory: number(row.memory) }) }}</dd></div><div><dt>{{ t('gcpInstances.disk') }}</dt><dd>{{ row.disk == null ? '—' : t('gcpInstances.diskValue', { value: number(row.disk) }) }}</dd></div>
              <div class="mobile-record-wide"><dt>{{ t('gcpInstances.publicIp') }}</dt><dd class="gcp-copy-value"><span>{{ row.publicIp || '—' }}</span><button v-if="row.publicIp" type="button" class="gcp-icon-button" :aria-label="t('gcpInstances.copyIp')" @click="copy(row.publicIp)"><i class="i-mdi-content-copy" aria-hidden="true" /></button></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('gcpInstances.password') }}</dt><dd class="gcp-copy-value gcp-password-value"><span>{{ row.rootPassword ? revealed.has(row.bootId) ? row.rootPassword : '••••••••' : '—' }}</span><div v-if="row.rootPassword" class="gcp-value-actions"><button type="button" class="gcp-icon-button" :aria-label="t(revealed.has(row.bootId) ? 'gcpInstances.hidePassword' : 'gcpInstances.revealPassword')" :aria-pressed="revealed.has(row.bootId)" @click="togglePassword(row)"><i :class="revealed.has(row.bootId) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button><button type="button" class="gcp-icon-button" :aria-label="t('gcpInstances.copyPassword')" @click="copy(row.rootPassword)"><i class="i-mdi-content-copy" aria-hidden="true" /></button></div></dd></div>
            </dl>
            <template #footer><GhostBtn :disabled="loading || busy || !!listError || row.cloudType !== 2 || row.status !== 2" :title="row.cloudType !== 2 ? t('gcpInstances.onlyGcp') : row.status !== 2 ? t('gcpInstances.runningOnly') : t('gcpInstances.action.changeIp')" @click="openOperation('changeIp', row)">{{ t('gcpInstances.action.changeIp') }}</GhostBtn><GhostBtn :disabled="loading || busy || !!listError || row.cloudType !== 2" @click="openOperation('refresh', row)">{{ t('gcpInstances.action.refresh') }}</GhostBtn><GhostBtn danger :disabled="loading || busy || !!listError || row.cloudType !== 2" @click="openOperation('delete', row)">{{ t('gcpInstances.action.delete') }}</GhostBtn></template>
          </MobileRecordCard>
          <div v-if="!rows.length" class="gcp-empty" role="status"><strong>{{ loading ? t('gcpInstances.loading') : invalidScope || listError ? t('gcpInstances.loadFailed') : t('gcpInstances.empty') }}</strong><span v-if="!loading && !listError && !invalidScope">{{ t('gcpInstances.emptyHint') }}</span></div>
        </MobileRecordList>
        <el-table v-else :data="rows" row-key="bootId" height="100%" v-loading="loading" :element-loading-text="t('gcpInstances.loading')">
          <el-table-column :label="t('gcpInstances.name')" min-width="190">
            <template #default="{ row }"><span class="gcp-name">{{ instanceName(row) }}</span><span v-if="row.zone" class="gcp-subline" :title="t('gcpInstances.zone')">{{ row.zone }}</span></template>
          </el-table-column>
          <el-table-column :label="t('gcpInstances.tenant')" min-width="145"><template #default="{ row }"><span class="gcp-break">{{ tenantName(row) }}</span></template></el-table-column>
          <el-table-column :label="t('gcpInstances.cloud')" min-width="100"><template #default="{ row }"><span class="gcp-cloud-tag">{{ provider(row.cloudType) }}</span></template></el-table-column>
          <el-table-column :label="t('gcpInstances.resources')" min-width="155"><template #default="{ row }">{{ t('gcpInstances.resourcesValue', { cpu: number(row.ocpu), memory: number(row.memory) }) }}</template></el-table-column>
          <el-table-column :label="t('gcpInstances.architecture')" min-width="110"><template #default="{ row }">{{ row.architecture || t('gcpInstances.unknown') }}</template></el-table-column>
          <el-table-column :label="t('gcpInstances.disk')" min-width="90"><template #default="{ row }">{{ row.disk == null ? '—' : t('gcpInstances.diskValue', { value: number(row.disk) }) }}</template></el-table-column>
          <el-table-column :label="t('gcpInstances.status')" min-width="120"><template #default="{ row }"><span class="gcp-state" :class="`is-${stateCode(row)}`"><i aria-hidden="true" />{{ stateLabel(row) }}</span></template></el-table-column>
          <el-table-column :label="t('gcpInstances.publicIp')" min-width="175">
            <template #default="{ row }"><div class="gcp-copy-value"><span>{{ row.publicIp || '—' }}</span><button v-if="row.publicIp" type="button" class="gcp-icon-button" :aria-label="t('gcpInstances.copyIp')" :title="t('gcpInstances.copyIp')" @click="copy(row.publicIp)"><i class="i-mdi-content-copy" aria-hidden="true" /></button></div></template>
          </el-table-column>
          <el-table-column :label="t('gcpInstances.password')" min-width="205">
            <template #default="{ row }"><div class="gcp-copy-value gcp-password-value"><span>{{ row.rootPassword ? revealed.has(row.bootId) ? row.rootPassword : '••••••••' : '—' }}</span><div v-if="row.rootPassword" class="gcp-value-actions"><button type="button" class="gcp-icon-button" :aria-label="t(revealed.has(row.bootId) ? 'gcpInstances.hidePassword' : 'gcpInstances.revealPassword')" :title="t(revealed.has(row.bootId) ? 'gcpInstances.hidePassword' : 'gcpInstances.revealPassword')" :aria-pressed="revealed.has(row.bootId)" @click="togglePassword(row)"><i :class="revealed.has(row.bootId) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button><button type="button" class="gcp-icon-button" :aria-label="t('gcpInstances.copyPassword')" :title="t('gcpInstances.copyPassword')" @click="copy(row.rootPassword)"><i class="i-mdi-content-copy" aria-hidden="true" /></button></div></div></template>
          </el-table-column>
          <el-table-column :label="t('gcpInstances.actions')" min-width="320" :fixed="compactViewport ? false : 'right'">
            <template #default="{ row }">
              <div class="gcp-row-actions">
                <GhostBtn :disabled="loading || busy || !!listError || row.cloudType !== 2 || row.status !== 2" :title="row.cloudType !== 2 ? t('gcpInstances.onlyGcp') : row.status !== 2 ? t('gcpInstances.runningOnly') : t('gcpInstances.action.changeIp')" @click="openOperation('changeIp', row)">{{ t('gcpInstances.action.changeIp') }}</GhostBtn>
                <GhostBtn :disabled="loading || busy || !!listError || row.cloudType !== 2" :title="row.cloudType !== 2 ? t('gcpInstances.onlyGcp') : t('gcpInstances.action.refresh')" @click="openOperation('refresh', row)">{{ t('gcpInstances.action.refresh') }}</GhostBtn>
                <GhostBtn danger :disabled="loading || busy || !!listError || row.cloudType !== 2" :title="row.cloudType !== 2 ? t('gcpInstances.onlyGcp') : t('gcpInstances.action.delete')" @click="openOperation('delete', row)">{{ t('gcpInstances.action.delete') }}</GhostBtn>
              </div>
            </template>
          </el-table-column>
          <template #empty><div class="gcp-empty"><strong>{{ loading ? t('gcpInstances.loading') : invalidScope || listError ? t('gcpInstances.loadFailed') : t('gcpInstances.empty') }}</strong><span v-if="!loading && !listError && !invalidScope">{{ t('gcpInstances.emptyHint') }}</span></div></template>
        </el-table>
      </div>
      <template #footer>
        <PagePagination embedded :aria-label="t('gcpInstances.pagination')" :total="total" :current-page="page + 1" :page-size="size" :page-sizes="pageSizes" :disabled="loading || busy || invalidScope" @current-change="changePage" @size-change="changeSize"><span>{{ range }}</span></PagePagination>
      </template>
    </ListCard>

    <el-dialog v-model="dialogOpen" class="gcp-instance-dialog" :title="operation ? t(`gcpInstances.title.${operation.action}`) : ''" width="min(580px, calc(100vw - 32px))" append-to-body destroy-on-close :close-on-click-modal="false" :close-on-press-escape="!busy" :show-close="!busy">
      <template v-if="operation">
        <dl class="gcp-operation-target">
          <div><dt>{{ t('gcpInstances.name') }}</dt><dd>{{ instanceName(operation.row) }}</dd></div>
          <div><dt>{{ t('gcpInstances.tenant') }}</dt><dd>{{ tenantName(operation.row) }}</dd></div>
          <div><dt>{{ t('gcpInstances.bootId') }}</dt><dd>{{ operation.row.bootId }}</dd></div>
          <div v-if="operation.row.zone"><dt>{{ t('gcpInstances.zone') }}</dt><dd>{{ operation.row.zone }}</dd></div>
        </dl>
        <template v-if="operation.stage === 'confirm'">
          <template v-if="operation.action === 'delete'"><p class="gcp-operation-warning">{{ t('gcpInstances.deleteWarning') }}</p><p>{{ t('gcpInstances.diskHint') }}</p><el-checkbox v-model="operation.acknowledged" class="gcp-delete-acknowledgement">{{ t('gcpInstances.deleteAcknowledgement') }}</el-checkbox></template>
          <p v-else>{{ t(operation.action === 'changeIp' ? 'gcpInstances.changeIpHint' : 'gcpInstances.refreshHint') }}</p>
        </template>
        <div v-else-if="operation.stage === 'pending'" role="status"><p class="gcp-operation-pending">{{ t(`gcpInstances.pending.${operation.action}`) }}</p><p class="gcp-operation-hint">{{ t('gcpInstances.pendingHint') }}</p></div>
        <template v-else>
          <p class="gcp-operation-result" :class="`is-${resultTone}`" role="status">{{ t(`gcpInstances.${resultKey}`) }}</p>
          <PageErrorNotice v-if="operation.error && gcpInstancesServerError(operation.error)">{{ gcpInstancesServerError(operation.error) }}</PageErrorNotice>
          <PageErrorNotice v-if="operation.readFailed">{{ t('gcpInstances.readAfterActionFailed') }}</PageErrorNotice>
          <p v-else-if="operation.reread && operation.action === 'delete'" class="gcp-operation-hint">{{ t(operation.current ? 'gcpInstances.recordPresent' : 'gcpInstances.recordAbsent') }}</p>
          <p v-if="loading" class="gcp-operation-hint" role="status">{{ t('gcpInstances.refreshing') }}</p>
          <dl v-if="operation.action === 'changeIp'" class="gcp-operation-values"><div><dt>{{ t('gcpInstances.oldIp') }}</dt><dd>{{ operation.row.publicIp || '—' }}</dd></div><div><dt>{{ t('gcpInstances.currentIp') }}</dt><dd>{{ operation.current?.publicIp || '—' }}</dd></div></dl>
          <dl v-else-if="operation.action === 'refresh' && operation.current" class="gcp-operation-values"><div><dt>{{ t('gcpInstances.currentStatus') }}</dt><dd>{{ stateLabel(operation.current) }}</dd></div><div><dt>{{ t('gcpInstances.publicIp') }}</dt><dd>{{ operation.current.publicIp || '—' }}</dd></div></dl>
        </template>
      </template>
      <template #footer>
        <GhostBtn :disabled="busy" @click="dialogOpen = false">{{ t(operation?.stage === 'confirm' ? 'gcpInstances.cancel' : 'gcpInstances.close') }}</GhostBtn>
        <template v-if="operation?.stage === 'confirm' || busy">
          <GhostBtn v-if="operation?.action === 'delete'" danger :loading="busy" :disabled="!operation?.acknowledged" @click="confirmOperation">{{ t('gcpInstances.confirm.delete') }}</GhostBtn>
          <PrimaryBtn v-else :loading="busy" @click="confirmOperation">{{ t(`gcpInstances.confirm.${operation?.action || 'refresh'}`) }}</PrimaryBtn>
        </template>
        <GhostBtn v-else :loading="loading" @click="rereadOperation">{{ t('gcpInstances.refreshList') }}</GhostBtn>
      </template>
    </el-dialog>
  </div>
</template>

<style lang="scss">
.gcp-instances-page { display: flex; width: 100%; height: 100%; min-width: 0; min-height: 0; color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
.gcp-instances-card { flex: 1; min-width: 0; }
.gcp-instances-page {
  .gcp-instances-card > .toolbar { padding-bottom: 12px; border-bottom: 1px solid var(--border); }
  .gcp-instances-card > .body { display: flex; flex: 1; flex-direction: column; min-height: 160px; padding-top: 0; padding-bottom: 0; overflow: hidden; }
  .gcp-instances-card > .footer { flex: none; align-items: center; flex-wrap: wrap; gap: 12px 16px; border-top: 1px solid var(--border); }
  .gcp-scope { max-width: min(380px, 100%); overflow-wrap: anywhere; font-weight: 600; }
  .gcp-provider, .gcp-cloud-tag { display: inline-flex; padding: 3px 8px; border-radius: 7px; background: var(--bg-search); color: var(--text-primary); font-size: var(--font-size-caption); }
  .gcp-refresh-time { margin-left: auto; color: var(--text-secondary); font-size: var(--font-size-secondary); }
  .toolbar > .btn:not(.page-back-button) { margin-left: auto; min-height: 36px; padding: 8px 12px; }
  .gcp-refresh-time + .btn { margin-left: 0; }
  .gcp-list-error { display: flex; align-items: center; justify-content: space-between; flex: none; gap: 12px; margin: 12px 0; padding: 10px 12px; border-radius: var(--r-sm); background: var(--status-danger-bg); color: var(--status-danger); overflow-wrap: anywhere; }
  .gcp-table-wrap { position: relative; flex: 1; min-height: 140px; min-width: 0; }
  .el-table { position: absolute; inset: 0; color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
  .el-table th.el-table__cell { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; background: var(--bg-card); }
  .el-table .el-table__cell { padding: 12px 0; }
  .el-table .cell { font-size: var(--font-size-body); line-height: 1.47; }
  .gcp-name, .gcp-break { white-space: normal; overflow-wrap: anywhere; }
  .gcp-name { font-weight: 600; }
  .gcp-subline { display: block; margin-top: 4px; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
  .gcp-state { display: inline-flex; align-items: center; gap: 6px; padding: 4px 8px; border-radius: 7px; background: var(--bg-search); color: var(--text-primary); font-size: var(--font-size-caption); }
  .gcp-state > i { width: 6px; height: 6px; flex: none; border-radius: 50%; background: var(--text-secondary); }
  .gcp-state.is-running { background: var(--status-ok-bg); }
  .gcp-state.is-running > i { background: var(--status-ok); }
  .gcp-state.is-starting { background: var(--status-info-bg); }
  .gcp-state.is-starting > i { background: var(--status-info); }
  .gcp-copy-value { display: flex; align-items: center; gap: 4px; }
  .gcp-copy-value > span { min-width: 0; overflow-wrap: anywhere; }
  .gcp-password-value { justify-content: space-between; }
  .gcp-value-actions { display: flex; flex: none; }
  .gcp-icon-button { display: inline-grid; place-items: center; flex: none; width: 28px; height: 28px; padding: 0; border: 0; border-radius: 7px; background: transparent; color: var(--text-primary); font-size: 16px; cursor: pointer; }
  .gcp-icon-button:hover { background: var(--bg-hover); }
  .gcp-icon-button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
  .gcp-row-actions { display: flex; flex-wrap: wrap; gap: 6px; }
  .gcp-row-actions .btn { min-height: 32px; padding: 6px 10px; font-family: var(--sans); font-size: var(--font-size-body); }
  .gcp-empty { display: grid; gap: 8px; padding: 42px 12px; line-height: 1.6; }
  .gcp-empty strong { color: var(--text-primary); font-size: var(--font-size-section); font-weight: 600; }
  .gcp-empty > span { color: var(--text-secondary); font-size: var(--font-size-secondary); }
}
.gcp-instance-dialog { color: var(--text-primary); font: var(--font-size-body)/1.6 var(--sans); }
.gcp-instance-dialog {
  .el-dialog__title { color: var(--text-primary); font-size: var(--font-size-dialog-title); font-weight: 600; }
  .el-dialog__body { color: var(--text-primary); font-size: var(--font-size-body); }
  p { margin: 14px 0 0; color: var(--text-primary); font-size: var(--font-size-body); overflow-wrap: anywhere; }
  dl { display: grid; gap: 10px; margin: 0; }
  dl > div { display: grid; grid-template-columns: minmax(100px, 36%) 1fr; align-items: start; gap: 12px; }
  dt { color: var(--text-secondary); font-size: var(--font-size-body); }
  dd { min-width: 0; margin: 0; color: var(--text-primary); font-size: var(--font-size-body); overflow-wrap: anywhere; }
  .gcp-operation-target { padding: 14px; border-radius: var(--r-sm); background: var(--bg-search); }
  .gcp-operation-values { margin-top: 16px; padding-top: 14px; border-top: 1px solid var(--border); }
  .gcp-operation-warning, .gcp-operation-result.is-error { color: var(--status-danger); }
  .gcp-operation-result.is-warning { color: var(--status-warn); }
  .gcp-operation-pending { font-weight: 600; }
  .gcp-operation-hint { color: var(--text-secondary); font-size: var(--font-size-secondary); }
  .gcp-delete-acknowledgement { height: auto; margin-top: 16px; align-items: flex-start; }
  .gcp-delete-acknowledgement .el-checkbox__input { margin-top: 4px; }
  .gcp-delete-acknowledgement .el-checkbox__label { color: var(--text-primary); font: var(--font-size-body)/1.6 var(--sans); white-space: normal; }
  .el-dialog__footer { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 8px; }
}
@media (max-width: 760px) {
  .gcp-instances-page .gcp-table-wrap { overflow-y: auto; }
  .gcp-instances-page .mobile-record-card .gcp-icon-button { width: 44px; height: 44px; }
  .gcp-instances-page .mobile-record-card .btn { min-height: 44px; }
  .gcp-instances-page .gcp-refresh-time { width: 100%; margin-left: 0; }
  .gcp-instances-page .gcp-refresh-time + .btn { margin-left: auto; }
  .gcp-instance-dialog dl > div { grid-template-columns: 1fr; gap: 2px; }
}
</style>
