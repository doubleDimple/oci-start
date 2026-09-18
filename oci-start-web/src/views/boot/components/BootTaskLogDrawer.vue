<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { isBootTaskId } from '@/api/bootTasks'
import { checkSession } from '@/utils/session'
import GhostBtn from '@/components/GhostBtn.vue'

const props = defineProps<{ taskId: string; schedulerId: string }>()
const emit = defineEmits<{ close: [] }>()
const { t } = useI18n()
const state = ref<'connecting' | 'connected' | 'reconnecting' | 'disconnected'>('connecting')
const autoScroll = ref(true)
const lines = ref<{ key: number; text: string; level: string }[]>([])
const body = ref<HTMLElement>()
let sequence = 0
let connection: EventSource | undefined
let timer: ReturnType<typeof setTimeout> | undefined
let pending: { key: number; text: string; level: string }[] = []
let disposed = false
async function scroll() { await nextTick(); if (!disposed && autoScroll.value && body.value) body.value.scrollTop = body.value.scrollHeight }
function flush() { timer = undefined; lines.value = [...lines.value, ...pending].slice(-1000); pending = []; void scroll() }
function disconnect() { connection?.close(); connection = undefined; clearTimeout(timer); timer = undefined; pending = [] }
function connect() {
  disconnect()
  if (!isBootTaskId(props.taskId)) { state.value = 'disconnected'; return }
  state.value = 'connecting'
  // Cloud logs use the local Long; scheduler success/failure logs use the boot UUID.
  const ids = [props.taskId, props.schedulerId].filter(Boolean).map(value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
  const pattern = new RegExp(`(?:^|[^A-Za-z0-9_])taskid\\s*[=:：]\\s*(?:${ids.join('|')})(?![A-Za-z0-9_-])`, 'i')
  try {
    const active = new EventSource('/system/streamLogs?isBootLog=true')
    connection = active
    active.onopen = () => { if (!disposed && connection === active) state.value = 'connected' }
    active.onerror = () => {
      if (disposed || connection !== active) return
      void checkSession()
      state.value = active.readyState === EventSource.CLOSED ? 'disconnected' : 'reconnecting'
    }
    active.onmessage = event => {
      if (disposed || connection !== active || typeof event.data !== 'string' || !pattern.test(event.data)) return
      const level = /\[success\]/i.test(event.data) ? 'success' : /\[warn\]/i.test(event.data) ? 'warn' : /\[error\]/i.test(event.data) ? 'error' : 'default'
      pending.push({ key: sequence++, text: event.data.replace(/\[(success|warn|error)\]/gi, ''), level })
      if (pending.length > 1000) pending.splice(0, pending.length - 1000)
      if (!timer) timer = setTimeout(flush, 100)
    }
  } catch { state.value = 'disconnected' }
}
watch(autoScroll, scroll)
watch([() => props.taskId, () => props.schedulerId], () => { lines.value = []; connect() })
onMounted(connect)
onBeforeUnmount(() => { disposed = true; disconnect(); lines.value = [] })
</script>

<template>
  <el-drawer :model-value="true" :title="t('bootTasks.logs.title')" class="boot-task-logs" size="min(760px, 100vw)" append-to-body @close="emit('close')">
    <div class="log-content">
      <div class="toolbar"><strong>{{ t('bootTasks.logs.task', { id: taskId }) }}</strong><span role="status">{{ t(`bootTasks.logs.${state}`) }}</span><GhostBtn @click="connect">{{ t('bootTasks.logs.reconnect') }}</GhostBtn></div>
      <p class="note">{{ t('bootTasks.logs.hint') }}</p>
      <el-checkbox v-model="autoScroll">{{ t('bootTasks.logs.autoScroll') }}</el-checkbox>
      <div ref="body" class="log-body" role="log" aria-live="off" :aria-label="t('bootTasks.logs.task', { id: taskId })" tabindex="0">
        <p v-if="!lines.length" class="empty">{{ t('bootTasks.logs.empty') }}</p>
        <div v-for="line in lines" :key="line.key" class="line" :class="line.level">{{ line.text }}</div>
      </div>
    </div>
  </el-drawer>
</template>

<style scoped>
.log-content { display: flex; flex-direction: column; height: 100%; min-height: 0; color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); }
.toolbar { display: flex; gap: 14px; align-items: center; flex-wrap: wrap; }
.toolbar strong { font-size: var(--font-size-section); }
.toolbar span, .note { font-size: var(--font-size-secondary); color: var(--text-secondary); }
.log-body { flex: 1; min-height: 160px; overflow: auto; background: var(--bg-search); padding: 16px; border: 1px solid var(--border); border-radius: var(--r-sm); }
.line { white-space: pre-wrap; overflow-wrap: anywhere; font: var(--font-size-body)/1.6 var(--mono); padding: 3px 0; }
.line.success { color: var(--status-ok); }.line.warn { color: var(--status-warn); }.line.error { color: var(--status-danger); }
.empty { font: var(--font-size-secondary)/1.5 var(--sans); color: var(--text-secondary); }
:global(.boot-task-logs .el-drawer__title) { color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-dialog-title); font-weight: 600; }
:global(.boot-task-logs .el-drawer__header) { margin-bottom: 14px; }
:global(.boot-task-logs .el-drawer__body) { min-height: 0; }
</style>
