import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, defineComponent, h, nextTick } from 'vue'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`

const vueUrl = import.meta.resolve('vue')
const REVISION = '0123456789abcdef'.repeat(4)

const viewSource = await readFile(new URL('../src/views/settings/ApiTokensView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(viewSource, { filename: 'ApiTokensView.vue' })
const script = compileScript(descriptor, { id: 'api-tokens-test' })

const setupSource = `import { h as __testH, ref as __testRef, shallowRef as __testShallowRef, computed as __testComputed } from '${vueUrl}';\n`
  + script.content
    .replace(/import\s+['"][^'"]+\.scss['"];?/g, '')
    .replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_m, bindings, _q, mod) => {
    if (mod === 'vue') return `import ${bindings} from '${vueUrl}'`
    if (mod === 'vue-router') {
      return `
        const useRouter = () => ({ back() {}, push(target) { globalThis.apiTokenFixture.navigated.push(target) } })
        const useRoute = () => ({ fullPath: '/system/apiTokens' })
        const onBeforeRouteLeave = () => {}
      `
    }
    if (mod === 'element-plus') {
      return `const ElMessage = {
        success(m) { globalThis.apiTokenFixture.messages.push(['success', m]) },
        error(m) { globalThis.apiTokenFixture.messages.push(['error', m]) },
      }`
    }
    if (mod === 'vue-i18n') return "const useI18n = () => ({ t: (k, p) => p ? `${k}:${JSON.stringify(p)}` : k, locale: { value: 'zh-CN' } })"
    if (mod === '@/composables/useCompactViewport') return 'const useCompactViewport = () => ({ value: false })'
    if (mod === '@/utils/initialCredentials') return 'const copyCredentialText = v => globalThis.apiTokenFixture.copy(v)'
    if (mod === '@/api/apiTokens') return ''
    if (mod === './api-tokens/openApiSpec') {
      return 'const downloadOpenApiJson = origin => globalThis.apiTokenFixture.exports.push(origin)'
    }
    if (mod === './api-tokens/sessionTokenBridge') {
      return `
        const setSessionPlainToken = v => { globalThis.apiTokenFixture.sessionToken = v }
        const clearSessionPlainToken = () => { globalThis.apiTokenFixture.sessionToken = '' }
      `
    }
    if (mod === './api-tokens/useApiTokens') {
      return `
        const useApiTokens = () => globalThis.apiTokenFixture.page({
          ref: __testRef, shallowRef: __testShallowRef, computed: __testComputed,
        })
      `
    }
    if (mod.endsWith('.vue')) {
      const name = bindings.trim()
      return `const ${name} = { props: ['loading', 'disabled', 'type', 'modelValue', 'readonly', 'copyable'], emits: ['click', 'update:modelValue'], render() { return __testH(${name === 'PageBackButton' || name === 'GhostBtn' || name === 'PrimaryBtn' ? "'button'" : "'div'"}, { disabled: this.disabled, 'data-comp': '${name}', onClick: e => this.$emit('click', e) }, this.$slots.default?.()) } }`
    }
    if (mod.endsWith('.scss')) return ''
    throw new Error(`Unexpected import: ${mod}`)
  })

const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'ApiTokensView.vue',
  id: 'api-tokens-test',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
})
assert.deepEqual(template.errors, [])
const { default: ApiTokensView } = await import(moduleUrl(setupSource))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))

const makeNode = tag => ({
  tag, props: {}, children: [], listeners: {}, parent: null, style: {},
  addEventListener() {}, removeEventListener() {}, focus() {},
  setAttribute(k, v) { this.props[k] = v }, removeAttribute(k) { delete this.props[k] },
})

const { createApp } = createRenderer({
  createElement: makeNode,
  createText: text => ({ ...makeNode('#text'), text }),
  createComment: text => ({ ...makeNode('#comment'), text }),
  setText: (n, t) => { n.text = t },
  setElementText: (n, t) => { n.children = [{ ...makeNode('#text'), text: t }] },
  insert: (c, p, a) => {
    if (!p?.children) return
    if (c.parent) c.parent.children = c.parent.children.filter(x => x !== c)
    const i = a ? p.children.indexOf(a) : -1
    if (i === -1) p.children.push(c)
    else p.children.splice(i, 0, c)
    c.parent = p
  },
  remove: el => { if (el?.parent) el.parent.children = el.parent.children.filter(x => x !== el) },
  patchProp: (el, k, _p, next) => {
    if (k.startsWith('on')) el.listeners[k.slice(2).toLowerCase()] = next
    else el.props[k] = next
  },
  parentNode: el => el?.parent || null,
  nextSibling: el => el?.parent?.children[el.parent.children.indexOf(el) + 1] || null,
})

const walk = (node, visit) => { visit(node); for (const child of node.children || []) walk(child, visit) }
const textOf = node => node.tag === '#text' ? (node.text || '') : (node.children || []).map(textOf).join('')
const flush = async () => { for (let i = 0; i < 6; i++) { await Promise.resolve(); await nextTick() } }

test('ApiTokensView renders 2-column cards, copies bearer format with toast, and opens RTL drawer for token creation', async () => {
  const copied = []
  globalThis.document = { hidden: false, addEventListener() {}, removeEventListener() {} }
  globalThis.window = { setTimeout: () => 1, clearTimeout() {}, addEventListener() {}, removeEventListener() {}, history: {}, location: { origin: 'https://ops.example.com' } }

  globalThis.apiTokenFixture = {
    messages: [],
    navigated: [],
    exports: [],
    sessionToken: '',
    copy: async v => { copied.push(v); return true },
    page: ({ ref, shallowRef, computed }) => {
      const state = shallowRef({
        revision: REVISION,
        tokenName: 'Workflow API',
        description: 'Automation integration credential',
        enabled: true,
        hasToken: true,
        isExpired: false,
        expirationDays: 30,
        createdAt: '2026-10-15T10:30:00',
        expiresAt: '2026-11-14T10:30:00',
        daysUntilExpiration: 15,
        allowSwaggerAccess: true,
        serverTime: Date.now(),
        expiresAtEpochMs: Date.now() + 86400_000 * 15,
        serverTimeZone: 'Asia/Shanghai',
      })
      return {
        state,
        loaded: computed(() => true),
        loading: ref(false),
        problem: shallowRef(null),
        lastUpdated: ref(Date.now()),
        material: shallowRef(null),
        materialLoading: ref(false),
        materialProblem: shallowRef(null),
        mutation: shallowRef({ kind: null, pending: false, outcome: 'idle', problem: null, result: null }),
        canMutate: computed(() => true),
        contextLocked: computed(() => false),
        requiresReview: ref(false),
        reviewReady: computed(() => false),
        isExpired: ref(false),
        canReveal: computed(() => true),
        readbackChanged: computed(() => false),
        async refresh() { return true },
        async revealToken() {},
        clearMaterial() {},
        clearMutation() {},
        acknowledgeReview() {},
        async generateToken() {},
        async revokeToken() {},
      }
    },
  }

  const root = makeNode('div')
  const ElStub = name => defineComponent({
    name,
    props: ['modelValue', 'direction', 'size', 'title'],
    emits: ['update:modelValue'],
    setup(props, { slots }) {
      return () => h('div', { 'data-stub': name, 'data-open': String(Boolean(props.modelValue)), direction: props.direction }, [
        props.modelValue ? [slots.header?.(), slots.default?.(), slots.footer?.()] : null,
      ])
    },
  })

  const Comp = { ...ApiTokensView, render }
  const app = createApp({ setup: () => () => h(Comp) })
  app.component('el-drawer', ElStub('el-drawer'))
  app.component('el-dialog', ElStub('el-dialog'))
  app.component('el-select', ElStub('el-select'))
  app.component('el-option', ElStub('el-option'))
  app.mount(root)
  await flush()

  const cards = []
  walk(root, n => { if (n.tag === 'article' && String(n.props.class || '').includes('api-tokens-card')) cards.push(n) })
  assert.equal(cards.length, 2)

  const copyBtn = (() => {
    let found = null
    walk(root, n => { if (n.tag === 'button' && String(n.props.class || '').includes('api-token-copy-btn')) found = n })
    return found
  })()
  assert.ok(copyBtn)
  await copyBtn.listeners.click?.()
  assert.equal(copied[0], 'Authorization: Bearer <TOKEN>')
  assert.deepEqual(globalThis.apiTokenFixture.messages[0], ['success', 'apiTokens.copied'])

  const replaceBtn = (() => {
    let found = null
    walk(root, n => { if (n.tag === 'button' && textOf(n).includes('apiTokens.replace')) found = n })
    return found
  })()
  assert.ok(replaceBtn)
  replaceBtn.listeners.click?.()
  await flush()

  const drawer = (() => {
    let found = null
    walk(root, n => { if (n.props['data-stub'] === 'el-drawer') found = n })
    return found
  })()
  assert.ok(drawer)
  assert.equal(drawer.props['data-open'], 'true')
  assert.equal(drawer.props.direction, 'rtl')

  assert.doesNotMatch(viewSource, /\/swagger-ui|\/v3\/api-docs/)
  const docBtns = []
  walk(root, n => { if (n.tag === 'button' && String(n.props.class || '').includes('api-token-doc-btn')) docBtns.push(n) })
  assert.equal(docBtns.length, 2)
  docBtns[0].listeners.click?.()
  assert.equal(globalThis.apiTokenFixture.navigated[0], '/system/apiDocs')
  docBtns[1].listeners.click?.()
  assert.equal(globalThis.apiTokenFixture.exports.length, 1)
  assert.deepEqual(globalThis.apiTokenFixture.messages[1], ['success', 'apiTokens.exportedOpenApi'])

  app.unmount()
})
