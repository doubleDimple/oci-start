<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from '@/components/PageBackButton.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { loadSystemLogHistory, SYSTEM_LOG_STREAM_URL, openLogsError } from '@/api/openLogs'
import { useOpenLogs } from './useOpenLogs'
import './system-logs.scss'

const { t, locale } = useI18n()
const router = useRouter()
const route = useRoute()
const { rows, history, connection, bufferRevision, liveReceivedCount, trimmedCount, hasStreamGap, refreshHistory, reconnect, clear } = useOpenLogs({
  loadHistory: loadSystemLogHistory, streamUrl: SYSTEM_LOG_STREAM_URL,
})
const body = ref<HTMLElement | null>(null)
const query = ref('')
const wrap = ref(false)
const follow = ref(true)
const cleared = ref(false)
const unseen = ref(0)
const now = ref(new Date())
let clock: ReturnType<typeof setInterval> | undefined
let scrollFrame: number | undefined
let disposed = false
let adjustingScroll = false
const filtered = computed(() => {
  const needle = query.value.trim().toLowerCase()
  return needle ? rows.value.filter(row => row.text.toLowerCase().includes(needle)) : rows.value
})
const currentTime = computed(() => new Intl.DateTimeFormat(locale.value, { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(now.value))
const canReconnect = computed(() => !history.loading && ['reconnecting', 'disconnected'].includes(connection.value))
const emptyText = computed(() => {
  if (history.loading && !rows.value.length) return t('systemLogs.loadingHistory')
  if (query.value.trim() && rows.value.length) return t('systemLogs.noMatches')
  if (cleared.value) return t('systemLogs.cleared')
  if (history.problem) return t('systemLogs.historyUnavailable')
  return t('systemLogs.empty')
})
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function errorText(cause: unknown) { return t(`systemLogs.errors.${openLogsError(cause).key}`) }
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/boot/dashboard')
}
async function scrollLatest() {
  await nextTick()
  if (disposed || !follow.value || !body.value) return
  if (scrollFrame !== undefined) cancelAnimationFrame(scrollFrame)
  adjustingScroll = true
  body.value.scrollTop = body.value.scrollHeight
  scrollFrame = requestAnimationFrame(() => { adjustingScroll = false; scrollFrame = undefined })
}
function scrolled() {
  if (adjustingScroll || !body.value || !follow.value) return
  if (body.value.scrollHeight - body.value.scrollTop - body.value.clientHeight > 32) follow.value = false
}
function latest() { query.value = ''; follow.value = true; unseen.value = 0; void scrollLatest() }
function clearSearch() { query.value = '' }
function refresh() { cleared.value = false; unseen.value = 0; void refreshHistory() }
async function clearScreen() {
  clear(); cleared.value = true; unseen.value = 0
  await nextTick()
  if (!disposed && body.value) body.value.scrollTop = 0
}
watch(bufferRevision, () => {
  if (rows.value.length) cleared.value = false
  if (follow.value) void scrollLatest()
}, { flush: 'post' })
watch(liveReceivedCount, (current, previous) => { if (!follow.value) unseen.value += current - previous }, { flush: 'post' })
watch(follow, enabled => { if (enabled) { unseen.value = 0; void scrollLatest() } })
watch(query, value => { if (value.trim()) follow.value = false })
watch(wrap, () => { if (follow.value) void scrollLatest() })
onMounted(() => { clock = setInterval(() => { now.value = new Date() }, 1000) })
onBeforeUnmount(() => { disposed = true; clearInterval(clock); if (scrollFrame !== undefined) cancelAnimationFrame(scrollFrame) })
</script>

<template>
  <section class="system-logs-page" :aria-label="t('systemLogs.title')">
    <header class="system-logs-toolbar">
      <PageBackButton @click="back" />
      <label class="system-logs-search" :title="t('systemLogs.searchScope')"><i class="i-mdi-magnify" aria-hidden="true" /><input v-model="query" type="search" :placeholder="t('systemLogs.search')" :aria-label="t('systemLogs.search')" autocomplete="off" spellcheck="false" /></label>
      <GhostBtn v-if="query" :title="t('systemLogs.clearSearch')" :aria-label="t('systemLogs.clearSearch')" @click="clearSearch"><i class="i-mdi-close" aria-hidden="true" /></GhostBtn>
      <span class="system-logs-status" role="status"><i class="system-logs-dot" :class="connection" aria-hidden="true" />{{ t(`systemLogs.connection.${connection}`) }}</span>
      <div class="system-logs-actions" data-page-error-anchor><GhostBtn v-if="canReconnect" @click="reconnect"><i class="i-mdi-connection" aria-hidden="true" />{{ t('systemLogs.reconnect') }}</GhostBtn><GhostBtn :loading="history.loading" :title="t('systemLogs.refreshHint')" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('systemLogs.refreshHistory') }}</GhostBtn><GhostBtn :title="t('systemLogs.clearHint')" @click="clearScreen"><i class="i-mdi-broom" aria-hidden="true" />{{ t('systemLogs.clear') }}</GhostBtn></div>
    </header>
    <PageErrorNotice v-if="history.problem"><span>{{ errorText(history.problem) }} {{ t('systemLogs.historyFailureHint') }}</span></PageErrorNotice>
    <div v-if="connection === 'unsupported'" class="system-logs-notice" role="status"><i class="i-mdi-information-outline" aria-hidden="true" /><span>{{ t('systemLogs.unsupportedHint') }}</span></div>
    <div v-else-if="hasStreamGap" class="system-logs-notice" role="status"><i class="i-mdi-information-outline" aria-hidden="true" /><span>{{ t('systemLogs.gapHint') }}</span></div>
    <div class="system-logs-meta"><span role="status">{{ t(history.loading ? 'systemLogs.loadingHistory' : history.loaded ? 'systemLogs.historyLoaded' : 'systemLogs.historyPending') }}</span><span :title="t('systemLogs.searchScope')">{{ query.trim() ? t('systemLogs.matched', { matched: number(filtered.length), total: number(rows.length) }) : t('systemLogs.count', { count: number(rows.length) }) }}</span><label><input v-model="wrap" type="checkbox" />{{ t('systemLogs.wrap') }}</label></div>
    <div class="system-logs-console">
      <div ref="body" class="system-logs-body" :class="{ 'is-wrapped': wrap }" role="log" aria-live="off" :aria-label="t('systemLogs.logArea')" :aria-busy="history.loading" tabindex="0" @scroll.passive="scrolled">
        <p v-if="!filtered.length" class="system-logs-empty" role="status">{{ emptyText }}</p>
        <div v-for="row in filtered" :key="row.key" class="system-logs-row"><span class="system-logs-number" :title="t('systemLogs.lineNumber', { number: number(row.key) })" aria-hidden="true">{{ number(row.key) }}</span><span class="system-logs-marker" :class="row.level" :title="t(`systemLogs.level.${row.level}`)"><span class="system-logs-sr-only">{{ t(`systemLogs.level.${row.level}`) }}: </span></span><span class="system-logs-text">{{ row.text }}</span></div>
      </div>
      <button v-if="!follow" type="button" class="system-logs-latest" @click="latest"><i class="i-mdi-arrow-down" aria-hidden="true" />{{ unseen ? t('systemLogs.newEntries', { count: number(unseen) }) : t('systemLogs.latest') }}</button>
    </div>
    <footer class="system-logs-footer"><time :datetime="now.toISOString()" :title="t('systemLogs.localTime')"><i class="i-mdi-clock-outline" aria-hidden="true" />{{ currentTime }}</time><span v-if="trimmedCount" :title="t('systemLogs.trimmedHint')">{{ t('systemLogs.trimmed', { count: number(trimmedCount) }) }}</span><span :title="t('systemLogs.limitHint', { count: number(1000) })">{{ t(follow ? 'systemLogs.following' : 'systemLogs.reading') }}</span><label :title="t('systemLogs.followHint')"><input v-model="follow" type="checkbox" />{{ t('systemLogs.autoScroll') }}</label></footer>
  </section>
</template>
