<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import { normalizeNetworkQualityTask, type NetworkQualityTask, type NetworkQualityTaskInput, type NetworkQualityAgent } from '@/api/networkQuality'

const props = defineProps<{ task: NetworkQualityTask | null; agents: NetworkQualityAgent[]; pending: boolean; finished: boolean; feedback: string; initialInstanceId?: string }>()
const emit = defineEmits<{ close: []; save: [input: NetworkQualityTaskInput] }>()
const { t } = useI18n()
const form = reactive<NetworkQualityTaskInput>(props.task ? {
  name: props.task.name, operator: props.task.operator, region: props.task.region, type: props.task.type, target: props.task.target,
  intervalSeconds: props.task.intervalSeconds, sampleCount: props.task.sampleCount, enabled: props.task.enabled, instanceIds: [...props.task.instanceIds],
} : { name: '', operator: 'telecom', region: '', type: 'icmp', target: '', intervalSeconds: 60, sampleCount: 3, enabled: true, instanceIds: props.initialInstanceId ? [props.initialInstanceId] : [] })
const original = JSON.stringify(form)
const query = ref('')
const showIps = ref(false)
const problem = ref(false)
const discard = ref(false)
const locked = computed(() => props.pending || props.finished)
const pickerPage = ref(1)
const matches = computed(() => {
  const needle = query.value.trim().toLowerCase()
  return props.agents.filter(agent => !needle || [agent.displayName, agent.publicIps, agent.regionName].some(value => value?.toLowerCase().includes(needle)))
})
const pickerPages = computed(() => Math.max(1, Math.ceil(matches.value.length / 50)))
const visible = computed(() => matches.value.slice((pickerPage.value - 1) * 50, pickerPage.value * 50))
watch(query, () => { pickerPage.value = 1 })
watch(pickerPages, value => { if (pickerPage.value > value) pickerPage.value = value })
const chosen = computed(() => new Set(form.instanceIds))
function toggle(id: string) {
  if (locked.value) return
  if (chosen.value.has(id)) form.instanceIds = form.instanceIds.filter(value => value !== id)
  else if (form.instanceIds.length < 256) form.instanceIds.push(id)
}
function selectVisible() { if (!locked.value) form.instanceIds = [...new Set([...form.instanceIds, ...visible.value.map(agent => agent.id)])].slice(0, 256) }
function clearSelection() { if (!locked.value) form.instanceIds = [] }
function close() {
  if (props.pending) return
  if (!props.finished && JSON.stringify(form) !== original && !discard.value) { discard.value = true; return }
  emit('close')
}
function keepEditing() { discard.value = false }
function visibility(value: boolean) { if (!value) close() }
function save() {
  if (locked.value) return
  try { const input = normalizeNetworkQualityTask(form); problem.value = false; emit('save', input) }
  catch { problem.value = true }
}
</script>

<template>
  <el-dialog :model-value="true" append-to-body width="760px" class="nq-dialog" :title="t(task ? 'networkQuality.edit' : 'networkQuality.create')" :close-on-click-modal="false" :close-on-press-escape="!pending" :show-close="!pending" :before-close="close" @update:model-value="visibility">
    <p class="nq-form-intro">{{ t('networkQuality.taskHint') }}</p>
    <p v-if="task" class="nq-form-intro">{{ t('networkQuality.editHistoryHint') }}</p>
    <form id="nq-task-form" class="nq-form" @submit.prevent="save">
      <fieldset :disabled="locked">
        <div class="nq-fields">
          <label class="nq-field nq-wide"><span>{{ t('networkQuality.name') }}</span><input v-model="form.name" required maxlength="80" :placeholder="t('networkQuality.taskNamePlaceholder')" autocomplete="off" /></label>
          <label class="nq-field"><span>{{ t('networkQuality.operator') }}</span><el-select v-model="form.operator" :disabled="locked" :teleported="true" :aria-label="t('networkQuality.operator')"><el-option v-for="value in ['telecom', 'unicom', 'mobile', 'custom']" :key="value" :value="value" :label="t(`networkQuality.operators.${value}`)" /></el-select></label>
          <label class="nq-field"><span>{{ t('networkQuality.region') }}</span><input v-model="form.region" maxlength="80" :placeholder="t('networkQuality.regionPlaceholder')" /></label>
          <label class="nq-field"><span>{{ t('networkQuality.protocol') }}</span><el-select v-model="form.type" :disabled="locked" :teleported="true" :aria-label="t('networkQuality.protocol')"><el-option value="icmp" label="ICMP Ping" /><el-option value="tcp" label="TCP" /><el-option value="http" label="HTTP / HTTPS" /></el-select></label>
          <label class="nq-field"><span>{{ t('networkQuality.target') }}</span><input v-model="form.target" required maxlength="2048" :placeholder="t(form.type === 'icmp' ? 'networkQuality.hostPlaceholder' : form.type === 'tcp' ? 'networkQuality.tcpPlaceholder' : 'networkQuality.httpPlaceholder')" autocomplete="off" spellcheck="false" /></label>
          <label class="nq-field"><span>{{ t('networkQuality.interval') }}</span><input v-model.number="form.intervalSeconds" required type="number" min="30" max="86400" step="1" /></label>
          <label class="nq-field"><span>{{ t('networkQuality.samples') }}</span><input v-model.number="form.sampleCount" required type="number" min="1" max="10" step="1" /></label>
        </div>
        <div class="nq-selection-header"><strong>{{ t('networkQuality.assigned') }}</strong><span>{{ t('networkQuality.selected', { count: form.instanceIds.length }) }}</span><button type="button" class="nq-link" @click="selectVisible">{{ t('networkQuality.selectVisible') }}</button><button type="button" class="nq-link" @click="clearSelection">{{ t('networkQuality.clearSelection') }}</button></div>
        <div class="nq-selection-search"><input v-model="query" type="search" :placeholder="t('networkQuality.instanceSearch')" :aria-label="t('networkQuality.instanceSearch')" /><button type="button" class="nq-icon" :aria-label="t(showIps ? 'networkQuality.hideIp' : 'networkQuality.showIp')" @click="showIps = !showIps"><i :class="showIps ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button></div>
        <div class="nq-instance-picker" :aria-label="t('networkQuality.assigned')">
          <label v-for="agent in visible" :key="agent.id" class="nq-pick-row"><input type="checkbox" :checked="chosen.has(agent.id)" :disabled="!chosen.has(agent.id) && form.instanceIds.length >= 256" @change="toggle(agent.id)" /><span class="nq-truncate" :title="agent.displayName || agent.id">{{ agent.displayName || agent.id }}</span><small class="nq-truncate">{{ agent.publicIps ? showIps ? agent.publicIps : '••••••' : '—' }}</small><small>{{ t(`networkQuality.agents.${agent.qualityStatus}`) }}</small></label>
          <p v-if="!visible.length" class="nq-picker-empty">{{ t('networkQuality.noMatches') }}</p>
        </div>
        <PagePagination v-if="pickerPages > 1" v-model:current-page="pickerPage" class="nq-picker-pages" :page-size="50" :total="matches.length" :disabled="locked" embedded><span>{{ t('networkQuality.total', { count: matches.length }) }}</span></PagePagination>
        <small class="nq-help">{{ t('networkQuality.instanceLimit') }} · {{ t('networkQuality.intervalHint') }}</small>
        <label class="nq-check"><input v-model="form.enabled" type="checkbox" /><span>{{ t('networkQuality.enabled') }}</span></label>
        <small class="nq-help">{{ t('networkQuality.saveHint') }}</small>
      </fieldset>
      <div v-if="problem" class="nq-notice is-error" role="alert">{{ t('networkQuality.errors.invalidInput') }}</div>
      <div v-if="pending" class="nq-notice" role="status">{{ t('networkQuality.submitting') }}</div>
      <PageErrorNotice v-else-if="feedback && !finished">{{ feedback }}</PageErrorNotice>
      <div v-else-if="feedback" class="nq-notice is-warning" role="alert">{{ feedback }}</div>
      <div v-if="discard" class="nq-notice is-warning" role="alert"><span>{{ t('networkQuality.discard') }}</span><GhostBtn @click="keepEditing">{{ t('networkQuality.keepEditing') }}</GhostBtn><GhostBtn danger @click="close">{{ t('networkQuality.discardConfirm') }}</GhostBtn></div>
    </form>
    <template #footer><GhostBtn :disabled="pending" @click="close">{{ t(finished ? 'networkQuality.close' : 'networkQuality.cancel') }}</GhostBtn><PrimaryBtn v-if="!finished" type="submit" form="nq-task-form" :loading="pending"><i class="i-mdi-check" aria-hidden="true" />{{ t('networkQuality.save') }}</PrimaryBtn></template>
  </el-dialog>
</template>
