import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { createRenderer, h, nextTick, onMounted } from 'vue'
import { createPinia } from 'pinia'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'

// Exercise production authentication, store validation and session expiration together.
// Only HTTP, translations and the browser host are replaced; no application server is used.
const sources = Object.fromEntries(await Promise.all([
  ['session', '../src/utils/session.ts'], ['user', '../src/stores/user.ts'], ['guard', '../src/router/authGuard.ts'],
].map(async ([name, path]) => [name, await readFile(new URL(path, import.meta.url), 'utf8')])))
const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`
const link = (source, imports) => source.replace(/from\s+(['"])([^'"]+)\1/g, (statement, _quote, name) => {
  if (!imports[name]) throw new Error(`Unstubbed startup dependency: ${name}`)
  return `from ${JSON.stringify(imports[name])}`
})
let fixtureId = 0
const node = type => ({ type, text: '', children: [], parent: null })
const renderer = createRenderer({
  createElement: node, createText: text => ({ ...node('#text'), text }), createComment: text => ({ ...node('#comment'), text }),
  setText: (element, text) => { element.text = text },
  setElementText: (element, text) => { element.text = text; element.children = [] }, patchProp() {},
  insert(element, parent, anchor) {
    if (element.parent) element.parent.children = element.parent.children.filter(child => child !== element)
    const index = anchor ? parent.children.indexOf(anchor) : -1
    if (index < 0) parent.children.push(element); else parent.children.splice(index, 0, element)
    element.parent = parent
  },
  remove: element => { if (element.parent) element.parent.children = element.parent.children.filter(child => child !== element) },
  parentNode: element => element.parent,
  nextSibling: element => element.parent?.children[element.parent.children.indexOf(element) + 1] || null,
})
const textContent = element => element.type === '#comment' ? '' : `${element.text}${element.children.map(textContent).join('')}`
const validUser = () => ({ success: true, data: { username: 'verified-owner' } })
const httpError = status => Object.assign(new Error(`HTTP ${status}`), { response: { status } })
const deferred = () => {
  let resolve, reject
  const promise = new Promise((success, failure) => { resolve = success; reject = failure })
  return { promise, resolve, reject }
}
async function settle() {
  for (let index = 0; index < 5; index++) { await Promise.resolve(); await nextTick() }
}

async function fixture(t, path = '/tenants/list') {
  const id = ++fixtureId
  const state = { loads: 0, businessCalls: [], layouts: 0, setups: [], mounts: [], publicMounts: 0,
    redirects: [], errors: [], probes: 0, reply: async () => validUser() }
  const original = { window: globalThis.window, document: globalThis.document, fixture: globalThis.startupAuthFixture }
  globalThis.window = {
    location: { pathname: path, origin: 'https://console.invalid', replace: target => state.redirects.push(target) },
    matchMedia: () => ({ matches: path === '/m' || path.startsWith('/m/') }), setTimeout, clearTimeout,
  }
  globalThis.document = { hidden: false }
  t.mock.method(globalThis, 'fetch', () => { state.probes++; throw new Error('External requests are forbidden') })
  const sessionUrl = moduleUrl(link(sources.session, { vue: import.meta.resolve('vue') }) + `\n// fixture ${id}`)
  const session = await import(sessionUrl)
  state.fetchUserInfo = async options => {
    state.loads++
    try {
      const response = await state.reply(options)
      if (session.handleSessionResponse({ body: response })) throw httpError(401)
      return response
    } catch (error) {
      session.handleSessionResponse({ status: error.response?.status, body: error.response?.data })
      throw error
    }
  }
  globalThis.startupAuthFixture = state
  const apiUrl = moduleUrl(`export const fetchUserInfo = (...args) => globalThis.startupAuthFixture.fetchUserInfo(...args);
    export const logout = () => { throw new Error('Startup must not log the user out') }; // ${id}`)
  const userUrl = moduleUrl(link(sources.user, {
    pinia: import.meta.resolve('pinia'), '@/api/user': apiUrl, '@/utils/session': sessionUrl,
  }) + `\n// fixture ${id}`)
  const i18nUrl = moduleUrl("export const i18n = { global: { t: key => key === 'header.userFailed' ? 'Unable to verify the current user' : key } }")
  const guardUrl = moduleUrl(link(sources.guard, {
    'vue-router': import.meta.resolve('vue-router'), '@/stores/user': userUrl, '@/utils/session': sessionUrl, '@/i18n': i18nUrl,
  }) + `\n// fixture ${id}`)
  const { useUserStore } = await import(userUrl)
  const { createAuthenticationGuard } = await import(guardUrl)
  const privatePage = name => ({
    setup() {
      state.setups.push(name)
      state.businessCalls.push(name)
      onMounted(() => state.mounts.push(name))
      return () => h('section', `PRIVATE ${name}`)
    },
  })
  const publicPage = { setup() { onMounted(() => state.publicMounts++); return () => h('section', 'PUBLIC') } }
  const layout = { setup() { state.layouts++; return () => h('main', [h(RouterView)]) } }
  const router = createRouter({ history: createMemoryHistory(), routes: [
    { path: '/login', alias: '/m/login', meta: { public: true }, component: publicPage },
    { path: '/forbidden', meta: { public: true }, component: publicPage },
    { path: '/m', redirect: '/m/tenants' },
    { path: '/', component: layout, children: [
      { path: 'tenants/list', alias: '/m/tenants', component: privatePage('tenants') },
      { path: 'oci/list', alias: '/m/oci-instances', component: privatePage('instances') },
    ] },
  ] })
  const guard = createAuthenticationGuard()
  router.beforeEach(guard)
  router.onError(error => state.errors.push(error))
  const pinia = createPinia()
  const app = renderer.createApp({ setup: () => () => h(RouterView) })
  app.use(pinia)
  app.use(router)
  const container = node('root')
  app.mount(container)
  t.after(() => {
    app.unmount()
    for (const [key, value] of Object.entries({ window: original.window, document: original.document, startupAuthFixture: original.fixture })) {
      if (value === undefined) delete globalThis[key]; else globalThis[key] = value
    }
  })
  return { state, router, guard, session, container, user: useUserStore(pinia) }
}

function assertPrivateNotMounted(view) {
  assert.equal(view.state.layouts, 0, 'a private layout must wait for authentication')
  assert.deepEqual(view.state.setups, [])
  assert.deepEqual(view.state.mounts, [])
  assert.deepEqual(view.state.businessCalls, [], 'mount-triggered tenant/cloud requests must not start')
  assert.doesNotMatch(textContent(view.container), /PRIVATE/)
}

test('a valid startup session mounts protected content only after verification and is cached for later navigation', async t => {
  const view = await fixture(t)
  const response = deferred()
  view.state.reply = () => response.promise
  const navigation = view.router.push('/tenants/list')
  await settle()
  assert.equal(view.state.loads, 1)
  assert.equal(view.user.loading, true)
  assertPrivateNotMounted(view)

  response.resolve(validUser())
  await navigation
  await settle()
  assert.equal(view.user.username, 'verified-owner')
  assert.deepEqual(view.state.mounts, ['tenants'])
  assert.deepEqual(view.state.businessCalls, ['tenants'])
  await view.session.checkSession()
  assert.equal(view.state.probes, 0, 'verification already performed at startup suppresses an immediate session-monitor probe')
  await view.router.push('/oci/list')
  await settle()
  assert.deepEqual(view.state.mounts, ['tenants', 'instances'])
  assert.equal(view.state.loads, 1)
  assert.equal(view.state.errors.length, 0)
  assert.deepEqual(view.state.redirects, [])
})

test('concurrent protected navigations share one identity read and only the winning destination mounts', async t => {
  const view = await fixture(t)
  const response = deferred()
  view.state.reply = () => response.promise
  const first = view.router.push('/tenants/list')
  await settle()
  const second = view.router.push('/oci/list')
  await settle()
  assert.equal(view.state.loads, 1)
  assertPrivateNotMounted(view)
  response.resolve(validUser())
  await Promise.all([first, second])
  await settle()
  assert.equal(view.router.currentRoute.value.path, '/oci/list')
  assert.deepEqual(view.state.mounts, ['instances'])
  assert.deepEqual(view.state.businessCalls, ['instances'])
})

for (const path of ['/tenants/list', '/m/tenants', '/m']) {
  test(`an initial 401 at ${path} never mounts private content and redirects only once`, async t => {
    const view = await fixture(t, path)
    const response = deferred()
    view.state.reply = () => response.promise
    const navigation = view.router.push(path)
    await settle()
    assertPrivateNotMounted(view)
    response.reject(httpError(401))
    await navigation
    await settle()
    assertPrivateNotMounted(view)
    assert.equal(view.session.sessionExpired.value, true)
    assert.deepEqual(view.state.redirects, [path.startsWith('/m') ? '/m/login' : '/login'])
    await view.router.push('/oci/list')
    view.session.handleSessionResponse({ status: 401 })
    await settle()
    assert.equal(view.state.loads, 1)
    assert.equal(view.state.redirects.length, 1)
    assert.equal(view.state.errors.length, 0, 'an expired session follows the login path, not the server-error path')
    assertPrivateNotMounted(view)
  })
}

for (const path of ['/login', '/m/login', '/forbidden']) {
  test(`the public ${path} route does not query userInfo`, async t => {
    const view = await fixture(t, path)
    view.state.reply = () => { throw new Error('Public routes cannot query identity') }
    await view.router.push(path)
    await settle()
    assert.equal(view.state.loads, 0)
    assert.equal(view.state.publicMounts, 1)
    assertPrivateNotMounted(view)
    assert.deepEqual(view.state.redirects, [])
  })
}

const unavailable = [
  ['503', () => Promise.reject(httpError(503))],
  ['timeout', () => Promise.reject(Object.assign(new Error('timed out'), { code: 'ECONNABORTED' }))],
  ['invalid body', async () => '<html>proxy maintenance</html>'],
  ['missing username', async () => ({ success: true, data: {} })],
  ['blank username', async () => ({ success: true, data: { username: '   ' } })],
  ['non-boolean success', async () => ({ success: 'true', data: { username: 'unverified-owner' } })],
]
for (const [name, reply] of unavailable) {
  test(`${name} keeps protected content unmounted without logging out and permits retry`, async t => {
    const view = await fixture(t)
    view.state.reply = reply
    await assert.rejects(view.router.push('/tenants/list'), /Unable to verify the current user/)
    await settle()
    assertPrivateNotMounted(view)
    assert.equal(view.user.loadFailed, true)
    assert.equal(view.state.errors.length, 1)
    assert.equal(view.session.sessionExpired.value, false)
    assert.deepEqual(view.state.redirects, [])

    view.state.reply = async () => validUser()
    await view.router.push('/tenants/list')
    await settle()
    assert.equal(view.state.loads, 2)
    assert.equal(view.user.loadFailed, false)
    assert.deepEqual(view.state.mounts, ['tenants'])
  })
}

test('a stale cached username cannot bypass a failed verification', async t => {
  const view = await fixture(t)
  view.user.username = 'stale-owner'
  view.user.loadFailed = true
  view.state.reply = () => Promise.reject(httpError(503))
  await assert.rejects(view.router.push('/tenants/list'), /Unable to verify the current user/)
  assertPrivateNotMounted(view)
  assert.equal(view.state.loads, 1)
  assert.deepEqual(view.state.redirects, [])
})
