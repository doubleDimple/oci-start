import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { createRenderer, h, nextTick, ref } from 'vue'
import { compileScript, parse } from 'vue/compiler-sfc'
import { createMemoryHistory, createRouter } from 'vue-router'

// Run the actual TypeScript helpers with the project's installed compiler;
// this isolated suite needs neither a browser nor an application/API server.
const source = await readFile(new URL('../src/composables/useMobileRecords.ts', import.meta.url), 'utf8')
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } })
const helperModuleUrl = `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
const helpers = await import(helperModuleUrl)
const { mobileRecordOpenQuery: open, mobileRecordBackQuery: back, mobileRecordCloseQuery: close,
  mobileRecordSelection: selected, mobileRecordBackMethod: backMethod, isMobileRecordNavigation } = helpers
const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/records', component: {} }] })
const resolve = query => router.resolve({ path: '/records', query, hash: '#content' })
const normalize = query => resolve(query).query
const base = normalize({ tenantId: '71', mode: ['one', 'two'] })

test('switching page siblings leaves exactly one selected list and preserves filters', () => {
  const models = normalize(open(base, 'models', 'model:alpha'))
  const configs = normalize(open(models, 'configs', '123'))
  assert.equal(selected(configs, 'models'), '')
  assert.equal(selected(configs, 'configs'), '123')
  assert.equal(configs.mobileRecordParents, undefined)
  assert.equal(configs.tenantId, '71')
  assert.deepEqual(configs.mode, ['one', 'two'])
})

test('a dialog preserves its page record and a refreshed URL resolves both selections', () => {
  const parent = normalize(open(base, 'instances', 'ocid1.instance.alpha'))
  const child = normalize(open(parent, 'volumes', 'ocid1.volume.alpha', ['volumes']))
  const refreshed = router.resolve(resolve(child).fullPath).query
  assert.equal(selected(refreshed, 'instances'), 'ocid1.instance.alpha')
  assert.equal(selected(refreshed, 'volumes'), 'ocid1.volume.alpha')
  assert.deepEqual(normalize(back(refreshed, 'volumes')), parent)
  assert.deepEqual(normalize(close(refreshed, 'volumes')), parent)
})

test('two lists in the same dialog are siblings while keeping the underlying page', () => {
  const parent = normalize(open(base, 'accounts', '71'))
  const models = normalize(open(parent, 'available', 'model-alpha', ['available', 'configured']))
  const configs = normalize(open(models, 'configured', 'config-alpha', ['available', 'configured']))
  assert.equal(selected(configs, 'accounts'), '71')
  assert.equal(selected(configs, 'available'), '')
  assert.equal(selected(configs, 'configured'), 'config-alpha')
  assert.deepEqual(helpers.mobileRecordParents(configs), ['accounts:71'])
  assert.deepEqual(normalize(back(configs, 'configured')), parent)
})

test('nested dialogs unwind one level and an explicit parent back removes descendants', () => {
  const parent = normalize(open(base, 'instances', 'alpha'))
  const child = normalize(open(parent, 'vnics', 'beta', ['vnics']))
  const grandchild = normalize(open(child, 'addresses', '2001:db8::1', ['addresses']))
  assert.deepEqual(helpers.mobileRecordParents(grandchild), ['instances:alpha', 'vnics:beta'])
  assert.deepEqual(normalize(back(grandchild, 'addresses')), child)
  assert.deepEqual(normalize(back(grandchild, 'vnics')), parent)
  assert.deepEqual(normalize(back(grandchild, 'instances')), base)
})

test('changing records in one dialog does not repeat its parent or preserve the prior child', () => {
  const parent = normalize(open(base, 'instances', 'alpha'))
  const first = normalize(open(parent, 'volumes', 'first', ['volumes']))
  const second = normalize(open(first, 'volumes', 'second', ['volumes']))
  assert.deepEqual(helpers.mobileRecordParents(second), ['instances:alpha'])
  assert.equal(selected(second, 'volumes'), 'second')
  assert.deepEqual(normalize(back(second, 'volumes')), parent)
})

test('closing a sibling or ancestor cannot clear the active child', () => {
  const parent = normalize(open(base, 'instances', 'alpha'))
  const child = normalize(open(parent, 'volumes', 'beta', ['volumes']))
  assert.equal(close(child, 'instances'), null)
  assert.equal(close(child, 'other-volumes'), null)
  assert.equal(back(child, 'missing'), null)
  assert.deepEqual(normalize(close(normalize(open(base, 'volumes', 'beta', ['volumes'])), 'volumes')), base)
})

test('history back is used only for the intended distinct target', () => {
  const summary = resolve(base).fullPath
  const parent = resolve(open(base, 'instances', 'alpha')).fullPath
  const child = resolve(open(normalize(open(base, 'instances', 'alpha')), 'volumes', 'beta', ['volumes'])).fullPath
  assert.equal(backMethod(child, parent, parent), 'back')
  // Closing the child replaced C with P, leaving S, P, P in browser history.
  // The next parent Back must visibly reach S in one action.
  assert.equal(backMethod(parent, summary, parent), 'replace')
  assert.equal(backMethod(parent, summary, '/records?mobileRecord=other:42'), 'replace')
  assert.equal(backMethod(parent, summary, null), 'replace')
  assert.equal(backMethod(parent, parent, summary), 'none')
})

test('record navigation never bypasses a changed account, filter, path or hash', () => {
  const initial = resolve(base)
  const child = resolve(open(normalize(open(base, 'instances', 'alpha')), 'volumes', 'beta', ['volumes']))
  assert.equal(isMobileRecordNavigation(child, initial), true)
  assert.equal(isMobileRecordNavigation(resolve({ ...child.query, tenantId: '72' }), initial), false)
  assert.equal(isMobileRecordNavigation(resolve({ ...child.query, mode: ['two', 'one'] }), initial), false)
  assert.equal(isMobileRecordNavigation({ ...child, path: '/other' }, initial), false)
  assert.equal(isMobileRecordNavigation({ ...child, hash: '#other' }, initial), false)
})

test('record keys retain colons, spaces and serialized identity rather than row indices', () => {
  const key = JSON.stringify(['71', 'ocid1.model.alpha:revision 2'])
  const current = normalize(open(base, 'models', key))
  assert.equal(selected(router.resolve(resolve(current).fullPath).query, 'models'), key)
  assert.equal(selected({ mobileRecord: ['models:first', 'models:second'] }, 'models'), '')
  assert.deepEqual(helpers.mobileRecordParents({ mobileRecordParents: [null, '', 'models:first'] }), ['models:first'])
})

test('a retained dialog list clears its child selection when active becomes false without unmounting', async () => {
  const filename = new URL('../src/components/MobileRecordList.vue', import.meta.url)
  const descriptor = parse(await readFile(filename, 'utf8'), { filename: filename.pathname }).descriptor
  const compiled = compileScript(descriptor, { id: 'mobile-record-lifecycle-test', inlineTemplate: true }).content
  const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`
  const imports = {
    vue: import.meta.resolve('vue'),
    'vue-router': import.meta.resolve('vue-router'),
    'vue-i18n': moduleUrl('export const useI18n = () => ({ t: value => value })'),
    './PageBackButton.vue': moduleUrl('export default { render: () => null }'),
    '@/composables/useMobileRecords': helperModuleUrl,
  }
  const linked = compiled.replace(/from\s+(['"])([^'"]+)\1/g, (statement, quote, specifier) => imports[specifier] ? `from ${JSON.stringify(imports[specifier])}` : statement)
  const runtime = ts.transpileModule(linked, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText
  const { default: MobileRecordList } = await import(moduleUrl(runtime))
  class Node {
    constructor(type) { this.type = type; this.children = []; this.parent = null; this.props = {} }
    get parentElement() { return this.parent }
    closest() { for (let node = this; node; node = node.parent) if (node.type === 'dialog') return node; return null }
    querySelectorAll() { return [] }
    focus() {}
  }
  const renderer = createRenderer({
    createElement: type => new Node(type), createText: text => Object.assign(new Node('text'), { text }), createComment: text => Object.assign(new Node('comment'), { text }),
    setText: (node, text) => { node.text = text }, setElementText: (node, text) => { node.text = text },
    parentNode: node => node.parent, nextSibling: node => node.parent?.children[node.parent.children.indexOf(node) + 1] || null,
    patchProp: (node, key, previous, value) => { node.props[key] = value },
    insert: (node, parent, anchor) => { node.parent = parent; const index = anchor ? parent.children.indexOf(anchor) : -1; if (index < 0) parent.children.push(node); else parent.children.splice(index, 0, node) },
    remove: node => { if (node.parent) node.parent.children.splice(node.parent.children.indexOf(node), 1); node.parent = null },
  })
  const localRouter = createRouter({ history: createMemoryHistory(), routes: [{ path: '/records', component: {} }] })
  const parent = normalize(open(base, 'buckets', 'alpha'))
  await localRouter.push(resolve(open(parent, 'upload-records', 'beta', ['upload-records'])).fullPath)
  const active = ref(true)
  const app = renderer.createApp({ setup: () => () => h(MobileRecordList, { drilldown: true, listId: 'upload-records', recordKeys: ['beta'], active: active.value }) })
  app.use(localRouter)
  const previousWindow = globalThis.window
  globalThis.window = { matchMedia: () => ({ matches: true }) }
  try {
    const container = new Node('dialog')
    app.mount(container)
    const retainedRoot = container.children[0]
    active.value = false
    await nextTick()
    await new Promise(resolve => setImmediate(resolve))
    await nextTick()
    assert.equal(container.children[0], retainedRoot)
    assert.deepEqual(localRouter.currentRoute.value.query, parent)
    assert.equal(selected(localRouter.currentRoute.value.query, 'upload-records'), '')
    assert.equal(selected(localRouter.currentRoute.value.query, 'buckets'), 'alpha')
  } finally {
    app.unmount()
    if (previousWindow === undefined) delete globalThis.window
    else globalThis.window = previousWindow
  }
})
