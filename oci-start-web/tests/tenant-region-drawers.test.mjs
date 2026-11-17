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

async function compileSfc(relativePath, id) {
  const source = await readFile(new URL(relativePath, import.meta.url), 'utf8')
  const { descriptor } = parse(source, { filename: relativePath })
  const script = compileScript(descriptor, { id })
  const code = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_s, bindings, _q, dep) => {
    if (dep === 'vue') return `import ${bindings} from '${vueUrl}'`
    if (dep === 'vue-i18n') return 'const useI18n = () => ({ t: key => key, te: () => true, n: val => String(val), locale: { value: "zh" } })'
    if (dep === 'vue-router') return 'const useRoute = () => ({ query: {} })'
    if (dep === 'axios') return 'const isAxiosError = () => false'
    if (dep === 'element-plus') {
      if (bindings.includes('BaseTableColumn')) {
        return `const BaseTableColumn = { render() { return this.$slots.default?.({ row: {} }) || null } }`
      }
      return `
        const ElMessage = { success() {}, warning() {}, error() {} }
        const ElMessageBox = { async confirm() {} }
      `
    }
    if (dep === '@/api/tenant') return 'const tenantGet = async () => []; const tenantPost = async () => ({ success: true }); const tenantPut = async () => ({ success: true }); const tenantError = () => ""; const tenantCsrfToken = () => ""'
    if (dep === '@/api/request') return 'const request = { delete: async () => ({}), request: async () => ({ success: true }) }'
    if (dep === '@/utils/tenantPermissions') return 'const hasTenantPermission = () => true'
    if (dep === '@/composables/useCompactViewport') return 'const useCompactViewport = () => false'
    if (dep.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return this.$slots.default?.() || null } }`
    throw new Error(`Unexpected dependency in ${relativePath}: ${dep}`)
  })
  const template = compileTemplate({
    source: descriptor.template.content,
    filename: relativePath,
    id,
    compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
  })
  assert.deepEqual(template.errors, [])
  const { default: Component } = await import(moduleUrl(code))
  const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))
  const elementNames = [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(m => m[1]))]
  return { Component, render, elementNames }
}

async function renderSfc(sfc, props) {
  const app = createSSRApp({ ...sfc.Component, render: sfc.render }, props)
  app.component('el-drawer', {
    props: ['modelValue', 'direction', 'size', 'class'],
    render() {
      return h('div', {
        'data-widget': 'el-drawer',
        'data-direction': this.direction,
        'data-size': this.size,
        class: this.class,
      }, [this.$slots.header?.(), this.$slots.default?.(), this.$slots.footer?.()])
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
  for (const name of sfc.elementNames) {
    if (name !== 'el-drawer' && name !== 'el-dialog') {
      app.component(name, { render() { return h('div', this.$slots.default?.()) } })
    }
  }
  return renderToString(app)
}

const securitySfc = await compileSfc('../src/views/tenants/components/TenantRegionSecurityDialog.vue', 'region-security-drawer-test')
const volumesSfc = await compileSfc('../src/views/tenants/components/TenantRegionVolumesDialog.vue', 'region-volumes-drawer-test')
const mysqlSfc = await compileSfc('../src/views/tenants/components/TenantRegionMysqlDialog.vue', 'region-mysql-drawer-test')

const sampleTenant = {
  id: '201',
  defName: 'DEFAULT-不封号',
  region: 'us-phoenix-1',
}

test('TenantRegionSecurityDialog renders inside an RTL el-drawer', async () => {
  const html = await renderSfc(securitySfc, { tenant: sampleTenant })
  assert.match(html, /data-widget="el-drawer"/)
  assert.match(html, /data-direction="rtl"/)
  assert.match(html, /region-security-drawer/)
  assert.match(html, /DEFAULT-不封号 · us-phoenix-1/)
  assert.match(html, /security-drawer-footer/)
  assert.doesNotMatch(html, /data-widget="el-dialog"/)
})

test('TenantRegionVolumesDialog renders inside an RTL el-drawer', async () => {
  const html = await renderSfc(volumesSfc, { tenant: sampleTenant })
  assert.match(html, /data-widget="el-drawer"/)
  assert.match(html, /data-direction="rtl"/)
  assert.match(html, /tenant-region-volumes-drawer/)
  assert.match(html, /DEFAULT-不封号/)
  assert.match(html, /us-phoenix-1/)
  assert.match(html, /volume-footer/)
  assert.doesNotMatch(html, /data-widget="el-dialog"/)
})

test('TenantRegionMysqlDialog renders inside an RTL el-drawer', async () => {
  const html = await renderSfc(mysqlSfc, { tenant: sampleTenant })
  assert.match(html, /data-widget="el-drawer"/)
  assert.match(html, /data-direction="rtl"/)
  assert.match(html, /tenant-region-mysql-drawer/)
  assert.match(html, /DEFAULT-不封号 · us-phoenix-1/)
  assert.match(html, /mysql-drawer-footer/)
  assert.doesNotMatch(html, /data-widget="el-dialog"/)
})
