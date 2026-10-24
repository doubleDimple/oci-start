<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import SecuritySecretInput from './security/SecuritySecretInput.vue'
import type { ApiTokenApiError, ApiTokenInput } from '@/api/apiTokens'
import { useApiTokens } from './api-tokens/useApiTokens'
import './api-tokens/api-tokens.scss'

const { t, locale } = useI18n(), router = useRouter(), route = useRoute()
const page = useApiTokens()
const { state, loaded, loading, problem, lastUpdated, material, materialLoading, materialProblem,
  mutation, canMutate, contextLocked, requiresReview, reviewReady, isExpired, canReveal, readbackChanged } = page
const screen = ref<'overview' | 'generate'>('overview')
const draft = reactive<ApiTokenInput>({ tokenName: '', expirationDays: 30, description: '' })
const baseline = shallowRef<ApiTokenInput | null>(null), editorRevision = ref('')
const confirmation = shallowRef<{ kind: 'generate' | 'revoke'; revision: string; input?: ApiTokenInput; replacing: boolean; name: string } | null>(null)
const discardVisible = ref(false), reviewChecked = ref(false), nameInput = ref<HTMLInputElement>(), validation = ref(false)
const showMaterial = ref(false), authFormat = 'Authorization: Bearer <TOKEN>', copyState = ref('')
const presets = [7, 30, 90, 180, 365]
const expiryOptions = computed(() => [...new Set([...presets, draft.expirationDays])].filter(day => Number.isInteger(day) && day > 0 && day <= 365).sort((a, b) => a - b))
const dirty = computed(() => screen.value === 'generate' && baseline.value !== null && (
  draft.tokenName !== baseline.value.tokenName || draft.expirationDays !== baseline.value.expirationDays || draft.description !== baseline.value.description))
const blocked = computed(() => contextLocked.value || !!confirmation.value || discardVisible.value)
const formValid = computed(() => !!draft.tokenName.trim() && draft.tokenName.trim().length <= 255 && draft.description.length <= 1000
  && Number.isInteger(draft.expirationDays) && draft.expirationDays >= 1 && draft.expirationDays <= 365)
const currentStatus = computed(() => !state.value ? 'notLoaded' : !state.value.hasToken ? 'missing'
  : !state.value.enabled ? 'disabled' : isExpired.value === true ? 'expired' : isExpired.value === null ? 'unverified' : 'active')
const readTime = computed(() => lastUpdated.value ? t('apiTokens.lastUpdated', { time: new Intl.DateTimeFormat(locale.value, {
  hour: '2-digit', minute: '2-digit', second: '2-digit',
}).format(lastUpdated.value) }) : t('apiTokens.notLoaded'))
const staleEditor = computed(() => screen.value === 'generate' && !!state.value && editorRevision.value !== state.value.revision)
const materialVisible = computed(() => showMaterial.value && !!material.value && (!state.value || material.value.metadata.revision === state.value.revision))
let discardAction: (() => void) | undefined, cancelNavigation: (() => void) | undefined
let disposed = false, copySequence = 0, copyTimer: number | undefined

function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function errorText(error: ApiTokenApiError | null) { return error ? t(`apiTokens.errors.${error.key}`) : '' }
function dateText(value: string | null | undefined) {
  if (!value) return t('apiTokens.unset')
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/.exec(value)
  if (!match) return value
  const parts = match.slice(1).map(Number)
  const date = new Date(Date.UTC(parts[0]!, parts[1]! - 1, parts[2]!, parts[3]!, parts[4]!, parts[5]!))
  return new Intl.DateTimeFormat(locale.value, { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'UTC', hour12: false }).format(date)
}
function clearDraft() {
  Object.assign(draft, { tokenName: '', expirationDays: 30, description: '' })
  baseline.value = null; editorRevision.value = ''; validation.value = false
}
function clearMaterial() { showMaterial.value = false; page.clearMaterial() }
function openEditor() {
  if (!canMutate.value || blocked.value || !state.value) return
  clearMaterial(); page.clearMutation()
  const input = { tokenName: state.value.tokenName, expirationDays: state.value.expirationDays, description: state.value.description }
  Object.assign(draft, input); baseline.value = { ...input }; editorRevision.value = state.value.revision
  validation.value = false; screen.value = 'generate'
  void nextTick(() => nameInput.value?.focus())
}
function leaveEditor() { clearDraft(); screen.value = 'overview' }
function requestDiscard(action: () => void, cancel?: () => void) {
  if (discardVisible.value) { cancel?.(); return }
  discardAction = action; cancelNavigation = cancel; discardVisible.value = true
}
function cancelDiscard() {
  discardVisible.value = false; discardAction = undefined
  const cancel = cancelNavigation; cancelNavigation = undefined; cancel?.()
}
function acceptDiscard() {
  const action = discardAction; discardAction = undefined; cancelNavigation = undefined
  discardVisible.value = false; clearDraft(); action?.()
}
function requestCloseEditor() {
  if (blocked.value || requiresReview.value) return
  if (dirty.value) requestDiscard(leaveEditor); else leaveEditor()
}
function back() {
  if (screen.value === 'generate') { requestCloseEditor(); return }
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else void router.push('/boot/dashboard')
}
async function refresh() {
  if (blocked.value) return
  clearMaterial()
  await page.refresh()
}
function useLatestRevision() {
  if (!state.value || loading.value || problem.value || blocked.value) return
  editorRevision.value = state.value.revision; page.clearMutation()
}
function prepareGenerate() {
  validation.value = !formValid.value
  if (!formValid.value || !canMutate.value || blocked.value || staleEditor.value || !state.value) return
  page.clearMutation()
  confirmation.value = { kind: 'generate', revision: editorRevision.value, input: { ...draft, tokenName: draft.tokenName.trim() },
    replacing: state.value.hasToken, name: draft.tokenName.trim() }
}
function prepareRevoke() {
  if (!canMutate.value || blocked.value || !state.value || (!state.value.hasToken && !state.value.enabled)) return
  clearMaterial(); page.clearMutation()
  confirmation.value = { kind: 'revoke', revision: state.value.revision, replacing: state.value.hasToken, name: state.value.tokenName }
}
function cancelConfirmation() { if (!contextLocked.value) confirmation.value = null }
async function confirmMutation() {
  const action = confirmation.value
  if (!action || contextLocked.value) return
  if (action.kind === 'generate' && action.input) await page.generateToken({ ...action.input }, action.revision)
  else if (action.kind === 'revoke') await page.revokeToken(action.revision)
  if (disposed) return
  confirmation.value = null
  if (mutation.value.outcome === 'success' || mutation.value.outcome === 'unknown') {
    leaveEditor(); showMaterial.value = !!material.value
  }
}
async function revealToken() {
  if (!canReveal.value || blocked.value || !state.value) return
  showMaterial.value = true
  await page.revealToken(state.value.revision)
}
function acknowledgeReview() { if (reviewReady.value && reviewChecked.value) { page.acknowledgeReview(); reviewChecked.value = false } }
async function copyFormat() {
  const sequence = ++copySequence
  window.clearTimeout(copyTimer); copyState.value = ''
  try { await navigator.clipboard.writeText(authFormat); if (!disposed && sequence === copySequence) copyState.value = 'copied' }
  catch { if (!disposed && sequence === copySequence) copyState.value = 'copyFailed' }
  if (!disposed && sequence === copySequence) copyTimer = window.setTimeout(() => { copyState.value = '' }, 3000)
}
function beforeUnload(event: BeforeUnloadEvent) { if (contextLocked.value || requiresReview.value || dirty.value) { event.preventDefault(); event.returnValue = '' } }
function visibilityChanged() { if (document.hidden) { showMaterial.value = false; ++copySequence; copyState.value = ''; window.clearTimeout(copyTimer) } }
watch(reviewReady, () => { reviewChecked.value = false })
onBeforeRouteLeave(() => {
  if (blocked.value || requiresReview.value) return false
  if (!dirty.value) return true
  return new Promise<boolean>(resolve => requestDiscard(() => resolve(true), () => resolve(false)))
})
onMounted(() => { void page.refresh(); window.addEventListener('beforeunload', beforeUnload); document.addEventListener('visibilitychange', visibilityChanged) })
onBeforeUnmount(() => {
  disposed = true; ++copySequence; window.clearTimeout(copyTimer); clearDraft(); cancelNavigation?.()
  window.removeEventListener('beforeunload', beforeUnload); document.removeEventListener('visibilitychange', visibilityChanged)
})
</script>

<template>
  <section class="api-tokens-page">
    <header class="api-tokens-toolbar">
      <PageBackButton :disabled="blocked || requiresReview" @click="back" />
      <span v-if="screen === 'generate'" class="api-tokens-toolbar-title">{{ t(state?.hasToken ? 'apiTokens.replaceTitle' : 'apiTokens.createTitle') }}</span>
      <span v-else class="api-token-status" :class="`is-${currentStatus}`"><i aria-hidden="true" />{{ t(`apiTokens.${currentStatus}`) }}</span>
      <div class="api-tokens-toolbar-actions" data-page-error-anchor>
        <GhostBtn :loading="loading" :disabled="blocked" :title="readTime" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('apiTokens.refresh') }}</GhostBtn>
        <template v-if="screen === 'overview'"><GhostBtn danger :disabled="!canMutate || blocked || (!state?.hasToken && !state?.enabled)" @click="prepareRevoke"><i class="i-mdi-cancel" aria-hidden="true" />{{ t('apiTokens.revoke') }}</GhostBtn><PrimaryBtn :disabled="!canMutate || blocked" @click="openEditor"><i class="i-mdi-key-plus" aria-hidden="true" />{{ t(state?.hasToken ? 'apiTokens.replace' : 'apiTokens.generate') }}</PrimaryBtn></template>
        <GhostBtn v-else :disabled="blocked || requiresReview" @click="requestCloseEditor">{{ t('apiTokens.cancel') }}</GhostBtn>
      </div>
    </header>

    <PageErrorNotice v-if="problem"><p>{{ errorText(problem) }}<span v-if="loaded"> {{ t('apiTokens.retained') }}</span></p></PageErrorNotice>
    <div v-if="mutation.outcome === 'success'" class="api-tokens-notice" role="status"><p>{{ t(mutation.kind === 'generate' ? 'apiTokens.generated' : 'apiTokens.revoked') }}<span v-if="problem"> {{ t('apiTokens.readbackFailed') }}</span><span v-else-if="readbackChanged"> {{ t('apiTokens.readbackChanged') }}</span></p><GhostBtn @click="page.clearMutation">{{ t('apiTokens.close') }}</GhostBtn></div>
    <PageErrorNotice v-if="mutation.outcome === 'failed' && mutation.problem"><p>{{ errorText(mutation.problem) }} {{ t('apiTokens.rejected') }}</p></PageErrorNotice>
    <div v-if="requiresReview" class="api-tokens-notice is-warning" role="status"><div><strong>{{ t('apiTokens.unknownTitle') }}</strong><p>{{ t('apiTokens.unknownHint') }}</p><label class="api-token-check"><input v-model="reviewChecked" type="checkbox" :disabled="!reviewReady" /><span>{{ t('apiTokens.reviewLabel') }}</span></label></div><GhostBtn :disabled="!reviewReady || !reviewChecked" @click="acknowledgeReview">{{ t('apiTokens.finishReview') }}</GhostBtn></div>

    <div class="api-tokens-scroll" :aria-busy="loading">
      <template v-if="screen === 'overview'">
        <dl class="api-token-details">
          <div><dt>{{ t('apiTokens.name') }}</dt><dd>{{ state?.tokenName || '—' }}</dd></div>
          <div><dt>{{ t('apiTokens.expirationDays') }}</dt><dd>{{ state ? t('apiTokens.daysOption', { days: number(state.expirationDays) }) : '—' }}</dd></div>
          <div><dt>{{ t('apiTokens.created') }}</dt><dd><time :datetime="state?.createdAt || undefined">{{ state ? dateText(state.createdAt) : '—' }}</time></dd></div>
          <div><dt>{{ t('apiTokens.expires') }}</dt><dd><time :datetime="state?.expiresAt || undefined">{{ state ? dateText(state.expiresAt) : '—' }}</time><small v-if="state?.expiresAt && state.serverTimeZone">{{ state.serverTimeZone }}</small></dd></div>
          <div class="api-token-details-wide"><dt>{{ t('apiTokens.description') }}</dt><dd class="api-token-description">{{ state ? state.description || t('apiTokens.noDescription') : '—' }}</dd></div>
        </dl>
        <section class="api-token-material">
          <header><h2>{{ t('apiTokens.secret') }}</h2><GhostBtn v-if="showMaterial" @click="clearMaterial"><i class="i-mdi-eye-off-outline" aria-hidden="true" />{{ t('apiTokens.hide') }}</GhostBtn><GhostBtn v-else :loading="materialLoading" :disabled="!canReveal || blocked" @click="revealToken"><i class="i-mdi-eye-outline" aria-hidden="true" />{{ t('apiTokens.reveal') }}</GhostBtn></header>
          <p v-if="materialLoading" role="status">{{ t('apiTokens.secretLoading') }}</p>
          <PageErrorNotice v-else-if="materialProblem">{{ errorText(materialProblem) }}</PageErrorNotice>
          <SecuritySecretInput v-if="materialVisible && material" id="api-token-value" :label="t('apiTokens.secret')" :model-value="material.tokenValue" readonly copyable :reveal-duration="10000" autocomplete="off" />
          <div v-else-if="!materialLoading" class="api-token-mask" aria-hidden="true">•••• •••• •••• ••••</div>
        </section>
      </template>

      <form v-else id="api-token-form" class="api-token-form" autocomplete="off" @submit.prevent="prepareGenerate">
        <div v-if="staleEditor" class="api-token-conflict" role="status"><p>{{ t('apiTokens.errors.conflict') }}</p><GhostBtn :disabled="loading || !!problem || blocked" @click="useLatestRevision">{{ t('apiTokens.useLatest') }}</GhostBtn></div>
        <div class="api-token-field"><label for="api-token-name">{{ t('apiTokens.name') }}</label><input id="api-token-name" ref="nameInput" v-model="draft.tokenName" type="text" maxlength="255" required :disabled="blocked || requiresReview" :placeholder="t('apiTokens.namePlaceholder')" /></div>
        <div class="api-token-field"><label for="api-token-days">{{ t('apiTokens.expirationDays') }}</label><el-select id="api-token-days" v-model="draft.expirationDays" class="api-token-days" :disabled="blocked || requiresReview"><el-option v-for="days in expiryOptions" :key="days" :value="days" :label="t(presets.includes(days) ? 'apiTokens.daysOption' : 'apiTokens.customDays', { days: number(days) })" /></el-select></div>
        <div class="api-token-field"><label for="api-token-description">{{ t('apiTokens.description') }}</label><textarea id="api-token-description" v-model="draft.description" rows="5" maxlength="1000" :disabled="blocked || requiresReview" :placeholder="t('apiTokens.descriptionPlaceholder')" /><small>{{ number(draft.description.length) }} / {{ number(1000) }}</small></div>
        <p v-if="validation" class="api-token-error" role="alert">{{ t('apiTokens.errors.invalidInput') }}</p>
      </form>
    </div>

    <footer class="api-tokens-footer">
      <template v-if="screen === 'overview'"><span>{{ loading ? t('apiTokens.loading') : readTime }}</span><div class="api-tokens-docs"><a href="/swagger-ui/index.html" target="_blank" rel="noopener noreferrer"><i class="i-mdi-open-in-new" aria-hidden="true" />{{ t('apiTokens.swagger') }}</a><a href="/v3/api-docs" target="_blank" rel="noopener noreferrer">{{ t('apiTokens.schema') }}</a><button type="button" :title="authFormat" @click="copyFormat"><i class="i-mdi-content-copy" aria-hidden="true" />{{ t('apiTokens.copyFormat') }}</button><PageErrorNotice v-if="copyState === 'copyFailed'" :label="t('apiTokens.copyFailed')">{{ t('apiTokens.copyFailed') }}</PageErrorNotice><small v-else-if="copyState" role="status">{{ t(`apiTokens.${copyState}`) }}</small></div></template>
      <template v-else><span role="status">{{ contextLocked ? t('apiTokens.pending') : '' }}</span><PrimaryBtn type="submit" form="api-token-form" :disabled="!canMutate || blocked || staleEditor || !formValid"><i class="i-mdi-arrow-right" aria-hidden="true" />{{ t('apiTokens.submit') }}</PrimaryBtn></template>
    </footer>

    <el-dialog :model-value="!!confirmation" class="api-token-dialog" :title="t(confirmation?.kind === 'revoke' ? 'apiTokens.revokeTitle' : confirmation?.replacing ? 'apiTokens.replaceTitle' : 'apiTokens.createTitle')" width="520px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!contextLocked" :show-close="!contextLocked" :before-close="cancelConfirmation">
      <dl class="api-token-confirm-details"><div><dt>{{ t('apiTokens.name') }}</dt><dd>{{ confirmation?.name || '—' }}</dd></div><div v-if="confirmation?.input"><dt>{{ t('apiTokens.expirationDays') }}</dt><dd>{{ t('apiTokens.daysOption', { days: number(confirmation.input.expirationDays) }) }}</dd></div><div v-if="confirmation?.input?.description"><dt>{{ t('apiTokens.description') }}</dt><dd>{{ confirmation.input.description }}</dd></div></dl>
      <p v-if="confirmation?.kind === 'revoke'">{{ t('apiTokens.revokeHint') }}</p><p v-else-if="confirmation?.replacing">{{ t('apiTokens.replaceHint') }}</p>
      <p v-if="contextLocked" role="status">{{ t('apiTokens.pending') }}</p>
      <template #footer><GhostBtn :disabled="contextLocked" @click="cancelConfirmation">{{ t('apiTokens.cancel') }}</GhostBtn><PrimaryBtn :loading="contextLocked" @click="confirmMutation">{{ t(confirmation?.kind === 'revoke' ? 'apiTokens.confirmRevoke' : confirmation?.replacing ? 'apiTokens.confirmReplace' : 'apiTokens.confirmGenerate') }}</PrimaryBtn></template>
    </el-dialog>
    <el-dialog :model-value="discardVisible" class="api-token-dialog" :title="t('apiTokens.discardTitle')" width="460px" append-to-body :close-on-click-modal="false" :before-close="cancelDiscard"><p>{{ t('apiTokens.discardHint') }}</p><template #footer><GhostBtn @click="cancelDiscard">{{ t('apiTokens.keepEditing') }}</GhostBtn><PrimaryBtn @click="acceptDiscard">{{ t('apiTokens.discard') }}</PrimaryBtn></template></el-dialog>
  </section>
</template>
