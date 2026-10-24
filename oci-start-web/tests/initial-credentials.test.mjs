import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'

const source = await readFile(new URL('../src/utils/initialCredentials.ts', import.meta.url), 'utf8')
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } })
const credentials = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`)
function globalValue(t, key, value) {
  const previous = Object.getOwnPropertyDescriptor(globalThis, key)
  Object.defineProperty(globalThis, key, { configurable: true, writable: true, value })
  t.after(() => previous ? Object.defineProperty(globalThis, key, previous) : delete globalThis[key])
}

test('generated suggestions use secure random bytes and always include all password character classes', t => {
  let byte = 0, calls = 0
  globalValue(t, 'crypto', { getRandomValues(value) { calls++; value[0] = byte++ % 256; return value } })
  t.mock.method(Math, 'random', () => { throw new Error('Weak randomness is forbidden') })
  const suggestions = Array.from({ length: 20 }, () => credentials.generateInitialCredentials())
  for (const { username, password } of suggestions) {
    assert.match(username, /^u_[a-z0-9]{10}$/)
    assert.equal(credentials.isReservedRegistrationUsername(username), false)
    assert.equal(password.length, 24)
    for (const pattern of [/[a-z]/, /[A-Z]/, /[0-9]/, /[!@#$%^&*()_+=-]/]) assert.match(password, pattern)
  }
  assert.ok(calls > suggestions.length * 34)
  assert.ok(new Set(suggestions.map(value => value.password)).size > 1)
})

test('a browser without a secure random source never silently generates a weak password', t => {
  globalValue(t, 'crypto', undefined)
  assert.throws(() => credentials.generateInitialCredentials(), /Secure random source unavailable/)
})

test('new-account reserved names match the server NFKC, case, whitespace and numeric-suffix policy', () => {
  for (const value of ['root', ' ADMIN ', 'Administrator', 'superadmin', 'superuser', 'system', 'guest', 'test', 'user', 'root123', 'admin0', ' ＲＯＯＴ１２３ ', 'ＡＤＭＩＮ']) {
    assert.equal(credentials.isReservedRegistrationUsername(value), true, value)
  }
  for (const value of ['u_abc1234567', 'Alice', 'admin-alice', 'rooted', 'guest1', 'user123', '']) {
    assert.equal(credentials.isReservedRegistrationUsername(value), false, value)
  }
})

test('clipboard API success copies only the explicitly supplied value without a fallback field', async t => {
  const values = []
  globalValue(t, 'navigator', { clipboard: { async writeText(value) { values.push(value) } } })
  globalValue(t, 'document', { get body() { throw new Error('No fallback should run') } })
  assert.equal(await credentials.copyCredentialText('fixture-only'), true)
  assert.deepEqual(values, ['fixture-only'])
  assert.equal(await credentials.copyCredentialText(''), false)
  assert.equal(values.length, 1)
})

function fallbackDocument(t, result) {
  const state = { selected: false, removed: false, restored: false, copied: [] }
  const field = { value: '', style: {}, setAttribute() {}, select() { state.selected = true }, setSelectionRange() {}, remove() { state.removed = true } }
  globalValue(t, 'document', {
    activeElement: { focus() { state.restored = true } },
    body: { appendChild(element) { assert.equal(element, field) } },
    createElement(type) { assert.equal(type, 'textarea'); return field },
    execCommand(command) { assert.equal(command, 'copy'); assert.equal(state.selected, true); state.copied.push(field.value); return result },
  })
  return { state, field }
}

test('plain HTTP clipboard fallback copies on demand and removes the temporary secret field', async t => {
  globalValue(t, 'navigator', {})
  const { state, field } = fallbackDocument(t, true)
  assert.equal(await credentials.copyCredentialText('fixture-only'), true)
  assert.deepEqual(state.copied, ['fixture-only'])
  assert.equal(state.removed, true)
  assert.equal(state.restored, true)
  assert.equal(field.value, '')
})

test('denied clipboard permission tries the fallback and reports failure without retaining the secret', async t => {
  globalValue(t, 'navigator', { clipboard: { async writeText() { throw new Error('Denied') } } })
  const { state, field } = fallbackDocument(t, false)
  assert.equal(await credentials.copyCredentialText('fixture-only'), false)
  assert.equal(state.removed, true)
  assert.equal(field.value, '')
})
