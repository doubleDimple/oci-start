<script setup lang="ts">
import { allowsInstanceAction, hasTenantPermission, isManagedTenant } from '@/utils/tenantPermissions'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { InstanceRow } from '@/api/instances'
import { tenantError, tenantPost, tenantPut } from '@/api/tenant'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'

type Action = 'start' | 'stop' | 'terminate' | 'remark' | 'name' | 'config' | 'volume' | 'vpu' | 'delete'
interface OperationResponse { success?: boolean; status?: string; message?: string; msg?: string }

const props = defineProps<{ action: Action; row: InstanceRow }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const { t, n } = useI18n()
const busy = ref(false)
const sendingCode = ref(false)
const codeSent = ref(false)
const code = ref('')
const name = ref('')
const remark = ref('')
const cpu = ref<number | undefined>()
const memory = ref<number | undefined>()
const volume = ref<number | undefined>()
const vpu = ref(0)
const state = ref<'idle' | 'success' | 'failed' | 'uncertain'>('idle')
const errorKey = ref('')
const errorText = ref('')
const resendSeconds = ref(0)
let resendTimer: ReturnType<typeof setInterval> | undefined
let generation = 0
let disposed = false

const working = computed(() => busy.value || sendingCode.value)
const locked = computed(() => working.value || state.value === 'success' || state.value === 'uncertain')
const danger = computed(() => ['stop', 'terminate', 'delete'].includes(props.action))
const DRAWER_ACTION_ICONS: Record<string, string> = {
  name: 'i-mdi-pencil-outline',
  remark: 'i-mdi-note-edit-outline',
  config: 'i-mdi-chip',
  volume: 'i-mdi-harddisk',
  vpu: 'i-mdi-tune-vertical',
}
const drawerMode = computed(() => props.action in DRAWER_ACTION_ICONS)
const drawerIcon = computed(() => DRAWER_ACTION_ICONS[props.action] || 'i-mdi-tune')
const preserveBootVolume = computed(() => isManagedTenant(props.row.permissionContext)
  && !hasTenantPermission(props.row.permissionContext, 'BOOT_VOLUME_DELETE'))
const actionHintKey = computed(() => props.action === 'terminate' && preserveBootVolume.value ? 'terminatePreserveVolume' : props.action)
const instanceName = computed(() => props.row.displayName || props.row.instanceId || props.row.id)
const currentVolume = computed(() => props.row.bootVolumeSizeInGBs)
const knownVolume = computed(() => typeof currentVolume.value === 'number' && Number.isFinite(currentVolume.value) && currentVolume.value > 0)
const error = computed(() => errorKey.value ? t(`instanceOperations.errors.${errorKey.value}`) : errorText.value)
const actionLabel = computed(() => {
  if (props.action === 'terminate') return t(`instanceOperations.actions.${codeSent.value ? 'terminate' : 'sendCode'}`)
  if (props.action === 'volume') return t('instanceOperations.actions.expand')
  if (['start', 'stop', 'delete'].includes(props.action)) return t(`instanceOperations.actions.${props.action}`)
  return t('instanceOperations.actions.save')
})
const unchanged = computed(() => {
  switch (props.action) {
    case 'name': return name.value.trim() === props.row.displayName
    case 'remark': return remark.value === (props.row.remark || '')
    case 'config': return cpu.value === props.row.ocpus && memory.value === props.row.memoryInGBs
    case 'volume': return volume.value === currentVolume.value
    case 'vpu': return vpu.value === (props.row.vpusPerGB ?? 0)
    default: return false
  }
})

function reset() {
  generation++
  clearInterval(resendTimer)
  busy.value = false
  sendingCode.value = false
  codeSent.value = false
  code.value = ''
  name.value = props.row.displayName || ''
  remark.value = props.row.remark || ''
  cpu.value = props.row.ocpus ?? undefined
  memory.value = props.row.memoryInGBs ?? undefined
  volume.value = props.row.bootVolumeSizeInGBs ?? undefined
  vpu.value = props.row.vpusPerGB ?? 0
  state.value = 'idle'
  errorKey.value = ''
  errorText.value = ''
  resendSeconds.value = 0
}

function close() {
  if (working.value) return
  if (state.value === 'uncertain') emit('changed')
  emit('close')
}

function guardClose(done: () => void) {
  if (!working.value) done()
}

function accepted(result: OperationResponse | null | undefined) {
  // These legacy controllers return a boolean success field, unlike status-based OCI APIs.
  return result?.success === true && (!result.status || String(result.status).toLowerCase() === 'success')
}

function explicitlyFailed(cause: unknown) {
  const value = cause as { success?: unknown; status?: unknown; response?: { status?: number; data?: OperationResponse } }
  const body = value?.response?.data || value
  return body?.success === false || ['error', 'failed', 'failure'].includes(String(body?.status).toLowerCase()) ||
    [400, 401, 403, 404, 405, 409, 422].includes(value?.response?.status || 0)
}

function failValidation(key: string) {
  errorKey.value = key
  return false
}

function validate() {
  if (!props.row.id) return failValidation('missingId')
  if (props.action === 'name' && !name.value.trim()) return failValidation('name')
  if (props.action === 'terminate' && !/^\d{6}$/.test(code.value.trim())) return failValidation('code')
  if (props.action === 'config') {
    if (!Number.isInteger(cpu.value) || cpu.value! < 1 || cpu.value! > 24) return failValidation('cpu')
    if (!Number.isInteger(memory.value) || memory.value! < 1 || memory.value! > 256) return failValidation('memory')
  }
  if (props.action === 'volume') {
    if (!knownVolume.value) return failValidation('volumeUnknown')
    if (!Number.isSafeInteger(volume.value) || volume.value! < 47 || volume.value! <= currentVolume.value!) return failValidation('volume')
  }
  if (props.action === 'vpu') {
    if (!props.row.bootVolumeId || props.row.bootVolumeId === '-1' || !props.row.tenantId) return failValidation('missingVolume')
    if (!Number.isInteger(vpu.value) || vpu.value < 0 || vpu.value > 120 || vpu.value % 10 !== 0) return failValidation('vpu')
  }
  if (unchanged.value) return failValidation('unchanged')
  return true
}

function startCooldown() {
  clearInterval(resendTimer)
  resendSeconds.value = 60
  resendTimer = setInterval(() => {
    resendSeconds.value--
    if (resendSeconds.value <= 0) clearInterval(resendTimer)
  }, 1000)
}

async function sendCode() {
  if (!allowsInstanceAction(props.row.permissionContext, 'terminate')) return
  if (locked.value || resendSeconds.value) return
  errorKey.value = ''
  errorText.value = ''
  if (!props.row.id) { failValidation('missingId'); return }
  const current = generation
  sendingCode.value = true
  try {
    const result = await tenantPost<OperationResponse>('/oci/sendVerificationCode', { instanceId: props.row.id })
    if (disposed || current !== generation) return
    if (!accepted(result)) throw result || new Error()
    code.value = ''
    codeSent.value = true
    state.value = 'idle'
    startCooldown()
  } catch (cause) {
    if (disposed || current !== generation) return
    if (explicitlyFailed(cause)) errorText.value = tenantError(cause)
    else errorKey.value = 'codeFailed'
  } finally {
    if (!disposed && current === generation) sendingCode.value = false
  }
}

async function submit() {
  if (!allowsInstanceAction(props.row.permissionContext, props.action)) return
  if (locked.value) return
  if (props.action === 'terminate' && !codeSent.value) { await sendCode(); return }
  errorKey.value = ''
  errorText.value = ''
  if (!validate()) return
  const current = generation
  const action = props.action
  const row = props.row
  // instanceId is the local database ID in these controller contracts, not the OCI OCID.
  const payloads = {
    start: { instanceId: row.id }, stop: { instanceId: row.id },
    terminate: { instanceId: row.id, verificationCode: code.value.trim() },
    name: { instanceId: row.id, newName: name.value.trim() },
    remark: { instanceId: row.id, remark: remark.value },
    config: { instanceId: row.id, cpu: cpu.value, memory: memory.value },
    volume: { instanceId: row.id, bootVolumeSize: volume.value, expand: true },
    delete: { id: row.id },
  }
  const endpoints = {
    start: '/oci/startInstance', stop: '/oci/stopInstance', terminate: '/oci/terminateInstance',
    name: '/oci/updateName', remark: '/oci/updateRemark', config: '/oci/updateConfig',
    volume: '/oci/updateBootVolume', delete: '/oci/deleteInstanceRecord',
  }
  busy.value = true
  state.value = 'idle'
  try {
    const result = action === 'vpu'
      ? await tenantPut<OperationResponse>(`/tenants/update-volumes/${encodeURIComponent(row.bootVolumeId)}`, {
        vpusPerGB: vpu.value, tenantId: row.tenantId, instanceDetailId: row.id,
      }, { timeout: 120000 })
      : await tenantPost<OperationResponse>(endpoints[action], payloads[action], { timeout: 120000 })
    if (disposed || current !== generation) return
    if (!accepted(result)) throw result || new Error()
    state.value = 'success'
    code.value = ''
    emit('changed')
  } catch (cause) {
    if (disposed || current !== generation) return
    if (explicitlyFailed(cause)) {
      state.value = 'failed'
      errorText.value = tenantError(cause)
      if (!errorText.value) errorKey.value = 'failed'
    } else {
      // Do not offer another mutation while the server outcome is unknown.
      state.value = 'uncertain'
    }
  } finally {
    if (!disposed && current === generation) busy.value = false
  }
}

watch(() => [props.action, props.row.id], reset, { immediate: true })
onBeforeUnmount(() => { disposed = true; generation++; clearInterval(resendTimer) })
</script>

<template>
  <el-drawer
    v-if="drawerMode"
    :model-value="true"
    direction="rtl"
    size="min(540px, 94vw)"
    class="instance-operation-drawer"
    append-to-body
    destroy-on-close
    :close-on-click-modal="!working"
    :close-on-press-escape="!working"
    :show-close="!working"
    :before-close="guardClose"
    @close="close"
  >
    <template #header>
      <div class="operation-drawer-header">
        <span class="operation-drawer-icon" aria-hidden="true"><i :class="drawerIcon" /></span>
        <div class="operation-drawer-heading">
          <h2 class="operation-drawer-title">{{ t(`instanceOperations.titles.${action}`) }}</h2>
          <p class="operation-drawer-subtitle">{{ instanceName }}</p>
        </div>
      </div>
    </template>

    <div class="operation-drawer-body" :aria-busy="working">
      <div class="operation-instance">
        <strong>{{ instanceName }}</strong>
        <span v-if="row.instanceId">{{ row.instanceId }}</span>
      </div>
      <div class="operation-card">
        <el-form label-position="top" :disabled="locked" class="operation-form" @submit.prevent="submit">
          <button type="submit" class="drawer-hidden-submit" tabindex="-1" aria-hidden="true" />
          <template v-if="action === 'name'">
            <el-form-item :label="t('instanceOperations.fields.name')" for="instance-operation-name">
              <el-input id="instance-operation-name" v-model="name" :placeholder="t('instanceOperations.fields.namePlaceholder')" />
            </el-form-item>
            <p class="operation-note operation-last-note">{{ t('instanceOperations.hints.name') }}</p>
          </template>
          <el-form-item v-else-if="action === 'remark'" :label="t('instanceOperations.fields.remark')" for="instance-operation-remark" class="operation-last-item">
            <el-input id="instance-operation-remark" v-model="remark" type="textarea" :rows="4" :placeholder="t('instanceOperations.fields.remarkPlaceholder')" />
          </el-form-item>
          <template v-else-if="action === 'config'">
            <div class="operation-fields">
              <el-form-item :label="t('instanceOperations.fields.cpu')" for="instance-operation-cpu">
                <el-input-number id="instance-operation-cpu" v-model="cpu" :min="1" :max="24" :step="1" :precision="0" controls-position="right" />
              </el-form-item>
              <el-form-item :label="t('instanceOperations.fields.memory')" for="instance-operation-memory">
                <el-input-number id="instance-operation-memory" v-model="memory" :min="1" :max="256" :step="1" :precision="0" controls-position="right" />
              </el-form-item>
            </div>
            <p class="operation-note operation-last-note">{{ t('instanceOperations.hints.config') }}</p>
          </template>
          <template v-else-if="action === 'volume'">
            <p class="operation-current">{{ knownVolume ? t('instanceOperations.hints.currentVolume', { size: n(currentVolume ?? 0) }) : t('instanceOperations.hints.currentVolumeUnknown') }}</p>
            <el-form-item :label="t('instanceOperations.fields.volume')" for="instance-operation-volume">
              <el-input-number id="instance-operation-volume" v-model="volume" :min="47" :step="1" :precision="0" controls-position="right" />
            </el-form-item>
            <p class="operation-note operation-last-note">{{ t('instanceOperations.hints.volume') }}</p>
          </template>
          <template v-else-if="action === 'vpu'">
            <el-form-item :label="t('instanceOperations.fields.vpu')" for="instance-operation-vpu">
              <el-slider id="instance-operation-vpu" v-model="vpu" :min="0" :max="120" :step="10" show-input :aria-label="t('instanceOperations.fields.vpu')" />
            </el-form-item>
            <p class="operation-note operation-last-note">{{ t('instanceOperations.hints.vpu') }}</p>
          </template>
        </el-form>
      </div>
      <el-alert v-if="state === 'success'" :title="t(`instanceOperations.success.${actionHintKey}`)" type="success" :closable="false" show-icon role="status" />
      <el-alert v-else-if="state === 'uncertain'" :title="t('instanceOperations.hints.uncertain')" type="warning" :closable="false" show-icon role="alert" />
      <template v-else-if="error">
        <PageErrorNotice v-if="state === 'failed' || errorText">{{ error }}</PageErrorNotice>
        <div v-else class="operation-error" role="alert"><p>{{ error }}</p></div>
        <p v-if="state === 'failed'" class="operation-note">{{ t('instanceOperations.hints.failedCheck') }}</p>
      </template>
    </div>

    <template #footer>
      <div class="operation-drawer-footer">
        <GhostBtn :disabled="working" @click="close">{{ t(`instanceOperations.actions.${state === 'uncertain' ? 'refresh' : state === 'success' ? 'close' : 'cancel'}`) }}</GhostBtn>
        <PrimaryBtn v-if="state !== 'success' && state !== 'uncertain'" :loading="working" :disabled="unchanged || (action === 'volume' && !knownVolume)" @click="submit">{{ actionLabel }}</PrimaryBtn>
      </div>
    </template>
  </el-drawer>

  <el-dialog
    v-else
    :model-value="true" :title="t(`instanceOperations.titles.${action}`)" width="520px"
    align-center class="instance-operation-dialog" :close-on-click-modal="false"
    :close-on-press-escape="!working" :show-close="!working" @close="close"
  >
    <div class="operation-instance">
      <strong>{{ instanceName }}</strong>
      <span v-if="row.instanceId">{{ row.instanceId }}</span>
    </div>
    <el-alert
      :title="t(`instanceOperations.hints.${actionHintKey}`)" :type="danger ? 'warning' : 'info'" :closable="false" show-icon
    />
    <el-form v-if="action === 'terminate' && codeSent" label-position="top" :disabled="locked" class="operation-form" @submit.prevent="submit">
      <p class="operation-note">{{ t('instanceOperations.hints.codeRequested') }}</p>
      <el-form-item :label="t('instanceOperations.fields.code')" for="instance-operation-code">
        <el-input id="instance-operation-code" v-model="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" :placeholder="t('instanceOperations.fields.codePlaceholder')" />
      </el-form-item>
      <div class="operation-verification">
        <p class="operation-note">{{ t('instanceOperations.hints.code') }}</p>
        <el-button link :loading="sendingCode" :disabled="locked || resendSeconds > 0" @click="sendCode">
          {{ resendSeconds ? t('instanceOperations.actions.resendAfter', { seconds: resendSeconds }) : t('instanceOperations.actions.resend') }}
        </el-button>
      </div>
    </el-form>
    <el-alert v-if="state === 'success'" :title="t(`instanceOperations.success.${actionHintKey}`)" type="success" :closable="false" show-icon role="status" />
    <el-alert v-else-if="state === 'uncertain'" :title="t('instanceOperations.hints.uncertain')" type="warning" :closable="false" show-icon role="alert" />
    <template v-else-if="error">
      <PageErrorNotice v-if="state === 'failed' || errorText || errorKey === 'codeFailed'">{{ error }}</PageErrorNotice>
      <div v-else class="operation-error" role="alert"><p>{{ error }}</p></div>
      <p v-if="state === 'failed'" class="operation-note">{{ t('instanceOperations.hints.failedCheck') }}</p>
    </template>
    <template #footer>
      <GhostBtn :disabled="working" @click="close">{{ t(`instanceOperations.actions.${state === 'uncertain' ? 'refresh' : state === 'success' ? 'close' : 'cancel'}`) }}</GhostBtn>
      <template v-if="state !== 'success' && state !== 'uncertain'">
        <GhostBtn v-if="danger" danger :loading="working" :disabled="unchanged" @click="submit">{{ actionLabel }}</GhostBtn>
        <PrimaryBtn v-else :loading="working" :disabled="unchanged" @click="submit">{{ actionLabel }}</PrimaryBtn>
      </template>
    </template>
  </el-dialog>
</template>

<style scoped>
:global(.instance-operation-drawer) { --el-drawer-bg-color: var(--bg-card); background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.instance-operation-drawer .el-drawer__header) { margin: 0; padding: 18px 20px 14px; border-bottom: 1px solid var(--border); color: var(--text-primary); align-items: flex-start; gap: 12px; }
:global(.instance-operation-drawer .el-drawer__close-btn) { width: 36px; height: 36px; border-radius: var(--r-pill); color: var(--text-secondary); flex-shrink: 0; transition: background-color 180ms ease, color 180ms ease; }
:global(.instance-operation-drawer .el-drawer__close-btn:is(:hover, :focus-visible)) { color: var(--brand); background: var(--bg-hover); }
:global(.instance-operation-drawer .el-drawer__body) { min-height: 0; padding: 18px 20px; overflow-y: auto; overscroll-behavior: contain; scrollbar-gutter: stable; background: var(--bg-card); }
:global(.instance-operation-drawer .el-drawer__footer) { padding: 0; border-top: 1px solid var(--border); background: var(--bg-card); }
.operation-drawer-header { display: flex; align-items: center; gap: 12px; min-width: 0; }
.operation-drawer-icon { width: 38px; height: 38px; border-radius: 10px; background: var(--brand-subtle); color: var(--brand); display: grid; place-items: center; font-size: 20px; flex-shrink: 0; }
.operation-drawer-heading { min-width: 0; }
.operation-drawer-title { margin: 0; font-size: var(--font-size-dialog-title); font-weight: 600; line-height: 1.35; color: var(--text-primary); }
.operation-drawer-subtitle { margin: 2px 0 0; font-size: var(--font-size-secondary); color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.operation-drawer-body { display: flex; flex-direction: column; gap: 14px; }
.operation-card { padding: 16px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); }
.operation-card .operation-form { margin-top: 0; }
.operation-last-item { margin-bottom: 0; }
.operation-last-note { margin-bottom: 0 !important; }
.drawer-hidden-submit { position: absolute; width: 0; height: 0; padding: 0; border: 0; opacity: 0; pointer-events: none; }
.operation-drawer-footer { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 10px; padding: 12px 20px calc(12px + env(safe-area-inset-bottom)); }
.operation-drawer-footer :deep(.el-button + .el-button) { margin-left: 0; }
:global(.instance-operation-dialog) { max-width: calc(100vw - 32px); padding: 26px; font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
:global(.instance-operation-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); font-weight: 600; }
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-form-item__label),
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-input__inner),
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-textarea__inner),
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-button),
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-alert__title) { font-family: var(--sans); font-size: var(--font-size-body); }
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-form-item__label) { color: var(--text-primary); }
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-alert__description) { font-size: var(--font-size-secondary); }
:global(:is(.instance-operation-dialog, .instance-operation-drawer) .el-alert__content) { min-width: 0; overflow-wrap: anywhere; }
.operation-instance { display: grid; gap: 6px; padding: 14px 16px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); overflow-wrap: anywhere; }
:global(.instance-operation-dialog .operation-instance) { margin-bottom: 20px; border: 0; background: var(--bg-search); }
.operation-instance strong { font-size: var(--font-size-body); font-weight: 600; color: var(--text-primary); }
.operation-instance span { font-size: var(--font-size-secondary); color: var(--text-secondary); }
.operation-form { margin-top: 20px; }
.operation-form:empty { margin-top: 0; }
.operation-fields { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.operation-form :deep(.el-input-number) { width: 100%; }
.operation-form :deep(.el-slider__input) { width: 108px; }
.operation-note { margin: 0 0 18px; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.65; }
.operation-current { margin: 0 0 16px; color: var(--text-primary); }
.operation-verification { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 10px; margin-bottom: 18px; }
.operation-verification .operation-note { flex: 1; min-width: 180px; margin: 0; }
.operation-verification .el-button { white-space: normal; text-align: left; }
.operation-error { color: var(--status-danger); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.operation-error p { margin: 8px 0 0; }
:global(.instance-operation-dialog .el-dialog__footer) { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; }
:global(.instance-operation-dialog .el-dialog__footer button) { white-space: normal; }
@media (max-width: 760px) {
  :global(.instance-operation-drawer .el-drawer__header) { padding: 16px 16px 14px; }
  :global(.instance-operation-drawer .el-drawer__close-btn) { width: 44px; height: 44px; }
  :global(.instance-operation-drawer .el-drawer__body) { padding: 14px 16px; }
  .operation-card { padding: 14px; }
  .operation-drawer-footer { display: grid; grid-template-columns: repeat(auto-fit, minmax(0, 1fr)); gap: 10px; padding: 12px 16px calc(12px + env(safe-area-inset-bottom)); }
  .operation-drawer-footer :deep(button) { width: 100%; min-height: 44px; margin-left: 0; }
}
@media (max-width: 480px) {
  :global(.instance-operation-dialog) { padding: 22px; }
  .operation-fields { grid-template-columns: 1fr; gap: 0; }
}
@media (prefers-reduced-motion: reduce) {
  :global(.instance-operation-drawer .el-drawer__close-btn) { transition: none; }
}
</style>
