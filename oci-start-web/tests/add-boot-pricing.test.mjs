import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, h, nextTick, reactive } from 'vue'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`

const vueUrl = import.meta.resolve('vue')
const pricingSource = await readFile(new URL('../src/views/boot/bootPricing.ts', import.meta.url), 'utf8')
const pricingUrl = moduleUrl(pricingSource)
const pricing = await import(pricingUrl)

const sfcSource = await readFile(new URL('../src/views/boot/AddBootView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(sfcSource, { filename: 'AddBootView.vue' })
const script = compileScript(descriptor, { id: 'add-boot-pricing-test' })
const setupSource = `import { h as __testH } from '${vueUrl}';\n` + script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_s, bindings, _q, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === 'vue-router') {
    return `
      const useRoute = () => globalThis.addBootPricingFixture.route
      const useRouter = () => ({ push: async () => {}, back: () => {} })
      const onBeforeRouteLeave = () => {}
      const onBeforeRouteUpdate = () => {}
    `
  }
  if (source === 'vue-i18n') return "const useI18n = () => ({ t: (k, p) => p ? `${k}:${JSON.stringify(p)}` : k, locale: { value: 'zh' } })"
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
      const getBootRegions = async () => [{ id: '101', region: 'us-phoenix-1', userName: 'admin', tenancyName: 'tenancy-a', isHomeRegion: true }]
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
  id: 'add-boot-pricing-test',
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

const createApp = (() => {
  const { createApp: create } = createRenderer({
    createElement: makeNode,
    createText: text => ({ ...makeNode('#text'), text }),
    createComment: text => ({ ...makeNode('#comment'), text }),
    setText: (node, text) => { node.text = text },
    setElementText: (node, text) => { node.children = [{ ...makeNode('#text'), text }] },
    insert: (child, parent, anchor) => {
      if (!parent?.children) return
      if (child.parent) child.parent.children = child.parent.children.filter(item => item !== child)
      const idx = anchor ? parent.children.indexOf(anchor) : -1
      if (idx === -1) parent.children.push(child)
      else parent.children.splice(idx, 0, child)
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
  return create
})()

const walk = (node, visit) => {
  visit(node)
  for (const child of node.children || []) walk(child, visit)
}
const findFirst = (node, pred) => {
  let match = null
  walk(node, item => { if (!match && pred(item)) match = item })
  return match
}
const textOf = node => node.tag === '#text' ? (node.text || '') : (node.children || []).map(textOf).join('')
const flush = async () => {
  for (let i = 0; i < 5; i++) {
    await nextTick()
    await new Promise(resolve => setTimeout(resolve, 0))
  }
}

test('estimateBootTemplatePrice computes accurate hourly and monthly OCI rates only for paid templates', () => {
  assert.equal(pricing.estimateBootTemplatePrice({ architecture: 'ARM', ocpu: 4, memory: 24, disk: 50, paid: false }), null)
  const e5 = pricing.estimateBootTemplatePrice({ architecture: 'AMD_PAID_E5', ocpu: 4, memory: 24, disk: 50, paid: true }, 2)
  assert.ok(e5)
  assert.equal(e5.shapeName, 'VM.Standard.E5.Flex')
  assert.ok(Math.abs(e5.perInstanceComputeHourlyUsd - 0.168) < 1e-6)
  assert.ok(Math.abs(e5.perInstanceStorageMonthlyUsd - 1.275) < 1e-6)
  assert.equal(e5.count, 2)
  assert.ok(Math.abs(e5.totalMonthlyUsd - e5.perInstanceMonthlyUsd * 2) < 1e-6)
})

test('AddBootView shows estimated price card when a custom paid template is selected and scales by instance count', async () => {
  globalThis.addBootPricingFixture = {
    route: reactive({ query: { tenantId: '101' } }),
  }
  const root = makeNode('div')
  const app = createApp({ setup: () => () => h({ ...AddBootView, render }) })
  const ElStub = { props: ['modelValue', 'visible'], render() { return h('div', this.$slots.default?.()) } }
  app.component('el-select', ElStub)
  app.component('el-option', ElStub)
  app.component('el-dialog', ElStub)
  app.component('el-popover', ElStub)
  app.mount(root)
  await flush()

  assert.equal(findFirst(root, n => String(n.props.class || '').includes('boot-price-card')), null)

  const customBtn = findFirst(root, n => n.tag === 'button' && textOf(n).includes('ociBoot.custom'))
  assert.ok(customBtn)
  customBtn.listeners.click?.()
  await flush()

  const paidInput = findFirst(root, n => n.tag === 'input' && n.props.type === 'radio' && n.props.value === 'amd-e5')
  assert.ok(paidInput)
  paidInput.props.checked = true
  paidInput.listeners['update:modelvalue']?.('amd-e5')
  await flush()

  const priceCard = findFirst(root, n => String(n.props.class || '').includes('boot-price-card'))
  assert.ok(priceCard, 'Expected boot-price-card to render for custom paid template amd-e5')
  assert.match(textOf(priceCard), /VM\.Standard\.E5\.Flex/)
  assert.match(textOf(priceCard), /\$0\.170|\$0\.17/)

  const countEl = findFirst(root, n => n.tag === 'input' && n.props.id === 'boot-count')
  assert.ok(countEl)
  countEl.listeners.input?.({ target: { value: '2' } })
  await flush()
  assert.match(textOf(findFirst(root, n => String(n.props.class || '').includes('boot-price-card'))), /priceTotal/)

  const freeInput = findFirst(root, n => n.tag === 'input' && n.props.type === 'radio' && n.props.value === 'arm-basic')
  assert.ok(freeInput)
  freeInput.listeners['update:modelvalue']?.('arm-basic')
  await flush()
  assert.equal(findFirst(root, n => String(n.props.class || '').includes('boot-price-card')), null)

  app.unmount()
})
