import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
import test from 'node:test'
import ts from 'typescript'
import { createRenderer, h, nextTick, reactive, ref } from 'vue'

const require = createRequire(import.meta.url)
const vueUrl = pathToFileURL(require.resolve('vue/dist/vue.runtime.esm-bundler.js')).href
const source = (await readFile(new URL('../src/composables/useSessionGuard.ts', import.meta.url), 'utf8'))
  .replace("from 'vue'", `from '${vueUrl}'`)
  .replace("import { useRoute } from 'vue-router'", 'const useRoute = () => globalThis.authGuardFixture.route')
  .replace("import { checkSession, sessionExpired } from '@/utils/session'", 'const checkSession = () => globalThis.authGuardFixture.checkSession(); const sessionExpired = globalThis.authGuardFixture.expired')
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } })
const renderer = createRenderer({
  createElement: type => ({ type, children: [], parent: null }), createText: text => ({ text }), createComment: text => ({ text }),
  setText: (node, text) => { node.text = text }, setElementText: (node, text) => { node.text = text }, patchProp() {},
  insert: (child, parent) => { parent.children.push(child); child.parent = parent },
  remove: child => { if (child.parent) child.parent.children = child.parent.children.filter(item => item !== child) },
  parentNode: node => node.parent, nextSibling: () => null,
})

test('public and pending routes skip interval/focus probes, private routes resume them, unmount cleans listeners', async t => {
  const originalWindow = globalThis.window, originalDocument = globalThis.document
  const route = reactive({ fullPath: '/', matched: [], meta: {} })
  let checks = 0, interval, cleared = false
  globalThis.window = new EventTarget()
  globalThis.document = new EventTarget()
  globalThis.authGuardFixture = { route, expired: ref(false), checkSession: () => { checks++ } }
  t.mock.method(globalThis, 'setInterval', (callback, delay) => { assert.equal(delay, 30000); interval = callback; return 'guard-interval' })
  t.mock.method(globalThis, 'clearInterval', handle => { assert.equal(handle, 'guard-interval'); cleared = true })
  const { useSessionGuard } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`)
  const app = renderer.createApp({ setup() { useSessionGuard(); return () => h('div') } })
  app.mount({ children: [] })
  const probe = () => {
    interval()
    window.dispatchEvent(new Event('focus'))
    window.dispatchEvent(new Event('online'))
    document.dispatchEvent(new Event('visibilitychange'))
  }
  try {
    probe()
    assert.equal(checks, 0, 'the unresolved initial navigation cannot trigger userInfo')
    for (const path of ['/login', '/m/login', '/forbidden']) {
      Object.assign(route, { fullPath: path, matched: [{}], meta: { public: true } })
      await nextTick()
      probe()
      assert.equal(checks, 0, path)
    }
    Object.assign(route, { fullPath: '/tenants/list', matched: [{}], meta: {} })
    await nextTick()
    assert.equal(checks, 1, 'private navigation resumes checking')
    probe()
    assert.equal(checks, 5)
    app.unmount()
    assert.equal(cleared, true)
    window.dispatchEvent(new Event('focus'))
    document.dispatchEvent(new Event('visibilitychange'))
    assert.equal(checks, 5, 'unmounted listeners do not run')
  } finally {
    globalThis.window = originalWindow
    globalThis.document = originalDocument
    delete globalThis.authGuardFixture
  }
})
