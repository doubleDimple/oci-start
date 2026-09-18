<script setup lang="ts">
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from '@/components/PageBackButton.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import { isMetricServerId, type MetricServer, type MetricsApiError } from '@/api/metrics'
import MetricUsage from './components/MetricUsage.vue'
import { useMetricsPage } from './useMetricsPage'
import './metrics.scss'

const compact = useCompactViewport()
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const {
  rows, loading, loaded, readProblem, lastUpdated, autoRefresh, autoRefreshPaused, refresh,
  deleteTarget, deletePending, deleteProblem, deleteResult, openDelete, closeDelete,
  confirmDelete, canDismissModal,
} = useMetricsPage()
const search = ref('')
const statusFilter = ref<'all' | 'online' | 'offline' | 'unknown'>('all')
const columns = ['server', 'ip', 'status', 'cpu', 'memory', 'disk', 'totalUpload', 'totalDownload', 'lastReport', 'actions'] as const
const filtered = computed(() => !!search.value.trim() || statusFilter.value !== 'all')
const visibleRows = computed(() => {
  const query = search.value.trim().toLowerCase()
  const counts = new Map<string, number>()
  const occurrences = new Map<string, number>()
  for (const row of rows.value) counts.set(row.serverId, (counts.get(row.serverId) || 0) + 1)
  // Unique probe IDs survive reordering. Duplicate reports have no immutable
  // report ID, so an altered report becomes unavailable rather than selecting
  // another report. Identical duplicates are indistinguishable in this API.
  return rows.value.map(row => {
    const identity = counts.get(row.serverId) === 1 ? JSON.stringify([row.serverId]) : JSON.stringify([row.serverId, row])
    const occurrence = occurrences.get(identity) || 0
    occurrences.set(identity, occurrence + 1)
    return { row, key: occurrence ? `${identity}:${occurrence}` : identity }
  }).filter(({ row }) => {
    return (!query || row.serverId.toLowerCase().includes(query) || row.serverIp?.toLowerCase().includes(query))
      && (statusFilter.value === 'all' || statusFilter.value === status(row))
  })
})
const duplicates = computed(() => {
  const seen = new Set<string>()
  for (const row of rows.value) {
    if (!isMetricServerId(row.serverId)) continue
    if (seen.has(row.serverId)) return true
    seen.add(row.serverId)
  }
  return false
})
const emptyMessage = computed(() => {
  if (!loaded.value && loading.value) return t('metrics.loading')
  if (!loaded.value && readProblem.value) return t('metrics.loadFailed')
  if (rows.value.length && !visibleRows.value.length) return t('metrics.noMatches')
  return loaded.value ? t('metrics.empty') : t('metrics.loading')
})
const countLabel = computed(() => !loaded.value ? t('metrics.notRefreshed') : filtered.value
  ? t('metrics.filteredCount', { visible: number(visibleRows.value.length), total: number(rows.value.length) })
  : t('metrics.count', { count: number(rows.value.length) }))
const refreshLabel = computed(() => lastUpdated.value ? t('metrics.lastRefreshed', {
  time: new Intl.DateTimeFormat(locale.value, { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' }).format(lastUpdated.value),
}) : '')
const recordReappeared = computed(() => deleteResult.value === 'success' && !loading.value && !readProblem.value
  && rows.value.some(row => row.serverId === deleteTarget.value?.serverId))

function number(value: number) { return new Intl.NumberFormat(locale.value, { maximumFractionDigits: 2 }).format(value) }
function name(row: MetricServer) { return row.serverId.trim() ? row.serverId : t('metrics.unknownServer') }
function text(value: string | null) { return value?.trim() ? value : '—' }
function status(row: MetricServer) { return row.online === true ? 'online' : row.online === false ? 'offline' : 'unknown' }
function capacity(value: number | null) { return value == null ? '—' : `${number(value)} GB` }
function cores(value: number | null) { return value == null ? '—' : t('metrics.cores', { count: number(value) }) }
function errorMessage(problem: MetricsApiError) { return t(`metrics.errors.${problem.key}`) }
function columnHint(column: typeof columns[number]) {
  if (column === 'server') return t('metrics.serverHint')
  if (column === 'status') return t('metrics.onlineHint')
  if (column === 'totalUpload' || column === 'totalDownload') return t('metrics.trafficHint')
  if (column === 'lastReport') return t('metrics.lastReportHint')
  return undefined
}
function serverTime(value: string | null) {
  if (!value?.trim()) return '—'
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/.exec(value)
  if (!match) return value
  const [year, month, day, hour, minute, second] = match.slice(1).map(Number) as [number, number, number, number, number, number]
  const date = new Date(Date.UTC(year, month - 1, day, hour, minute, second))
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day
    || date.getUTCHours() !== hour || date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second) return value
  // Format the server's wall-clock components without inventing a source timezone
  // or shifting them to the browser's timezone.
  return new Intl.DateTimeFormat(locale.value, {
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
    hourCycle: 'h23', timeZone: 'UTC',
  }).format(date)
}
function clearFilters() { search.value = ''; statusFilter.value = 'all' }
function deleteVisibility(value: boolean) { if (!value) closeDelete() }
function beforeDeleteClose(done: () => void) { if (canDismissModal.value) { closeDelete(); done() } }
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/oci/list')
}
</script>

<template>
  <section class="metrics-page" :aria-label="t('metrics.title')">
    <header class="metrics-toolbar">
      <PageBackButton :disabled="deletePending" @click="back" />
      <label class="metrics-search"><i class="i-mdi-magnify" aria-hidden="true" /><input v-model="search" type="search" :placeholder="t('metrics.search')" :aria-label="t('metrics.search')" :spellcheck="false" /></label>
      <el-select v-model="statusFilter" class="metrics-status-select" :aria-label="t('metrics.filterStatus')">
        <el-option value="all" :label="t('metrics.allStatuses')" /><el-option value="online" :label="t('metrics.online')" /><el-option value="offline" :label="t('metrics.offline')" /><el-option value="unknown" :label="t('metrics.unknown')" />
      </el-select>
      <div class="metrics-toolbar-actions" data-page-error-anchor><GhostBtn :loading="loading" :disabled="deletePending" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('metrics.refresh') }}</GhostBtn></div>
    </header>

    <PageErrorNotice v-if="readProblem"><span>{{ errorMessage(readProblem) }} <span v-if="readProblem.detail">{{ readProblem.detail }}</span> <span v-if="loaded">{{ t('metrics.retainedHint') }}</span></span><GhostBtn :disabled="deletePending" :loading="loading" @click="refresh">{{ t('metrics.refresh') }}</GhostBtn></PageErrorNotice>
    <div v-if="duplicates" class="metrics-notice is-warning" role="status"><i class="i-mdi-information-outline" aria-hidden="true" /><span>{{ t('metrics.duplicateHint') }}</span></div>

    <div class="metrics-body" :aria-busy="loading">
      <div class="metrics-table-wrap">
        <MobileRecordList v-if="compact" drilldown :list-id="'metrics-table'" :record-keys="visibleRows.map(entry => entry.key)" :loading="loading">
          <MobileRecordCard v-for="entry in visibleRows" :key="entry.key" :record-key="entry.key" :summary-title="name(entry.row)" :summary-meta="text(entry.row.serverIp)" :summary-status="t(`metrics.${status(entry.row)}`)" :summary-tone="status(entry.row) === 'online' ? 'success' : status(entry.row) === 'offline' ? 'danger' : 'neutral'">
            <template #identity><h3 class="mobile-record-title">{{ name(entry.row) }}</h3></template>
            <dl class="mobile-record-fields">
              <div class="mobile-record-wide"><dt>{{ t('metrics.server') }}</dt><dd><span class="metrics-truncate" :title="name(entry.row)">{{ name(entry.row) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.ip') }}</dt><dd><span class="metrics-truncate" :title="text(entry.row.serverIp)">{{ text(entry.row.serverIp) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.status') }}</dt><dd><span class="metrics-status" :class="`is-${status(entry.row)}`" :title="t('metrics.onlineHint')">{{ t(`metrics.${status(entry.row)}`) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.cpu') }}</dt><dd><MetricUsage :value="entry.row.cpuUsage" :capacity="cores(entry.row.cpuCores)" :label="t('metrics.cpu')" /></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.memory') }}</dt><dd><MetricUsage :value="entry.row.memoryUsage" :capacity="capacity(entry.row.totalMemory)" :label="t('metrics.memory')" /></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.disk') }}</dt><dd><MetricUsage :value="entry.row.diskUsage" :capacity="capacity(entry.row.totalDisk)" :label="t('metrics.disk')" /></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.totalUpload') }}</dt><dd><span class="metrics-truncate" :title="text(entry.row.totalUploadTraffic)">{{ text(entry.row.totalUploadTraffic) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.totalDownload') }}</dt><dd><span class="metrics-truncate" :title="text(entry.row.totalDownloadTraffic)">{{ text(entry.row.totalDownloadTraffic) }}</span></dd></div>
              <div class="mobile-record-wide"><dt>{{ t('metrics.lastReport') }}</dt><dd><span class="metrics-truncate" :title="text(entry.row.lastCheckTime)">{{ serverTime(entry.row.lastCheckTime) }}</span></dd></div>
            </dl>
            <template #footer><GhostBtn danger :disabled="deletePending || !isMetricServerId(entry.row.serverId)" :aria-label="`${t('metrics.delete')} ${name(entry.row)}`" @click="openDelete(entry.row)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('metrics.delete') }}</GhostBtn></template>
          </MobileRecordCard>
        </MobileRecordList>
        <table v-else class="metrics-table" :aria-label="t('metrics.title')">
          <thead><tr><th v-for="column in columns" :key="column" scope="col" :title="columnHint(column)">{{ t(`metrics.${column}`) }}</th></tr></thead>
          <tbody>
            <tr v-for="entry in visibleRows" :key="entry.key">
              <td class="metrics-name-cell"><span class="metrics-truncate" :title="name(entry.row)">{{ name(entry.row) }}</span></td>
              <td class="metrics-ip-cell"><span class="metrics-truncate" :title="text(entry.row.serverIp)">{{ text(entry.row.serverIp) }}</span></td>
              <td><span class="metrics-status" :class="`is-${status(entry.row)}`" :title="t('metrics.onlineHint')">{{ t(`metrics.${status(entry.row)}`) }}</span></td>
              <td><MetricUsage :value="entry.row.cpuUsage" :capacity="cores(entry.row.cpuCores)" :label="t('metrics.cpu')" /></td>
              <td><MetricUsage :value="entry.row.memoryUsage" :capacity="capacity(entry.row.totalMemory)" :label="t('metrics.memory')" /></td>
              <td><MetricUsage :value="entry.row.diskUsage" :capacity="capacity(entry.row.totalDisk)" :label="t('metrics.disk')" /></td>
              <td class="metrics-traffic-cell"><span class="metrics-truncate" :title="text(entry.row.totalUploadTraffic)">{{ text(entry.row.totalUploadTraffic) }}</span></td>
              <td class="metrics-traffic-cell"><span class="metrics-truncate" :title="text(entry.row.totalDownloadTraffic)">{{ text(entry.row.totalDownloadTraffic) }}</span></td>
              <td class="metrics-time-cell"><span class="metrics-truncate" :title="text(entry.row.lastCheckTime)">{{ serverTime(entry.row.lastCheckTime) }}</span></td>
              <td><GhostBtn danger :disabled="deletePending || !isMetricServerId(entry.row.serverId)" :aria-label="`${t('metrics.delete')} ${name(entry.row)}`" @click="openDelete(entry.row)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('metrics.delete') }}</GhostBtn></td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-if="!visibleRows.length" class="metrics-empty" role="status">
        <i class="i-mdi-chart-box-outline" aria-hidden="true" /><p>{{ emptyMessage }}</p>
        <span v-if="loaded && !rows.length && !readProblem">{{ t('metrics.emptyHint') }}</span>
        <GhostBtn v-if="filtered" @click="clearFilters">{{ t('metrics.clearFilters') }}</GhostBtn>
        <GhostBtn v-else-if="readProblem" :loading="loading" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('metrics.refresh') }}</GhostBtn>
      </div>
    </div>

    <footer class="metrics-footer">
      <div class="metrics-footer-info"><span>{{ countLabel }}</span><span v-if="refreshLabel">{{ refreshLabel }}</span><span class="metrics-traffic-hint" :title="t('metrics.trafficHint')"><i class="i-mdi-information-outline" aria-hidden="true" />{{ t('metrics.trafficLabel') }}</span></div>
      <span v-if="autoRefreshPaused">{{ t('metrics.refreshPaused') }}</span>
      <label class="metrics-auto-refresh"><input v-model="autoRefresh" type="checkbox" />{{ t('metrics.autoRefresh') }}</label>
    </footer>

    <el-dialog :model-value="!!deleteTarget" :title="t('metrics.deleteTitle')" width="520px" :close-on-click-modal="false" :close-on-press-escape="canDismissModal" :show-close="canDismissModal" :before-close="beforeDeleteClose" class="metrics-delete-dialog" @update:model-value="deleteVisibility">
      <template v-if="deleteTarget">
        <p class="metrics-delete-target">{{ t('metrics.deleteTarget', { name: name(deleteTarget) }) }}</p>
        <p>{{ t('metrics.deleteHint') }}</p>
        <div v-if="deletePending" class="metrics-notice" role="status">{{ t('metrics.deleting') }}</div>
        <div v-else-if="deleteResult === 'success'" class="metrics-notice" role="status">{{ t('metrics.deleteSuccess') }} <span v-if="recordReappeared">{{ t('metrics.deleteReappeared') }}</span></div>
        <div v-else-if="deleteResult === 'unknown'" class="metrics-notice is-warning" role="alert">{{ t('metrics.deleteUnknown') }}</div>
        <PageErrorNotice v-if="deleteProblem || deleteResult === 'failed'"><span>{{ t(deleteResult === 'unknown' ? 'metrics.deleteUnknown' : 'metrics.deleteFailed') }} <span v-if="deleteProblem">{{ errorMessage(deleteProblem) }} {{ deleteProblem.detail }}</span></span></PageErrorNotice>
        <PageErrorNotice v-if="deleteResult !== 'idle' && readProblem">{{ t('metrics.deleteRecheckFailed') }}</PageErrorNotice>
      </template>
      <template #footer>
        <GhostBtn :disabled="!canDismissModal" @click="closeDelete">{{ t(deleteResult === 'idle' ? 'metrics.cancel' : 'metrics.close') }}</GhostBtn>
        <PrimaryBtn v-if="deleteResult === 'idle'" class="metrics-delete-submit" :loading="deletePending" @click="confirmDelete"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('metrics.deleteConfirm') }}</PrimaryBtn>
        <GhostBtn v-else-if="readProblem" :loading="loading" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('metrics.refresh') }}</GhostBtn>
      </template>
    </el-dialog>
  </section>
</template>

<style scoped>
.metrics-status-select { flex: 0 1 170px; min-width: 140px; max-width: 100%; }

.mobile-record-fields .metrics-truncate, .mobile-record-fields .metrics-ellipsis { max-width: 100%; white-space: normal; overflow-wrap: anywhere; }
.mobile-record-card .metrics-row-actions { flex-wrap: wrap; }
</style>
