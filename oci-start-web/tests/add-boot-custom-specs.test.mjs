import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, h, nextTick, reactive } from 'vue'

const savedTasks = []

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`

const vueUrl = import.meta.resolve('vue')
const pricingSource = await readFile(new URL('../src/views/boot/bootPricing.ts', import.meta.url), 'utf8')
const pricingUrl = moduleUrl(pricingSource)
const sfcSource = await readFile(new URL('../src/views/boot/AddBootView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(sfcSource, { filename: 'AddBootView.vue' })
const script = compileScript(descriptor, { id: 'add-boot-custom-specs-test' })

const setupSource = `import { h as __testH } from '${vueUrl}';\n` + script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_s, bindings, _q, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === 'vue-router') {
    return `
      const useRoute = () => globalThis.addBootCustomFixture.route
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
      const generateBootPassword = () => 'Pass#12345'
      const getBootImages = async () => []
      const getBootRegions = async () => [{ id: '101', region: 'us-phoenix-1', userName: 'admin', tenancyName: 'tenancy-a', isHomeRegion: true }]
      const isBootTenantId = value => typeof value === 'string' && /^\\d+$/.test(value)
      const saveBootTask = async (input) => { globalThis.addBootCustomFixture.savedTasks.push(input) }
    `
  }
  if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return __testH('button', this.$attrs, this.$slots.default?.()) } }`
  throw new Error(`Unexpected dependency: ${source}`)
})

const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'AddBootView.vue',
  id: 'add-boot-custom-specs-test',
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
  querySelector() { return null },
  setAttribute(k, v) { this.props[k] = v },
  removeAttribute(k) { delete this.props[k] },
})

const { createApp } = createRenderer({
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

const walk = (node, visit) => {
  if (!node) return
  visit(node)
  for (const child of node.children || []) walk(child, visit)
}
const findFirst = (node, pred) => {
  let match = null
  walk(node, item => { if (!match && pred(item)) match = item })
  return match
}
const findAll = (node, pred) => {
  const matches = []
  walk(node, item => { if (pred(item)) matches.push(item) })
  return matches
}
const textOf = node => node.tag === '#text' ? (node.text || '') : (node.children || []).map(textOf).join('')
const flush = async () => {
  for (let i = 0; i < 6; i++) {
    await nextTick()
    await new Promise(resolve => setTimeout(resolve, 0))
  }
}

function mountAddBoot() {
  savedTasks.length = 0
  globalThis.addBootCustomFixture = {
    route: reactive({ query: { tenantId: '101' } }),
    savedTasks,
  }
  const root = makeNode('div')
  const app = createApp({ setup: () => () => h({ ...AddBootView, render }) })
  const ElStub = { props: ['modelValue', 'visible'], render() { return h('div', this.$slots.default?.()) } }
  app.component('el-select', ElStub)
  app.component('el-option', ElStub)
  app.component('el-dialog', {
    props: ['modelValue'],
    render() {
      return this.modelValue ? h('div', { class: 'dialog-stub' }, [this.$slots.default?.(), this.$slots.footer?.()]) : null
    },
  })
  app.component('el-popover', ElStub)
  app.mount(root)
  return { root, unmount: () => app.unmount() }
}

test('AddBootView custom mode allows editing CPU and memory, updates live price/summary, validates bounds, and submits edited values', async () => {
  const { root, unmount } = mountAddBoot()
  try {
    await flush()

    const customBtn = findFirst(root, n => n.tag === 'button' && textOf(n).includes('ociBoot.custom'))
    assert.ok(customBtn)
    customBtn.listeners.click?.()
    await flush()

    const e5Radio = findFirst(root, n => n.tag === 'input' && n.props.type === 'radio' && n.props.value === 'amd-e5')
    assert.ok(e5Radio)
    e5Radio.listeners['update:modelvalue']?.('amd-e5')
    await flush()

    const ocpuInput = () => findFirst(root, n => n.tag === 'input' && n.props.id === 'boot-ocpu')
    const memoryInput = () => findFirst(root, n => n.tag === 'input' && n.props.id === 'boot-memory')
    assert.equal(ocpuInput()?.props.value, '4')
    assert.equal(memoryInput()?.props.value, '24')

    // Invalid CPU prevents confirmation dialog and shows inline error.
    ocpuInput().listeners.input?.({ target: { value: '0' } })
    await flush()
    const defaultImgToggle = findFirst(root, n => n.tag === 'input' && n.props.type === 'checkbox')
    defaultImgToggle.listeners['update:modelvalue']?.(true)
    await flush()

    const form = findFirst(root, n => n.tag === 'form')
    form.listeners.submit?.({ preventDefault() {} })
    await flush()
    assert.ok(findFirst(root, n => n.props.id === 'boot-ocpu-error'))
    assert.equal(findFirst(root, n => n.props.class === 'dialog-stub'), null)

    // Edit valid CPU and Memory via input and preset button.
    ocpuInput().listeners.input?.({ target: { value: '8' } })
    await flush()
    const mem64Preset = findAll(root, n => n.tag === 'button').find(n => textOf(n).includes('"size":"64"'))
    assert.ok(mem64Preset)
    mem64Preset.listeners.click?.()
    await flush()

    assert.equal(ocpuInput()?.props.value, '8')
    assert.equal(memoryInput()?.props.value, '64')

    // Price card and footer reflect 8 OCPU and 64 GB: 8*0.03 + 64*0.002 + 50*0.0255/744 = 0.3697 -> $0.370
    const priceCard = findFirst(root, n => String(n.props.class || '').includes('boot-price-card'))
    assert.match(textOf(priceCard), /\$0\.370/)
    const footer = findFirst(root, n => String(n.props.class || '').includes('boot-footer'))
    assert.match(textOf(footer), /"cpu":"8"/)
    assert.match(textOf(footer), /"memory":"64"/)

    // Submit and verify confirmation + saved payload use customized CPU and Memory.
    form.listeners.submit?.({ preventDefault() {} })
    await flush()
    const dialog = findFirst(root, n => n.props.class === 'dialog-stub')
    assert.ok(dialog)
    assert.match(textOf(dialog), /"cpu":"8"/)
    assert.match(textOf(dialog), /"memory":"64"/)

    const confirmBtn = findAll(dialog, n => n.tag === 'button').find(n => textOf(n).includes('ociBoot.riskConfirm'))
    assert.ok(confirmBtn)
    confirmBtn.listeners.click?.()
    await flush()

    assert.equal(savedTasks.length, 1)
    assert.equal(savedTasks[0].ocpu, 8)
    assert.equal(savedTasks[0].memory, 64)
    assert.equal(savedTasks[0].architecture, 'AMD_PAID_E5')
  } finally {
    unmount()
  }
})

test('AddBootView restores template defaults and locks fixed-shape AMD micro specs', async () => {
  const { root, unmount } = mountAddBoot()
  try {
    await flush()

    const customBtn = findFirst(root, n => n.tag === 'button' && textOf(n).includes('ociBoot.custom'))
    customBtn.listeners.click?.()
    await flush()

    const armRadio = findFirst(root, n => n.tag === 'input' && n.props.type === 'radio' && n.props.value === 'arm-basic')
    armRadio.listeners['update:modelvalue']?.('arm-basic')
    await flush()

    const ocpuInput = () => findFirst(root, n => n.tag === 'input' && n.props.id === 'boot-ocpu')
    const memoryInput = () => findFirst(root, n => n.tag === 'input' && n.props.id === 'boot-memory')
    ocpuInput().listeners.input?.({ target: { value: '3' } })
    memoryInput().listeners.input?.({ target: { value: '18' } })
    await flush()

    const restoreBtn = findAll(root, n => n.tag === 'button').find(n => textOf(n).includes('ociBoot.restoreTemplateSpecs'))
    assert.ok(restoreBtn)
    restoreBtn.listeners.click?.()
    await flush()
    assert.equal(ocpuInput()?.props.value, '1')
    assert.equal(memoryInput()?.props.value, '6')

    // Switching to amd-basic locks fixed 1 OCPU / 1 GB shape.
    const amdRadio = findFirst(root, n => n.tag === 'input' && n.props.type === 'radio' && n.props.value === 'amd-basic')
    amdRadio.listeners['update:modelvalue']?.('amd-basic')
    await flush()
    assert.equal(ocpuInput()?.props.value, '1')
    assert.equal(memoryInput()?.props.value, '1')
    assert.equal(Boolean(ocpuInput()?.props.disabled), true)
    assert.equal(Boolean(memoryInput()?.props.disabled), true)
    assert.ok(findFirst(root, n => String(n.props.class || '').includes('fixed-shape-hint')))
  } finally {
    unmount()
  }
})
