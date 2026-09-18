import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { generateKeyPairSync, privateDecrypt, constants } from 'node:crypto'
import test from 'node:test'
import ts from 'typescript'

const source = await readFile(new URL('../src/api/auth.ts', import.meta.url), 'utf8')
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } })
const auth = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`)
const config = { siteLogoName: 'OCI', publicKey: 'key', allowRegister: false, githubEnabled: false, googleEnabled: false, turnstileEnabled: false, turnstileSiteKey: '', messageEnabled: false, mfaEnabled: false, locale: 'zh_CN' }
const values = { username: 'test', password: 'test-password', remember: true, method: 'message', verificationCode: '654321', mfaCode: '123456', turnstileToken: 'challenge-token' }
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

function response(t, result) { t.mock.method(globalThis, 'fetch', async () => result) }

test('all verification configurations submit only the selected enabled factor', () => {
  for (const messageEnabled of [false, true]) for (const mfaEnabled of [false, true]) for (const method of ['message', 'mfa']) {
    const body = auth.loginPayload({ ...values, method }, { ...config, messageEnabled, mfaEnabled }, () => 'encrypted')
    assert.equal(body.get('password'), 'encrypted')
    assert.equal(body.get('remember-me'), 'true')
    assert.equal(body.has('verificationCode'), messageEnabled && method === 'message')
    assert.equal(body.has('mfaCode'), mfaEnabled && method === 'mfa')
  }
})

test('encryption failure never returns a plaintext payload; challenge token is included only when enabled', () => {
  assert.throws(() => auth.loginPayload(values, config, () => false), { key: 'encryption' })
  assert.equal(auth.loginPayload(values, config, () => 'encrypted').has('cf-turnstile-response'), false)
  assert.equal(auth.loginPayload(values, { ...config, turnstileEnabled: true }, () => 'encrypted').get('cf-turnstile-response'), 'challenge-token')
})

test('bundled RSA implementation encrypts a value that the server-compatible private key decrypts', async () => {
  const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 })
  const originalWindow = globalThis.window
  globalThis.window = { crypto: globalThis.crypto, addEventListener() {}, removeEventListener() {} }
  try {
    const { default: JSEncrypt } = await import('../src/views/auth/vendor/jsencrypt.js')
    const rsa = new JSEncrypt()
    rsa.setPublicKey(publicKey.export({ type: 'spki', format: 'pem' }).toString())
    const ciphertext = rsa.encrypt('验证-password-123')
    assert.ok(ciphertext)
    // Inspect PKCS#1 v1.5 padding manually because current Node disables its privateDecrypt shortcut.
    const block = privateDecrypt({ key: privateKey, padding: constants.RSA_NO_PADDING }, Buffer.from(ciphertext, 'base64'))
    assert.equal(block[0], 0)
    assert.equal(block[1], 2)
    assert.equal(block.subarray(block.indexOf(0, 2) + 1).toString('utf8'), '验证-password-123')
  } finally { globalThis.window = originalWindow }
})

test('a 401 credential failure surfaces the JSON error without navigating', async t => {
  response(t, json({ success: false, message: 'Credentials rejected' }, 401))
  await assert.rejects(auth.signIn(new URLSearchParams()), { key: 'failed', detail: 'Credentials rejected' })
})

test('a followed HTML login redirect cannot be mistaken for successful authentication', async t => {
  response(t, new Response('<html><form>Login</form></html>', { status: 200 }))
  await assert.rejects(auth.signIn(new URLSearchParams()), { key: 'invalidResponse' })
})

test('successful login respects the server mobile destination', async t => {
  response(t, json({ success: true, redirectUrl: '/m/tenants' }))
  assert.equal(await auth.signIn(new URLSearchParams()), '/m/tenants')
})

test('redirect targets reject script, protocol-relative, backslash and login loop paths', () => {
  for (const value of ['javascript:alert(1)', '//external.example', '/\\external.example', '/login?error=true', '/m/login', '\r\n/index', null]) assert.equal(auth.safeLoginRedirect(value), '/index')
  assert.equal(auth.safeLoginRedirect('/main?path=%2Ftenants%2Flist'), '/main?path=%2Ftenants%2Flist')
})

test('registration preserves successful empty-body responses', async t => {
  response(t, new Response(null, { status: 200 }))
  await auth.registerAccount('account', 'password')
})

test('registration preserves plain-text backend error messages', async t => {
  response(t, new Response('Registration is disabled', { status: 400 }))
  await assert.rejects(auth.registerAccount('account', 'password'), { key: 'failed', detail: 'Registration is disabled' })
})

test('recovery rejects HTTP 200 business errors before countdown or step advancement', async t => {
  response(t, json({ success: false, code: 500, message: 'Code expired' }))
  await assert.rejects(auth.sendResetCode('account'), { key: 'failed', detail: 'Code expired' })
})

test('recovery requires an actual reset token before the reset operation', async t => {
  response(t, json({ success: true, data: {} }))
  await assert.rejects(auth.verifyResetCode('account', '123456'), { key: 'invalidResponse' })
})

test('OAuth preserves remember-me and accepts the provider HTTPS redirect', async t => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => new Response('https://github.com/login/oauth/authorize?state=example'))
  assert.equal(await auth.oauthLoginUrl('github', true), 'https://github.com/login/oauth/authorize?state=example')
  assert.equal(fetch.mock.calls[0].arguments[0], '/api/github/login/url?remember-me=on')
})

test('bootstrap refuses missing security flags or public keys', async t => {
  response(t, json({ ...config, publicKey: '' }))
  await assert.rejects(auth.fetchAuthBootstrap('zh'), { key: 'invalidResponse' })
})

test('hung authentication requests time out and remove their timeout handle', async t => {
  let fireTimeout, duration, cleared = false, requestSignal
  t.mock.method(globalThis, 'setTimeout', (callback, delay) => { fireTimeout = callback; duration = delay; return 'auth-timeout' })
  t.mock.method(globalThis, 'clearTimeout', handle => { assert.equal(handle, 'auth-timeout'); cleared = true })
  t.mock.method(globalThis, 'fetch', (_path, init) => {
    requestSignal = init.signal
    return new Promise((_resolve, reject) => init.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true }))
  })
  const request = auth.fetchAuthBootstrap('en')
  assert.equal(duration, 20000)
  fireTimeout()
  await assert.rejects(request, { key: 'network' })
  assert.equal(requestSignal.aborted, true)
  assert.equal(cleared, true)
})

test('unmount cancellation reaches fetch and retains AbortError instead of reporting a network failure', async t => {
  const controller = new AbortController()
  let requestSignal
  t.mock.method(globalThis, 'fetch', (_path, init) => {
    requestSignal = init.signal
    return new Promise((_resolve, reject) => init.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true }))
  })
  const request = auth.fetchAuthBootstrap('zh', controller.signal)
  controller.abort()
  await assert.rejects(request, { name: 'AbortError' })
  assert.equal(requestSignal.aborted, true)
})

test('recovery rejects unknown successful JSON without advancing the wizard', async t => {
  response(t, json({}))
  await assert.rejects(auth.resetPassword('account', 'token'), { key: 'invalidResponse' })
})
