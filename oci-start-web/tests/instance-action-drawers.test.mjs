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
    if (dep === 'vue-i18n') return 'const useI18n = () => ({ t: key => key, n: val => String(val) })'
    if (dep === 'element-plus') return 'const ElMessage = { success() {}, error() {} }'
    if (dep === '@/api/tenant') return 'const tenantError = () => ""; const tenantPost = async () => ({}); const tenantPut = async () => ({}); const tenantCsrfToken = () => ""'
    if (dep === '@/utils/tenantPermissions') return 'const allowsInstanceAction = () => true; const hasTenantPermission = () => true; const isManagedTenant = () => false'
    if (dep === '@/utils/session') return 'const checkSession = async () => {}'
    if (dep.startsWith('@/api/')) return 'const dummy = null'
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

const networkSfc = await compileSfc('../src/views/instances/components/InstanceNetworkDialog.vue', 'network-drawer-test')
const reinstallSfc = await compileSfc('../src/views/instances/components/InstanceReinstallDialog.vue', 'reinstall-drawer-test')
const operationSfc = await compileSfc('../src/views/instances/components/InstanceOperationDialog.vue', 'operation-drawer-test')

const sampleRow = {
  id: 'inst-1',
  instanceId: 'ocid1.instance.oc1..demo',
  displayName: 'demo-vm',
  remark: '',
  ocpus: 2,
  memoryInGBs: 12,
  bootVolumeId: 'vol-1',
  bootVolumeSizeInGBs: 50,
  vpusPerGB: 10,
  tenantId: 't-1',
}

test('InstanceNetworkDialog renders inside an RTL el-drawer for ip and ipv6', async () => {
  for (const action of ['ip', 'ipv6']) {
    const html = await renderSfc(networkSfc, { row: sampleRow, action })
    assert.match(html, /data-widget="el-drawer"/)
    assert.match(html, /data-direction="rtl"/)
    assert.match(html, /instance-network-drawer/)
    assert.doesNotMatch(html, /data-widget="el-dialog"/)
  }
})

test('InstanceReinstallDialog renders inside an RTL el-drawer', async () => {
  const html = await renderSfc(reinstallSfc, { row: sampleRow })
  assert.match(html, /data-widget="el-drawer"/)
  assert.match(html, /data-direction="rtl"/)
  assert.match(html, /instance-reinstall-drawer/)
  assert.doesNotMatch(html, /data-widget="el-dialog"/)
})

test('InstanceOperationDialog uses RTL el-drawer for config edits and keeps el-dialog for power/delete confirmations', async () => {
  for (const action of ['name', 'remark', 'config', 'volume', 'vpu']) {
    const html = await renderSfc(operationSfc, { row: sampleRow, action })
    assert.match(html, /data-widget="el-drawer"/, `expected drawer for ${action}`)
    assert.match(html, /data-direction="rtl"/, `expected rtl direction for ${action}`)
    assert.match(html, /instance-operation-drawer/, `expected drawer class for ${action}`)
    assert.doesNotMatch(html, /data-widget="el-dialog"/, `did not expect dialog for ${action}`)
  }

  for (const action of ['start', 'stop', 'terminate', 'delete']) {
    const html = await renderSfc(operationSfc, { row: sampleRow, action })
    assert.match(html, /data-widget="el-dialog"/, `expected dialog for ${action}`)
    assert.match(html, /instance-operation-dialog/, `expected dialog class for ${action}`)
    assert.doesNotMatch(html, /data-widget="el-drawer"/, `did not expect drawer for ${action}`)
  }
})
