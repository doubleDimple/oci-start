<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { setSiteLogoName } from '@/composables/useSiteBrand'
import { normalizeAccountSecurity, normalizeGithubSecurity, normalizeGoogleSecurity, normalizeMfaSecurity,
  normalizeTurnstileSecurity, type SecuritySettingsApiError } from '@/api/securitySettings'
import SecuritySecretInput from './security/SecuritySecretInput.vue'
import { useSecuritySettings, type SecurityMutationKind } from './security/useSecuritySettings'
import './security/security-settings.scss'

type Section = 'account' | 'github' | 'google' | 'mfa' | 'turnstile' | 'channel'
type SecretMode = 'keep' | 'replace' | 'clear'
const sections: { id: Section; icon: string }[] = [
  { id: 'account', icon: 'i-mdi-account-outline' }, { id: 'github', icon: 'i-mdi-github' },
  { id: 'google', icon: 'i-mdi-google' }, { id: 'mfa', icon: 'i-mdi-shield-key-outline' },
  { id: 'turnstile', icon: 'i-mdi-shield-check-outline' }, { id: 'channel', icon: 'i-mdi-bell-outline' },
]
const { t, locale } = useI18n()
const router = useRouter()
const page = useSecuritySettings()
const { settings, loading, loaded, problem, lastUpdated, mutation, contextLocked, canMutate, requiresReview,
  reviewReady, needRelogin, githubLookup, mfaEnrollment, mfaLoading, mfaProblem, verification } = page
const active = ref<Section>('account')
const formHeading = ref<HTMLElement>()
const scrollArea = ref<HTMLElement>()
const account = reactive({ currentPassword: '', newUsername: '', newPassword: '', confirmPassword: '' })
const siteName = ref('')
const github = reactive({ enabled: false, userName: '', githubId: '', clientId: '', clientSecret: '', redirectUri: '' })
const google = reactive({ enabled: false, email: '', clientId: '', clientSecret: '', redirectUri: '' })
const mfa = reactive({ enabled: false, issuer: '' })
const turnstile = reactive({ enabled: false, siteKey: '', secretKey: '' })
const channel = ref(false)
const modes = reactive<Record<'github' | 'google' | 'turnstile', SecretMode>>({ github: 'replace', google: 'replace', turnstile: 'replace' })
const code = ref('')
const validation = ref('')
const confirmation = ref<SecurityMutationKind | null>(null)
const discardVisible = ref(false)
let discardAction: (() => void) | undefined
let cancelNavigation: (() => void) | undefined
let disposed = false
// Baselines hold only metadata and empty secret drafts, never saved secrets.
const baseline = reactive<Record<Section, string>>({ account: '', github: '', google: '', mfa: '', turnstile: '', channel: '' })
function snapshot(section: Section): string {
  if (section === 'account') return JSON.stringify({ ...account, siteName: siteName.value })
  if (section === 'github') return JSON.stringify({ ...github, mode: modes.github })
  if (section === 'google') return JSON.stringify({ ...google, mode: modes.google })
  if (section === 'turnstile') return JSON.stringify({ ...turnstile, mode: modes.turnstile })
  return JSON.stringify(section === 'mfa' ? mfa : channel.value)
}
const dirty = computed(() => loaded.value && snapshot(active.value) !== baseline[active.value])
const accountChanged = computed(() => !!(account.newUsername.trim() || account.newPassword))
const activeChanged = computed(() => active.value === 'account' ? accountChanged.value : dirty.value)
const disabled = computed(() => !loaded.value || loading.value || contextLocked.value || needRelogin.value || requiresReview.value || !!confirmation.value)
const oauthDraft = computed(() => active.value === 'github' ? github : google)
const secretSection = computed(() => active.value === 'github' ? 'github' : active.value === 'google' ? 'google' : 'turnstile')
const hasSecret = computed(() => secretSection.value === 'turnstile'
  ? !!settings.value?.turnstile.hasSecretKey : !!settings.value?.[secretSection.value].hasClientSecret)
const secretMode = computed({
  get: () => modes[secretSection.value],
  set(value: SecretMode) {
    modes[secretSection.value] = value
    if (secretSection.value === 'turnstile') turnstile.secretKey = ''
    else if (secretSection.value === 'github') github.clientSecret = ''
    else google.clientSecret = ''
  },
})
const enabled = computed({
  get: () => active.value === 'channel' ? channel.value : active.value === 'github' ? github.enabled
    : active.value === 'google' ? google.enabled : active.value === 'turnstile' ? turnstile.enabled : mfa.enabled,
  set(value: boolean) {
    if (active.value === 'channel') channel.value = value
    else if (active.value === 'github') github.enabled = value
    else if (active.value === 'google') google.enabled = value
    else if (active.value === 'turnstile') turnstile.enabled = value
    else mfa.enabled = value
  },
})
const updatedLabel = computed(() => lastUpdated.value ? t('securitySettings.lastUpdated', {
  time: new Intl.DateTimeFormat(locale.value, { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(lastUpdated.value),
}) : t('securitySettings.notLoaded'))
const confirmTitle = computed(() => confirmation.value ? t(`securitySettings.confirmTitles.${confirmation.value === 'channelNotify' ? 'channel' : confirmation.value}`) : '')
const confirmHint = computed(() => {
  const kind = confirmation.value
  if (kind === 'account') return t('securitySettings.confirmAccount')
  if (kind === 'logo') return t('securitySettings.confirmLogo', { name: siteName.value.trim() })
  if (kind === 'regenerateMfa') return t('securitySettings.confirmRegenerate')
  if (kind === 'deleteMfa') return t('securitySettings.confirmDelete')
  if (kind === 'mfa') return t(`securitySettings.${mfa.enabled ? 'confirmMfaEnable' : 'confirmMfaDisable'}`)
  if (kind === 'channelNotify') return t(`securitySettings.${channel.value ? 'confirmChannelEnable' : 'confirmChannelDisable'}`)
  return t(`securitySettings.${enabled.value ? 'confirmEnable' : 'confirmDisable'}`, { feature: t(`securitySettings.sections.${active.value}`) })
})
const clearsSecret = computed(() => confirmation.value !== null && ['github', 'google', 'turnstile'].includes(confirmation.value) && secretMode.value === 'clear')
const successLabel = computed(() => t(`securitySettings.${mutation.value.kind === 'logo' ? 'siteSaved'
  : mutation.value.kind === 'regenerateMfa' ? 'mfaGenerated' : mutation.value.kind === 'deleteMfa' ? 'mfaDeleted' : 'saved'}`))
function errorLabel(error: SecuritySettingsApiError | null): string { return error ? t(`securitySettings.errors.${error.key}`) : '' }
function clearAccount() { Object.assign(account, { currentPassword: '', newUsername: '', newPassword: '', confirmPassword: '' }) }
function clearEphemeral() {
  clearAccount(); github.clientSecret = ''; google.clientSecret = ''; turnstile.secretKey = ''; code.value = ''
  page.cancelGithubLookup(); page.clearMfaEnrollment(); page.clearVerification()
}
function resetSection(section: Section) {
  const saved = settings.value
  if (!saved) return
  if (section === 'account') { clearAccount(); siteName.value = saved.siteLogoName }
  if (section === 'github') {
    Object.assign(github, saved.github, { clientSecret: '' }); modes.github = saved.github.hasClientSecret ? 'keep' : 'replace'
  }
  if (section === 'google') {
    Object.assign(google, saved.google, { clientSecret: '' }); modes.google = saved.google.hasClientSecret ? 'keep' : 'replace'
  }
  if (section === 'turnstile') {
    Object.assign(turnstile, saved.turnstile, { secretKey: '' }); modes.turnstile = saved.turnstile.hasSecretKey ? 'keep' : 'replace'
  }
  if (section === 'mfa') Object.assign(mfa, { enabled: saved.mfa.enabled, issuer: saved.mfa.issuer })
  if (section === 'channel') channel.value = saved.channelNotifyEnabled
  baseline[section] = snapshot(section)
}
function resetAll() { clearEphemeral(); sections.forEach(section => resetSection(section.id)); validation.value = '' }
async function refresh() {
  await page.refresh()
  if (!disposed && !problem.value && !needRelogin.value) resetAll()
}
function requestDiscard(action: () => void, onCancel?: () => void) {
  if (discardVisible.value) { onCancel?.(); return }
  discardAction = action; cancelNavigation = onCancel; discardVisible.value = true
}
function cancelDiscard() {
  discardVisible.value = false; discardAction = undefined
  const cancel = cancelNavigation; cancelNavigation = undefined; cancel?.()
}
function acceptDiscard() {
  const action = discardAction; discardAction = undefined; cancelNavigation = undefined
  discardVisible.value = false; resetAll(); action?.()
}
function requestRefresh() {
  if (contextLocked.value || confirmation.value || needRelogin.value) return
  if (dirty.value) requestDiscard(() => { void refresh() })
  else void refresh()
}
async function activate(section: Section) {
  resetAll(); active.value = section
  if (!requiresReview.value) page.clearMutation()
  await nextTick()
  if (scrollArea.value) scrollArea.value.scrollTop = 0
  formHeading.value?.focus({ preventScroll: true })
}
function selectSection(section: Section) {
  if (section === active.value || contextLocked.value || confirmation.value || needRelogin.value) return
  if (dirty.value) requestDiscard(() => { void activate(section) })
  else void activate(section)
}
function back() { if (window.history.state?.back) router.back(); else void router.push('/boot/dashboard') }
function login() { clearEphemeral(); window.location.assign('/login') }
function acknowledge() { if (reviewReady.value) { resetAll(); page.acknowledgeReview() } }
function changeGithubName() { github.githubId = ''; page.cancelGithubLookup() }
function siteNameEnter(event: KeyboardEvent) {
  if (event.isComposing) return
  event.preventDefault(); prepare('logo')
}
function githubEnter(event: KeyboardEvent) {
  if (event.isComposing) return
  event.preventDefault(); void lookupGithub()
}
function codeEnter(event: KeyboardEvent) {
  if (event.isComposing) return
  event.preventDefault(); void verify()
}
async function lookupGithub() {
  if (disabled.value || githubLookup.value.loading) return
  const username = github.userName.trim()
  const result = await page.lookupGithub(username)
  if (!disposed && result && active.value === 'github' && github.userName.trim() === username) github.githubId = result.id
}
function updateCode(event: Event) {
  page.clearVerification(); code.value = (event.target as HTMLInputElement).value.replace(/\D/g, '').slice(0, 6)
}
async function verify() {
  if (disabled.value || verification.value.state === 'checking') return
  validation.value = ''
  if (!/^\d{6}$/.test(code.value)) { validation.value = 'code'; return }
  const submittedCode = code.value; code.value = ''
  await page.verifyMfa(submittedCode)
}
function hideMfa() { page.clearMfaEnrollment(); code.value = ''; page.clearVerification() }
function prepare(kind: SecurityMutationKind) {
  if (!canMutate.value || confirmation.value) return
  validation.value = ''
  if (kind === 'account' && account.newPassword !== account.confirmPassword) { validation.value = 'passwordMismatch'; return }
  if (kind === 'logo' && siteName.value.trim() === settings.value?.siteLogoName) return
  if (kind === 'logo' && (!siteName.value.trim() || siteName.value.trim().length > 15)) { validation.value = 'site'; return }
  if (['github', 'google', 'turnstile'].includes(kind)
    && ((secretMode.value === 'clear' && enabled.value) || (secretMode.value === 'replace'
      && !(kind === 'turnstile' ? turnstile.secretKey : oauthDraft.value.clientSecret).trim()))) { validation.value = 'secret'; return }
  try {
    if (kind === 'account') normalizeAccountSecurity(account)
    if (kind === 'github') normalizeGithubSecurity({ ...github, keepSecret: modes.github === 'keep' })
    if (kind === 'google') normalizeGoogleSecurity({ ...google, keepSecret: modes.google === 'keep' })
    if (kind === 'turnstile') normalizeTurnstileSecurity({ ...turnstile, keepSecret: modes.turnstile === 'keep' })
    if (kind === 'mfa') normalizeMfaSecurity(mfa)
  } catch {
    validation.value = kind === 'account' ? 'account' : kind === 'mfa' ? 'mfa' : kind === 'turnstile' ? 'turnstile' : 'oauth'
    return
  }
  page.cancelGithubLookup(); page.clearVerification(); confirmation.value = kind
}
function prepareActive() { prepare(active.value === 'channel' ? 'channelNotify' : active.value) }
function closeConfirmation() { if (!contextLocked.value) confirmation.value = null }
async function submit() {
  const kind = confirmation.value
  if (!kind || !canMutate.value) return
  if (kind === 'account') await page.saveAccount(account)
  else if (kind === 'logo') await page.saveLogo(siteName.value)
  else if (kind === 'github') await page.saveGithub({ ...github, keepSecret: modes.github === 'keep' })
  else if (kind === 'google') await page.saveGoogle({ ...google, keepSecret: modes.google === 'keep' })
  else if (kind === 'mfa') await page.saveMfa(mfa)
  else if (kind === 'turnstile') await page.saveTurnstile({ ...turnstile, keepSecret: modes.turnstile === 'keep' })
  else if (kind === 'channelNotify') await page.saveChannelNotify(channel.value)
  else if (kind === 'regenerateMfa') await page.regenerateMfa()
  else await page.deleteMfa()
  if (disposed) return
  confirmation.value = null
  if (kind === 'account') { account.currentPassword = ''; account.newPassword = ''; account.confirmPassword = '' }
  if (kind === 'github') github.clientSecret = ''
  if (kind === 'google') google.clientSecret = ''
  if (kind === 'turnstile') turnstile.secretKey = ''
  code.value = ''
  if (mutation.value.outcome === 'success') {
    if (kind === 'logo' && mutation.value.result?.logoName !== undefined) {
      // A newer successful read takes precedence; a failed read still has a confirmed save receipt.
      const name = (!problem.value || problem.value.key === 'saveMismatch') && settings.value
        ? settings.value.siteLogoName : mutation.value.result.logoName
      setSiteLogoName(name); siteName.value = name
      baseline.account = JSON.stringify({ currentPassword: '', newUsername: '', newPassword: '', confirmPassword: '', siteName: name })
    } else if (!problem.value && !needRelogin.value) resetSection(active.value)
  } else if (mutation.value.outcome === 'unknown' && !problem.value && !needRelogin.value) {
    // Show the actual read-back before offering acknowledgement of an unknown write.
    resetSection(active.value)
  }
  if (scrollArea.value) scrollArea.value.scrollTop = 0
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (!needRelogin.value && (dirty.value || contextLocked.value || requiresReview.value)) { event.preventDefault(); event.returnValue = '' }
}
function visibilityChanged() { if (document.hidden) hideMfa() }
onBeforeRouteLeave(() => {
  if (needRelogin.value) return true
  if (contextLocked.value || confirmation.value || requiresReview.value) return false
  if (!dirty.value) return true
  return new Promise<boolean>(resolve => requestDiscard(() => resolve(true), () => resolve(false)))
})
onMounted(() => {
  window.addEventListener('beforeunload', beforeUnload)
  document.addEventListener('visibilitychange', visibilityChanged)
  void refresh()
})
onBeforeUnmount(() => {
  disposed = true; clearEphemeral(); cancelNavigation?.()
  discardAction = undefined; cancelNavigation = undefined
  window.removeEventListener('beforeunload', beforeUnload)
  document.removeEventListener('visibilitychange', visibilityChanged)
})
</script>

<template>
  <section class="security-settings" :aria-label="t('securitySettings.title')">
    <header class="security-toolbar" data-page-error-anchor>
      <PageBackButton :disabled="contextLocked || requiresReview || !!confirmation" @click="back" />
      <span class="security-read-time">{{ loading ? t('securitySettings.loading') : updatedLabel }}</span>
      <GhostBtn :loading="loading" :disabled="contextLocked || needRelogin || !!confirmation" @click="requestRefresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('securitySettings.refresh') }}</GhostBtn>
    </header>
    <div class="security-workspace">
      <nav class="security-nav" :aria-label="t('securitySettings.title')">
        <button v-for="section in sections" :key="section.id" type="button" :class="{ 'is-active': active === section.id }"
          :aria-current="active === section.id ? 'page' : undefined" :disabled="contextLocked || needRelogin || !!confirmation" @click="selectSection(section.id)">
          <i :class="section.icon" aria-hidden="true" /><span>{{ t(`securitySettings.sections.${section.id}`) }}</span>
        </button>
      </nav>
      <div class="security-content">
        <div ref="scrollArea" class="security-scroll">
          <div v-if="needRelogin" class="security-notice" role="status">
            <p>{{ t(`securitySettings.${mutation.outcome === 'unknown' ? 'reloginUnknown' : 'relogin'}`) }}</p>
            <PrimaryBtn @click="login">{{ t('securitySettings.login') }}</PrimaryBtn>
          </div>
          <div v-else-if="requiresReview" class="security-notice is-warning" role="alert">
            <p>{{ t('securitySettings.unknownResult') }}</p>
            <div class="security-actions"><GhostBtn :loading="loading" :disabled="contextLocked" @click="requestRefresh">{{ t('securitySettings.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady" @click="acknowledge">{{ t('securitySettings.reviewed') }}</GhostBtn></div>
          </div>
          <div v-else-if="mutation.outcome === 'success' && !contextLocked" class="security-notice" role="status">
            <p>{{ successLabel }}</p><GhostBtn @click="page.clearMutation">{{ t('securitySettings.dismiss') }}</GhostBtn>
          </div>
          <PageErrorNotice v-if="problem">{{ errorLabel(problem) }} {{ loaded ? t('securitySettings.retained') : '' }}</PageErrorNotice>
          <PageErrorNotice v-if="mutation.outcome === 'failed'">{{ errorLabel(mutation.problem) }}</PageErrorNotice>
          <div class="security-section-title">
            <div><h2 ref="formHeading" tabindex="-1">{{ t(`securitySettings.sections.${active}`) }}</h2><p>{{ t(`securitySettings.descriptions.${active}`) }}</p></div>
            <label v-if="active !== 'account'" class="security-toggle"><span>{{ loaded ? t(`securitySettings.${enabled ? 'enabled' : 'disabled'}`) : '—' }}</span><input v-model="enabled" type="checkbox" role="switch" :aria-label="t('securitySettings.enable')" :disabled="disabled" /><span class="security-switch" aria-hidden="true" /></label>
          </div>
          <form id="security-settings-form" class="security-form" :aria-busy="loading || contextLocked" @submit.prevent="prepareActive">
            <fieldset :disabled="disabled">
              <template v-if="active === 'account'">
                <div class="security-field"><span class="security-label">{{ t('securitySettings.currentUser') }}</span><strong class="security-current-user">{{ settings?.currentUsername || '—' }}</strong></div>
                <div class="security-field"><label for="security-site-name">{{ t('securitySettings.siteName') }}</label><div class="security-input-action"><input id="security-site-name" v-model="siteName" type="text" maxlength="15" autocomplete="off" @keydown.enter="siteNameEnter" /><GhostBtn :disabled="!canMutate || siteName.trim() === settings?.siteLogoName" @click="prepare('logo')"><i class="i-mdi-check" aria-hidden="true" />{{ t('securitySettings.saveSite') }}</GhostBtn></div><small>{{ t('securitySettings.siteHint') }}</small></div>
                <div class="security-divider" />
                <SecuritySecretInput id="security-current-password" v-model="account.currentPassword" :disabled="disabled" :label="t('securitySettings.currentPassword')" autocomplete="current-password" />
                <div class="security-field"><label for="security-new-username">{{ t('securitySettings.newUsername') }}</label><input id="security-new-username" v-model="account.newUsername" type="text" autocomplete="username" :placeholder="settings?.currentUsername" autocapitalize="off" :spellcheck="false" /></div>
                <div class="security-pair"><SecuritySecretInput id="security-new-password" v-model="account.newPassword" :disabled="disabled" :label="t('securitySettings.newPassword')" /><SecuritySecretInput id="security-confirm-password" v-model="account.confirmPassword" :disabled="disabled" :label="t('securitySettings.confirmPassword')" /></div>
                <p class="security-help">{{ t('securitySettings.accountHint') }}</p>
              </template>
              <template v-else-if="active === 'github' || active === 'google'">
                <template v-if="active === 'github'">
                  <div class="security-field"><label for="security-github-user">{{ t('securitySettings.githubUsername') }}</label><div class="security-input-action"><input id="security-github-user" v-model="github.userName" type="text" autocomplete="off" autocapitalize="off" :spellcheck="false" @input="changeGithubName" @keydown.enter="githubEnter" /><GhostBtn :loading="githubLookup.loading" :disabled="disabled || !github.userName.trim()" @click="lookupGithub"><i class="i-mdi-account-search-outline" aria-hidden="true" />{{ t('securitySettings.lookupGithub') }}</GhostBtn></div><small>{{ t('securitySettings.lookupHint') }}</small><PageErrorNotice v-if="githubLookup.problem">{{ errorLabel(githubLookup.problem) }}</PageErrorNotice></div>
                  <div class="security-field"><label for="security-github-id">{{ t('securitySettings.githubId') }}</label><input id="security-github-id" :value="github.githubId" type="text" readonly placeholder="—" /></div>
                </template>
                <div v-else class="security-field"><label for="security-google-email">{{ t('securitySettings.googleEmail') }}</label><input id="security-google-email" v-model="google.email" type="email" autocomplete="off" :spellcheck="false" /></div>
                <div class="security-field"><label for="security-oauth-client-id">{{ t('securitySettings.clientId') }}</label><input id="security-oauth-client-id" v-model="oauthDraft.clientId" type="text" autocomplete="off" :spellcheck="false" /></div>
                <div class="security-field"><label for="security-secret-mode">{{ t('securitySettings.secretMode') }}</label><el-select id="security-secret-mode" v-model="secretMode" :disabled="disabled" :teleported="true"><el-option v-if="hasSecret" value="keep" :label="t('securitySettings.keepSecret')" /><el-option value="replace" :label="t('securitySettings.replaceSecret')" /><el-option value="clear" :disabled="enabled" :label="t('securitySettings.clearSecret')" /></el-select><small>{{ t(`securitySettings.${secretMode === 'clear' ? 'clearHint' : hasSecret ? 'keepHint' : 'noSecret'}`) }}</small></div>
                <SecuritySecretInput v-if="secretMode === 'replace'" :key="active" id="security-oauth-secret" v-model="oauthDraft.clientSecret" :disabled="disabled" :label="t('securitySettings.clientSecret')" />
                <div class="security-field"><label for="security-oauth-callback">{{ t('securitySettings.callback') }}</label><input id="security-oauth-callback" v-model="oauthDraft.redirectUri" type="url" autocomplete="off" :spellcheck="false" :placeholder="t(`securitySettings.${active === 'github' ? 'githubCallback' : 'googleCallback'}`)" /></div>
              </template>
              <template v-else-if="active === 'mfa'">
                <div class="security-field"><label for="security-mfa-issuer">{{ t('securitySettings.issuer') }}</label><input id="security-mfa-issuer" v-model="mfa.issuer" type="text" placeholder="OCI-Start Verify" autocomplete="off" /><small>{{ t('securitySettings.issuerHint') }}</small></div>
                <div class="security-divider" />
                <div class="security-material-heading"><h3>{{ t('securitySettings.material') }}</h3><span>{{ loaded ? t(`securitySettings.${settings?.mfa.hasSecretKey ? 'configured' : 'notConfigured'}`) : '—' }}</span></div>
                <div class="security-actions"><GhostBtn v-if="settings?.mfa.hasSecretKey && !mfaEnrollment" :loading="mfaLoading" :disabled="disabled" @click="page.loadMfaEnrollment"><i class="i-mdi-qrcode" aria-hidden="true" />{{ t('securitySettings.revealMfa') }}</GhostBtn><GhostBtn v-if="mfaEnrollment" @click="hideMfa"><i class="i-mdi-eye-off-outline" aria-hidden="true" />{{ t('securitySettings.hideMfa') }}</GhostBtn><GhostBtn :disabled="!canMutate || dirty" @click="prepare('regenerateMfa')"><i class="i-mdi-key-plus" aria-hidden="true" />{{ t(`securitySettings.${settings?.mfa.hasSecretKey ? 'regenerateMfa' : 'generateMfa'}`) }}</GhostBtn></div>
                <p v-if="!settings?.mfa.hasSecretKey" class="security-help">{{ t('securitySettings.mfaMissing') }}</p>
                <PageErrorNotice v-if="mfaProblem">{{ errorLabel(mfaProblem) }}</PageErrorNotice>
                <div v-if="mfaEnrollment" class="security-enrollment">
                  <img v-if="mfaEnrollment.qrCode" :src="`data:image/png;base64,${mfaEnrollment.qrCode}`" :alt="t('securitySettings.qrAlt')" width="180" height="180" />
                  <div><SecuritySecretInput id="security-mfa-secret" :model-value="mfaEnrollment.secretKey || ''" :label="t('securitySettings.mfaSecret')" readonly copyable autocomplete="off" :disabled="disabled" /><p class="security-help">{{ t('securitySettings.mfaMaterialHint') }}</p></div>
                </div>
                <div v-if="settings?.mfa.hasSecretKey" class="security-field">
                  <label for="security-mfa-code">{{ t('securitySettings.verificationCode') }}</label><div class="security-input-action security-code"><input id="security-mfa-code" :value="code" type="text" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="000000" :disabled="verification.state === 'checking'" @input="updateCode" @keydown.enter="codeEnter" /><GhostBtn :loading="verification.state === 'checking'" :disabled="disabled || !/^\d{6}$/.test(code)" @click="verify"><i class="i-mdi-check" aria-hidden="true" />{{ t('securitySettings.verify') }}</GhostBtn></div>
                  <small>{{ t('securitySettings.mfaVerifyHint') }}</small><small v-if="verification.state === 'passed'" role="status">{{ t('securitySettings.verificationPassed') }}</small>
                  <small v-if="verification.state === 'failed' && verification.problem?.key === 'verifyFailed'" class="security-inline-error" role="alert">{{ errorLabel(verification.problem) }}</small>
                  <PageErrorNotice v-else-if="verification.state === 'failed'">{{ errorLabel(verification.problem) }}</PageErrorNotice>
                </div>
                <div v-if="settings?.mfa.hasSecretKey || settings?.mfa.enabled" class="security-danger-row"><GhostBtn danger :disabled="!canMutate || dirty" @click="prepare('deleteMfa')"><i class="i-mdi-delete-outline" aria-hidden="true" />{{ t('securitySettings.deleteMfa') }}</GhostBtn></div>
              </template>
              <template v-else-if="active === 'turnstile'">
                <div class="security-field"><label for="security-turnstile-site">{{ t('securitySettings.siteKey') }}</label><input id="security-turnstile-site" v-model="turnstile.siteKey" type="text" autocomplete="off" :spellcheck="false" /><small>{{ t('securitySettings.turnstileHint') }}</small></div>
                <div class="security-field"><label for="security-turnstile-mode">{{ t('securitySettings.secretMode') }}</label><el-select id="security-turnstile-mode" v-model="secretMode" :disabled="disabled" :teleported="true"><el-option v-if="hasSecret" value="keep" :label="t('securitySettings.keepSecret')" /><el-option value="replace" :label="t('securitySettings.replaceSecret')" /><el-option value="clear" :disabled="enabled" :label="t('securitySettings.clearSecret')" /></el-select><small>{{ t(`securitySettings.${secretMode === 'clear' ? 'clearHint' : hasSecret ? 'keepHint' : 'noSecret'}`) }}</small></div>
                <SecuritySecretInput v-if="secretMode === 'replace'" id="security-turnstile-secret" v-model="turnstile.secretKey" :disabled="disabled" :label="t('securitySettings.secretKey')" />
              </template>
              <p v-else class="security-help">{{ t('securitySettings.channelHint') }}</p>
            </fieldset>
            <p v-if="validation" class="security-inline-error" role="alert">{{ t(`securitySettings.validation.${validation}`) }}</p>
          </form>
        </div>
        <footer class="security-footer"><span role="status">{{ contextLocked ? t('securitySettings.submitting') : dirty ? t('securitySettings.dirty') : '' }}</span><PrimaryBtn type="submit" form="security-settings-form" :loading="contextLocked" :disabled="!canMutate || !activeChanged || !!confirmation"><i class="i-mdi-check" aria-hidden="true" />{{ t(`securitySettings.${active === 'account' ? 'accountSave' : 'save'}`) }}</PrimaryBtn></footer>
      </div>
    </div>
    <el-dialog :model-value="!!confirmation" class="security-confirm-dialog" :title="confirmTitle" width="520px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!contextLocked" :show-close="!contextLocked" :before-close="closeConfirmation">
      <p>{{ confirmHint }}</p><p v-if="clearsSecret" class="security-confirm-warning">{{ t('securitySettings.confirmClearSecret') }}</p><p v-if="contextLocked" role="status">{{ t('securitySettings.submitting') }}</p>
      <template #footer><GhostBtn :disabled="contextLocked" @click="closeConfirmation">{{ t('securitySettings.cancel') }}</GhostBtn><PrimaryBtn :loading="contextLocked" :disabled="!canMutate" @click="submit">{{ t('securitySettings.confirm') }}</PrimaryBtn></template>
    </el-dialog>
    <el-dialog :model-value="discardVisible" class="security-confirm-dialog" :title="t('securitySettings.discardTitle')" width="480px" append-to-body :close-on-click-modal="false" :before-close="cancelDiscard">
      <p>{{ t('securitySettings.discardHint') }}</p><template #footer><GhostBtn @click="cancelDiscard">{{ t('securitySettings.keepEditing') }}</GhostBtn><PrimaryBtn @click="acceptDiscard">{{ t('securitySettings.discard') }}</PrimaryBtn></template>
    </el-dialog>
  </section>
</template>
