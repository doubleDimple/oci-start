import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, nextTick, ref } from 'vue'

// Run the production form and template locally: no backend, real credentials,
// clipboard, verification messages or network are used.
const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`
const sourceUrl = async path => moduleUrl(await readFile(new URL(path, import.meta.url), 'utf8'))
const authUrl = await sourceUrl('../src/api/auth.ts')
const auth = await import(authUrl)
const credentials = await import(await sourceUrl('../src/utils/initialCredentials.ts'))
const vueUrl = import.meta.resolve('vue')
const messagesUrl = await sourceUrl('../src/views/auth/messages.ts')
const copyUrl = await sourceUrl('../src/views/auth/copy.ts')
const source = await readFile(new URL('../src/views/auth/LoginView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(source, { filename: 'LoginView.vue' })
const script = compileScript(descriptor, { id: 'login-offline' })
const setup = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_statement, bindings, _quote, dependency) => {
  if (dependency === 'vue') return `import ${bindings.replace(/\bonMounted\b,?\s*/, '')} from '${vueUrl}'; ${bindings.includes('onMounted') ? 'const onMounted = () => {}' : ''}`
  if (dependency === 'vue-i18n') return 'const useI18n = () => globalThis.loginViewFixture.i18n'
  if (dependency === '@/i18n') return "const applyDocumentLocale = () => {}; const LOCALE_STORAGE_KEY = 'locale'"
  if (dependency === '@/composables/useTheme') return 'const theme = globalThis.loginViewTheme; const setTheme = value => { theme.value = value }'
  if (dependency === '@/api/auth') {
    if (bindings.includes('resetPassword')) return _statement
    return `import { AuthError, isLoginVerificationCode, loginPayload, normalizeLoginVerificationCode } from '${authUrl}'; ${['fetchAuthBootstrap', 'oauthLoginUrl', 'registerAccount', 'sendLoginCode', 'signIn'].map(name => `const ${name} = (...args) => globalThis.loginViewFixture.api.${name}(...args);`).join(' ')}`
  }
  if (dependency === '@/utils/initialCredentials') return `const { ${['copyCredentialText', 'generateInitialCredentials', 'isReservedRegistrationUsername'].join(', ')} } = { ${['copyCredentialText', 'generateInitialCredentials', 'isReservedRegistrationUsername'].map(name => `${name}: (...args) => globalThis.loginViewFixture.credentials.${name}(...args)`).join(', ')} }`
  if (dependency === './vendor/jsencrypt') return 'class JSEncrypt { setPublicKey() {} encrypt() { return "fixture-ciphertext" } }'
  if (dependency === './messages') return `import ${bindings} from '${messagesUrl}'`
  if (dependency === './copy') return `import ${bindings} from '${copyUrl}'`
  if (dependency === './loginMap') return 'const mountLoginMap = () => () => {}'
  if (dependency.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
  throw new Error(`Unstubbed dependency: ${dependency}`)
})
const template = compileTemplate({ source: descriptor.template.content, filename: 'LoginView.vue', id: 'login-offline',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false } })
assert.deepEqual(template.errors, [])
globalThis.loginViewTheme = ref('light')
const { default: LoginView } = await import(moduleUrl(setup))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))
const node = type => ({ type, tagName: type.toUpperCase(), children: [], parent: null, props: {}, style: {}, addEventListener() {}, removeEventListener() {},
  getRootNode() { return { activeElement: null } },
  querySelector(selector) { return flatten(this).find(element => element.props.id === selector.slice(1)) || null },
  reportValidity() { return true }, focus() {},
  setAttribute(key, value) { this.props[key] = value }, removeAttribute(key) { delete this.props[key] } })
const flatten = element => [element, ...element.children.flatMap(flatten)]
const textContent = element => element.type === '#comment' ? '' : `${element.text || ''}${element.children.map(textContent).join('')}`
const renderer = createRenderer({
  createElement: node, createText: text => ({ ...node('#text'), text }), createComment: text => ({ ...node('#comment'), text }),
  setText: (element, text) => { element.text = text }, setElementText: (element, text) => { element.text = text; element.children = [] },
  patchProp: (element, key, _previous, value) => { element.props[key] = value },
  insert(element, parent, anchor) {
    if (element.parent) element.parent.children = element.parent.children.filter(child => child !== element)
    const index = anchor ? parent.children.indexOf(anchor) : -1
    if (index < 0) parent.children.push(element); else parent.children.splice(index, 0, element)
    element.parent = parent
  },
  remove: element => { if (element.parent) element.parent.children = element.parent.children.filter(child => child !== element) },
  parentNode: element => element.parent, nextSibling: element => element.parent?.children[element.parent.children.indexOf(element) + 1] || null,
})
const config = { siteLogoName: 'OCI', publicKey: 'fixture', allowRegister: true, githubEnabled: false, googleEnabled: false, turnstileEnabled: false, turnstileSiteKey: '', messageEnabled: false, mfaEnabled: false, locale: 'zh_CN' }
async function settle() { for (let count = 0; count < 4; count++) { await Promise.resolve(); await nextTick() } }
async function view(t, overrides = {}) {
  const state = { generated: 0, copied: [], registered: [], signedIn: [], sentCodes: [], oauthCalls: [], bootstrapCalls: 0, redirects: [], bootstrap: { ...config, ...overrides }, i18n: { locale: ref('zh') }, theme: globalThis.loginViewTheme }
  state.api = { ...auth,
    async fetchAuthBootstrap() { state.bootstrapCalls++; if (state.bootstrapError) throw state.bootstrapError; return { ...state.bootstrap } },
    async registerAccount(...args) { state.registered.push(args); if (state.registrationError) throw state.registrationError; state.bootstrap.allowRegister = false },
    async signIn(payload) { state.signedIn.push(payload); if (state.signInError) throw state.signInError; return '/index' },
    async sendLoginCode(username) { state.sentCodes.push(username); if (state.sendError) throw state.sendError },
    async oauthLoginUrl(provider) { state.oauthCalls.push(provider); if (state.oauthError) throw state.oauthError; return 'https://example.invalid/authorize' },
  }
  state.credentials = { ...credentials,
    generateInitialCredentials() { state.generated++; return { username: `u_fixture${state.generated}`, password: `Fixture-only-password-${state.generated}!` } },
    async copyCredentialText(value) { state.copied.push(value); return state.copyResult !== false },
  }
  const previous = Object.fromEntries(['loginViewFixture', 'document', 'Document', 'ShadowRoot', 'window'].map(key => [key, globalThis[key]]))
  Object.assign(globalThis, { loginViewFixture: state, document: { activeElement: null }, Document: class {}, ShadowRoot: class {}, window: { location: { assign: value => state.redirects.push(value) } } })
  t.mock.method(globalThis, 'fetch', () => { throw new Error('Network is forbidden') })
  const container = node('root')
  const app = renderer.createApp({ ...LoginView, render })
  const vm = app.mount(container).$.setupState
  t.after(() => { app.unmount(); Object.assign(globalThis, previous) })
  vm.config = { ...config, ...overrides }
  vm.configLoading = false
  await settle()
  return { state, container, vm }
}

test('registration generates once on first display and preserves edits across configuration, language, theme and tab changes', async t => {
  const { state, vm, container } = await view(t)
  assert.equal(state.generated, 0)
  vm.tab = 'register'; await settle()
  assert.equal(state.generated, 1)
  assert.equal(vm.registration.confirmation, vm.registration.password)
  assert.match(textContent(container), /注册前请复制并保存用户名和密码/)
  Object.assign(vm.registration, { username: 'MyAccount', password: 'My edited password', confirmation: 'My edited confirmation' })
  state.i18n.locale.value = 'en'; state.theme.value = 'dark'; await vm.loadConfig(false)
  vm.tab = 'login'; await settle(); vm.tab = 'register'; await settle()
  assert.equal(state.generated, 1)
  assert.deepEqual({ ...vm.registration }, { username: 'MyAccount', password: 'My edited password', confirmation: 'My edited confirmation' })
  assert.match(textContent(container), /Copy and save your username and password before registering/)
  assert.equal(state.copied.length, 0)
  vm.regenerateRegistration(); await settle()
  assert.equal(state.generated, 2)
  assert.equal(vm.registration.confirmation, vm.registration.password)
  assert.equal(vm.registration.username, 'u_fixture2')
})

test('an already-filled registration draft and a closed registration page never get automatic suggestions', async t => {
  const { state, vm } = await view(t)
  Object.assign(vm.registration, { username: 'TypedFirst', password: 'edited', confirmation: 'edited' })
  vm.tab = 'register'; await settle()
  assert.equal(state.generated, 0)
  assert.equal(vm.registration.username, 'TypedFirst')
  vm.config = { ...config, allowRegister: false }; await settle()
  vm.regenerateRegistration(); await vm.copyRegistration('username'); await vm.submitRegistration()
  assert.equal(vm.registration.password, '')
  assert.equal(vm.registration.confirmation, '')
  assert.equal(state.generated, 0)
  assert.equal(state.registered.length, 0)
  assert.equal(state.copied.length, 0)
})

test('reserved registration usernames show an inline error and block requests without affecting existing-user login', async t => {
  const { state, vm, container } = await view(t)
  vm.tab = 'register'; await settle()
  vm.registration.username = ' ＡＤＭＩＮ１２３ '; await settle()
  assert.equal(container.querySelector('#registerUsername').props['aria-invalid'], true)
  assert.match(textContent(container.querySelector('#register-username-error')), /不可用于注册/)
  await vm.submitRegistration()
  assert.equal(state.registered.length, 0)
  vm.tab = 'login'; vm.form.username = 'admin'; vm.form.password = 'existing-account-password'; await settle()
  await vm.submitLogin()
  assert.equal(state.signedIn.length, 1)
  assert.equal(state.signedIn[0].get('username'), 'admin')
})

test('explicit copy actions trim the username and show a manual-copy fallback when clipboard access fails', async t => {
  const { state, vm, container } = await view(t)
  vm.tab = 'register'; await settle()
  vm.registration.username = ' MyAccount '
  await vm.copyRegistration('username')
  assert.deepEqual(state.copied, ['MyAccount'])
  assert.equal(vm.registration.username, 'MyAccount')
  state.copyResult = false
  await vm.copyRegistration('password'); await settle()
  assert.equal(vm.copyingCredentials, false)
  assert.match(textContent(container), /复制失败，请选中输入框内容手动复制/)
  assert.equal(vm.registration.password, 'Fixture-only-password-1!')
})

test('successful registration uses the trimmed username then clears generated secrets and returns to login', async t => {
  const { state, vm } = await view(t)
  vm.tab = 'register'; await settle()
  vm.registration.username = ' MyAccount '
  vm.showRegistrationPassword = true
  await vm.submitRegistration(); await settle()
  assert.equal(state.registered.length, 1)
  assert.equal(state.registered[0][0], 'MyAccount')
  assert.equal(vm.form.username, 'MyAccount')
  assert.equal(vm.registration.password, '')
  assert.equal(vm.registration.confirmation, '')
  assert.equal(vm.showRegistrationPassword, false)
  assert.equal(vm.config.allowRegister, false)
  assert.equal(vm.tab, 'login')
})

test('registration rejection retains editable credentials and shows the actual backend message', async t => {
  const { state, vm, container } = await view(t)
  vm.tab = 'register'; await settle()
  state.registrationError = new auth.AuthError('failed', 'Registration was closed by another request')
  await vm.submitRegistration(); await settle()
  assert.equal(vm.registration.password, 'Fixture-only-password-1!')
  assert.equal(vm.tab, 'register')
  assert.equal(vm.busy, false)
  assert.match(textContent(container), /Registration was closed by another request/)
})

test('message login inputs and requests use eight uppercase ASCII characters while MFA stays six digits', async t => {
  const { state, vm, container } = await view(t, { messageEnabled: true, mfaEnabled: true })
  const input = container.querySelector('#verificationCode')
  assert.equal(input.props.maxlength, '8')
  assert.equal(input.props.pattern, '[A-Z0-9]{8}')
  vm.form.username = 'fixture'; vm.form.password = 'fixture'; vm.form.verificationCode = '123456'
  await vm.submitLogin(); await settle()
  assert.equal(state.signedIn.length, 0)
  assert.match(textContent(container), /8位大写字母或数字/)
  const target = { value: 'ab12cd34' }
  vm.setVerificationCode({ target })
  assert.equal(target.value, 'AB12CD34')
  await vm.submitLogin()
  assert.equal(state.signedIn[0].get('verificationCode'), 'AB12CD34')
  vm.changeMethod('mfa'); await settle()
  const mfa = container.querySelector('#mfaCode')
  assert.equal(mfa.props.maxlength, '6')
  assert.equal(mfa.props.pattern, '[0-9]{6}')
  vm.form.mfaCode = '654321'; await vm.submitLogin()
  assert.equal(state.signedIn[1].get('mfaCode'), '654321')
  assert.equal(state.signedIn[1].has('verificationCode'), false)
})

const blockedStatus = { loginBlocked: true, loginBlockedUntil: '2000-01-02T00:00+08:00', loginBlockedMessage: '本站今天已暂停所有新登录，请明天再试' }

test('server-wide login block shows no recovery time, disables every new-login action, and keeps registration separate', async t => {
  const { state, vm, container } = await view(t, { ...blockedStatus, messageEnabled: true, githubEnabled: true, googleEnabled: true })
  Object.assign(vm.form, { username: 'Existing', password: 'Keep this draft', verificationCode: 'AB12CD34' })
  await settle()
  assert.match(textContent(container), /登录入口已封禁/)
  assert.doesNotMatch(textContent(container), /2000-01-02|UTC\+08:00|明天|次日|午夜|恢复时间/)
  const banner = flatten(container).find(element => element.props['aria-labelledby'] === 'login-access-title')
  assert.ok(banner)
  assert.equal(flatten(banner).some(element => element.type === 'time'), false)
  state.i18n.locale.value = 'en'; await settle()
  assert.match(textContent(container), /Sign-in is blocked site-wide/)
  assert.doesNotMatch(textContent(container), /2000-01-02|UTC\+08:00|明天|tomorrow|next day|midnight|Resumes at/i)
  state.i18n.locale.value = 'zh'; await settle()
  for (const id of ['loginButton', 'sendCodeBtn', 'githubLoginBtn', 'googleLoginBtn']) assert.equal(container.querySelector('#' + id).props.disabled, true, id)
  await vm.submitLogin(); await vm.sendCode(); await vm.oauth('github'); await vm.oauth('google')
  assert.equal(state.signedIn.length + state.sentCodes.length + state.oauthCalls.length, 0)
  assert.equal(vm.form.username, 'Existing')
  assert.equal(vm.form.password, 'Keep this draft')
  assert.equal(vm.form.verificationCode, 'AB12CD34')
  // Even a deadline in the past cannot unlock without a fresh server response.
  vm.now = Date.now() + 86400000
  assert.equal(vm.loginDisabled, true)
  vm.tab = 'register'; await settle(); await vm.submitRegistration()
  assert.equal(state.registered.length, 1)
})

test('refresh only reopens login after the server reports it unblocked and preserves the entered draft', async t => {
  const { state, vm, container } = await view(t, blockedStatus)
  Object.assign(vm.form, { username: 'Existing', password: 'Keep this draft' })
  await vm.refreshLoginStatus(); await settle()
  assert.equal(state.bootstrapCalls, 1)
  assert.equal(vm.loginDisabled, true)
  state.bootstrap = { ...config, loginBlocked: false, loginBlockedUntil: null, loginBlockedMessage: null }
  await vm.refreshLoginStatus(); await settle()
  assert.equal(state.bootstrapCalls, 2)
  assert.equal(vm.loginDisabled, false)
  assert.equal(container.querySelector('#refresh-login-status'), null)
  assert.equal(vm.form.password, 'Keep this draft')
})

test('a blocked password response refreshes bootstrap, retains input and prevents another attempt', async t => {
  const { state, vm, container } = await view(t)
  Object.assign(vm.form, { username: 'Existing', password: 'Keep this draft' })
  state.signInError = new auth.AuthError('failed', blockedStatus.loginBlockedMessage, 403, true, blockedStatus.loginBlockedUntil)
  state.bootstrap = { ...config, ...blockedStatus }
  await vm.submitLogin(); await settle()
  assert.equal(state.bootstrapCalls, 1)
  assert.equal(vm.loginDisabled, true)
  assert.equal(vm.form.password, 'Keep this draft')
  assert.match(textContent(container), /登录入口已封禁/)
  assert.doesNotMatch(textContent(container), /2000-01-02|UTC\+08:00|明天|次日|午夜|恢复时间/)
  await vm.submitLogin()
  assert.equal(state.signedIn.length, 1)
  assert.equal(state.redirects.length, 0)
})

test('a denied login-code request refreshes the lock status without starting a resend countdown', async t => {
  const { state, vm, container } = await view(t, { messageEnabled: true })
  vm.form.username = 'Existing'; vm.form.password = 'Keep this draft'
  state.sendError = new auth.AuthError('failed', blockedStatus.loginBlockedMessage, 403)
  state.bootstrap = { ...config, ...blockedStatus, messageEnabled: true }
  await vm.sendCode(); await settle()
  assert.equal(state.bootstrapCalls, 1)
  assert.equal(vm.loginDisabled, true)
  assert.equal(vm.countdown, 0)
  assert.equal(vm.form.password, 'Keep this draft')
  assert.match(textContent(container), /登录入口已封禁/)
  assert.doesNotMatch(textContent(container), /2000-01-02|UTC\+08:00|明天|次日|午夜|恢复时间/)
})

test('OAuth and bootstrap 503 errors keep inputs and block new logins until a successful status refresh', async t => {
  const { state, vm, container } = await view(t, { githubEnabled: true, googleEnabled: true, messageEnabled: true })
  Object.assign(vm.form, { username: 'Existing', password: 'Keep this draft', verificationCode: 'AB12CD34' })
  const failure = new auth.AuthError('failed', '登录安全状态暂时无法验证，请稍后重试', 503)
  state.oauthError = failure; state.bootstrapError = failure
  await vm.oauth('github'); await settle()
  assert.equal(state.oauthCalls.length, 1)
  assert.equal(state.bootstrapCalls, 1)
  assert.equal(vm.loginStateUnavailable, true)
  assert.equal(vm.loginBlocked, false)
  assert.equal(vm.form.password, 'Keep this draft')
  assert.match(textContent(container), /登录安全状态暂时无法验证，请稍后重试/)
  for (const id of ['loginButton', 'sendCodeBtn', 'githubLoginBtn', 'googleLoginBtn']) assert.equal(container.querySelector('#' + id).props.disabled, true, id)
  await vm.submitLogin(); await vm.sendCode(); await vm.oauth('google')
  assert.equal(state.signedIn.length + state.sentCodes.length, 0)
  assert.equal(state.oauthCalls.length, 1)
  state.bootstrapError = undefined
  await vm.refreshLoginStatus(); await settle()
  assert.equal(vm.loginStateUnavailable, false)
  assert.equal(vm.loginDisabled, false)
  assert.equal(vm.form.verificationCode, 'AB12CD34')
})
