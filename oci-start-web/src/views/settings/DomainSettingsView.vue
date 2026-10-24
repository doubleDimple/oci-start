<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue'
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import type { DomainProvider, DomainProviderApiError } from '@/api/domainProviders'
import ProviderSecretInput from './ProviderSecretInput.vue'
import { useDomainProviders } from './useDomainProviders'
import './domain-providers.scss'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const {
  providers, loading, loadProblem, loaded, anyDirty,
  saveProvider, savePending, saveCompleted, saveEnabled, canDismissSave,
  prepareSave, confirmSave, closeSave, reload, runTest, cancelTest,
} = useDomainProviders()
const providerNames: DomainProvider[] = ['cloudflare', 'edgeOne']
const cloudflare = providers.cloudflare
const edgeOne = providers.edgeOne
const saveState = computed(() => saveProvider.value ? providers[saveProvider.value] : null)
const discardAction = ref<'reload' | 'leave' | null>(null)
const summary = computed(() => t(`domainProviders.${loading.value ? 'loading' : anyDirty.value ? 'unsaved' : loaded.value ? 'allSaved' : 'notLoaded'}`))
let resolveLeave: ((allow: boolean) => void) | undefined

function errorText(problem: DomainProviderApiError) { return t(`domainProviders.errors.${problem.key}`) }
function locked(provider: DomainProvider) {
  const state = providers[provider]
  return !state.loaded || loading.value || !!saveProvider.value || !!discardAction.value || state.testState === 'testing' || state.requiresReload
}
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/oci/list')
}
function requestReload() {
  if (loading.value || saveProvider.value || discardAction.value) return
  if (anyDirty.value) discardAction.value = 'reload'
  else void reload()
}
function cancelDiscard() {
  discardAction.value = null
  resolveLeave?.(false)
  resolveLeave = undefined
}
function confirmDiscard() {
  const action = discardAction.value
  discardAction.value = null
  if (action === 'leave') { resolveLeave?.(true); resolveLeave = undefined }
  else if (action === 'reload') void reload()
}
function discardVisibility(value: boolean) { if (!value) cancelDiscard() }
function beforeDiscardClose(done: () => void) { cancelDiscard(); done() }
function saveVisibility(value: boolean) { if (!value) closeSave() }
function beforeSaveClose(done: () => void) { if (canDismissSave.value) { closeSave(); done() } }

onBeforeRouteLeave(() => {
  if (saveProvider.value || discardAction.value) return false
  if (!anyDirty.value) return true
  discardAction.value = 'leave'
  return new Promise<boolean>(resolve => { resolveLeave = resolve })
})
onBeforeUnmount(cancelDiscard)
</script>

<template>
  <section class="domain-providers-page" :aria-label="t('domainProviders.title')">
    <header class="domain-providers-toolbar">
      <PageBackButton :disabled="!!saveProvider || !!discardAction" @click="back" />
      <span class="domain-providers-summary" role="status">{{ summary }}</span>
      <div class="domain-providers-toolbar-actions" data-page-error-anchor><GhostBtn :loading="loading" :disabled="!!saveProvider || !!discardAction" @click="requestReload"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('domainProviders.refresh') }}</GhostBtn></div>
    </header>

    <PageErrorNotice v-if="loadProblem"><span>{{ errorText(loadProblem) }} {{ loadProblem.detail }} <span v-if="loaded">{{ t('domainProviders.retainedHint') }}</span></span></PageErrorNotice>

    <div class="domain-providers-body" :aria-busy="loading">
      <section v-for="provider in providerNames" :key="provider" class="domain-provider" :aria-labelledby="`${provider}-heading`">
        <header class="domain-provider-heading" data-page-error-anchor>
          <h2 :id="`${provider}-heading`">{{ t(`domainProviders.${provider}`) }}</h2>
          <label class="domain-provider-enable"><input v-model="providers[provider].draft.enabled" type="checkbox" :disabled="locked(provider)" />{{ t('domainProviders.enabled') }}</label>
        </header>
        <div class="domain-provider-status">
          <span>{{ providers[provider].baseline ? t(providers[provider].baseline.enabled ? 'domainProviders.savedEnabled' : 'domainProviders.savedDisabled') : t('domainProviders.notLoaded') }}</span>
          <span v-if="providers[provider].dirty" class="is-dirty">{{ t('domainProviders.dirty') }}</span>
        </div>

        <div class="domain-provider-fields">
          <template v-if="provider === 'cloudflare'">
            <ProviderSecretInput v-model="cloudflare.draft.apiToken" field-id="cloudflare-api-token" :label="t('domainProviders.apiKey')" :hint="t('domainProviders.apiKeyHint')" :disabled="locked(provider)" />
            <div class="domain-provider-field">
              <label for="cloudflare-email">{{ t('domainProviders.email') }}</label>
              <input id="cloudflare-email" v-model="cloudflare.draft.email" type="email" class="domain-provider-input" :disabled="locked(provider)" aria-describedby="cloudflare-email-hint" autocomplete="off" autocapitalize="off" :spellcheck="false" />
              <small id="cloudflare-email-hint">{{ t('domainProviders.emailHint') }}</small>
            </div>
          </template>
          <template v-else>
            <ProviderSecretInput v-model="edgeOne.draft.secretId" field-id="edgeone-secret-id" :label="t('domainProviders.secretId')" :hint="t('domainProviders.secretIdHint')" :disabled="locked(provider)" />
            <ProviderSecretInput v-model="edgeOne.draft.secretKey" field-id="edgeone-secret-key" :label="t('domainProviders.secretKey')" :hint="t('domainProviders.secretKeyHint')" :disabled="locked(provider)" />
          </template>
        </div>

        <div class="domain-provider-feedback" aria-live="polite">
          <div v-if="providers[provider].testState === 'testing'" class="domain-provider-notice"><i class="i-mdi-loading animate-spin" aria-hidden="true" /><span>{{ t('domainProviders.testing') }}</span></div>
          <div v-else-if="providers[provider].testState === 'passed'" class="domain-provider-notice is-success"><i class="i-mdi-check-circle-outline" aria-hidden="true" /><span>{{ t('domainProviders.testPassed') }}</span></div>
          <PageErrorNotice v-else-if="providers[provider].testProblem"><span>{{ errorText(providers[provider].testProblem) }} {{ providers[provider].testProblem.detail }}</span></PageErrorNotice>
          <div v-if="providers[provider].saveState === 'saved' && !providers[provider].dirty" class="domain-provider-notice is-success"><i class="i-mdi-check-circle-outline" aria-hidden="true" /><span>{{ t('domainProviders.saved') }}</span></div>
          <PageErrorNotice v-if="providers[provider].saveProblem && saveProvider !== provider"><span>{{ errorText(providers[provider].saveProblem) }} {{ providers[provider].saveProblem.detail }}</span></PageErrorNotice>
          <div v-if="providers[provider].requiresReload" class="domain-provider-notice is-warning"><i class="i-mdi-information-outline" aria-hidden="true" /><span>{{ t('domainProviders.reloadBeforeSave') }}</span></div>
        </div>
        <footer class="domain-provider-actions">
          <GhostBtn v-if="providers[provider].testState === 'testing'" :disabled="!!saveProvider || loading" @click="cancelTest(provider)"><i class="i-mdi-stop" aria-hidden="true" />{{ t('domainProviders.cancelTest') }}</GhostBtn>
          <GhostBtn v-else :disabled="locked(provider)" @click="runTest(provider)"><i class="i-mdi-connection" aria-hidden="true" />{{ t('domainProviders.test') }}</GhostBtn>
          <GhostBtn :disabled="locked(provider) || !providers[provider].dirty" @click="prepareSave(provider)"><i class="i-mdi-content-save-outline" aria-hidden="true" />{{ t('domainProviders.save') }}</GhostBtn>
        </footer>
      </section>
    </div>
    <footer class="domain-providers-footer">{{ t('domainProviders.testHint') }}</footer>

    <el-dialog :model-value="!!saveProvider" :title="t('domainProviders.saveTitle')" width="520px" append-to-body :close-on-click-modal="false" :close-on-press-escape="canDismissSave" :show-close="canDismissSave" :before-close="beforeSaveClose" class="domain-provider-dialog" @update:model-value="saveVisibility">
      <template v-if="saveProvider && saveState">
        <p class="domain-provider-confirm-summary">{{ t('domainProviders.saveSummary', { provider: t(`domainProviders.${saveProvider}`), action: t(saveEnabled ? 'domainProviders.enableAction' : 'domainProviders.disableAction') }) }}</p>
        <p>{{ t('domainProviders.saveHint') }}</p>
        <div v-if="savePending" class="domain-provider-notice" role="status"><i class="i-mdi-loading animate-spin" aria-hidden="true" /><span>{{ t('domainProviders.saving') }}</span></div>
        <div v-else-if="saveState.saveState === 'saved'" class="domain-provider-notice is-success" role="status">{{ t('domainProviders.saved') }}</div>
        <div v-else-if="saveState.saveState === 'unknown'" class="domain-provider-notice is-warning" role="alert">{{ t('domainProviders.unknown') }}</div>
        <PageErrorNotice v-if="saveState.saveProblem"><span>{{ errorText(saveState.saveProblem) }} {{ saveState.saveProblem.detail }}</span></PageErrorNotice>
      </template>
      <template #footer>
        <GhostBtn :disabled="!canDismissSave" @click="closeSave">{{ t(saveCompleted ? 'domainProviders.close' : 'domainProviders.cancel') }}</GhostBtn>
        <PrimaryBtn v-if="saveState?.saveState === 'idle'" :loading="savePending" @click="confirmSave"><i class="i-mdi-content-save-outline" aria-hidden="true" />{{ t('domainProviders.confirmSave') }}</PrimaryBtn>
      </template>
    </el-dialog>

    <el-dialog :model-value="!!discardAction" :title="t('domainProviders.discardTitle')" width="480px" append-to-body :close-on-click-modal="false" :before-close="beforeDiscardClose" class="domain-provider-discard-dialog" @update:model-value="discardVisibility">
      <p>{{ t(discardAction === 'leave' ? 'domainProviders.discardLeave' : 'domainProviders.discardReload') }}</p>
      <template #footer>
        <GhostBtn @click="cancelDiscard">{{ t('domainProviders.keepEditing') }}</GhostBtn>
        <PrimaryBtn @click="confirmDiscard">{{ t(discardAction === 'leave' ? 'domainProviders.discardAndLeave' : 'domainProviders.discardAndReload') }}</PrimaryBtn>
      </template>
    </el-dialog>
  </section>
</template>
