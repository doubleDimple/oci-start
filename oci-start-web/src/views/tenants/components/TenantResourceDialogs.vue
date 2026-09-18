<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantGet, tenantPut } from '@/api/tenant'
import PagePagination from '@/components/PagePagination.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'

type Row = Record<string, any>
type UiMessage = string | { key: string; params?: Record<string, string | number> }

const { t } = useI18n()
const compact = useCompactViewport()
const props = defineProps<{ tenant: Row | null; action: string }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const titles = computed<Record<string, string>>(() => ({
  detail: t('tenantResources.titles.detail'), volumes: t('tenantResources.titles.volumes'), quota: t('tenantResources.titles.quota'), transferDetail: t('tenantResources.titles.transferDetail'),
}))
const visible = computed(() => Boolean(props.tenant && titles.value[props.action]))
const tenantName = computed(() => props.tenant?.defName || props.tenant?.tenancyName || props.tenant?.userName || t('tenantResources.currentTenant'))
const loading = ref(false)
const saving = ref(false)
const error = ref<UiMessage>('')
let session = 0
let controller = new AbortController()
const config = () => ({ signal: controller.signal, silent: true, timeout: 120000 })

function localMessage(key: string): UiMessage {
  return { key: `tenantResources.${key}` }
}
function displayMessage(value: UiMessage) {
  return typeof value === 'string' ? value : t(value.key, value.params || {})
}
function message(cause: any): UiMessage {
  if (typeof cause?.key === 'string' && cause.key.startsWith('tenantResources.')) return cause
  const raw = cause?.response?.data?.error || cause?.response?.data?.message || cause?.message || cause?.error
  return raw ? String(raw) : localMessage('errors.loadFailed')
}

function close() {
  if (!saving.value) emit('close')
}

const detail = computed<Row | null>(() => props.tenant?.registerDetail || null)
function typeName(value: unknown, plan = false) {
  const raw = value && typeof value === 'object'
    ? (value as Row).value ?? (value as Row).code ?? ''
    : value
  const text = String(raw || '')
  const key = text.toUpperCase().replace(/[-_\s]/g, '')
  const types: Record<string, string> = plan
    ? { FREETIER: 'free', FREE: 'free', PAID: 'paid', PAYG: 'paid', PAYASYOUGO: 'paid' }
    : { PERSONAL: 'personal', CORPORATE: 'corporate', CORPORATESUBMITTED: 'corporateSubmitted' }
  return types[key] ? t(`tenantResources.account.types.${types[key]}`) : text
}
const accountPlan = computed(() => [typeName(detail.value?.accountType), typeName(detail.value?.planType, true)].filter(Boolean).join(' · ') || '—')
const accountAddress = computed(() => [detail.value?.country, detail.value?.city, detail.value?.line1].filter((part) => String(part || '').trim()).join(' · ') || '—')
const transferAmount = computed(() => {
  const amount = props.tenant?.transferAmount
  return amount && amount !== 'null' ? amount : '0'
})

const volumes = ref<Row[]>([])
const editingVolume = ref<Row | null>(null)
const volumeName = ref('')
const volumeVpus = ref(10)
const volumeError = ref<UiMessage>('')

async function loadVolumes() {
  const current = session
  loading.value = true
  error.value = ''
  try {
    const result = await tenantGet<Row[]>('/tenants/boot-volumes', { tenantId: String(props.tenant!.id) }, config())
    if (current === session) volumes.value = result
  } catch (cause) {
    if (current === session) error.value = message(cause)
  } finally {
    if (current === session) loading.value = false
  }
}

function editVolume(row: Row) {
  editingVolume.value = row
  volumeName.value = row.displayName || ''
  const vpus = Number(row.vpusPerGB ?? 10)
  volumeVpus.value = Number.isFinite(vpus) ? vpus : 10
  volumeError.value = ''
}

async function saveVolume() {
  const row = editingVolume.value
  if (!row || saving.value) return
  const name = volumeName.value.trim()
  if (!name) {
    volumeError.value = localMessage('errors.volumeName')
    return
  }
  const displayName = name === row.displayName ? '' : name
  const vpusPerGB = volumeVpus.value === Number(row.vpusPerGB) ? -1 : volumeVpus.value
  if (!displayName && vpusPerGB === -1) {
    editingVolume.value = null
    return
  }
  const current = session
  const tenantId = String(props.tenant!.id)
  const proposedVpus = volumeVpus.value
  saving.value = true
  volumeError.value = ''
  try {
    try {
      await ElMessageBox.confirm(t('tenantResources.volume.confirmMessage', { previous: row.displayName || t('tenantResources.volume.fallbackName'), name, vpus: proposedVpus }), t('tenantResources.volume.confirmTitle'), {
        customClass: 'tenant-resource-confirm',
        confirmButtonText: t('tenantResources.volume.confirmAction'), cancelButtonText: t('tenantResources.cancel'), type: 'warning',
      })
    } catch { return }
    if (current !== session || editingVolume.value !== row) return
    await tenantPut(`/tenants/update-volumes/${encodeURIComponent(row.id)}`, {
      tenantId, displayName, vpusPerGB,
    }, config())
    if (current !== session) return
    row.displayName = name
    row.vpusPerGB = proposedVpus
    editingVolume.value = null
    ElMessage.success(t('tenantResources.volume.updated'))
    emit('changed')
  } catch (cause) {
    if (current === session) volumeError.value = message(cause)
  } finally {
    if (current === session) saving.value = false
  }
}

const quotaRegions = ref<Row[]>([])
const regionsLoading = ref(false)
const regionsError = ref<UiMessage>('')
const quotaTenantId = ref('')
const quotaService = ref('compute')
const quotaPageSize = ref(20)
const quotaPage = ref(0)
const quota = ref<Row | null>(null)
const services = computed(() => [
  { group: t('tenantResources.quota.services.computeStorage'), options: [
    { value: 'compute', label: t('tenantResources.quota.services.compute') },
    { value: 'block-storage', label: t('tenantResources.quota.services.blockStorage') },
    { value: 'object-storage', label: t('tenantResources.quota.services.objectStorage') },
  ] },
  { group: t('tenantResources.quota.services.databases'), options: [
    { value: 'mysql', label: t('tenantResources.quota.services.mysql') },
    { value: 'database', label: t('tenantResources.quota.services.database') },
    { value: 'autonomous-database', label: t('tenantResources.quota.services.autonomousDatabase') },
    { value: 'nosql', label: t('tenantResources.quota.services.nosql') },
  ] },
])
const quotaRows = computed<Row[]>(() => quota.value?.items || [])
const queriedService = computed(() => services.value.flatMap((group) => group.options).find((option) => option.value === quota.value?.service)?.label || '')
const hasInstanceTypes = computed(() => quotaRows.value.some((row) => instanceType(row.name)))

async function loadQuotaRegions() {
  const current = session
  regionsLoading.value = true
  regionsError.value = ''
  const tenantId = String(props.tenant!.id)
  try {
    const result = await tenantGet<Row[]>('/tenants/listRegions', { parentId: tenantId }, config())
    if (current !== session) return
    quotaRegions.value = result.length ? result : [props.tenant!]
    quotaTenantId.value = String(quotaRegions.value[0]!.id)
  } catch (cause) {
    if (current !== session) return
    quotaRegions.value = [props.tenant!]
    quotaTenantId.value = tenantId
    regionsError.value = message(cause)
  } finally {
    if (current === session) regionsLoading.value = false
  }
}

function resetQuota() {
  quota.value = null
  quotaPage.value = 0
  error.value = ''
}

async function queryQuota(page = 0) {
  if (loading.value || !quotaTenantId.value) return
  const current = session
  loading.value = true
  error.value = ''
  try {
    const result = await tenantGet<Row>('/tenants/quota', {
      tenantId: quotaTenantId.value, serviceName: quotaService.value, page, pageSize: quotaPageSize.value,
    }, config())
    if (current !== session) return
    if (result.error) throw new Error(String(result.error))
    quota.value = result
    quotaPage.value = Number(result.page ?? page)
  } catch (cause) {
    if (current === session) error.value = message(cause)
  } finally {
    if (current === session) loading.value = false
  }
}

function changeQuotaPage(value: number) {
  const knownPages = quotaPage.value + 1 + (quota.value?.hasNextPage ? 1 : 0)
  if (!Number.isInteger(value) || value < 1 || value > knownPages || value === quotaPage.value + 1) return
  void queryQuota(value - 1)
}
function changeQuotaSize(value: number) {
  if (loading.value || ![10, 20, 50].includes(value) || value === quotaPageSize.value) return
  quotaPageSize.value = value
  void queryQuota(0)
}

function instanceType(value: unknown) {
  const name = String(value || '').toLowerCase()
  const bareMetal = name.startsWith('bm-') || name.includes('-bm-')
  const matches: [RegExp, string][] = [
    [/-a[12]-/, 'ampere'], [/-e5-/, 'amdE5'], [/-e4-/, 'amdE4'], [/-e3-/, 'amdE3'],
    [/-e2-|e2-1-micro/, 'amdE2'], [/gpu/, 'gpu'], [/hpc/, 'hpc'], [/optimized3/, 'intelHighFrequency'],
    [/x9-/, 'intelX9'], [/-x8-/, 'intelX8'], [/-x7-/, 'intelX7'], [/standard3/, 'intel'],
    [/standard2/, 'intelLegacy'], [/dense-a4-ax/, 'denseA4'], [/dense-?io/, 'denseIo'],
    [/autonomous-|-adb-|^adb-/, 'adb'], [/mysql/, 'mysql'], [/nosql/, 'nosql'],
    [/exadata/, 'exadata'], [/db-system|db-vcpu|db-node/, 'dbcs'],
  ]
  const type = matches.find(([pattern]) => pattern.test(name))?.[1]
  const label = type ? t(`tenantResources.quota.instanceTypes.${type}`) : ''
  return bareMetal ? (label ? t('tenantResources.quota.bareMetalType', { type: label }) : t('tenantResources.quota.bareMetal')) : label
}

function usage(row: Row) {
  return Number(row.total) > 0 ? Math.min(100, Math.max(0, Math.round(Number(row.used || 0) / Number(row.total) * 100))) : 0
}

function usageClass(row: Row) {
  const percent = usage(row)
  return percent >= 90 ? 'danger' : percent >= 60 ? 'warning' : 'healthy'
}

watch(() => [props.action, props.tenant?.id], () => {
  session += 1
  controller.abort()
  controller = new AbortController()
  loading.value = false
  saving.value = false
  error.value = ''
  editingVolume.value = null
  volumes.value = []
  resetQuota()
  quotaRegions.value = []
  quotaTenantId.value = ''
  quotaService.value = 'compute'
  regionsError.value = ''
  if (!props.tenant) return
  if (props.action === 'volumes') void loadVolumes()
  if (props.action === 'quota') void loadQuotaRegions()
}, { immediate: true })

onBeforeUnmount(() => {
  session += 1
  controller.abort()
})
</script>

<template>
  <el-dialog
    v-if="visible"
    :model-value="true"
    :title="titles[action]"
    :width="action === 'detail' || action === 'transferDetail' ? 'min(620px, calc(100vw - 32px))' : 'min(1080px, calc(100vw - 32px))'"
    class="tenant-resource-dialog"
    :close-on-click-modal="!saving"
    :close-on-press-escape="!saving"
    :show-close="!saving"
    align-center
    append-to-body
    destroy-on-close
    @close="close"
  >
    <div class="resource-body">
      <p class="resource-context">{{ tenantName }}<span v-if="tenant?.region"> · {{ tenant.region }}</span></p>

      <template v-if="action === 'detail'">
        <dl v-if="detail" class="account-details">
          <div class="detail-feature"><dt>{{ t('tenantResources.account.typeAndPlan') }}</dt><dd>{{ accountPlan }}</dd></div>
          <div><dt>{{ t('tenantResources.account.registeredAt') }}</dt><dd>{{ detail.registerTime || '—' }}</dd></div>
          <div><dt>{{ t('tenantResources.account.subscriptionNumber') }}</dt><dd>{{ detail.subscriptionPlanNumber || '—' }}</dd></div>
          <div><dt>{{ t('tenantResources.account.email') }}</dt><dd>{{ detail.emailAddress || '—' }}</dd></div>
          <div><dt>{{ t('tenantResources.account.address') }}</dt><dd>{{ accountAddress }}</dd></div>
        </dl>
        <el-empty v-else :description="t('tenantResources.account.empty')" :image-size="80" />
      </template>

      <template v-else-if="action === 'transferDetail'">
        <div class="transfer-summary"><span>{{ t('tenantResources.transferAmount') }}</span><strong>{{ transferAmount }}</strong></div>
      </template>

      <template v-else-if="action === 'volumes'">
        <div class="resource-toolbar"><span>{{ t('tenantResources.volume.description') }}</span><el-button :loading="loading" :disabled="saving" @click="loadVolumes">{{ t('tenantResources.refresh') }}</el-button></div>
        <PageErrorNotice v-if="error">{{ displayMessage(error) }}</PageErrorNotice>
        <MobileRecordList v-if="compact" drilldown :list-id="`tenant-resource-volumes-${tenant?.id}`" :record-keys="volumes.map(row => String(row.id))" :loading="loading" class="resource-mobile-list">
          <MobileRecordCard v-for="row in volumes" :key="row.id" :record-key="String(row.id)" :summary-title="row.displayName || '—'" :summary-meta="row.instanceName || '—'" :summary-status="row.sizeInGBs == null ? undefined : `${row.sizeInGBs} GB`">
            <template #identity><h3 class="mobile-record-title">{{ row.displayName || '—' }}</h3></template>
            <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('tenantResources.volume.instance') }}</dt><dd>{{ row.instanceName || '—' }}</dd></div><div><dt>{{ t('tenantResources.volume.size') }}</dt><dd>{{ row.sizeInGBs ?? '—' }}</dd></div><div><dt>{{ t('tenantResources.volume.vpus') }}</dt><dd>{{ row.vpusPerGB ?? '—' }}</dd></div></dl>
            <template #footer><el-button :disabled="saving || loading" @click="editVolume(row)">{{ t('tenantResources.edit') }}</el-button></template>
          </MobileRecordCard>
          <p v-if="loading || !volumes.length" class="resource-mobile-empty" role="status">{{ t(loading ? 'pageLoading.loading' : 'tenantResources.volume.empty') }}</p>
        </MobileRecordList>
        <el-table v-else :data="volumes" v-loading="loading" max-height="380" row-key="id" class="resource-table" :empty-text="t('tenantResources.volume.empty')">
          <el-table-column prop="instanceName" :label="t('tenantResources.volume.instance')" min-width="160"><template #default="{ row }">{{ row.instanceName || '—' }}</template></el-table-column>
          <el-table-column prop="displayName" :label="t('tenantResources.volume.name')" min-width="210" show-overflow-tooltip />
          <el-table-column prop="sizeInGBs" :label="t('tenantResources.volume.size')" width="120" />
          <el-table-column prop="vpusPerGB" :label="t('tenantResources.volume.vpus')" width="110" />
          <el-table-column :label="t('tenantResources.actions')" width="90" fixed="right"><template #default="{ row }"><el-button link :disabled="saving" @click="editVolume(row)">{{ t('tenantResources.edit') }}</el-button></template></el-table-column>
        </el-table>
        <Transition name="resource-reveal">
          <section v-if="editingVolume" class="volume-editor" :aria-label="t('tenantResources.volume.editTitle')">
            <h3>{{ t('tenantResources.volume.editTitle') }}</h3>
            <el-form label-position="top" :disabled="saving" @submit.prevent="saveVolume">
              <el-form-item :label="t('tenantResources.volume.name')"><el-input v-model="volumeName" :placeholder="t('tenantResources.volume.namePlaceholder')" /></el-form-item>
              <el-form-item :label="t('tenantResources.volume.performance')"><el-slider v-model="volumeVpus" :min="Math.min(10, Number(editingVolume.vpusPerGB ?? 10))" :max="120" :step="10" show-input :aria-label="t('tenantResources.volume.performanceAria')" /></el-form-item>
              <PageErrorNotice v-if="volumeError">{{ displayMessage(volumeError) }}</PageErrorNotice>
              <div class="editor-actions"><el-button :disabled="saving" @click="editingVolume = null">{{ t('tenantResources.cancel') }}</el-button><el-button type="primary" :loading="saving" native-type="submit">{{ t('tenantResources.saveChanges') }}</el-button></div>
            </el-form>
          </section>
        </Transition>
      </template>

      <template v-else-if="action === 'quota'">
        <el-form class="query-filters" label-position="top" :disabled="loading" @submit.prevent="queryQuota(0)">
          <el-form-item :label="t('tenantResources.quota.tenantRegion')" class="filter-grow">
            <el-select v-model="quotaTenantId" popper-class="tenant-resource-select" filterable :loading="regionsLoading" :disabled="regionsLoading" :placeholder="t('tenantResources.quota.regionPlaceholder')" @change="resetQuota">
              <el-option v-for="(region, index) in quotaRegions" :key="`${region.id}-${index}`" :value="String(region.id)" :label="`${region.tenancyName || region.userName || t('tenantResources.currentTenant')}${region.region ? ` · ${region.region}` : ''}`" />
            </el-select>
          </el-form-item>
          <el-form-item :label="t('tenantResources.quota.serviceType')" class="filter-grow">
            <el-select v-model="quotaService" popper-class="tenant-resource-select" @change="resetQuota">
              <el-option-group v-for="group in services" :key="group.group" :label="group.group"><el-option v-for="option in group.options" :key="option.value" v-bind="option" /></el-option-group>
            </el-select>
          </el-form-item>
          <el-form-item><el-button native-type="submit" type="primary" :loading="loading" :disabled="!quotaTenantId || regionsLoading">{{ t('tenantResources.quota.query') }}</el-button></el-form-item>
        </el-form>
        <PageErrorNotice v-if="regionsError">{{ t('tenantResources.errors.regionsFallback', { message: displayMessage(regionsError) }) }}</PageErrorNotice>
        <PageErrorNotice v-if="error">{{ displayMessage(error) }}</PageErrorNotice>
        <div v-loading="loading" class="resource-results" :aria-busy="loading">
          <template v-if="quota">
            <p class="result-caption" aria-live="polite">{{ t('tenantResources.quota.caption', { region: quota.region || '', service: queriedService, count: quotaRows.length }) }}</p>
            <MobileRecordList v-if="compact" drilldown :list-id="`tenant-quota-${tenant?.id}-${quotaTenantId}-${quota.service}-${quotaPage}`" :record-keys="quotaRows.map(row => String(row.name))" :loading="loading" class="resource-mobile-list">
              <MobileRecordCard v-for="row in quotaRows" :key="row.name" :record-key="String(row.name)" :summary-title="row.name || '—'" :summary-meta="instanceType(row.name) || queriedService" :summary-status="`${t('tenantResources.quota.available')}: ${row.available ?? 0}`" :summary-tone="Number(row.available || 0) <= 0 ? 'danger' : 'success'">
                <template #identity><h3 class="mobile-record-title">{{ row.name || '—' }}</h3></template>
                <dl class="mobile-record-fields">
                  <div v-if="hasInstanceTypes" class="mobile-record-wide"><dt>{{ t('tenantResources.quota.instanceType') }}</dt><dd>{{ instanceType(row.name) || '—' }}</dd></div>
                  <div><dt>{{ t('tenantResources.quota.total') }}</dt><dd>{{ row.total ?? 0 }}</dd></div><div><dt>{{ t('tenantResources.quota.used') }}</dt><dd>{{ row.used ?? 0 }}</dd></div>
                  <div><dt>{{ t('tenantResources.quota.available') }}</dt><dd :class="Number(row.available || 0) <= 0 ? 'danger' : 'healthy'">{{ row.available ?? 0 }}</dd></div>
                  <div class="mobile-record-wide"><dt>{{ t('tenantResources.quota.usage') }}</dt><dd><div class="usage" :class="usageClass(row)"><span class="usage-track" role="progressbar" :aria-valuenow="usage(row)" :aria-valuemin="0" :aria-valuemax="100" :aria-label="t('tenantResources.quota.usageAria', { name: row.name })"><span :style="{ transform: `scaleX(${usage(row) / 100})` }" /></span><span>{{ usage(row) }}%</span></div></dd></div>
                </dl>
              </MobileRecordCard>
              <p v-if="!quotaRows.length" class="resource-mobile-empty" role="status">{{ t('tenantResources.quota.empty') }}</p>
            </MobileRecordList>
            <el-table v-else :data="quotaRows" max-height="390" class="resource-table" :empty-text="t('tenantResources.quota.empty')">
              <el-table-column prop="name" :label="t('tenantResources.quota.limitName')" min-width="245" show-overflow-tooltip />
              <el-table-column v-if="hasInstanceTypes" :label="t('tenantResources.quota.instanceType')" min-width="140"><template #default="{ row }"><span class="instance-type">{{ instanceType(row.name) || '—' }}</span></template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.total')" width="80" align="right"><template #default="{ row }">{{ row.total ?? 0 }}</template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.used')" width="80" align="right"><template #default="{ row }">{{ row.used ?? 0 }}</template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.available')" width="95" align="right"><template #default="{ row }"><span :class="Number(row.available || 0) <= 0 ? 'danger' : 'healthy'">{{ row.available ?? 0 }}</span></template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.usage')" min-width="155"><template #default="{ row }"><div class="usage" :class="usageClass(row)"><span class="usage-track" role="progressbar" :aria-valuenow="usage(row)" :aria-valuemin="0" :aria-valuemax="100" :aria-label="t('tenantResources.quota.usageAria', { name: row.name })"><span :style="{ transform: `scaleX(${usage(row) / 100})` }" /></span><span>{{ usage(row) }}%</span></div></template></el-table-column>
            </el-table>
            <PagePagination embedded cursor class="resource-pagination" :current-page="quotaPage + 1" :page-size="quotaPageSize" :has-next="!!quota.hasNextPage" :has-previous="quotaPage > 0" :page-sizes="[10, 20, 50]" :disabled="loading" @current-change="changeQuotaPage" @size-change="changeQuotaSize"><span aria-live="polite">{{ t('tenantResources.pageNumber', { page: quotaPage + 1 }) }}</span></PagePagination>
          </template>
          <el-empty v-else :description="loading ? t('tenantResources.quota.loading') : t('tenantResources.quota.selectPrompt')" :image-size="88" />
        </div>
      </template>

    </div>
    <template v-if="action === 'detail' || action === 'transferDetail'" #footer><el-button @click="close">{{ t('tenantResources.close') }}</el-button></template>
  </el-dialog>
</template>

<style scoped>
.resource-body { color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.tenant-resource-dialog) { font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
:global(.tenant-resource-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); font-weight: 600; color: var(--text-primary); }
:global(.tenant-resource-confirm) { font-family: var(--sans); --el-messagebox-title-color: var(--text-primary); --el-messagebox-content-color: var(--text-primary); --el-messagebox-font-size: var(--font-size-dialog-title); --el-messagebox-content-font-size: var(--font-size-body); }
:global(.tenant-resource-confirm .el-message-box__title) { font-weight: 600; }
:global(.tenant-resource-select.el-popper) { font-family: var(--sans); font-size: var(--font-size-body); }
:global(.tenant-resource-select .el-select-group__title) { color: var(--text-secondary); font-size: var(--font-size-secondary); }
:global(.tenant-resource-dialog .el-button), :global(.tenant-resource-dialog .el-input__inner), :global(.tenant-resource-dialog .el-select__wrapper), :global(.tenant-resource-dialog .el-form-item__label), :global(.tenant-resource-dialog .el-checkbox__label), :global(.tenant-resource-dialog .el-radio__label), :global(.tenant-resource-dialog .el-table) { font-size: var(--font-size-body); }
:global(.tenant-resource-dialog .el-tag) { font-size: var(--font-size-caption); }
:global(.tenant-resource-dialog .el-alert__title) { font-size: var(--font-size-body); }
:global(.tenant-resource-dialog .el-alert__description), :global(.tenant-resource-dialog .el-form-item__error), :global(.tenant-resource-dialog .el-empty__description p) { font-size: var(--font-size-secondary); }
.resource-context { margin: -4px 0 24px; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.account-details { margin: 0; }
.account-details > div { display: grid; grid-template-columns: 128px minmax(0, 1fr); gap: 20px; padding: 18px 0; border-bottom: 1px solid var(--border); }
.account-details > div:last-child { border-bottom: 0; }
.account-details dt { color: var(--text-secondary); }
.account-details dd { margin: 0; overflow-wrap: anywhere; }
.account-details .detail-feature { display: block; padding: 24px; margin-bottom: 6px; background: var(--bg-search); border: 0; border-radius: var(--r-card); }
.detail-feature dd { margin-top: 8px; font-size: var(--font-size-section); font-weight: 600; letter-spacing: -.022em; }
.transfer-summary { display: grid; gap: 12px; padding: 30px 0 38px; text-align: center; color: var(--text-secondary); }
.transfer-summary strong { font-size: 44px; font-weight: 600; color: var(--brand); font-variant-numeric: tabular-nums; }
.resource-toolbar, .query-filters { display: flex; align-items: center; gap: 12px; }
.resource-toolbar { justify-content: space-between; flex-wrap: wrap; margin-bottom: 18px; color: var(--text-secondary); }
.resource-toolbar > span { font-size: var(--font-size-secondary); }
.query-filters { align-items: flex-end; flex-wrap: wrap; gap: 12px; }
.query-filters :deep(.el-form-item) { margin-bottom: 18px; }
.resource-body :deep(.el-form-item__label) { font-family: var(--sans); color: var(--text-primary); }
.filter-grow { flex: 1 1 220px; }
.resource-results { min-height: 230px; }
.resource-table { margin-top: 14px; border-radius: var(--r-sm); font-variant-numeric: tabular-nums; }
.resource-table :deep(.el-table__cell) { padding: 13px 0; }
.resource-table :deep(th.el-table__cell) { font-size: var(--font-size-body); font-weight: 600; color: var(--text-secondary); }
.resource-pagination { margin-top: 18px; }
.result-caption { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.instance-type { font-size: var(--font-size-body); color: var(--text-primary); }
.usage { display: flex; align-items: center; gap: 10px; font-size: var(--font-size-body); font-variant-numeric: tabular-nums; }
.usage > span:last-child { width: 35px; text-align: right; }
.usage-track { flex: 1; height: 6px; overflow: hidden; border-radius: var(--r-pill); background: var(--bg-search); }
.usage-track > span { display: block; height: 100%; border-radius: inherit; background: currentColor; transform-origin: left; transition: transform 460ms cubic-bezier(.22, 1, .36, 1); }
.healthy { color: var(--status-ok); }
.warning { color: var(--status-warn); }
.danger { color: var(--status-danger); }
.volume-editor { margin-top: 20px; padding: 24px; background: var(--bg-search); border-radius: var(--r-card); }
.volume-editor h3 { margin: 0 0 20px; font-size: var(--font-size-section); font-weight: 600; }
.volume-editor :deep(.el-slider) { margin-inline: 7px; }
.editor-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 22px; }
.editor-actions :deep(.el-button + .el-button) { margin-left: 0; }
.resource-reveal-enter-active, .resource-reveal-leave-active { transition: transform 320ms cubic-bezier(.22, 1, .36, 1), opacity 220ms ease; }
.resource-reveal-enter-from, .resource-reveal-leave-to { opacity: 0; transform: translateY(8px); }
@media (max-width: 600px) {
  .account-details > div { grid-template-columns: 1fr; gap: 7px; }
  .detail-feature dd { font-size: var(--font-size-section); }
  .volume-editor { padding: 18px; }
  .volume-editor :deep(.el-slider__input) { width: 100px; }
}
@media (max-width: 760px) {
  :global(.tenant-resource-dialog) { max-height: calc(100dvh - 32px); overflow-y: auto; }
  .resource-body, .query-filters, .filter-grow { min-width: 0; }
  .resource-results { min-height: 100px; }
  .resource-mobile-list { padding: 0; max-height: 52dvh; overflow-y: auto; overscroll-behavior: contain; }
  .resource-mobile-empty { display: grid; place-items: center; min-height: 88px; margin: 0; color: var(--text-secondary); font-size: var(--font-size-body); }
  .resource-mobile-list :deep(.el-button) { min-height: 44px; height: auto; max-width: 100%; white-space: normal; }
  .result-caption { margin-bottom: 12px; overflow-wrap: anywhere; }
  .editor-actions { flex-wrap: wrap; }
}
@media (prefers-reduced-motion: reduce) {
  .resource-reveal-enter-active, .resource-reveal-leave-active, .usage-track > span { transition: none; }
}
</style>
