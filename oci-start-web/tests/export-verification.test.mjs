import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, parse } from 'vue/compiler-sfc'
import { createRenderer, nextTick } from 'vue'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`
const verificationUrl = moduleUrl(await readFile(new URL('../src/api/exportVerification.ts', import.meta.url), 'utf8'))
const verification = await import(verificationUrl)
const promptUrl = moduleUrl((await readFile(new URL('../src/composables/useExportVerification.ts', import.meta.url), 'utf8'))
  .replace("import { ElMessageBox } from 'element-plus'", 'const ElMessageBox = { prompt: (...args) => globalThis.exportFixture.prompt(...args), close: () => globalThis.exportFixture.closePrompt() }')
  .replace("import { i18n } from '@/i18n'", 'const i18n = { global: { t: key => key } }')
  .replace("import { tenantPost } from '@/api/tenant'", 'const tenantPost = (...args) => globalThis.exportFixture.post(...args)')
  .replace("from '@/api/exportVerification'", `from '${verificationUrl}'`))
const { requestExportVerification } = await import(promptUrl)
async function component(path) {
  const { descriptor } = parse(await readFile(new URL(path, import.meta.url), 'utf8'), { filename: path })
  const code = compileScript(descriptor, { id: path }).content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_original, bindings, _quote, source) => {
    if (source === 'vue') return `import ${bindings} from '${import.meta.resolve('vue')}'`
    if (source === 'vue-i18n') return 'const useI18n = () => ({ t: key => key })'
    if (source === '@/api/tenant') return `const tenantGet = (...args) => globalThis.exportFixture.get(...args); const tenantPost = (...args) => globalThis.exportFixture.post(...args); const tenantError = () => 'fallback-error'`
    if (source === '@/api/exportVerification') return `import ${bindings} from '${verificationUrl}'`
    if (source === '@/composables/useExportVerification') return `import ${bindings} from '${promptUrl}'`
    if (source === 'element-plus') return 'const ElMessage = { success() {} }; const ElMessageBox = { confirm: async () => {} }'
    if (source === '@/utils/tenantPermissions') return 'const hasTenantPermission = () => true'
    if (source === '@/utils/session') return 'const checkSession = async () => {}'
    if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
    throw new Error(`Unstubbed dependency: ${source}`)
  })
  return (await import(moduleUrl(code))).default
}
const InstanceExport = await component('../src/views/instances/components/InstanceExportDialog.vue')
const TenantOperation = await component('../src/views/tenants/components/TenantOperationDialogs.vue')
const node = () => ({ children: [] })
const renderer = createRenderer({ createElement: node, createText: node, createComment: node, setText() {}, setElementText() {}, patchProp() {},
  insert(element, parent) { parent.children.push(element) }, remove() {}, parentNode() { return null }, nextSibling() { return null } })
function fixture(t) {
  const state = {
    posts: [], gets: [], prompts: [], files: [], clicks: 0, closed: 0, result: 'ab12cd34', response: [],
    async post(...args) { this.posts.push(args); if (this.sendError) throw this.sendError },
    async get(...args) { this.gets.push(args); if (this.exportError) throw this.exportError; return this.response },
    async prompt(...args) { this.prompts.push(args); if (this.cancel) throw this.cancel; return { value: this.result } },
    closePrompt() { this.closed++ },
  }
  const previous = { fixture: globalThis.exportFixture, document: globalThis.document }
  globalThis.exportFixture = state
  globalThis.document = { body: { append() {}, appendChild() {} }, createElement() { return { click() { state.clicks++ }, remove() {} } } }
  t.mock.method(globalThis, 'fetch', () => { throw new Error('Network is forbidden') })
  t.mock.method(URL, 'createObjectURL', file => { state.files.push(file); return 'blob:offline-export' })
  t.mock.method(URL, 'revokeObjectURL', () => {})
  t.mock.method(globalThis, 'setTimeout', () => 1)
  t.after(() => { state.unmount?.(); globalThis.exportFixture = previous.fixture; globalThis.document = previous.document })
  return state
}
function mount(state, view, props = {}) {
  const app = renderer.createApp({ ...view, render() { return null } }, props)
  const vm = app.mount(node()).$.setupState
  state.unmount = () => app.unmount()
  return vm
}

test('shared verification sends once, accepts eight characters, normalizes the returned code and never pre-verifies it', async t => {
  const state = fixture(t)
  const code = await requestExportVerification()
  assert.equal(code, 'AB12CD34')
  assert.deepEqual(state.posts.map(call => call[0]), ['/tenants/verify/sendExportCode'])
  assert.equal(state.gets.length, 0)
  const [message, , options] = state.prompts[0]
  assert.match(message, /codeLimit/)
  assert.equal(options.inputValidator('ab12cd34'), true)
  for (const invalid of ['123456', 'AB12CD345', 'AB12 CD3', 'ＡＢ１２ＣＤ３４']) assert.notEqual(options.inputValidator(invalid), true)
})

test('cancel and already-aborted verification do not export or report a request failure', async t => {
  const state = fixture(t)
  state.cancel = 'cancel'
  assert.equal(await requestExportVerification(), null)
  const controller = new AbortController(); controller.abort()
  assert.equal(await requestExportVerification(controller.signal), null)
  assert.equal(state.posts.length, 1)
  assert.equal(state.gets.length, 0)
})

test('shared verification preserves a daily-lock reason when code sending is denied', async t => {
  const state = fixture(t)
  state.sendError = { response: { data: '今日已暂停导出，请明天重试' } }
  await assert.rejects(requestExportVerification(), { message: '今日已暂停导出，请明天重试' })
  assert.equal(state.prompts.length, 0)
})

test('export error parsing preserves bounded plain text and JSON but rejects HTML, private-key and oversized bodies', async () => {
  assert.equal(await verification.exportErrorMessage({ response: { data: new Blob(['今日已暂停导出'], { type: 'text/plain;charset=UTF-8' }) } }), '今日已暂停导出')
  assert.equal(await verification.readExportResponseError(new Response(JSON.stringify({ message: 'Code expired' }), { status: 403, headers: { 'Content-Type': 'application/json' } })), 'Code expired')
  for (const value of ['<html>gateway failure</html>', '-----BEGIN PRIVATE KEY-----\nfixture', 'x'.repeat(9000)]) {
    assert.equal(await verification.exportErrorMessage({ response: { data: new Blob([value], { type: 'text/plain' }) } }), '')
  }
})

test('instance export sends the code with the only real file request and keeps the original text format', async t => {
  const state = fixture(t)
  state.response = new Blob(['# OCI 实例导出\nfixture data'], { type: 'text/plain;charset=UTF-8' })
  const vm = mount(state, InstanceExport)
  await vm.download()
  assert.deepEqual(state.posts.map(call => call[0]), ['/tenants/verify/sendExportCode'])
  assert.equal(state.gets.length, 1)
  assert.equal(state.gets[0][0], '/oci/export')
  assert.equal(state.gets[0][1], undefined)
  assert.equal(state.gets[0][2].headers['X-Verify-Code'], 'AB12CD34')
  assert.equal(state.gets[0][2].responseType, 'blob')
  assert.equal(state.files[0], state.response)
  assert.equal(vm.downloaded, true)
  assert.equal(state.clicks, 1)
  await vm.download()
  assert.equal(state.gets.length, 1)
})

test('instance export cancellation and a 403 blob do not download and show the specific rejection', async t => {
  const state = fixture(t)
  const vm = mount(state, InstanceExport)
  state.cancel = 'close'
  await vm.download()
  assert.equal(vm.errorText, '')
  assert.equal(state.gets.length, 0)
  state.cancel = null
  state.exportError = { response: { status: 403, data: new Blob(['验证码错误，今日还可输错1次'], { type: 'text/plain' }) } }
  await vm.download()
  assert.equal(vm.errorText, '验证码错误，今日还可输错1次')
  assert.equal(vm.busy, false)
  assert.equal(vm.downloaded, false)
  assert.equal(state.clicks, 0)
})

test('single-tenant export keeps its local ID, normalizes eight-character input, and verifies only on the download request', async t => {
  const state = fixture(t)
  const vm = mount(state, TenantOperation, { action: 'export', tenant: { id: '9223372036854775807' } })
  await nextTick(); await vm.submit()
  assert.equal(vm.codeSent, true)
  vm.setExportCode('123456'); await vm.submit()
  assert.equal(state.gets.length, 0)
  vm.setExportCode(' ab12cd34 '); await vm.submit()
  assert.equal(state.gets.length, 1)
  assert.equal(state.gets[0][0], '/tenants/exportByTenant')
  assert.deepEqual(state.gets[0][1], { id: '9223372036854775807' })
  assert.equal(state.gets[0][2].headers['X-Verify-Code'], 'AB12CD34')
  assert.equal(state.posts.length, 1)
})

test('all-tenant export sends its code in the same request and keeps a daily lock reason visible', async t => {
  const state = fixture(t)
  const vm = mount(state, TenantOperation, { action: 'export', tenant: null })
  await nextTick(); await vm.submit()
  vm.setExportCode('ab12cd34')
  state.exportError = { response: { status: 403, data: '今日已暂停导出，请明天重试' } }
  await vm.submit()
  assert.equal(state.gets.length, 1)
  assert.equal(state.gets[0][0], '/tenants/export')
  assert.equal(state.gets[0][2].headers['X-Verify-Code'], 'AB12CD34')
  assert.equal(vm.error, '今日已暂停导出，请明天重试')
  assert.equal(state.clicks, 0)
})
