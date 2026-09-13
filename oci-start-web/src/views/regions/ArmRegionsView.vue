<script setup lang="ts">
import { computed, defineAsyncComponent, nextTick, onMounted, onUnmounted, ref, shallowRef, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { TableInstance } from 'element-plus'
import { fetchArmData, fetchMyRegions } from '@/api/resource'
import { REGION_COORDINATES, englishRegionName, getContinent } from './regionCoords'
import type { RegionGlobePoint } from './globeTypes'
import GhostBtn from '@/components/GhostBtn.vue'

const PAGE_SIZE = 10
const REFRESH_MS = 5 * 60 * 1000
interface ArmRecord {
  region: string
  architectureType?: string
  openTime?: string
  openCount?: number
  monthlyOpenCount?: number
  lastNotifyTime?: string
}
interface RegionRow extends Omit<RegionGlobePoint, 'lat' | 'lng'> {
  rowId: string
  continent: string
  coordinates?: { lat: number; lng: number }
}
interface LoadProblem { key: string; detail: string }

const { t, locale } = useI18n()
const loading = ref(false)
const armLoaded = ref(false)
const mineLoaded = ref(false)
const armLoading = ref(false)
const mineLoading = ref(false)
const lastUpdate = ref<Date | null>(null)
const refreshClock = ref(Date.now())
const loadProblems = ref<LoadProblem[]>([])
const search = ref('')
const continent = ref('all')
const status = ref('all')
const page = ref(1)
const mapVisible = ref(true)
const showArmRegions = ref(true)
const showMyRegions = ref(true)
const selectedRegion = ref<string | null>(null)
const openRegions = ref<ArmRecord[]>([])
const myRegions = ref<ArmRecord[]>([])
const regionMap = ref<Record<string, string>>({})
const table = ref<TableInstance>()
const tableArea = ref<HTMLElement>()
const pageActive = ref(true)
const globeLoading = ref(false)
const globeLoadFailed = ref(false)
let disposed = false
let requestVersion = 0
let requestController: AbortController | null = null
let refreshTimer: number | null = null

function createGlobeComponent() {
  return defineAsyncComponent({
    loader: async () => {
      if (!disposed) globeLoading.value = true
      try { return (await import('./components/RegionGlobe.vue')).default }
      catch {
        if (!disposed) globeLoadFailed.value = true
        return { render: () => null }
      } finally { if (!disposed) globeLoading.value = false }
    },
  })
}
const globeComponent = shallowRef(createGlobeComponent())
function retryGlobe() {
  globeLoadFailed.value = false
  globeComponent.value = createGlobeComponent()
}

const continents = [
  { value: 'all', labelKey: 'arm.filterContinentAll' },
  { value: 'asia', labelKey: 'arm.filterContinentAsia' },
  { value: 'europe', labelKey: 'arm.filterContinentEurope' },
  { value: 'america-north', labelKey: 'arm.filterContinentNa' },
  { value: 'america-south', labelKey: 'arm.filterContinentSa' },
  { value: 'middle-east', labelKey: 'arm.filterContinentMe' },
]
const statuses = [
  { value: 'all', labelKey: 'arm.filterStatusAll' },
  { value: 'open', labelKey: 'regionPage.hasHistory' },
  { value: 'closed', labelKey: 'regionPage.noHistory' },
]
const dateFormatter = computed(() => new Intl.DateTimeFormat(locale.value.startsWith('zh') ? 'zh-CN' : 'en-US', { dateStyle: 'medium', timeStyle: 'medium' }))
const updatedText = computed(() => lastUpdate.value ? t('regionPage.updatedAt', { time: dateFormatter.value.format(lastUpdate.value) }) : t('regionPage.notUpdated'))
function parseDate(value: string) {
  // Server timestamps have no timezone. Preserve that meaning instead of appending UTC.
  return new Date(value.replace(/^(\d{4}-\d{2}-\d{2}) /, '$1T'))
}
function formatDateTime(value?: string | null) {
  if (!value) return '—'
  const date = parseDate(value)
  return Number.isNaN(date.getTime()) ? value : dateFormatter.value.format(date)
}
function regionName(code: string) {
  return locale.value.startsWith('zh') ? regionMap.value[code] || code : englishRegionName(code)
}
const ownedRegionCodes = computed(() => new Set(myRegions.value.map(region => region.region)))
const allRows = computed<RegionRow[]>(() => {
  const makeRow = (regionCode: string, rowId: string, record?: ArmRecord): RegionRow => ({
    rowId, regionCode, name: regionName(regionCode), coordinates: REGION_COORDINATES[regionCode],
    isOpen: (record?.openCount || 0) > 0,
    isMine: ownedRegionCodes.value.has(regionCode),
    architectureType: record?.architectureType || '—',
    openTime: record?.openTime || null,
    openCount: record?.openCount || 0,
    monthlyOpenCount: record?.monthlyOpenCount || 0,
    lastNotifyTime: record?.lastNotifyTime || null,
    continent: getContinent(regionCode),
  })
  // Preserve every backend record, including regions missing from the fixed coordinate table.
  const recorded = openRegions.value.map((record, index) => makeRow(record.region, 'record-' + index, record))
  const added = new Set(recorded.map(row => row.regionCode))
  const otherCodes = new Set([...Object.keys(REGION_COORDINATES), ...ownedRegionCodes.value])
  const remaining = [...otherCodes].filter(code => !added.has(code)).sort()
  return [...recorded, ...remaining.map(code => makeRow(code, 'region-' + code))]
})
const filteredRows = computed(() => {
  const term = search.value.trim().toLowerCase()
  return allRows.value.filter(region => {
    const matchesSearch = region.regionCode.toLowerCase().includes(term) || region.name.toLowerCase().includes(term)
    const matchesContinent = continent.value === 'all' || region.continent === continent.value
    const matchesStatus = status.value === 'all' || (status.value === 'open' && region.isOpen) || (status.value === 'closed' && !region.isOpen)
    return matchesSearch && matchesContinent && matchesStatus
  })
})
const pagedRows = computed(() => filteredRows.value.slice((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE))
const mapRegions = computed<RegionGlobePoint[]>(() => {
  const points = new Map<string, RegionGlobePoint>()
  // The map has its own category filters and never loses points to table filtering.
  for (const row of allRows.value) {
    if (!row.coordinates || (!row.isOpen && !row.isMine)) continue
    const existing = points.get(row.regionCode)
    if (existing && (existing.isOpen || !row.isOpen)) {
      existing.isMine ||= row.isMine
      continue
    }
    // A positive launch record takes precedence over another record for this region.
    points.set(row.regionCode, {
      regionCode: row.regionCode, name: row.name, ...row.coordinates,
      isOpen: row.isOpen, isMine: row.isMine || !!existing?.isMine, architectureType: row.architectureType,
      openTime: row.openTime, openCount: row.openCount, monthlyOpenCount: row.monthlyOpenCount, lastNotifyTime: row.lastNotifyTime,
    })
  }
  return [...points.values()]
})
const mapRegionCodes = computed(() => new Set(mapRegions.value.map(point => point.regionCode)))
const globePoints = computed(() => mapRegions.value.filter(point => (showArmRegions.value && point.isOpen) || (showMyRegions.value && point.isMine)))
const armMapCount = computed(() => mapRegions.value.filter(point => point.isOpen).length)
const mineMapCount = computed(() => mapRegions.value.filter(point => point.isMine).length)
const overlapCount = computed(() => mapRegions.value.filter(point => point.isOpen && point.isMine).length)
const unmappedCount = computed(() => new Set(allRows.value
  .filter(row => !row.coordinates && ((showArmRegions.value && row.isOpen) || (showMyRegions.value && row.isMine)))
  .map(row => row.regionCode)).size)
const totalRegions = computed(() => new Set(allRows.value.map(row => row.regionCode)).size)
const openArmCount = computed(() => new Set(allRows.value.filter(row => row.isOpen).map(row => row.regionCode)).size)
const todayNewCount = computed(() => {
  const today = new Date(refreshClock.value)
  today.setHours(0, 0, 0, 0)
  const tomorrow = new Date(today)
  tomorrow.setDate(tomorrow.getDate() + 1)
  return new Set(allRows.value.filter(row => {
    if (!row.openTime || !row.isOpen) return false
    const opened = parseDate(row.openTime)
    return opened >= today && opened < tomorrow
  }).map(row => row.regionCode)).size
})
const visibleProblems = computed(() => loadProblems.value.map(problem => ({
  title: t(problem.key), detail: problem.detail.startsWith('regionPage.') ? t(problem.detail) : problem.detail,
})))

function recordList(value: unknown): ArmRecord[] {
  if (value == null) return []
  const records = Array.isArray(value) ? value : [value]
  if (records.some(record => !record || typeof record !== 'object')) throw new Error('regionPage.invalidData')
  return records.filter(record => typeof record.region === 'string' && record.region.trim())
}
function parseArm(value: any) {
  if (Array.isArray(value)) return { records: recordList(value), names: regionMap.value }
  const payload = value?.data ?? value
  if (!payload || typeof payload !== 'object' || !('armRecords' in payload)) throw new Error('regionPage.invalidData')
  const names: Record<string, string> = {}
  const suppliedNames = payload.regionMap ?? regionMap.value
  if (suppliedNames && typeof suppliedNames === 'object' && !Array.isArray(suppliedNames)) {
    for (const [key, name] of Object.entries(suppliedNames)) if (typeof name === 'string') names[key] = name
  }
  return { records: recordList(payload.armRecords), names }
}
function parseMine(value: any) {
  const payload = value?.data ?? value
  if (!payload || typeof payload !== 'object' || !('hasRecords' in payload)) throw new Error('regionPage.invalidData')
  return recordList(payload.hasRecords)
}
function errorDetail(cause: any) {
  const body = cause?.response?.data
  return String((typeof body === 'string' ? body : body?.message || body?.msg) || cause?.message || cause?.msg || '')
}
async function loadAll() {
  if (loading.value || disposed) return
  const version = ++requestVersion
  requestController?.abort()
  requestController = new AbortController()
  refreshClock.value = Date.now()
  loading.value = true
  armLoading.value = true
  mineLoading.value = true
  loadProblems.value = []
  const config = { signal: requestController.signal, timeout: 30000 }
  const isCurrent = () => !disposed && version === requestVersion
  // Commit each source independently so a slow or failed request cannot hide the other.
  await Promise.allSettled([
    (async () => {
      try {
        const response = await fetchArmData(config)
        if (!isCurrent()) return
        const data = parseArm(response)
        openRegions.value = data.records
        regionMap.value = data.names
        armLoaded.value = true
        lastUpdate.value = new Date()
      } catch (cause) {
        if (isCurrent()) loadProblems.value.push({ key: 'regionPage.armLoadFailed', detail: errorDetail(cause) })
      } finally { if (isCurrent()) armLoading.value = false }
    })(),
    (async () => {
      try {
        const response = await fetchMyRegions(config)
        if (!isCurrent()) return
        myRegions.value = parseMine(response)
        mineLoaded.value = true
        lastUpdate.value = new Date()
      } catch (cause) {
        if (isCurrent()) loadProblems.value.push({ key: 'regionPage.mineLoadFailed', detail: errorDetail(cause) })
      } finally { if (isCurrent()) mineLoading.value = false }
    })(),
  ])
  if (isCurrent()) loading.value = false
}
async function selectRegion(code: string | null) {
  if (!code) { selectedRegion.value = null; return }
  if (!mapRegionCodes.value.has(code)) return
  const matches = allRows.value.filter(region => region.regionCode === code)
  const term = search.value.trim().toLowerCase()
  if (term && !matches.some(region => region.regionCode.toLowerCase().includes(term) || region.name.toLowerCase().includes(term))) search.value = ''
  if (continent.value !== 'all' && !matches.some(region => region.continent === continent.value)) continent.value = 'all'
  if (status.value !== 'all' && !matches.some(region => status.value === 'open' ? region.isOpen : !region.isOpen)) status.value = 'all'
  selectedRegion.value = code
  // Filter watchers reset pagination first; then jump to the selected region's page.
  await nextTick()
  if (disposed || selectedRegion.value !== code) return
  const index = filteredRows.value.findIndex(region => region.regionCode === code)
  if (index < 0) { selectedRegion.value = null; return }
  page.value = Math.floor(index / PAGE_SIZE) + 1
}
async function locateRegion(code: string) {
  const point = mapRegions.value.find(region => region.regionCode === code)
  if (!point) return
  if (!globePoints.value.some(region => region.regionCode === code)) {
    if (point.isOpen) showArmRegions.value = true
    else showMyRegions.value = true
  }
  mapVisible.value = true
  if (selectedRegion.value === code) { selectedRegion.value = null; await nextTick() }
  if (!disposed) await selectRegion(code)
}
function locationHint(row: RegionRow) {
  if (!row.coordinates) return t('regionPage.unmappedRegion', { region: row.name })
  return t(mapRegionCodes.value.has(row.regionCode) ? 'regionPage.locateRegion' : 'regionPage.untrackedRegion', { region: row.name })
}
async function scrollToSelection() {
  await nextTick()
  if (disposed) return
  const row = tableArea.value?.querySelector<HTMLElement>('[data-selected="true"]')?.closest('tr')
  const scroll = tableArea.value?.querySelector<HTMLElement>('.el-table__body-wrapper .el-scrollbar__wrap')
  if (!row || !scroll) { table.value?.setScrollTop(0); return }
  const rowRect = row.getBoundingClientRect()
  const viewport = scroll.getBoundingClientRect()
  if (rowRect.top < viewport.top) scroll.scrollTop += rowRect.top - viewport.top
  else if (rowRect.bottom > viewport.bottom) scroll.scrollTop += rowRect.bottom - viewport.bottom
}
function rowClassName({ row }: { row: RegionRow }) { return row.regionCode === selectedRegion.value ? 'region-selected-row' : '' }
function updateVisibility() { pageActive.value = document.visibilityState !== 'hidden' }
watch([search, continent, status], () => { page.value = 1 })
watch(filteredRows, rows => {
  page.value = Math.max(1, Math.min(page.value, Math.ceil(rows.length / PAGE_SIZE)))
})
watch(globePoints, points => {
  if (selectedRegion.value && !points.some(point => point.regionCode === selectedRegion.value)) selectedRegion.value = null
})
watch([page, selectedRegion], () => { void scrollToSelection() })
onMounted(() => {
  updateVisibility()
  document.addEventListener('visibilitychange', updateVisibility)
  void loadAll()
  refreshTimer = window.setInterval(() => { void loadAll() }, REFRESH_MS)
})
onUnmounted(() => {
  disposed = true
  requestVersion++
  requestController?.abort()
  if (refreshTimer !== null) window.clearInterval(refreshTimer)
  document.removeEventListener('visibilitychange', updateVisibility)
})
</script>

<template>
  <div class="region-page">
    <section class="region-card" :aria-label="t('arm.pageTitle')">
      <div class="region-toolbar">
        <el-input v-model="search" class="region-search" :placeholder="t('arm.searchPlaceholder')" :aria-label="t('arm.searchPlaceholder')" clearable><template #prefix><span class="i-mdi-magnify" aria-hidden="true" /></template></el-input>
        <el-select v-model="continent" class="continent-filter" :aria-label="t('regionPage.continentFilter')"><el-option v-for="item in continents" :key="item.value" :label="t(item.labelKey)" :value="item.value" /></el-select>
        <el-select v-model="status" class="status-filter" :aria-label="t('regionPage.statusFilter')"><el-option v-for="item in statuses" :key="item.value" :label="t(item.labelKey)" :value="item.value" /></el-select>
        <div class="region-toolbar-actions">
          <GhostBtn :loading="loading" :aria-label="t('regionPage.refresh')" @click="loadAll"><span class="i-mdi-refresh" aria-hidden="true" /><span class="toolbar-button-label">{{ t('regionPage.refresh') }}</span></GhostBtn>
          <GhostBtn :aria-label="t(mapVisible ? 'arm.mapHide' : 'arm.mapShow')" :aria-expanded="mapVisible" aria-controls="region-globe-panel" @click="mapVisible = !mapVisible"><span :class="mapVisible ? 'i-mdi-earth' : 'i-mdi-earth-off'" aria-hidden="true" /><span class="toolbar-button-label">{{ t(mapVisible ? 'arm.mapHide' : 'arm.mapShow') }}</span></GhostBtn>
        </div>
      </div>
      <div v-if="visibleProblems.length" class="region-load-error" role="alert"><span class="i-mdi-alert-circle-outline" aria-hidden="true" /><div><p v-for="(problem, index) in visibleProblems" :key="index"><strong>{{ problem.title }}</strong><span v-if="problem.detail"> · {{ problem.detail }}</span></p></div><GhostBtn :loading="loading" @click="loadAll">{{ t('regionPage.retry') }}</GhostBtn></div>
      <div class="region-workspace" :class="{ 'map-collapsed': !mapVisible }">
        <aside id="region-globe-panel" v-show="mapVisible" class="globe-pane" :aria-label="t('regionPage.globeLabel')">
          <div class="globe-toolbar">
            <div class="globe-categories" role="group" :aria-label="t('regionPage.mapFilters')">
              <label class="globe-category"><input v-model="showArmRegions" type="checkbox" /><span>{{ t('regionPage.showArm') }}</span><strong>{{ armLoaded ? armMapCount : '—' }}</strong><span v-if="armLoading" class="source-loading i-mdi-loading" role="status" :aria-label="t('regionPage.armSourceLoading')" /></label>
              <label class="globe-category"><input v-model="showMyRegions" type="checkbox" /><span>{{ t('regionPage.showMine') }}</span><strong>{{ mineLoaded ? mineMapCount : '—' }}</strong><span v-if="mineLoading" class="source-loading i-mdi-loading" role="status" :aria-label="t('regionPage.mineSourceLoading')" /></label>
              <span v-if="armLoaded && mineLoaded" class="globe-count">{{ t('regionPage.overlapCount', { count: overlapCount }) }}</span>
            </div>
            <span class="globe-count">{{ t('regionPage.mapCount', { count: globePoints.length, total: mapRegions.length }) }}</span>
            <p class="globe-filter-note">{{ t('regionPage.mapIndependent') }}</p>
            <p v-if="unmappedCount" class="globe-filter-note" role="status">{{ t('regionPage.unmappedCount', { count: unmappedCount }) }}</p>
          </div>
          <div class="globe-stage" :aria-busy="globeLoading">
            <div v-if="globeLoadFailed" class="globe-placeholder" role="alert"><span class="i-mdi-earth-off" aria-hidden="true" /><p>{{ t('regionPage.globeLoadFailed') }}</p><GhostBtn @click="retryGlobe">{{ t('regionPage.retry') }}</GhostBtn></div>
            <template v-else><component :is="globeComponent" :points="globePoints" :active="mapVisible && pageActive" :selected-region="selectedRegion" @select="selectRegion" /><div v-if="globeLoading" class="globe-placeholder globe-loading" role="status"><span class="i-mdi-earth" aria-hidden="true" /><p>{{ t('regionPage.globeLoading') }}</p></div></template>
          </div>
        </aside>
        <div class="region-list-pane">
          <div ref="tableArea" class="region-table-area">
            <el-table ref="table" :data="pagedRows" v-loading="loading && !armLoaded && !mineLoaded" height="100%" row-key="rowId" :row-class-name="rowClassName" class="region-table">
              <el-table-column :label="t('regionPage.historyStatus')" width="128"><template #default="{ row }"><span class="region-status" :class="armLoaded && row.isOpen ? 'recorded' : 'muted'">{{ armLoaded ? t(row.isOpen ? 'regionPage.hasHistory' : 'regionPage.noHistory') : '—' }}</span></template></el-table-column>
              <el-table-column prop="regionCode" :label="t('arm.colCode')" min-width="176" show-overflow-tooltip />
              <el-table-column :label="t('arm.colName')" min-width="168"><template #default="{ row }"><button type="button" class="region-name" :disabled="!mapRegionCodes.has(row.regionCode)" :title="locationHint(row)" :aria-label="locationHint(row)" :aria-pressed="selectedRegion === row.regionCode" :data-selected="selectedRegion === row.regionCode" @click="locateRegion(row.regionCode)"><span v-if="row.isMine" class="owned-dot" :title="t('regionPage.ownedRegion')" /><span>{{ row.name }}</span><span v-if="mapRegionCodes.has(row.regionCode)" class="i-mdi-crosshairs-gps" aria-hidden="true" /></button></template></el-table-column>
              <el-table-column prop="architectureType" :label="t('arm.colArch')" width="112" />
              <el-table-column :label="t('arm.colOpenTime')" min-width="190"><template #default="{ row }">{{ formatDateTime(row.openTime) }}</template></el-table-column>
              <el-table-column prop="openCount" :label="t('arm.colTotal')" width="122" align="right"><template #default="{ row }">{{ armLoaded ? row.openCount : '—' }}</template></el-table-column>
              <el-table-column prop="monthlyOpenCount" :label="t('arm.colMonth')" width="130" align="right"><template #default="{ row }">{{ armLoaded ? row.monthlyOpenCount : '—' }}</template></el-table-column>
              <el-table-column :label="t('regionPage.lastRecord')" min-width="190"><template #default="{ row }">{{ formatDateTime(row.lastNotifyTime) }}</template></el-table-column>
              <template #empty>{{ loading ? t('arm.loading') : t('arm.empty') }}</template>
            </el-table>
          </div>
          <div class="region-pager"><span>{{ t('regionPage.matchingRows', { count: filteredRows.length }) }}</span><el-pagination v-model:current-page="page" :total="filteredRows.length" :page-size="PAGE_SIZE" :pager-count="5" layout="prev, pager, next" :aria-label="t('regionPage.pagination')" /></div>
        </div>
      </div>
      <footer class="region-footer"><div class="region-counters"><span>{{ t('regionPage.totalRegions') }} <strong>{{ totalRegions }}</strong></span><span>{{ t('regionPage.armRecorded') }} <strong>{{ armLoaded ? openArmCount : '—' }}</strong></span><span :title="t('regionPage.todayHint')">{{ t('regionPage.today') }} <strong>{{ armLoaded ? todayNewCount : '—' }}</strong></span></div><span class="region-updated" :title="t('regionPage.refreshInterval')">{{ loading ? t('arm.loading') : updatedText }}</span></footer>
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
.globe-categories { display: flex; align-items: center; flex-wrap: wrap; gap: 10px 22px; }
.globe-category { display: inline-flex; align-items: center; gap: 7px; color: var(--text-primary); font-size: var(--font-size-body); cursor: pointer; }
.globe-category input { width: 15px; height: 15px; margin: 0; accent-color: var(--brand); cursor: pointer; }
.globe-category strong { color: var(--text-secondary); font-weight: 500; font-variant-numeric: tabular-nums; }
.globe-category input:focus-visible, .region-name:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.source-loading { color: var(--text-muted); font-size: 13px; animation: region-source-spin 1s linear infinite; }
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
.region-table { font-family: var(--sans); font-size: var(--font-size-body); }
.region-table :deep(th.el-table__cell) { height: 36px; padding: 6px 0; background: transparent; color: var(--text-secondary); font-size: var(--font-size-body); font-weight: 500; }
.region-table :deep(td.el-table__cell) { height: 48px; padding: 7px 0; font-size: var(--font-size-body); font-variant-numeric: tabular-nums; }
.region-table :deep(.el-table__inner-wrapper::before) { display: none; }
.region-table :deep(.region-selected-row td.el-table__cell) { background: var(--status-ok-bg); }
.region-table :deep(.region-selected-row td.el-table__cell:first-child) { box-shadow: inset 3px 0 var(--brand); }
.region-status { display: inline-flex; align-items: center; gap: 5px; padding: 3px 8px; border-radius: var(--r-pill); font-size: var(--font-size-caption); white-space: nowrap; }
.region-status::before { content: ''; width: 4px; height: 4px; border-radius: 50%; background: currentColor; }
.region-status.recorded { background: var(--status-ok-bg); color: var(--status-ok); }
.region-status.muted { background: var(--bg-search); color: var(--text-secondary); }
.region-name { display: inline-flex; align-items: center; gap: 6px; max-width: 100%; border: 0; padding: 4px 0; background: transparent; color: var(--text-primary); font: inherit; text-align: left; cursor: pointer; }
.region-name > span:not([class]) { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.region-name > .i-mdi-crosshairs-gps { flex-shrink: 0; font-size: 13px; color: var(--text-muted); }
.region-name:not(:disabled):hover, .region-name[aria-pressed='true'] { color: var(--brand); }
.region-name:disabled { cursor: default; }
.owned-dot { flex-shrink: 0; width: 5px; height: 5px; border-radius: 50%; background: var(--brand); }
.region-pager { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; flex-shrink: 0; min-height: 50px; padding: 8px 14px; border-top: 1px solid var(--border); }
.region-pager > span { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.region-pager :deep(.el-pagination) { --el-pagination-font-size: var(--font-size-body); max-width: 100%; flex-wrap: wrap; }
.region-pager :deep(.el-pager li), .region-pager :deep(.btn-prev), .region-pager :deep(.btn-next) { min-width: 27px; }
.region-footer { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; flex-shrink: 0; gap: 8px 20px; padding: 11px 16px; border-top: 1px solid var(--border); }
.region-counters { display: flex; flex-wrap: wrap; gap: 8px 20px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.region-counters strong { margin-left: 4px; color: var(--text-primary); font-weight: 600; font-variant-numeric: tabular-nums; }
.region-updated { color: var(--text-muted); font-size: var(--font-size-secondary); }
@keyframes region-source-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .source-loading { animation: none; } }
@media (max-width: 640px) {
  .region-toolbar { gap: 8px; padding: 12px; }
  .region-search { width: 100%; min-width: 100%; max-width: none; }
  .continent-filter { flex: 1; min-width: 110px; width: auto; }
  .status-filter { flex: 1; min-width: 110px; width: auto; }
  .region-toolbar-actions { margin-left: 0; }
  .region-toolbar-actions :deep(.btn) { min-width: 36px; padding: 9px; }
  .toolbar-button-label { display: none; }
  .globe-toolbar { gap: 6px; padding: 10px; }
  .globe-categories { gap: 10px 16px; }
  .region-pager { padding-inline: 10px; }
  .region-footer { padding-inline: 12px; }
  .region-load-error { flex-wrap: wrap; }
}
</style>
