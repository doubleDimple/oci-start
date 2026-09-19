<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { applyDocumentLocale, LOCALE_STORAGE_KEY } from '@/i18n'
import { setTheme, theme, type ThemePreference } from '@/composables/useTheme'
import { AuthError, fetchAuthBootstrap, loginPayload, oauthLoginUrl, registerAccount, resetPassword, sendLoginCode, sendResetCode, signIn, verifyResetCode, type AuthBootstrap } from '@/api/auth'
import JSEncrypt from './vendor/jsencrypt'
import { authMessages } from './messages'
import { authCopy } from './copy'
import { mountLoginMap } from './loginMap'
import TurnstileChallenge from './TurnstileChallenge.vue'

const { locale } = useI18n()
const language = computed(() => locale.value === 'en' ? 'en' : 'zh')
const copy = computed(() => authCopy[language.value])
const t = (key: string) => authMessages[language.value][key] || key
const root = ref<HTMLElement>()
const config = ref<AuthBootstrap>()
const configLoading = ref(true)
const configError = ref<unknown>()
const tab = ref<'login' | 'register'>('login')
const busy = ref(false)
const oauthBusy = ref<'github' | 'google' | ''>('')
const showPassword = ref(false)
const form = reactive({ username: '', password: '', remember: false, method: 'message' as 'message' | 'mfa', verificationCode: '', mfaCode: '', turnstileToken: '' })
const registration = reactive({ username: '', password: '', confirmation: '' })
const notice = ref<{ type: 'success' | 'error'; key?: string; detail?: string }>()
const challenge = ref<InstanceType<typeof TurnstileChallenge>>()
const allowed = computed(() => !!config.value && (!config.value.turnstileEnabled || !!form.turnstileToken))
const messageVisible = computed(() => config.value?.messageEnabled && form.method === 'message')
const mfaVisible = computed(() => config.value?.mfaEnabled && form.method === 'mfa')
const sending = ref(false)
const sendUntil = ref(0)
const now = ref(Date.now())
const countdown = computed(() => Math.max(0, Math.ceil((sendUntil.value - now.value) / 1000)))
const resetOpen = ref(false)
const resetDialog = ref<HTMLElement>()
const reset = reactive({ username: '', code: '', token: '', step: 1, busy: false, sending: false, sendUntil: 0 })
const resetNotice = ref<{ type: 'success' | 'error'; key?: string; detail?: string }>()
const resetCountdown = computed(() => Math.max(0, Math.ceil((reset.sendUntil - now.value) / 1000)))
const resetBodyController = ref<AbortController>()
const lifetime = new AbortController()
let bootstrapController: AbortController | undefined
let disposeMap: (() => void) | undefined
let clock: ReturnType<typeof setInterval> | undefined
let returnFocus: HTMLElement | null = null
let originalOverflow = ''
let disposed = false

function errorText(error: unknown) { return error instanceof AuthError ? error.detail || copy.value[error.key] : copy.value.network }
function showError(error: unknown, inReset = false) {
  if (disposed) return
  const target = inReset ? resetNotice : notice
  target.value = { type: 'error', detail: errorText(error) }
}
function noticeText(value: { key?: string; detail?: string }) { return value.detail || (value.key ? t(value.key) : '') }
async function loadConfig(blocking = true) {
  if (disposed) return
  blocking = blocking || !config.value
  bootstrapController?.abort()
  const controller = new AbortController()
  bootstrapController = controller
  if (blocking) { configLoading.value = true; configError.value = undefined }
  try {
    const loaded = await fetchAuthBootstrap(language.value, controller.signal)
    if (disposed || controller.signal.aborted) return
    if (!config.value || (form.method === 'message' && !loaded.messageEnabled) || (form.method === 'mfa' && !loaded.mfaEnabled)) {
      form.method = loaded.messageEnabled ? 'message' : 'mfa'
    }
    config.value = loaded
    if (!loaded.allowRegister) tab.value = 'login'
  } catch (error) {
    if (!disposed && !controller.signal.aborted) {
      if (blocking) configError.value = error
      else showError(error)
    }
  }
  finally { if (!disposed && !controller.signal.aborted) configLoading.value = false }
}
function changeLocale(value: 'zh' | 'en') {
  locale.value = value
  applyDocumentLocale(value)
  try { localStorage.setItem(LOCALE_STORAGE_KEY, value) } catch { /* Optional preference storage. */ }
  const url = new URL(window.location.href)
  url.searchParams.set('lang', value === 'en' ? 'en_US' : 'zh_CN')
  window.history.replaceState(window.history.state, '', url)
  void loadConfig(false)
}
function toggleAppearance() { setTheme(theme.value === 'dark' ? 'light' : 'dark') }
function changeMethod(method: 'message' | 'mfa') { form.method = method; form.verificationCode = ''; form.mfaCode = '' }
function validate(formId: string) {
  const element = root.value?.querySelector<HTMLFormElement>(`#${formId}`)
  return !!element?.reportValidity()
}
async function submitLogin() {
  if (busy.value || !allowed.value || !config.value || !validate('loginForm')) return
  busy.value = true
  notice.value = undefined
  try {
    const encryptor = new JSEncrypt()
    encryptor.setPublicKey(config.value.publicKey)
    const body = loginPayload(form, config.value, value => encryptor.encrypt(value))
    const target = await signIn(body, lifetime.signal)
    if (!disposed) window.location.assign(target)
  } catch (error) {
    if (disposed) return
    showError(error)
    const failureNotice = notice.value
    if (config.value.turnstileEnabled) challenge.value?.reset()
    // A timed-out login may have succeeded server-side and consumed its RSA key.
    // Refresh the key in place so a retry can work without losing entered fields.
    await loadConfig(false)
    if (!disposed) notice.value = failureNotice
  } finally { if (!disposed) busy.value = false }
}
async function submitRegistration() {
  if (busy.value || !config.value?.allowRegister || !validate('registerForm')) return
  if (registration.password !== registration.confirmation) { notice.value = { type: 'error', key: 'login.notMatch.password' }; return }
  busy.value = true
  notice.value = undefined
  try {
    await registerAccount(registration.username, registration.password, lifetime.signal)
    if (disposed) return
    form.username = registration.username
    registration.password = registration.confirmation = ''
    tab.value = 'login'
    notice.value = { type: 'success', key: 'login.register.success' }
    await loadConfig()
  } catch (error) { showError(error) }
  finally { if (!disposed) busy.value = false }
}
async function sendCode() {
  if (sending.value || countdown.value || !allowed.value) return
  if (!form.username.trim()) { notice.value = { type: 'error', key: 'login.username.placeholder' }; root.value?.querySelector<HTMLInputElement>('#username')?.focus(); return }
  sending.value = true
  try {
    await sendLoginCode(form.username, lifetime.signal)
    if (disposed) return
    sendUntil.value = Date.now() + 60000
    now.value = Date.now()
    notice.value = { type: 'success', key: 'login.input.code.success' }
  } catch (error) { showError(error) }
  finally { if (!disposed) sending.value = false }
}
async function oauth(provider: 'github' | 'google') {
  if (oauthBusy.value || !allowed.value) return
  oauthBusy.value = provider
  try {
    const url = await oauthLoginUrl(provider, form.remember, lifetime.signal)
    if (!disposed) window.location.assign(url)
  } catch (error) { showError(error) }
  finally { if (!disposed) oauthBusy.value = '' }
}
async function openReset() {
  returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
  originalOverflow = document.body.style.overflow
  document.body.style.overflow = 'hidden'
  resetOpen.value = true
  reset.username = form.username
  reset.code = reset.token = ''
  reset.step = 1
  resetNotice.value = undefined
  resetBodyController.value = new AbortController()
  await nextTick()
  root.value?.querySelector<HTMLInputElement>('#resetUsername')?.focus()
}
function closeReset() {
  resetBodyController.value?.abort()
  resetOpen.value = false
  reset.busy = reset.sending = false
  reset.code = reset.token = ''
  document.body.style.overflow = originalOverflow
  const target = returnFocus
  void nextTick().then(() => { if (!disposed && !resetOpen.value) target?.focus() })
}
async function sendRecoveryCode() {
  if (reset.sending || resetCountdown.value || reset.busy) return
  if (!reset.username.trim()) { resetNotice.value = { type: 'error', key: 'login.username.placeholder' }; return }
  const controller = resetBodyController.value
  reset.sending = true
  try {
    await sendResetCode(reset.username, controller?.signal)
    if (disposed || controller?.signal.aborted) return
    reset.sendUntil = Date.now() + 60000
    now.value = Date.now()
    resetNotice.value = { type: 'success', key: 'login.send.yourDevice' }
  } catch (error) { if (!controller?.signal.aborted) showError(error, true) }
  finally { if (!controller?.signal.aborted) reset.sending = false }
}
async function nextResetStep() {
  if (reset.busy || !resetOpen.value || reset.step === 3) return
  if (reset.step === 1 && (!reset.username.trim() || !reset.code.trim())) {
    resetNotice.value = { type: 'error', key: !reset.username.trim() ? 'login.username.placeholder' : 'login.verify.code.placeholder' }; return
  }
  const controller = resetBodyController.value
  reset.busy = true
  resetNotice.value = undefined
  try {
    if (reset.step === 1) {
      const token = await verifyResetCode(reset.username, reset.code, controller?.signal)
      if (disposed || controller?.signal.aborted) return
      reset.token = token
      reset.step = 2
    } else {
      if (!reset.token) { reset.step = 1; resetNotice.value = { type: 'error', key: 'login.input.verify.fail.retry' }; return }
      await resetPassword(reset.username, reset.token, controller?.signal)
      if (disposed || controller?.signal.aborted) return
      reset.token = ''
      reset.step = 3
    }
    await nextTick()
    resetDialog.value?.focus()
  } catch (error) { if (!controller?.signal.aborted) showError(error, true) }
  finally { if (!controller?.signal.aborted) reset.busy = false }
}
function cancelReset() {
  if (reset.busy) return
  if (reset.step === 2) { reset.step = 1; reset.token = ''; resetNotice.value = undefined }
  else closeReset()
}
function resetKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape' && !reset.busy) { event.preventDefault(); closeReset(); return }
  if (event.key !== 'Tab') return
  const controls = Array.from(resetDialog.value?.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), a[href]') || []).filter(el => el.getClientRects().length)
  const first = controls[0], last = controls.at(-1)
  if (event.shiftKey && (document.activeElement === first || document.activeElement === resetDialog.value)) { event.preventDefault(); last?.focus() }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus() }
}
watch(language, () => { document.title = t('login.page.title') })
onMounted(() => {
  let preference: ThemePreference = window.matchMedia('(max-width: 760px)').matches ? 'system' : 'dark'
  try {
    const stored = localStorage.getItem('oci_theme') || localStorage.getItem('mob-theme')
    if (stored === 'light' || stored === 'dark' || stored === 'system') preference = stored
    if (stored === 'auto') preference = 'system'
  } catch { /* Use the established login defaults. */ }
  setTheme(preference)
  document.title = t('login.page.title')
  const error = new URLSearchParams(window.location.search).get('error')
  if (error) notice.value = error === 'true' ? { type: 'error', key: 'login.input.userOrNameError' } : { type: 'error', detail: error }
  void loadConfig()
  if (root.value) disposeMap = mountLoginMap(root.value)
  clock = setInterval(() => { now.value = Date.now() }, 1000)
})
onBeforeUnmount(() => {
  disposed = true
  lifetime.abort()
  bootstrapController?.abort()
  resetBodyController.value?.abort()
  disposeMap?.()
  if (clock) clearInterval(clock)
  if (resetOpen.value) document.body.style.overflow = originalOverflow
})
</script>

<template>
  <main ref="root" class="auth-page" :data-theme="theme">
    <section class="stage" aria-labelledby="heroBrandName" :inert="resetOpen || undefined">
      <div class="brand">
        <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 2.5c0 0 6.8 7.4 6.8 12.1A6.8 6.8 0 0 1 12 21.4a6.8 6.8 0 0 1-6.8-6.8C5.2 9.9 12 2.5 12 2.5z" stroke="var(--brand-hi)" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 17.6a3 3 0 0 1-3-3c0-1.6 3-5 3-5s3 3.4 3 5a3 3 0 0 1-3 3z" fill="var(--brand-hi)"/></svg>
        <span id="heroBrandName" class="nm">{{ config?.siteLogoName || 'OCI-START' }} <em>/ {{ copy.workspace }}</em></span>
      </div>
      <div class="pitch"><h2>{{ copy.pitch }}</h2><p>{{ copy.description }}</p></div>
      <div class="login-map-heading"><h3 id="loginMapHeading">{{ copy.regions }}</h3><span><b id="loginMapRegionCount">—</b> {{ copy.regionUnit }}</span></div>
      <div class="mapbox login-mapbox"><canvas id="loginRegionMap" role="img" aria-labelledby="loginMapHeading" aria-describedby="loginMapNote"/><div id="loginMapTooltip" role="presentation"><strong/><span/></div></div>
      <details id="loginRegionDirectory" class="login-region-directory">
        <summary>{{ copy.directory }}</summary><ul id="loginRegionList" aria-labelledby="loginMapHeading"/><p id="loginMapUnavailable" class="login-map-unavailable">{{ copy.unavailable }}</p>
        <p id="loginMapNote" class="login-map-note">{{ copy.mapNote }}</p>
        <div class="login-map-sources"><a href="https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm" target="_blank" rel="noopener noreferrer">{{ copy.oracleDirectory }}</a><a href="https://www.geonames.org/" target="_blank" rel="noopener noreferrer">GeoNames</a><span>{{ copy.checked }} <time id="loginMapCheckedAt">—</time></span></div>
      </details>
      <div class="foot">© 2026 doubleDimple · <a href="https://github.com/doubleDimple/oci-start" target="_blank" rel="noopener">GitHub</a> · <a href="https://github.com/doubleDimple/oci-start#readme" target="_blank" rel="noopener">{{ copy.docs }}</a></div>
    </section>
    <section class="auth" :inert="resetOpen || undefined">
      <div class="topbar"><div class="lang"><button type="button" :class="{ active: language === 'zh' }" :aria-current="language === 'zh'" @click="changeLocale('zh')">中文</button><i aria-hidden="true">/</i><button type="button" :class="{ active: language === 'en' }" :aria-current="language === 'en'" @click="changeLocale('en')">EN</button></div><button id="themeToggle" class="icon-btn" type="button" :title="theme === 'dark' ? copy.light : copy.dark" :aria-label="theme === 'dark' ? copy.light : copy.dark" @click="toggleAppearance"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg></button></div>
      <div class="login-card">
        <div class="mobile-auth-mark" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M12 2.5c0 0 6.8 7.4 6.8 12.1A6.8 6.8 0 0 1 12 21.4a6.8 6.8 0 0 1-6.8-6.8C5.2 9.9 12 2.5 12 2.5z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M12 17.6a3 3 0 0 1-3-3c0-1.6 3-5 3-5s3 3.4 3 5a3 3 0 0 1-3 3z" fill="currentColor"/></svg></div>
        <div class="auth-header">
          <h1>{{ copy.welcome }}</h1>
          <p class="lede">{{ copy.lede }}</p>
        </div>
        <div v-if="notice" id="loginRedirectError" class="message" :class="`${notice.type}-message`" :role="notice.type === 'error' ? 'alert' : 'status'">{{ noticeText(notice) }}</div>
        <p v-if="configLoading" role="status">{{ copy.loading }}</p>
        <div v-else-if="configError" class="config-error"><p class="message error-message" role="alert">{{ errorText(configError) }}</p><button type="button" class="submit" @click="loadConfig()">{{ copy.retry }}</button></div>
        <template v-else-if="config">
          <div v-if="config.allowRegister" class="tab-group"><button type="button" class="tab" :class="{ active: tab === 'login' }" :aria-pressed="tab === 'login'" :disabled="busy" @click="tab = 'login'">{{ t('login.title') }}</button><button type="button" class="tab" :class="{ active: tab === 'register' }" :aria-pressed="tab === 'register'" :disabled="busy" @click="tab = 'register'">{{ t('login.register') }}</button></div>
          <form v-show="tab === 'login'" id="loginForm" class="auth-form active" novalidate @submit.prevent="submitLogin">
            <div v-if="config.turnstileEnabled" id="turnstileContainer" class="turnstile-container"><TurnstileChallenge ref="challenge" :site-key="config.turnstileSiteKey" :locale="language" :theme="theme" :retry-label="copy.retry" :failure-label="copy.challengeError" @token="form.turnstileToken = $event"/><p v-if="!allowed" id="turnstileHint">{{ copy.challenge }}</p></div>
            <div v-show="allowed" id="loginFormContent">
              <div class="field form-group">
                <label for="username">{{ t('login.username') }}</label>
                <div class="ctrl input-container has-prefix">
                  <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg></span>
                  <input id="username" v-model="form.username" type="text" name="username" class="form-control" autocomplete="username" autocapitalize="none" spellcheck="false" required :placeholder="t('login.username.placeholder')"/>
                </div>
              </div>
              <div class="field form-group">
                <label for="password">{{ t('login.password') }}</label>
                <div class="ctrl input-container password-container has-prefix">
                  <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></span>
                  <input id="password" v-model="form.password" :type="showPassword ? 'text' : 'password'" name="password" class="form-control" autocomplete="current-password" required :placeholder="t('login.password.placeholder')"/>
                  <button id="loginPasswordToggle" type="button" class="peek password-toggle" aria-controls="password" :aria-pressed="showPassword" :aria-label="showPassword ? copy.hidePassword : copy.showPassword" @click="showPassword = !showPassword">
                    <svg v-if="!showPassword" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3.8-6.5 10-6.5S22 12 22 12s-3.8 6.5-10 6.5S2 12 2 12z"/><circle cx="12" cy="12" r="2.8"/></svg>
                    <svg v-else viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                  </button>
                </div>
              </div>
              <div v-if="messageVisible" id="verificationGroup" class="field form-group">
                <label for="verificationCode">{{ t('login.verify.code') }}</label>
                <div class="verification-group">
                  <div class="verification-input has-prefix">
                    <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/></svg></span>
                    <input id="verificationCode" v-model="form.verificationCode" type="text" name="verificationCode" class="form-control" autocomplete="one-time-code" required :placeholder="t('login.verify.code.placeholder')"/>
                  </div>
                  <button id="sendCodeBtn" type="button" class="btn btn-send-code" :disabled="sending || countdown > 0" @click="sendCode">{{ sending ? t('login.input.sending') : countdown ? countdown + t('login.input.seconds.retry') : t('login.btn.send.code') }}</button>
                </div>
              </div>
              <div v-if="mfaVisible" id="mfaGroup" class="field form-group">
                <label for="mfaCode">{{ t('login.mfa.code') }}</label>
                <div class="ctrl input-container has-prefix">
                  <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></span>
                  <input id="mfaCode" v-model="form.mfaCode" type="text" name="mfaCode" class="form-control" autocomplete="one-time-code" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" required :placeholder="t('login.mfa.code.placeholder')"/>
                </div>
              </div>
              <div v-if="config.messageEnabled && config.mfaEnabled" id="verificationChoice" class="field form-group"><label>{{ t('login.verify.method') }}</label><div class="tab-group"><button id="messageTab" type="button" class="tab" :class="{ active: form.method === 'message' }" :aria-pressed="form.method === 'message'" @click="changeMethod('message')"><i class="i-mdi-email-outline" aria-hidden="true"/>{{ t('login.verify.method.msg') }}</button><button id="mfaTab" type="button" class="tab" :class="{ active: form.method === 'mfa' }" :aria-pressed="form.method === 'mfa'" @click="changeMethod('mfa')"><i class="i-mdi-shield-check-outline" aria-hidden="true"/>{{ t('login.verify.method.mfa') }}</button></div></div>
              <div class="aux form-meta"><label class="check remember-me"><input v-model="form.remember" type="checkbox" name="remember-me" value="true"/><span>{{ t('login.remember.me') }}</span></label><a href="#" class="link forgot-password-link" @click.prevent="openReset">{{ t('login.forgot.password') }}</a></div>
              <button id="loginButton" type="submit" class="submit btn btn-primary" :class="{ busy }" :disabled="busy || !allowed"><span class="spin" aria-hidden="true"/><span class="txt">{{ busy ? t('login.input.login.loading') : t('login.btn.login') }}</span></button><p class="msg" aria-hidden="true"/>
              <div v-if="config.githubEnabled || config.googleEnabled" class="auth-divider"><span>{{ copy.orThirdParty }}</span></div>
              <div v-if="config.githubEnabled || config.googleEnabled" class="oauth-row"><button v-if="config.githubEnabled" id="githubLoginBtn" type="button" class="btn btn-github btn-oauth" :disabled="!!oauthBusy || busy" @click="oauth('github')"><i class="i-mdi-github" aria-hidden="true"/><span>{{ oauthBusy === 'github' ? t('login.input.step.next') : t('login.btn.github') }}</span></button><button v-if="config.googleEnabled" id="googleLoginBtn" type="button" class="btn btn-google btn-oauth" :disabled="!!oauthBusy || busy" @click="oauth('google')"><i class="i-mdi-google" aria-hidden="true"/><span>{{ oauthBusy === 'google' ? t('login.input.step.next') : t('login.btn.google') }}</span></button></div>
              <div class="enterprise-trust-badge" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10"/></svg><span>{{ copy.securityBadge }}</span></div>
            </div>
          </form>
          <form v-if="config.allowRegister" v-show="tab === 'register'" id="registerForm" class="auth-form" novalidate @submit.prevent="submitRegistration">
            <div class="field form-group">
              <label for="registerUsername">{{ t('login.username') }}</label>
              <div class="ctrl input-container has-prefix">
                <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg></span>
                <input id="registerUsername" v-model="registration.username" type="text" name="username" class="form-control" autocomplete="username" autocapitalize="none" spellcheck="false" required :placeholder="t('login.username.placeholder')"/>
              </div>
            </div>
            <div class="field form-group">
              <label for="registerPassword">{{ t('login.password') }}</label>
              <div class="ctrl input-container has-prefix">
                <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></span>
                <input id="registerPassword" v-model="registration.password" type="password" name="password" class="form-control" autocomplete="new-password" required :placeholder="t('login.password.placeholder')"/>
              </div>
            </div>
            <div class="field form-group">
              <label for="confirmPassword">{{ t('login.confirm.password') }}</label>
              <div class="ctrl input-container has-prefix">
                <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10"/></svg></span>
                <input id="confirmPassword" v-model="registration.confirmation" type="password" name="confirmPassword" class="form-control" autocomplete="new-password" required :placeholder="t('login.confirm.password.placeholder')"/>
              </div>
            </div>
            <button type="submit" class="submit btn btn-primary" :disabled="busy">{{ busy ? t('login.input.sending') : t('login.register') }}</button>
            <div class="enterprise-trust-badge" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10"/></svg><span>{{ copy.securityBadge }}</span></div>
          </form>
        </template>
      </div>
      <div class="authfoot">
        <a href="https://github.com/doubleDimple/oci-start" target="_blank" rel="noopener noreferrer" class="authfoot-link">
          <svg viewBox="0 0 24 24" width="15" height="15" fill="currentColor" aria-hidden="true"><path d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.53 1.032 1.53 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"/></svg>
          <span>doubleDimple / oci-start</span>
        </a>
        <span class="authfoot-sep" aria-hidden="true">·</span>
        <span class="authfoot-date">{{ copy.projectStartTime }}: 2025-10-01</span>
      </div>
    </section>
    <div v-if="resetOpen" id="forgotPasswordModal" class="modal-overlay show" @click.self="!reset.busy && closeReset()" @keydown="resetKeydown">
      <div ref="resetDialog" class="modal" role="dialog" aria-modal="true" aria-labelledby="loginResetTitle" tabindex="-1">
        <div class="modal-header"><div id="loginResetTitle" class="modal-title"><i class="i-mdi-key-outline" aria-hidden="true"/> {{ t('login.reset.title') }}</div><button type="button" class="modal-close" :aria-label="copy.close" :disabled="reset.busy" @click="closeReset"><i class="i-mdi-close" aria-hidden="true"/></button></div>
        <div class="modal-steps"><div id="progressLine" class="progress-line" :style="{ width: `calc(${(reset.step - 1) / 2 * 100}% - 16px)` }"/><div v-for="step in 3" :id="`step${step}`" :key="step" class="step" :class="{ active: reset.step === step, completed: reset.step > step }"><div class="step-circle">{{ step === 3 ? '✓' : step }}</div><div class="step-label">{{ t(`login.reset.step${step}`) }}</div></div></div>
        <div class="modal-body">
          <div v-if="reset.step === 1" id="resetStep1" class="reset-step active">
            <div class="step-description">{{ t('login.reset.info1') }}</div>
            <div class="field form-group">
              <label for="resetUsername">{{ t('login.username') }}</label>
              <div class="ctrl input-container has-prefix">
                <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg></span>
                <input id="resetUsername" v-model="reset.username" type="text" class="form-control" autocomplete="username" autocapitalize="none" :disabled="reset.busy" :placeholder="t('login.username.placeholder')"/>
              </div>
            </div>
            <div class="field form-group">
              <label for="resetVerificationCode">{{ t('login.verify.code') }}</label>
              <div class="verification-group">
                <div class="verification-input has-prefix">
                  <span class="input-icon-prefix" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/></svg></span>
                  <input id="resetVerificationCode" v-model="reset.code" type="text" class="form-control" autocomplete="one-time-code" :disabled="reset.busy" :placeholder="t('login.verify.code.placeholder')" @keydown.enter.prevent="nextResetStep"/>
                </div>
                <button id="resetSendCodeBtn" type="button" class="btn btn-send-code" :disabled="reset.sending || resetCountdown > 0 || reset.busy" @click="sendRecoveryCode">{{ reset.sending ? t('login.input.sending') : resetCountdown ? resetCountdown + t('login.input.seconds.retry') : t('login.btn.send.code') }}</button>
              </div>
            </div>
          </div>
          <div v-else-if="reset.step === 2" id="resetStep2" class="reset-step active"><div class="step-description">{{ t('login.reset.info2') }}</div><div class="field form-group"><label>{{ t('login.reset.method.title') }}</label><div class="modal-box">{{ t('login.reset.method.desc') }}<ul class="modal-box-list"><li>{{ t('login.reset.method.list1') }}</li><li>{{ t('login.reset.method.list2') }}</li></ul></div></div></div>
          <div v-else id="resetStep3" class="reset-step active"><div class="step-description">{{ t('login.reset.success') }}</div><div class="modal-success"><i class="i-mdi-send-check-outline" aria-hidden="true"/><div class="modal-success-title">{{ t('login.reset.success') }}</div><div class="modal-success-sub">{{ t('login.reset.check.msg') }}</div></div></div>
          <div id="resetMessage"><div v-if="resetNotice" class="message" :class="`${resetNotice.type}-message`" :role="resetNotice.type === 'error' ? 'alert' : 'status'">{{ noticeText(resetNotice) }}</div></div>
        </div>
        <div class="modal-actions"><button id="resetCancelBtn" type="button" class="btn btn-secondary btn-modal" :disabled="reset.busy" @click="cancelReset">{{ reset.step === 3 ? copy.finish : reset.step === 2 ? copy.back : t('login.btn.cancel') }}</button><button v-if="reset.step < 3" id="resetNextBtn" type="button" class="btn btn-primary btn-modal" :disabled="reset.busy" @click="nextResetStep">{{ reset.busy ? t('login.input.resetting') : t(`login.reset.step${reset.step}`) }}</button></div>
      </div>
    </div>
  </main>
</template>

<style lang="scss" src="./login.scss"/>
