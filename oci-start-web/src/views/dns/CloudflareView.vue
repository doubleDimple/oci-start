<script setup lang="ts">
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { computed, ref } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import { cloudflareCanEdit, type CloudflareApiError } from '@/api/cloudflare'
import CloudflareRecordDialog from './components/CloudflareRecordDialog.vue'
import CloudflareCredentialsDialog from './components/CloudflareCredentialsDialog.vue'
import { useCloudflarePage } from './useCloudflarePage'
import './cloudflare.scss'

const compact = useCompactViewport()
const { t, locale, te } = useI18n()
const route = useRoute()
const router = useRouter()
const credentialsOpen = ref(false)
const credentialsBusy = ref(false)
let credentialsChanged = false
const {
  zones, zonesLoading, zonesLoaded, zonesProblem, zoneId, selectedZone, zoneUnavailable,
  records, loading, loaded, readProblem, page, size, total, totalPages, searchName, searchContent, appliedFilters,
  loadZones, refresh, selectZone, applySearch, clearSearch, changePage, changeSize,
  operation, operationPending, operationOutcome, operationResult, operationProblem,
  openCreate, openEdit, openDelete, openSync, submitOperation, closeOperation,
  requiresReview, reviewZone, reviewReady, acknowledgeReview, contextLocked, canOperate,
} = useCloudflarePage(credentialsOpen)
const columns = ['type', 'name', 'content', 'ttl', 'proxy', 'actions'] as const
const pageSizes = [10, 20, 30, 50]
const emptyText = computed(() => {
  if (zoneUnavailable.value) return t('cloudflareDns.zoneMissing')
  if (!selectedZone.value) return t('cloudflareDns.noZone')
  if (loading.value) return t('cloudflareDns.loadingRecords')
  if (readProblem.value) return t('cloudflareDns.loadFailed')
  if (!loaded.value) return t('cloudflareDns.notLoaded')
  return t(appliedFilters.value.searchName || appliedFilters.value.searchContent ? 'cloudflareDns.noMatches' : 'cloudflareDns.empty')
})
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function text(value: string | null) { return value?.trim() ? value : '—' }
function problemText(problem: CloudflareApiError) { return t(`cloudflareDns.errors.${problem.key}`) }
function status(value: string) { const key = `cloudflareDns.statuses.${value}`; return te(key) ? t(key) : text(value) }
function ttl(value: number | null) {
  if (value == null) return '—'
  if (value === 1) return t('cloudflareDns.auto')
  if (value % 86400 === 0) return t('cloudflareDns.days', { count: number(value / 86400) })
  if (value % 3600 === 0) return t('cloudflareDns.hours', { count: number(value / 3600) })
  if (value % 60 === 0) return t('cloudflareDns.minutes', { count: number(value / 60) })
  return t('cloudflareDns.seconds', { count: number(value) })
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
function selectPageSize(value: unknown) {
  if (typeof value === 'number' && pageSizes.includes(value)) void changeSize(value)
}
onBeforeRouteLeave(() => !credentialsBusy.value)
onBeforeRouteUpdate(() => !credentialsBusy.value)
</script>

<template>
  <section class="cloudflare-page" :aria-label="t('cloudflareDns.title')">
    <header class="cloudflare-toolbar">
      <PageBackButton :disabled="operationPending || credentialsBusy" @click="back" />
      <div class="cloudflare-zone-picker">
        <label for="cloudflare-zone">{{ t('cloudflareDns.zone') }}</label>
        <el-select id="cloudflare-zone" :model-value="zoneId" filterable clearable :placeholder="t('cloudflareDns.selectZone')" :loading="zonesLoading" :disabled="contextLocked || zonesLoading" :no-data-text="t('cloudflareDns.noZones')" :no-match-text="t('cloudflareDns.noMatches')" :loading-text="t('cloudflareDns.loadingZones')" popper-class="cloudflare-zone-options" @update:model-value="selectZone">
          <el-option v-for="zone in zones" :key="zone.id" :value="zone.id" :label="`${zone.name} (${status(zone.status)})`" />
        </el-select>
      </div>
      <GhostBtn :loading="zonesLoading" :disabled="contextLocked" :title="t('cloudflareDns.refreshZones')" :aria-label="t('cloudflareDns.refreshZones')" @click="loadZones"><i class="i-mdi-refresh" aria-hidden="true" /></GhostBtn>
      <div class="cloudflare-toolbar-actions" data-page-error-anchor>
        <GhostBtn :disabled="contextLocked" @click="openCredentials"><i class="i-mdi-key-outline" aria-hidden="true" />{{ t('cloudflareDns.credentials.title') }}</GhostBtn>
        <GhostBtn :disabled="!canOperate" @click="openSync"><i class="i-mdi-sync" aria-hidden="true" />{{ t('cloudflareDns.sync') }}</GhostBtn>
        <GhostBtn :loading="loading" :disabled="contextLocked || !selectedZone" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('cloudflareDns.refreshRecords') }}</GhostBtn>
        <PrimaryBtn :disabled="!canOperate" @click="openCreate"><i class="i-mdi-plus" aria-hidden="true" />{{ t('cloudflareDns.add') }}</PrimaryBtn>
      </div>
    </header>
    <form class="cloudflare-filters" @submit.prevent="applySearch">
      <label class="cloudflare-search-field"><span>{{ t('cloudflareDns.searchName') }}</span><input v-model="searchName" type="search" :disabled="contextLocked || !selectedZone" autocomplete="off" :spellcheck="false" /></label>
      <label class="cloudflare-search-field"><span>{{ t('cloudflareDns.searchContent') }}</span><input v-model="searchContent" type="search" :disabled="contextLocked || !selectedZone" autocomplete="off" :spellcheck="false" /></label>
      <div class="cloudflare-filter-actions"><button type="submit" class="cloudflare-search-button" :disabled="contextLocked || loading || !selectedZone"><i class="i-mdi-magnify" aria-hidden="true" />{{ t('cloudflareDns.search') }}</button><GhostBtn :disabled="contextLocked || loading" @click="clearSearch"><i class="i-mdi-close" aria-hidden="true" />{{ t('cloudflareDns.clear') }}</GhostBtn></div>
    </form>

    <PageErrorNotice v-if="zonesProblem"><span>{{ problemText(zonesProblem) }} {{ zonesProblem.detail }} <span v-if="zonesLoaded">{{ t('cloudflareDns.retained') }}</span></span></PageErrorNotice>
    <div v-else-if="zonesLoaded && !zones.length" class="cloudflare-notice" role="status">{{ t('cloudflareDns.noZones') }}</div>
    <PageErrorNotice v-if="readProblem"><span>{{ problemText(readProblem) }} {{ readProblem.detail }} <span v-if="loaded">{{ t('cloudflareDns.retained') }}</span></span></PageErrorNotice>
    <div v-if="requiresReview && !operation" class="cloudflare-notice is-warning" role="alert"><span>{{ t('cloudflareDns.writeUnknown') }} <span v-if="reviewZone">{{ t('cloudflareDns.reviewTarget', { name: reviewZone.name }) }}</span> {{ t('cloudflareDns.recheckHint') }}</span><GhostBtn :loading="loading" :disabled="contextLocked || !selectedZone" @click="refresh">{{ t('cloudflareDns.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady || contextLocked" @click="acknowledgeReview">{{ t('cloudflareDns.reviewed') }}</GhostBtn></div>

    <div class="cloudflare-body" :aria-busy="loading || zonesLoading">
      <div class="cloudflare-table-wrap">
        <MobileRecordList v-if="compact" drilldown :list-id="`cloudflare-${zoneId}`" :record-keys="records.map(record => record.id)" :loading="loading">
          <MobileRecordCard v-for="record in records" :key="record.id" :record-key="record.id" :summary-title="text(record.name)" :summary-meta="`${text(record.type)} · ${text(record.content)}`" :summary-status="t(record.proxied === true ? 'cloudflareDns.proxied' : record.proxied === false ? 'cloudflareDns.dnsOnly' : 'cloudflareDns.unknown')" :summary-tone="record.proxied === true ? 'success' : 'neutral'">
            <template #identity><h3 class="mobile-record-title">{{ text(record.name) }}</h3></template>
            <dl class="mobile-record-fields">
              <div class="mobile-record-wide"><dt>{{ t('cloudflareDns.type') }}</dt><dd><span class="cloudflare-type">{{ text(record.type) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('cloudflareDns.name') }}</dt><dd><span class="cloudflare-truncate" :title="text(record.name)">{{ text(record.name) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('cloudflareDns.content') }}</dt><dd><span class="cloudflare-truncate" :title="text(record.content)">{{ text(record.content) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('cloudflareDns.ttl') }}</dt><dd><span class="cloudflare-truncate" :title="ttl(record.ttl)">{{ ttl(record.ttl) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('cloudflareDns.proxy') }}</dt><dd><span :class="{ 'cloudflare-proxied': record.proxied === true }">{{ t(record.proxied === true ? 'cloudflareDns.proxied' : record.proxied === false ? 'cloudflareDns.dnsOnly' : 'cloudflareDns.unknown') }}</span></dd></div>
            </dl>
            <template #footer><div class="cloudflare-row-actions"><GhostBtn :disabled="!canOperate || !cloudflareCanEdit(record.type)" :title="!cloudflareCanEdit(record.type) ? t('cloudflareDns.errors.unsupportedType') : undefined" :aria-label="`${t('cloudflareDns.edit')} ${record.name}`" @click="openEdit(record)"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('cloudflareDns.edit') }}</GhostBtn><GhostBtn danger :disabled="!canOperate" :aria-label="`${t('cloudflareDns.delete')} ${record.name}`" @click="openDelete(record)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('cloudflareDns.delete') }}</GhostBtn></div></template>
          </MobileRecordCard>
        </MobileRecordList>
        <table v-else class="cloudflare-table" :aria-label="t('cloudflareDns.title')">
          <thead><tr><th v-for="column in columns" :key="column" scope="col">{{ t(`cloudflareDns.${column}`) }}</th></tr></thead>
          <tbody>
            <tr v-for="record in records" :key="record.id">
              <td><span class="cloudflare-type">{{ text(record.type) }}</span></td>
              <td><span class="cloudflare-truncate" :title="text(record.name)">{{ text(record.name) }}</span></td>
              <td><span class="cloudflare-truncate" :title="text(record.content)">{{ text(record.content) }}</span></td>
              <td><span class="cloudflare-truncate" :title="ttl(record.ttl)">{{ ttl(record.ttl) }}</span></td>
              <td><span :class="{ 'cloudflare-proxied': record.proxied === true }">{{ t(record.proxied === true ? 'cloudflareDns.proxied' : record.proxied === false ? 'cloudflareDns.dnsOnly' : 'cloudflareDns.unknown') }}</span></td>
              <td><div class="cloudflare-row-actions"><GhostBtn :disabled="!canOperate || !cloudflareCanEdit(record.type)" :title="!cloudflareCanEdit(record.type) ? t('cloudflareDns.errors.unsupportedType') : undefined" :aria-label="`${t('cloudflareDns.edit')} ${record.name}`" @click="openEdit(record)"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('cloudflareDns.edit') }}</GhostBtn><GhostBtn danger :disabled="!canOperate" :aria-label="`${t('cloudflareDns.delete')} ${record.name}`" @click="openDelete(record)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('cloudflareDns.delete') }}</GhostBtn></div></td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-if="!records.length" class="cloudflare-empty" role="status"><i class="i-mdi-dns-outline" aria-hidden="true" /><p>{{ emptyText }}</p><GhostBtn v-if="readProblem && selectedZone" :loading="loading" :disabled="contextLocked" @click="refresh">{{ t('cloudflareDns.refreshRecords') }}</GhostBtn></div>
    </div>

    <PagePagination :current-page="page" :page-size="size" :page-count="Math.max(1, totalPages)" :page-sizes="pageSizes" :disabled="contextLocked || loading || !selectedZone" @current-change="changePage" @size-change="selectPageSize">
      <span>{{ loaded ? t('cloudflareDns.count', { count: number(total) }) : t('cloudflareDns.notLoaded') }}</span>
    </PagePagination>

    <CloudflareRecordDialog v-if="operation" :operation="operation" :pending="operationPending" :outcome="operationOutcome" :result="operationResult" :problem="operationProblem" :read-problem="readProblem" @submit="submitOperation" @close="closeOperation" />
    <CloudflareCredentialsDialog v-if="credentialsOpen" @close="closeCredentials" @changed="markCredentialsChanged" @busy="setCredentialsBusy" />
  </section>
</template>

<style scoped>
.mobile-record-fields .cloudflare-truncate, .mobile-record-fields .cloudflare-ellipsis { max-width: 100%; white-space: normal; overflow-wrap: anywhere; }
.mobile-record-card .cloudflare-row-actions { flex-wrap: wrap; }
</style>
