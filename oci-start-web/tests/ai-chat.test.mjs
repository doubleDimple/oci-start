import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, parse } from 'vue/compiler-sfc'
import { createRenderer, h, nextTick, reactive, ref } from 'vue'

// Execute the production SFC setup and API serializers/parsers. Only the route,
// transport, clock and visual component imports are replaced; no browser,
// backend, model endpoint or additional DOM dependency is required.
const require = createRequire(import.meta.url)
const vueUrl = pathToFileURL(require.resolve('vue')).href
function moduleUrl(source) {
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  })
  return `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
}
const apiSource = (await readFile(new URL('../src/api/aiChat.ts', import.meta.url), 'utf8'))
  .replace("import { isAxiosError } from 'axios'", `import axios from '${pathToFileURL(require.resolve('axios')).href}'; const { isAxiosError } = axios`)
  .replace("import { tenantGet } from './tenant'", 'const tenantGet = (...args: unknown[]) => globalThis.aiChatFixture.tenantGet(...args)')
const apiUrl = moduleUrl(apiSource)
const api = await import(apiUrl)
const sfcSource = await readFile(new URL('../src/views/ai/ChatView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(sfcSource, { filename: 'ChatView.vue' })
const setupSource = compileScript(descriptor, { id: 'ai-chat-offline-fixture' }).content
  .replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (statement, bindings, _quote, source) => {
    if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
    if (source === '@/api/aiChat') return `import ${bindings} from '${apiUrl}'`
    if (source === 'vue-router') return 'const useRoute = () => globalThis.aiChatFixture.route; const useRouter = () => globalThis.aiChatFixture.router'
    if (source === 'vue-i18n') return 'const useI18n = () => globalThis.aiChatFixture.i18n'
    if (source === '@/utils/session') return 'const checkSession = () => globalThis.aiChatFixture.checkSession()'
    if (source === 'element-plus') return 'const ElMessage = globalThis.aiChatFixture.toast; type InputInstance = { focus(): void }'
    if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
    throw new Error(`Unexpected production dependency: ${source}`)
  })
// ElMessage is bound at module evaluation, so defer the SFC import until its
// first fixture exists. Per-mount setup reads the current isolated route/state.
let ChatView
const renderer = createRenderer({
  createElement: type => ({ type, children: [], parent: null }),
  createText: text => ({ text }), createComment: text => ({ text }),
  setText: (node, text) => { node.text = text },
  setElementText: (node, text) => { node.text = text }, patchProp() {},
  insert: (child, parent) => { parent.children.push(child); child.parent = parent },
  remove: child => { if (child.parent) child.parent.children = child.parent.children.filter(item => item !== child) },
  parentNode: node => node.parent, nextSibling: () => null,
})

class Clock {
  now = 0
  nextId = 0
  tasks = new Map()
  schedule(callback, delay = 0, repeat = false, args = []) {
    const id = ++this.nextId
    this.tasks.set(id, { callback, due: this.now + Number(delay), interval: repeat ? Number(delay) : 0, args })
    return id
  }
  advance(milliseconds) {
    const end = this.now + milliseconds
    let calls = 0
    while (true) {
      const next = [...this.tasks.entries()].filter(([, task]) => task.due <= end)
        .sort((a, b) => a[1].due - b[1].due || a[0] - b[0])[0]
      if (!next) break
      assert.ok(++calls < 10000, 'a production timer must not spin forever')
      const [id, task] = next
      this.now = task.due
      if (task.interval) task.due += task.interval
      else this.tasks.delete(id)
      task.callback(...task.args)
    }
    this.now = end
  }
}

class FakeWebSocket {
  static CONNECTING = 0
  static OPEN = 1
  static CLOSING = 2
  static CLOSED = 3
  readyState = FakeWebSocket.CONNECTING
  onopen = null
  onmessage = null
  onerror = null
  onclose = null
  sent = []
  constructor(url) {
    this.url = String(url)
    globalThis.aiChatFixture.sockets.push(this)
  }
  send(payload) {
    assert.equal(this.readyState, FakeWebSocket.OPEN)
    this.sent.push(JSON.parse(payload))
  }
  close() { this.readyState = FakeWebSocket.CLOSED }
  open() { this.readyState = FakeWebSocket.OPEN; this.onopen?.({}) }
  receive(message) { this.onmessage?.({ data: typeof message === 'string' ? message : JSON.stringify(message) }) }
  remoteClose() { this.readyState = FakeWebSocket.CLOSED; this.onclose?.({}) }
}

function deferred() {
  let resolve, reject
  const promise = new Promise((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}
const model = id => ({ id, displayName: id, version: 'fixture', vendor: 'offline', lifecycleState: 'ACTIVE' })
async function settle() { for (let i = 0; i < 4; i++) { await Promise.resolve(); await nextTick() } }

async function fixture(t) {
  const clock = new Clock()
  const previous = new Map(['window', 'WebSocket', 'aiChatFixture'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]))
  const state = {
    clock, requests: [], sockets: [], checks: 0,
    route: reactive({ query: { tenantId: '1' }, fullPath: '/ai/chat?tenantId=1' }),
    router: { back() {}, push() {} },
    i18n: { t: key => key, locale: ref('en') },
    toast: { success() {}, error() {} },
    checkSession() { this.checks++; return Promise.resolve(true) },
    tenantGet(path, params, options) {
      const request = { ...deferred(), path, tenantId: params.tenantId, signal: options.signal }
      this.requests.push(request)
      return request.promise
    },
  }
  const window = new EventTarget()
  window.location = new URL('https://offline.invalid/ai/chat?tenantId=1')
  window.history = { state: {} }
  globalThis.window = window
  globalThis.WebSocket = FakeWebSocket
  globalThis.aiChatFixture = state
  t.mock.method(globalThis, 'fetch', () => { throw new Error('Real network is forbidden in this fixture') })
  t.mock.method(Date, 'now', () => clock.now)
  t.mock.method(globalThis, 'setTimeout', (callback, delay, ...args) => clock.schedule(callback, delay, false, args))
  t.mock.method(globalThis, 'setInterval', (callback, delay, ...args) => clock.schedule(callback, delay, true, args))
  t.mock.method(globalThis, 'clearTimeout', id => clock.tasks.delete(id))
  t.mock.method(globalThis, 'clearInterval', id => clock.tasks.delete(id))
  let app
  let unmounted = false
  state.unmount = () => { if (!unmounted && app) { app.unmount(); unmounted = true } }
  t.after(() => {
    state.unmount()
    assert.equal(clock.tasks.size, 0, 'unmount must cancel all production timers')
    for (const [key, descriptor] of previous) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor)
      else delete globalThis[key]
    }
  })
  ChatView ??= (await import(moduleUrl(setupSource))).default
  app = renderer.createApp({ ...ChatView, render() { return h('div') } })
  const vm = app.mount({ children: [] })
  state.vm = vm.$.setupState
  state.request = (path, tenantId = '1') => {
    const found = state.requests.findLast(request => request.path === path && request.tenantId === tenantId)
    assert.ok(found, `Missing ${path} request for tenant ${tenantId}`)
    return found
  }
  state.resolveModels = async (tenantId = '1', id = `model-${tenantId}`) => {
    state.request('/ai/models', tenantId).resolve({ success: true, models: [model(id)] })
    state.request('/tenants/regionList/json', tenantId).resolve([{ idStr: tenantId, defName: `Fixture ${tenantId}`, region: 'offline' }])
    await settle()
    return state.sockets.at(-1)
  }
  state.ready = async () => {
    const socket = await state.resolveModels()
    assert.equal(state.vm.connection, 'connecting')
    socket.open()
    assert.equal(state.vm.connection, 'initializing')
    assert.deepEqual(socket.sent, [{ type: 'init', tenant: { tenantId: '1', modelId: 'model-1' } }])
    socket.receive({ type: 'init', status: 'success' })
    assert.equal(state.vm.connection, 'ready')
    return socket
  }
  state.send = text => { state.vm.draft = text; state.vm.send() }
  return state
}

test('real API parser rejects malformed envelopes and preserves assistant chunks', () => {
  assert.throws(() => api.parseAiChatEvent('{bad'), api.AiChatResponseError)
  assert.throws(() => api.parseAiChatEvent(JSON.stringify({ message: 'missing type' })), api.AiChatResponseError)
  assert.equal(api.parseAiChatEvent(JSON.stringify({ type: 'chat', role: 'assistant', message: 'part', isChunk: true })).isChunk, true)
  assert.equal(api.parseAiChatEvent(JSON.stringify({ type: 'chat', role: 'assistant' })).message, undefined)
})

test('SFC opens, initializes, batches real parsed chunks, and finishes only at chat_end', async t => {
  const f = await fixture(t)
  const socket = await f.ready()
  assert.equal(socket.url, 'wss://offline.invalid/ws/aiChat')
  f.send('  hello  ')
  assert.equal(f.vm.activity, 'replying')
  assert.equal(f.vm.messages.at(-1).status, 'waiting')
  assert.equal(f.vm.draft, '')
  assert.deepEqual(socket.sent.at(-1), { type: 'chat', message: 'hello', tenantId: '1', modelId: 'model-1', useHistory: true })
  socket.receive({ type: 'chat', role: 'assistant', message: '你', isChunk: true })
  socket.receive({ type: 'chat', role: 'assistant', message: '好', isChunk: true })
  f.clock.advance(90)
  assert.equal(f.vm.messages.at(-1).content, '你好')
  assert.equal(f.vm.messages.at(-1).status, 'streaming')
  assert.equal(f.vm.activity, 'replying')
  socket.receive({ type: 'chat_end', status: 'success' })
  assert.equal(f.vm.messages.at(-1).status, 'complete')
  assert.equal(f.vm.activity, 'idle')
  assert.equal(f.vm.connection, 'ready')
})

test('initialization deadline ends preparation even with live heartbeat packets', async t => {
  const f = await fixture(t)
  const socket = await f.resolveModels()
  socket.open()
  f.clock.advance(15000)
  socket.receive({ type: 'heartbeat' })
  f.clock.advance(15000)
  assert.equal(f.vm.errorKey, 'initializationTimeout')
  assert.equal(f.vm.connection, 'disconnected')
  assert.equal(f.vm.preparing, false)
  assert.equal(socket.readyState, FakeWebSocket.CLOSED)
})

test('heartbeat and pong cannot extend the five-minute reply deadline', async t => {
  const f = await fixture(t)
  const socket = await f.ready()
  f.send('waiting for model')
  for (let i = 0; i < 11; i++) {
    f.clock.advance(25000)
    socket.receive({ type: i % 2 ? 'pong' : 'heartbeat' })
    assert.equal(f.vm.activity, 'replying')
  }
  f.clock.advance(25000)
  assert.equal(f.vm.errorKey, 'replyTimeout')
  assert.equal(f.vm.activity, 'idle')
  assert.equal(f.vm.messages.at(-1).status, 'interrupted')
  assert.equal(f.vm.connection, 'disconnected')
})

for (const stage of ['waiting', 'streaming']) {
  for (const ending of ['server-error', 'close', 'transport-error', 'malformed']) {
    test(`${ending} clears ${stage} and retains any received text`, async t => {
      const f = await fixture(t)
      const socket = await f.ready()
      f.send('request')
      if (stage === 'streaming') {
        socket.receive({ type: 'chat', role: 'assistant', message: 'partial', isChunk: true })
        f.clock.advance(90)
      }
      assert.equal(f.vm.messages.at(-1).status, stage)
      if (ending === 'server-error') socket.receive({ type: 'error', message: 'offline failure' })
      else if (ending === 'close') socket.remoteClose()
      else if (ending === 'transport-error') socket.onerror?.({})
      else socket.receive('{malformed')
      assert.equal(f.vm.connection, 'disconnected')
      assert.equal(f.vm.activity, 'idle')
      assert.equal(f.vm.messages.at(-1).status, ending === 'server-error' ? 'error' : 'interrupted')
      assert.equal(f.vm.messages.at(-1).content, stage === 'streaming' ? 'partial' : '')
      assert.equal(f.clock.tasks.size, 0)
    })
  }
}

test('route switches ignore late metadata/models and all old socket callbacks', async t => {
  const f = await fixture(t)
  const oldModels = f.request('/ai/models')
  const oldMetadata = f.request('/tenants/regionList/json')
  f.vm.draft = 'old draft'
  f.route.query.tenantId = '2'
  await settle()
  assert.equal(oldModels.signal.aborted, true)
  const socket = await f.resolveModels('2')
  oldModels.resolve({ success: true, models: [model('stale-model')] })
  oldMetadata.resolve([{ idStr: '1', defName: 'Stale label' }])
  await settle()
  assert.equal(f.vm.modelId, 'model-2')
  assert.equal(f.vm.tenant.id, '2')
  assert.equal(f.sockets.length, 1)
  socket.open()
  socket.receive({ type: 'init', status: 'success' })
  const stale = { open: socket.onopen, message: socket.onmessage, error: socket.onerror, close: socket.onclose }
  f.send('second tenant')
  f.route.query.tenantId = '3'
  await settle()
  assert.equal(socket.readyState, FakeWebSocket.CLOSED)
  const next = await f.resolveModels('3')
  next.open(); next.receive({ type: 'init', status: 'success' })
  stale.open({}); stale.error({}); stale.close({})
  stale.message({ data: JSON.stringify({ type: 'chat', role: 'assistant', message: 'stale text', isChunk: true }) })
  stale.message({ data: JSON.stringify({ type: 'chat_end', status: 'success' }) })
  assert.equal(f.vm.connection, 'ready')
  assert.equal(f.vm.messages.length, 0)
  assert.equal(f.vm.modelId, 'model-3')
  assert.equal(f.vm.tenant.id, '3')
  assert.equal(f.checks, 0, 'stale socket callbacks must not probe the login session')
})

test('cancelled model preparation ignores a late response and allows retry', async t => {
  const f = await fixture(t)
  const pending = f.request('/ai/models')
  f.vm.cancelPreparation()
  assert.equal(pending.signal.aborted, true)
  assert.equal(f.vm.preparing, false)
  pending.resolve({ success: true, models: [model('too-late')] })
  await settle()
  assert.equal(f.sockets.length, 0)
  assert.equal(f.vm.modelId, '')
  assert.equal(f.vm.connection, 'disconnected')
  f.vm.retryPreparation()
  const socket = await f.resolveModels()
  assert.equal(f.sockets.length, 1)
  assert.equal(socket.readyState, FakeWebSocket.CONNECTING)
})

test('cancelled initialization and unmount cannot be revived by queued socket packets', async t => {
  const f = await fixture(t)
  const socket = await f.resolveModels()
  socket.open()
  const receive = socket.onmessage
  f.vm.cancelPreparation()
  receive({ data: JSON.stringify({ type: 'init', status: 'success' }) })
  assert.equal(f.vm.connection, 'disconnected')
  assert.equal(f.clock.tasks.size, 0)
  f.vm.retryPreparation()
  const next = f.sockets.at(-1)
  next.open(); next.receive({ type: 'init', status: 'success' })
  const late = next.onmessage
  f.unmount()
  late({ data: JSON.stringify({ type: 'error', message: 'late' }) })
  assert.equal(f.vm.errorKey, '')
  assert.equal(next.readyState, FakeWebSocket.CLOSED)
  assert.equal(f.clock.tasks.size, 0)
})

test('reentrant send preserves the next draft and sends exactly one request', async t => {
  const f = await fixture(t)
  const socket = await f.ready()
  f.send('first')
  f.send('next draft')
  f.vm.send()
  assert.equal(socket.sent.filter(message => message.type === 'chat').length, 1)
  assert.equal(f.vm.messages.length, 2)
  assert.equal(f.vm.draft, 'next draft')
  f.vm.stopReceiving()
  assert.equal(f.vm.activity, 'idle')
  assert.equal(f.vm.messages.at(-1).status, 'interrupted')
  assert.equal(f.vm.errorKey, 'stopped')
})
