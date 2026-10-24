<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { mobileRecordSelection } from '@/composables/useMobileRecords'
import VnicActionDialog from './components/VnicActionDialog.vue'
import {
  getVnicData, isVnicInstanceId, vnicError,
  type VnicRow, type VnicAction, type VnicMutationResult, type VnicApiError,
} from '@/api/vnic'
import './vnic.scss'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const compact = useCompactViewport()
const instanceId = computed(() => isVnicInstanceId(route.query.instanceId) ? route.query.instanceId : '')
const rows = shallowRef<VnicRow[]>([])
const tenantId = ref('')
const loaded = ref(false)
const loading = ref(false)
const lastRead = ref<number | null>(null)
const readError = shallowRef<VnicApiError | null>(null)
const search = ref('')
const typeFilter = ref<'all' | 'primary' | 'secondary'>('all')
const busy = ref(false)
const dirty = ref(false)
const requiresReview = ref(false)
const lastResult = shallowRef<VnicMutationResult | null>(null)
const writeError = shallowRef<VnicApiError | null>(null)
const actionOpen = ref(false)
const action = ref<VnicAction>('create')
const actionRow = shallowRef<VnicRow | null>(null)
const actionAddress = ref('')
const ipv6Open = ref(false)
const ipv6VnicId = ref('')
let readController: AbortController | null = null
let scope = 0
let disposed = false
const downloadUrls = new Set<string>()
const downloadTimers = new Set<ReturnType<typeof setTimeout>>()

const primarySubnetId = computed(() => rows.value.find(row => row.isPrimary === true)?.subnetId || '')
const secondaryCount = computed(() => rows.value.filter(row => row.isPrimary === false).length)
const canWrite = computed(() => !!instanceId.value && loaded.value && !loading.value && !busy.value && !dirty.value && !requiresReview.value && !readError.value)
const queryDisabled = computed(() => !instanceId.value || loading.value || busy.value || actionOpen.value)
const ipv6Row = computed(() => rows.value.find(row => row.vnicId === ipv6VnicId.value) || null)
const ipv6Addresses = computed(() => ipv6Row.value?.ipv6Addresses || [])
watch([rows, () => route.query.mobileRecord, () => route.query.mobileRecordParents], () => {
  if (ipv6Open.value || actionOpen.value) return
  const row = rows.value.find(item => mobileRecordSelection(route.query, `vnic-ipv6-${item.vnicId}`))
  if (row) { ipv6VnicId.value = row.vnicId; ipv6Open.value = true }
})
const numberFormat = computed(() => new Intl.NumberFormat(locale.value.startsWith('zh') ? 'zh-CN' : 'en-US'))
function count(value: number) { return numberFormat.value.format(value) }
function name(row: VnicRow) { return row.vnicDisplayName || t('vnic.unnamed') }
function typeLabel(row: VnicRow) { return t(`vnic.${row.isPrimary === true ? 'primary' : row.isPrimary === false ? 'secondary' : 'unknownType'}`) }
function stateLabel(value: string) {
  const state = value.toLowerCase()
  return ['attached', 'attaching', 'detached', 'detaching'].includes(state) ? t(`vnic.states.${state}`) : value || t('vnic.states.unknown')
}
function stateClass(value: string) {
  const state = value.toLowerCase()
  return state === 'attached' ? 'attached' : ['attaching', 'detaching'].includes(state) ? 'pending' : ''
}
function errorText(error: VnicApiError) { return t(`vnic.errors.${error.key}`) + (error.detail ? ` ${error.detail}` : '') }
const filteredRows = computed(() => {
  const keyword = search.value.trim().toLocaleLowerCase()
  return rows.value.filter(row => {
    if (typeFilter.value === 'primary' && row.isPrimary !== true) return false
    if (typeFilter.value === 'secondary' && row.isPrimary !== false) return false
    return !keyword || [name(row), row.vnicId, row.subnetId, row.publicIp, row.privateIp, ...row.ipv6Addresses]
      .some(value => value.toLocaleLowerCase().includes(keyword))
  }).slice().sort((a, b) => Number(b.isPrimary === true) - Number(a.isPrimary === true))
})
const emptyText = computed(() => !instanceId.value ? t('vnic.invalidContext')
  : loading.value ? t('vnic.loading') : readError.value ? '—'
    : !loaded.value ? t('vnic.queryIdle') : rows.value.length ? t('vnic.noMatch') : t('vnic.empty'))
const lastReadText = computed(() => lastRead.value === null ? '' : new Intl.DateTimeFormat(
  locale.value.startsWith('zh') ? 'zh-CN' : 'en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' },
).format(lastRead.value))
const resultText = computed(() => writeError.value
  ? t(writeError.value.writeAttempted ? 'vnic.resultUnknown' : 'vnic.errors.invalidInput')
  : lastResult.value ? t(`vnic.result${lastResult.value.outcome === 'completed' ? 'Completed' : lastResult.value.outcome === 'partial' ? 'Partial' : 'Failed'}`) : '')

async function load(mode: 'loadData' | 'refresh' = 'loadData') {
  if (!instanceId.value || busy.value || disposed) return
  readController?.abort()
  const controller = new AbortController()
  readController = controller
  const version = scope
  const id = instanceId.value
  const current = () => !disposed && version === scope && readController === controller && !controller.signal.aborted
  loading.value = true
  readError.value = null
  try {
    const data = await getVnicData(id, mode, controller.signal)
    if (!current()) return
    rows.value = data.rows
    if (data.tenantId) tenantId.value = data.tenantId
    loaded.value = true
    dirty.value = false
    lastRead.value = Date.now()
  } catch (cause) {
    if (current()) readError.value = vnicError(cause)
  } finally {
    if (current()) { loading.value = false; readController = null }
  }
}
function query() { if (!queryDisabled.value) void load('loadData') }
function refresh() { if (!queryDisabled.value) void load('refresh') }
function setBusy(value: boolean) {
  busy.value = value
  if (value) {
    readController?.abort()
    readController = null
    loading.value = false
    dirty.value = true
    lastResult.value = null
    writeError.value = null
  }
}
function settled(result: VnicMutationResult | null, error: VnicApiError | null) {
  if (disposed) return
  busy.value = false
  lastResult.value = result
  writeError.value = error
  const attempted = !!result || !!error?.writeAttempted
  dirty.value = attempted
  requiresReview.value = attempted && (!result || result.outcome !== 'completed')
  if (attempted) void load('loadData')
}
function acknowledgeReview() {
  if (busy.value || loading.value || dirty.value || readError.value || !loaded.value) return
  requiresReview.value = false
  lastResult.value = null
  writeError.value = null
}
function dismissResult() {
  if (requiresReview.value) return
  lastResult.value = null
  writeError.value = null
}
function openAction(next: VnicAction, row: VnicRow | null = null, address = '') {
  if (!canWrite.value || actionOpen.value) return
  if (row && !rows.value.some(current => current.vnicId === row.vnicId)) return
  if (next === 'delete' && row?.isPrimary !== false) return
  if (next === 'deleteIpv6' && (!row || !row.ipv6Addresses.includes(address))) return
  if (next === 'deleteAllSecondary' && (!secondaryCount.value || rows.value.some(current => current.isPrimary === null))) return
  action.value = next
  // Keep the confirmed target independent of the next list refresh.
  actionRow.value = row ? { ...row, ipv6Addresses: [...row.ipv6Addresses], ipv6Ids: [...row.ipv6Ids] } : null
  actionAddress.value = address
  actionOpen.value = true
}
function createVnic() { openAction('create') }
function moreAction(command: string) {
  if (command === 'configureLoadBalancer' || command === 'restoreNetwork' || command === 'deleteAllSecondary') openAction(command)
}
function viewIpv6(row: VnicRow) {
  if (busy.value || actionOpen.value) return
  ipv6VnicId.value = row.vnicId
  ipv6Open.value = true
}
function addIpv6() { if (ipv6Row.value) openAction('createIpv6', ipv6Row.value) }
function deleteIpv6(address: string) { if (ipv6Row.value) openAction('deleteIpv6', ipv6Row.value, address) }
function rowAction(command: string, row: VnicRow) {
  if (command === 'ipv6') viewIpv6(row)
  else if (command === 'copyVnic') void copy(row.vnicId)
  else if (command === 'copySubnet') void copy(row.subnetId)
  else if (command === 'createIpv6' || command === 'delete' || command === 'changeIp') openAction(command, row)
}
async function copy(value: string) {
  if (!value) return
  const version = scope
  try {
    await navigator.clipboard.writeText(value)
    if (!disposed && version === scope) ElMessage.success(t('vnic.copied'))
  } catch {
    if (!disposed && version === scope) ElMessage.error(t('vnic.copyFailed'))
  }
}
function exportAddresses() {
  if (!ipv6Row.value || !ipv6Addresses.value.length) return
  let url = ''
  const link = document.createElement('a')
  try {
    url = URL.createObjectURL(new Blob([ipv6Addresses.value.join('\n')], { type: 'text/plain;charset=utf-8' }))
    downloadUrls.add(url)
    const filename = (ipv6Row.value.vnicDisplayName || 'VNIC').replace(/[\x00-\x1f\x7f<>:"/\\|?*]/g, '_').slice(0, 80) || 'VNIC'
    link.href = url
    link.download = `${filename}_IPv6_${new Date().toISOString().replace(/[:.]/g, '-')}.txt`
    document.body.appendChild(link)
    link.click()
    ElMessage.success(t('vnic.exportStarted'))
    const timer = setTimeout(() => { URL.revokeObjectURL(url); downloadUrls.delete(url); downloadTimers.delete(timer) }, 30000)
    downloadTimers.add(timer)
  } catch {
    if (url) { URL.revokeObjectURL(url); downloadUrls.delete(url) }
    ElMessage.error(t('vnic.exportFailed'))
  } finally { link.remove() }
}
function canLeave() {
  if (!busy.value) return true
  ElMessage.warning(t('vnic.leavePending'))
  return false
}
function goBack() {
  if (!canLeave()) return
  const previous: unknown = window.history.state?.back
  if (typeof previous === 'string' && previous && previous !== route.fullPath) router.back()
  else void router.push({ path: '/oci/list', query: tenantId.value ? { tenantId: tenantId.value } : {} })
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (!busy.value) return
  event.preventDefault()
  event.returnValue = ''
}
onBeforeRouteLeave(canLeave)
onBeforeRouteUpdate((to, from) => to.path === from.path && to.query.instanceId === from.query.instanceId ? true : canLeave())
watch([() => route.path, instanceId], () => {
  scope += 1
  readController?.abort()
  readController = null
  rows.value = []
  tenantId.value = ''
  loaded.value = false
  loading.value = false
  lastRead.value = null
  readError.value = null
  search.value = ''
  typeFilter.value = 'all'
  dirty.value = false
  requiresReview.value = false
  lastResult.value = null
  writeError.value = null
  actionOpen.value = false
  actionRow.value = null
  actionAddress.value = ''
  ipv6Open.value = false
  ipv6VnicId.value = ''
  // The desktop page deliberately waits for an explicit query before cloud reads.
}, { immediate: true })
window.addEventListener('beforeunload', beforeUnload)
onBeforeUnmount(() => {
  disposed = true
  scope += 1
  readController?.abort()
  window.removeEventListener('beforeunload', beforeUnload)
  downloadTimers.forEach(clearTimeout)
  downloadUrls.forEach(url => URL.revokeObjectURL(url))
})

// Column slots cannot infer the parent table’s row type.
const ElTableColumn = BaseTableColumn<VnicRow>
</script>

<template>
  <section class="vnic-page" :aria-label="t('vnic.label')">
    <div class="vnic-toolbar">
      <PageBackButton :disabled="busy" @click="goBack" />
      <el-input v-model="search" class="vnic-search" clearable :placeholder="t('vnic.search')" :aria-label="t('vnic.search')"><template #prefix><i class="i-mdi-magnify" aria-hidden="true" /></template></el-input>
      <el-select v-model="typeFilter" class="vnic-filter" :aria-label="t('vnic.typeFilter')">
        <el-option value="all" :label="t('vnic.allTypes')" /><el-option value="primary" :label="t('vnic.primary')" /><el-option value="secondary" :label="t('vnic.secondary')" />
      </el-select>
      <div class="vnic-toolbar-actions" data-page-error-anchor>
        <el-button :loading="loading" :disabled="queryDisabled" @click="query">{{ t('vnic.query') }}</el-button>
        <button class="vnic-icon-button" type="button" :disabled="queryDisabled" :title="t('vnic.refresh')" :aria-label="t('vnic.refresh')" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" /></button>
        <el-button type="primary" :disabled="!canWrite || actionOpen" @click="createVnic">{{ t('vnic.create') }}</el-button>
        <el-dropdown trigger="click" :disabled="!canWrite || actionOpen" @command="moreAction">
          <button class="vnic-icon-button" type="button" :disabled="!canWrite || actionOpen" :aria-label="t('vnic.more')" :title="t('vnic.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
          <template #dropdown><el-dropdown-menu>
            <el-dropdown-item command="configureLoadBalancer">{{ t('vnic.configureLoadBalancer') }}</el-dropdown-item>
            <el-dropdown-item command="restoreNetwork">{{ t('vnic.restoreNetwork') }}</el-dropdown-item>
            <el-dropdown-item command="deleteAllSecondary" :disabled="!secondaryCount || rows.some(row => row.isPrimary === null)" divided>{{ t('vnic.deleteAllSecondary') }}</el-dropdown-item>
          </el-dropdown-menu></template>
        </el-dropdown>
      </div>
    </div>

    <div v-if="busy" class="vnic-notice" role="status">{{ t('vnic.pending') }}</div>
    <PageErrorNotice v-if="readError"><span v-if="loaded">{{ t('vnic.retained') }}</span><span>{{ errorText(readError) }}</span><el-button :loading="loading" :disabled="queryDisabled" @click="query">{{ t('vnic.query') }}</el-button></PageErrorNotice>
    <div v-if="dirty && !busy" class="vnic-notice" role="status">{{ t('vnic.stale') }}</div>
    <PageErrorNotice v-if="resultText && !requiresReview && (writeError || lastResult?.outcome === 'failed')"><span>{{ resultText }} {{ writeError?.detail || lastResult?.message }}</span><el-button @click="dismissResult">{{ t('vnic.dismiss') }}</el-button></PageErrorNotice>
    <div v-else-if="resultText" class="vnic-notice vnic-result" role="status">
      <div><p>{{ resultText }}</p><PageErrorNotice v-if="writeError?.detail || (lastResult?.message && !lastResult.success)">{{ writeError?.detail || lastResult?.message }}</PageErrorNotice><p v-else-if="lastResult?.message">{{ lastResult.message }}</p><p v-if="requiresReview">{{ t('vnic.reviewRequired') }}</p></div>
      <el-button v-if="requiresReview" :disabled="loading || dirty || !!readError || !loaded || actionOpen" :title="dirty ? t('vnic.reviewQueryFirst') : undefined" @click="acknowledgeReview">{{ t('vnic.review') }}</el-button>
      <button v-else class="vnic-icon-button" type="button" :aria-label="t('vnic.dismiss')" :title="t('vnic.dismiss')" @click="dismissResult"><i class="i-mdi-close" aria-hidden="true" /></button>
    </div>

    <div class="vnic-table" :aria-busy="loading">
      <MobileRecordList v-if="compact" drilldown list-id="vnics" :record-keys="filteredRows.map(row => row.vnicId)" :loading="loading">
        <MobileRecordCard v-for="row in filteredRows" :key="row.vnicId" :record-key="row.vnicId" :summary-title="name(row)" :summary-meta="typeLabel(row)" :summary-status="stateLabel(row.lifecycleState)" :summary-tone="stateClass(row.lifecycleState) === 'attached' ? 'success' : stateClass(row.lifecycleState) === 'pending' ? 'warning' : 'neutral'">
          <template #identity><div class="mobile-record-title">{{ name(row) }}</div><span class="mobile-record-subtitle">{{ typeLabel(row) }} · {{ stateLabel(row.lifecycleState) }}</span></template>
          <dl class="mobile-record-fields">
            <div class="mobile-record-wide"><dt>{{ t('vnic.copyVnic') }}</dt><dd><button class="vnic-id" type="button" @click="copy(row.vnicId)">{{ row.vnicId }}</button></dd></div>
            <div><dt>{{ t('vnic.publicIp') }}</dt><dd><button v-if="row.publicIp" class="vnic-copy-address" type="button" :aria-label="`${t('vnic.copyPublic')}: ${row.publicIp}`" @click="copy(row.publicIp)">{{ row.publicIp }}</button><span v-else>—</span></dd></div>
            <div><dt>{{ t('vnic.privateIp') }}</dt><dd><button v-if="row.privateIp" class="vnic-copy-address" type="button" :aria-label="`${t('vnic.copyPrivate')}: ${row.privateIp}`" @click="copy(row.privateIp)">{{ row.privateIp }}</button><span v-else>—</span></dd></div>
            <div class="mobile-record-wide"><dt>{{ t('vnic.subnet') }}</dt><dd><button v-if="row.subnetId" class="vnic-id subnet" type="button" :aria-label="`${t('vnic.copySubnet')}: ${row.subnetId}`" @click="copy(row.subnetId)">{{ row.subnetId }}</button><span v-else>—</span></dd></div>
            <div><dt>{{ t('vnic.ipv6') }}</dt><dd><button class="vnic-count-button" type="button" :disabled="busy || actionOpen" :aria-label="`${t('vnic.viewIpv6')}: ${count(row.ipv6Addresses.length)}`" @click="viewIpv6(row)">{{ count(row.ipv6Addresses.length) }}<i class="i-mdi-chevron-right" aria-hidden="true" /></button></dd></div>
          </dl>
          <template #footer><button type="button" class="mobile-record-button" :disabled="!canWrite || actionOpen" @click="openAction('changeIp', row)">{{ t('vnic.changeIp') }}</button><button type="button" class="mobile-record-button" :disabled="!canWrite || actionOpen" @click="openAction('createIpv6', row)">{{ t('vnic.addIpv6') }}</button><button v-if="row.isPrimary === false" type="button" class="mobile-record-button" :disabled="!canWrite || actionOpen" @click="openAction('delete', row)">{{ t('vnic.deleteVnic') }}</button></template>
        </MobileRecordCard>
        <p v-if="!filteredRows.length" class="vnic-mobile-empty" role="status">{{ emptyText }}</p>
      </MobileRecordList>
      <el-table v-else :data="filteredRows" row-key="vnicId" height="100%" :empty-text="emptyText">
        <el-table-column :label="t('vnic.name')" min-width="230"><template #default="{ row }"><div class="vnic-name" :title="name(row)">{{ name(row) }}</div><button class="vnic-id" type="button" :title="`${t('vnic.copyVnic')}: ${row.vnicId}`" @click="copy(row.vnicId)">{{ row.vnicId }}</button></template></el-table-column>
        <el-table-column :label="t('vnic.type')" width="130"><template #default="{ row }"><span class="vnic-type" :class="{ primary: row.isPrimary === true }">{{ typeLabel(row) }}</span></template></el-table-column>
        <el-table-column :label="t('vnic.state')" width="150"><template #default="{ row }"><span class="vnic-state"><i :class="stateClass(row.lifecycleState)" aria-hidden="true" />{{ stateLabel(row.lifecycleState) }}</span></template></el-table-column>
        <el-table-column :label="t('vnic.publicIp')" min-width="175"><template #default="{ row }"><div class="vnic-address-cell"><button v-if="row.publicIp" class="vnic-copy-address" type="button" :title="`${t('vnic.copyPublic')}: ${row.publicIp}`" @click="copy(row.publicIp)">{{ row.publicIp }}</button><span v-else>—</span><button class="vnic-icon-button compact" type="button" :disabled="!canWrite || actionOpen" :title="t('vnic.changeIp')" :aria-label="t('vnic.changeIp')" @click="openAction('changeIp', row)"><i class="i-mdi-swap-horizontal" aria-hidden="true" /></button></div></template></el-table-column>
        <el-table-column :label="t('vnic.privateIp')" min-width="160"><template #default="{ row }"><button v-if="row.privateIp" class="vnic-copy-address" type="button" :title="`${t('vnic.copyPrivate')}: ${row.privateIp}`" @click="copy(row.privateIp)">{{ row.privateIp }}</button><span v-else>—</span></template></el-table-column>
        <el-table-column :label="t('vnic.subnet')" min-width="200"><template #default="{ row }"><button v-if="row.subnetId" class="vnic-id subnet" type="button" :title="`${t('vnic.copySubnet')}: ${row.subnetId}`" @click="copy(row.subnetId)">{{ row.subnetId }}</button><span v-else>—</span></template></el-table-column>
        <el-table-column :label="t('vnic.ipv6')" width="155"><template #default="{ row }"><button class="vnic-count-button" type="button" :disabled="busy || actionOpen" :title="t('vnic.viewIpv6')" :aria-label="`${t('vnic.viewIpv6')}: ${count(row.ipv6Addresses.length)}`" @click="viewIpv6(row)">{{ count(row.ipv6Addresses.length) }}<i class="i-mdi-chevron-right" aria-hidden="true" /></button></template></el-table-column>
        <el-table-column :label="t('vnic.actions')" width="95" fixed="right" align="right"><template #default="{ row }">
          <el-dropdown trigger="click" :disabled="busy || actionOpen" @command="rowAction($event, row)">
            <button class="vnic-icon-button compact" type="button" :disabled="busy || actionOpen" :aria-label="`${t('vnic.actions')}: ${name(row)}`"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
            <template #dropdown><el-dropdown-menu>
              <el-dropdown-item command="ipv6">{{ t('vnic.viewIpv6') }}</el-dropdown-item>
              <el-dropdown-item command="createIpv6" :disabled="!canWrite">{{ t('vnic.addIpv6') }}</el-dropdown-item>
              <el-dropdown-item command="changeIp" :disabled="!canWrite">{{ t('vnic.changeIp') }}</el-dropdown-item>
              <el-dropdown-item command="copyVnic">{{ t('vnic.copyVnic') }}</el-dropdown-item>
              <el-dropdown-item command="copySubnet" :disabled="!row.subnetId">{{ t('vnic.copySubnet') }}</el-dropdown-item>
              <el-dropdown-item v-if="row.isPrimary === false" command="delete" :disabled="!canWrite" divided>{{ t('vnic.deleteVnic') }}</el-dropdown-item>
            </el-dropdown-menu></template>
          </el-dropdown>
        </template></el-table-column>
      </el-table>
    </div>
    <footer class="vnic-footer">
      <span class="vnic-context" :title="instanceId">{{ t('vnic.instance') }} · {{ instanceId || '—' }}</span>
      <span v-if="loaded">{{ t('vnic.count', { visible: count(filteredRows.length), total: count(rows.length) }) }} · {{ t('vnic.ipv6Count', { count: count(rows.reduce((total, row) => total + row.ipv6Addresses.length, 0)) }) }}</span>
      <span v-if="lastReadText">{{ t('vnic.lastRead', { time: lastReadText }) }}</span>
    </footer>

    <el-dialog v-model="ipv6Open" class="vnic-ipv6-dialog" :title="t('vnic.ipv6Title')" width="740px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!busy && !actionOpen" :show-close="!busy && !actionOpen">
      <p class="vnic-dialog-context">{{ ipv6Row ? name(ipv6Row) : ipv6VnicId }}</p>
      <p class="vnic-dialog-note">{{ t('vnic.updatedIpv6') }}</p>
      <div class="vnic-ipv6-toolbar"><el-button :disabled="!ipv6Addresses.length" @click="exportAddresses">{{ t('vnic.export') }}</el-button><el-button :disabled="!ipv6Row || !canWrite || actionOpen" @click="addIpv6">{{ t('vnic.addIpv6') }}</el-button></div>
      <div class="vnic-ipv6-scroll">
        <MobileRecordList v-if="compact && ipv6Open && ipv6Addresses.length" drilldown :list-id="`vnic-ipv6-${ipv6VnicId}`" :record-keys="ipv6Addresses">
          <MobileRecordCard v-for="address in ipv6Addresses" :key="address" :record-key="address" :summary-title="address" :summary-meta="ipv6Row ? name(ipv6Row) : ''">
            <template #identity><div class="mobile-record-title">{{ address }}</div><span v-if="ipv6Row" class="mobile-record-subtitle">{{ name(ipv6Row) }}</span></template>
            <template #footer><button type="button" class="mobile-record-button" @click="copy(address)">{{ t('vnic.copy') }}</button><button type="button" class="mobile-record-button" :disabled="!canWrite || actionOpen" @click="deleteIpv6(address)">{{ t('vnic.deleteAddress') }}</button></template>
          </MobileRecordCard>
        </MobileRecordList>
        <table v-else-if="!compact && ipv6Addresses.length" class="vnic-ipv6-table"><thead><tr><th>{{ t('vnic.address') }}</th><th>{{ t('vnic.actions') }}</th></tr></thead><tbody><tr v-for="address in ipv6Addresses" :key="address"><td>{{ address }}</td><td><button type="button" class="vnic-icon-button compact" :title="t('vnic.copy')" :aria-label="`${t('vnic.copy')}: ${address}`" @click="copy(address)"><i class="i-mdi-content-copy" aria-hidden="true" /></button><button type="button" class="vnic-icon-button compact" :disabled="!canWrite || actionOpen" :title="t('vnic.deleteAddress')" :aria-label="`${t('vnic.deleteAddress')}: ${address}`" @click="deleteIpv6(address)"><i class="i-mdi-delete-outline" aria-hidden="true" /></button></td></tr></tbody></table>
        <p v-else class="vnic-ipv6-empty">{{ t(ipv6Row ? 'vnic.ipv6Empty' : 'vnic.ipv6Missing') }}</p>
      </div>
      <template #footer><el-button :disabled="busy || actionOpen" @click="ipv6Open = false">{{ t('vnic.close') }}</el-button></template>
    </el-dialog>
    <VnicActionDialog v-model="actionOpen" :instance-id="instanceId" :action="action" :row="actionRow" :ipv6-address="actionAddress" :primary-subnet-id="primarySubnetId" :secondary-count="secondaryCount" @busy="setBusy" @settled="settled" />
  </section>
</template>
