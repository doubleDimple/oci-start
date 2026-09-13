<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { tenantGet, tenantPost, tenantPut } from '@/api/tenant'

type Row = Record<string, any>
type AuditPage = { rows: Row[]; nextToken: string | null }
type UiMessage = string | { key: string; params?: Record<string, string | number> }

const { t } = useI18n()
const props = defineProps<{ tenant: Row | null; action: string }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const titles = computed<Record<string, string>>(() => ({
  detail: t('tenantResources.titles.detail'), volumes: t('tenantResources.titles.volumes'), quota: t('tenantResources.titles.quota'), audit: t('tenantResources.titles.audit'), transferDetail: t('tenantResources.titles.transferDetail'),
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

const auditStart = ref('')
const auditEnd = ref('')
const auditDates = ref({ startDate: '', endDate: '' })
const auditPage = ref(1)
const auditCache = ref<Record<number, AuditPage>>({})
const auditTokens = ref<Record<number, string | null>>({ 1: null })
const auditRows = computed(() => auditCache.value[auditPage.value]?.rows || [])
const auditHasNext = computed(() => Boolean(auditCache.value[auditPage.value]?.nextToken))
const auditKnownPages = computed(() => Math.max(1, ...Object.keys(auditTokens.value).map(Number)))
const auditCount = computed(() => Object.values(auditCache.value).reduce((total, page) => total + page.rows.length, 0))
const auditOffset = computed(() => Object.entries(auditCache.value).reduce((count, [page, data]) => Number(page) < auditPage.value ? count + data.rows.length : count, 0))

function auditRowClass({ row }: { row: Row }) {
  return row.responseStatus && String(row.responseStatus) !== '200' ? 'audit-error-row' : ''
}

function auditCell(row: Row, column: { property: string }) {
  return row[column.property] || '—'
}

async function loadAudit(page = 1) {
  if (loading.value || (page > 1 && !(page in auditTokens.value))) return
  error.value = ''
  if (auditCache.value[page]) {
    auditPage.value = page
    return
  }
  const current = session
  loading.value = true
  try {
    const result = await tenantPost<Row>('/tenants/audit/log', {
      tenantId: String(props.tenant!.id), ...auditDates.value, pageToken: auditTokens.value[page] || null,
    }, config())
    if (current !== session) return
    const data = result.data
    if (!data || !Array.isArray(data.data)) throw localMessage('errors.auditFormat')
    const nextToken = data.nextPageToken || null
    auditCache.value[page] = { rows: data.data, nextToken }
    if (nextToken) auditTokens.value[page + 1] = nextToken
    auditPage.value = page
  } catch (cause) {
    if (current === session) error.value = message(cause)
  } finally {
    if (current === session) loading.value = false
  }
}

function queryAudit() {
  const startDate = auditStart.value
  const endDate = auditEnd.value || startDate
  if (!startDate) {
    error.value = localMessage('errors.startDate')
    return
  }
  if (startDate > endDate) {
    error.value = localMessage('errors.dateOrder')
    return
  }
  const earliest = new Date()
  earliest.setUTCDate(earliest.getUTCDate() - 90)
  if (startDate < earliest.toISOString().slice(0, 10)) {
    error.value = localMessage('errors.startDateRange')
    return
  }
  if ((Date.parse(endDate) - Date.parse(startDate)) / 86400000 > 90) {
    error.value = localMessage('errors.dateRange')
    return
  }
  auditDates.value = { startDate, endDate }
  auditPage.value = 1
  auditCache.value = {}
  auditTokens.value = { 1: null }
  void loadAudit(1)
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
  auditCache.value = {}
  auditTokens.value = { 1: null }
  auditPage.value = 1
  if (!props.tenant) return
  if (props.action === 'volumes') void loadVolumes()
  if (props.action === 'quota') void loadQuotaRegions()
  if (props.action === 'audit') {
    const today = new Date().toISOString().slice(0, 10)
    auditStart.value = today
    auditEnd.value = today
    auditDates.value = { startDate: today, endDate: today }
    void loadAudit(1)
  }
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
          <div><dt>{{ t('tenantResources.account.subscriptionNumber') }}</dt><dd class="mono">{{ detail.subscriptionPlanNumber || '—' }}</dd></div>
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
        <el-alert v-if="error" :title="displayMessage(error)" type="error" :closable="false" show-icon />
        <el-table :data="volumes" v-loading="loading" max-height="380" row-key="id" class="resource-table" :empty-text="t('tenantResources.volume.empty')">
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
              <el-alert v-if="volumeError" :title="displayMessage(volumeError)" type="error" :closable="false" show-icon />
              <div class="editor-actions"><el-button :disabled="saving" @click="editingVolume = null">{{ t('tenantResources.cancel') }}</el-button><el-button type="primary" :loading="saving" native-type="submit">{{ t('tenantResources.saveChanges') }}</el-button></div>
            </el-form>
          </section>
        </Transition>
      </template>

      <template v-else-if="action === 'quota'">
        <el-form class="query-filters" label-position="top" :disabled="loading" @submit.prevent="queryQuota(0)">
          <el-form-item :label="t('tenantResources.quota.tenantRegion')" class="filter-grow">
            <el-select v-model="quotaTenantId" filterable :loading="regionsLoading" :disabled="regionsLoading" :placeholder="t('tenantResources.quota.regionPlaceholder')" @change="resetQuota">
              <el-option v-for="(region, index) in quotaRegions" :key="`${region.id}-${index}`" :value="String(region.id)" :label="`${region.tenancyName || region.userName || t('tenantResources.currentTenant')}${region.region ? ` · ${region.region}` : ''}`" />
            </el-select>
          </el-form-item>
          <el-form-item :label="t('tenantResources.quota.serviceType')" class="filter-grow">
            <el-select v-model="quotaService" @change="resetQuota">
              <el-option-group v-for="group in services" :key="group.group" :label="group.group"><el-option v-for="option in group.options" :key="option.value" v-bind="option" /></el-option-group>
            </el-select>
          </el-form-item>
          <el-form-item><el-button native-type="submit" type="primary" :loading="loading" :disabled="!quotaTenantId || regionsLoading">{{ t('tenantResources.quota.query') }}</el-button></el-form-item>
        </el-form>
        <el-alert v-if="regionsError" :title="t('tenantResources.errors.regionsFallback', { message: displayMessage(regionsError) })" type="warning" :closable="false" show-icon />
        <el-alert v-if="error" :title="displayMessage(error)" type="error" :closable="false" show-icon />
        <div v-loading="loading" class="resource-results" :aria-busy="loading">
          <template v-if="quota">
            <p class="result-caption" aria-live="polite">{{ t('tenantResources.quota.caption', { region: quota.region || '', service: queriedService, count: quotaRows.length }) }}</p>
            <el-table :data="quotaRows" max-height="390" class="resource-table" :empty-text="t('tenantResources.quota.empty')">
              <el-table-column prop="name" :label="t('tenantResources.quota.limitName')" min-width="245" show-overflow-tooltip />
              <el-table-column v-if="hasInstanceTypes" :label="t('tenantResources.quota.instanceType')" min-width="140"><template #default="{ row }"><span class="instance-type">{{ instanceType(row.name) || '—' }}</span></template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.total')" width="80" align="right"><template #default="{ row }">{{ row.total ?? 0 }}</template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.used')" width="80" align="right"><template #default="{ row }">{{ row.used ?? 0 }}</template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.available')" width="95" align="right"><template #default="{ row }"><span :class="Number(row.available || 0) <= 0 ? 'danger' : 'healthy'">{{ row.available ?? 0 }}</span></template></el-table-column>
              <el-table-column :label="t('tenantResources.quota.usage')" min-width="155"><template #default="{ row }"><div class="usage" :class="usageClass(row)"><span class="usage-track" role="progressbar" :aria-valuenow="usage(row)" :aria-valuemin="0" :aria-valuemax="100" :aria-label="t('tenantResources.quota.usageAria', { name: row.name })"><span :style="{ transform: `scaleX(${usage(row) / 100})` }" /></span><span>{{ usage(row) }}%</span></div></template></el-table-column>
            </el-table>
            <div class="resource-pagination">
              <label class="page-size">{{ t('tenantResources.quota.pageSize') }}<el-select v-model="quotaPageSize" :disabled="loading" :aria-label="t('tenantResources.quota.pageSizeAria')" @change="queryQuota(0)"><el-option v-for="size in [10, 20, 50]" :key="size" :value="size" :label="String(size)" /></el-select></label>
              <div class="page-controls"><el-button :disabled="loading || quotaPage === 0" @click="queryQuota(quotaPage - 1)">{{ t('tenantResources.previousPage') }}</el-button><span aria-live="polite">{{ t('tenantResources.pageNumber', { page: quotaPage + 1 }) }}</span><el-button :disabled="loading || !quota.hasNextPage" @click="queryQuota(quotaPage + 1)">{{ t('tenantResources.nextPage') }}</el-button></div>
            </div>
          </template>
          <el-empty v-else :description="loading ? t('tenantResources.quota.loading') : t('tenantResources.quota.selectPrompt')" :image-size="88" />
        </div>
      </template>

      <template v-else-if="action === 'audit'">
        <el-form class="query-filters" label-position="top" :disabled="loading" @submit.prevent="queryAudit">
          <el-form-item :label="t('tenantResources.audit.startDate')" class="filter-date"><el-date-picker v-model="auditStart" type="date" value-format="YYYY-MM-DD" format="YYYY-MM-DD" :placeholder="t('tenantResources.audit.startPlaceholder')" /></el-form-item>
          <el-form-item :label="t('tenantResources.audit.endDate')" class="filter-date"><el-date-picker v-model="auditEnd" type="date" value-format="YYYY-MM-DD" format="YYYY-MM-DD" :placeholder="t('tenantResources.audit.endPlaceholder')" /></el-form-item>
          <el-form-item><el-button native-type="submit" type="primary" :loading="loading">{{ t('tenantResources.audit.query') }}</el-button></el-form-item>
        </el-form>
        <el-alert v-if="error" :title="displayMessage(error)" type="error" :closable="false" show-icon />
        <p class="result-caption">{{ t('tenantResources.audit.dateRange', { start: auditDates.startDate, end: auditDates.endDate }) }}</p>
        <el-table :data="auditRows" v-loading="loading" max-height="420" class="resource-table" :empty-text="t('tenantResources.audit.empty')" :row-class-name="auditRowClass">
          <el-table-column :label="t('tenantResources.audit.index')" width="68"><template #default="{ $index }">{{ auditOffset + $index + 1 }}</template></el-table-column>
          <el-table-column prop="userName" :label="t('tenantResources.audit.username')" min-width="150" show-overflow-tooltip :formatter="auditCell" />
          <el-table-column prop="ipAddress" :label="t('tenantResources.audit.sourceIp')" min-width="180" show-overflow-tooltip :formatter="auditCell" />
          <el-table-column prop="eventType" :label="t('tenantResources.audit.eventType')" min-width="180" show-overflow-tooltip :formatter="auditCell" />
          <el-table-column prop="clientEnv" :label="t('tenantResources.audit.client')" min-width="150" show-overflow-tooltip :formatter="auditCell" />
          <el-table-column prop="eventTime" :label="t('tenantResources.audit.eventTime')" min-width="170" :formatter="auditCell" />
          <el-table-column :label="t('tenantResources.audit.response')" width="100"><template #default="{ row }"><span :class="row.responseStatus && String(row.responseStatus) !== '200' ? 'danger' : ''">{{ row.responseStatus || '—' }}</span></template></el-table-column>
        </el-table>
        <div class="resource-pagination">
          <span class="result-caption" aria-live="polite">{{ t(auditHasNext ? 'tenantResources.audit.loadedWithMore' : 'tenantResources.audit.loaded', { count: auditCount }) }}</span>
          <el-pagination :current-page="auditPage" :page-count="auditKnownPages" :pager-count="5" layout="prev, pager, next" :disabled="loading" @current-change="loadAudit" />
        </div>
        <p class="audit-note">{{ t('tenantResources.audit.note') }}</p>
      </template>
    </div>
    <template v-if="action === 'detail' || action === 'transferDetail'" #footer><el-button @click="close">{{ t('tenantResources.close') }}</el-button></template>
  </el-dialog>
</template>

<style scoped>
.resource-body { color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.tenant-resource-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); }
:global(.tenant-resource-dialog .el-button), :global(.tenant-resource-dialog .el-input__inner), :global(.tenant-resource-dialog .el-select__wrapper), :global(.tenant-resource-dialog .el-form-item__label), :global(.tenant-resource-dialog .el-checkbox__label), :global(.tenant-resource-dialog .el-radio__label), :global(.tenant-resource-dialog .el-table) { font-size: var(--font-size-body); }
:global(.tenant-resource-dialog .el-tag) { font-size: var(--font-size-caption); }
:global(.tenant-resource-dialog .el-alert__title) { font-size: var(--font-size-body); }
:global(.tenant-resource-dialog .el-alert__description), :global(.tenant-resource-dialog .el-form-item__error), :global(.tenant-resource-dialog .el-empty__description p) { font-size: var(--font-size-secondary); }
.resource-body :deep(.el-date-editor .el-range-input), .resource-body :deep(.el-date-editor .el-range-separator) { font-size: var(--font-size-body); }
.resource-context { margin: -4px 0 24px; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.account-details { margin: 0; }
.account-details > div { display: grid; grid-template-columns: 128px minmax(0, 1fr); gap: 20px; padding: 18px 0; border-bottom: 1px solid var(--border); }
.account-details > div:last-child { border-bottom: 0; }
.account-details dt { color: var(--text-secondary); }
.account-details dd { margin: 0; overflow-wrap: anywhere; }
.account-details .detail-feature { display: block; padding: 24px; margin-bottom: 6px; background: var(--bg-search); border: 0; border-radius: var(--r-card); }
.detail-feature dd { margin-top: 8px; font-size: var(--font-size-section); font-weight: 600; letter-spacing: -.022em; }
.mono { font-family: var(--mono); }
.transfer-summary { display: grid; gap: 12px; padding: 30px 0 38px; text-align: center; color: var(--text-secondary); }
.transfer-summary strong { font-size: 44px; font-weight: 600; color: var(--brand); font-variant-numeric: tabular-nums; }
.resource-toolbar, .query-filters, .resource-pagination, .page-controls, .page-size { display: flex; align-items: center; gap: 12px; }
.resource-toolbar { justify-content: space-between; flex-wrap: wrap; margin-bottom: 18px; color: var(--text-secondary); }
.query-filters { align-items: flex-end; flex-wrap: wrap; gap: 12px; }
.query-filters :deep(.el-form-item) { margin-bottom: 18px; }
.query-filters :deep(.el-form-item__label) { color: var(--text-secondary); }
.filter-grow { flex: 1 1 220px; }
.filter-date { flex: 1 1 210px; }
.filter-date :deep(.el-date-editor) { width: 100%; }
.resource-results { min-height: 230px; }
.resource-table { margin-top: 14px; border-radius: var(--r-sm); font-variant-numeric: tabular-nums; }
.resource-table :deep(.el-table__cell) { padding: 13px 0; }
.resource-table :deep(.audit-error-row) { --el-table-tr-bg-color: var(--status-danger-bg); }
.resource-pagination { flex-wrap: wrap; justify-content: space-between; margin-top: 18px; }
.page-size { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.page-size :deep(.el-select) { width: 75px; }
.page-controls { flex-wrap: wrap; }
.page-controls > span { color: var(--text-secondary); font-size: var(--font-size-secondary); white-space: nowrap; }
.result-caption { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.instance-type { font-size: var(--font-size-body); color: var(--text-secondary); }
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
.audit-note { margin: 14px 0 0; font-size: var(--font-size-secondary); color: var(--text-muted); }
.resource-reveal-enter-active, .resource-reveal-leave-active { transition: transform 320ms cubic-bezier(.22, 1, .36, 1), opacity 220ms ease; }
.resource-reveal-enter-from, .resource-reveal-leave-to { opacity: 0; transform: translateY(8px); }
@media (max-width: 600px) {
  .account-details > div { grid-template-columns: 1fr; gap: 7px; }
  .detail-feature dd { font-size: var(--font-size-section); }
  .resource-pagination { gap: 16px; }
  .volume-editor { padding: 18px; }
  .volume-editor :deep(.el-slider__input) { width: 100px; }
  .page-controls { gap: 8px; }
}
@media (prefers-reduced-motion: reduce) {
  .resource-reveal-enter-active, .resource-reveal-leave-active, .usage-track > span { transition: none; }
}
</style>
