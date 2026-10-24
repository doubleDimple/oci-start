<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { mobileRecordParents, mobileRecordSelection } from '@/composables/useMobileRecords'
import {
  TelegramAiApiError, addTelegramAiConfig, deleteTelegramAiConfig, listTelegramAiConfigs,
  listTelegramAiModels, listTelegramAiTenants, setTelegramAiEnabled, telegramAiError,
  type TelegramAiConfig, type TelegramAiModel, type TelegramAiTenant,
} from '@/api/telegramAi'

const props = withDefaults(defineProps<{ modelValue: boolean; disabled?: boolean }>(), { disabled: false })
const emit = defineEmits<{ 'update:modelValue': [value: boolean]; busy: [value: boolean]; changed: [] }>()
const { t } = useI18n()
const route = useRoute(), compact = useCompactViewport()
type Confirmation = { kind: 'add'; model: TelegramAiModel; tenantName: string }
  | { kind: 'toggle'; config: TelegramAiConfig; enabled: boolean }
  | { kind: 'delete'; config: TelegramAiConfig }
const tenants = shallowRef<TelegramAiTenant[]>([])
const models = shallowRef<TelegramAiModel[]>([])
const configs = shallowRef<TelegramAiConfig[]>([])
const tenantId = ref('')
const tenantsLoading = ref(false), modelsLoading = ref(false), configsLoading = ref(false)
const tenantsLoaded = ref(false), configsLoaded = ref(false)
const tenantsProblem = shallowRef<TelegramAiApiError | null>(null)
const modelsProblem = shallowRef<TelegramAiApiError | null>(null)
const configsProblem = shallowRef<TelegramAiApiError | null>(null)
const operationProblem = shallowRef<TelegramAiApiError | null>(null)
const confirmation = shallowRef<Confirmation | null>(null)
const lastAction = shallowRef<Confirmation | null>(null)
const pending = ref(false)
const requiresReview = ref(false)
const receipt = ref<'idle' | 'success' | 'failed' | 'unknown'>('idle')
const configRevision = ref(0), reviewRevision = ref(0)
const availablePage = ref(1), configuredPage = ref(1)
const confirmHeading = ref<HTMLElement>()
const notice = ref<HTMLElement>()
const failureNotice = ref<InstanceType<typeof PageErrorNotice>>()
const pageSize = 7
let disposed = false
let tenantController: AbortController | undefined
let modelController: AbortController | undefined
let configController: AbortController | undefined
const readLocked = computed(() => props.disabled || pending.value || !!confirmation.value)
const locked = computed(() => readLocked.value || requiresReview.value)
const canWrite = computed(() => props.modelValue && !locked.value && configsLoaded.value && !configsLoading.value && !configsProblem.value)
const reviewReady = computed(() => requiresReview.value && !pending.value && !configsLoading.value && !configsProblem.value
  && configsLoaded.value && configRevision.value >= reviewRevision.value)
const configuredModels = computed(() => new Set(configs.value.map(config => config.modelId)))
const availablePages = computed(() => Math.max(1, Math.ceil(models.value.length / pageSize)))
const configuredPages = computed(() => Math.max(1, Math.ceil(configs.value.length / pageSize)))
const visibleModels = computed(() => models.value.slice((availablePage.value - 1) * pageSize, availablePage.value * pageSize))
const visibleConfigs = computed(() => configs.value.slice((configuredPage.value - 1) * pageSize, configuredPage.value * pageSize))
const modelListId = computed(() => `telegram-models-${tenantId.value || savedModelTenant() || 'none'}`)
const configListId = 'telegram-configs-all-tenants'
const mobileModels = computed(() => mobileRecordSelection(route.query, modelListId.value) ? models.value : visibleModels.value)
const mobileConfigs = computed(() => mobileRecordSelection(route.query, configListId) ? configs.value : visibleConfigs.value)
function configKey(config: TelegramAiConfig) { return `${config.tenantId}:${config.id}` }
function savedModelTenant() {
  const records = [...mobileRecordParents(route.query), route.query.mobileRecord]
  for (const value of records.reverse()) {
    if (typeof value !== 'string') continue
    const match = /^telegram-models-([1-9]\d*):/.exec(value)
    if (match) return match[1] || ''
  }
  return ''
}
const outcomeModel = computed(() => lastAction.value?.kind === 'add' ? modelLabel(lastAction.value.model)
  : lastAction.value ? configLabel(lastAction.value.config) : '')
const outcomeModelId = computed(() => lastAction.value?.kind === 'add' ? lastAction.value.model.id
  : lastAction.value?.config.modelId || '')
const confirmationText = computed(() => {
  const action = confirmation.value
  if (!action) return ''
  if (action.kind === 'add') return t('notificationSettings.ai.confirmAdd', { model: modelLabel(action.model), tenant: action.tenantName })
  return t(action.kind === 'delete' ? 'notificationSettings.ai.confirmDelete'
    : action.enabled ? 'notificationSettings.ai.confirmEnable' : 'notificationSettings.ai.confirmDisable', { model: configLabel(action.config) })
})
function modelLabel(model: TelegramAiModel) { return model.name || model.modelName || model.id }
function configLabel(config: TelegramAiConfig) { return config.modelName || config.modelId || config.id }
function tenantLabel(id: string) { return tenants.value.find(tenant => tenant.id === id)?.name || t('notificationSettings.ai.tenantUnknown', { id: id || '—' }) }
function errorLabel(error: TelegramAiApiError | null) { return error ? t(`notificationSettings.ai.errors.${error.key}`) : '' }
function active(controller: AbortController, owner: AbortController | undefined) {
  return !disposed && props.modelValue && controller === owner && !controller.signal.aborted
}
function cancelReads() {
  tenantController?.abort(); tenantController = undefined
  modelController?.abort(); modelController = undefined
  configController?.abort(); configController = undefined
  tenantsLoading.value = false; modelsLoading.value = false; configsLoading.value = false
}
async function loadTenants() {
  tenantController?.abort()
  const controller = new AbortController(); tenantController = controller
  tenantsLoading.value = true; tenantsProblem.value = null
  try {
    const result = await listTelegramAiTenants(controller.signal)
    if (!active(controller, tenantController)) return
    tenants.value = result; tenantsLoaded.value = true
    if (tenantId.value && !result.some(tenant => tenant.id === tenantId.value)) tenantId.value = ''
    const savedTenant = compact.value ? savedModelTenant() : ''
    if (!tenantId.value && savedTenant && result.some(tenant => tenant.id === savedTenant)) tenantId.value = savedTenant
  } catch (cause) { if (active(controller, tenantController)) tenantsProblem.value = telegramAiError(cause) }
  finally { if (active(controller, tenantController)) { tenantController = undefined; tenantsLoading.value = false } }
}
async function loadModels() {
  modelController?.abort(); modelController = undefined
  models.value = []; modelsProblem.value = null; modelsLoading.value = false; availablePage.value = 1
  const selected = tenantId.value
  if (!selected || !props.modelValue || disposed) return
  const controller = new AbortController(); modelController = controller; modelsLoading.value = true
  try {
    const result = await listTelegramAiModels(selected, controller.signal)
    if (!active(controller, modelController) || tenantId.value !== selected) return
    models.value = result
    const selectedModel = mobileRecordSelection(route.query, modelListId.value)
    const selectedIndex = selectedModel ? result.findIndex(model => model.id === selectedModel) : -1
    if (selectedIndex >= 0) availablePage.value = Math.floor(selectedIndex / pageSize) + 1
  } catch (cause) { if (active(controller, modelController) && tenantId.value === selected) modelsProblem.value = telegramAiError(cause) }
  finally { if (active(controller, modelController)) { modelController = undefined; modelsLoading.value = false } }
}
async function loadConfigs(): Promise<boolean> {
  configController?.abort()
  const controller = new AbortController(); configController = controller
  configsLoading.value = true; configsProblem.value = null
  try {
    const result = await listTelegramAiConfigs(controller.signal)
    if (!active(controller, configController)) return false
    configs.value = result; configsLoaded.value = true; configRevision.value += 1
    const selectedConfig = mobileRecordSelection(route.query, configListId)
    const selectedIndex = selectedConfig ? result.findIndex(config => configKey(config) === selectedConfig) : -1
    if (selectedIndex >= 0) configuredPage.value = Math.floor(selectedIndex / pageSize) + 1
    return true
  } catch (cause) { if (active(controller, configController)) configsProblem.value = telegramAiError(cause); return false }
  finally { if (active(controller, configController)) { configController = undefined; configsLoading.value = false } }
}
async function refresh() {
  if (pending.value || confirmation.value || props.disabled || !props.modelValue) return
  await Promise.all([loadTenants(), loadConfigs()])
}
function refreshModels() { if (!locked.value && !tenantsLoading.value && !tenantsProblem.value) void loadModels() }
function prepareAdd(model: TelegramAiModel) {
  if (!canWrite.value || modelsLoading.value || modelsProblem.value || tenantsLoading.value || tenantsProblem.value
    || model.tenantId !== tenantId.value || configuredModels.value.has(model.id)) return
  confirmation.value = { kind: 'add', model: { ...model }, tenantName: tenantLabel(model.tenantId) }
  void focusConfirmation()
}
function prepareConfig(config: TelegramAiConfig, kind: 'toggle' | 'delete', enabled = false) {
  if (!canWrite.value || (kind === 'toggle' && config.cloudType !== 1)) return
  confirmation.value = kind === 'delete' ? { kind, config: { ...config } } : { kind, config: { ...config }, enabled }
  void focusConfirmation()
}
async function focusConfirmation() { await nextTick(); if (!disposed) confirmHeading.value?.focus() }
function cancelConfirmation() { if (!pending.value) confirmation.value = null }
function matchesReceipt(row: TelegramAiConfig | undefined, expected: TelegramAiConfig): boolean {
  return !!row && row.id === expected.id && row.tenantId === expected.tenantId && row.modelId === expected.modelId
    && row.modelName === expected.modelName && row.provider === expected.provider && row.enabled === expected.enabled && row.cloudType === expected.cloudType
}
async function submit() {
  const action = confirmation.value
  if (!action || pending.value || props.disabled || requiresReview.value || !configsLoaded.value || configsProblem.value) return
  pending.value = true; operationProblem.value = null; receipt.value = 'idle'; lastAction.value = action
  configController?.abort(); configController = undefined; configsLoading.value = false
  let expected: TelegramAiConfig | undefined
  try {
    if (action.kind === 'add') expected = await addTelegramAiConfig({ tenantId: action.model.tenantId, modelId: action.model.id,
      modelName: action.model.name || action.model.modelName, provider: action.model.provider || 'OCI', userName: action.model.userName })
    else if (action.kind === 'toggle') expected = await setTelegramAiEnabled(action.config.id, action.enabled)
    else await deleteTelegramAiConfig(action.config.id)
    if (disposed || !props.modelValue) return
    receipt.value = 'success'
    emit('changed')
  } catch (cause) {
    if (disposed || !props.modelValue) return
    const failure = telegramAiError(cause)
    operationProblem.value = failure
    receipt.value = failure.writeAttempted ? 'unknown' : 'failed'
  }
  if (disposed || !props.modelValue) return
  reviewRevision.value = configRevision.value + 1
  const readBack = await loadConfigs()
  if (disposed || !props.modelValue) return
  if (readBack) {
    const affectedIndex = configs.value.findIndex(config => action.kind === 'add'
      ? config.modelId === action.model.id && config.tenantId === action.model.tenantId : config.id === action.config.id)
    if (affectedIndex >= 0) configuredPage.value = Math.floor(affectedIndex / pageSize) + 1
  }
  if (receipt.value === 'success' && readBack) {
    const matches = action.kind === 'delete' ? !configs.value.some(config => config.id === action.config.id)
      : !!expected && matchesReceipt(configs.value.find(config => config.id === expected?.id), expected)
    if (!matches) operationProblem.value = new TelegramAiApiError('saveMismatch', true)
  }
  requiresReview.value = receipt.value === 'unknown' || (receipt.value === 'success' && (!readBack || !!operationProblem.value))
  confirmation.value = null; pending.value = false
  await nextTick()
  if (!disposed) {
    if (receipt.value === 'failed') failureNotice.value?.focus()
    else notice.value?.focus()
  }
}
function acknowledge() {
  if (!reviewReady.value) return
  requiresReview.value = false; receipt.value = 'idle'; operationProblem.value = null; lastAction.value = null
}
function requestClose() {
  if (pending.value || requiresReview.value) {
    void nextTick(() => { if (!disposed) notice.value?.focus() })
    return
  }
  confirmation.value = null; cancelReads(); emit('update:modelValue', false)
}
function visibility(value: boolean) { if (!value) requestClose() }
function beforeUnload(event: BeforeUnloadEvent) {
  if (props.modelValue && (pending.value || requiresReview.value)) { event.preventDefault(); event.returnValue = '' }
}
function reset() {
  cancelReads(); tenants.value = []; models.value = []; configs.value = []; tenantId.value = ''
  tenantsLoaded.value = false; configsLoaded.value = false; tenantsProblem.value = null; modelsProblem.value = null; configsProblem.value = null
  operationProblem.value = null; confirmation.value = null; lastAction.value = null; receipt.value = 'idle'; requiresReview.value = false
  availablePage.value = 1; configuredPage.value = 1; configRevision.value = 0; reviewRevision.value = 0
}
watch(tenantId, () => { if (!pending.value && !confirmation.value) void loadModels() })
watch(() => savedModelTenant(), saved => {
  if (compact.value && props.modelValue && saved && saved !== tenantId.value && !pending.value && !confirmation.value
    && tenants.value.some(tenant => tenant.id === saved)) tenantId.value = saved
})
watch(availablePages, count => { availablePage.value = Math.min(availablePage.value, count) })
watch(configuredPages, count => { configuredPage.value = Math.min(configuredPage.value, count) })
watch(pending, value => emit('busy', value), { flush: 'sync' })
watch(() => props.modelValue, open => { reset(); if (open) void refresh() }, { immediate: true })
onMounted(() => window.addEventListener('beforeunload', beforeUnload))
onBeforeUnmount(() => { disposed = true; cancelReads(); confirmation.value = null; emit('busy', false); window.removeEventListener('beforeunload', beforeUnload) })
</script>

<template>
  <el-dialog :model-value="modelValue" class="telegram-ai-dialog" append-to-body destroy-on-close width="1080px"
    :title="t('notificationSettings.ai.title')" :close-on-click-modal="false" :close-on-press-escape="!pending && !requiresReview"
    :show-close="!pending && !requiresReview" :before-close="requestClose" @update:model-value="visibility">
    <div class="telegram-ai">
      <p class="telegram-ai-help">{{ t('notificationSettings.ai.intro') }}</p>
      <PageErrorNotice v-if="receipt === 'failed' && !pending" ref="failureNotice"><p v-if="lastAction"><strong>{{ outcomeModel }}</strong><span v-if="outcomeModelId"> · {{ t('notificationSettings.ai.modelId') }}: {{ outcomeModelId }}</span></p><p v-if="operationProblem">{{ errorLabel(operationProblem) }}</p></PageErrorNotice>
      <div v-else-if="receipt !== 'idle' || pending" ref="notice" class="telegram-ai-notice" role="status" tabindex="-1">
        <p v-if="lastAction" class="telegram-ai-outcome"><strong>{{ outcomeModel }}</strong><small v-if="outcomeModelId">{{ t('notificationSettings.ai.modelId') }}: {{ outcomeModelId }}</small></p>
        <p v-if="pending">{{ t('notificationSettings.ai.submitting') }}</p>
        <p v-else-if="receipt === 'unknown'">{{ t('notificationSettings.ai.unknownResult') }}</p>
        <p v-else-if="receipt === 'success'">{{ t('notificationSettings.ai.saved') }}</p>
        <PageErrorNotice v-if="operationProblem">{{ errorLabel(operationProblem) }}</PageErrorNotice>
        <p v-if="requiresReview && configsProblem" class="telegram-ai-error">{{ t('notificationSettings.ai.readbackFailed') }}</p>
        <div v-if="requiresReview" class="telegram-ai-actions"><GhostBtn :loading="configsLoading" :disabled="pending || disabled" @click="refresh">{{ t('notificationSettings.ai.refresh') }}</GhostBtn><GhostBtn :disabled="!reviewReady" @click="acknowledge">{{ t('notificationSettings.ai.reviewed') }}</GhostBtn></div>
      </div>
      <div v-if="confirmation" class="telegram-ai-confirm">
        <h3 ref="confirmHeading" tabindex="-1">{{ confirmationText }}</h3>
        <dl><dt>{{ t('notificationSettings.ai.modelId') }}</dt><dd>{{ confirmation.kind === 'add' ? confirmation.model.id : confirmation.config.modelId || '—' }}</dd><dt>{{ t('notificationSettings.ai.tenantId') }}</dt><dd>{{ confirmation.kind === 'add' ? confirmation.model.tenantId : confirmation.config.tenantId || '—' }}</dd></dl>
        <div class="telegram-ai-actions"><GhostBtn :disabled="pending" @click="cancelConfirmation">{{ t('notificationSettings.ai.cancel') }}</GhostBtn><PrimaryBtn :loading="pending" :disabled="disabled || requiresReview" @click="submit">{{ t('notificationSettings.ai.confirm') }}</PrimaryBtn></div>
      </div>
      <div class="telegram-ai-toolbar"><label for="telegram-ai-tenant">{{ t('notificationSettings.ai.tenant') }}</label><el-select id="telegram-ai-tenant" v-model="tenantId" :disabled="locked || tenantsLoading || !!tenantsProblem" :loading="tenantsLoading" :placeholder="t('notificationSettings.ai.chooseTenant')"><el-option value="" :label="t('notificationSettings.ai.chooseTenant')" /><el-option v-for="tenant in tenants" :key="tenant.id" :value="tenant.id" :label="tenant.name || tenant.id" /></el-select><GhostBtn :loading="tenantsLoading || configsLoading" :disabled="pending || !!confirmation || disabled" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('notificationSettings.ai.refresh') }}</GhostBtn></div>
      <PageErrorNotice v-if="tenantsProblem">{{ errorLabel(tenantsProblem) }}</PageErrorNotice>
      <p v-else-if="tenantsLoaded && !tenantsLoading && !tenants.length" class="telegram-ai-help">{{ t('notificationSettings.ai.noTenants') }}</p>
      <div class="telegram-ai-columns">
        <section class="telegram-ai-pane" aria-labelledby="telegram-ai-available-title">
          <header class="telegram-ai-pane-heading"><h3 id="telegram-ai-available-title">{{ t('notificationSettings.ai.available') }}</h3><GhostBtn :loading="modelsLoading" :disabled="locked || !tenantId || tenantsLoading || !!tenantsProblem" :title="t('notificationSettings.ai.reloadModels')" :aria-label="t('notificationSettings.ai.reloadModels')" @click="refreshModels"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn></header>
          <p v-if="modelsLoading" class="telegram-ai-empty" role="status">{{ t('notificationSettings.ai.loading') }}</p>
          <PageErrorNotice v-else-if="modelsProblem">{{ errorLabel(modelsProblem) }}</PageErrorNotice>
          <p v-else-if="!tenantId" class="telegram-ai-empty">{{ t('notificationSettings.ai.chooseTenant') }}</p>
          <p v-else-if="!models.length" class="telegram-ai-empty">{{ t('notificationSettings.ai.emptyModels') }}</p>
          <MobileRecordList v-if="compact" drilldown :list-id="modelListId" :record-keys="models.map(model => model.id)" :loading="modelsLoading || tenantsLoading">
            <MobileRecordCard v-for="model in mobileModels" :key="model.id" :record-key="model.id" :summary-title="modelLabel(model)" :summary-meta="`${model.provider || 'OCI'} · ${tenantLabel(model.tenantId)}`" :summary-status="configuredModels.has(model.id) ? t('notificationSettings.ai.added') : ''" :summary-tone="configuredModels.has(model.id) ? 'success' : 'neutral'">
              <template #identity><h3 class="mobile-record-title">{{ modelLabel(model) }}</h3><span class="mobile-record-subtitle">{{ model.provider || 'OCI' }}</span></template>
              <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('notificationSettings.ai.modelId') }}</dt><dd>{{ model.id }}</dd></div><div class="mobile-record-wide"><dt>{{ t('notificationSettings.ai.tenant') }}</dt><dd>{{ tenantLabel(model.tenantId) }}<span class="mobile-record-subtitle">{{ model.tenantId }}</span></dd></div></dl>
              <template #footer><GhostBtn :disabled="!canWrite || configuredModels.has(model.id) || tenantsLoading || !!tenantsProblem" @click="prepareAdd(model)"><i :class="configuredModels.has(model.id) ? 'i-mdi-check' : 'i-mdi-plus'" aria-hidden="true" />{{ t(configuredModels.has(model.id) ? 'notificationSettings.ai.added' : 'notificationSettings.ai.add') }}</GhostBtn></template>
            </MobileRecordCard>
          </MobileRecordList>
          <ul v-else-if="!modelsLoading && !modelsProblem && tenantId && models.length" class="telegram-ai-list"><li v-for="model in visibleModels" :key="model.id"><div class="telegram-ai-item"><strong>{{ modelLabel(model) }}</strong><span>{{ model.provider || 'OCI' }}</span><small :title="model.id">{{ model.id }}</small></div><GhostBtn :disabled="!canWrite || configuredModels.has(model.id) || tenantsLoading || !!tenantsProblem" @click="prepareAdd(model)"><i :class="configuredModels.has(model.id) ? 'i-mdi-check' : 'i-mdi-plus'" aria-hidden="true" />{{ t(configuredModels.has(model.id) ? 'notificationSettings.ai.added' : 'notificationSettings.ai.add') }}</GhostBtn></li></ul>
          <PagePagination v-if="models.length" v-model:current-page="availablePage" class="telegram-ai-pager" :page-size="pageSize" :total="models.length" :disabled="readLocked" embedded><span>{{ t('notificationSettings.ai.count', { count: models.length }) }}</span></PagePagination>
        </section>
        <section class="telegram-ai-pane" aria-labelledby="telegram-ai-configured-title">
          <header class="telegram-ai-pane-heading"><h3 id="telegram-ai-configured-title">{{ t('notificationSettings.ai.configured') }}</h3><span>{{ configsLoaded ? configs.length : '—' }}</span></header>
          <p class="telegram-ai-help">{{ t('notificationSettings.ai.allTenantsHint') }}</p>
          <p v-if="configsLoading" class="telegram-ai-empty" role="status">{{ t('notificationSettings.ai.loading') }}</p>
          <PageErrorNotice v-if="configsProblem">{{ errorLabel(configsProblem) }}</PageErrorNotice>
          <p v-else-if="configsLoaded && !configsLoading && !configs.length" class="telegram-ai-empty">{{ t('notificationSettings.ai.emptyConfigs') }}</p>
          <MobileRecordList v-if="compact" drilldown :list-id="configListId" :record-keys="configs.map(configKey)" :loading="configsLoading">
            <MobileRecordCard v-for="config in mobileConfigs" :key="config.id" :record-key="configKey(config)" :summary-title="configLabel(config)" :summary-meta="tenantLabel(config.tenantId)" :summary-status="t(config.enabled === true ? 'notificationSettings.ai.enabled' : config.enabled === false ? 'notificationSettings.ai.disabled' : 'notificationSettings.ai.unknownStatus')" :summary-tone="config.enabled === true ? 'success' : 'neutral'">
              <template #identity><h3 class="mobile-record-title">{{ configLabel(config) }}</h3><span class="mobile-record-subtitle">{{ tenantLabel(config.tenantId) }} · {{ t(config.enabled === true ? 'notificationSettings.ai.enabled' : config.enabled === false ? 'notificationSettings.ai.disabled' : 'notificationSettings.ai.unknownStatus') }}</span></template>
              <dl class="mobile-record-fields"><div><dt>{{ t('notificationSettings.ai.configId') }}</dt><dd>{{ config.id }}</dd></div><div><dt>{{ t('notificationSettings.ai.tenantId') }}</dt><dd>{{ config.tenantId || '—' }}</dd></div><div class="mobile-record-wide"><dt>{{ t('notificationSettings.ai.modelId') }}</dt><dd>{{ config.modelId || '—' }}</dd></div></dl>
              <template #footer><GhostBtn v-if="config.enabled !== true" :disabled="!canWrite || config.cloudType !== 1" @click="prepareConfig(config, 'toggle', true)">{{ t('notificationSettings.ai.enable') }}</GhostBtn><GhostBtn v-if="config.enabled !== false" :disabled="!canWrite || config.cloudType !== 1" @click="prepareConfig(config, 'toggle', false)">{{ t('notificationSettings.ai.disable') }}</GhostBtn><GhostBtn danger :disabled="!canWrite" @click="prepareConfig(config, 'delete')"><i class="i-mdi-delete-outline" aria-hidden="true" />{{ t('notificationSettings.ai.delete') }}</GhostBtn></template>
            </MobileRecordCard>
          </MobileRecordList>
          <ul v-else class="telegram-ai-list"><li v-for="config in visibleConfigs" :key="config.id"><div class="telegram-ai-item"><strong>{{ configLabel(config) }}</strong><span>{{ tenantLabel(config.tenantId) }}</span><small>{{ t('notificationSettings.ai.configId') }}: {{ config.id }} · {{ t(config.enabled === true ? 'notificationSettings.ai.enabled' : config.enabled === false ? 'notificationSettings.ai.disabled' : 'notificationSettings.ai.unknownStatus') }}</small><small :title="config.modelId">{{ config.modelId || '—' }}</small></div><div class="telegram-ai-row-actions"><GhostBtn v-if="config.enabled !== true" :disabled="!canWrite || config.cloudType !== 1" @click="prepareConfig(config, 'toggle', true)">{{ t('notificationSettings.ai.enable') }}</GhostBtn><GhostBtn v-if="config.enabled !== false" :disabled="!canWrite || config.cloudType !== 1" @click="prepareConfig(config, 'toggle', false)">{{ t('notificationSettings.ai.disable') }}</GhostBtn><GhostBtn danger :disabled="!canWrite" :title="t('notificationSettings.ai.delete')" :aria-label="t('notificationSettings.ai.delete')" @click="prepareConfig(config, 'delete')"><i class="i-mdi-delete-outline" aria-hidden="true" /></GhostBtn></div></li></ul>
          <PagePagination v-if="configs.length" v-model:current-page="configuredPage" class="telegram-ai-pager" :page-size="pageSize" :total="configs.length" :disabled="readLocked" embedded><span>{{ t('notificationSettings.ai.count', { count: configs.length }) }}</span></PagePagination>
        </section>
      </div>
    </div>
    <template #footer><GhostBtn :disabled="pending || requiresReview" @click="requestClose">{{ t('notificationSettings.ai.close') }}</GhostBtn></template>
  </el-dialog>
</template>

<style scoped>
:global(.telegram-ai-dialog) { max-width: calc(100vw - 28px); margin-top: min(6vh, 48px); background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); }
:global(.telegram-ai-dialog .el-dialog__title) { color: var(--text-primary); font: 600 var(--font-size-dialog-title)/1.5 var(--sans); }
:global(.telegram-ai-dialog .el-dialog__body) { max-height: calc(85vh - 120px); max-height: calc(85dvh - 120px); overflow-y: auto; scrollbar-gutter: stable; }
.telegram-ai { min-width: 0; color: var(--text-primary); font: 400 var(--font-size-body)/1.5 var(--sans); }
.telegram-ai-help { margin: 0 0 12px; font-size: var(--font-size-secondary); color: var(--text-secondary); line-height: 1.6; }
.telegram-ai-toolbar { display: flex; align-items: center; flex-wrap: wrap; gap: 12px; margin: 18px 0; }
.telegram-ai-toolbar > label { font-weight: 500; }
.telegram-ai-toolbar > .el-select { flex: 1; min-width: 120px; max-width: 500px; }
.telegram-ai-columns { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.15fr); }
.telegram-ai-pane { min-width: 0; }
.telegram-ai-pane:first-child { padding-right: 24px; }
.telegram-ai-pane + .telegram-ai-pane { padding-left: 24px; border-left: 1px solid var(--border); }
.telegram-ai-pane-heading { display: flex; align-items: center; justify-content: space-between; gap: 10px; min-height: 38px; margin-bottom: 10px; }
.telegram-ai-pane-heading h3, .telegram-ai-confirm h3 { margin: 0; color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; line-height: 1.5; }
.telegram-ai-pane-heading > span { font-size: var(--font-size-secondary); }
.telegram-ai-list { margin: 0; padding: 0; list-style: none; }
.telegram-ai-list > li { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-width: 0; padding: 14px 0; border-bottom: 1px solid var(--border); }
.telegram-ai-item { display: grid; flex: 1; min-width: 0; gap: 4px; }
.telegram-ai-item strong { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 500; overflow-wrap: anywhere; }
.telegram-ai-item > span, .telegram-ai-item > small { min-width: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.telegram-ai-item > small:last-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.telegram-ai-row-actions, .telegram-ai-actions { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; }
.telegram-ai-row-actions { flex: none; max-width: 150px; justify-content: flex-end; }
.telegram-ai :deep(.btn) { min-height: 34px; padding: 6px 10px; font-size: var(--font-size-body); }
.telegram-ai i { display: inline-block; flex: none; width: 18px; height: 18px; }
.telegram-ai-empty { margin: 0; padding: 24px 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.telegram-ai-error { margin: 10px 0; color: var(--status-danger); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.telegram-ai-notice, .telegram-ai-confirm { margin: 14px 0; padding: 14px 0 18px; border-bottom: 1px solid var(--border); }
.telegram-ai-notice > p { margin: 0 0 10px; }
.telegram-ai-outcome { display: grid; gap: 4px; overflow-wrap: anywhere; }
.telegram-ai-outcome > strong { font-weight: 500; }
.telegram-ai-outcome > small { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.telegram-ai-notice:focus, .telegram-ai-confirm h3:focus { outline: 2px solid var(--brand); outline-offset: 3px; }
.telegram-ai-confirm dl { display: grid; grid-template-columns: 90px minmax(0, 1fr); gap: 7px 12px; margin: 12px 0; font-size: var(--font-size-secondary); }
.telegram-ai-confirm dt, .telegram-ai-confirm dd { margin: 0; overflow-wrap: anywhere; }
.telegram-ai-pager { margin-top: 14px; }
@media (max-width: 760px) {
  .telegram-ai-columns { grid-template-columns: minmax(0, 1fr); gap: 24px; }
  .telegram-ai-pane:first-child { padding-right: 0; }
  .telegram-ai-pane + .telegram-ai-pane { padding: 24px 0 0; border-left: 0; border-top: 1px solid var(--border); }
  .telegram-ai-toolbar > .el-select { max-width: none; }
}
@media (max-width: 400px) { .telegram-ai-list > li { align-items: flex-start; flex-direction: column; } .telegram-ai-row-actions { max-width: none; } }
</style>
