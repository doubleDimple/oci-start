<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { computed, defineAsyncComponent, nextTick, ref } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { instanceError, type InstanceRow } from '@/api/instances'
import { useTenantInstances } from './useTenantInstances'
import '../tenants/tenants.scss'
import './instances.scss'
import './tenant-instances.scss'

const InstanceOperationDialog = defineAsyncComponent(() => import('./components/InstanceOperationDialog.vue'))
const InstanceNetworkDialog = defineAsyncComponent(() => import('./components/InstanceNetworkDialog.vue'))
type Operation = 'config' | 'name' | 'volume' | 'terminate'
type Action = Operation | 'ip' | 'ipv6' | 'inspect'
interface MenuItem { id: Action; label: string; icon: string; danger?: boolean; disabled?: boolean }

const { t, locale } = useI18n()
const compact = useCompactViewport()
const router = useRouter()
const { rows, total, loaded, loading, problem, updatedAt, tenantId, invalidScope, page, size, tab, volumeRows, load, changePage, changeSize, changeTab } = useTenantInstances()
const selected = ref<InstanceRow | null>(null)
const operation = ref<Operation | ''>('')
const networkAction = ref<'ip' | 'ipv6' | ''>('')
const inspected = ref<InstanceRow | null>(null)
const inspectVolume = ref(false)
const pageSizes = [10, 20, 30, 50]
let restoreFocus: HTMLElement | null = null
let refreshAfterOperation = false

const operationOpen = computed(() => !!operation.value || !!networkAction.value)
const emptyText = computed(() => t(loading.value ? 'instances.loading' : invalidScope.value ? 'tenantInstances.invalidScope'
  : problem.value ? 'instances.listLoadFailed' : tab.value === 'volumes' ? 'tenantInstances.emptyVolumes' : 'instances.emptyFiltered'))
const rangeLabel = computed(() => t('tenantInstances.range', {
  start: number(rows.value.length ? page.value * size.value + 1 : 0),
  end: number(rows.value.length ? page.value * size.value + rows.value.length : 0), total: number(total.value),
}))
const refreshTitle = computed(() => updatedAt.value ? t('instances.refreshed', { time: dateTime(updatedAt.value) }) : t('instances.refresh'))
const detailFields = computed(() => {
  const row = inspected.value
  if (!row) return []
  const fields = inspectVolume.value
    ? [
      ['tenantInstances.volumeName', volumeName(row)], ['tenantInstances.volumeId', row.bootVolumeId],
      ['tenantInstances.volumeSize', quantity(row.bootVolumeSizeInGBs, 'GB')], ['tenantInstances.vpu', number(row.vpusPerGB)],
      ['tenantInstances.linkedInstance', row.displayName], ['tenantInstances.instanceState', stateLabel(row)],
    ]
    : [
      ['instances.name', row.displayName], ['tenantInstances.instanceState', stateLabel(row)],
      ['tenantInstances.shape', row.shape], ['instances.resources', `${number(row.ocpus)} C / ${number(row.memoryInGBs)} GB`],
      ['instances.ipv4', address(row.publicIps)], ['instances.privateIp', address(row.privateIps)],
      ['instances.ipv6Address', row.ipv6Addresses],
    ]
  return [...fields,
    ['tenantInstances.availabilityDomain', availability(row)], ['tenantInstances.instanceId', row.instanceId],
    ['instances.recordId', row.id], ['tenantInstances.tenantId', row.tenantId],
    ['tenantInstances.compartmentId', row.compartmentId], ['tenantInstances.recordCreated', dateTime(row.createTime)],
  ].map(([key, value]) => ({ key: key!, value: value || '—' }))
})

function number(value: number | null | undefined) { return value == null ? '—' : new Intl.NumberFormat(locale.value).format(value) }
function quantity(value: number | null | undefined, unit: string) { return value == null ? '—' : `${number(value)} ${unit}` }
function address(value: string) { return !value || value === '0.0.0.0' ? '—' : value }
function availability(row: InstanceRow) { return !row.availabilityDomain || row.availabilityDomain === '空' ? '—' : row.availabilityDomain }
function hasVolume(row: InstanceRow) { return !!row.bootVolumeId.trim() && row.bootVolumeId !== '-1' }
function volumeName(row: InstanceRow) { return row.bootVolumeName && row.bootVolumeName !== '无' ? row.bootVolumeName : row.bootVolumeId || '—' }
function dateTime(value: InstanceRow['createTime'] | Date) {
  if (value == null || value === '') return '—'
  const parsed = value instanceof Date ? value : new Date(typeof value === 'string' ? value.replace(' ', 'T') : value)
  return Number.isNaN(parsed.getTime()) ? String(value) : new Intl.DateTimeFormat(locale.value, {
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).format(parsed)
}
function stateLabel(row: InstanceRow) {
  const code = row.state.toUpperCase()
  return ['RUNNING', 'STOPPED', 'STARTING', 'STOPPING', 'TERMINATING', 'TERMINATED', 'PROVISIONING'].includes(code)
    ? t(`instances.states.${code}`) : row.state || t('instances.states.UNKNOWN')
}
function stateTone(row: InstanceRow) {
  const code = row.state.toUpperCase()
  return code === 'RUNNING' ? 'running' : ['STARTING', 'STOPPING', 'PROVISIONING'].includes(code) ? 'pending'
    : ['TERMINATING', 'TERMINATED'].includes(code) ? 'terminated' : 'neutral'
}
function rowActions(row: InstanceRow): MenuItem[] {
  return [
    { id: 'inspect', label: t('instances.details'), icon: 'information-outline' },
    { id: 'config', label: t('instances.config'), icon: 'chip' },
    { id: 'ip', label: t('instances.changeIp'), icon: 'ip-network-outline' },
    { id: 'ipv6', label: t(row.ipv6Addresses.trim() ? 'instances.manageIpv6' : 'instances.enableIpv6'), icon: 'web' },
    { id: 'name', label: t('instances.rename'), icon: 'pencil-outline' },
    { id: 'volume', label: t('instances.resize'), icon: 'harddisk', disabled: !hasVolume(row) },
    { id: 'terminate', label: t('instances.terminate'), icon: 'power', danger: true },
  ]
}
function rememberFocus() { restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null }
function inspect(row: InstanceRow, volume = false) {
  rememberFocus()
  inspected.value = { ...row }
  inspectVolume.value = volume
}
function runAction(item: MenuItem, row: InstanceRow) {
  if (loading.value || operationOpen.value || item.disabled) return
  if (item.id === 'inspect') { inspect(row); return }
  rememberFocus()
  refreshAfterOperation = false
  selected.value = { ...row }
  if (item.id === 'ip' || item.id === 'ipv6') networkAction.value = item.id
  else operation.value = item.id
}
function resizeVolume(row: InstanceRow) { runAction({ id: 'volume', label: '', icon: '', disabled: !hasVolume(row) }, row) }
function restoreActionFocus() { void nextTick(() => { if (restoreFocus?.isConnected) restoreFocus.focus() }) }
function operationChanged() { refreshAfterOperation = true }
function closeOperation() {
  selected.value = null; operation.value = ''; networkAction.value = ''
  restoreActionFocus()
  // The user has acknowledged the result. A terminate may remove the last row
  // on this page, so allow the subsequent read to correct the page in the URL.
  if (refreshAfterOperation) { refreshAfterOperation = false; void load() }
}
function closeDetails() { inspected.value = null; restoreActionFocus() }
function back() {
  if (operationOpen.value) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push('/tenants/list')
}
// Finish or close the existing operation dialog before leaving its result behind.
onBeforeRouteLeave(() => !operationOpen.value)
onBeforeRouteUpdate(() => !operationOpen.value)
</script>

<template>
  <section class="tenant-instances-page">
    <div class="tenant-instances-toolbar" data-page-error-anchor>
      <PageBackButton :disabled="operationOpen" @click="back" />
      <div class="tenant-instances-tabs" role="group" :aria-label="t('tenantInstances.views')">
        <button type="button" :aria-pressed="tab === 'instances'" :disabled="operationOpen" @click="changeTab('instances')">{{ t('tenantInstances.instances') }}</button>
        <button type="button" :aria-pressed="tab === 'volumes'" :disabled="operationOpen" @click="changeTab('volumes')">{{ t('tenantInstances.volumes') }}</button>
      </div>
      <GhostBtn class="tenant-instances-refresh" :disabled="invalidScope || operationOpen" :loading="loading" :title="refreshTitle" @click="load"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('instances.refresh') }}</GhostBtn>
    </div>
    <div v-if="invalidScope" class="tenant-instances-notice error" role="alert">{{ t('tenantInstances.invalidScope') }}</div>
    <PageErrorNotice v-else-if="problem" style="margin: 10px 18px">{{ instanceError(problem) }} <span v-if="loaded">{{ t('instances.previousData') }}</span></PageErrorNotice>
    <p v-if="tab === 'volumes'" class="tenant-instances-notice">{{ t('tenantInstances.volumesHint') }}</p>
    <div class="tenant-instances-table" :aria-busy="loading">
      <MobileRecordList v-if="compact" :key="tab" drilldown :list-id="tab === 'instances' ? 'tenant-instances' : 'tenant-volumes'" :record-keys="(tab === 'instances' ? rows : volumeRows).map(row => String(row.id))" :loading="loading">
        <MobileRecordCard v-for="row in tab === 'instances' ? rows : volumeRows" :key="row.id" :record-key="String(row.id)" :summary-title="tab === 'volumes' ? volumeName(row) : row.displayName || t('instances.unnamed')" :summary-meta="tab === 'volumes' ? row.displayName || t('instances.unnamed') : row.regionName || row.regionCode || availability(row)" :summary-status="stateLabel(row)" :summary-tone="stateTone(row) === 'running' ? 'success' : stateTone(row) === 'pending' ? 'warning' : stateTone(row) === 'terminated' ? 'danger' : 'neutral'">
          <template #identity>
            <div class="mobile-record-title">{{ tab === 'volumes' ? volumeName(row) : row.displayName || t('instances.unnamed') }}</div>
            <span class="tenant-instance-state mobile-record-subtitle"><i :class="stateTone(row)" aria-hidden="true" />{{ stateLabel(row) }}</span>
          </template>
          <template v-if="tab === 'instances'" #actions>
            <el-dropdown trigger="click" placement="bottom-end" popper-class="tenant-action-menu instance-action-menu" @command="(item: MenuItem) => runAction(item, row)">
              <button type="button" class="tenant-instance-menu" :disabled="loading || operationOpen" :aria-label="t('instances.menuLabel', { name: row.displayName || t('instances.unnamed') })"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
              <template #dropdown><el-dropdown-menu><el-dropdown-item v-for="item in rowActions(row)" :key="item.id" :command="item" :disabled="item.disabled" :class="{ 'danger-item': item.danger }"><i :class="`i-mdi-${item.icon}`" aria-hidden="true" /><span>{{ item.label }}</span></el-dropdown-item></el-dropdown-menu></template>
            </el-dropdown>
          </template>
          <dl v-if="tab === 'instances'" class="mobile-record-fields">
            <div class="mobile-record-wide"><dt>{{ t('tenantInstances.shape') }}</dt><dd>{{ row.shape || '—' }}<span class="mobile-record-subtitle">{{ number(row.ocpus) }} C / {{ number(row.memoryInGBs) }} GB</span></dd></div>
            <div><dt>{{ t('tenantInstances.public') }}</dt><dd>{{ address(row.publicIps) }}</dd></div>
            <div><dt>{{ t('tenantInstances.private') }}</dt><dd>{{ address(row.privateIps) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('tenantInstances.availabilityDomain') }}</dt><dd>{{ availability(row) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('tenantInstances.recordCreated') }}</dt><dd>{{ dateTime(row.createTime) }}</dd></div>
          </dl>
          <dl v-else class="mobile-record-fields">
            <div><dt>{{ t('tenantInstances.volumeSize') }}</dt><dd>{{ quantity(row.bootVolumeSizeInGBs, 'GB') }}</dd></div>
            <div><dt>{{ t('tenantInstances.vpu') }}</dt><dd>{{ number(row.vpusPerGB) }}</dd></div>
            <div class="mobile-record-wide"><dt>{{ t('tenantInstances.linkedInstance') }}</dt><dd>{{ row.displayName || t('instances.unnamed') }}</dd></div>
          </dl>
          <template #footer>
            <button type="button" class="mobile-record-button" :disabled="loading || operationOpen" @click="inspect(row, tab === 'volumes')">{{ t('tenantInstances.details') }}</button>
            <button v-if="tab === 'volumes'" type="button" class="mobile-record-button" :disabled="loading || operationOpen" @click="resizeVolume(row)">{{ t('tenantInstances.expand') }}</button>
          </template>
        </MobileRecordCard>
        <p v-if="!(tab === 'instances' ? rows : volumeRows).length" class="tenant-instances-mobile-empty" role="status">{{ emptyText }}</p>
      </MobileRecordList>
      <el-table v-else-if="tab === 'instances'" key="instances" :data="rows" row-key="id" height="100%" :empty-text="emptyText" :aria-label="t('tenantInstances.instances')">
        <el-table-column prop="displayName" :label="t('instances.name')" min-width="190" show-overflow-tooltip><template #default="{ row }">{{ row.displayName || t('instances.unnamed') }}</template></el-table-column>
        <el-table-column :label="t('tenantInstances.instanceState')" width="125"><template #default="{ row }"><span class="tenant-instance-state"><i :class="stateTone(row as InstanceRow)" aria-hidden="true" />{{ stateLabel(row as InstanceRow) }}</span></template></el-table-column>
        <el-table-column :label="t('tenantInstances.shape')" min-width="220" show-overflow-tooltip><template #default="{ row }"><div>{{ row.shape || '—' }}</div><div class="tenant-instance-quantity">{{ number(row.ocpus) }} C / {{ number(row.memoryInGBs) }} GB</div></template></el-table-column>
        <el-table-column :label="t('tenantInstances.addresses')" width="230"><template #default="{ row }"><div class="tenant-instance-address"><span>{{ t('tenantInstances.public') }}</span><span :title="address(row.publicIps)">{{ address(row.publicIps) }}</span></div><div class="tenant-instance-address"><span>{{ t('tenantInstances.private') }}</span><span :title="address(row.privateIps)">{{ address(row.privateIps) }}</span></div></template></el-table-column>
        <el-table-column :label="t('tenantInstances.availabilityDomain')" min-width="185" show-overflow-tooltip><template #default="{ row }">{{ availability(row as InstanceRow) }}</template></el-table-column>
        <el-table-column :label="t('tenantInstances.recordCreated')" width="215" show-overflow-tooltip><template #default="{ row }"><span class="tenant-instance-date">{{ dateTime(row.createTime) }}</span></template></el-table-column>
        <el-table-column :label="t('instances.actions')" fixed="right" width="76" align="right"><template #default="{ row }"><el-dropdown trigger="click" placement="bottom-end" popper-class="tenant-action-menu instance-action-menu" @command="(item: MenuItem) => runAction(item, row as InstanceRow)"><button type="button" class="tenant-instance-menu" :disabled="loading || operationOpen" :aria-label="t('instances.menuLabel', { name: row.displayName || t('instances.unnamed') })"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button><template #dropdown><el-dropdown-menu><el-dropdown-item v-for="item in rowActions(row as InstanceRow)" :key="item.id" :command="item" :disabled="item.disabled" :class="{ 'danger-item': item.danger }"><i :class="`i-mdi-${item.icon}`" aria-hidden="true" /><span>{{ item.label }}</span></el-dropdown-item></el-dropdown-menu></template></el-dropdown></template></el-table-column>
      </el-table>
      <el-table v-else key="volumes" :data="volumeRows" row-key="id" height="100%" :empty-text="emptyText" :aria-label="t('tenantInstances.volumes')">
        <el-table-column :label="t('tenantInstances.volumeName')" min-width="240" show-overflow-tooltip><template #default="{ row }">{{ volumeName(row as InstanceRow) }}</template></el-table-column>
        <el-table-column :label="t('tenantInstances.volumeSize')" width="140" align="right"><template #default="{ row }"><span class="tenant-instance-quantity">{{ quantity(row.bootVolumeSizeInGBs, 'GB') }}</span></template></el-table-column>
        <el-table-column :label="t('tenantInstances.vpu')" width="110" align="right"><template #default="{ row }">{{ number(row.vpusPerGB) }}</template></el-table-column>
        <el-table-column prop="displayName" :label="t('tenantInstances.linkedInstance')" min-width="200" show-overflow-tooltip><template #default="{ row }">{{ row.displayName || t('instances.unnamed') }}</template></el-table-column>
        <el-table-column :label="t('tenantInstances.instanceState')" width="140"><template #default="{ row }"><span class="tenant-instance-state"><i :class="stateTone(row as InstanceRow)" aria-hidden="true" />{{ stateLabel(row as InstanceRow) }}</span></template></el-table-column>
        <el-table-column :label="t('instances.actions')" fixed="right" width="170" align="right"><template #default="{ row }"><div class="tenant-volume-actions"><button type="button" :disabled="loading || operationOpen" @click="inspect(row as InstanceRow, true)">{{ t('tenantInstances.details') }}</button><button type="button" :disabled="loading || operationOpen" @click="resizeVolume(row as InstanceRow)">{{ t('tenantInstances.expand') }}</button></div></template></el-table-column>
      </el-table>
    </div>
    <PagePagination :disabled="loading || !loaded || invalidScope || operationOpen" :current-page="page + 1" :page-size="size" :total="total" :page-sizes="pageSizes" @current-change="changePage" @size-change="changeSize">
      <div class="tenant-instances-context"><span v-if="loaded">{{ rangeLabel }}</span><span v-if="!invalidScope" :title="t('tenantInstances.tenantScope', { id: tenantId })">{{ t('tenantInstances.tenantScope', { id: tenantId }) }}</span></div>
    </PagePagination>
    <InstanceOperationDialog v-if="selected && operation" :key="`${selected.id}-${operation}`" :row="selected" :action="operation" @close="closeOperation" @changed="operationChanged" />
    <InstanceNetworkDialog v-if="selected && networkAction" :key="`${selected.id}-${networkAction}`" :row="selected" :action="networkAction" @close="closeOperation" @changed="operationChanged" />
    <el-dialog :model-value="!!inspected" :title="t(inspectVolume ? 'tenantInstances.volumeDetails' : 'instances.details')" width="680px" class="tenant-instance-details" append-to-body @close="closeDetails">
      <p class="tenant-instance-details-note">{{ t('tenantInstances.detailsHint') }}</p>
      <dl class="tenant-instance-fields"><div v-for="field in detailFields" :key="field.key"><dt>{{ t(field.key) }}</dt><dd>{{ field.value }}</dd></div></dl>
      <template #footer><GhostBtn @click="closeDetails">{{ t('instances.close') }}</GhostBtn></template>
    </el-dialog>
  </section>
</template>
