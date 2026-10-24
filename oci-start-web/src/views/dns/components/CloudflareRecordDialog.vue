<script setup lang="ts">
import { computed, reactive, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import {
  CLOUDFLARE_RECORD_TYPES, CLOUDFLARE_TTLS, cloudflareCanProxy,
  type CloudflareZone, type CloudflareRecord, type CloudflareRecordInput,
  type CloudflareMutationResult, type CloudflareApiError,
} from '@/api/cloudflare'

const props = defineProps<{
  operation: { kind: 'create' | 'edit' | 'delete' | 'sync'; zone: CloudflareZone; record: CloudflareRecord | null }
  pending: boolean
  outcome: 'idle' | 'success' | 'unknown' | 'failed'
  result: CloudflareMutationResult | null
  problem: CloudflareApiError | null
  readProblem: CloudflareApiError | null
}>()
const emit = defineEmits<{ close: []; submit: [input?: CloudflareRecordInput] }>()
const { t, locale } = useI18n()
const record = props.operation.record
const draft = reactive<CloudflareRecordInput>({
  type: record?.type ?? 'A', name: record?.name ?? '', content: record?.content ?? '',
  ttl: record ? record.ttl : 1, proxied: record ? record.proxied : false,
  priority: record ? record.priority : 0,
})
const editing = computed(() => props.operation.kind === 'edit')
const formOperation = computed(() => editing.value || props.operation.kind === 'create')
const finished = computed(() => props.outcome === 'success' || props.outcome === 'unknown')
const locked = computed(() => props.pending || finished.value)
const title = computed(() => t(`cloudflareDns.${props.operation.kind === 'create' ? 'add' : props.operation.kind}Title`))
const submitLabel = computed(() => t(`cloudflareDns.${props.operation.kind === 'create' ? 'add' : props.operation.kind === 'edit' ? 'save' : props.operation.kind === 'delete' ? 'confirmDelete' : 'confirmSync'}`))
const successText = computed(() => props.operation.kind === 'sync'
  ? t('cloudflareDns.syncSuccess', { count: props.result?.syncCount == null ? '—' : number(props.result.syncCount) })
  : t(`cloudflareDns.${props.operation.kind === 'edit' ? 'update' : props.operation.kind}Success`))
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function ttlLabel(value: number) {
  if (value === 1) return t('cloudflareDns.auto')
  if (value % 86400 === 0) return t('cloudflareDns.days', { count: number(value / 86400) })
  if (value % 3600 === 0) return t('cloudflareDns.hours', { count: number(value / 3600) })
  if (value % 60 === 0) return t('cloudflareDns.minutes', { count: number(value / 60) })
  return t('cloudflareDns.seconds', { count: number(value) })
}
function updatePriority(event: Event) {
  const value = (event.target as HTMLInputElement).value
  draft.priority = value === '' ? null : Number(value)
}
function updateProxy(event: Event) { draft.proxied = (event.target as HTMLInputElement).checked }
function updateTtl(value: unknown) { if (!locked.value && typeof value === 'number') draft.ttl = value }
function submit() { if (!locked.value && (!formOperation.value || draft.ttl != null)) emit('submit', formOperation.value ? { ...draft } : undefined) }
function clickSubmit() { if (!formOperation.value) submit() }
function close() { if (!props.pending) emit('close') }
function visibility(value: boolean) { if (!value) close() }
function beforeClose(done: () => void) { if (!props.pending) { emit('close'); done() } }
watch(() => draft.type, value => { if (!cloudflareCanProxy(value)) draft.proxied = false })
</script>

<template>
  <el-dialog :model-value="true" :title="title" width="580px" append-to-body :close-on-click-modal="false" :show-close="!pending" :close-on-press-escape="!pending" :before-close="beforeClose" class="cloudflare-record-dialog" @update:model-value="visibility">
    <div class="cloudflare-target"><span>{{ t('cloudflareDns.targetZone') }}</span><strong>{{ operation.zone.name }}</strong><template v-if="operation.record"><span>{{ t('cloudflareDns.targetRecord') }}</span><strong>{{ operation.record.type }} · {{ operation.record.name }}</strong></template></div>
    <form v-if="formOperation" id="cloudflare-record-form" class="cloudflare-record-form" @submit.prevent="submit">
      <div class="cloudflare-form-row">
        <div class="cloudflare-field"><label for="cloudflare-record-type">{{ t('cloudflareDns.type') }}</label>
          <input v-if="editing" id="cloudflare-record-type" :value="draft.type" class="cloudflare-input" readonly />
          <el-select v-else id="cloudflare-record-type" v-model="draft.type" class="cloudflare-select" :disabled="locked"><el-option v-for="type in CLOUDFLARE_RECORD_TYPES" :key="type" :value="type" :label="type" /></el-select>
        </div>
        <div class="cloudflare-field"><label for="cloudflare-record-ttl">{{ t('cloudflareDns.ttl') }}</label>
          <el-select id="cloudflare-record-ttl" :model-value="draft.ttl ?? undefined" class="cloudflare-select" :placeholder="t('cloudflareDns.selectTtl')" aria-required="true" :disabled="locked" @update:model-value="updateTtl">
            <el-option v-if="draft.ttl != null && !CLOUDFLARE_TTLS.some(value => value === draft.ttl)" :value="draft.ttl" :label="t('cloudflareDns.originalTtl', { value: ttlLabel(draft.ttl) })" />
            <el-option v-for="ttl in CLOUDFLARE_TTLS" :key="ttl" :value="ttl" :label="ttlLabel(ttl)" />
          </el-select>
        </div>
      </div>
      <label class="cloudflare-field"><span>{{ t('cloudflareDns.name') }}</span><input v-model="draft.name" class="cloudflare-input" :readonly="editing" :disabled="locked" required autocomplete="off" :spellcheck="false" /><small v-if="!editing">{{ t('cloudflareDns.rootHint') }}</small></label>
      <label class="cloudflare-field"><span>{{ t('cloudflareDns.content') }}</span><textarea v-model="draft.content" class="cloudflare-input cloudflare-content-input" :disabled="locked" :readonly="editing && record?.contentEditable === false" required rows="3" autocomplete="off" :spellcheck="false" /><small>{{ t(editing && record?.contentEditable === false ? 'cloudflareDns.structuredContentHint' : 'cloudflareDns.contentHint') }}</small></label>
      <label v-if="draft.type === 'MX'" class="cloudflare-field"><span>{{ t('cloudflareDns.priority') }}</span><input :value="draft.priority" type="number" min="0" max="65535" step="1" class="cloudflare-input" :disabled="locked" :required="!editing" @input="updatePriority" /><small>{{ t('cloudflareDns.priorityHint') }}</small></label>
      <div v-if="cloudflareCanProxy(draft.type)" class="cloudflare-field"><label class="cloudflare-checkbox"><input type="checkbox" :checked="draft.proxied === true" :indeterminate="draft.proxied == null" :disabled="locked" @change="updateProxy" />{{ t('cloudflareDns.enableProxy') }}</label><small>{{ t('cloudflareDns.proxyHint') }}</small></div>
    </form>
    <p v-else class="cloudflare-operation-hint">{{ t(operation.kind === 'delete' ? 'cloudflareDns.deleteHint' : 'cloudflareDns.syncHint') }}</p>
    <div v-if="pending" class="cloudflare-notice" role="status"><i class="i-mdi-loading animate-spin" aria-hidden="true" /><span>{{ t('cloudflareDns.submitting') }}</span></div>
    <div v-else-if="outcome === 'success'" class="cloudflare-notice is-success" role="status">{{ successText }}</div>
    <div v-else-if="outcome === 'unknown'" class="cloudflare-notice is-warning" role="alert">{{ t('cloudflareDns.writeUnknown') }}</div>
    <PageErrorNotice v-if="problem"><span>{{ t(`cloudflareDns.errors.${problem.key}`) }} {{ problem.detail }}</span></PageErrorNotice>
    <PageErrorNotice v-if="finished && readProblem">{{ t('cloudflareDns.refreshAfterWriteFailed') }}</PageErrorNotice>
    <template #footer>
      <GhostBtn :disabled="pending" @click="close">{{ t(finished ? 'cloudflareDns.close' : 'cloudflareDns.cancel') }}</GhostBtn>
      <PrimaryBtn v-if="!finished" :type="formOperation ? 'submit' : 'button'" :form="formOperation ? 'cloudflare-record-form' : undefined" :disabled="formOperation && draft.ttl == null" :loading="pending" :class="{ 'cloudflare-delete-button': operation.kind === 'delete' }" @click="clickSubmit">{{ submitLabel }}</PrimaryBtn>
    </template>
  </el-dialog>
</template>
