<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import type { DomainProviderApiError } from '@/api/domainProviders'
import ProviderSecretInput from '@/views/settings/ProviderSecretInput.vue'
import { useDomainProviders } from '@/views/settings/useDomainProviders'

const emit = defineEmits<{ close: []; changed: []; busy: [value: boolean] }>()
const { t } = useI18n()
const {
  providers, loading, loadProblem, saveProvider, savePending, saveCompleted,
  saveEnabled, prepareSave, confirmSave, closeSave, reload, runTest, cancelTest,
} = useDomainProviders()
const state = providers.edgeOne
const regions = [
  { value: 'ap-beijing', labelKey: 'beijing' },
  { value: 'ap-shanghai', labelKey: 'shanghai' },
  { value: 'ap-guangzhou', labelKey: 'guangzhou' },
  { value: 'ap-singapore', labelKey: 'singapore' },
  { value: 'na-ashburn', labelKey: 'ashburn' },
  { value: 'eu-frankfurt', labelKey: 'frankfurt' },
] as const
const customRegions = computed(() => [...new Set([state.baseline?.region ?? '', state.draft.region])]
  .filter(region => region && !regions.some(option => option.value === region)))
const discardAction = ref<'close' | 'reload' | 'navigation' | null>(null)
const testStopped = ref(false)
const staged = computed(() => saveProvider.value === 'edgeOne')
const locked = computed(() => !state.loaded || loading.value || staged.value
  || !!discardAction.value || state.requiresReload)
const testing = computed(() => state.testState === 'testing')
const fieldsLocked = computed(() => locked.value || testing.value || !state.draft.enabled)
const discardMessage = computed(() => discardAction.value === 'reload'
  ? t('edgeoneDns.credentials.discardReload') : discardAction.value === 'navigation'
    ? t('domainProviders.discardLeave') : t('edgeoneDns.credentials.discardClose'))
const discardButton = computed(() => discardAction.value === 'reload'
  ? t('domainProviders.discardAndReload') : discardAction.value === 'navigation'
    ? t('domainProviders.discardAndLeave') : t('edgeoneDns.credentials.discardAndClose'))
let disposed = false
let closing = false
let saveAttempt = 0
let notifiedAttempt = 0
let resolveNavigation: ((allow: boolean) => void) | undefined

function problemText(problem: DomainProviderApiError): string {
  return t(`domainProviders.errors.${problem.key}`)
}
function closeDialog(): void {
  if (disposed || closing || savePending.value) return
  closing = true
  emit('close')
}
function cancelDiscard(): void {
  discardAction.value = null
  const resolve = resolveNavigation
  resolveNavigation = undefined
  resolve?.(false)
}
function requestClose(): void {
  if (disposed || closing || savePending.value) return
  // Escape or the close icon first dismisses an inline discard confirmation.
  if (discardAction.value) { cancelDiscard(); return }
  closeSave()
  if (state.dirty) discardAction.value = 'close'
  else closeDialog()
}
function visibilityChanged(value: boolean): void { if (!value) requestClose() }
function requestReload(): void {
  if (disposed || closing || savePending.value || loading.value || discardAction.value) return
  closeSave()
  if (state.dirty) discardAction.value = 'reload'
  else {
    testStopped.value = false
    void reload()
  }
}
function confirmDiscard(): void {
  if (disposed || savePending.value) return
  const action = discardAction.value
  if (!action) return
  discardAction.value = null
  if (action === 'reload') {
    closeSave()
    testStopped.value = false
    void reload()
  } else if (action === 'navigation') {
    const resolve = resolveNavigation
    resolveNavigation = undefined
    resolve?.(true)
    closeDialog()
  } else closeDialog()
}
function testConnection(): void {
  if (locked.value || testing.value || !state.draft.enabled) return
  testStopped.value = false
  void runTest('edgeOne')
}
function stopTest(): void {
  if (savePending.value || !testing.value) return
  cancelTest('edgeOne')
  testStopped.value = true
}
function beginSave(): void {
  if (locked.value || testing.value || !state.dirty) return
  if (prepareSave('edgeOne')) {
    ++saveAttempt
    testStopped.value = false
  }
}
async function submitSave(): Promise<void> {
  if (disposed || !staged.value || savePending.value || saveCompleted.value) return
  const attempt = saveAttempt
  await confirmSave()
  if (disposed || notifiedAttempt === attempt) return
  if (state.saveState === 'saved' || state.saveState === 'unknown') {
    notifiedAttempt = attempt
    // Unknown writes may have committed too; the parent refreshes its site
    // context after this dialog closes, without automatically resending a save.
    emit('changed')
  }
}
function returnToForm(): void { if (!savePending.value) closeSave() }
function guardNavigation(): boolean | Promise<boolean> {
  if (savePending.value || staged.value || discardAction.value) return false
  if (!state.dirty) return true
  discardAction.value = 'navigation'
  return new Promise<boolean>(resolve => { resolveNavigation = resolve })
}

watch(savePending, value => emit('busy', value), { immediate: true, flush: 'sync' })
watch(() => [state.draft.enabled, state.draft.secretId, state.draft.secretKey, state.draft.region], () => { testStopped.value = false })
onBeforeRouteLeave(guardNavigation)
onBeforeRouteUpdate(guardNavigation)
onBeforeUnmount(() => {
  disposed = true
  closing = true
  const resolve = resolveNavigation
  resolveNavigation = undefined
  resolve?.(false)
  emit('busy', false)
})
</script>

<template>
  <el-dialog :model-value="true" append-to-body width="560px" class="edgeone-credentials-dialog"
    :title="t('edgeoneDns.credentials.title')" :close-on-click-modal="false"
    :close-on-press-escape="!savePending" :show-close="!savePending"
    :before-close="requestClose" @update:model-value="visibilityChanged">
    <div class="edgeone-credentials-header">
      <div class="edgeone-credentials-status" role="status">
        <span>{{ loading ? t('domainProviders.loading') : state.baseline ? t(state.baseline.enabled ? 'domainProviders.savedEnabled' : 'domainProviders.savedDisabled') : t('domainProviders.notLoaded') }}</span>
        <span v-if="state.dirty">{{ t('domainProviders.dirty') }}</span>
      </div>
      <label class="edgeone-credentials-enable"><input v-model="state.draft.enabled" type="checkbox" :disabled="locked || testing" />{{ t('domainProviders.enabled') }}</label>
    </div>

    <PageErrorNotice v-if="loadProblem">
      <span>{{ problemText(loadProblem) }} {{ loadProblem.detail }} <span v-if="state.loaded">{{ t('domainProviders.retainedHint') }}</span></span>
    </PageErrorNotice>

    <div class="edgeone-credentials-fields" :aria-busy="loading">
      <ProviderSecretInput v-model="state.draft.secretId" field-id="edgeone-dns-secret-id"
        :label="t('domainProviders.secretId')" :hint="t('domainProviders.secretIdHint')" :disabled="fieldsLocked" />
      <ProviderSecretInput v-model="state.draft.secretKey" field-id="edgeone-dns-secret-key"
        :label="t('domainProviders.secretKey')" :hint="t('domainProviders.secretKeyHint')" :disabled="fieldsLocked" />
      <div class="edgeone-field">
        <label for="edgeone-dns-region">{{ t('edgeoneDns.credentials.region') }}</label>
        <el-select id="edgeone-dns-region" v-model="state.draft.region" class="edgeone-select" :placeholder="t('edgeoneDns.credentials.regionEmpty')" :disabled="fieldsLocked" aria-describedby="edgeone-dns-region-hint">
          <el-option v-for="region in customRegions" :key="region" :value="region" :label="region" />
          <el-option v-for="region in regions" :key="region.value" :value="region.value" :label="t(`edgeoneDns.credentials.regions.${region.labelKey}`)" />
        </el-select>
        <small id="edgeone-dns-region-hint">{{ t('edgeoneDns.credentials.regionHint') }}</small>
      </div>
    </div>

    <div class="edgeone-credentials-actions">
      <GhostBtn v-if="testing" :disabled="savePending || !!discardAction" @click="stopTest"><i class="i-mdi-stop" aria-hidden="true" />{{ t('domainProviders.cancelTest') }}</GhostBtn>
      <GhostBtn v-else :disabled="locked || !state.draft.enabled" @click="testConnection"><i class="i-mdi-connection" aria-hidden="true" />{{ t('domainProviders.test') }}</GhostBtn>
      <GhostBtn :loading="loading" :disabled="savePending || !!discardAction" @click="requestReload"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('domainProviders.refresh') }}</GhostBtn>
    </div>
    <p class="edgeone-credentials-help">{{ t('domainProviders.testHint') }}</p>

    <div v-if="testing" class="edgeone-credentials-notice" role="status">{{ t('domainProviders.testing') }}</div>
    <div v-else-if="testStopped" class="edgeone-credentials-notice" role="status">{{ t('edgeoneDns.credentials.testStopped') }}</div>
    <div v-else-if="state.testState === 'passed'" class="edgeone-credentials-notice is-success" role="status">{{ t('domainProviders.testPassed') }}</div>
    <PageErrorNotice v-else-if="state.testProblem"><span>{{ problemText(state.testProblem) }} {{ state.testProblem.detail }}</span></PageErrorNotice>

    <div v-if="discardAction" class="edgeone-credentials-confirm" role="alert">
      <strong>{{ t('domainProviders.discardTitle') }}</strong>
      <p>{{ discardMessage }}</p>
    </div>
    <div v-else-if="staged" class="edgeone-credentials-confirm">
      <p>{{ t('domainProviders.saveSummary', { provider: t('domainProviders.edgeOne'), action: t(saveEnabled ? 'domainProviders.enableAction' : 'domainProviders.disableAction') }) }}</p>
      <p>{{ t('domainProviders.saveHint') }}</p>
    </div>

    <div v-if="savePending" class="edgeone-credentials-notice" role="status">{{ t('domainProviders.saving') }}</div>
    <div v-else-if="state.saveState === 'saved' && !state.dirty" class="edgeone-credentials-notice is-success" role="status">{{ t('domainProviders.saved') }}</div>
    <div v-else-if="state.requiresReload" class="edgeone-credentials-notice is-warning" role="alert">{{ t('domainProviders.reloadBeforeSave') }}</div>
    <PageErrorNotice v-if="state.saveProblem"><span>{{ problemText(state.saveProblem) }} {{ state.saveProblem.detail }}</span></PageErrorNotice>

    <template #footer>
      <div class="edgeone-credentials-footer">
        <template v-if="discardAction">
          <GhostBtn @click="cancelDiscard">{{ t('domainProviders.keepEditing') }}</GhostBtn>
          <PrimaryBtn @click="confirmDiscard">{{ discardButton }}</PrimaryBtn>
        </template>
        <template v-else-if="staged">
          <GhostBtn :disabled="savePending" @click="returnToForm">{{ t('edgeoneDns.credentials.backToForm') }}</GhostBtn>
          <GhostBtn v-if="saveCompleted" @click="requestClose">{{ t('domainProviders.close') }}</GhostBtn>
          <PrimaryBtn v-else :loading="savePending" @click="submitSave"><i class="i-mdi-content-save-outline" aria-hidden="true" />{{ t('domainProviders.confirmSave') }}</PrimaryBtn>
        </template>
        <template v-else>
          <GhostBtn @click="requestClose">{{ t('domainProviders.close') }}</GhostBtn>
          <PrimaryBtn :disabled="locked || testing || !state.dirty" @click="beginSave"><i class="i-mdi-content-save-outline" aria-hidden="true" />{{ t('domainProviders.save') }}</PrimaryBtn>
        </template>
      </div>
    </template>
  </el-dialog>
</template>
