import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createSSRApp, h } from 'vue'
import { renderToString } from 'vue/server-renderer'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`

const vueUrl = import.meta.resolve('vue')
const componentSource = await readFile(new URL('../src/views/tenants/components/TenantOperationDialogs.vue', import.meta.url), 'utf8')
const { descriptor } = parse(componentSource, { filename: 'TenantOperationDialogs.vue' })
const script = compileScript(descriptor, { id: 'tenant-traffic-drawer-test' })

const code = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_s, bindings, _q, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === 'vue-i18n') return "const useI18n = () => ({ t: key => key })"
  if (source === 'element-plus') return 'const ElMessage = { success() {} }; const ElMessageBox = { async confirm() {} }'
  if (source === '@/api/tenant') return 'const tenantGet = async () => ({ statisticsEnabled: true, threshold: 100, autoShutdown: false }); const tenantPost = async () => ({})'
  if (source === '@/utils/tenantPermissions') return 'const hasTenantPermission = () => true'
  if (source === '@/utils/session') return 'const checkSession = async () => {}'
  if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
  throw new Error(`Unexpected dependency: ${source}`)
})

const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'TenantOperationDialogs.vue',
  id: 'tenant-traffic-drawer-test',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
})
assert.deepEqual(template.errors, [])

const { default: OperationDialogs } = await import(moduleUrl(code))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))
const elementNames = [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(m => m[1]))]

async function renderAction(action) {
  const app = createSSRApp({ ...OperationDialogs, render }, {
    tenant: { id: '101', defName: 'Demo Tenant' },
    action,
  })
  app.component('el-drawer', {
    props: ['modelValue', 'direction', 'size', 'class'],
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
        this.$slots.header?.(),
        this.$slots.default?.(),
        this.$slots.footer?.(),
      ])
    },
  })
  for (const name of elementNames) {
    if (name !== 'el-drawer' && name !== 'el-dialog') {
      app.component(name, { render() { return h('div', this.$slots.default?.()) } })
    }
  }
  return renderToString(app)
}

test('traffic action renders inside a right-to-left sliding el-drawer instead of an el-dialog', async () => {
  const html = await renderAction('traffic')
  assert.match(html, /data-widget="el-drawer"/)
  assert.match(html, /data-direction="rtl"/)
  assert.match(html, /tenant-traffic-drawer/)
  assert.match(html, /Demo Tenant/)
  assert.match(html, /traffic-drawer-footer/)
  assert.doesNotMatch(html, /data-widget="el-dialog"/)
})

test('other operation actions continue to render inside el-dialog', async () => {
  const html = await renderAction('proxy')
  assert.match(html, /data-widget="el-dialog"/)
  assert.match(html, /tenant-operation-dialog/)
  assert.doesNotMatch(html, /data-widget="el-drawer"/)
})
