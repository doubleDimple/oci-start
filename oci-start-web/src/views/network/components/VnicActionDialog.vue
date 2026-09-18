<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref, shallowRef, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import {
  runVnicAction, vnicError, isVnicWriteUncertain,
  type VnicAction, type VnicRow, type VnicMutationResult, type VnicApiError,
} from '@/api/vnic'

const props = defineProps<{
  modelValue: boolean
  instanceId: string
  action: VnicAction
  row: VnicRow | null
  primarySubnetId: string
  secondaryCount: number
  ipv6Address?: string
}>()
const emit = defineEmits<{
  'update:modelValue': [value: boolean]
  busy: [value: boolean]
  settled: [result: VnicMutationResult | null, error: VnicApiError | null]
}>()
const { t, n } = useI18n()
const compact = useCompactViewport()
interface Context {
  instanceId: string
  action: VnicAction
  row: VnicRow | null
  primarySubnetId: string
  secondaryCount: number
  ipv6Address: string
}
const context = shallowRef<Context | null>(null)
const phase = ref<'idle' | 'sending' | 'settled'>('idle')
const result = shallowRef<VnicMutationResult | null>(null)
const problem = shallowRef<VnicApiError | null>(null)
const subnetId = ref('')
const vnicCount = ref(1)
const ipv6PerVnic = ref(0)
const ipv6Count = ref(1)
const cidrs = ref([{ key: 0, value: '' }])
const acknowledged = ref(false)
const validation = ref('')
let cidrKey = 0
let disposed = false
const busy = computed(() => phase.value === 'sending')
const action = computed(() => context.value?.action || props.action)
const advanced = computed(() => ['configureLoadBalancer', 'restoreNetwork'].includes(action.value))
const needsAcknowledgement = computed(() => action.value === 'createIpv6' || advanced.value)
const acknowledgeKey = computed(() => action.value === 'createIpv6' ? 'rebootAcknowledge' : action.value === 'restoreNetwork' ? 'restoreAcknowledge' : 'configureAcknowledge')
const confirmationKey = computed(() => {
  switch (action.value) {
    case 'create': return 'confirmCreate'
    case 'createIpv6': return 'confirmIpv6'
    case 'delete': case 'deleteIpv6': case 'deleteAllSecondary': return 'confirmDelete'
    case 'changeIp': return 'confirmChangeIp'
    case 'configureLoadBalancer': return 'confirmConfigure'
    case 'restoreNetwork': return 'confirmRestore'
  }
})
const uncertain = computed(() => !!problem.value && isVnicWriteUncertain(problem.value))
const outcome = computed(() => problem.value ? uncertain.value ? 'unknown' : 'notSent' : result.value?.outcome || 'failed')
const message = computed(() => result.value?.message || problem.value?.detail || '')
const details = computed(() => result.value?.details || null)
const networkFields = computed(() => {
  const data = details.value
  if (data?.kind !== 'configureLoadBalancer') return []
  return [
    { key: 'natGatewayName', value: data.natGatewayName }, { key: 'natGatewayId', value: data.natGatewayId },
    { key: 'routeTableName', value: data.routeTableName }, { key: 'routeTableId', value: data.routeTableId },
    { key: 'networkLoadBalancerName', value: data.networkLoadBalancerName }, { key: 'networkLoadBalancerId', value: data.networkLoadBalancerId },
    { key: 'loadBalancerIp', value: data.nlpIpAddress },
  ]
})
const resultItems = computed(() => {
  const data = details.value
  if (data?.kind === 'create') return data.vnicResults.map(item => ({
    name: item.vnicDisplayName || item.vnicId || '—', identifier: item.vnicId,
    address: item.publicIp || item.privateIp, ipv6Addresses: item.ipv6Addresses, success: item.success, error: item.errorMessage,
  }))
  if (data?.kind === 'createIpv6') return data.results.map(item => ({
    name: item.ipv6Address || item.ipv6Id || '—', identifier: item.ipv6Id,
    address: '', ipv6Addresses: [] as string[], success: item.success, error: item.errorMessage,
  }))
  if (data?.kind === 'deleteAllSecondary') return data.results.map(item => ({
    name: item.vnicId, identifier: '', address: '', ipv6Addresses: [] as string[], success: item.success, error: '',
  }))
  return []
})
const mobileResultItems = computed(() => resultItems.value.map((item, index) => ({ ...item, recordKey: JSON.stringify([item.identifier || item.name, index]) })))

function reset() {
  if (busy.value) return
  context.value = {
    instanceId: props.instanceId, action: props.action,
    row: props.row ? { ...props.row, ipv6Addresses: [...props.row.ipv6Addresses] } : null,
    primarySubnetId: props.primarySubnetId, secondaryCount: props.secondaryCount,
    ipv6Address: props.ipv6Address || '',
  }
  phase.value = 'idle'
  result.value = null
  problem.value = null
  subnetId.value = props.primarySubnetId || ''
  vnicCount.value = ipv6Count.value = 1
  ipv6PerVnic.value = 0
  cidrs.value = [{ key: ++cidrKey, value: '' }]
  acknowledged.value = false
  validation.value = ''
}
function close() { if (!busy.value) emit('update:modelValue', false) }
function visibilityChanged(value: boolean) { if (!value) close() }
function addCidr() { if (phase.value === 'idle') cidrs.value.push({ key: ++cidrKey, value: '' }) }
function removeCidr(key: number) {
  if (phase.value !== 'idle') return
  cidrs.value = cidrs.value.filter(item => item.key !== key)
  if (!cidrs.value.length) cidrs.value = [{ key: ++cidrKey, value: '' }]
}
function ocid(value: string, kind: string) {
  return value.startsWith(`ocid1.${kind}.`) && value.length > `ocid1.${kind}.`.length
    && !/[\s\x00-\x1f\x7f]/.test(value)
}
function cidrValid(value: string) {
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d{1,2})$/.exec(value)
  return !!match && match.slice(1, 5).every(part => Number(part) <= 255) && Number(match[5]) <= 32
}
function invalid(key: string) { validation.value = key; return false }
function validate() {
  const target = context.value
  validation.value = ''
  if (!target || !ocid(target.instanceId, 'instance')) return invalid('instance')
  const rowActions: VnicAction[] = ['delete', 'createIpv6', 'deleteIpv6', 'changeIp']
  if (rowActions.includes(target.action) && (!target.row || !ocid(target.row.vnicId, 'vnic'))) return invalid('vnic')
  if (target.action === 'delete' && target.row?.isPrimary !== false) return invalid('primary')
  if (target.action === 'create') {
    if (!ocid(subnetId.value.trim(), 'subnet')) return invalid('subnet')
    if (!Number.isInteger(vnicCount.value) || vnicCount.value < 1 || vnicCount.value > 31) return invalid('vnicCount')
    if (!Number.isInteger(ipv6PerVnic.value) || ipv6PerVnic.value < 0 || ipv6PerVnic.value > 32) return invalid('ipv6PerVnic')
  }
  if (target.action === 'createIpv6' && (!Number.isInteger(ipv6Count.value) || ipv6Count.value < 1 || ipv6Count.value > 32)) return invalid('ipv6Count')
  if (target.action === 'deleteIpv6' && (!target.ipv6Address || !target.row?.ipv6Addresses.includes(target.ipv6Address))) return invalid('ipv6')
  if (target.action === 'deleteAllSecondary' && target.secondaryCount < 1) return invalid('secondary')
  if (target.action === 'changeIp' && cidrs.value.some(item => item.value.trim() && !cidrValid(item.value.trim()))) return invalid('cidr')
  if (needsAcknowledgement.value && !acknowledged.value) return invalid('acknowledge')
  return true
}
function perform(target: Context): Promise<VnicMutationResult> {
  switch (target.action) {
    case 'create': return runVnicAction('create', target.instanceId, {
      subnetId: subnetId.value.trim(), vnicCount: vnicCount.value, ipv6CountPerVnic: ipv6PerVnic.value,
    })
    case 'delete': return runVnicAction('delete', target.instanceId, { vnicId: target.row!.vnicId })
    case 'createIpv6': return runVnicAction('createIpv6', target.instanceId, { vnicId: target.row!.vnicId, ipv6Count: ipv6Count.value })
    case 'deleteIpv6': return runVnicAction('deleteIpv6', target.instanceId, { vnicId: target.row!.vnicId, ipv6Address: target.ipv6Address })
    case 'changeIp': return runVnicAction('changeIp', target.instanceId, { vnicId: target.row!.vnicId, cidrRanges: cidrs.value.map(item => item.value.trim()).filter(Boolean) })
    case 'deleteAllSecondary': return runVnicAction('deleteAllSecondary', target.instanceId, {})
    case 'configureLoadBalancer': return runVnicAction('configureLoadBalancer', target.instanceId, {})
    case 'restoreNetwork': return runVnicAction('restoreNetwork', target.instanceId, {})
  }
}
async function submit() {
  if (disposed || !props.modelValue || phase.value !== 'idle' || !validate()) return
  const target = context.value!
  phase.value = 'sending'
  emit('busy', true)
  try {
    const receipt = await perform(target)
    if (!disposed) result.value = receipt
  } catch (cause) {
    if (!disposed) problem.value = vnicError(cause)
  } finally {
    if (!disposed) {
      phase.value = 'settled'
      emit('busy', false)
      // The parent locks navigation during the write. The target snapshot also
      // prevents its subsequent list refresh from changing this receipt's row.
      if (props.instanceId === target.instanceId && props.action === target.action) emit('settled', result.value, problem.value)
    }
  }
}
watch(() => props.modelValue, value => { if (value) reset() }, { immediate: true })
watch([() => props.instanceId, () => props.action, () => props.row?.vnicId, () => props.ipv6Address], () => {
  if (props.modelValue && phase.value === 'idle') reset()
})
onBeforeUnmount(() => {
  disposed = true
  // Do not abort or claim to cancel an already-issued cloud mutation.
  if (busy.value) emit('busy', false)
})
</script>

<template>
  <el-dialog :model-value="modelValue || busy" :title="t(`vnicActions.titles.${action}`)" width="660px"
    class="vnic-action-dialog" append-to-body :close-on-click-modal="false"
    :close-on-press-escape="!busy" :show-close="!busy" @update:model-value="visibilityChanged">
    <template v-if="context">
      <dl class="vnic-action-target">
        <div><dt>{{ t('vnicActions.instance') }}</dt><dd>{{ context.instanceId || '—' }}</dd></div>
        <div v-if="context.row"><dt>{{ t('vnicActions.vnic') }}</dt><dd><span>{{ context.row.vnicDisplayName || '—' }}</span><span class="vnic-action-secondary">{{ context.row.vnicId }}</span></dd></div>
        <div v-if="action === 'deleteIpv6'"><dt>{{ t('vnicActions.ipv6Address') }}</dt><dd>{{ context.ipv6Address }}</dd></div>
        <div v-if="action === 'changeIp'"><dt>{{ t('vnicActions.currentIp') }}</dt><dd>{{ context.row?.publicIp || '—' }}</dd></div>
      </dl>
      <form v-if="phase !== 'settled'" id="vnic-action-form" class="vnic-action-form" @submit.prevent="submit">
        <fieldset :disabled="busy">
          <template v-if="action === 'create'">
            <label><span>{{ t('vnicActions.subnet') }}</span><input v-model="subnetId" autocomplete="off" spellcheck="false" /><small>{{ t('vnicActions.subnetHint') }}</small></label>
            <div class="vnic-action-numbers">
              <label><span>{{ t('vnicActions.vnicCount') }}</span><input v-model.number="vnicCount" type="number" min="1" max="31" step="1" /><small>{{ t('vnicActions.vnicCountHint') }}</small></label>
              <label><span>{{ t('vnicActions.ipv6PerVnic') }}</span><input v-model.number="ipv6PerVnic" type="number" min="0" max="32" step="1" /><small>{{ t('vnicActions.ipv6PerVnicHint') }}</small></label>
            </div>
            <p class="vnic-action-note">{{ t('vnicActions.createHint') }}</p>
          </template>
          <template v-else-if="action === 'createIpv6'">
            <label><span>{{ t('vnicActions.ipv6Count') }}</span><input v-model.number="ipv6Count" type="number" min="1" max="32" step="1" /><small>{{ t('vnicActions.ipv6CountHint') }}</small></label>
            <p class="vnic-action-warning">{{ t('vnicActions.rebootWarning') }}</p>
          </template>
          <p v-else-if="action === 'delete'" class="vnic-action-warning">{{ t('vnicActions.deleteHint') }}</p>
          <p v-else-if="action === 'deleteIpv6'" class="vnic-action-warning">{{ t('vnicActions.deleteIpv6Hint') }}</p>
          <p v-else-if="action === 'deleteAllSecondary'" class="vnic-action-warning">{{ t('vnicActions.deleteAllHint', { count: n(context.secondaryCount) }) }}</p>
          <template v-else-if="action === 'changeIp'">
            <p class="vnic-action-warning">{{ t('vnicActions.changeIpHint') }}</p>
            <div class="vnic-action-cidrs"><span>{{ t('vnicActions.cidr') }}</span>
              <div v-for="(cidr, index) in cidrs" :key="cidr.key" class="vnic-action-cidr"><input v-model="cidr.value" :aria-label="`${t('vnicActions.cidr')} ${index + 1}`" :placeholder="t('vnicActions.cidrPlaceholder')" autocomplete="off" spellcheck="false" /><button type="button" :title="t('vnicActions.removeCidr', { number: index + 1 })" :aria-label="t('vnicActions.removeCidr', { number: index + 1 })" @click="removeCidr(cidr.key)"><i class="i-mdi-close" aria-hidden="true" /></button></div>
              <GhostBtn :disabled="busy" @click="addCidr">{{ t('vnicActions.addCidr') }}</GhostBtn><small>{{ t('vnicActions.cidrHint') }}</small>
            </div>
          </template>
          <template v-else-if="advanced">
            <p class="vnic-action-warning">{{ t(action === 'restoreNetwork' ? 'vnicActions.restoreHint' : 'vnicActions.configureHint') }}</p>
            <p v-if="action === 'restoreNetwork'" class="vnic-action-warning">{{ t('vnicActions.restoreScope') }}</p>
            <p class="vnic-action-note">{{ t('vnicActions.advancedEligibility') }}</p>
          </template>
          <label v-if="needsAcknowledgement" class="vnic-action-check"><input v-model="acknowledged" type="checkbox" /><span>{{ t(`vnicActions.${acknowledgeKey}`) }}</span></label>
        </fieldset>
        <p v-if="validation" class="vnic-action-validation" role="alert">{{ t(`vnicActions.validation.${validation}`) }}</p>
      </form>
      <div v-if="busy" class="vnic-action-pending" role="status" aria-live="polite"><p>{{ t('vnicActions.sending') }}</p><p class="vnic-action-note">{{ t('vnicActions.sendingHint') }}</p></div>
      <div v-if="phase === 'settled'" class="vnic-action-result" aria-live="polite">
        <p class="vnic-action-outcome"><i :class="outcome === 'completed' ? 'i-mdi-check-circle-outline' : 'i-mdi-information-outline'" aria-hidden="true" />{{ t(`vnicActions.outcomes.${outcome}`) }}</p>
        <PageErrorNotice v-if="problem || (result && !result.success)"><p v-if="problem">{{ t(`vnicActions.errors.${problem.key}`) }}</p><p v-if="result && !result.success">{{ t('vnicActions.failedHint') }}</p><p v-if="message">{{ message }}</p><p v-if="action === 'create' && result && !result.success && !details">{{ t('vnicActions.createFailureHint') }}</p></PageErrorNotice>
        <p v-if="uncertain" class="vnic-action-warning">{{ t('vnicActions.unknownHint') }}</p>
        <p v-else-if="result?.outcome === 'partial'" class="vnic-action-warning">{{ t('vnicActions.partialHint') }}</p>
        <p v-else-if="result?.outcome === 'accepted'" class="vnic-action-note">{{ t('vnicActions.acceptedHint') }}</p>
        <p v-if="action === 'createIpv6'" class="vnic-action-note">{{ t('vnicActions.rebootReceipt') }}</p>
        <p v-if="advanced" class="vnic-action-note">{{ t('vnicActions.networkReceipt') }}</p>
        <div v-if="message && !problem && result?.success" class="vnic-action-original"><strong>{{ t('vnicActions.serverMessage') }}</strong><p>{{ message }}</p></div>
        <dl v-if="details?.kind === 'create'" class="vnic-action-counts">
          <div><dt>{{ t('vnicActions.requestedVnics') }}</dt><dd>{{ n(details.requestedVnicCount) }}</dd></div><div><dt>{{ t('vnicActions.createdVnics') }}</dt><dd>{{ n(details.successfulVnicCount) }}</dd></div><div><dt>{{ t('vnicActions.returnedIpv6PerVnic') }}</dt><dd>{{ n(details.requestedIpv6CountPerVnic) }}</dd></div><div><dt>{{ t('vnicActions.createdIpv6') }}</dt><dd>{{ n(details.totalIpv6Count) }}</dd></div>
        </dl>
        <dl v-if="details?.kind === 'changeIp'" class="vnic-action-target"><div><dt>{{ t('vnicActions.oldIp') }}</dt><dd>{{ details.oldIp || '—' }}</dd></div><div><dt>{{ t('vnicActions.newIp') }}</dt><dd>{{ details.newIp || '—' }}</dd></div></dl>
        <dl v-if="networkFields.length" class="vnic-action-target"><div v-for="field in networkFields" :key="field.key"><dt>{{ t(`vnicActions.${field.key}`) }}</dt><dd>{{ field.value || '—' }}</dd></div></dl>
        <MobileRecordList v-if="compact && modelValue && mobileResultItems.length" drilldown :list-id="`vnic-results-${context.instanceId}-${action}-${context.row?.vnicId || 'all'}`" :record-keys="mobileResultItems.map(item => item.recordKey)">
          <MobileRecordCard v-for="item in mobileResultItems" :key="item.recordKey" :record-key="item.recordKey" :summary-title="item.name" :summary-meta="item.address" :summary-status="t(item.success ? 'vnicActions.success' : 'vnicActions.failure')" :summary-tone="item.success ? 'success' : 'warning'">
            <template #identity><div class="mobile-record-title">{{ item.name }}</div><span v-if="item.identifier && item.identifier !== item.name" class="mobile-record-subtitle">{{ item.identifier }}</span></template>
            <dl class="mobile-record-fields"><div v-if="item.address" class="mobile-record-wide"><dt>{{ t('vnic.address') }}</dt><dd>{{ item.address }}</dd></div><div class="mobile-record-wide"><dt>{{ t('vnicActions.result') }}</dt><dd>{{ t(item.success ? 'vnicActions.success' : 'vnicActions.failure') }}</dd></div><div class="mobile-record-wide"><dt>{{ t('vnicActions.error') }}</dt><dd>{{ item.error || '—' }}</dd></div><div v-if="item.ipv6Addresses.length" class="mobile-record-wide"><dt>{{ t('vnicActions.returnedIpv6Addresses', { count: n(item.ipv6Addresses.length) }) }}</dt><dd><div v-for="(address, index) in item.ipv6Addresses" :key="index">{{ address }}</div></dd></div></dl>
          </MobileRecordCard>
        </MobileRecordList>
        <div v-else-if="!compact && resultItems.length" class="vnic-action-items"><table><thead><tr><th>{{ t('vnicActions.item') }}</th><th>{{ t('vnicActions.result') }}</th><th>{{ t('vnicActions.error') }}</th></tr></thead><tbody><tr v-for="(item, index) in resultItems" :key="index"><td><span>{{ item.name }}</span><small v-if="item.identifier && item.identifier !== item.name">{{ item.identifier }}</small><small v-if="item.address">{{ item.address }}</small><details v-if="item.ipv6Addresses.length" class="vnic-action-addresses"><summary>{{ t('vnicActions.returnedIpv6Addresses', { count: n(item.ipv6Addresses.length) }) }}</summary><ul><li v-for="(address, addressIndex) in item.ipv6Addresses" :key="addressIndex">{{ address }}</li></ul></details></td><td>{{ t(item.success ? 'vnicActions.success' : 'vnicActions.failure') }}</td><td>{{ item.error || '—' }}</td></tr></tbody></table></div>
        <p v-if="result && !details" class="vnic-action-note">{{ t('vnicActions.noDetails') }}</p>
      </div>
    </template>
    <template #footer><GhostBtn :disabled="busy" @click="close">{{ t(phase === 'idle' ? 'vnicActions.cancel' : 'vnicActions.close') }}</GhostBtn><PrimaryBtn v-if="phase !== 'settled'" type="submit" form="vnic-action-form" :loading="busy" :disabled="busy || (needsAcknowledgement && !acknowledged)">{{ t(`vnicActions.${confirmationKey}`) }}</PrimaryBtn></template>
  </el-dialog>
</template>

<style lang="scss">
.vnic-action-dialog {
  max-width: calc(100vw - 28px); color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans);
  .el-dialog__title { color: var(--text-primary); font: 600 var(--font-size-dialog-title)/1.4 var(--sans); }
  .el-dialog__body { max-height: 70vh; overflow: auto; color: var(--text-primary); font: inherit; }
  .el-dialog__footer { display: flex; justify-content: flex-end; align-items: center; flex-wrap: wrap; gap: 8px; border-top: 1px solid var(--border); }
  .btn { min-height: 36px; padding: 7px 12px; white-space: normal; }
  p { margin: 0; overflow-wrap: anywhere; }
  .vnic-action-target { display: grid; gap: 10px; margin: 0 0 18px; }
  .vnic-action-target > div { display: grid; grid-template-columns: minmax(100px, 28%) minmax(0, 1fr); gap: 12px; }
  dt { font-weight: 500; }
  dd { min-width: 0; margin: 0; overflow-wrap: anywhere; }
  dd > span { display: block; }
  .vnic-action-secondary, small, .vnic-action-note { color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; }
  .vnic-action-form fieldset { display: grid; gap: 16px; min-width: 0; margin: 0; border: 0; padding: 0; }
  .vnic-action-form label, .vnic-action-cidrs { display: flex; flex-direction: column; gap: 7px; min-width: 0; }
  .vnic-action-form input { box-sizing: border-box; min-width: 0; width: 100%; min-height: 36px; border: 1px solid var(--border-strong); border-radius: var(--r-sm); padding: 7px 10px; background: var(--bg-search); color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); }
  input::placeholder { color: var(--text-muted); }
  input:disabled { cursor: default; }
  input:focus-visible, button:focus-visible, summary:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
  .vnic-action-numbers { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
  .vnic-action-cidr { display: flex; align-items: center; gap: 8px; }
  .vnic-action-cidr button { flex: none; display: grid; place-items: center; width: 36px; height: 36px; border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg-card); color: var(--text-primary); cursor: pointer; }
  .vnic-action-cidr button:disabled { cursor: default; }
  .vnic-action-cidrs > .btn { align-self: flex-start; }
  .vnic-action-form .vnic-action-check { display: flex; flex-direction: row; align-items: flex-start; gap: 9px; }
  .vnic-action-check input { flex: none; width: 16px; min-height: 16px; height: 16px; margin: 3px 0 0; padding: 0; accent-color: var(--brand); }
  .vnic-action-warning { padding: 11px 12px; border-left: 3px solid var(--status-warn); border-radius: var(--r-sm); background: var(--status-warn-bg); color: var(--text-primary); }
  .vnic-action-validation { margin-top: 12px; color: var(--status-danger); }
  .vnic-action-pending { display: grid; gap: 6px; margin-top: 18px; padding-top: 14px; border-top: 1px solid var(--border); }
  .vnic-action-result { display: grid; gap: 14px; }
  .vnic-action-outcome { display: flex; align-items: center; gap: 8px; font-weight: 600; }
  .vnic-action-outcome > i { flex: none; font-size: 18px; }
  .vnic-action-original { display: grid; gap: 6px; }
  .vnic-action-original strong { font-weight: 500; }
  .vnic-action-original p { white-space: pre-wrap; }
  .vnic-action-counts { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin: 0; }
  .vnic-action-counts > div { display: grid; gap: 4px; padding: 10px 12px; border: 1px solid var(--border); border-radius: var(--r-sm); }
  .vnic-action-counts dt { font-size: var(--font-size-secondary); }
  .vnic-action-counts dd { font-variant-numeric: tabular-nums; }
  .vnic-action-items { overflow: auto; border: 1px solid var(--border); border-radius: var(--r-sm); }
  .vnic-action-items table { width: 100%; min-width: 450px; border-collapse: collapse; table-layout: fixed; color: var(--text-primary); font: inherit; text-align: left; }
  .vnic-action-items th { padding: 9px 10px; background: var(--bg-search); font-weight: 500; }
  .vnic-action-items td { padding: 10px; border-top: 1px solid var(--border); vertical-align: top; overflow-wrap: anywhere; }
  .vnic-action-items th:first-child { width: 42%; }
  .vnic-action-items th:nth-child(2) { width: 20%; }
  .vnic-action-items td > span, .vnic-action-items td > small { display: block; }
  .vnic-action-addresses { margin-top: 7px; }
  .vnic-action-addresses summary { cursor: pointer; }
  .vnic-action-addresses ul { display: grid; gap: 5px; margin: 8px 0 0; padding: 0; list-style: none; }
}
@media (max-width: 540px) {
  .vnic-action-dialog { .vnic-action-target > div, .vnic-action-numbers, .vnic-action-counts { grid-template-columns: minmax(0, 1fr); } .vnic-action-target > div { gap: 4px; } }
}
</style>
