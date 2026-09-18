<script setup lang="ts">
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { computed, ref, shallowRef } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import { edgeOneCanEdit, type EdgeOneApiError, type EdgeOneRecord, type EdgeOneZone } from '@/api/edgeone'
import EdgeOneRecordDialog from './components/EdgeOneRecordDialog.vue'
import EdgeOneCredentialsDialog from './components/EdgeOneCredentialsDialog.vue'
import { useEdgeOnePage } from './useEdgeOnePage'
import './edgeone.scss'

const compact = useCompactViewport()
const { t, locale, te } = useI18n()
const route = useRoute()
const router = useRouter()
const credentialsOpen = ref(false)
const credentialsBusy = ref(false)
const details = shallowRef<{ zone: EdgeOneZone; record: EdgeOneRecord } | null>(null)
const readDialogOpen = computed(() => credentialsOpen.value || !!details.value)
let credentialsChanged = false
const {
  zones, zonesLoading, zonesLoaded, zonesProblem, zoneId, selectedZone, zoneUnavailable,
  mode, selectMode, records, loading, loaded, readProblem, page, size, total,
  searchName, searchContent, searchStatus, appliedFilters,
  loadZones, refresh, selectZone, applySearch, clearSearch, changePage, changeSize,
  operation, operationPending, operationOutcome, operationResult, operationProblem,
  openEdit, openDelete, openSync, submitOperation, closeOperation,
  requiresReview, reviewZone, reviewMode, reviewReady, acknowledgeReview, contextLocked, canOperate,
} = useEdgeOnePage(readDialogOpen)
const pageSizes = [10, 20, 30, 50]
const domainStatuses = ['online', 'offline', 'pending']
const columns = computed(() => mode.value === 'dns'
  ? ['type', 'name', 'content', 'ttl', 'priority', 'actions']
  : ['name', 'status', 'cname', 'originProtocol', 'actions'])
const emptyText = computed(() => {
  if (zoneUnavailable.value) return t('edgeoneDns.zoneMissing')
  if (!selectedZone.value) return t('edgeoneDns.noZone')
  if (loading.value) return t('edgeoneDns.loadingRecords')
  if (readProblem.value) return t('edgeoneDns.loadFailed')
  if (!loaded.value) return t('edgeoneDns.notLoaded')
  const filters = appliedFilters.value
  return t(filters.searchName || filters.searchContent || filters.searchStatus ? 'edgeoneDns.noMatches'
    : mode.value === 'domain' ? 'edgeoneDns.emptyDomains' : 'edgeoneDns.empty')
})
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function text(value: string | null) { return value?.trim() ? value : '—' }
function problemText(problem: EdgeOneApiError) { return t(`edgeoneDns.errors.${problem.key}`) }
function status(value: string) {
  const key = `edgeoneDns.statuses.${value}`
  return value ? (te(key) ? t(key) : value) : t('edgeoneDns.unknown')
}
function protocol(value: string | null) {
  if (!value) return '—'
  if (value.toLowerCase() === 'follow') return t('edgeoneDns.follow')
  return /^(http|https)$/i.test(value) ? value.toUpperCase() : value
}
function ttl(value: number | null) {
  if (value == null) return '—'
  if (value % 86400 === 0) return t('edgeoneDns.days', { count: number(value / 86400) })
  if (value % 3600 === 0) return t('edgeoneDns.hours', { count: number(value / 3600) })
  if (value % 60 === 0) return t('edgeoneDns.minutes', { count: number(value / 60) })
  return t('edgeoneDns.seconds', { count: number(value) })
}
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/oci/list')
}
function openCredentials() {
  if (contextLocked.value) return
  credentialsChanged = false
  credentialsOpen.value = true
}
function markCredentialsChanged() { credentialsChanged = true }
function setCredentialsBusy(value: boolean) { credentialsBusy.value = value }
async function closeCredentials() {
  if (credentialsBusy.value) return
  credentialsOpen.value = false
  if (credentialsChanged) {
    credentialsChanged = false
    await loadZones()
  }
}
function openDetails(record: EdgeOneRecord) {
  if (contextLocked.value || loading.value || mode.value !== 'domain' || !selectedZone.value) return
  const current = records.value.find(row => row.id === record.id)
  if (current) details.value = { zone: { ...selectedZone.value }, record: { ...current } }
}
function closeDetails() { details.value = null }
function detailsVisibility(value: boolean) { if (!value) closeDetails() }
function selectPageSize(value: unknown) {
  if (typeof value === 'number' && pageSizes.includes(value)) changeSize(value)
}
onBeforeRouteLeave(() => !credentialsBusy.value)
onBeforeRouteUpdate(() => !credentialsBusy.value)
</script>

<template>
  <section class="edgeone-page" :aria-label="t('edgeoneDns.title')">
    <header class="edgeone-toolbar">
      <PageBackButton :disabled="operationPending || credentialsBusy" @click="back" />
      <div class="edgeone-zone-picker">
        <label for="edgeone-zone">{{ t('edgeoneDns.zone') }}</label>
        <el-select id="edgeone-zone" :model-value="zoneId" filterable clearable :placeholder="t('edgeoneDns.selectZone')" :loading="zonesLoading" :disabled="contextLocked || zonesLoading" :no-data-text="t('edgeoneDns.noZones')" :no-match-text="t('edgeoneDns.noMatches')" :loading-text="t('edgeoneDns.loadingZones')" popper-class="edgeone-zone-options" @update:model-value="selectZone">
          <el-option v-for="zone in zones" :key="zone.id" :value="zone.id" :label="`${zone.name} (${status(zone.status)})`" />
        </el-select>
      </div>
      <GhostBtn :loading="zonesLoading" :disabled="contextLocked" :title="t('edgeoneDns.refreshZones')" :aria-label="t('edgeoneDns.refreshZones')" @click="loadZones"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn>
      <div class="edgeone-toolbar-actions" data-page-error-anchor>
        <GhostBtn :disabled="contextLocked" @click="openCredentials"><i class="i-mdi-key-outline" aria-hidden="true" />{{ t('edgeoneDns.credentials.title') }}</GhostBtn>
        <GhostBtn :loading="loading" :disabled="contextLocked || !selectedZone" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('edgeoneDns.refreshRecords') }}</GhostBtn>
        <PrimaryBtn :disabled="!canOperate" @click="openSync"><i class="i-mdi-sync" aria-hidden="true" />{{ t('edgeoneDns.sync') }}</PrimaryBtn>
      </div>
    </header>
    <div class="edgeone-mode-switch" role="group" :aria-label="t('edgeoneDns.recordMode')">
      <button type="button" :aria-pressed="mode === 'dns'" :disabled="contextLocked" @click="selectMode('dns')"><i class="i-mdi-dns-outline" aria-hidden="true" />{{ t('edgeoneDns.dns') }}</button>
      <button type="button" :aria-pressed="mode === 'domain'" :disabled="contextLocked" @click="selectMode('domain')"><i class="i-mdi-web" aria-hidden="true" />{{ t('edgeoneDns.domain') }}</button>
    </div>
    <form class="edgeone-filters" @submit.prevent="applySearch">
      <label class="edgeone-search-field"><span>{{ t(mode === 'dns' ? 'edgeoneDns.searchName' : 'edgeoneDns.searchDomainName') }}</span><input v-model="searchName" type="search" :disabled="contextLocked || !selectedZone" autocomplete="off" :spellcheck="false" /></label>
      <label v-if="mode === 'dns'" class="edgeone-search-field"><span>{{ t('edgeoneDns.searchContent') }}</span><input v-model="searchContent" type="search" :disabled="contextLocked || !selectedZone" autocomplete="off" :spellcheck="false" /></label>
      <div v-else class="edgeone-search-field"><label for="edgeone-search-status">{{ t('edgeoneDns.searchStatus') }}</label><el-select id="edgeone-search-status" v-model="searchStatus" class="edgeone-select" :empty-values="[null, undefined]" :placeholder="t('edgeoneDns.allStatuses')" :disabled="contextLocked || !selectedZone"><el-option value="" :label="t('edgeoneDns.allStatuses')" /><el-option v-if="searchStatus && !domainStatuses.includes(searchStatus)" :value="searchStatus" :label="status(searchStatus)" /><el-option v-for="value in domainStatuses" :key="value" :value="value" :label="status(value)" /></el-select></div>
      <div class="edgeone-filter-actions"><button type="submit" class="edgeone-search-button" :disabled="contextLocked || loading || !selectedZone"><i class="i-mdi-magnify" aria-hidden="true" />{{ t('edgeoneDns.search') }}</button><GhostBtn :disabled="contextLocked || loading" @click="clearSearch"><i class="i-mdi-close" aria-hidden="true" />{{ t('edgeoneDns.clear') }}</GhostBtn></div>
    </form>

    <PageErrorNotice v-if="zonesProblem"><span>{{ problemText(zonesProblem) }} {{ zonesProblem.detail }} <span v-if="zonesLoaded">{{ t('edgeoneDns.retained') }}</span></span></PageErrorNotice>
    <div v-else-if="zonesLoaded && !zones.length" class="edgeone-notice" role="status">{{ t('edgeoneDns.noZones') }}</div>
    <PageErrorNotice v-if="readProblem"><span>{{ problemText(readProblem) }} {{ readProblem.detail }} <span v-if="loaded">{{ t('edgeoneDns.retained') }}</span></span></PageErrorNotice>
    <div v-if="requiresReview && !operation" class="edgeone-notice is-warning" role="alert"><span>{{ t('edgeoneDns.writeUnknown') }} <span v-if="reviewZone">{{ t('edgeoneDns.reviewTarget', { name: reviewZone.name, mode: t(`edgeoneDns.${reviewMode}`) }) }}</span> {{ t('edgeoneDns.recheckHint') }}</span><GhostBtn :loading="loading" :disabled="contextLocked || !selectedZone" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('edgeoneDns.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady || contextLocked" @click="acknowledgeReview"><i class="i-mdi-check" aria-hidden="true" />{{ t('edgeoneDns.reviewed') }}</GhostBtn></div>

    <div class="edgeone-body" :aria-busy="loading || zonesLoading">
      <div class="edgeone-table-wrap">
        <MobileRecordList v-if="compact" drilldown :list-id="`edgeone-${zoneId}-${mode}`" :record-keys="records.map(record => record.id)" :loading="loading">
          <MobileRecordCard v-for="record in records" :key="record.id" :record-key="record.id" :summary-title="text(record.name)" :summary-meta="text(record.content)" :summary-status="mode === 'dns' ? text(record.type) : status(record.status)">
            <template #identity><h3 class="mobile-record-title">{{ text(record.name) }}</h3></template>
            <dl class="mobile-record-fields"><template v-if="mode === 'dns'"><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.type') }}</dt><dd><span class="edgeone-type">{{ text(record.type) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.name') }}</dt><dd><span class="edgeone-truncate" :title="text(record.name)">{{ text(record.name) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.content') }}</dt><dd><span class="edgeone-truncate" :title="text(record.content)">{{ text(record.content) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.ttl') }}</dt><dd><span class="edgeone-truncate" :title="ttl(record.ttl)">{{ ttl(record.ttl) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.priority') }}</dt><dd>{{ record.priority == null ? '—' : number(record.priority) }}</dd></div></template><template v-else><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.name') }}</dt><dd><span class="edgeone-truncate" :title="text(record.name)">{{ text(record.name) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.status') }}</dt><dd><span class="edgeone-truncate" :title="status(record.status)">{{ status(record.status) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.cname') }}</dt><dd><span class="edgeone-truncate" :title="text(record.content)">{{ text(record.content) }}</span></dd></div><div class="mobile-record-wide"><dt>{{ t('edgeoneDns.originProtocol') }}</dt><dd><span class="edgeone-truncate" :title="protocol(record.originProtocol)">{{ protocol(record.originProtocol) }}</span></dd></div></template></dl>
            <template #footer><div class="edgeone-row-actions">
                <GhostBtn v-if="mode === 'dns'" :disabled="!canOperate || !edgeOneCanEdit(record.type)" :title="!edgeOneCanEdit(record.type) ? t('edgeoneDns.errors.unsupportedType') : undefined" :aria-label="`${t('edgeoneDns.edit')} ${record.name}`" @click="openEdit(record)"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('edgeoneDns.edit') }}</GhostBtn>
                <GhostBtn v-else :disabled="contextLocked || loading" :aria-label="`${t('edgeoneDns.details')} ${record.name}`" @click="openDetails(record)"><i class="i-mdi-information-outline" aria-hidden="true" />{{ t('edgeoneDns.details') }}</GhostBtn>
                <GhostBtn danger :disabled="!canOperate" :aria-label="`${t('edgeoneDns.delete')} ${record.name}`" @click="openDelete(record)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('edgeoneDns.delete') }}</GhostBtn>
              </div></template>
          </MobileRecordCard>
        </MobileRecordList>
        <table v-else class="edgeone-table" :class="{ 'is-domain': mode === 'domain' }" :aria-label="t(`edgeoneDns.${mode}`)">
          <thead><tr><th v-for="column in columns" :key="column" scope="col">{{ t(`edgeoneDns.${column}`) }}</th></tr></thead>
          <tbody>
            <tr v-for="record in records" :key="record.id">
              <template v-if="mode === 'dns'">
                <td><span class="edgeone-type">{{ text(record.type) }}</span></td>
                <td><span class="edgeone-truncate" :title="text(record.name)">{{ text(record.name) }}</span></td>
                <td><span class="edgeone-truncate" :title="text(record.content)">{{ text(record.content) }}</span></td>
                <td><span class="edgeone-truncate" :title="ttl(record.ttl)">{{ ttl(record.ttl) }}</span></td>
                <td>{{ record.priority == null ? '—' : number(record.priority) }}</td>
              </template>
              <template v-else>
                <td><span class="edgeone-truncate" :title="text(record.name)">{{ text(record.name) }}</span></td>
                <td><span class="edgeone-truncate" :title="status(record.status)">{{ status(record.status) }}</span></td>
                <td><span class="edgeone-truncate" :title="text(record.content)">{{ text(record.content) }}</span></td>
                <td><span class="edgeone-truncate" :title="protocol(record.originProtocol)">{{ protocol(record.originProtocol) }}</span></td>
              </template>
              <td><div class="edgeone-row-actions">
                <GhostBtn v-if="mode === 'dns'" :disabled="!canOperate || !edgeOneCanEdit(record.type)" :title="!edgeOneCanEdit(record.type) ? t('edgeoneDns.errors.unsupportedType') : undefined" :aria-label="`${t('edgeoneDns.edit')} ${record.name}`" @click="openEdit(record)"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('edgeoneDns.edit') }}</GhostBtn>
                <GhostBtn v-else :disabled="contextLocked || loading" :aria-label="`${t('edgeoneDns.details')} ${record.name}`" @click="openDetails(record)"><i class="i-mdi-information-outline" aria-hidden="true" />{{ t('edgeoneDns.details') }}</GhostBtn>
                <GhostBtn danger :disabled="!canOperate" :aria-label="`${t('edgeoneDns.delete')} ${record.name}`" @click="openDelete(record)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('edgeoneDns.delete') }}</GhostBtn>
              </div></td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-if="!records.length" class="edgeone-empty" role="status"><i class="i-mdi-dns-outline" aria-hidden="true" /><p>{{ emptyText }}</p><GhostBtn v-if="readProblem && selectedZone" :loading="loading" :disabled="contextLocked" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('edgeoneDns.refreshRecords') }}</GhostBtn></div>
    </div>

    <PagePagination :current-page="page" :page-size="size" :total="total" :page-sizes="pageSizes" :disabled="contextLocked || loading || !loaded" @current-change="changePage" @size-change="selectPageSize">
      <span>{{ loaded ? t('edgeoneDns.count', { count: number(total) }) : t('edgeoneDns.notLoaded') }}</span>
    </PagePagination>

    <EdgeOneRecordDialog v-if="operation" :operation="operation" :pending="operationPending" :outcome="operationOutcome" :result="operationResult" :problem="operationProblem" :read-problem="readProblem" @submit="submitOperation" @close="closeOperation" />
    <EdgeOneCredentialsDialog v-if="credentialsOpen" @close="closeCredentials" @changed="markCredentialsChanged" @busy="setCredentialsBusy" />
    <el-dialog v-if="details" :model-value="true" :title="t('edgeoneDns.detailsTitle')" width="620px" class="edgeone-detail-dialog" append-to-body :close-on-click-modal="false" :before-close="closeDetails" @update:model-value="detailsVisibility">
      <dl class="edgeone-details">
        <div><dt>{{ t('edgeoneDns.zone') }}</dt><dd>{{ details.zone.name }}</dd></div>
        <div><dt>{{ t('edgeoneDns.name') }}</dt><dd>{{ details.record.name }}</dd></div>
        <div><dt>{{ t('edgeoneDns.id') }}</dt><dd>{{ details.record.id }}</dd></div>
        <div><dt>{{ t('edgeoneDns.status') }}</dt><dd>{{ status(details.record.status) }}</dd></div>
        <div><dt>{{ t('edgeoneDns.cname') }}</dt><dd>{{ text(details.record.content) }}</dd></div>
        <div><dt>{{ t('edgeoneDns.originProtocol') }}</dt><dd>{{ protocol(details.record.originProtocol) }}</dd></div>
      </dl>
      <p class="edgeone-operation-hint">{{ t('edgeoneDns.domainDetailsHint') }}</p>
      <template #footer><GhostBtn @click="closeDetails">{{ t('edgeoneDns.close') }}</GhostBtn></template>
    </el-dialog>
  </section>
</template>

<style scoped>
.mobile-record-fields .edgeone-truncate, .mobile-record-fields .edgeone-ellipsis { max-width: 100%; white-space: normal; overflow-wrap: anywhere; }
.mobile-record-card .edgeone-row-actions { flex-wrap: wrap; }
</style>
