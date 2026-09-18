<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from '@/components/PageBackButton.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { openLogsError } from '@/api/openLogs'
import { useOpenLogs } from './useOpenLogs'

const { t, locale } = useI18n()
const router = useRouter()
const { rows, history, connection, bufferRevision, trimmedCount, hasStreamGap, refreshHistory, reconnect, clear } = useOpenLogs()
const body = ref<HTMLElement>()
const autoScroll = ref(true)
const cleared = ref(false)
const now = ref(new Date())
let clock: ReturnType<typeof setInterval> | undefined
let disposed = false

const currentTime = computed(() => new Intl.DateTimeFormat(locale.value, {
  hour: '2-digit', minute: '2-digit', second: '2-digit',
}).format(now.value))
const connectionLabel = computed(() => history.loading ? t('openLogs.loadingHistory') : t(`openLogs.connection.${connection.value}`))
const canReconnect = computed(() => !history.loading && ['reconnecting', 'disconnected'].includes(connection.value))
const emptyText = computed(() => {
  if (history.loading) return t('openLogs.loadingHistory')
  if (cleared.value) return t('openLogs.cleared')
  if (history.problem) return t('openLogs.historyUnavailable')
  return t('openLogs.empty')
})

function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function errorText(cause: unknown) {
  const error = openLogsError(cause)
  return error.detail || t(`openLogs.errors.${error.key}`)
}
async function scrollToLatest() {
  await nextTick()
  if (!disposed && autoScroll.value && body.value) body.value.scrollTop = body.value.scrollHeight
}
function refresh() {
  cleared.value = false
  void refreshHistory()
}
async function clearScreen() {
  clear()
  cleared.value = true
  await nextTick()
  if (!disposed && body.value) body.value.scrollTop = 0
}
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push('/boot/dashboard')
}

watch([bufferRevision, autoScroll], scrollToLatest, { flush: 'post' })
onMounted(() => { clock = setInterval(() => { now.value = new Date() }, 1000) })
onBeforeUnmount(() => { disposed = true; clearInterval(clock) })
</script>

<template>
  <section class="open-logs-page">
    <div class="open-logs-toolbar">
      <PageBackButton @click="back" />
      <span class="open-logs-status" role="status">
        <i class="open-logs-status-dot" :class="history.loading ? 'connecting' : connection" aria-hidden="true" />
        {{ connectionLabel }}
      </span>
      <div class="open-logs-actions" data-page-error-anchor>
        <GhostBtn v-if="canReconnect" @click="reconnect"><i class="i-mdi-connection" aria-hidden="true" />{{ t('openLogs.reconnect') }}</GhostBtn>
        <GhostBtn :loading="history.loading" :title="t('openLogs.refreshHint')" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('openLogs.refreshHistory') }}</GhostBtn>
        <GhostBtn :title="t('openLogs.clearHint')" @click="clearScreen"><i class="i-mdi-broom" aria-hidden="true" />{{ t('openLogs.clear') }}</GhostBtn>
      </div>
    </div>

    <PageErrorNotice v-if="history.problem"><span>{{ errorText(history.problem) }} {{ t('openLogs.historyFailureHint') }}</span></PageErrorNotice>
    <div v-if="connection === 'unsupported'" class="open-logs-notice" role="status"><i class="i-mdi-information-outline" aria-hidden="true" /><span>{{ t('openLogs.unsupportedHint') }}</span></div>
    <div v-else-if="hasStreamGap" class="open-logs-notice" role="status"><i class="i-mdi-information-outline" aria-hidden="true" /><span>{{ t('openLogs.gapHint') }}</span></div>

    <div ref="body" class="open-logs-body" role="log" aria-live="off" :aria-label="t('openLogs.logArea')" :aria-busy="history.loading" tabindex="0">
      <p v-if="!rows.length" class="open-logs-empty" role="status">{{ emptyText }}</p>
      <div v-for="row in rows" :key="row.key" class="open-logs-line">
        <span class="open-logs-level" :class="row.level" :title="t(`openLogs.level.${row.level}`)"><span class="open-logs-sr-only">{{ t(`openLogs.level.${row.level}`) }}: </span></span>
        <span class="open-logs-text">{{ row.text }}</span>
      </div>
    </div>

    <div class="open-logs-footer">
      <div class="open-logs-footer-info">
        <time :datetime="now.toISOString()" :title="t('openLogs.localTime')"><i class="i-mdi-clock-outline" aria-hidden="true" />{{ currentTime }}</time>
        <span :title="t('openLogs.limitHint', { count: number(1000) })">{{ t('openLogs.count', { count: number(rows.length) }) }}</span>
        <span v-if="trimmedCount" :title="t('openLogs.trimmedHint')">{{ t('openLogs.trimmed', { count: number(trimmedCount) }) }}</span>
      </div>
      <label class="open-logs-auto-scroll"><input v-model="autoScroll" type="checkbox" />{{ t('openLogs.autoScroll') }}</label>
    </div>
  </section>
</template>

<style lang="scss" src="./open-logs.scss" />
