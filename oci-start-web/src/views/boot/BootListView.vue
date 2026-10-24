<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { bootTaskError, getBootTasks, isBootTaskId, type BootTaskAction, type BootTaskError, type BootTaskGroup } from '@/api/bootTasks'
import { getInstanceParent, getInstanceRegions, getInstanceTenants, type InstanceTenant } from '@/api/instances'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { mobileRecordSelection } from '@/composables/useMobileRecords'
import BootTaskActionDialog from './components/BootTaskActionDialog.vue'
import BootTaskDetailsDialog from './components/BootTaskDetailsDialog.vue'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const compact = useCompactViewport()
const tenantId = computed(() => typeof route.query.tenantId === 'string' ? route.query.tenantId : '')
const invalidTenant = computed(() => route.query.tenantId != null && !isBootTaskId(tenantId.value))
const rows = ref<BootTaskGroup[]>([])
const loading = ref(false)
const problem = ref<BootTaskError | null>(null)
const initialMobilePage = Number(route.query.mobilePage)
const page = ref(Number.isSafeInteger(initialMobilePage) && initialMobilePage > 0 ? initialMobilePage : 1)
const pageSize = ref([10, 20, 50, 100].includes(Number(route.query.mobileSize)) ? Number(route.query.mobileSize) : 20)
const total = ref(0)
const parents = ref<InstanceTenant[]>([])
const regions = ref<InstanceTenant[]>([])
const parentId = ref('')
const regionId = ref('')
const filtersLoading = ref(false)
const regionsLoading = ref(false)
const filtersProblem = ref<BootTaskError | null>(null)
const parentUnavailable = ref(false)
const unresolvedParent = ref(false)
const showNames = ref(false)
const visibleNames = ref(new Set<string>())
const operation = ref<{ action: BootTaskAction; target?: BootTaskGroup } | null>(null)
const operationBusy = ref(false)
const detailBusy = ref(false)
const details = ref<BootTaskGroup | null>(null)
const navigating = ref('')
const overlay = computed(() => operation.value !== null || details.value !== null)
const error = computed(() => invalidTenant.value ? t('bootTasks.errors.invalidId') : problem.value ? problem.value.detail || t(`bootTasks.errors.${problem.value.key}`) : '')
const filterError = computed(() => parentUnavailable.value ? t('bootTasks.errors.parentUnavailable') : filtersProblem.value ? filtersProblem.value.detail || t(`bootTasks.errors.${filtersProblem.value.key}`) : '')
const countColumns = ['recordCount', 'executingCount', 'totalCount', 'yesterdayAttemptCount', 'currentAttemptCount', 'failCount', 'successCount'] as const
const groupActions = ['clone', 'start', 'stop', 'manual', 'delete'] as const
function groupActionIcon(action: string) {
  switch (action) {
    case 'clone': return 'i-mdi-content-copy'
    case 'start': return 'i-mdi-play-outline'
    case 'stop': return 'i-mdi-stop-circle-outline'
    case 'manual': return 'i-mdi-flash-outline'
    case 'delete': return 'i-mdi-delete-outline'
    default: return 'i-mdi-dots-horizontal'
  }
}
let listController: AbortController | undefined
let filtersController: AbortController | undefined
let regionsController: AbortController | undefined
let navigationController: AbortController | undefined
let listGeneration = 0
let filterGeneration = 0
let regionGeneration = 0
let disposed = false
let pageScopeInitialized = false

function number(value: string | number) { return new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US').format(typeof value === 'string' ? BigInt(value) : value) }
function label(value: string) { return value === '未设置' || !value ? t('bootTasks.unset') : value === '未知' ? t('bootTasks.unknown') : value }
function rowKey(row: BootTaskGroup) { return `${row.tenantId}:${row.architecture}` }
function isNameVisible(row: BootTaskGroup) { return showNames.value || visibleNames.value.has(rowKey(row)) }
function maskedName(row: BootTaskGroup) {
  const value = label(row.tenancyName || row.defName)
  if (isNameVisible(row)) return value
  const characters = Array.from(value)
  return characters.length > 2 ? `${characters[0]}***${characters[characters.length - 1]}` : '***'
}
function toggleName(row: BootTaskGroup) {
  if (showNames.value) { showNames.value = false; visibleNames.value = new Set(rows.value.filter(item => rowKey(item) !== rowKey(row)).map(rowKey)); return }
  const next = new Set(visibleNames.value)
  if (next.has(rowKey(row))) next.delete(rowKey(row)); else next.add(rowKey(row))
  visibleNames.value = next
}
function toggleNames() { showNames.value = !showNames.value; visibleNames.value = new Set() }
function date(value: string) {
  if (!value) return '—'
  const parsed = new Date(`${value.replace(' ', 'T')}Z`)
  return Number.isFinite(parsed.getTime()) ? new Intl.DateTimeFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US', { dateStyle: 'medium', timeStyle: 'medium', timeZone: 'UTC' }).format(parsed) : value
}
async function load() {
  listController?.abort()
  const active = new AbortController()
  listController = active
  const current = ++listGeneration
  rows.value = []
  total.value = 0
  problem.value = null
  visibleNames.value = new Set()
  if (invalidTenant.value) { loading.value = false; return }
  loading.value = true
  try {
    const result = await getBootTasks(page.value - 1, pageSize.value, tenantId.value, active.signal)
    if (disposed || current !== listGeneration || active.signal.aborted) return
    if (result.total > 0 && page.value > result.totalPages) { page.value = Math.max(1, result.totalPages); return }
    if (result.total === 0 && page.value > 1) { page.value = 1; return }
    rows.value = result.rows
    total.value = result.total
  } catch (cause) { if (!disposed && current === listGeneration && !active.signal.aborted) problem.value = bootTaskError(cause) }
  finally { if (!disposed && current === listGeneration) loading.value = false }
}
async function initializeFilters() {
  filtersController?.abort()
  regionsController?.abort()
  const active = new AbortController()
  filtersController = active
  const current = ++filterGeneration
  regionGeneration++
  filtersLoading.value = true
  regionsLoading.value = false
  filtersProblem.value = null
  parentUnavailable.value = false
  unresolvedParent.value = false
  parentId.value = ''
  regionId.value = ''
  regions.value = []
  try {
    const result = await getInstanceTenants(active.signal)
    if (disposed || current !== filterGeneration || active.signal.aborted) return
    parents.value = result.sort((a, b) => a.userName.localeCompare(b.userName))
    if (tenantId.value && !invalidTenant.value) {
      const parent = await getInstanceParent(tenantId.value, result, active.signal)
      if (disposed || current !== filterGeneration || active.signal.aborted) return
      parentId.value = parent
      if (parent) {
        const list = await getInstanceRegions(parent, active.signal)
        if (disposed || current !== filterGeneration || active.signal.aborted) return
        regions.value = list.sort((a, b) => a.region.localeCompare(b.region))
        regionId.value = list.find(item => item.id === tenantId.value)?.id || ''
      }
      unresolvedParent.value = !parent || !regionId.value
    }
  } catch (cause) { if (!disposed && current === filterGeneration && !active.signal.aborted) filtersProblem.value = bootTaskError(cause) }
  finally { if (!disposed && current === filterGeneration) filtersLoading.value = false }
}
async function changeParent() {
  regionsController?.abort()
  const current = ++regionGeneration
  regions.value = []
  regionId.value = ''
  unresolvedParent.value = false
  filtersProblem.value = null
  parentUnavailable.value = false
  if (!parentId.value) { regionsLoading.value = false; return }
  const active = new AbortController()
  regionsController = active
  regionsLoading.value = true
  try {
    const result = await getInstanceRegions(parentId.value, active.signal)
    if (disposed || current !== regionGeneration || active.signal.aborted) return
    regions.value = result.sort((a, b) => a.region.localeCompare(b.region))
    if (result.length === 1) regionId.value = result[0]!.id
  } catch (cause) { if (!disposed && current === regionGeneration && !active.signal.aborted) filtersProblem.value = bootTaskError(cause) }
  finally { if (!disposed && current === regionGeneration) regionsLoading.value = false }
}
async function search(all = false) {
  if (overlay.value || filtersLoading.value || regionsLoading.value) return
  const next = all ? '' : regionId.value
  if (!all && (!isBootTaskId(next) || !regions.value.some(item => item.id === next))) return
  if (next === tenantId.value && !invalidTenant.value) {
    if (all) { parentId.value = ''; regionId.value = ''; regions.value = []; unresolvedParent.value = false }
    if (page.value !== 1) page.value = 1; else void load()
    return
  }
  await router.replace({ path: route.path, query: { ...route.query, tenantId: next || undefined, cloudType: '1' } })
}
function openAction(action: BootTaskAction, target?: BootTaskGroup) { if (!overlay.value && !loading.value && !navigating.value) operation.value = { action, target } }
function batchAction(value: unknown) { if (typeof value === 'string' && ['batchStart', 'batchStop', 'resetFailures'].includes(value)) openAction(value as BootTaskAction) }
function menuAction(value: unknown, row: BootTaskGroup) {
  if (value === 'add') { void addConfiguration(row); return }
  if (typeof value === 'string' && groupActions.includes(value as typeof groupActions[number])) openAction(value as BootTaskAction, row)
}
async function addConfiguration(row: BootTaskGroup) {
  if (navigating.value || overlay.value) return
  navigating.value = row.id
  filtersProblem.value = null
  parentUnavailable.value = false
  navigationController?.abort()
  const active = new AbortController()
  navigationController = active
  try {
    const accounts = parents.value.length ? parents.value : await getInstanceTenants(active.signal)
    const parent = await getInstanceParent(row.tenantId, accounts, active.signal)
    if (disposed || active.signal.aborted) return
    if (!parent) { parentUnavailable.value = true; return }
    await router.push({ path: '/tenants/bootPage', query: { tenantId: parent, regionId: row.tenantId, cloudType: '1' } })
  } catch (cause) { if (!disposed && !active.signal.aborted) filtersProblem.value = bootTaskError(cause) }
  finally { if (!disposed) navigating.value = '' }
}
function back() {
  if (overlay.value || navigating.value || operationBusy.value || detailBusy.value) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: '1' } })
}
watch(() => route.query.tenantId, () => { if (pageScopeInitialized) page.value = 1; pageScopeInitialized = true; details.value = null; operation.value = null; void load(); void initializeFilters() }, { immediate: true })
watch(page, () => { void load() })
watch([rows, () => route.query.mobileRecord, () => route.query.mobileRecordParents], () => {
  if (details.value || operation.value) return
  const group = rows.value.find(row => mobileRecordSelection(route.query, `boot-task-details-${row.id}-${row.architecture}`))
  if (group) details.value = group
})
watch(pageSize, () => { if (page.value !== 1) page.value = 1; else void load() })
watch([page, pageSize], () => {
  if (!compact.value || operationBusy.value || detailBusy.value) return
  if (route.query.mobilePage === String(page.value) && route.query.mobileSize === String(pageSize.value)) return
  void router.replace({ query: { ...route.query, mobilePage: String(page.value), mobileSize: String(pageSize.value) } })
}, { flush: 'post' })
onBeforeRouteLeave(() => !operationBusy.value && !detailBusy.value)
onBeforeRouteUpdate(() => !operationBusy.value && !detailBusy.value)
onBeforeUnmount(() => { disposed = true; listGeneration++; filterGeneration++; regionGeneration++; listController?.abort(); filtersController?.abort(); regionsController?.abort(); navigationController?.abort() })
</script>

<template>
  <section class="boot-list-page" :aria-label="t('bootTasks.title')">
    <div class="filter-card">
      <div class="filters">
        <PageBackButton :disabled="overlay || !!navigating || operationBusy || detailBusy" @click="back" />
        <div class="filter-field"><label for="boot-task-account">{{ t('bootTasks.parent') }}</label><el-select id="boot-task-account" v-model="parentId" filterable clearable :placeholder="t('bootTasks.chooseParent')" :loading="filtersLoading" :disabled="filtersLoading || overlay" @change="changeParent"><el-option v-for="item in parents" :key="item.id" :value="item.id" :label="item.userName || item.tenancyName || item.id" /></el-select></div>
        <div class="filter-field"><label for="boot-task-region">{{ t('bootTasks.region') }}</label><el-select id="boot-task-region" v-model="regionId" filterable clearable :placeholder="t('bootTasks.chooseRegion')" :loading="regionsLoading" :disabled="!parentId || filtersLoading || regionsLoading || overlay"><el-option v-for="item in regions" :key="item.id" :value="item.id" :label="item.region" /></el-select></div>
        <PrimaryBtn :disabled="!regionId || filtersLoading || regionsLoading || overlay || loading" @click="search()">{{ t('bootTasks.search') }}</PrimaryBtn>
        <GhostBtn :disabled="filtersLoading || regionsLoading || overlay || loading" @click="search(true)">{{ t('bootTasks.all') }}</GhostBtn>
        <div class="toolbar-actions" data-page-error-anchor>
          <el-dropdown trigger="click" :disabled="overlay || loading || !!navigating" popper-class="boot-task-menu" @command="batchAction">
            <GhostBtn :disabled="overlay || loading || !!navigating">{{ t('bootTasks.batchActions') }}<i class="i-mdi-chevron-down" aria-hidden="true" /></GhostBtn>
            <template #dropdown><el-dropdown-menu><el-dropdown-item command="batchStart">{{ t('bootTasks.actions.batchStart') }}</el-dropdown-item><el-dropdown-item command="batchStop">{{ t('bootTasks.actions.batchStop') }}</el-dropdown-item><el-dropdown-item command="resetFailures" divided>{{ t('bootTasks.actions.resetFailures') }}</el-dropdown-item></el-dropdown-menu></template>
          </el-dropdown>
          <GhostBtn :disabled="overlay" :title="t(showNames ? 'bootTasks.hideNames' : 'bootTasks.showNames')" :aria-label="t(showNames ? 'bootTasks.hideNames' : 'bootTasks.showNames')" :aria-pressed="showNames" @click="toggleNames"><i :class="showNames ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'" aria-hidden="true" /></GhostBtn>
          <GhostBtn :loading="loading" :disabled="overlay || !!navigating" :title="t('bootTasks.refresh')" :aria-label="t('bootTasks.refresh')" @click="load"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn>
        </div>
      </div>
      <p v-if="tenantId && !invalidTenant" class="note">{{ t('bootTasks.filtered', { id: tenantId }) }}</p>
      <p v-if="unresolvedParent" class="note">{{ t('bootTasks.unresolvedParent') }}</p>
      <PageErrorNotice v-if="filterError" class="filter-error-notice"><span>{{ filterError }}</span><GhostBtn :disabled="filtersLoading || overlay" @click="initializeFilters">{{ t('bootTasks.retry') }}</GhostBtn></PageErrorNotice>
    </div>
    <div class="list-card">
      <PageErrorNotice v-if="error" class="list-error-notice">{{ error }}</PageErrorNotice>
      <div class="table-stage">
      <MobileRecordList v-if="compact" drilldown list-id="boot-tasks" :record-keys="rows.map(rowKey)" :loading="loading" :aria-busy="loading">
        <MobileRecordCard v-for="row in rows" :key="rowKey(row)" :record-key="rowKey(row)" :summary-title="maskedName(row)" :summary-meta="`${label(row.regionName)} · ${row.architecture}`" :summary-status="t(row.openBootFlag ? 'bootTasks.statuses.active' : 'bootTasks.statuses.idle')" :summary-tone="row.openBootFlag ? 'success' : 'neutral'">
          <template #identity>
            <div class="account-name mobile-record-title"><span>{{ maskedName(row) }}</span><button type="button" class="icon-button" :aria-label="t(isNameVisible(row) ? 'bootTasks.hideName' : 'bootTasks.showName')" :aria-pressed="isNameVisible(row)" @click="toggleName(row)"><i :class="isNameVisible(row) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></div>
            <span class="mobile-record-subtitle">{{ label(row.regionName) }} · {{ row.architecture }}</span>
          </template>
          <template #actions>
            <el-dropdown trigger="click" :disabled="overlay || loading || !!navigating" popper-class="boot-task-menu" @command="menuAction($event, row)">
              <button type="button" class="mobile-record-button" :disabled="overlay || loading || !!navigating" :aria-label="t('bootTasks.columns.actions')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
              <template #dropdown><el-dropdown-menu><el-dropdown-item v-for="action in groupActions" :key="action" :command="action" :class="{ danger: action === 'delete' }" :divided="action === 'delete'">{{ t(`bootTasks.actions.${action}`) }}</el-dropdown-item></el-dropdown-menu></template>
            </el-dropdown>
          </template>
          <dl class="mobile-record-fields">
            <div><dt>{{ t('bootTasks.columns.status') }}</dt><dd><el-tag :type="row.openBootFlag ? 'success' : 'info'">{{ t(row.openBootFlag ? 'bootTasks.statuses.active' : 'bootTasks.statuses.idle') }}</el-tag></dd></div>
            <div><dt>{{ t('bootTasks.columns.remark') }}</dt><dd>{{ label(row.defName) }}</dd></div>
            <div v-for="field in countColumns" :key="field"><dt :title="field === 'successCount' ? t('bootTasks.successCountHint') : undefined">{{ t(`bootTasks.columns.${field}`) }}</dt><dd>{{ number(row[field]) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('bootTasks.columns.createdAt') }}</dt><dd>{{ date(row.createdAt) }}</dd></div>
          </dl>
          <template #footer>
            <button type="button" class="mobile-record-button" :disabled="overlay || loading || !!navigating" @click="details = row">{{ t('bootTasks.actions.details') }}</button>
            <button type="button" class="mobile-record-button" :disabled="overlay || loading || !!navigating" :aria-busy="navigating === row.id" @click="addConfiguration(row)"><i class="i-mdi-plus" aria-hidden="true" />{{ t('bootTasks.actions.add') }}</button>
          </template>
        </MobileRecordCard>
        <p v-if="!rows.length" class="mobile-empty" role="status">{{ loading ? t('bootTasks.loading') : error || t('bootTasks.empty') }}</p>
      </MobileRecordList>
      <el-table v-else :data="rows" :row-key="rowKey" :empty-text="loading ? t('bootTasks.loading') : error || t('bootTasks.empty')" :aria-busy="loading" height="100%">
        <el-table-column :label="t('bootTasks.columns.index')" width="70"><template #default="{ $index }">{{ number((page - 1) * pageSize + $index + 1) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.name')" min-width="190"><template #default="{ row }"><div class="account-name"><span :title="maskedName(row as BootTaskGroup)">{{ maskedName(row as BootTaskGroup) }}</span><button type="button" class="icon-button" :aria-label="t(isNameVisible(row as BootTaskGroup) ? 'bootTasks.hideName' : 'bootTasks.showName')" :aria-pressed="isNameVisible(row as BootTaskGroup)" @click="toggleName(row as BootTaskGroup)"><i :class="isNameVisible(row as BootTaskGroup) ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></div></template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.remark')" min-width="150" show-overflow-tooltip><template #default="{ row }">{{ label(row.defName) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.region')" min-width="160" show-overflow-tooltip><template #default="{ row }">{{ label(row.regionName) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.status')" min-width="155"><template #default="{ row }"><el-tag :type="row.openBootFlag ? 'success' : 'info'">{{ t(row.openBootFlag ? 'bootTasks.statuses.active' : 'bootTasks.statuses.idle') }}</el-tag></template></el-table-column>
        <el-table-column v-for="field in countColumns" :key="field" :label="t(`bootTasks.columns.${field}`)" :min-width="field === 'successCount' ? 240 : 140" show-overflow-tooltip><template #header><span :title="field === 'successCount' ? t('bootTasks.successCountHint') : undefined">{{ t(`bootTasks.columns.${field}`) }}</span></template><template #default="{ row }">{{ number(row[field]) }}</template></el-table-column>
        <el-table-column prop="architecture" :label="t('bootTasks.columns.architecture')" min-width="155" show-overflow-tooltip />
        <el-table-column :label="t('bootTasks.columns.createdAt')" min-width="210" show-overflow-tooltip><template #default="{ row }">{{ date(row.createdAt) }}</template></el-table-column>
        <el-table-column :label="t('bootTasks.columns.actions')" fixed="right" width="125" align="left" header-align="left">
          <template #default="{ row }">
            <div class="row-actions">
              <button
                type="button"
                class="boot-button"
                :title="t('bootTasks.actions.details')"
                :aria-label="t('bootTasks.actions.details')"
                :disabled="overlay || loading || !!navigating"
                @click="details = row as BootTaskGroup"
              >
                <i class="i-mdi-information-outline" aria-hidden="true" />
              </button>
              <button
                type="button"
                class="boot-button"
                :title="t((row as BootTaskGroup).openBootFlag ? 'bootTasks.actions.stop' : 'bootTasks.actions.start')"
                :aria-label="t((row as BootTaskGroup).openBootFlag ? 'bootTasks.actions.stop' : 'bootTasks.actions.start')"
                :disabled="overlay || loading || !!navigating"
                @click="openAction((row as BootTaskGroup).openBootFlag ? 'stop' : 'start', row as BootTaskGroup)"
              >
                <i :class="(row as BootTaskGroup).openBootFlag ? 'i-mdi-stop-circle-outline' : 'i-mdi-play-outline'" aria-hidden="true" />
              </button>
              <el-dropdown
                trigger="click"
                :disabled="overlay || loading || !!navigating"
                popper-class="boot-task-menu"
                @command="menuAction($event, row as BootTaskGroup)"
              >
                <button
                  type="button"
                  class="more-button"
                  :disabled="overlay || loading || !!navigating"
                  :aria-label="t('bootTasks.columns.actions')"
                  :title="t('bootTasks.columns.actions')"
                >
                  <i class="i-mdi-dots-horizontal" aria-hidden="true" />
                </button>
                <template #dropdown>
                  <el-dropdown-menu>
                    <el-dropdown-item command="add">
                      <i class="i-mdi-plus" aria-hidden="true" />
                      <span>{{ t('bootTasks.actions.add') }}</span>
                    </el-dropdown-item>
                    <el-dropdown-item
                      v-for="action in groupActions.filter(a => a !== 'delete')"
                      :key="action"
                      :command="action"
                    >
                      <i :class="groupActionIcon(action)" aria-hidden="true" />
                      <span>{{ t(`bootTasks.actions.${action}`) }}</span>
                    </el-dropdown-item>
                    <el-dropdown-item
                      command="delete"
                      divided
                      class="danger"
                    >
                      <i :class="groupActionIcon('delete')" aria-hidden="true" />
                      <span>{{ t('bootTasks.actions.delete') }}</span>
                    </el-dropdown-item>
                  </el-dropdown-menu>
                </template>
              </el-dropdown>
            </div>
          </template>
        </el-table-column>
      </el-table>
      </div>
      <p v-if="!loading && !error && !rows.length" class="note empty-hint" role="status">{{ t('bootTasks.emptyHint') }}</p>
      <PagePagination v-model:current-page="page" v-model:page-size="pageSize" :page-sizes="[10, 20, 50, 100]" :total="total" :disabled="loading || overlay || !!navigating"><div class="footer-context"><span>{{ t('bootTasks.records', { count: number(total) }) }}</span><span>{{ t('bootTasks.groupHint') }}</span></div></PagePagination>
    </div>
    <BootTaskActionDialog v-if="operation" :key="`${operation.action}:${operation.target?.id || 'all'}`" :action="operation.action" :target="operation.target" @close="operation = null" @changed="load" @busy="operationBusy = $event" />
    <BootTaskDetailsDialog v-if="details" :key="rowKey(details)" :group="details" @close="details = null" @changed="load" @busy="detailBusy = $event" />
  </section>
</template>

<style scoped>
.boot-list-page { display: flex; flex-direction: column; width: 100%; height: 100%; min-width: 0; min-height: 0; overflow: hidden; border-radius: var(--r-card); background: var(--bg-card); box-shadow: var(--shadow-card); color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); }
.filter-card { flex: none; padding: 14px 18px; border-bottom: 1px solid var(--border); min-width: 0; }
.list-card { display: flex; flex: 1; flex-direction: column; min-width: 0; min-height: 0; }
.table-stage { flex: 1; min-width: 0; min-height: 0; }
.filters { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }.filter-field { display: flex; align-items: center; gap: 8px; flex: 0 1 245px; min-width: 170px; }.filter-field label { flex: none; white-space: nowrap; }.filter-field :deep(.el-select) { flex: 1; min-width: 0; }.filters :deep(.btn) { min-height: 36px; padding: 7px 12px; font-size: var(--font-size-body); }
.note { color: var(--text-secondary); font-size: var(--font-size-secondary); margin: 10px 0 0; }.group-hint { margin: 12px 0 18px; }
.toolbar-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-left: auto; }.filter-error-notice { margin-top: 12px; }
.list-error-notice { margin: 12px 18px; }
.list-card :deep(.el-table th.el-table__cell .cell),
.list-card :deep(.el-table td.el-table__cell .cell) {
  white-space: nowrap !important;
  word-break: keep-all !important;
  word-wrap: normal !important;
}
.list-card :deep(.el-table th.el-table__cell .cell) { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; }
.list-card :deep(.el-table .el-tag) { white-space: nowrap !important; }
.footer-context { display: flex; flex-wrap: wrap; gap: 5px 14px; font-size: var(--font-size-secondary); }.empty-hint { padding: 0 18px 12px; }
.account-name { display: flex; align-items: center; gap: 8px; }.account-name span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.icon-button, .row-actions button {
  display: inline-flex; align-items: center; justify-content: center; height: 32px; min-height: 32px; padding: 0 12px;
  border: 1px solid var(--border-color, var(--border)); border-radius: 9px; background: var(--card-bg, var(--bg-card));
  color: var(--text-primary); font: 500 var(--font-size-body)/1.4 var(--sans); cursor: pointer; white-space: nowrap;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1); box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}
.row-actions .boot-button, .row-actions .more-button, .icon-button { width: 32px; padding: 0; }
.icon-button i, .row-actions i { width: 16px; height: 16px; font-size: 16px; }
.row-actions { display: inline-flex; justify-content: flex-start; align-items: center; gap: 7px; flex-wrap: nowrap; }
.icon-button:hover:not(:disabled), .row-actions button:hover:not(:disabled) {
  border-color: var(--brand); background: var(--color-ok-bg, var(--bg-hover)); color: var(--brand);
  transform: translateY(-1px); box-shadow: 0 3px 6px rgba(0, 0, 0, 0.08);
}
.icon-button:active:not(:disabled), .row-actions button:active:not(:disabled) { transform: scale(0.94); }
.row-actions button:disabled { opacity: .45; cursor: not-allowed; }
.icon-button:focus-visible, .row-actions button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
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
.is-spinning { animation: boot-spin 1s linear infinite; }
@keyframes boot-spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
:global(.boot-task-menu .el-dropdown-menu__item) {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--text-primary);
  font: var(--font-size-body)/1.5 var(--sans);
}
:global(.boot-task-menu .el-dropdown-menu__item i) {
  font-size: 16px;
  width: 16px;
  height: 16px;
}
:global(.boot-task-menu .el-dropdown-menu__item.danger) { color: var(--status-danger); }
@media (max-width: 760px) {
  .filter-card { padding: 12px; }
  .filter-field { flex: 1 1 100%; min-width: 0; }
  .filter-field label { min-width: 48px; }
  .toolbar-actions { margin-left: 0; gap: 6px; }
  .filters :deep(.btn), .icon-button { min-height: 40px; }
  .table-stage { overflow-y: auto; overscroll-behavior: contain; }
  .account-name span { white-space: normal; overflow-wrap: anywhere; }
  .mobile-empty { margin: 0; padding: 28px 12px; text-align: center; color: var(--text-secondary); }
  .note { overflow-wrap: anywhere; }
}
</style>
