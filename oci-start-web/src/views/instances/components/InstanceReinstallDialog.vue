<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, nextTick, onBeforeUnmount, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { useI18n } from 'vue-i18n'
import type { InstanceRow } from '@/api/instances'
import { tenantCsrfToken } from '@/api/tenant'
import { checkSession } from '@/utils/session'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'

interface OsOption { value: string; label: string }
interface OsGroup { label: string; other?: boolean; options: OsOption[] }
function versions(os: string, label: string, values: string[]): OsOption[] {
  return values.map((version) => ({ value: `${os}|${version}`, label: `${label} ${version}` }))
}
// Preserve the complete final inline-script catalog, including versionless systems.
const osGroups: OsGroup[] = [
  { label: 'Alpine', options: versions('alpine', 'Alpine', ['3.19', '3.20', '3.21', '3.22']) },
  { label: 'Debian', options: versions('debian', 'Debian', ['9', '10', '11', '12', '13']) },
  { label: 'Ubuntu', options: versions('ubuntu', 'Ubuntu', ['16.04', '18.04', '20.04', '22.04', '24.04', '25.10']) },
  { label: 'RHEL', options: [
    ...versions('centos', 'CentOS', ['9', '10']),
    ...versions('rocky', 'Rocky', ['8', '9', '10']),
    ...versions('almalinux', 'AlmaLinux', ['8', '9', '10']),
    ...versions('oracle', 'Oracle', ['8', '9', '10']),
    ...versions('fedora', 'Fedora', ['41', '42']),
  ] },
  { label: 'Other', other: true, options: [
    ...versions('anolis', 'Anolis', ['7', '8', '23']),
    ...versions('opencloudos', 'OpenCloudOS', ['8', '9']),
    ...versions('openeuler', 'OpenEuler', ['20.03', '22.03', '24.03', '25.09']),
    ...versions('opensuse', 'OpenSUSE', ['15.6', '16.0']),
    { value: 'opensuse|tumbleweed', label: 'OpenSUSE Tumbleweed' },
    ...versions('nixos', 'NixOS', ['25.05']),
    { value: 'kali|', label: 'Kali Linux' },
    { value: 'arch|', label: 'Arch Linux' },
    { value: 'gentoo|', label: 'Gentoo' },
    { value: 'aosc|', label: 'AOSC' },
    { value: 'fnos|', label: 'FNOS' },
    { value: 'netboot.xyz|', label: 'Netboot.xyz' },
  ] },
]

const props = defineProps<{ row: InstanceRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const { t } = useI18n()
const stage = ref<'form' | 'confirm' | 'running' | 'success' | 'failed' | 'unknown' | 'completed'>('form')
const selectedOs = ref('')
const password = ref('')
const validationKey = ref('')
const errorKey = ref('')
const serverError = ref('')
const hasSuccess = ref(false)
const logs = ref<string[]>([])
const logsTrimmed = ref(false)
const logArea = ref<HTMLElement | null>(null)
const osLabel = computed(() => osGroups.flatMap((group) => group.options).find((option) => option.value === selectedOs.value)?.label || '')
const isForm = computed(() => stage.value === 'form' || stage.value === 'confirm')
const statusText = computed(() => {
  if (stage.value === 'running') return t(`instanceNetwork.dd.${hasSuccess.value ? 'reported' : 'running'}`)
  if (stage.value === 'failed') return serverError.value || t('instanceNetwork.dd.failed')
  return t(`instanceNetwork.dd.${errorKey.value || stage.value}`)
})
let source: EventSource | undefined
let timeout: ReturnType<typeof setTimeout> | undefined
let flushTimer: ReturnType<typeof setTimeout> | undefined
let pending: string[] = []
let disposed = false
let closed = false
let submitted = false
let changedEmitted = false

function flushLogs() {
  clearTimeout(flushTimer)
  flushTimer = undefined
  if (disposed || !pending.length) return
  const followTail = !logArea.value || logArea.value.scrollHeight - logArea.value.scrollTop - logArea.value.clientHeight < 60
  const combined = [...logs.value, ...pending]
  pending = []
  let length = combined.reduce((total, line) => total + line.length, 0)
  while (combined.length > 1 && (combined.length > 600 || length > 250000)) {
    length -= combined.shift()!.length
    logsTrimmed.value = true
  }
  logs.value = combined
  if (followTail) void nextTick(() => {
    if (logArea.value) logArea.value.scrollTop = logArea.value.scrollHeight
  })
}

function appendLog(value: unknown) {
  if (typeof value !== 'string' || !value.trim() || disposed || closed) return
  pending.push(value)
  if (!flushTimer) flushTimer = setTimeout(flushLogs, 100)
}

function stopReading() {
  // This GET launches a destructive job. Always close before EventSource can retry.
  source?.close()
  source = undefined
  clearTimeout(timeout)
  timeout = undefined
  flushLogs()
}

function reportChange() {
  if (changedEmitted || disposed || closed) return
  changedEmitted = true
  emit('changed')
}

function finish(state: 'success' | 'failed' | 'unknown' | 'completed', key = '') {
  if (stage.value !== 'running' || disposed || closed) return
  stopReading()
  stage.value = state
  errorKey.value = key
  if (state === 'success') reportChange()
}

function review() {
  if (stage.value !== 'form' || submitted) return
  validationKey.value = !osLabel.value ? 'osRequired' : !password.value ? 'passwordRequired' : ''
  if (!validationKey.value) stage.value = 'confirm'
}

function start() {
  if (submitted || stage.value !== 'confirm' || disposed || closed) return
  submitted = true
  stage.value = 'running'
  const [osType = '', osVersion = ''] = selectedOs.value.split('|')
  const params = new URLSearchParams({
    instanceId: props.row.id,
    osType,
    osVersion,
    ddPassword: password.value,
  })
  const csrf = tenantCsrfToken()
  if (csrf) params.set('_csrf', csrf)
  try {
    const connection = new EventSource(`/oci/instance/quickDD?${params}`, { withCredentials: true })
    source = connection
    const active = () => source === connection && !disposed && !closed && stage.value === 'running'
    connection.addEventListener('log', (event) => {
      if (active()) appendLog((event as MessageEvent).data)
    })
    connection.addEventListener('success', (event) => {
      if (!active()) return
      appendLog((event as MessageEvent).data)
      // The first success may only say "reboot detected". Keep reading the final
      // server message; it describes command execution, not a verified OS install.
      hasSuccess.value = true
    })
    connection.addEventListener('complete', (event) => {
      if (!active()) return
      appendLog((event as MessageEvent).data)
      finish(hasSuccess.value ? 'success' : 'completed')
    })
    connection.addEventListener('error', (event) => {
      if (!active()) return
      void checkSession()
      // Native errors include normal EOF. Closing here also prevents automatic
      // reconnection, which would otherwise submit the same reinstall again.
      connection.close()
      const data: unknown = (event as MessageEvent).data
      if (typeof data === 'string') {
        appendLog(data)
        serverError.value = data
        finish('failed')
      } else {
        finish(hasSuccess.value ? 'success' : 'unknown')
      }
    })
    timeout = setTimeout(() => finish(hasSuccess.value ? 'success' : 'unknown', hasSuccess.value ? '' : 'timeout'), 60 * 60 * 1000)
  } catch {
    finish('unknown', 'connectionFailed')
  } finally {
    password.value = ''
  }
}

async function copyLogs() {
  flushLogs()
  try {
    await navigator.clipboard.writeText(logs.value.join('\n'))
    if (!disposed && !closed) ElMessage.success(t('instanceNetwork.dd.copied'))
  } catch {
    if (!disposed && !closed) ElMessage.error(t('instanceNetwork.dd.copyFailed'))
  }
}

function close() {
  if (closed) return
  stopReading()
  if (hasSuccess.value) reportChange()
  closed = true
  password.value = ''
  emit('close')
}

function guardClose(done: () => void) {
  if (stage.value !== 'running') done()
}

onBeforeUnmount(() => {
  stopReading()
  disposed = true
  clearTimeout(flushTimer)
  pending = []
  password.value = ''
})
</script>

<template>
  <el-drawer
    :model-value="true"
    direction="rtl"
    size="min(700px, 94vw)"
    class="instance-reinstall-drawer"
    append-to-body
    destroy-on-close
    :close-on-click-modal="stage !== 'running' && stage !== 'confirm'"
    :close-on-press-escape="stage !== 'running'"
    :before-close="guardClose"
    @close="close"
  >
    <template #header>
      <div class="reinstall-drawer-header">
        <span class="reinstall-drawer-icon" aria-hidden="true"><i class="i-mdi-restore" /></span>
        <div class="reinstall-drawer-heading">
          <h2 class="reinstall-drawer-title">{{ t('instanceNetwork.dd.title') }}</h2>
          <p class="reinstall-drawer-subtitle">{{ row.displayName || row.instanceId }}</p>
        </div>
      </div>
    </template>

    <div class="reinstall-drawer-body" :aria-busy="stage === 'running'">
      <div class="reinstall-instance">
        <span>{{ t('instanceNetwork.common.instance') }}</span>
        <strong>{{ row.displayName || row.instanceId }}</strong>
        <code v-if="row.instanceId">{{ row.instanceId }}</code>
      </div>

      <template v-if="stage === 'form'">
        <div class="reinstall-card">
          <el-form label-position="top" @submit.prevent="review">
            <el-form-item :label="t('instanceNetwork.dd.os')">
              <el-select v-model="selectedOs" filterable :placeholder="t('instanceNetwork.dd.selectOs')" :aria-label="t('instanceNetwork.dd.os')" popper-class="instance-reinstall-os-popper" @change="validationKey = ''">
                <el-option-group v-for="group in osGroups" :key="group.label" :label="group.other ? t('instanceNetwork.dd.otherOs') : group.label">
                  <el-option v-for="option in group.options" :key="option.value" :value="option.value" :label="option.label" />
                </el-option-group>
              </el-select>
            </el-form-item>
            <el-form-item :label="t('instanceNetwork.dd.password')" class="reinstall-last-item">
              <el-input v-model="password" type="password" show-password autocomplete="new-password" :placeholder="t('instanceNetwork.dd.passwordPlaceholder')" :aria-label="t('instanceNetwork.dd.password')" @input="validationKey = ''" />
            </el-form-item>
          </el-form>
        </div>
        <p v-if="validationKey" class="reinstall-error" role="alert">{{ t(`instanceNetwork.dd.${validationKey}`) }}</p>
        <p class="reinstall-note">{{ t('instanceNetwork.dd.scriptPrefix') }} <a href="https://github.com/bin456789/reinstall" target="_blank" rel="noopener noreferrer">reinstall</a> {{ t('instanceNetwork.dd.scriptSuffix') }}</p>
        <el-alert :title="t('instanceNetwork.dd.warning')" type="warning" :closable="false" show-icon />
      </template>

      <template v-else-if="stage === 'confirm'">
        <div class="reinstall-card">
          <h3 class="reinstall-confirm-title">{{ t('instanceNetwork.dd.confirmTitle') }}</h3>
          <dl class="reinstall-summary"><dt>{{ t('instanceNetwork.dd.os') }}</dt><dd>{{ osLabel }}</dd></dl>
        </div>
        <el-alert :title="t('instanceNetwork.dd.confirmWarning')" type="warning" :closable="false" show-icon />
      </template>

      <template v-else>
        <PageErrorNotice v-if="stage === 'failed'">{{ statusText }}</PageErrorNotice>
        <el-alert v-else :title="statusText" :type="stage === 'success' ? 'success' : stage === 'running' ? 'info' : 'warning'" :closable="false" show-icon />
        <div ref="logArea" class="reinstall-log" tabindex="0" role="log" aria-live="off" :aria-label="t('instanceNetwork.dd.logs')">
          <p v-if="!logs.length">{{ t('instanceNetwork.dd.waitingLogs') }}</p>
          <p v-for="(line, index) in logs" :key="index">{{ line }}</p>
        </div>
        <p v-if="logsTrimmed" class="reinstall-note">{{ t('instanceNetwork.dd.logsTrimmed') }}</p>
        <p class="reinstall-note">{{ t('instanceNetwork.dd.closeHint') }}</p>
      </template>
    </div>

    <template #footer>
      <div class="reinstall-drawer-footer">
        <GhostBtn v-if="logs.length" @click="copyLogs">{{ t('instanceNetwork.dd.copyLogs') }}</GhostBtn>
        <GhostBtn v-if="stage === 'confirm'" @click="stage = 'form'">{{ t('instanceNetwork.common.back') }}</GhostBtn>
        <GhostBtn @click="close">{{ stage === 'running' ? t('instanceNetwork.dd.stopReading') : t(`instanceNetwork.common.${isForm ? 'cancel' : 'close'}`) }}</GhostBtn>
        <PrimaryBtn v-if="stage === 'form'" @click="review">{{ t('instanceNetwork.dd.continue') }}</PrimaryBtn>
        <PrimaryBtn v-else-if="stage === 'confirm'" @click="start">{{ t('instanceNetwork.dd.start') }}</PrimaryBtn>
      </div>
    </template>
  </el-drawer>
</template>

<style scoped>
:global(.instance-reinstall-drawer) { --el-drawer-bg-color: var(--bg-card); background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.instance-reinstall-drawer .el-drawer__header) { margin: 0; padding: 18px 20px 14px; border-bottom: 1px solid var(--border); color: var(--text-primary); align-items: flex-start; gap: 12px; }
:global(.instance-reinstall-drawer .el-drawer__close-btn) { width: 36px; height: 36px; border-radius: var(--r-pill); color: var(--text-secondary); flex-shrink: 0; transition: background-color 180ms ease, color 180ms ease; }
:global(.instance-reinstall-drawer .el-drawer__close-btn:is(:hover, :focus-visible)) { color: var(--brand); background: var(--bg-hover); }
:global(.instance-reinstall-drawer .el-drawer__body) { min-height: 0; padding: 18px 20px; overflow-y: auto; overscroll-behavior: contain; scrollbar-gutter: stable; background: var(--bg-card); }
:global(.instance-reinstall-drawer .el-drawer__footer) { padding: 0; border-top: 1px solid var(--border); background: var(--bg-card); }
:global(.instance-reinstall-os-popper) { font-family: var(--sans); }
:global(.instance-reinstall-os-popper .el-select-dropdown__item) { font-size: var(--font-size-body); }
:global(.instance-reinstall-os-popper .el-select-group__title) { font-size: var(--font-size-secondary); }
.reinstall-drawer-header { display: flex; align-items: center; gap: 12px; min-width: 0; }
.reinstall-drawer-icon { width: 38px; height: 38px; border-radius: 10px; background: var(--brand-subtle); color: var(--brand); display: grid; place-items: center; font-size: 20px; flex-shrink: 0; }
.reinstall-drawer-heading { min-width: 0; }
.reinstall-drawer-title { margin: 0; font-size: var(--font-size-dialog-title); font-weight: 600; line-height: 1.35; color: var(--text-primary); }
.reinstall-drawer-subtitle { margin: 2px 0 0; font-size: var(--font-size-secondary); color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.reinstall-drawer-body { display: flex; flex-direction: column; gap: 14px; }
.reinstall-drawer-body :deep(.el-input), .reinstall-drawer-body :deep(.el-select), .reinstall-drawer-body :deep(.el-form-item__label), .reinstall-drawer-body :deep(.el-alert__title) { font-size: var(--font-size-body); }
.reinstall-drawer-body :deep(.el-select) { width: 100%; }
.reinstall-instance { display: grid; gap: 6px; padding: 14px 16px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); }
.reinstall-instance span, .reinstall-note { color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; }
.reinstall-instance strong { color: var(--text-primary); overflow-wrap: anywhere; }
.reinstall-instance code { color: var(--text-secondary); font: var(--font-size-secondary)/1.6 var(--mono); overflow-wrap: anywhere; }
.reinstall-card { padding: 16px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); }
.reinstall-last-item { margin-bottom: 0; }
.reinstall-note { margin: 0; }
.reinstall-note a { color: var(--brand); text-underline-offset: 3px; }
.reinstall-error { margin: 0; color: var(--status-danger); font-size: var(--font-size-secondary); }
.reinstall-confirm-title { font-size: var(--font-size-section); margin: 0 0 14px; }
.reinstall-summary { display: grid; grid-template-columns: auto 1fr; gap: 10px 16px; margin: 0; padding: 14px; background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--r-sm); }
.reinstall-summary dt { color: var(--text-secondary); }
.reinstall-summary dd { margin: 0; color: var(--text-primary); overflow-wrap: anywhere; }
.reinstall-log { min-height: 240px; max-height: calc(100dvh - 340px); overflow: auto; overscroll-behavior: contain; padding: 16px; border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg-search); color: var(--text-primary); font: var(--font-size-body)/1.7 var(--mono); white-space: pre-wrap; overflow-wrap: anywhere; }
.reinstall-log p { margin: 0 0 5px; }
.reinstall-log:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.reinstall-drawer-footer { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 10px; padding: 12px 20px calc(12px + env(safe-area-inset-bottom)); }
.reinstall-drawer-footer :deep(.el-button + .el-button) { margin-left: 0; }
@media (max-width: 760px) {
  :global(.instance-reinstall-drawer .el-drawer__header) { padding: 16px 16px 14px; }
  :global(.instance-reinstall-drawer .el-drawer__close-btn) { width: 44px; height: 44px; }
  :global(.instance-reinstall-drawer .el-drawer__body) { padding: 14px 16px; }
  .reinstall-card { padding: 14px; }
  .reinstall-drawer-footer { display: grid; grid-template-columns: repeat(auto-fit, minmax(0, 1fr)); gap: 10px; padding: 12px 16px calc(12px + env(safe-area-inset-bottom)); }
  .reinstall-drawer-footer :deep(button) { width: 100%; min-height: 44px; margin-left: 0; }
}
@media (prefers-reduced-motion: reduce) {
  :global(.instance-reinstall-drawer .el-drawer__close-btn) { transition: none; }
}
</style>
