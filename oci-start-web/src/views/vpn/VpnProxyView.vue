<script setup lang="ts">
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import SecuritySecretInput from '@/views/settings/security/SecuritySecretInput.vue'
import type { VpnProxyApiError, VpnProxyInput, VpnProxyRecord } from '@/api/vpnProxy'
import ProxyEditorDialog from './components/ProxyEditorDialog.vue'
import { useVpnProxy } from './useVpnProxy'
import './vpn-proxy.scss'

const compact = useCompactViewport()
const { t, locale } = useI18n()
const router = useRouter()
const route = useRoute()
const proxy = useVpnProxy()
const { rows, page, size, total, loading, loaded, problem, parents, parentsLoading, parentsProblem,
  operation, mutation, canOperate, canSubmit, contextLocked, requiresReview, reviewReady, batch,
  passwordTarget, password, passwordLoading, passwordProblem } = proxy
page.value = Math.max(1, Math.floor(Number(route.query.proxyPage) || 1))
size.value = [10, 20, 50].includes(Number(route.query.proxySize)) ? Number(route.query.proxySize) : 10
watch([page, size], () => { if (compact.value) void router.replace({ path: route.path, query: { ...route.query, proxyPage: String(page.value), proxySize: String(size.value) } }) })
const resultPage = ref(1)
const isEditor = computed(() => operation.value?.kind === 'create' || operation.value?.kind === 'edit')
const actionVisible = computed(() => !!operation.value && !isEditor.value)
const editorVisible = computed({ get: () => isEditor.value, set: (visible: boolean) => { if (!visible) proxy.closeOperation() } })
const batchEntries = computed(() => batch.value.entries.slice((resultPage.value - 1) * 10, resultPage.value * 10))
const currentBatch = computed(() => batch.value.entries.find(entry => entry.id === batch.value.currentId))
const batchTitle = computed(() => t(`vpnProxy.${batch.value.state === 'preparing' ? 'preparing'
  : batch.value.state === 'stopped' ? 'batchStopped' : batch.value.state === 'completed' ? 'batchCompleted' : 'batchRunning'}`))
const operationTitle = computed(() => {
  const kind = operation.value?.kind
  if (kind === 'create' || kind === 'edit') return t(`vpnProxy.editor.${kind === 'create' ? 'createTitle' : 'editTitle'}`)
  return kind ? t(`vpnProxy.titles.${kind}`) : ''
})
const targetName = computed(() => operation.value?.row ? nameOf(operation.value.row) : '')
const confirmHint = computed(() => {
  const item = operation.value
  if (!item) return ''
  if (item.kind === 'create' || item.kind === 'edit') return ''
  if (item.kind === 'force') return t(`vpnProxy.confirmations.${item.nextForce === 1 ? 'forceOn' : 'forceOff'}`)
  return t(`vpnProxy.confirmations.${item.kind}`, { target: targetName.value })
})
const successLabel = computed(() => t(`vpnProxy.${mutation.value.result?.kind === 'delete' ? 'deleted'
  : mutation.value.result?.kind === 'force' ? 'forceSaved' : 'saved'}`))
function number(value: number): string { return new Intl.NumberFormat(locale.value).format(value) }
function nameOf(row: Pick<VpnProxyRecord, 'id' | 'customName' | 'proxyHost' | 'proxyPort'>): string {
  return row.customName || endpoint(row) || `#${row.id}`
}
function endpoint(row: Pick<VpnProxyRecord, 'proxyHost' | 'proxyPort'>): string {
  const host = row.proxyHost.includes(':') && !row.proxyHost.startsWith('[') ? `[${row.proxyHost}]` : row.proxyHost
  return host ? `${host}:${row.proxyPort ?? '—'}` : '—'
}
function bindings(row: VpnProxyRecord): string {
  return row.tenantIds.length ? row.tenantName || row.tenantIds.map(id => `#${id}`).join(', ') : t('vpnProxy.global')
}
function errorLabel(error: VpnProxyApiError | null): string { return error ? t(`vpnProxy.errors.${error.key}`) : '' }
function back() { if (window.history.state?.back) router.back(); else void router.push('/boot/dashboard') }
function add() { proxy.openOperation('create') }
function edit(row: VpnProxyRecord) { proxy.openOperation('edit', row) }
function test(row: VpnProxyRecord) { proxy.openOperation('test', row) }
function testAll() { proxy.openOperation('testAll') }
function rowCommand(command: unknown, row: VpnProxyRecord) {
  if (command === 'delete') proxy.openOperation('delete', row)
  else if (command === 'force' && row.forceProxy !== null) proxy.openOperation('force', row, row.forceProxy === 1 ? 0 : 1)
}
async function save(input: VpnProxyInput) {
  if (!canSubmit.value) return
  await proxy.submitOperation(input)
  if (mutation.value.outcome === 'success' || mutation.value.outcome === 'unknown') proxy.closeOperation()
}
function closeAction() { if (!mutation.value.pending) proxy.closeOperation() }
function submitAction() { if (canSubmit.value) void proxy.submitOperation() }
function closePassword() { proxy.closePassword() }
function beforeUnload(event: BeforeUnloadEvent) {
  if (mutation.value.pending || isEditor.value || requiresReview.value) { event.preventDefault(); event.returnValue = '' }
}
watch(() => batch.value.state, state => { if (state === 'preparing') resultPage.value = 1 })
onBeforeRouteLeave(() => !(contextLocked.value || requiresReview.value))
onMounted(() => {
  window.addEventListener('beforeunload', beforeUnload)
  void proxy.refresh(); void proxy.loadParents()
})
onBeforeUnmount(() => window.removeEventListener('beforeunload', beforeUnload))
</script>

<template>
  <section class="vpn-proxies" :aria-label="t('vpnProxy.title')">
    <header class="vpn-toolbar">
      <PageBackButton :disabled="contextLocked || requiresReview" @click="back" />
      <span class="vpn-total">{{ loaded ? t('vpnProxy.total', { count: number(total) }) : t('vpnProxy.loading') }}</span>
      <div class="vpn-toolbar-actions" data-page-error-anchor>
        <GhostBtn :disabled="!canOperate || total === 0" @click="testAll"><i class="i-mdi-lan-connect" aria-hidden="true" />{{ t('vpnProxy.testAll') }}</GhostBtn>
        <GhostBtn :loading="loading" :disabled="contextLocked" @click="proxy.refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('vpnProxy.refresh') }}</GhostBtn>
        <PrimaryBtn :disabled="!canOperate" @click="add"><i class="i-mdi-plus" aria-hidden="true" />{{ t('vpnProxy.add') }}</PrimaryBtn>
      </div>
    </header>
    <div v-if="requiresReview && !operation" class="vpn-notice is-warning" role="alert">
      <p>{{ t('vpnProxy.unknownResult') }}</p><div class="vpn-inline-actions"><GhostBtn :loading="loading" @click="proxy.refresh">{{ t('vpnProxy.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady" @click="proxy.acknowledgeReview">{{ t('vpnProxy.reviewed') }}</GhostBtn></div>
    </div>
    <PageErrorNotice v-if="problem">{{ errorLabel(problem) }} {{ loaded ? t('vpnProxy.retained') : '' }}</PageErrorNotice>
    <p v-if="!operation && mutation.outcome === 'success' && mutation.result && ['create', 'edit', 'delete', 'force'].includes(mutation.result.kind)" class="vpn-page-receipt" role="status">{{ successLabel }}</p>
    <div class="vpn-table-scroll" :aria-busy="loading">
      <MobileRecordList v-if="compact" drilldown :list-id="'vpn-table'" :record-keys="rows.map(row => row.id)" :loading="loading">
          <MobileRecordCard v-for="row in rows" :key="row.id" :record-key="row.id" :summary-title="nameOf(row)" :summary-meta="endpoint(row)" :summary-status="t(`vpnProxy.${row.availableStatus === 1 ? 'available' : row.availableStatus === 0 ? 'unavailable' : 'unknown'}`)" :summary-tone="row.availableStatus === 1 ? 'success' : row.availableStatus === 0 ? 'danger' : 'neutral'">
            <template #identity><h3 class="mobile-record-title">{{ nameOf(row) }}</h3></template>
            <dl class="mobile-record-fields">
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.name') }}</dt><dd><span class="vpn-ellipsis" :title="row.customName || `#${row.id}`">{{ row.customName || '—' }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.type') }}</dt><dd>{{ row.proxyType || '—' }}</dd></div>
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.endpoint') }}</dt><dd><span class="vpn-ellipsis" :title="endpoint(row)">{{ endpoint(row) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.username') }}</dt><dd><span class="vpn-ellipsis" :title="row.proxyUsername">{{ row.proxyUsername || '—' }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.password') }}</dt><dd><button v-if="row.hasPassword" class="vpn-icon-button" type="button" :disabled="contextLocked || loading" :aria-label="t('vpnProxy.showPassword')" :title="t('vpnProxy.showPassword')" @click="proxy.revealPassword(row)"><i class="i-mdi-eye-outline" aria-hidden="true" /></button><span v-else>—</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.bindings') }}</dt><dd><span class="vpn-ellipsis" :title="bindings(row)">{{ bindings(row) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.policy') }}</dt><dd><span class="vpn-policy" :class="{ 'is-forced': row.forceProxy === 1 }"><i :class="row.forceProxy === 1 ? 'i-mdi-shield-lock-outline' : 'i-mdi-shield-outline'" aria-hidden="true" />{{ t(`vpnProxy.${row.forceProxy === 1 ? 'forced' : row.forceProxy === 0 ? 'optional' : 'unknown'}`) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('vpnProxy.status') }}</dt><dd><span class="vpn-status" :class="{ 'is-available': row.availableStatus === 1, 'is-unavailable': row.availableStatus === 0 }">{{ t(`vpnProxy.${row.availableStatus === 1 ? 'available' : row.availableStatus === 0 ? 'unavailable' : 'unknown'}`) }}</span></dd></div>
            </dl>
            <template #footer><div class="vpn-row-actions">
              <button type="button" :disabled="!canOperate" :title="t('vpnProxy.edit')" :aria-label="t('vpnProxy.edit')" @click="edit(row)"><i class="i-mdi-pencil-outline" aria-hidden="true" /><span class="vpn-action-text">{{ t('vpnProxy.edit') }}</span></button>
              <button type="button" :disabled="!canOperate" :title="t('vpnProxy.test')" :aria-label="t('vpnProxy.test')" @click="test(row)"><i class="i-mdi-lan-connect" aria-hidden="true" /><span class="vpn-action-text">{{ t('vpnProxy.test') }}</span></button>
              <el-dropdown trigger="click" :disabled="!canOperate" popper-class="vpn-actions-menu" @command="rowCommand($event, row)">
                <button type="button" :disabled="!canOperate" :title="t('vpnProxy.more')" :aria-label="t('vpnProxy.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
                <template #dropdown><el-dropdown-menu><el-dropdown-item command="force" :disabled="row.forceProxy === null"><i class="i-mdi-shield-lock-outline" aria-hidden="true" />{{ t(`vpnProxy.${row.forceProxy === 1 ? 'forceOff' : 'forceOn'}`) }}</el-dropdown-item><el-dropdown-item command="delete" divided class="vpn-menu-danger"><i class="i-mdi-delete-outline" aria-hidden="true" />{{ t('vpnProxy.remove') }}</el-dropdown-item></el-dropdown-menu></template>
              </el-dropdown>
            </div></template>
          </MobileRecordCard>
          <p v-if="!rows.length && (loading || !problem)" role="status">{{ t(loading ? 'vpnProxy.loading' : 'vpnProxy.empty') }}</p>
        </MobileRecordList>
        <table v-else class="vpn-table">
        <caption class="vpn-sr-only">{{ t('vpnProxy.title') }}</caption>
        <colgroup><col class="vpn-col-name" /><col class="vpn-col-type" /><col class="vpn-col-endpoint" /><col class="vpn-col-user" /><col class="vpn-col-password" /><col class="vpn-col-tenants" /><col class="vpn-col-policy" /><col class="vpn-col-status" /><col class="vpn-col-actions" /></colgroup>
        <thead><tr><th scope="col">{{ t('vpnProxy.name') }}</th><th scope="col">{{ t('vpnProxy.type') }}</th><th scope="col">{{ t('vpnProxy.endpoint') }}</th><th scope="col">{{ t('vpnProxy.username') }}</th><th scope="col">{{ t('vpnProxy.password') }}</th><th scope="col">{{ t('vpnProxy.bindings') }}</th><th scope="col">{{ t('vpnProxy.policy') }}</th><th scope="col">{{ t('vpnProxy.status') }}</th><th scope="col" class="vpn-sticky-actions">{{ t('vpnProxy.actions') }}</th></tr></thead>
        <tbody>
          <tr v-for="row in rows" :key="row.id">
            <td><span class="vpn-ellipsis" :title="row.customName || `#${row.id}`">{{ row.customName || '—' }}</span></td>
            <td>{{ row.proxyType || '—' }}</td>
            <td><span class="vpn-ellipsis" :title="endpoint(row)">{{ endpoint(row) }}</span></td>
            <td><span class="vpn-ellipsis" :title="row.proxyUsername">{{ row.proxyUsername || '—' }}</span></td>
            <td><button v-if="row.hasPassword" class="vpn-icon-button" type="button" :disabled="contextLocked || loading" :aria-label="t('vpnProxy.showPassword')" :title="t('vpnProxy.showPassword')" @click="proxy.revealPassword(row)"><i class="i-mdi-eye-outline" aria-hidden="true" /></button><span v-else>—</span></td>
            <td><span class="vpn-ellipsis" :title="bindings(row)">{{ bindings(row) }}</span></td>
            <td><span class="vpn-policy" :class="{ 'is-forced': row.forceProxy === 1 }"><i :class="row.forceProxy === 1 ? 'i-mdi-shield-lock-outline' : 'i-mdi-shield-outline'" aria-hidden="true" />{{ t(`vpnProxy.${row.forceProxy === 1 ? 'forced' : row.forceProxy === 0 ? 'optional' : 'unknown'}`) }}</span></td>
            <td><span class="vpn-status" :class="{ 'is-available': row.availableStatus === 1, 'is-unavailable': row.availableStatus === 0 }">{{ t(`vpnProxy.${row.availableStatus === 1 ? 'available' : row.availableStatus === 0 ? 'unavailable' : 'unknown'}`) }}</span></td>
            <td class="vpn-sticky-actions"><div class="vpn-row-actions">
              <button type="button" :disabled="!canOperate" :title="t('vpnProxy.edit')" :aria-label="t('vpnProxy.edit')" @click="edit(row)"><i class="i-mdi-pencil-outline" aria-hidden="true" /><span class="vpn-action-text">{{ t('vpnProxy.edit') }}</span></button>
              <button type="button" :disabled="!canOperate" :title="t('vpnProxy.test')" :aria-label="t('vpnProxy.test')" @click="test(row)"><i class="i-mdi-lan-connect" aria-hidden="true" /><span class="vpn-action-text">{{ t('vpnProxy.test') }}</span></button>
              <el-dropdown trigger="click" :disabled="!canOperate" popper-class="vpn-actions-menu" @command="rowCommand($event, row)">
                <button type="button" :disabled="!canOperate" :title="t('vpnProxy.more')" :aria-label="t('vpnProxy.more')"><i class="i-mdi-dots-horizontal" aria-hidden="true" /></button>
                <template #dropdown><el-dropdown-menu><el-dropdown-item command="force" :disabled="row.forceProxy === null"><i class="i-mdi-shield-lock-outline" aria-hidden="true" />{{ t(`vpnProxy.${row.forceProxy === 1 ? 'forceOff' : 'forceOn'}`) }}</el-dropdown-item><el-dropdown-item command="delete" divided class="vpn-menu-danger"><i class="i-mdi-delete-outline" aria-hidden="true" />{{ t('vpnProxy.remove') }}</el-dropdown-item></el-dropdown-menu></template>
              </el-dropdown>
            </div></td>
          </tr>
          <tr v-if="!rows.length && (loading || !problem)"><td colspan="9" class="vpn-empty"><i :class="loading ? 'i-mdi-loading vpn-spinner' : 'i-mdi-lan-disconnect'" aria-hidden="true" /><span>{{ loading ? t('vpnProxy.loading') : t('vpnProxy.empty') }}</span></td></tr>
        </tbody>
      </table>
    </div>
    <PagePagination :current-page="page" :page-size="size" :total="total" :page-sizes="[10, 20, 50]" :disabled="loading || contextLocked" @current-change="proxy.changePage" @size-change="proxy.changeSize"><span>{{ t('vpnProxy.statusHint') }}</span></PagePagination>

    <ProxyEditorDialog v-model="editorVisible" :record="isEditor ? operation?.row || null : null" :tenants="parents" :tenants-loading="parentsLoading" :tenants-problem="parentsProblem" :can-submit="canSubmit" :pending="mutation.pending" :problem="mutation.problem" @save="save" @reload-tenants="proxy.loadParents" />

    <el-dialog :model-value="actionVisible" class="vpn-operation-dialog" :class="{ 'vpn-batch-dialog': operation?.kind === 'testAll' && batch.state !== 'idle' }" :title="operationTitle" :width="operation?.kind === 'testAll' && batch.state !== 'idle' ? '800px' : '540px'" append-to-body :close-on-click-modal="false" :close-on-press-escape="!mutation.pending" :show-close="!mutation.pending" :before-close="closeAction">
      <template v-if="operation?.kind === 'testAll' && batch.state !== 'idle'">
        <div class="vpn-batch-heading"><strong>{{ batchTitle }}</strong><span>{{ t('vpnProxy.progress', { completed: number(batch.completed), total: number(batch.total) }) }}</span></div>
        <progress v-if="batch.state !== 'preparing'" class="vpn-progress" :value="batch.completed" :max="batch.total || 1" :aria-label="t('vpnProxy.progress', { completed: batch.completed, total: batch.total })" />
        <p v-if="currentBatch" class="vpn-current-proxy">{{ t('vpnProxy.testing') }} · {{ nameOf(currentBatch) }}</p>
        <p class="vpn-batch-summary">{{ t('vpnProxy.batchSummary', { connected: number(batch.connected), disconnected: number(batch.disconnected), unknown: number(batch.unknown), skipped: number(batch.skipped) }) }}</p>
        <div v-if="batch.entries.length" class="vpn-results-scroll"><MobileRecordList v-if="compact" drilldown list-id="proxy-test-results" :record-keys="batch.entries.map(entry => entry.id)">
          <MobileRecordCard v-for="entry in batch.entries" :key="entry.id" :record-key="entry.id" :summary-title="nameOf(entry)" :summary-meta="endpoint(entry)" :summary-status="t(`vpnProxy.${entry.status}`)">
            <template #identity><h3 class="mobile-record-title">{{ nameOf(entry) }}</h3></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('vpnProxy.name') }}</dt><dd><span :title="entry.customName || `#${entry.id}`">{{ entry.customName || `#${entry.id}` }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('vpnProxy.endpoint') }}</dt><dd><span :title="endpoint(entry)">{{ endpoint(entry) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('vpnProxy.status') }}</dt><dd><span :class="{ 'vpn-result-error': entry.status === 'unknown' || entry.status === 'disconnected' }" :title="entry.problem ? errorLabel(entry.problem) : entry.result?.errorKey ? t(`vpnProxy.errors.${entry.result.errorKey}`) : ''">{{ t(`vpnProxy.${entry.status}`) }}</span></dd></div></dl>
            <p v-if="entry.problem || entry.result?.errorKey">{{ entry.problem ? errorLabel(entry.problem) : t(`vpnProxy.errors.${entry.result?.errorKey}`) }}</p>
          </MobileRecordCard>
        </MobileRecordList><table v-else class="vpn-results-table"><thead><tr><th>{{ t('vpnProxy.name') }}</th><th>{{ t('vpnProxy.endpoint') }}</th><th>{{ t('vpnProxy.status') }}</th></tr></thead><tbody><tr v-for="entry in batchEntries" :key="entry.id"><td><span :title="entry.customName || `#${entry.id}`">{{ entry.customName || `#${entry.id}` }}</span></td><td><span :title="endpoint(entry)">{{ endpoint(entry) }}</span></td><td><span :class="{ 'vpn-result-error': entry.status === 'unknown' || entry.status === 'disconnected' }" :title="entry.problem ? errorLabel(entry.problem) : entry.result?.errorKey ? t(`vpnProxy.errors.${entry.result.errorKey}`) : ''">{{ t(`vpnProxy.${entry.status}`) }}</span></td></tr></tbody></table></div>
        <PagePagination v-if="!compact && batch.entries.length > 10" v-model:current-page="resultPage" :page-size="10" :total="batch.entries.length" embedded />
        <p v-if="mutation.pending" class="vpn-dialog-hint">{{ t('vpnProxy.stopHint') }}</p>
      </template>
      <template v-else-if="mutation.outcome === 'idle' || mutation.pending">
        <p>{{ confirmHint }}</p>
        <p v-if="operation?.kind === 'delete' && operation.row?.tenantIds.length" class="vpn-dialog-hint">{{ t('vpnProxy.confirmations.deleteBindings', { count: operation.row.tenantIds.length }) }}</p>
        <dl v-if="operation?.row" class="vpn-target"><dt>{{ t('vpnProxy.endpoint') }}</dt><dd>{{ endpoint(operation.row) }}</dd><dt>{{ t('vpnProxy.bindings') }}</dt><dd>{{ bindings(operation.row) }}</dd></dl>
        <p v-if="mutation.pending" role="status">{{ t('vpnProxy.submitting') }}</p>
      </template>
      <PageErrorNotice v-else-if="mutation.outcome === 'success' && mutation.result?.test?.connected === false"><strong>{{ t('vpnProxy.disconnected') }}</strong><p v-if="mutation.result.test.errorKey">{{ t(`vpnProxy.errors.${mutation.result.test.errorKey}`) }}</p></PageErrorNotice>
      <div v-else-if="mutation.outcome === 'success'" class="vpn-operation-result" role="status">
        <template v-if="mutation.result?.test"><i :class="mutation.result.test.connected === true ? 'i-mdi-check-circle-outline' : 'i-mdi-alert-circle-outline'" aria-hidden="true" /><strong>{{ t(`vpnProxy.${mutation.result.test.connected === true ? 'connected' : 'testUnknown'}`) }}</strong><PageErrorNotice v-if="mutation.result.test.errorKey">{{ t(`vpnProxy.errors.${mutation.result.test.errorKey}`) }}</PageErrorNotice></template>
        <strong v-else>{{ successLabel }}</strong>
      </div>
      <dl v-if="mutation.outcome !== 'idle' && !mutation.pending && operation?.kind === 'test' && operation.row" class="vpn-target"><dt>{{ t('vpnProxy.endpoint') }}</dt><dd>{{ endpoint(mutation.result?.test || operation.row) }}</dd></dl>
      <p v-if="mutation.outcome === 'unknown' || requiresReview" class="vpn-result-error" role="alert">{{ t('vpnProxy.unknownResult') }}</p>
      <PageErrorNotice v-if="mutation.problem">{{ errorLabel(mutation.problem) }}</PageErrorNotice>
      <PageErrorNotice v-if="problem && mutation.outcome === 'success'">{{ errorLabel(problem) }}</PageErrorNotice>
      <template #footer>
        <GhostBtn v-if="operation?.kind === 'testAll' && mutation.pending && ['preparing', 'running'].includes(batch.state)" :disabled="batch.stopRequested" @click="proxy.stopBatch"><i class="i-mdi-stop-circle-outline" aria-hidden="true" />{{ t(`vpnProxy.${batch.stopRequested ? 'stopping' : 'stopBatch'}`) }}</GhostBtn>
        <GhostBtn :disabled="mutation.pending" @click="closeAction">{{ t(`vpnProxy.${mutation.outcome === 'idle' ? 'cancel' : 'close'}`) }}</GhostBtn>
        <PrimaryBtn v-if="mutation.outcome === 'idle' || mutation.outcome === 'failed'" :loading="mutation.pending" :disabled="!canSubmit" @click="submitAction">{{ t('vpnProxy.confirm') }}</PrimaryBtn>
      </template>
    </el-dialog>

    <el-dialog :model-value="!!passwordTarget" class="vpn-operation-dialog" :title="t('vpnProxy.passwordTitle')" width="520px" append-to-body :close-on-click-modal="false" :before-close="closePassword">
      <p v-if="passwordTarget" class="vpn-password-target">{{ nameOf(passwordTarget) }}</p>
      <p v-if="passwordLoading" role="status">{{ t('vpnProxy.passwordLoading') }}</p>
      <PageErrorNotice v-else-if="passwordProblem">{{ errorLabel(passwordProblem) }}</PageErrorNotice>
      <template v-else><SecuritySecretInput v-if="password" id="vpn-proxy-password" :model-value="password" :label="t('vpnProxy.password')" readonly copyable autocomplete="off" /><p v-else>{{ t('vpnProxy.noPassword') }}</p><p class="vpn-dialog-hint">{{ t('vpnProxy.passwordHint') }}</p></template>
      <template #footer><GhostBtn @click="closePassword">{{ t('vpnProxy.close') }}</GhostBtn></template>
    </el-dialog>
  </section>
</template>

<style scoped>
.mobile-record-fields .vpn-truncate, .mobile-record-fields .vpn-ellipsis { max-width: 100%; white-space: normal; overflow-wrap: anywhere; }
.mobile-record-card .vpn-row-actions { flex-wrap: wrap; }
</style>
