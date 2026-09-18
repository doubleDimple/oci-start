<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { bootTaskError, getBootTaskBatchCount, performBootTaskAction, validBootTaskEdit, type BootTaskAction, type BootTaskDetail, type BootTaskEdit, type BootTaskError, type BootTaskGroup } from '@/api/bootTasks'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'

const props = defineProps<{ action: BootTaskAction; target?: BootTaskGroup | BootTaskDetail }>()
const emit = defineEmits<{ close: []; changed: []; busy: [value: boolean] }>()
const { t, locale } = useI18n()
const state = ref<'ready' | 'submitting' | 'success' | 'failed' | 'uncertain'>('ready')
const preflight = ref(false)
const eligible = ref<string | null>(null)
const problem = ref<BootTaskError | null>(null)
const validation = ref(false)
const source = props.target && 'rootPassword' in props.target ? props.target : undefined
const form = reactive({ ocpu: source?.ocpu, memory: source?.memory, disk: source?.disk, loopTime: source?.loopTime, rootPassword: source?.rootPassword || '', dayGap: source?.dayGap || '' })
const controller = new AbortController()
let disposed = false
const editing = computed(() => props.action === 'edit')
const counting = computed(() => props.action === 'batchStart' || props.action === 'batchStop')
const busy = computed(() => state.value === 'submitting' || preflight.value)
const finished = computed(() => ['success', 'failed', 'uncertain'].includes(state.value))
const danger = computed(() => ['stop', 'delete', 'batchStop', 'resetFailures', 'detailStop', 'detailDelete'].includes(props.action))
const error = computed(() => validation.value ? t('bootTasks.edit.validation') : problem.value ? problem.value.detail || t(`bootTasks.errors.${problem.value.key}`) : '')
const unchanged = computed(() => source && form.ocpu === source.ocpu && form.memory === source.memory && form.disk === source.disk && form.loopTime === source.loopTime && form.rootPassword === source.rootPassword && form.dayGap.trim() === source.dayGap)
const canSubmit = computed(() => !busy.value && !finished.value && (!counting.value || (eligible.value !== null && eligible.value !== '0')) && (!editing.value || !unchanged.value))
const formattedCount = computed(() => eligible.value === null ? '—' : new Intl.NumberFormat(locale.value === 'zh' ? 'zh-CN' : 'en-US').format(BigInt(eligible.value)))

async function countTasks() {
  if (preflight.value || (props.action !== 'batchStart' && props.action !== 'batchStop')) return
  preflight.value = true
  eligible.value = null
  problem.value = null
  try { eligible.value = await getBootTaskBatchCount(props.action, controller.signal) }
  catch (cause) { if (!disposed && !controller.signal.aborted) problem.value = bootTaskError(cause) }
  finally { if (!disposed) preflight.value = false }
}
async function submit() {
  if (!canSubmit.value) return
  validation.value = false
  const input: BootTaskEdit | undefined = editing.value ? {
    id: props.target?.id || '', ocpu: form.ocpu!, memory: form.memory!, disk: form.disk!, loopTime: form.loopTime!, rootPassword: form.rootPassword, dayGap: form.dayGap.trim(),
  } : undefined
  if (input && !validBootTaskEdit(input)) { validation.value = true; return }
  problem.value = null
  state.value = 'submitting'
  emit('busy', true)
  try {
    await performBootTaskAction(props.action, props.target?.id, input)
    if (!disposed) state.value = 'success'
  } catch (cause) {
    if (!disposed) {
      problem.value = bootTaskError(cause)
      state.value = problem.value.explicit ? 'failed' : 'uncertain'
    }
  } finally {
    if (!disposed) {
      form.rootPassword = ''
      emit('busy', false)
      // Failures may follow partial group/batch work. Refresh for every attempted mutation.
      emit('changed')
    }
  }
}
function close() { if (state.value !== 'submitting') emit('close') }
onMounted(countTasks)
onBeforeUnmount(() => { disposed = true; controller.abort(); form.rootPassword = '' })
</script>

<template>
  <el-dialog :model-value="true" :title="t(`bootTasks.actions.${action}`)" class="boot-task-action" width="min(620px, calc(100vw - 28px))" append-to-body :close-on-click-modal="false" :close-on-press-escape="!busy" :show-close="!busy" @close="close">
    <div class="action-content">
      <p v-if="target" class="target">{{ t('bootTasks.target', { id: target.id, architecture: target.architecture }) }}</p>
      <p class="explanation">{{ t(`bootTasks.confirmText.${action}`) }}</p>
      <div v-if="counting" class="count" aria-live="polite">
        <p>{{ preflight ? t('bootTasks.loading') : t('bootTasks.globalCount', { count: formattedCount }) }}</p>
        <p class="note">{{ eligible === '0' ? t('bootTasks.noEligible') : t('bootTasks.countHint') }}</p>
      </div>
      <el-form v-if="editing && !finished" label-position="top" :disabled="busy" @submit.prevent="submit">
        <div class="fields">
          <el-form-item v-for="field in (['ocpu', 'memory', 'disk', 'loopTime'] as const)" :key="field" :label="t(`bootTasks.edit.${field}`)" :for="`boot-edit-${field}`">
            <el-input-number :id="`boot-edit-${field}`" v-model="form[field]" :min="1" :max="2147483647" :precision="0" :step="1" controls-position="right" />
          </el-form-item>
        </div>
        <el-form-item :label="t('bootTasks.edit.rootPassword')" for="boot-edit-password"><el-input id="boot-edit-password" v-model="form.rootPassword" type="password" show-password autocomplete="new-password" /></el-form-item>
        <el-form-item :label="t('bootTasks.edit.dayGap')" for="boot-edit-window"><el-input id="boot-edit-window" v-model="form.dayGap" :placeholder="t('bootTasks.edit.dayGapPlaceholder')" maxlength="5" /></el-form-item>
        <p class="note">{{ t('bootTasks.edit.dayGapHint') }}</p>
        <p v-if="unchanged" class="note">{{ t('bootTasks.edit.unchanged') }}</p>
      </el-form>
      <el-alert v-if="state === 'success'" type="success" :closable="false" :title="t(action === 'manual' ? 'bootTasks.manualAccepted' : 'bootTasks.accepted')" show-icon />
      <PageErrorNotice v-if="state === 'failed' || state === 'uncertain'" class="action-error-notice" :title="state === 'failed' ? t('bootTasks.failed') : undefined">{{ error }}</PageErrorNotice>
      <PageErrorNotice v-else-if="problem && !finished && !validation" class="action-error-notice"><span>{{ error }}</span><GhostBtn v-if="counting" @click="countTasks">{{ t('bootTasks.retry') }}</GhostBtn></PageErrorNotice>
      <el-alert v-if="state === 'uncertain'" type="warning" :closable="false" :title="t('bootTasks.uncertain')" show-icon />
      <p v-if="error && validation" class="error" role="alert">{{ error }}</p>
    </div>
    <template #footer>
      <GhostBtn :disabled="state === 'submitting'" @click="close">{{ t(finished ? 'bootTasks.close' : 'bootTasks.cancel') }}</GhostBtn>
      <GhostBtn v-if="!finished && danger" danger :loading="state === 'submitting'" :disabled="!canSubmit" @click="submit">{{ t(`bootTasks.actions.${action}`) }}</GhostBtn>
      <PrimaryBtn v-else-if="!finished" :loading="state === 'submitting'" :disabled="!canSubmit" @click="submit">{{ t(editing ? 'bootTasks.save' : 'bootTasks.confirm') }}</PrimaryBtn>
    </template>
  </el-dialog>
</template>

<style scoped>
.action-content { color: var(--text-primary); font: var(--font-size-body)/1.55 var(--sans); }
.target { padding: 12px 14px; background: var(--bg-search); border-radius: var(--r-sm); overflow-wrap: anywhere; }
.explanation { margin: 0 0 20px; }
.count { padding: 12px 14px; border: 1px solid var(--border); border-radius: var(--r-sm); margin-bottom: 18px; }
.count p { margin: 0 0 8px; }
.note { font-size: var(--font-size-secondary); color: var(--text-secondary); }
.error { color: var(--status-danger); overflow-wrap: anywhere; }
.action-error-notice { margin-top: 12px; }
.fields { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 18px; }
.action-content :deep(.el-input-number) { width: 100%; }
.action-content :deep(.el-form-item__label) { font-size: var(--font-size-body); color: var(--text-primary); }
:global(.boot-task-action .el-dialog__footer) { display: flex; justify-content: flex-end; gap: 10px; flex-wrap: wrap; }
@media (max-width: 460px) { .fields { grid-template-columns: 1fr; } }
</style>
