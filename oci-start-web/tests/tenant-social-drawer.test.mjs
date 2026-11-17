import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, createSSRApp, defineComponent, h, nextTick } from 'vue'
import { renderToString } from 'vue/server-renderer'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`

const vueUrl = import.meta.resolve('vue')
const componentSource = await readFile(new URL('../src/views/tenants/components/TenantIdentityDialogs.vue', import.meta.url), 'utf8')
const { descriptor } = parse(componentSource, { filename: 'TenantIdentityDialogs.vue' })
const script = compileScript(descriptor, { id: 'tenant-social-drawer-test' })

const code = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_s, bindings, _q, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === '@/utils/tenantPermissions') {
    return `
      const hasTenantPermission = () => true
      const isManagedTenant = tenant => Boolean(tenant?.permissionMode)
    `
  }
  if (source === 'vue-i18n') return "const useI18n = () => ({ t: key => key, locale: ref('zh') })"
  if (source === '@/composables/useCompactViewport') return 'const useCompactViewport = () => false'
  if (source === 'element-plus') return 'const ElMessage = { success() {}, warning() {}, error() {} }; const ElMessageBox = { async confirm() { return true } }'
  if (source === '@/api/tenant') {
    return `
      const tenantPost = async url => {
        if (url === '/social/list') {
          return { data: [{ id: 's1', socialTypeStr: 'Google', clientId: 'cid-1', redirectUrl: 'https://example.com/cb', socialStatus: 'active' }] }
        }
        if (url === '/social/availableLoginTypes') return { data: ['Google', 'GitHub'] }
        return { data: [] }
      }
    `
  }
  if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
  throw new Error(`Unexpected dependency: ${source}`)
})

const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'TenantIdentityDialogs.vue',
  id: 'tenant-social-drawer-test',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
})
assert.deepEqual(template.errors, [])

const { default: Dialogs } = await import(moduleUrl(code))
const testRenderCode = template.code
  .replace(/from "vue"/g, `from '${vueUrl}'`)
  .replace(/Transition as _Transition,?\s*/g, '')
  + '\nconst _Transition = (_props, { slots }) => slots.default?.()\n'
const { render } = await import(moduleUrl(testRenderCode))

const elementNames = [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(m => m[1]))]

async function renderAction(action) {
  const app = createSSRApp({ ...Dialogs, render }, {
    tenant: { id: '101', defName: 'Demo Tenant', region: 'us-phoenix-1' },
    action,
  })
  app.directive('loading', {})
  app.component('el-drawer', {
    props: ['modelValue', 'direction', 'size', 'class', 'closeOnClickModal'],
    render() {
      return h('div', {
        'data-widget': 'el-drawer',
        'data-direction': this.direction,
        'data-size': this.size,
        class: this.class,
      }, [
        this.$slots.header?.(),
        this.$slots.default?.(),
        this.$slots.footer?.(),
      ])
    },
  })
  app.component('el-dialog', {
    props: ['modelValue', 'title', 'class'],
    render() {
      return h('div', { 'data-widget': 'el-dialog', class: this.class }, [
        this.$slots.default?.(),
        this.$slots.footer?.(),
      ])
    },
  })
  app.component('el-table-column', {
    props: ['label', 'prop', 'width', 'minWidth', 'fixed'],
    render() {
      return h('div', this.$slots.default ? this.$slots.default({ row: { id: 's1', socialTypeStr: 'Google', clientId: 'cid-1', socialStatus: 'active' } }) : [])
    },
  })
  for (const name of elementNames) {
    if (!['el-drawer', 'el-dialog', 'el-table-column'].includes(name)) {
      app.component(name, { render() { return h('div', this.$slots.default?.()) } })
    }
  }
  return renderToString(app)
}

test('social action renders inside a right-to-left sliding el-drawer instead of an el-dialog', async () => {
  const html = await renderAction('social')
  assert.match(html, /data-widget="el-drawer"/)
  assert.match(html, /data-direction="rtl"/)
  assert.match(html, /tenant-social-drawer/)
  assert.match(html, /Demo Tenant/)
  assert.match(html, /us-phoenix-1/)
  assert.match(html, /social-drawer-footer/)
  assert.doesNotMatch(html, /data-widget="el-dialog"/)
})

test('email action continues to render inside centered el-dialog', async () => {
  const html = await renderAction('email')
  assert.match(html, /data-widget="el-dialog"/)
  assert.match(html, /tenant-identity-dialog/)
  assert.doesNotMatch(html, /data-widget="el-drawer"/)
})

test('social drawer enters editor view with footer save and cancel buttons', async () => {
  const node = type => ({
    type,
    children: [],
    parent: null,
    props: {},
    style: {},
    setAttribute(k, v) { this.props[k] = v },
    removeAttribute(k) { delete this.props[k] },
  })
  const renderer = createRenderer({
    createElement: node,
    createText: text => ({ ...node('#text'), text }),
    createComment: text => ({ ...node('#comment'), text }),
    setText: (el, text) => { el.text = text },
    setElementText: (el, text) => { el.text = text; el.children = [] },
    patchProp: (el, key, _prev, value) => { el.props[key] = value },
    insert(el, parent, anchor) {
      if (el.parent) el.parent.children = el.parent.children.filter(c => c !== el)
      const i = anchor ? parent.children.indexOf(anchor) : -1
      if (i < 0) parent.children.push(el)
      else parent.children.splice(i, 0, el)
      el.parent = parent
    },
    remove: el => { if (el.parent) el.parent.children = el.parent.children.filter(c => c !== el) },
    parentNode: el => el.parent,
    nextSibling: el => el.parent?.children[el.parent.children.indexOf(el) + 1] || null,
  })
  const flatten = el => [el, ...el.children.flatMap(flatten)]
  const textContent = el => el.type === '#comment' ? '' : `${el.text || ''}${el.children.map(textContent).join('')}`

  const root = node('root')
  const app = renderer.createApp(defineComponent({
    render: () => h({ ...Dialogs, render }, {
      tenant: { id: '101', defName: 'Demo Tenant', region: 'us-phoenix-1' },
      action: 'social',
    }),
  }))
  app.directive('loading', {})
  app.component('el-drawer', {
    props: ['modelValue', 'direction', 'closeOnClickModal'],
    render() {
      return h('div', { 'data-widget': 'el-drawer', 'data-close-modal': String(this.closeOnClickModal) }, [
        this.$slots.header?.(),
        this.$slots.default?.(),
        this.$slots.footer?.(),
      ])
    },
  })
  app.component('el-button', {
    props: ['disabled', 'type', 'loading'],
    emits: ['click'],
    render() {
      return h('button', { disabled: this.disabled, onClick: e => this.$emit('click', e) }, this.$slots.default?.())
    },
  })
  app.component('el-table-column', {
    props: ['label', 'prop', 'width', 'minWidth', 'fixed'],
    render() {
      return h('div', this.$slots.default ? this.$slots.default({ row: { id: 's1', socialTypeStr: 'Google', clientId: 'cid-1', socialStatus: 'active' } }) : [])
    },
  })
  for (const name of elementNames) {
    if (!['el-drawer', 'el-button', 'el-table-column'].includes(name)) {
      app.component(name, { render() { return h('div', this.$slots.default?.()) } })
    }
  }
  app.mount(root)
  for (let i = 0; i < 6; i++) {
    await Promise.resolve()
    await nextTick()
  }

  const drawerBefore = flatten(root).find(el => el.props?.['data-widget'] === 'el-drawer')
  assert.equal(drawerBefore.props['data-close-modal'], 'true')

  const addButton = flatten(root).find(el => el.type === 'button' && textContent(el).includes('tenantIdentity.actions.addSocial'))
  assert.ok(addButton)
  addButton.props.onClick({})
  await nextTick()
  await nextTick()

  const drawerAfter = flatten(root).find(el => el.props?.['data-widget'] === 'el-drawer')
  assert.equal(drawerAfter.props['data-close-modal'], 'false')
  assert.match(textContent(root), /tenantIdentity\.actions\.saveConfig/)
  assert.match(textContent(root), /tenantIdentity\.actions\.cancel/)

  const googleLink = flatten(root).find(el => el.type === 'a' && el.props?.href === 'https://console.cloud.google.com/apis/credentials')
  assert.ok(googleLink, 'renders direct link to Google Cloud OAuth credentials console')
  assert.equal(googleLink.props.target, '_blank')
  assert.equal(googleLink.props.rel, 'noopener noreferrer')
  assert.match(textContent(googleLink), /tenantIdentity\.actions\.openGoogleConsole/)

  app.unmount()
})
