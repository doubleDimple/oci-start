<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { tenantCsrfToken, type TenantRow } from '@/api/tenant'

const props = defineProps<{ tenant: TenantRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const { t } = useI18n()
const state = ref<'idle' | 'running' | 'success' | 'error'>('idle')
const logs = ref<string[]>([])
const errorKey = ref('')
const errorText = ref('')
const message = computed(() => state.value === 'error'
  ? errorText.value || t(`tenant.update.${errorKey.value}`)
  : t(`tenant.update.${state.value}`))
const logArea = ref<HTMLElement | null>(null)
let source: EventSource | undefined
let flushTimer: ReturnType<typeof setTimeout> | undefined
let timeout: ReturnType<typeof setTimeout> | undefined
let pending: string[] = []
let disposed = false

function flush() {
  clearTimeout(flushTimer)
  flushTimer = undefined
  if (!pending.length || disposed) return
  const followTail =
    !logArea.value ||
    logArea.value.scrollHeight -
      logArea.value.scrollTop -
      logArea.value.clientHeight <
      50
  logs.value = [...logs.value, ...pending].slice(-300)
  pending = []
  if (followTail)
    void nextTick(() => {
      if (logArea.value) logArea.value.scrollTop = logArea.value.scrollHeight
    })
}
function append(line: string) {
  pending.push(line)
  if (!flushTimer) flushTimer = setTimeout(flush, 100)
}
function stop() {
  source?.close()
  source = undefined
  clearTimeout(timeout)
  flush()
}
function fail(key: string, text = '') {
  stop()
  state.value = 'error'
  errorKey.value = key
  errorText.value = text
}
function start() {
  if (state.value === 'running') return
  state.value = 'running'
  logs.value = []
  errorKey.value = ''
  errorText.value = ''
  const params = new URLSearchParams({
    tenantId: props.tenant.id,
    _csrf: tenantCsrfToken(),
  })
  try {
    source = new EventSource(`/tenants/updateTenant?${params}`, {
      withCredentials: true,
    })
    source.addEventListener('progress', (event) =>
      append((event as MessageEvent).data),
    )
    source.addEventListener('success', (event) => {
      append((event as MessageEvent).data || t('tenant.update.success'))
      stop()
      state.value = 'success'
      emit('changed')
    })
    source.addEventListener('error', (event) =>
      fail(
        'interrupted',
        (event as MessageEvent).data || '',
      ),
    )
    timeout = setTimeout(
      () => fail('timeout'),
      180000,
    )
  } catch {
    fail('connectionFailed')
  }
}
async function copyLogs() {
  try {
    await navigator.clipboard.writeText(logs.value.join('\n'))
    ElMessage.success(t('tenant.update.copied'))
  } catch {
    ElMessage.error(t('tenant.update.copyFailed'))
  }
}
function close() {
  stop()
  emit('close')
}
onBeforeUnmount(() => {
  stop()
  disposed = true
  clearTimeout(flushTimer)
  pending = []
})
</script>

<template>
  <el-dialog
    :model-value="true"
    :title="t('tenant.actions.update')"
    width="620px"
    align-center
    class="tenant-update-dialog"
    @close="close"
  >
    <div class="update-account">
      <span class="update-icon"><i class="i-mdi-sync" /></span>
      <div>
        <strong>{{ tenant.defName || t('tenant.update.currentTenant') }}</strong>
        <p>{{ message }}</p>
      </div>
      <i
        v-if="state === 'success'"
        class="i-mdi-check-circle-outline update-success"
      />
    </div>
    <div
      v-if="state !== 'idle'"
      ref="logArea"
      class="update-log"
      tabindex="0"
      :aria-label="t('tenant.update.logs')"
    >
      <p v-if="!logs.length">{{ t('tenant.update.connecting') }}</p>
      <p v-for="(line, index) in logs" :key="index">{{ line }}</p>
    </div>
    <p v-if="state === 'error'" class="update-error" role="alert">
      {{ message }}
    </p>
    <p v-if="state === 'running'" class="update-note">
      {{ t('tenant.update.closeHint') }}
    </p>
    <template #footer
      ><GhostBtn v-if="logs.length" @click="copyLogs">{{ t('tenant.update.copy') }}</GhostBtn
      ><GhostBtn @click="close">{{
        state === 'idle' ? t('tenant.common.cancel') : t('tenant.common.close')
      }}</GhostBtn
      ><PrimaryBtn v-if="state === 'idle'" @click="start">{{ t('tenant.update.start') }}</PrimaryBtn
      ><PrimaryBtn v-else-if="state === 'running'" loading
        >{{ t('tenant.update.busy') }}</PrimaryBtn
      ></template
    >
  </el-dialog>
</template>

<style>
.tenant-update-dialog {
  max-width: calc(100vw - 32px);
  padding: 26px;
}
.tenant-update-dialog .update-account {
  display: flex;
  align-items: center;
  gap: 14px;
  margin: 8px 0 24px;
}
.tenant-update-dialog .update-icon {
  display: grid;
  place-items: center;
  flex: none;
  width: 44px;
  height: 44px;
  border-radius: 14px;
  background: var(--status-ok-bg);
  color: var(--brand);
  font-size: 23px;
}
.tenant-update-dialog strong {
  font-weight: 600;
  color: var(--text-primary);
}
.tenant-update-dialog .update-account p {
  color: var(--text-secondary);
  font-size: 13px;
  margin: 5px 0 0;
}
.tenant-update-dialog .update-success {
  color: var(--brand);
  margin-left: auto;
  font-size: 24px;
}
.tenant-update-dialog .update-log {
  max-height: 300px;
  min-height: 160px;
  overflow: auto;
  padding: 16px;
  background: var(--bg-search);
  border-radius: 12px;
  font: 12px/1.7 var(--mono);
  color: var(--text-primary);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.tenant-update-dialog .update-log p {
  margin: 0 0 5px;
}
.tenant-update-dialog .update-error {
  color: var(--status-danger);
  font-size: 13px;
}
.tenant-update-dialog .update-note {
  color: var(--text-secondary);
  font-size: 12px;
}
.tenant-update-dialog .el-dialog__footer {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: flex-end;
}
</style>
