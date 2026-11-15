import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { computed, createRenderer, h, nextTick, provide, ref } from 'vue'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`

const vueUrl = import.meta.resolve('vue')
const headerBackSource = await readFile(new URL('../src/utils/headerBack.ts', import.meta.url), 'utf8')
const headerBackUrl = moduleUrl(headerBackSource)
const { LAYOUT_HEADER_BACK_KEY } = await import(headerBackUrl)

const backButtonSource = await readFile(new URL('../src/components/PageBackButton.vue', import.meta.url), 'utf8')
const { descriptor } = parse(backButtonSource, { filename: 'PageBackButton.vue' })
const script = compileScript(descriptor, { id: 'topbar-back-test' })
const setupSource = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_m, bindings, _q, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === 'vue-i18n') return "const useI18n = () => ({ t: k => k === 'pageBack' ? '返回' : k })"
  if (source === '@/utils/headerBack') return `import ${bindings} from '${headerBackUrl}'`
  throw new Error(`Unexpected import: ${source}`)
})
const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'PageBackButton.vue',
  id: 'topbar-back-test',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
})
assert.deepEqual(template.errors, [])
const { default: PageBackButton } = await import(moduleUrl(setupSource))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))
const BackButtonComponent = { ...PageBackButton, render }

const makeNode = tag => ({
  tag,
  props: {},
  children: [],
  listeners: {},
  parent: null,
  style: {},
  addEventListener(type, fn) { this.listeners[type] = fn },
  removeEventListener(type) { delete this.listeners[type] },
  setAttribute(k, v) { this.props[k] = v },
  removeAttribute(k) { delete this.props[k] },
})

const createApp = (() => {
  const { createApp: create } = createRenderer({
    createElement: makeNode,
    createText: text => ({ ...makeNode('#text'), text }),
    createComment: text => ({ ...makeNode('#comment'), text }),
    querySelector: () => null,
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

const findAll = (root, pred) => {
  const matches = []
  const walk = node => {
    if (pred(node)) matches.push(node)
    for (const child of node.children || []) walk(child)
  }
  walk(root)
  return matches
}

test('PageBackButton teleports into LAYOUT_HEADER_BACK_KEY unless local is true', async () => {
  const root = makeNode('div')
  const headerTarget = makeNode('div')
  const inlineParent = makeNode('section')
  let clicks = 0

  const app = createApp({
    setup() {
      const slotEl = ref(headerTarget)
      provide(LAYOUT_HEADER_BACK_KEY, computed(() => slotEl.value))
      return () => h('main', [
        h('div', { id: 'inline-wrapper' }, [
          h(BackButtonComponent, { onClick: () => { clicks += 1 } }),
        ]),
        h(BackButtonComponent, { local: true }),
      ])
    },
  })
  app.mount(root)
  await nextTick()

  const headerButtons = findAll(headerTarget, n => n.tag === 'button')
  assert.equal(headerButtons.length, 1, 'teleported back button should mount inside header slot')
  assert.ok(String(headerButtons[0].props.class || '').includes('in-header'))

  headerButtons[0].listeners.click?.({})
  assert.equal(clicks, 1)

  const localButtons = findAll(root, n => n.tag === 'button')
  assert.equal(localButtons.length, 1, 'local PageBackButton should remain inline and not teleport')
  assert.ok(!String(localButtons[0].props.class || '').includes('in-header'))

  assert.ok(inlineParent)
  app.unmount()
})

test('PageBackButton stays inline cleanly when no header slot provider exists', async () => {
  const root = makeNode('div')
  const app = createApp({
    setup: () => () => h(BackButtonComponent),
  })
  app.mount(root)
  await nextTick()

  const buttons = findAll(root, n => n.tag === 'button')
  assert.equal(buttons.length, 1)
  assert.ok(!String(buttons[0].props.class || '').includes('in-header'))
  app.unmount()
})

test('MobileRecordList keeps its drill-down back button local', async () => {
  const mobileRecordList = await readFile(new URL('../src/components/MobileRecordList.vue', import.meta.url), 'utf8')
  assert.match(mobileRecordList, /<PageBackButton\s+local\b/)
})
