<script setup lang="ts">
import { computed, reactive } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import { EDGEONE_TTLS, type EdgeOneRecordInput, type EdgeOneMutationResult, type EdgeOneApiError } from '@/api/edgeone'
import type { EdgeOneOperation } from '../useEdgeOnePage'

const props = defineProps<{
  operation: EdgeOneOperation
  pending: boolean
  outcome: 'idle' | 'success' | 'unknown' | 'failed'
  result: EdgeOneMutationResult | null
  problem: EdgeOneApiError | null
  readProblem: EdgeOneApiError | null
}>()
const emit = defineEmits<{ close: []; submit: [input?: EdgeOneRecordInput] }>()
const { t, locale } = useI18n()
const record = props.operation.record
const originalTtl = record?.ttl ?? null
const keepTtlValue = 'keep-cloud-value'
const draft = reactive<EdgeOneRecordInput>({
  type: record?.type ?? '', name: record?.name ?? '', content: record?.content ?? '',
  ttl: record?.ttl ?? null, priority: record?.priority ?? null,
})
const editing = computed(() => props.operation.kind === 'edit')
const finished = computed(() => props.outcome === 'success' || props.outcome === 'unknown')
const locked = computed(() => props.pending || finished.value)
const title = computed(() => t(`edgeoneDns.${props.operation.kind}${props.operation.mode === 'domain' ? 'Domain' : ''}Title`))
const submitLabel = computed(() => t(`edgeoneDns.${editing.value ? 'save' : props.operation.kind === 'delete' ? 'confirmDelete' : 'confirmSync'}`))
const hint = computed(() => t(`edgeoneDns.${props.operation.kind}${props.operation.mode === 'domain' ? 'Domain' : ''}Hint`))
const successText = computed(() => props.operation.kind === 'sync'
  ? t('edgeoneDns.syncSuccess', { count: props.result?.syncCount == null ? '—' : number(props.result.syncCount) })
  : t(`edgeoneDns.${editing.value ? 'update' : props.operation.mode === 'domain' ? 'deleteDomain' : 'delete'}Success`))
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function ttlLabel(value: number) {
  if (value % 86400 === 0) return t('edgeoneDns.days', { count: number(value / 86400) })
  if (value % 3600 === 0) return t('edgeoneDns.hours', { count: number(value / 3600) })
  if (value % 60 === 0) return t('edgeoneDns.minutes', { count: number(value / 60) })
  return t('edgeoneDns.seconds', { count: number(value) })
}
function updatePriority(event: Event) {
  const value = (event.target as HTMLInputElement).value
  draft.priority = value === '' ? null : Number(value)
}
function updateTtl(value: unknown) {
  if (locked.value) return
  if (value === keepTtlValue && originalTtl == null) draft.ttl = null
  else if (typeof value === 'number') draft.ttl = value
}
function submit() { if (!locked.value) emit('submit', editing.value ? { ...draft } : undefined) }
function clickSubmit() { if (!editing.value) submit() }
function close() { if (!props.pending) emit('close') }
function visibility(value: boolean) { if (!value) close() }
</script>

<template>
  <el-dialog :model-value="true" :title="title" width="580px" append-to-body :close-on-click-modal="false" :show-close="!pending" :close-on-press-escape="!pending" :before-close="close" class="edgeone-record-dialog" @update:model-value="visibility">
    <div class="edgeone-target"><span>{{ t('edgeoneDns.targetZone') }}</span><strong>{{ operation.zone.name }}</strong><span>{{ t('edgeoneDns.recordMode') }}</span><strong>{{ t(`edgeoneDns.${operation.mode}`) }}</strong><template v-if="operation.record"><span>{{ t('edgeoneDns.targetRecord') }}</span><strong>{{ operation.mode === 'dns' ? `${operation.record.type} · ${operation.record.name}` : operation.record.name }}</strong></template></div>
    <form v-if="editing" id="edgeone-record-form" class="edgeone-record-form" @submit.prevent="submit">
      <div class="edgeone-form-row">
        <label class="edgeone-field"><span>{{ t('edgeoneDns.type') }}</span><input :value="draft.type" class="edgeone-input" readonly /></label>
        <div class="edgeone-field"><label for="edgeone-record-ttl">{{ t('edgeoneDns.ttl') }}</label>
          <el-select id="edgeone-record-ttl" :model-value="draft.ttl ?? keepTtlValue" class="edgeone-select" :disabled="locked" @update:model-value="updateTtl">
            <el-option v-if="originalTtl == null" :value="keepTtlValue" :label="t('edgeoneDns.keepCloudValue')" />
            <el-option v-if="originalTtl != null && !EDGEONE_TTLS.some(value => value === originalTtl)" :value="originalTtl" :label="t('edgeoneDns.originalTtl', { value: ttlLabel(originalTtl) })" />
            <el-option v-for="value in EDGEONE_TTLS" :key="value" :value="value" :label="ttlLabel(value)" />
          </el-select>
        </div>
      </div>
      <label class="edgeone-field"><span>{{ t('edgeoneDns.name') }}</span><input :value="draft.name" class="edgeone-input" readonly /></label>
      <label class="edgeone-field"><span>{{ t('edgeoneDns.content') }}</span><textarea v-model="draft.content" class="edgeone-input edgeone-content-input" :disabled="locked" required rows="3" autocomplete="off" :spellcheck="false" /><small>{{ t('edgeoneDns.contentHint') }}</small></label>
      <label v-if="draft.type === 'MX'" class="edgeone-field"><span>{{ t('edgeoneDns.priority') }}</span><input :value="draft.priority" type="number" min="0" max="65535" step="1" class="edgeone-input" :disabled="locked" :placeholder="t('edgeoneDns.keepCloudValue')" @input="updatePriority" /><small>{{ t('edgeoneDns.priorityHint') }}</small></label>
    </form>
    <template v-else><p class="edgeone-operation-hint">{{ hint }}</p><p v-if="operation.kind === 'sync'" class="edgeone-operation-hint">{{ t('edgeoneDns.syncLocalHint') }}</p></template>
    <div v-if="pending" class="edgeone-notice" role="status"><i class="i-mdi-loading animate-spin" aria-hidden="true" /><span>{{ t('edgeoneDns.submitting') }}</span></div>
    <div v-else-if="outcome === 'success'" class="edgeone-notice is-success" role="status">{{ successText }}</div>
    <div v-else-if="outcome === 'unknown'" class="edgeone-notice is-warning" role="alert">{{ t('edgeoneDns.writeUnknown') }}</div>
    <PageErrorNotice v-if="problem"><span>{{ t(`edgeoneDns.errors.${problem.key}`) }} {{ problem.detail }}</span></PageErrorNotice>
    <PageErrorNotice v-if="finished && readProblem">{{ t('edgeoneDns.refreshAfterWriteFailed') }}</PageErrorNotice>
    <template #footer>
      <GhostBtn :disabled="pending" @click="close">{{ t(finished ? 'edgeoneDns.close' : 'edgeoneDns.cancel') }}</GhostBtn>
      <PrimaryBtn v-if="!finished" :type="editing ? 'submit' : 'button'" :form="editing ? 'edgeone-record-form' : undefined" :loading="pending" :class="{ 'edgeone-delete-button': operation.kind === 'delete' }" @click="clickSubmit"><i :class="editing ? 'i-mdi-content-save-outline' : operation.kind === 'delete' ? 'i-mdi-trash-can-outline' : 'i-mdi-sync'" aria-hidden="true" />{{ submitLabel }}</PrimaryBtn>
    </template>
  </el-dialog>
</template>
