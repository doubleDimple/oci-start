import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`
const verificationUrl = moduleUrl(await readFile(new URL('../src/api/exportVerification.ts', import.meta.url), 'utf8'))
const verification = await import(verificationUrl)
async function loadApi(file) {
  const source = (await readFile(new URL(`../src/api/${file}`, import.meta.url), 'utf8'))
    .replace("import { tenantCsrfToken } from './tenant'", "const tenantCsrfToken = () => 'fixture-csrf'")
    .replace("import { checkSession, handleSessionResponse } from '@/utils/session'", 'const checkSession = async () => {}; const handleSessionResponse = () => {}')
    .replace("from './exportVerification'", `from '${verificationUrl}'`)
  return import(moduleUrl(source))
}
const migration = await loadApi('migration.ts')
const mfa = await loadApi('mfaBackup.ts')
const origin = 'http://offline.test'
function response(path, body, status = 200, headers = {}) {
  const result = new Response(body, { status, headers })
  Object.defineProperty(result, 'url', { value: origin + path })
  return result
}
function fixture(t, handler) {
  const previousWindow = globalThis.window, previousDocument = globalThis.document
  globalThis.window = { location: { origin }, setTimeout, clearTimeout }
  globalThis.document = { querySelector: () => ({ content: 'X-CSRF-TOKEN' }) }
  const calls = []
  t.mock.method(globalThis, 'fetch', async (path, options) => {
    calls.push({ path, options })
    return handler(path, options)
  })
  t.after(() => { globalThis.window = previousWindow; globalThis.document = previousDocument })
  return calls
}
const blocked = '今天导出验证码已累计输错 2 次，当前账号当天已暂停导出，请明天再试'

test('encrypted database export sends its code with the download and preserves the encrypted artifact', async t => {
  const key = Buffer.alloc(32, 7).toString('base64')
  const envelope = `-----BEGIN OCI-START MIGRATION-----\nIV:${Buffer.alloc(16).toString('base64')}\nDATA:${Buffer.alloc(16, 9).toString('base64')}\n-----END OCI-START MIGRATION-----`
  const calls = fixture(t, path => response(path, envelope, 200, {
    'Content-Type': 'application/octet-stream', 'X-MASTER-KEY': key,
  }))
  const artifact = await migration.exportEncryptedBackup(' ab12cd34 ')
  assert.equal(calls.length, 1, 'No separate verification or retry request')
  assert.equal(calls[0].path, '/migration/exportEncrypted')
  assert.equal(calls[0].options.method, 'GET')
  assert.equal(calls[0].options.headers.get('X-Verify-Code'), 'AB12CD34')
  assert.equal(calls[0].options.headers.get('X-CSRF-TOKEN'), 'fixture-csrf')
  assert.equal(calls[0].options.cache, 'no-store')
  assert.equal(calls[0].options.body, undefined)
  assert.equal(artifact.masterKey, key)
  assert.equal(await artifact.blob.text(), envelope)
})

test('MFA export sends its code with the selected IDs and preserves returned secrets and order', async t => {
  const ids = ['101', '9007199254740993']
  const entries = ids.map(id => ({ id, keyName: `fixture-${id}`, issuer: 'offline', secretKey: 'AAAA2222TESTONLY' }))
  const calls = fixture(t, path => response(path, JSON.stringify({ success: true, data: [...entries].reverse() }), 200, { 'Content-Type': 'application/json' }))
  assert.deepEqual(await mfa.exportMfaEntries(ids, ' ab12cd34 '), entries)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].path, '/api/mfa/export')
  assert.equal(calls[0].options.method, 'POST')
  assert.equal(calls[0].options.headers.get('X-Verify-Code'), 'AB12CD34')
  assert.equal(calls[0].options.headers.get('X-CSRF-TOKEN'), 'fixture-csrf')
  assert.deepEqual(JSON.parse(calls[0].options.body), { ids })
})

test('invalid or old six-digit export codes never submit an export', async t => {
  const calls = fixture(t, () => { throw new Error('Unexpected network request') })
  for (const code of ['', '123456', 'AB12-CD3', 'ＡＢ１２ＣＤ３４', 'AB12CD345']) {
    await assert.rejects(migration.exportEncryptedBackup(code))
    await assert.rejects(mfa.exportMfaEntries(['101'], code))
  }
  assert.equal(calls.length, 0)
})

test('both export APIs retain the daily-ban reason from plain text and JSON without retrying', async t => {
  for (const json of [false, true]) {
    const body = json ? JSON.stringify({ success: false, errorKey: 'forbidden', message: blocked }) : blocked
    const calls = fixture(t, path => response(path, body, 403, { 'Content-Type': json ? 'application/json' : 'text/plain;charset=UTF-8' }))
    await assert.rejects(migration.exportEncryptedBackup('AB12CD34'), cause => cause.key === 'forbidden' && cause.detail === blocked)
    await assert.rejects(mfa.exportMfaEntries(['101'], 'AB12CD34'), cause => cause.key === 'forbidden' && cause.detail === blocked && !cause.writeAttempted)
    assert.equal(calls.length, 2)
  }
})

test('file data, HTML errors and oversized responses are never shown as verification messages', async t => {
  const rejected = [
    { body: '<html>upstream debug page</html>', type: 'text/html' },
    { body: '-----BEGIN PRIVATE KEY-----\nnot-a-real-key', type: 'text/plain' },
    { body: '# OCI 实例导出\nnot-real-data', type: 'text/plain' },
    { body: 'x'.repeat(9000), type: 'text/plain' },
  ]
  for (const item of rejected) {
    fixture(t, path => response(path, item.body, 403, { 'Content-Type': item.type }))
    await assert.rejects(migration.exportEncryptedBackup('AB12CD34'), cause => cause.key === 'forbidden' && cause.detail === '')
    await assert.rejects(mfa.exportMfaEntries(['101'], 'AB12CD34'), cause => cause.key === 'forbidden' && cause.detail === '')
  }
})

test('verification error helpers do not stringify unexpected response objects', () => {
  assert.equal(verification.safeExportMessage({ privateKey: 'NOT FOR DISPLAY', credentials: ['secret'] }), '')
  assert.equal(verification.safeExportMessage({ message: blocked, privateKey: 'NOT FOR DISPLAY' }), blocked)
})

test('MFA TOTP retrieval still uses six digits and never asks for an export code', async t => {
  const calls = fixture(t, path => response(path, JSON.stringify({ success: true,
    serverTime: 1000, expiresAt: 30000, items: [{ id: '101', code: '123456', errorKey: null }],
  }), 200, { 'Content-Type': 'application/json' }))
  const result = await mfa.getMfaCodes(['101'])
  assert.equal(result.items[0].code, '123456')
  assert.equal(calls[0].options.headers.has('X-Verify-Code'), false)
})
