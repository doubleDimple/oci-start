import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, defineComponent, h, nextTick, reactive } from 'vue'

const moduleUrl = source => {
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  })
  return `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
}

const vueUrl = import.meta.resolve('vue')
const pricingSource = await readFile(new URL('../src/views/boot/bootPricing.ts', import.meta.url), 'utf8')
const pricingUrl = moduleUrl(pricingSource)
const sfcSource = await readFile(new URL('../src/views/boot/AddBootView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(sfcSource, { filename: 'AddBootView.vue' })
const script = compileScript(descriptor, { id: 'add-boot-risk-test' })

const setupSource = `import { h as __testH } from '${vueUrl}';\n` + script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_statement, bindings, _quote, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === 'vue-router') {
    return `
      const useRoute = () => globalThis.addBootFixture.route
      const useRouter = () => ({ push: async () => {}, back: () => {} })
      const onBeforeRouteLeave = () => {}
      const onBeforeRouteUpdate = () => {}
    `
  }
  if (source === 'vue-i18n') return "const useI18n = () => ({ t: (key, params) => params ? `${key}:${JSON.stringify(params)}` : key, locale: { value: 'zh' } })"
  if (source === 'element-plus') return 'const ElMessage = { success() {}, warning() {}, error() {} }'
  if (source === 'axios') return 'const isAxiosError = () => false'
  if (source === '@/composables/usePageMotion') return 'const usePageMotion = () => {}'
  if (source === '@/stores/shell') return 'const useShellStore = () => ({ setCloud() {} })'
  if (source === '@/views/regions/regionCoords') return 'const REGION_COORDINATES = { "us-phoenix-1": [33.4, -112] }; const regionCityName = code => code'
  if (source === './bootPricing') return `import ${bindings} from '${pricingUrl}'`
  if (source === '@/api/ociBoot') {
    return `
      const bootError = () => 'error'
      const generateBootPassword = async () => 'Pass#12345'
      const getBootImages = async () => []
      const getBootRegions = (...args) => globalThis.addBootFixture.getBootRegions(...args)
      const isBootTenantId = value => typeof value === 'string' && /^\\d+$/.test(value)
      const saveBootTask = async () => ({})
    `
  }
  if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return __testH('button', this.$attrs, this.$slots.default?.()) } }`
  throw new Error(`Unexpected dependency: ${source}`)
})

const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'AddBootView.vue',
  id: 'add-boot-risk-test',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
})
assert.deepEqual(template.errors, [])
const { default: AddBootView } = await import(moduleUrl(setupSource))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))

const makeNode = tag => ({
  tag,
  props: {},
  children: [],
  listeners: {},
  parent: null,
  style: {},
  addEventListener(type, fn) { this.listeners[type] = fn },
  removeEventListener(type) { delete this.listeners[type] },
  focus() {},
  setAttribute(k, v) { this.props[k] = v },
  removeAttribute(k) { delete this.props[k] },
})

const host = () => {
  const { createApp } = createRenderer({
    createElement: makeNode,
    createText: text => ({ ...makeNode('#text'), text }),
    createComment: text => ({ ...makeNode('#comment'), text }),
    setText: (node, text) => { node.text = text },
    setElementText: (node, text) => { node.children = [{ ...makeNode('#text'), text }] },
    insert: (child, parent, anchor) => {
      if (!parent?.children) return
      if (child.parent) child.parent.children = child.parent.children.filter(item => item !== child)
      const index = anchor ? parent.children.indexOf(anchor) : -1
      if (index === -1) parent.children.push(child)
      else parent.children.splice(index, 0, child)
      child.parent = parent
    },
    remove: el => {
      if (el?.parent) el.parent.children = el.parent.children.filter(item => item !== el)
    },
    patchProp: (el, key, _prev, next) => {
      if (key.startsWith('on')) el.listeners[key.slice(2).toLowerCase()] = next
      else el.props[key] = next
    },
    parentNode: el => el?.parent || null,
    nextSibling: el => el?.parent?.children[el.parent.children.indexOf(el) + 1] || null,
  })
  return createApp
}

function walk(node, visit) {
  if (!node) return
  visit(node)
  for (const child of node.children || []) walk(child, visit)
}

function findAll(node, predicate) {
  const matches = []
  walk(node, item => {
    if (predicate(item)) matches.push(item)
  })
  return matches
}

function textOf(node) {
  let text = ''
  walk(node, item => {
    if (item.tag === '#text') text += item.text
  })
  return text
}

function createHarness() {
  globalThis.addBootFixture = {
    route: reactive({ query: { tenantId: '101' }, params: {} }),
    async getBootRegions() {
      return [{ id: '101', region: 'us-phoenix-1', isHomeRegion: true, tenancyName: 'demo-tenancy' }]
    },
  }
  const createApp = host()
  const root = { tag: 'div', props: {}, children: [], listeners: {} }
  const Root = defineComponent({
    name: 'AddBootTestRoot',
    setup() {
      return () => h({ ...AddBootView, render })
    },
  })
  const app = createApp(Root)
  const stub = name => ({ name, render() { return h(name, this.$attrs, this.$slots.default?.()) } })
  app.component('el-select', stub('el-select'))
  app.component('el-option', stub('el-option'))
  app.component('el-dialog', stub('el-dialog'))
  app.component('el-popover', defineComponent({
    name: 'ElPopoverStub',
    props: { visible: Boolean, placement: String, popperClass: String },
    emits: ['update:visible', 'show'],
    setup(props, { slots, emit }) {
      const toggle = () => {
        const next = !props.visible
        emit('update:visible', next)
        if (next) emit('show')
      }
      return () => h('el-popover', { 'data-visible': String(props.visible), placement: props.placement, popperClass: props.popperClass }, [
        h('div', { class: 'popover-reference', onClick: toggle }, slots.reference?.()),
        props.visible ? h('div', { class: 'popover-content' }, slots.default?.()) : null,
      ])
    },
  }))
  app.mount(root)
  return { root, unmount: () => app.unmount() }
}

test('AddBootView hides risk warning banner initially and shows it only when exclamation trigger beside create button is clicked', async () => {
  const { root, unmount } = createHarness()
  try {
    await nextTick()
    await new Promise(resolve => setTimeout(resolve, 10))
    await nextTick()

    assert.equal(findAll(root, n => n.props?.class?.includes('boot-risk-strip')).length, 0)
    assert.equal(findAll(root, n => n.props?.id === 'boot-risk-popover').length, 0)

    const actions = findAll(root, n => n.props?.class?.includes('boot-toolbar-actions'))[0]
    assert.ok(actions)
    const trigger = findAll(actions, n => n.props?.class?.includes('boot-risk-trigger'))[0]
    assert.ok(trigger)
    assert.equal(trigger.props['aria-expanded'], false)

    const refWrapper = findAll(actions, n => n.props?.class === 'popover-reference')[0]
    refWrapper.listeners.click()
    await nextTick()
    await nextTick()

    assert.equal(trigger.props['aria-expanded'], true)
    const popoverCard = findAll(actions, n => n.props?.id === 'boot-risk-popover')[0]
    assert.ok(popoverCard)
    const cardText = textOf(popoverCard)
    assert.ok(cardText.includes('ociBoot.riskTitle'))
    assert.ok(cardText.includes('ociBoot.riskBanner'))

    const closeBtn = findAll(popoverCard, n => n.props?.class?.includes('boot-risk-popover-close'))[0]
    closeBtn.listeners.click()
    await nextTick()
    await nextTick()
    assert.equal(trigger.props['aria-expanded'], false)
    assert.equal(findAll(actions, n => n.props?.id === 'boot-risk-popover').length, 0)
  } finally {
    unmount()
  }
})
