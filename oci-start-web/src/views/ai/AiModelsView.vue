<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { useAiModelsData } from './useAiModelsData'
import {
  addAiModelConfig, setAiModelConfigEnabled, deleteAiModelConfig, setAllAiModelConfigsEnabled,
  aiModelsError, isAiModelsWriteUncertain,
  type AvailableAiModel, type AiModelConfig, type AiModelTenant,
} from '@/api/aiModels'

type Action = { kind: 'add'; model: AvailableAiModel; tenant: AiModelTenant }
  | { kind: 'toggle'; config: AiModelConfig; enabled: boolean }
  | { kind: 'delete'; config: AiModelConfig }
  | { kind: 'batch'; enabled: boolean; count: number }
const { t, locale } = useI18n()
const router = useRouter()
const route = useRoute()
const compact = useCompactViewport()
const {
  tenantId, filterByTenant, selectedTenant, tenants, models, configs,
  visibleConfigs, pagedModels, pagedConfigs, modelPage, configPage, pageSize,
  isModelConfigured, loadTenants, loadModels, loadConfigs, refreshAll, cancelReads, setModelPage, setConfigPage,
} = useAiModelsData()
const mobileModels = computed(() => typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith('ai-available-models:') ? models.rows : pagedModels.value)
const mobileConfigs = computed(() => typeof route.query.mobileRecord === 'string' && route.query.mobileRecord.startsWith('ai-model-configs:') ? visibleConfigs.value : pagedConfigs.value)
function modelRecordKey(row: AvailableAiModel) { return JSON.stringify([row.tenantId, row.id]) }
watch(() => [route.query.mobileRecord, tenants.rows], () => {
  if (!compact.value || tenantId.value || !tenants.loaded) return
  const selected = route.query.mobileRecord
  if (typeof selected !== 'string' || !selected.startsWith('ai-available-models:')) return
  try {
    const key: unknown = JSON.parse(selected.slice('ai-available-models:'.length))
    if (Array.isArray(key) && key.length === 2 && key.every(part => typeof part === 'string') && tenants.rows.some(tenant => tenant.id === key[0])) tenantId.value = key[0]
  } catch { /* A malformed record link must not change the account scope. */ }
}, { immediate: true })
const action = shallowRef<Action | null>(null)
const actionState = ref<'idle' | 'pending' | 'failed' | 'uncertain' | 'saved'>('idle')
const actionProblem = shallowRef<ReturnType<typeof aiModelsError> | null>(null)
const actionReceipt = shallowRef<{ key: string; count: number } | null>(null)
const unverifiedConfigs = ref(false)
const busy = computed(() => actionState.value === 'pending')
const configsReady = computed(() => configs.loaded && !configs.loading && !configs.problem && !unverifiedConfigs.value)
const writeLocked = computed(() => busy.value || tenants.loading || !configsReady.value)
const refreshing = computed(() => tenants.loading || models.loading || configs.loading)
const sortedTenants = computed(() => [...tenants.rows].sort((a, b) => tenantName(a).localeCompare(tenantName(b), locale.value)))
const canEnableAll = computed(() => configs.rows.some(row => row.enabled !== true))
const canDisableAll = computed(() => configs.rows.some(row => row.enabled !== false))
const actionKind = computed(() => {
  const current = action.value
  if (!current) return ''
  return current.kind === 'toggle' ? current.enabled ? 'enable' : 'disable'
    : current.kind === 'batch' ? current.enabled ? 'enableAll' : 'disableAll' : current.kind
})
const actionTitle = computed(() => actionKind.value ? t(`aiModels.${actionKind.value}Title`) : '')
const actionHint = computed(() => {
  if (!action.value) return ''
  return action.value.kind === 'batch' ? t(action.value.enabled ? 'aiModels.batchEnableHint' : 'aiModels.batchDisableHint')
    : t(`aiModels.${actionKind.value}Hint`)
})
const needsInspection = computed(() => actionState.value === 'uncertain' || actionState.value === 'saved'
  || ['alreadyConfigured', 'configMissing'].includes(actionProblem.value?.key || ''))
const modelEmpty = computed(() => t(!tenantId.value ? 'aiModels.chooseTenant' : models.loading ? 'aiModels.loading'
  : models.problem ? 'aiModels.loadFailed' : !models.loaded ? 'aiModels.notLoaded' : 'aiModels.noModels'))
const configEmpty = computed(() => t(configs.loading ? 'aiModels.loading' : configs.problem ? 'aiModels.loadFailed'
  : !configs.loaded ? 'aiModels.notLoaded' : filterByTenant.value && tenantId.value ? 'aiModels.noTenantConfigs' : 'aiModels.noConfigs'))
let disposed = false
let actionSequence = 0

function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function errorText(cause: unknown) { const error = aiModelsError(cause); return error.detail || t(`aiModels.errors.${error.key}`) }
function tenantName(row: AiModelTenant) { return row.name || t('aiModels.tenantId', { id: row.id }) }
function modelName(row: AvailableAiModel) { return row.name || row.modelName || row.id }
function configName(row: AiModelConfig) { return row.modelName || row.modelId || t('aiModels.unknown') }
function configTenant(row: AiModelConfig) {
  const known = tenants.rows.find(tenant => tenant.id === row.tenantId)
  if (known) return tenantName(known)
  // Keep actual names/region labels returned by the service as user data.
  const parts = [row.userName, row.region].filter(Boolean)
  return parts.length ? parts.join(' · ') : row.tenantId ? t('aiModels.tenantId', { id: row.tenantId }) : t('aiModels.unknown')
}
function openAction(value: Action, immediate = false) {
  if (writeLocked.value) return
  actionSequence++
  action.value = value
  actionState.value = 'idle'
  actionProblem.value = null
  actionReceipt.value = null
  if (immediate) void submitAction()
}
function addModel(model: AvailableAiModel) {
  if (!selectedTenant.value || models.loading || models.problem || !models.loaded || isModelConfigured(model.id)) return
  if (model.tenantId !== tenantId.value) return
  openAction({ kind: 'add', model: { ...model }, tenant: { ...selectedTenant.value } }, true)
}
function toggleConfig(config: AiModelConfig) { openAction({ kind: 'toggle', config: { ...config }, enabled: config.enabled !== true }, true) }
function confirmDelete(config: AiModelConfig) { openAction({ kind: 'delete', config: { ...config } }) }
function confirmBatch(enabled: boolean) {
  if (!configs.rows.length || (enabled ? !canEnableAll.value : !canDisableAll.value)) return
  openAction({ kind: 'batch', enabled, count: configs.rows.length })
}
function closeAction() {
  if (busy.value) return
  actionSequence++
  action.value = null
  actionReceipt.value = null
}
function inspectLatest() { closeAction(); void loadConfigs() }
async function submitAction() {
  const target = action.value
  if (!target || busy.value || needsInspection.value) return
  const sequence = ++actionSequence
  const interruptedModels = models.loading
  cancelReads()
  actionState.value = 'pending'
  actionProblem.value = null
  unverifiedConfigs.value = true
  try {
    let messageKey = ''
    let updatedCount = 0
    let addedId = ''
    if (target.kind === 'add') {
      const saved = await addAiModelConfig({ tenantId: target.tenant.id, modelId: target.model.id,
        modelName: modelName(target.model), provider: target.model.provider, userName: target.model.userName || '' })
      addedId = saved.id
      messageKey = 'addedSuccess'
    } else if (target.kind === 'toggle') {
      await setAiModelConfigEnabled(target.config.id, target.enabled)
      messageKey = target.enabled ? 'enabledSuccess' : 'disabledSuccess'
    } else if (target.kind === 'delete') {
      await deleteAiModelConfig(target.config.id)
      messageKey = 'deletedSuccess'
    } else {
      const result = await setAllAiModelConfigsEnabled(target.enabled)
      updatedCount = result.updatedCount
      messageKey = target.enabled ? 'batchEnabledSuccess' : 'batchDisabledSuccess'
    }
    if (disposed || sequence !== actionSequence) return
    actionReceipt.value = { key: messageKey, count: updatedCount }
    const refreshed = await loadConfigs()
    if (disposed || sequence !== actionSequence) return
    if (!refreshed) { actionState.value = 'saved'; return }
    if (addedId) {
      const index = visibleConfigs.value.findIndex(row => row.id === addedId)
      if (index >= 0) setConfigPage(Math.floor(index / 6) + 1)
    }
    actionState.value = 'idle'
    closeAction()
    ElMessage.success(t(`aiModels.${messageKey}`, { count: number(updatedCount) }))
  } catch (cause) {
    if (disposed || sequence !== actionSequence) return
    actionProblem.value = aiModelsError(cause)
    actionState.value = isAiModelsWriteUncertain(cause) ? 'uncertain' : 'failed'
  } finally {
    if (!disposed && interruptedModels && tenantId.value && !models.loading) void loadModels()
    if (!disposed && sequence === actionSequence && actionState.value === 'pending') actionState.value = 'idle'
  }
}
function guardLeaving() {
  if (!busy.value) return true
  ElMessage.warning(t('aiModels.busyLeave'))
  return false
}
function back() {
  if (!guardLeaving()) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: '1' } })
}
function beforeUnload(event: BeforeUnloadEvent) { if (busy.value) { event.preventDefault(); event.returnValue = '' } }
watch(() => configs.rows, () => { unverifiedConfigs.value = false }, { flush: 'sync' })
onBeforeRouteLeave(guardLeaving)
onBeforeRouteUpdate(guardLeaving)
onMounted(() => { window.addEventListener('beforeunload', beforeUnload) })
onBeforeUnmount(() => { disposed = true; window.removeEventListener('beforeunload', beforeUnload) })
</script>

<template>
  <section class="ai-models-page">
    <div class="ai-models-toolbar">
      <PageBackButton :disabled="busy" @click="back" />
      <label for="ai-models-tenant">{{ t('aiModels.tenant') }}</label>
      <el-select id="ai-models-tenant" v-model="tenantId" class="ai-models-tenant" clearable filterable :disabled="busy || tenants.loading" :loading="tenants.loading" :placeholder="t('aiModels.selectTenant')" :no-data-text="t('aiModels.noTenants')">
        <el-option v-for="row in sortedTenants" :key="row.id" :value="row.id" :label="tenantName(row)" />
      </el-select>
      <div class="ai-models-toolbar-actions" data-page-error-anchor><GhostBtn :disabled="busy" :loading="refreshing" @click="refreshAll"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('aiModels.refresh') }}</GhostBtn></div>
    </div>
    <PageErrorNotice v-if="tenants.problem"><span>{{ errorText(tenants.problem) }}</span><GhostBtn :disabled="busy" :loading="tenants.loading" @click="loadTenants">{{ t('aiModels.reloadTenants') }}</GhostBtn></PageErrorNotice>
    <div class="ai-models-grid">
      <section class="ai-models-panel" :aria-label="t('aiModels.available')" :aria-busy="models.loading">
        <div class="ai-models-panel-header" data-page-error-anchor><h2>{{ t('aiModels.available') }}</h2><GhostBtn :disabled="busy || !tenantId" :loading="models.loading" :title="t('aiModels.refreshModels')" :aria-label="t('aiModels.refreshModels')" @click="loadModels"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn></div>
        <PageErrorNotice v-if="models.problem"><span>{{ errorText(models.problem) }}</span><GhostBtn :disabled="busy" :loading="models.loading" @click="loadModels">{{ t('aiModels.retry') }}</GhostBtn></PageErrorNotice>
        <MobileRecordList v-if="compact" drilldown list-id="ai-available-models" :record-keys="models.rows.map(modelRecordKey)" :loading="models.loading || tenants.loading" class="ai-models-mobile-list">
          <MobileRecordCard v-for="row in mobileModels" :key="modelRecordKey(row)" :record-key="modelRecordKey(row)" :summary-title="modelName(row)" :summary-meta="row.provider || t('aiModels.unknown')" :summary-status="isModelConfigured(row.id) ? t('aiModels.added') : undefined" summary-tone="success">
            <template #identity><h3 class="mobile-record-title">{{ modelName(row) }}</h3><p v-if="row.description" class="mobile-record-subtitle">{{ row.description }}</p></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('aiModels.modelId') }}</dt><dd>{{ row.id }}</dd></div><div class="mobile-record-wide"><dt>{{ t('aiModels.provider') }}</dt><dd>{{ row.provider || t('aiModels.unknown') }}</dd></div><div class="mobile-record-wide"><dt>{{ t('aiModels.tenant') }}</dt><dd>{{ selectedTenant ? tenantName(selectedTenant) : t('aiModels.tenantId', { id: row.tenantId }) }}</dd></div></dl>
            <template #footer><GhostBtn :disabled="writeLocked || models.loading || !!models.problem || isModelConfigured(row.id)" :title="isModelConfigured(row.id) ? t('aiModels.addedHint') : t('aiModels.add')" @click="addModel(row)"><i v-if="!isModelConfigured(row.id)" class="i-mdi-plus" aria-hidden="true" />{{ t(isModelConfigured(row.id) ? 'aiModels.added' : 'aiModels.add') }}</GhostBtn></template>
          </MobileRecordCard>
          <p v-if="!models.rows.length" class="ai-models-empty" role="status">{{ modelEmpty }}</p>
        </MobileRecordList>
        <div v-else class="ai-models-list">
          <p v-if="!pagedModels.length" class="ai-models-empty" role="status">{{ modelEmpty }}</p>
          <article v-for="row in pagedModels" :key="row.id" class="ai-models-row">
            <div class="ai-models-row-main"><h3 class="ai-models-name" :title="`${t('aiModels.modelId')}: ${row.id}`">{{ modelName(row) }}</h3><div class="ai-models-meta"><span class="ai-models-provider" :title="t('aiModels.provider')">{{ row.provider || t('aiModels.unknown') }}</span></div></div>
            <GhostBtn :disabled="writeLocked || models.loading || !!models.problem || isModelConfigured(row.id)" :title="isModelConfigured(row.id) ? t('aiModels.addedHint') : t('aiModels.add')" @click="addModel(row)"><i v-if="!isModelConfigured(row.id)" class="i-mdi-plus" aria-hidden="true" />{{ t(isModelConfigured(row.id) ? 'aiModels.added' : 'aiModels.add') }}</GhostBtn>
          </article>
        </div>
        <PagePagination :current-page="modelPage" :page-size="pageSize" :total="models.rows.length" :disabled="busy || models.loading" @current-change="setModelPage"><span>{{ t('aiModels.returnedModels', { count: models.loaded ? number(models.rows.length) : '—' }) }}</span></PagePagination>
      </section>
      <section class="ai-models-panel" :aria-label="t('aiModels.configured')" :aria-busy="configs.loading">
        <div class="ai-models-panel-header" data-page-error-anchor>
          <h2>{{ t('aiModels.configured') }}</h2>
          <div class="ai-models-panel-tools"><GhostBtn :disabled="busy" :loading="configs.loading" :title="t('aiModels.refreshConfigs')" :aria-label="t('aiModels.refreshConfigs')" @click="loadConfigs"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn><GhostBtn :disabled="writeLocked || !canEnableAll" @click="confirmBatch(true)">{{ t('aiModels.enableAll') }}</GhostBtn><GhostBtn :disabled="writeLocked || !canDisableAll" @click="confirmBatch(false)">{{ t('aiModels.disableAll') }}</GhostBtn></div>
          <label class="ai-models-linked" for="ai-models-link" :title="t('aiModels.filterHint')"><span>{{ t('aiModels.filterTenant') }}</span><el-switch id="ai-models-link" v-model="filterByTenant" :disabled="busy" :aria-label="t('aiModels.filterTenant')" /></label>
        </div>
        <p class="ai-models-note ai-models-scope">{{ t('aiModels.batchScope') }}</p>
        <PageErrorNotice v-if="configs.problem"><span>{{ errorText(configs.problem) }}</span><GhostBtn :disabled="busy" :loading="configs.loading" @click="loadConfigs">{{ t('aiModels.retry') }}</GhostBtn></PageErrorNotice>
        <div v-else-if="unverifiedConfigs && !busy && !configs.loading" class="ai-models-read-error" role="status"><span>{{ t('aiModels.reloadBeforeEditing') }}</span><GhostBtn @click="loadConfigs">{{ t('aiModels.refreshConfigs') }}</GhostBtn></div>
        <MobileRecordList v-if="compact" drilldown list-id="ai-model-configs" :record-keys="visibleConfigs.map(row => row.id)" :loading="configs.loading" class="ai-models-mobile-list">
          <MobileRecordCard v-for="row in mobileConfigs" :key="row.id" :record-key="row.id" :summary-title="configName(row)" :summary-meta="configTenant(row)" :summary-status="t(row.enabled === true ? 'aiModels.enabled' : row.enabled === false ? 'aiModels.disabled' : 'aiModels.statusUnknown')" :summary-tone="row.enabled === true ? 'success' : row.enabled == null ? 'warning' : 'neutral'">
            <template #identity><h3 class="mobile-record-title">{{ configName(row) }}</h3><span class="mobile-record-subtitle">{{ t(row.enabled === true ? 'aiModels.enabled' : row.enabled === false ? 'aiModels.disabled' : 'aiModels.statusUnknown') }}</span></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('aiModels.modelId') }}</dt><dd>{{ row.modelId || t('aiModels.unknown') }}</dd></div><div class="mobile-record-wide"><dt>{{ t('aiModels.tenant') }}</dt><dd>{{ configTenant(row) }}</dd></div><div class="mobile-record-wide"><dt>{{ t('aiModels.provider') }}</dt><dd>{{ row.provider || t('aiModels.unknown') }}</dd></div></dl>
            <template #footer><GhostBtn :disabled="writeLocked" @click="toggleConfig(row)"><i :class="row.enabled === true ? 'i-mdi-pause-circle-outline' : 'i-mdi-play-circle-outline'" aria-hidden="true" />{{ t(row.enabled === true ? 'aiModels.disable' : 'aiModels.enable') }}</GhostBtn><GhostBtn danger :disabled="writeLocked" @click="confirmDelete(row)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('aiModels.delete') }}</GhostBtn></template>
          </MobileRecordCard>
          <p v-if="!visibleConfigs.length" class="ai-models-empty" role="status">{{ configEmpty }}</p>
        </MobileRecordList>
        <div v-else class="ai-models-list">
          <p v-if="!pagedConfigs.length" class="ai-models-empty" role="status">{{ configEmpty }}</p>
          <article v-for="row in pagedConfigs" :key="row.id" class="ai-models-row">
            <div class="ai-models-row-main"><h3 class="ai-models-name" :title="`${t('aiModels.modelId')}: ${row.modelId}`">{{ configName(row) }}</h3><div class="ai-models-meta"><span>{{ configTenant(row) }}</span><span v-if="row.provider" class="ai-models-provider">{{ row.provider }}</span></div></div>
            <div class="ai-models-row-actions"><span class="ai-models-status" :class="{ enabled: row.enabled === true, unknown: row.enabled == null }">{{ t(row.enabled === true ? 'aiModels.enabled' : row.enabled === false ? 'aiModels.disabled' : 'aiModels.statusUnknown') }}</span><button type="button" class="ai-models-icon" :disabled="writeLocked" :title="t(row.enabled === true ? 'aiModels.disable' : 'aiModels.enable')" :aria-label="`${t(row.enabled === true ? 'aiModels.disable' : 'aiModels.enable')}: ${configName(row)}`" @click="toggleConfig(row)"><i :class="row.enabled === true ? 'i-mdi-pause-circle-outline' : 'i-mdi-play-circle-outline'" aria-hidden="true" /></button><button type="button" class="ai-models-icon danger" :disabled="writeLocked" :title="t('aiModels.delete')" :aria-label="`${t('aiModels.delete')}: ${configName(row)}`" @click="confirmDelete(row)"><i class="i-mdi-trash-can-outline" aria-hidden="true" /></button></div>
          </article>
        </div>
        <PagePagination :current-page="configPage" :page-size="pageSize" :total="visibleConfigs.length" :disabled="busy || configs.loading" @current-change="setConfigPage"><span>{{ filterByTenant && tenantId ? t('aiModels.visibleConfigCount', { count: configs.loaded ? number(visibleConfigs.length) : '—', total: configs.loaded ? number(configs.rows.length) : '—' }) : t('aiModels.configCount', { count: configs.loaded ? number(configs.rows.length) : '—' }) }}</span></PagePagination>
      </section>
    </div>
    <el-dialog :model-value="!!action" :title="actionTitle" width="540px" class="ai-models-action-dialog" append-to-body :close-on-click-modal="false" :close-on-press-escape="!busy" :show-close="!busy" @update:model-value="!$event && closeAction()">
      <form v-if="action" id="ai-models-action-form" @submit.prevent="submitAction">
        <div v-if="action.kind === 'add'" class="ai-models-action-context"><strong>{{ modelName(action.model) }}</strong><span>{{ tenantName(action.tenant) }}</span></div>
        <div v-else-if="action.kind !== 'batch'" class="ai-models-action-context"><strong>{{ configName(action.config) }}</strong><span>{{ configTenant(action.config) }}</span><span>{{ action.config.modelId }}</span></div>
        <p class="ai-models-action-hint">{{ actionHint }}</p>
        <p v-if="action.kind === 'batch'" class="ai-models-action-note">{{ t('aiModels.batchCount', { count: number(action.count) }) }}</p>
        <p v-if="actionReceipt" class="ai-models-action-note" role="status">{{ t(`aiModels.${actionReceipt.key}`, { count: number(actionReceipt.count) }) }}</p>
        <p v-if="busy" class="ai-models-action-note" role="status">{{ t(actionReceipt ? 'aiModels.reloadingAfterSave' : 'aiModels.processingHint') }}</p>
        <PageErrorNotice v-if="actionProblem">{{ errorText(actionProblem) }}</PageErrorNotice>
        <p v-if="actionState === 'uncertain' || actionState === 'saved'" class="ai-models-action-warning" role="status">{{ t(actionState === 'saved' ? 'aiModels.refreshAfterSave' : 'aiModels.uncertain') }}</p>
      </form>
      <template #footer><GhostBtn :disabled="busy" @click="closeAction">{{ t(needsInspection || actionState === 'failed' ? 'aiModels.close' : 'aiModels.cancel') }}</GhostBtn><GhostBtn v-if="needsInspection" @click="inspectLatest">{{ t('aiModels.inspect') }}</GhostBtn><button v-else-if="action?.kind === 'delete'" type="submit" form="ai-models-action-form" class="ai-models-danger" :disabled="busy">{{ t(busy ? 'aiModels.processing' : 'aiModels.confirmDelete') }}</button><PrimaryBtn v-else type="submit" form="ai-models-action-form" :loading="busy">{{ t(actionState === 'failed' ? 'aiModels.retryAction' : 'aiModels.confirm') }}</PrimaryBtn></template>
    </el-dialog>
  </section>
</template>

<style lang="scss" src="./models.scss" />
<style scoped>
@media (max-width: 760px) {
  .ai-models-page .ai-models-panel { min-height: 0; }
  .ai-models-mobile-list { min-width: 0; }
  .ai-models-mobile-list .ai-models-empty { min-height: 88px; padding-block: 18px; }
  .ai-models-mobile-list :deep(.btn) { min-height: 44px; max-width: 100%; white-space: normal; }
}
</style>
