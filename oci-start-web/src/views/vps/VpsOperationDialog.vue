<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import type { VpsApiError, VpsMutationResult, VpsOperationKind, VpsRow } from '@/api/vps'
const props = defineProps<{
  operation: { kind: VpsOperationKind; row: VpsRow | null }
  pending: boolean
  outcome: 'idle' | 'success' | 'unknown' | 'failed'
  result: VpsMutationResult | null
  problem: VpsApiError | null
  readProblem: VpsApiError | null
}>()
const emit = defineEmits<{ close: []; submit: [] }>()
const { t } = useI18n()
const showIp = ref(false)
const finished = computed(() => props.outcome === 'success' || props.outcome === 'unknown')
function close() { if (!props.pending) emit('close') }
function visibility(value: boolean) { if (!value) close() }
function submit() { if (!props.pending && !finished.value) emit('submit') }
function toggleIp() { showIp.value = !showIp.value }
</script>
<template>
  <el-dialog :model-value="true" append-to-body width="580px" class="vps-operation-dialog" :title="t(`vps.operationTitles.${operation.kind}`)" :close-on-click-modal="false" :close-on-press-escape="!pending" :show-close="!pending" :before-close="close" @update:model-value="visibility">
    <dl v-if="operation.row" class="vps-target">
      <dt>{{ t('vps.target') }}</dt><dd>{{ operation.row.displayName || t('vps.unnamed') }}</dd>
      <dt>{{ t('vps.localId') }}</dt><dd>{{ operation.row.id }}</dd>
      <dt>{{ t('vps.server') }}</dt><dd><button v-if="operation.row.publicIps" type="button" class="vps-reveal" :aria-label="t(showIp ? 'vps.hideIp' : 'vps.showIp')" @click="toggleIp"><span>{{ showIp ? operation.row.publicIps : '••••••' }}</span><i :class="showIp ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button><span v-else>{{ t('vps.noIp') }}</span></dd>
    </dl>
    <p>{{ t(`vps.operationHints.${operation.kind}`) }}</p>
    <p v-if="!operation.row" class="vps-scope-hint">{{ t('vps.globalScope') }}</p>
    <div v-if="pending" class="vps-notice" role="status"><i class="i-mdi-loading animate-spin" aria-hidden="true" />{{ t('vps.submitting') }}</div>
    <div v-else-if="outcome === 'success'" class="vps-notice is-success" role="status">{{ t(`vps.successes.${operation.kind}`) }}</div>
    <div v-else-if="outcome === 'unknown'" class="vps-notice is-warning" role="alert">{{ t('vps.unknownResult') }}</div>
    <PageErrorNotice v-if="problem">{{ t(`vps.errors.${problem.key}`) }} {{ problem.detail }}</PageErrorNotice>
    <PageErrorNotice v-if="finished && readProblem">{{ t('vps.refreshFailed') }}</PageErrorNotice>
    <template #footer>
      <GhostBtn :disabled="pending" @click="close">{{ t(finished ? 'vps.close' : 'vps.cancel') }}</GhostBtn>
      <PrimaryBtn v-if="!finished" :loading="pending" :class="{ 'vps-danger-button': operation.kind === 'uninstall' }" @click="submit"><i :class="operation.kind === 'uninstall' ? 'i-mdi-trash-can-outline' : 'i-mdi-check'" aria-hidden="true" />{{ t('vps.confirm') }}</PrimaryBtn>
    </template>
  </el-dialog>
</template>
