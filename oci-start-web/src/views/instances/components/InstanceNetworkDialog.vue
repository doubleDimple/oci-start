<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { InstanceRow } from '@/api/instances'
import { tenantError, tenantPost } from '@/api/tenant'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'

interface NetworkResult {
  status?: string
  message?: string
  details?: { oldIp?: string; newIp?: string; ipv6Address?: string }
}

const props = defineProps<{ row: InstanceRow; action: 'ip' | 'ipv6' }>()
const emit = defineEmits<{ close: []; changed: [] }>()
const { t } = useI18n()
const cidrs = ref([{ id: 0, value: '' }])
const state = ref<'idle' | 'running' | 'success' | 'error'>('idle')
const validationKey = ref('')
const errorKey = ref('')
const errorText = ref('')
const result = ref<NetworkResult | null>(null)
const busy = computed(() => state.value === 'running')
const title = computed(() => t(`instanceNetwork.network.${props.action === 'ip' ? 'ipTitle' : 'ipv6Title'}`))
const message = computed(() => {
  if (state.value === 'error') return errorText.value || t(`instanceNetwork.common.${errorKey.value}`)
  if (state.value === 'success') return result.value?.message || t(`instanceNetwork.network.${props.action === 'ip' ? 'ipSuccess' : 'ipv6Success'}`)
  return t(`instanceNetwork.network.${props.action === 'ip' ? 'runningIp' : 'runningIpv6'}`)
})
let nextId = 1
let controller: AbortController | undefined
let disposed = false
let closed = false

function validCidr(value: string) {
  const match = value.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d{1,2})$/)
  return !!match && match.slice(1, 5).every((part) => Number(part) <= 255) && Number(match[5]) <= 32
}

async function submit() {
  if (state.value !== 'idle' || disposed || closed) return
  const ranges = [...new Set(cidrs.value.map((item) => item.value.trim()).filter(Boolean))]
  validationKey.value = props.action === 'ip' && ranges.some((value) => !validCidr(value)) ? 'invalidCidr' : ''
  if (validationKey.value) return
  state.value = 'running'
  controller = new AbortController()
  try {
    // Both legacy endpoints call the local instance-detail ID "tenantId".
    // CIDR matching retries can last minutes; preserve the old unbounded request.
    const response = await tenantPost<NetworkResult>(
      props.action === 'ip' ? '/oci/changeSpecIp' : '/oci/enableIpv6',
      { tenantId: props.row.id, ...(props.action === 'ip' ? { cidrRanges: ranges } : {}) },
      { signal: controller.signal, timeout: 0 },
    )
    if (disposed || closed) return
    if (!response || response.status !== 'success') {
      errorText.value = typeof response?.message === 'string' ? response.message : ''
      errorKey.value = 'responseInvalid'
      state.value = 'error'
      return
    }
    result.value = response
    state.value = 'success'
    emit('changed')
  } catch (cause) {
    if (disposed || closed) return
    const body = (cause as { response?: { data?: unknown } })?.response?.data
    errorText.value = typeof body === 'string' && body.trim() ? body : tenantError(cause)
    errorKey.value = 'requestFailed'
    state.value = 'error'
  }
}

function close() {
  if (closed) return
  closed = true
  controller?.abort()
  emit('close')
}
onBeforeUnmount(() => {
  disposed = true
  controller?.abort()
})
</script>

<template>
  <el-dialog :model-value="true" :title="title" width="590px" align-center class="instance-network-dialog" :close-on-click-modal="false" @close="close">
    <div class="network-instance"><span>{{ t('instanceNetwork.common.instance') }}</span><strong>{{ row.displayName || row.instanceId }}</strong><code>{{ row.instanceId }}</code></div>
    <p class="network-note">{{ t(`instanceNetwork.network.${action === 'ip' ? 'ipDescription' : 'ipv6Description'}`) }}</p>
    <div v-if="action === 'ip'" class="network-cidrs">
      <p class="network-label">{{ t('instanceNetwork.network.cidr') }}</p>
      <div v-for="(item, index) in cidrs" :key="item.id" class="network-cidr-row">
        <el-input v-model="item.value" :disabled="state !== 'idle'" :placeholder="t('instanceNetwork.network.cidrPlaceholder')" :aria-label="t('instanceNetwork.network.cidrInput', { index: index + 1 })" @input="validationKey = ''" />
        <GhostBtn v-if="cidrs.length > 1" :disabled="state !== 'idle'" :aria-label="t('instanceNetwork.network.removeCidr', { index: index + 1 })" :title="t('instanceNetwork.network.removeCidr', { index: index + 1 })" @click="cidrs.splice(index, 1)"><i class="i-mdi-minus" aria-hidden="true" /></GhostBtn>
      </div>
      <GhostBtn :disabled="state !== 'idle'" @click="cidrs.push({ id: nextId++, value: '' })"><i class="i-mdi-plus" aria-hidden="true" />{{ t('instanceNetwork.network.addCidr') }}</GhostBtn>
      <p class="network-note">{{ t('instanceNetwork.network.cidrDescription') }}</p>
      <p v-if="validationKey" class="network-error" role="alert">{{ t(`instanceNetwork.network.${validationKey}`) }}</p>
    </div>
    <PageErrorNotice v-if="state === 'error'">{{ message }}</PageErrorNotice>
    <el-alert v-else-if="state !== 'idle'" :title="message" :type="state === 'success' ? 'success' : 'info'" :closable="false" show-icon />
    <dl v-if="result?.details" class="network-details">
      <template v-if="result.details.oldIp"><dt>{{ t('instanceNetwork.network.oldIp') }}</dt><dd>{{ result.details.oldIp }}</dd></template>
      <template v-if="result.details.newIp"><dt>{{ t('instanceNetwork.network.newIp') }}</dt><dd>{{ result.details.newIp }}</dd></template>
      <template v-if="result.details.ipv6Address"><dt>{{ t('instanceNetwork.network.ipv6Address') }}</dt><dd>{{ result.details.ipv6Address }}</dd></template>
    </dl>
    <p v-if="busy || state === 'error'" class="network-note">{{ t('instanceNetwork.common.pendingHint') }}</p>
    <template #footer>
      <GhostBtn @click="close">{{ t(`instanceNetwork.common.${busy ? 'stopWaiting' : state === 'idle' ? 'cancel' : 'close'}`) }}</GhostBtn>
      <PrimaryBtn v-if="state === 'idle' || busy" :loading="busy" @click="submit">{{ t(`instanceNetwork.network.${action === 'ip' ? 'changeIp' : 'enableIpv6'}`) }}</PrimaryBtn>
    </template>
  </el-dialog>
</template>

<style>
.instance-network-dialog { max-width: calc(100vw - 32px); padding: 26px; font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
.instance-network-dialog .el-dialog__title { font-size: var(--font-size-dialog-title); font-weight: 600; }
.instance-network-dialog .el-input, .instance-network-dialog .el-alert__title { font-size: var(--font-size-body); }
.instance-network-dialog .network-instance { display: grid; gap: 6px; margin-bottom: 18px; }
.instance-network-dialog .network-instance span, .instance-network-dialog .network-note { font-size: var(--font-size-secondary); color: var(--text-secondary); line-height: 1.6; }
.instance-network-dialog .network-instance strong { color: var(--text-primary); overflow-wrap: anywhere; }
.instance-network-dialog .network-instance code { color: var(--text-secondary); font: var(--font-size-secondary)/1.6 var(--sans); overflow-wrap: anywhere; }
.instance-network-dialog .network-note { margin: 12px 0; }
.instance-network-dialog .network-label { margin: 18px 0 10px; color: var(--text-primary); font-weight: 600; }
.instance-network-dialog .network-cidr-row { display: flex; gap: 8px; margin-bottom: 10px; }
.instance-network-dialog .network-cidr-row .el-input { flex: 1; min-width: 0; }
.instance-network-dialog .network-error { color: var(--status-danger); font-size: var(--font-size-secondary); }
.instance-network-dialog .network-details { display: grid; grid-template-columns: minmax(100px, auto) 1fr; gap: 10px 16px; padding: 16px; border-radius: var(--r-sm); background: var(--bg-search); }
.instance-network-dialog .network-details dt { color: var(--text-secondary); }
.instance-network-dialog .network-details dd { margin: 0; color: var(--text-primary); overflow-wrap: anywhere; }
.instance-network-dialog .el-dialog__footer { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; }
</style>
