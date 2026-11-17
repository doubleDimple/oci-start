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

function guardClose(done: () => void) {
  if (!busy.value) done()
}
onBeforeUnmount(() => {
  disposed = true
  controller?.abort()
})
</script>

<template>
  <el-drawer
    :model-value="true"
    direction="rtl"
    size="min(560px, 94vw)"
    class="instance-network-drawer"
    append-to-body
    destroy-on-close
    :close-on-click-modal="!busy"
    :close-on-press-escape="true"
    :before-close="guardClose"
    @close="close"
  >
    <template #header>
      <div class="network-drawer-header">
        <span class="network-drawer-icon" aria-hidden="true">
          <i :class="action === 'ip' ? 'i-mdi-ip-network-outline' : 'i-mdi-web'" />
        </span>
        <div class="network-drawer-heading">
          <h2 class="network-drawer-title">{{ title }}</h2>
          <p class="network-drawer-subtitle">{{ row.displayName || row.instanceId }}</p>
        </div>
      </div>
    </template>

    <div class="network-drawer-body" :aria-busy="busy">
      <div class="network-instance">
        <span>{{ t('instanceNetwork.common.instance') }}</span>
        <strong>{{ row.displayName || row.instanceId }}</strong>
        <code v-if="row.instanceId">{{ row.instanceId }}</code>
      </div>
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
    </div>

    <template #footer>
      <div class="network-drawer-footer">
        <GhostBtn @click="close">{{ t(`instanceNetwork.common.${busy ? 'stopWaiting' : state === 'idle' ? 'cancel' : 'close'}`) }}</GhostBtn>
        <PrimaryBtn v-if="state === 'idle' || busy" :loading="busy" @click="submit">{{ t(`instanceNetwork.network.${action === 'ip' ? 'changeIp' : 'enableIpv6'}`) }}</PrimaryBtn>
      </div>
    </template>
  </el-drawer>
</template>

<style scoped>
:global(.instance-network-drawer) { --el-drawer-bg-color: var(--bg-card); background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
:global(.instance-network-drawer .el-drawer__header) { margin: 0; padding: 18px 20px 14px; border-bottom: 1px solid var(--border); color: var(--text-primary); align-items: flex-start; gap: 12px; }
:global(.instance-network-drawer .el-drawer__close-btn) { width: 36px; height: 36px; border-radius: var(--r-pill); color: var(--text-secondary); flex-shrink: 0; transition: background-color 180ms ease, color 180ms ease; }
:global(.instance-network-drawer .el-drawer__close-btn:is(:hover, :focus-visible)) { color: var(--brand); background: var(--bg-hover); }
:global(.instance-network-drawer .el-drawer__body) { min-height: 0; padding: 18px 20px; overflow-y: auto; overscroll-behavior: contain; scrollbar-gutter: stable; background: var(--bg-card); }
:global(.instance-network-drawer .el-drawer__footer) { padding: 0; border-top: 1px solid var(--border); background: var(--bg-card); }
.network-drawer-header { display: flex; align-items: center; gap: 12px; min-width: 0; }
.network-drawer-icon { width: 38px; height: 38px; border-radius: 10px; background: var(--brand-subtle); color: var(--brand); display: grid; place-items: center; font-size: 20px; flex-shrink: 0; }
.network-drawer-heading { min-width: 0; }
.network-drawer-title { margin: 0; font-size: var(--font-size-dialog-title); font-weight: 600; line-height: 1.35; color: var(--text-primary); }
.network-drawer-subtitle { margin: 2px 0 0; font-size: var(--font-size-secondary); color: var(--text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.network-drawer-body { display: flex; flex-direction: column; gap: 14px; }
.network-drawer-body :deep(.el-input), .network-drawer-body :deep(.el-alert__title) { font-size: var(--font-size-body); }
.network-instance { display: grid; gap: 6px; padding: 14px 16px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); }
.network-instance span, .network-note { font-size: var(--font-size-secondary); color: var(--text-secondary); line-height: 1.6; }
.network-instance strong { color: var(--text-primary); overflow-wrap: anywhere; }
.network-instance code { color: var(--text-secondary); font: var(--font-size-secondary)/1.6 var(--mono); overflow-wrap: anywhere; }
.network-note { margin: 0; }
.network-cidrs { display: flex; flex-direction: column; gap: 10px; padding: 14px 16px; border-radius: var(--r-card); border: 1px solid var(--border); background: var(--bg-card-subtle); }
.network-label { margin: 0; color: var(--text-primary); font-weight: 600; }
.network-cidr-row { display: flex; gap: 8px; }
.network-cidr-row .el-input { flex: 1; min-width: 0; }
.network-error { margin: 0; color: var(--status-danger); font-size: var(--font-size-secondary); }
.network-details { display: grid; grid-template-columns: minmax(100px, auto) 1fr; gap: 10px 16px; margin: 0; padding: 16px; border-radius: var(--r-sm); background: var(--bg-search); border: 1px solid var(--border); }
.network-details dt { color: var(--text-secondary); }
.network-details dd { margin: 0; color: var(--text-primary); overflow-wrap: anywhere; }
.network-drawer-footer { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 10px; padding: 12px 20px calc(12px + env(safe-area-inset-bottom)); }
@media (max-width: 760px) {
  :global(.instance-network-drawer .el-drawer__header) { padding: 16px 16px 14px; }
  :global(.instance-network-drawer .el-drawer__close-btn) { width: 44px; height: 44px; }
  :global(.instance-network-drawer .el-drawer__body) { padding: 14px 16px; }
  .network-drawer-footer { display: grid; grid-template-columns: repeat(auto-fit, minmax(0, 1fr)); gap: 10px; padding: 12px 16px calc(12px + env(safe-area-inset-bottom)); }
  .network-drawer-footer :deep(button) { width: 100%; min-height: 44px; }
}
@media (prefers-reduced-motion: reduce) {
  :global(.instance-network-drawer .el-drawer__close-btn) { transition: none; }
}
</style>
