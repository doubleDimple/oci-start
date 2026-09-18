<script setup lang="ts">
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
  <el-dialog
    :model-value="true" :title="t(`instanceOperations.titles.${action}`)" width="520px"
    align-center class="instance-operation-dialog" :close-on-click-modal="false"
    :close-on-press-escape="!working" :show-close="!working" @close="close"
  >
    <div class="operation-instance">
      <strong>{{ instanceName }}</strong>
      <span v-if="row.instanceId">{{ row.instanceId }}</span>
    </div>
    <el-alert
      v-if="['start', 'stop', 'terminate', 'delete'].includes(action)"
      :title="t(`instanceOperations.hints.${action}`)" :type="danger ? 'warning' : 'info'" :closable="false" show-icon
    />
    <el-form label-position="top" :disabled="locked" class="operation-form" @submit.prevent="submit">
      <template v-if="action === 'name'">
        <el-form-item :label="t('instanceOperations.fields.name')" for="instance-operation-name">
          <el-input id="instance-operation-name" v-model="name" :placeholder="t('instanceOperations.fields.namePlaceholder')" />
        </el-form-item>
        <p class="operation-note">{{ t('instanceOperations.hints.name') }}</p>
      </template>
      <el-form-item v-else-if="action === 'remark'" :label="t('instanceOperations.fields.remark')" for="instance-operation-remark">
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
        <p class="operation-note">{{ t('instanceOperations.hints.config') }}</p>
      </template>
      <template v-else-if="action === 'volume'">
        <p class="operation-current">{{ knownVolume ? t('instanceOperations.hints.currentVolume', { size: n(currentVolume ?? 0) }) : t('instanceOperations.hints.currentVolumeUnknown') }}</p>
        <el-form-item :label="t('instanceOperations.fields.volume')" for="instance-operation-volume">
          <el-input-number id="instance-operation-volume" v-model="volume" :min="47" :step="1" :precision="0" controls-position="right" />
        </el-form-item>
        <p class="operation-note">{{ t('instanceOperations.hints.volume') }}</p>
      </template>
      <template v-else-if="action === 'vpu'">
        <el-form-item :label="t('instanceOperations.fields.vpu')" for="instance-operation-vpu">
          <el-slider id="instance-operation-vpu" v-model="vpu" :min="0" :max="120" :step="10" show-input :aria-label="t('instanceOperations.fields.vpu')" />
        </el-form-item>
        <p class="operation-note">{{ t('instanceOperations.hints.vpu') }}</p>
      </template>
      <template v-else-if="action === 'terminate' && codeSent">
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
      </template>
    </el-form>
    <el-alert v-if="state === 'success'" :title="t(`instanceOperations.success.${action}`)" type="success" :closable="false" show-icon role="status" />
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
        <PrimaryBtn v-else :loading="working" :disabled="unchanged || (action === 'volume' && !knownVolume)" @click="submit">{{ actionLabel }}</PrimaryBtn>
      </template>
    </template>
  </el-dialog>
</template>

<style>
.instance-operation-dialog { max-width: calc(100vw - 32px); padding: 26px; font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
.instance-operation-dialog .el-dialog__title { font-size: var(--font-size-dialog-title); font-weight: 600; }
.instance-operation-dialog .el-form-item__label,
.instance-operation-dialog .el-input__inner,
.instance-operation-dialog .el-textarea__inner,
.instance-operation-dialog .el-button,
.instance-operation-dialog .el-alert__title { font-family: var(--sans); font-size: var(--font-size-body); }
.instance-operation-dialog .el-form-item__label { color: var(--text-primary); }
.instance-operation-dialog .el-alert__description { font-size: var(--font-size-secondary); }
.instance-operation-dialog .el-alert__content { min-width: 0; overflow-wrap: anywhere; }
.instance-operation-dialog .operation-instance { display: grid; gap: 6px; padding: 16px; margin-bottom: 20px; border-radius: 14px; background: var(--bg-search); overflow-wrap: anywhere; }
.instance-operation-dialog .operation-instance strong { font-size: var(--font-size-body); font-weight: 600; color: var(--text-primary); }
.instance-operation-dialog .operation-instance span { font-size: var(--font-size-secondary); color: var(--text-secondary); }
.instance-operation-dialog .operation-form { margin-top: 20px; }
.instance-operation-dialog .operation-form:empty { margin-top: 0; }
.instance-operation-dialog .operation-fields { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
.instance-operation-dialog .el-input-number { width: 100%; }
.instance-operation-dialog .el-slider__input { width: 108px; }
.instance-operation-dialog .operation-note { margin: 0 0 18px; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.65; }
.instance-operation-dialog .operation-current { margin: 0 0 16px; color: var(--text-primary); }
.instance-operation-dialog .operation-verification { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 10px; margin-bottom: 18px; }
.instance-operation-dialog .operation-verification .operation-note { flex: 1; min-width: 180px; margin: 0; }
.instance-operation-dialog .operation-verification .el-button { white-space: normal; text-align: left; }
.instance-operation-dialog .operation-error { color: var(--status-danger); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.instance-operation-dialog .operation-error p { margin: 8px 0 0; }
.instance-operation-dialog .el-dialog__footer { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; }
.instance-operation-dialog .el-dialog__footer button { white-space: normal; }
@media (max-width: 480px) {
  .instance-operation-dialog { padding: 22px; }
  .instance-operation-dialog .operation-fields { grid-template-columns: 1fr; gap: 0; }
}
</style>
