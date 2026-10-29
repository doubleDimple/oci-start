<script setup lang="ts">
import { ElTableColumn as BaseTableColumn } from 'element-plus'
import { computed, defineAsyncComponent, nextTick, onMounted, onUnmounted, ref, shallowRef, watch } from 'vue'
import type { TableInstance } from 'element-plus'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { fetchMyRegions } from '@/api/resource'
import { REGION_COORDINATES, getContinent, regionCityName } from './regionCoords'
import type { RegionGlobePoint } from './globeTypes'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'

interface RegionRow {
  regionCode: string
  name: string
  isMine: boolean
  continent: string
  coordinates?: { lat: number; lng: number }
}
const PAGE_SIZE = 10
const { t, locale } = useI18n()
const route = useRoute(), router = useRouter(), compact = useCompactViewport()
const search = ref(typeof route.query.regionSearch === 'string' ? route.query.regionSearch : '')
const continent = ref(readContinent())
const status = ref(readStatus())
const page = ref(readPage())
const loading = ref(false), loaded = ref(false), failed = ref(false)
const lastUpdate = ref<Date | null>(null)
const ownedRegions = ref<string[]>([])
const regionNames = ref<Record<string, string>>({})
const mapVisible = ref(!compact.value), pageActive = ref(true)
const selectedRegion = ref<string | null>(null)
const table = ref<TableInstance>(), tableArea = ref<HTMLElement>()
const globeLoading = ref(false), globeLoadFailed = ref(false)
let disposed = false
let controller: AbortController | null = null
let refreshTimer: number | undefined

const continentKeys = ['all', 'asia', 'europe', 'america-north', 'america-south', 'middle-east', 'other']
function readContinent() {
  const value = route.query.regionContinent
  return typeof value === 'string' && ['asia', 'europe', 'america-north', 'america-south', 'middle-east', 'other'].includes(value) ? value : 'all'
}
function readStatus() { return route.query.regionStatus === 'linked' || route.query.regionStatus === 'unlinked' ? route.query.regionStatus : 'all' }
function readPage() { const value = Number(route.query.regionPage); return Number.isSafeInteger(value) && value > 0 ? value : 1 }
function createGlobeComponent() {
  return defineAsyncComponent({ loader: async () => {
    globeLoading.value = true
    try { return (await import('./components/RegionGlobe.vue')).default }
    catch { if (!disposed) globeLoadFailed.value = true; return { render: () => null } }
    finally { if (!disposed) globeLoading.value = false }
  } })
}
const globeComponent = shallowRef(createGlobeComponent())
function retryGlobe() { globeLoadFailed.value = false; globeComponent.value = createGlobeComponent() }
const ownedCodes = computed(() => new Set(ownedRegions.value))
const allRows = computed<RegionRow[]>(() => [...new Set([...Object.keys(REGION_COORDINATES), ...Object.keys(regionNames.value), ...ownedCodes.value])].sort().map(regionCode => ({
  regionCode, name: locale.value.startsWith('zh') && regionNames.value[regionCode] || regionCityName(regionCode, locale.value),
  isMine: ownedCodes.value.has(regionCode), continent: getContinent(regionCode) || 'other', coordinates: REGION_COORDINATES[regionCode],
})))
const filteredRows = computed(() => {
  const term = search.value.trim().toLowerCase()
  return allRows.value.filter(row => (!term || row.regionCode.toLowerCase().includes(term) || row.name.toLowerCase().includes(term))
    && (continent.value === 'all' || row.continent === continent.value)
    && (status.value === 'all' || loaded.value && row.isMine === (status.value === 'linked')))
})
const pagedRows = computed(() => filteredRows.value.slice((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE))
const mapRegions = computed<RegionGlobePoint[]>(() => allRows.value.filter(row => row.isMine && row.coordinates)
  .map(row => ({ regionCode: row.regionCode, name: row.name, ...row.coordinates! })))
const mapRegionCodes = computed(() => new Set(mapRegions.value.map(row => row.regionCode)))
const unmappedCount = computed(() => allRows.value.filter(row => row.isMine && !row.coordinates).length)
const updatedText = computed(() => lastUpdate.value ? t('regionPage.updatedAt', { time: new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'medium' }).format(lastUpdate.value) }) : t('regionPage.notUpdated'))

async function loadRegions() {
  if (loading.value || disposed) return
  loading.value = true; failed.value = false
  controller?.abort(); controller = new AbortController()
  try {
    const response = await fetchMyRegions({ signal: controller.signal, timeout: 30000 })
    const payload = response?.data ?? response
    if (!payload || !Array.isArray(payload.hasRecords) || payload.hasRecords.some((row: unknown) => !row || typeof row !== 'object' || !('region' in row) || typeof row.region !== 'string' || !row.region.trim())) throw new Error('Invalid region data')
    if (disposed) return
    ownedRegions.value = [...new Set<string>(payload.hasRecords.map((row: { region: string }) => row.region.trim()))]
    const names: Record<string, string> = {}
    if (payload.regionMap && typeof payload.regionMap === 'object' && !Array.isArray(payload.regionMap)) {
      for (const [code, name] of Object.entries(payload.regionMap)) if (typeof name === 'string') names[code] = name
    }
    regionNames.value = names
    loaded.value = true; lastUpdate.value = new Date()
  } catch { if (!disposed) failed.value = true }
  finally { if (!disposed) loading.value = false }
}
async function selectRegion(code: string | null) {
  selectedRegion.value = code
  if (!code) return
  if (!filteredRows.value.some(row => row.regionCode === code)) { search.value = ''; continent.value = 'all'; status.value = 'all' }
  await nextTick()
  if (disposed || selectedRegion.value !== code) return
  const index = filteredRows.value.findIndex(row => row.regionCode === code)
  if (index >= 0) page.value = Math.floor(index / PAGE_SIZE) + 1
}
async function locateRegion(code: string) {
  if (!mapRegionCodes.value.has(code)) return
  mapVisible.value = true
  if (selectedRegion.value === code) { selectedRegion.value = null; await nextTick() }
  if (!disposed) await selectRegion(code)
}
function locationHint(row: RegionRow) {
  return t(!row.coordinates ? 'regionPage.unmappedRegion' : row.isMine ? 'regionPage.locateRegion' : 'regionPage.untrackedRegion', { region: row.name })
}
async function scrollToSelection() {
  await nextTick()
  if (disposed) return
  const container = compact.value ? tableArea.value : tableArea.value?.querySelector<HTMLElement>('.el-table__body-wrapper .el-scrollbar__wrap')
  const row = tableArea.value?.querySelector<HTMLElement>('[data-selected="true"]')
  if (!container || !row) return
  const item = row.closest('tr') || row, rect = item.getBoundingClientRect(), bounds = container.getBoundingClientRect()
  if (rect.top < bounds.top) container.scrollTop += rect.top - bounds.top
  else if (rect.bottom > bounds.bottom) container.scrollTop += rect.bottom - bounds.bottom
}
function rowClassName({ row }: { row: RegionRow }) { return row.regionCode === selectedRegion.value ? 'region-selected-row' : '' }
function updateVisibility() { pageActive.value = document.visibilityState !== 'hidden' }
watch([search, continent, status], () => { page.value = 1 }, { flush: 'sync' })
watch(filteredRows, rows => { page.value = Math.max(1, Math.min(page.value, Math.ceil(rows.length / PAGE_SIZE))) })
watch(() => [route.query.regionSearch, route.query.regionContinent, route.query.regionStatus, route.query.regionPage], () => {
  search.value = typeof route.query.regionSearch === 'string' ? route.query.regionSearch : ''
  continent.value = readContinent(); status.value = readStatus(); page.value = readPage()
})
watch([search, continent, status, page], () => {
  if (!compact.value) return
  const state = { regionSearch: search.value || undefined, regionContinent: continent.value === 'all' ? undefined : continent.value,
    regionStatus: status.value === 'all' ? undefined : status.value, regionPage: page.value > 1 ? String(page.value) : undefined }
  if (!Object.entries(state).every(([key, value]) => route.query[key] === value)) void router.replace({ query: { ...route.query, ...state, mobileRecord: undefined }, hash: route.hash })
}, { flush: 'post' })
watch(mapRegionCodes, codes => { if (selectedRegion.value && !codes.has(selectedRegion.value)) selectedRegion.value = null })
watch([page, selectedRegion], () => { void scrollToSelection() })
onMounted(() => {
  updateVisibility(); document.addEventListener('visibilitychange', updateVisibility)
  void loadRegions()
  refreshTimer = window.setInterval(() => { if (pageActive.value) void loadRegions() }, 5 * 60 * 1000)
})
onUnmounted(() => { disposed = true; controller?.abort(); window.clearInterval(refreshTimer); document.removeEventListener('visibilitychange', updateVisibility) })
const ElTableColumn = BaseTableColumn<RegionRow>
</script>

<template>
  <div class="region-page">
    <section class="region-card" :aria-label="t('regionPage.title')">
      <div class="region-toolbar">
        <el-input v-model="search" class="region-search" :placeholder="t('regionPage.search')" :aria-label="t('regionPage.search')" clearable><template #prefix><span class="i-mdi-magnify" aria-hidden="true" /></template></el-input>
        <el-select v-model="continent" class="continent-filter" :aria-label="t('regionPage.continentFilter')"><el-option v-for="key in continentKeys" :key="key" :value="key" :label="t(`regionPage.continents.${key}`)" /></el-select>
        <el-select v-model="status" class="status-filter" :aria-label="t('regionPage.statusFilter')"><el-option v-for="key in ['all', 'linked', 'unlinked']" :key="key" :value="key" :label="t(`regionPage.statuses.${key}`)" /></el-select>
        <div class="region-toolbar-actions" data-page-error-anchor>
          <GhostBtn :loading="loading" :aria-label="t('regionPage.refresh')" @click="loadRegions"><span class="i-mdi-refresh" aria-hidden="true" /><span class="toolbar-button-label">{{ t('regionPage.refresh') }}</span></GhostBtn>
          <GhostBtn :aria-label="t(mapVisible ? 'regionPage.mapHide' : 'regionPage.mapShow')" :aria-expanded="mapVisible" aria-controls="region-globe-panel" @click="mapVisible = !mapVisible"><span class="i-mdi-earth" aria-hidden="true" /><span class="toolbar-button-label">{{ t(mapVisible ? 'regionPage.mapHide' : 'regionPage.mapShow') }}</span></GhostBtn>
        </div>
      </div>
      <PageErrorNotice v-if="failed">{{ t('regionPage.loadFailed') }}<GhostBtn :loading="loading" @click="loadRegions">{{ t('regionPage.retry') }}</GhostBtn></PageErrorNotice>
      <div class="region-workspace" :class="{ 'map-collapsed': !mapVisible }">
        <aside id="region-globe-panel" v-show="mapVisible" class="globe-pane" :aria-label="t('regionPage.globeLabel')">
          <div class="globe-toolbar"><span class="globe-count">{{ t('regionPage.linkedRegions') }} {{ loaded ? ownedCodes.size : '—' }}</span><span class="globe-count">{{ t('regionPage.mapCount', { count: mapRegions.length }) }}</span><p v-if="unmappedCount" class="globe-filter-note" role="status">{{ t('regionPage.unmappedCount', { count: unmappedCount }) }}</p></div>
          <div class="globe-stage" :aria-busy="globeLoading || loading">
            <PageErrorNotice v-if="globeLoadFailed && mapVisible">{{ t('regionPage.globeLoadFailed') }}<GhostBtn @click="retryGlobe">{{ t('regionPage.retry') }}</GhostBtn></PageErrorNotice>
            <template v-else><component :is="globeComponent" :points="mapRegions" :active="mapVisible && pageActive" :selected-region="selectedRegion" @select="selectRegion" /><div v-if="globeLoading || loading && !loaded" class="globe-placeholder globe-loading" role="status"><span class="i-mdi-earth" aria-hidden="true" /><p>{{ t('regionPage.loading') }}</p></div></template>
          </div>
        </aside>
        <div class="region-list-pane">
          <div ref="tableArea" class="region-table-area" :class="{ 'is-compact': compact }">
            <MobileRecordList v-if="compact" drilldown list-id="oci-regions" :record-keys="pagedRows.map(row => row.regionCode)" :loading="loading">
              <MobileRecordCard v-for="row in pagedRows" :key="row.regionCode" :record-key="row.regionCode" :data-selected="selectedRegion === row.regionCode" :summary-title="row.name" :summary-meta="row.regionCode" :summary-status="loaded ? t(`regionPage.statuses.${row.isMine ? 'linked' : 'unlinked'}`) : '—'" :summary-tone="row.isMine ? 'success' : 'neutral'">
                <template #identity><h2 class="mobile-record-title">{{ row.name }}</h2><span class="mobile-record-subtitle">{{ row.regionCode }}</span></template>
                <dl class="mobile-record-fields"><div><dt>{{ t('regionPage.continent') }}</dt><dd>{{ t(`regionPage.continents.${row.continent}`) }}</dd></div><div><dt>{{ t('regionPage.ownership') }}</dt><dd>{{ loaded ? t(`regionPage.statuses.${row.isMine ? 'linked' : 'unlinked'}`) : '—' }}</dd></div></dl>
                <template #footer><button type="button" class="mobile-record-button" :disabled="!mapRegionCodes.has(row.regionCode)" :title="locationHint(row)" :aria-pressed="selectedRegion === row.regionCode" @click="locateRegion(row.regionCode)"><span class="i-mdi-crosshairs-gps" aria-hidden="true" />{{ t('regionPage.locateRegion', { region: row.name }) }}</button></template>
              </MobileRecordCard>
              <template #empty>{{ t('regionPage.empty') }}</template>
            </MobileRecordList>
            <el-table v-else ref="table" v-loading="loading" class="region-table" :data="pagedRows" row-key="regionCode" :row-class-name="rowClassName" height="100%">
              <el-table-column :label="t('regionPage.name')" min-width="190"><template #default="{ row }"><button type="button" class="region-name" :disabled="!mapRegionCodes.has(row.regionCode)" :title="locationHint(row)" :aria-label="locationHint(row)" :aria-pressed="selectedRegion === row.regionCode" :data-selected="selectedRegion === row.regionCode" @click="locateRegion(row.regionCode)"><span v-if="row.isMine" class="owned-dot" /><span>{{ row.name }}</span><span v-if="mapRegionCodes.has(row.regionCode)" class="i-mdi-crosshairs-gps" aria-hidden="true" /></button></template></el-table-column>
              <el-table-column prop="regionCode" :label="t('regionPage.code')" min-width="200" />
              <el-table-column :label="t('regionPage.continent')" min-width="145"><template #default="{ row }">{{ t(`regionPage.continents.${row.continent}`) }}</template></el-table-column>
              <el-table-column :label="t('regionPage.ownership')" min-width="150"><template #default="{ row }"><span v-if="loaded" class="region-status" :class="row.isMine ? 'linked' : 'muted'">{{ t(`regionPage.statuses.${row.isMine ? 'linked' : 'unlinked'}`) }}</span><span v-else>—</span></template></el-table-column>
              <template #empty>{{ t(loading ? 'regionPage.loading' : 'regionPage.empty') }}</template>
            </el-table>
          </div>
          <PagePagination v-model:current-page="page" :total="filteredRows.length" :page-size="PAGE_SIZE" :aria-label="t('regionPage.pagination')"><span>{{ t('regionPage.matchingRows', { count: filteredRows.length }) }}</span></PagePagination>
        </div>
      </div>
      <footer class="region-footer"><div class="region-counters"><span>{{ t('regionPage.totalRegions') }} <strong>{{ allRows.length }}</strong></span><span>{{ t('regionPage.linkedRegions') }} <strong>{{ loaded ? ownedCodes.size : '—' }}</strong></span></div><span class="region-updated" :title="t('regionPage.refreshInterval')">{{ loading ? t('regionPage.loading') : updatedText }}</span></footer>
    </section>
  </div>
</template>

<style scoped>
.region-page { display: flex; min-height: 480px; min-width: 0; font-size: var(--font-size-body); }
.region-card { display: flex; flex-direction: column; width: 100%; min-width: 0; min-height: 0; overflow: hidden; background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--r-card); box-shadow: var(--shadow-card); }
.region-toolbar { display: flex; align-items: center; flex-wrap: wrap; gap: 10px; padding: 14px 16px; border-bottom: 1px solid var(--border); }
.region-search { flex: 1; min-width: 170px; max-width: 320px; }
.continent-filter { width: 156px; }
.status-filter { width: 142px; }
.region-toolbar-actions { display: flex; align-items: center; gap: 8px; margin-left: auto; }
.region-toolbar :deep(.el-input__wrapper), .region-toolbar :deep(.el-select__wrapper) { min-height: 38px; font-size: var(--font-size-body); }
.region-toolbar :deep(.el-input__inner), .region-toolbar :deep(.el-select__input), .region-toolbar :deep(.el-select__selected-item) { font-size: var(--font-size-body); }
.region-card :deep(.btn) { font-size: var(--font-size-body); }
.region-toolbar-actions :deep(.btn) { min-height: 38px; padding: 8px 13px; }
.region-load-error { display: flex; align-items: center; gap: 12px; padding: 12px 16px; background: var(--status-danger-bg); border-bottom: 1px solid var(--border); }
.region-load-error > span { flex-shrink: 0; color: var(--status-danger); font-size: 20px; }
.region-load-error > div { flex: 1; min-width: 0; }
.region-load-error p { margin: 0; font-size: var(--font-size-body); line-height: 1.65; overflow-wrap: anywhere; }
.region-load-error strong { font-weight: 500; }
.region-load-error p > span { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.region-workspace { display: flex; flex-direction: column; min-height: 0; }
.globe-pane { display: flex; flex-direction: column; min-width: 0; border-bottom: 1px solid var(--border); }
.globe-toolbar { display: flex; align-items: center; flex-wrap: wrap; justify-content: space-between; gap: 7px 16px; padding: 12px 16px 10px; }
.globe-filter-note { flex-basis: 100%; margin: 0; color: var(--text-muted); font-size: var(--font-size-secondary); line-height: 1.5; }
.globe-count { font-size: var(--font-size-secondary); color: var(--text-secondary); font-variant-numeric: tabular-nums; white-space: nowrap; }
.globe-stage { position: relative; display: flex; flex-direction: column; min-height: 340px; overflow: hidden; }
.globe-stage > :deep(.region-globe) { flex: 1; }
.globe-placeholder { display: flex; flex: 1; flex-direction: column; align-items: center; justify-content: center; padding: 28px; text-align: center; color: var(--text-secondary); }
.globe-placeholder > span { font-size: 32px; color: var(--brand); }
.globe-placeholder p { margin: 12px 0 18px; font-size: var(--font-size-secondary); }
.globe-loading { position: absolute; inset: 0; background: var(--bg-card); }
.region-list-pane { display: flex; flex-direction: column; height: 440px; min-width: 0; min-height: 350px; }
.region-workspace.map-collapsed .region-list-pane { height: max(480px, calc(100dvh - 220px)); }
.region-table-area { flex: 1; min-height: 0; overflow: hidden; }
.region-table-area.is-compact { overflow: auto; overscroll-behavior: contain; }
.region-mobile-empty { padding: 20px 14px; color: var(--text-secondary); }
.region-table { font-family: var(--sans); font-size: var(--font-size-body); }
.region-table :deep(th.el-table__cell) { height: 36px; padding: 6px 0; background: transparent; color: var(--text-secondary); font-size: var(--font-size-body); font-weight: 500; }
.region-table :deep(td.el-table__cell) { height: 48px; padding: 7px 0; font-size: var(--font-size-body); font-variant-numeric: tabular-nums; }
.region-table :deep(.el-table__inner-wrapper::before) { display: none; }
.region-table :deep(.region-selected-row td.el-table__cell) { background: var(--brand-subtle); }
.region-table :deep(.region-selected-row td.el-table__cell:first-child) { box-shadow: inset 3px 0 var(--brand); }
.region-status { display: inline-flex; align-items: center; gap: 5px; padding: 3px 8px; border-radius: var(--r-pill); font-size: var(--font-size-caption); white-space: nowrap; }
.region-status::before { content: ''; width: 4px; height: 4px; border-radius: 50%; background: currentColor; }
.region-status.linked { background: var(--status-ok-bg); color: var(--status-ok); }
.region-status.muted { background: var(--bg-search); color: var(--text-secondary); }
.region-name { display: inline-flex; align-items: center; gap: 6px; max-width: 100%; border: 0; padding: 4px 0; background: transparent; color: var(--text-primary); font: inherit; text-align: left; cursor: pointer; }
.region-name > span:not([class]) { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.region-name > .i-mdi-crosshairs-gps { flex-shrink: 0; font-size: 13px; color: var(--text-muted); }
.region-name:not(:disabled):hover, .region-name[aria-pressed='true'] { color: var(--brand); }
.region-name:disabled { cursor: default; }
.owned-dot { flex-shrink: 0; width: 5px; height: 5px; border-radius: 50%; background: var(--brand); }
.region-footer { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; flex-shrink: 0; gap: 8px 20px; padding: 11px 16px; border-top: 1px solid var(--border); }
.region-counters { display: flex; flex-wrap: wrap; gap: 8px 20px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.region-counters strong { margin-left: 4px; color: var(--text-primary); font-weight: 600; font-variant-numeric: tabular-nums; }
.region-updated { color: var(--text-muted); font-size: var(--font-size-secondary); }
@media (max-width: 640px) {
  .region-toolbar { gap: 8px; padding: 12px; }
  .region-search { width: 100%; min-width: 100%; max-width: none; }
  .continent-filter { flex: 1; min-width: 110px; width: auto; }
  .status-filter { flex: 1; min-width: 110px; width: auto; }
  .region-toolbar-actions { margin-left: 0; }
  .region-toolbar-actions :deep(.btn) { min-width: 36px; padding: 9px; }
  .toolbar-button-label { display: none; }
  .globe-toolbar { gap: 6px; padding: 10px; }
  .region-footer { padding-inline: 12px; }
  .region-load-error { flex-wrap: wrap; }
}
</style>
