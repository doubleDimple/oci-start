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
const accountSource = await readFile(new URL('../src/utils/tenantAccount.ts', import.meta.url), 'utf8')
const accountUrl = moduleUrl(accountSource)
const componentSource = await readFile(new URL('../src/views/tenants/components/TenantResourceDialogs.vue', import.meta.url), 'utf8')
const { descriptor } = parse(componentSource, { filename: 'TenantResourceDialogs.vue' })
const script = compileScript(descriptor, { id: 'tenant-quota-drawer-test' })
const code = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_s, bindings, _q, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === '@/utils/tenantAccount') return `import ${bindings} from '${accountUrl}'`
  if (source === 'vue-i18n') return 'const useI18n = () => ({ t: key => key })'
  if (source === '@/composables/useCompactViewport') return 'const useCompactViewport = () => false'
  if (source === 'element-plus') return 'const ElMessage = {}; const ElMessageBox = {}'
  if (source === '@/api/tenant') return 'const tenantGet = async () => []; const tenantPut = async () => ({})'
  if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
  throw new Error(`Unexpected dependency: ${source}`)
})
const template = compileTemplate({ source: descriptor.template.content, filename: 'TenantResourceDialogs.vue', id: 'tenant-quota-drawer-test', compilerOptions: { bindingMetadata: script.bindings } })
assert.deepEqual(template.errors, [])
const { default: Dialogs } = await import(moduleUrl(code))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))

async function renderAction(action) {
  const app = createSSRApp({ ...Dialogs, render }, { tenant: { id: '101', defName: 'Demo Tenant', region: 'us-phoenix-1' }, action })
  app.component('el-drawer', {
    props: ['modelValue', 'direction', 'size', 'class'],
    render() {
      return h('div', { 'data-widget': 'el-drawer', 'data-direction': this.direction, class: this.class }, [
        this.$slots.header?.(),
        this.$slots.default?.(),
        this.$slots.footer?.(),
      ])
    },
  })
  app.component('el-dialog', {
    props: ['modelValue', 'title', 'class'],
    render() {
      return h('div', { 'data-widget': 'el-dialog', class: this.class }, [this.$slots.default?.(), this.$slots.footer?.()])
    },
  })
  for (const name of [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(m => m[1]))]) {
    if (name !== 'el-drawer' && name !== 'el-dialog') {
      app.component(name, { render() { return h('div', this.$slots.default?.()) } })
    }
  }
  return renderToString(app)
}

test('quota action renders in a right-to-left sliding el-drawer instead of an el-dialog', async () => {
  const html = await renderAction('quota')
  assert.match(html, /data-widget="el-drawer"/)
  assert.match(html, /data-direction="rtl"/)
  assert.match(html, /tenant-quota-drawer/)
  assert.doesNotMatch(html, /data-widget="el-dialog"/)
})

test('account detail action continues to render inside el-dialog', async () => {
  const html = await renderAction('detail')
  assert.match(html, /data-widget="el-dialog"/)
  assert.doesNotMatch(html, /data-widget="el-drawer"/)
})
