import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, defineComponent, h, nextTick, reactive, ref } from 'vue'

const moduleUrl = source => {
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  })
  return `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
}

const vueUrl = import.meta.resolve('vue')
const sfcSource = await readFile(new URL('../src/views/tenants/components/TenantIdentityUsersWorkspace.vue', import.meta.url), 'utf8')
const { descriptor } = parse(sfcSource, { filename: 'TenantIdentityUsersWorkspace.vue' })
const script = compileScript(descriptor, { id: 'tenant-identity-drawers-test' })

const setupSource = `import { h as __testH } from '${vueUrl}';\n` + script.content
  .replace(/import\s+(['"])[^'"]+\.scss\1;?/g, '')
  .replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_statement, bindings, _quote, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === '@/utils/tenantPermissions') {
    return `
      const hasTenantPermission = () => true
      const isManagedTenant = tenant => Boolean(tenant?.permissionMode)
    `
  }
  if (source === '@/composables/useCompactViewport') return 'const useCompactViewport = () => globalThis.identityDrawerFixture.compact'
  if (source === 'vue-i18n') return "const useI18n = () => ({ t: (key, params) => params ? `${key}:${JSON.stringify(params)}` : key, locale: ref('zh') })"
  if (source === 'vue-router') return 'const useRoute = () => globalThis.identityDrawerFixture.route'
  if (source === 'element-plus') {
    return `
      const ElMessage = {
        success(msg) { globalThis.identityDrawerFixture.messages.push({ type: 'success', msg }) },
        warning(msg) { globalThis.identityDrawerFixture.messages.push({ type: 'warning', msg }) },
        error(msg) { globalThis.identityDrawerFixture.messages.push({ type: 'error', msg }) },
      }
      const ElMessageBox = { async confirm() { return true } }
    `
  }
  if (source === '@/api/tenant') {
    return `
      const tenantGet = (...args) => globalThis.identityDrawerFixture.get(...args)
      const tenantPost = (...args) => globalThis.identityDrawerFixture.post(...args)
    `
  }
  if (source.endsWith('.scss')) return ''
  if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return __testH('div', this.$slots.default?.()) } }`
  throw new Error(`Unexpected dependency: ${source}`)
})

const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'TenantIdentityUsersWorkspace.vue',
  id: 'tenant-identity-drawers-test',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
})
assert.deepEqual(template.errors, [])
const { default: TenantIdentityUsersWorkspace } = await import(moduleUrl(setupSource))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))

const node = type => ({
  type,
  children: [],
  parent: null,
  props: {},
  style: {},
  addEventListener() {},
  removeEventListener() {},
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
    if (el.parent) el.parent.children = el.parent.children.filter(child => child !== el)
    const index = anchor ? parent.children.indexOf(anchor) : -1
    if (index < 0) parent.children.push(el)
    else parent.children.splice(index, 0, el)
    el.parent = parent
  },
  remove: el => { if (el.parent) el.parent.children = el.parent.children.filter(child => child !== el) },
  parentNode: el => el.parent,
  nextSibling: el => el.parent?.children[el.parent.children.indexOf(el) + 1] || null,
})

const flatten = el => [el, ...el.children.flatMap(flatten)]
const textContent = el => el.type === '#comment' ? '' : `${el.text || ''}${el.children.map(textContent).join('')}`
async function settle() {
  for (let i = 0; i < 6; i++) {
    await Promise.resolve()
    await nextTick()
  }
}

function mountWorkspace(t, { compact = false, tenant = { id: '101', defName: 'Demo Tenant' } } = {}) {
  const prev = globalThis.identityDrawerFixture
  const getCalls = []
  const postCalls = []
  const messages = []
  const state = {
    compact: ref(compact),
    route: reactive({ query: {} }),
    messages,
    getCalls,
    postCalls,
    async get(url, params) {
      getCalls.push({ url, params })
      if (url === '/tenants/oracle-users') {
        return [{ id: 'u1', domain: 'Default', username: 'Default/alice', email: 'alice@example.com', lifecycleState: 'Active' }]
      }
      return []
    },
    async post(url, data) {
      postCalls.push({ url, data })
      if (url === '/tenants/groups') return [{ groupId: 'g1', groupName: 'Administrators' }]
      if (url === '/tenants/oracle-users/getPasspolicy') {
        return { success: true, data: [{ name: 'Default Policy', enablePasswordExpiry: true, expiryDays: 90 }] }
      }
      if (url === '/tenants/oracle-users') {
        return { username: data.username, email: data.email, password: 'TmpPassword#123' }
      }
      return { success: true }
    },
  }
  globalThis.identityDrawerFixture = state

  const container = node('root')
  const app = renderer.createApp({
    render: () => h({ ...TenantIdentityUsersWorkspace, render }, { tenant }),
  })
  app.directive('loading', {
    mounted(el, binding) { el.props['v-loading'] = Boolean(binding.value) },
    updated(el, binding) { el.props['v-loading'] = Boolean(binding.value) },
  })

  const ElDialogStub = defineComponent({
    name: 'ElDialog',
    props: ['modelValue', 'appendToBody', 'closeOnPressEscape', 'title', 'class'],
    emits: ['close'],
    setup(props, { slots }) {
      return () => h('el-dialog', {
        class: props.class,
        modelValue: props.modelValue,
        appendToBody: props.appendToBody === '' || props.appendToBody === true,
        closeOnPressEscape: props.closeOnPressEscape,
      }, [props.modelValue ? slots.default?.() : null])
    },
  })

  const ElDrawerStub = defineComponent({
    name: 'ElDrawer',
    props: ['modelValue', 'appendToBody', 'direction', 'size', 'class', 'closeOnPressEscape'],
    emits: ['close'],
    setup(props, { slots, emit }) {
      return () => h('el-drawer', {
        class: props.class,
        modelValue: props.modelValue,
        appendToBody: props.appendToBody === '' || props.appendToBody === true,
        direction: props.direction,
        size: props.size,
        closeOnPressEscape: props.closeOnPressEscape,
        onClose: () => emit('close'),
      }, props.modelValue ? [slots.header?.(), slots.default?.(), slots.footer?.()] : [])
    },
  })

  app.component('el-dialog', ElDialogStub)
  app.component('el-drawer', ElDrawerStub)
  for (const name of [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(m => m[1]))]) {
    if (name === 'el-dialog' || name === 'el-drawer') continue
    app.component(name, {
      props: ['label', 'name', 'disabled'],
      render() { return h('div', { ...this.$attrs, class: this.$attrs.class }, this.$slots.default?.()) },
    })
  }

  const rootVm = app.mount(container)
  const vm = rootVm.$.subTree.component.setupState
  t.after(() => {
    app.unmount()
    globalThis.identityDrawerFixture = prev
  })

  return { state, vm, container }
}

test('standalone users workspace renders tenant-card layout without dialog and opens add-user / policy RTL drawers', async t => {
  const { state, vm, container } = mountWorkspace(t)
  await settle()

  const mainDialog = flatten(container).find(el => el.type === 'el-dialog' && String(el.props.class).includes('tenant-identity-dialog'))
  assert.equal(mainDialog, undefined, 'users management must not be wrapped inside a modal el-dialog')

  const tenantCard = flatten(container).find(el => String(el.props?.class).includes('tenant-card'))
  assert.ok(tenantCard, 'renders tenant-card container matching TenantsView layout')

  const table = flatten(container).find(el => el.type === 'table' && String(el.props?.class).includes('tenant-table'))
  assert.ok(table, 'renders tenant-table for user rows')
  assert.match(textContent(table), /alice/)

  // Open Add User drawer
  vm.addUser()
  await settle()

  const userDrawer = flatten(container).find(el => el.type === 'el-drawer' && String(el.props.class).includes('identity-user-drawer'))
  const policyDrawer = flatten(container).find(el => el.type === 'el-drawer' && String(el.props.class).includes('identity-policy-drawer'))
  assert.equal(userDrawer.props.modelValue, true)
  assert.equal(userDrawer.props.appendToBody, true)
  assert.equal(userDrawer.props.direction, 'rtl')
  assert.equal(userDrawer.props.size, '500px')
  assert.equal(policyDrawer.props.modelValue, false)

  // Create user via drawer
  Object.assign(vm.userForm, { username: 'bob', email: 'bob@example.com', groupId: 'g1', useEmail: false })
  await vm.createUser()
  await settle()

  const createCall = state.postCalls.find(call => call.url === '/tenants/oracle-users')
  assert.deepEqual(createCall.data, { tenantId: '101', username: 'bob', email: 'bob@example.com', groupId: 'g1' })
  assert.equal(userDrawer.props.modelValue, false, 'user drawer closes after creation')

  // Open Password Policy drawer
  vm.openPolicy()
  await settle()

  assert.equal(policyDrawer.props.modelValue, true)
  assert.equal(policyDrawer.props.appendToBody, true)
  assert.equal(policyDrawer.props.direction, 'rtl')
  assert.match(textContent(policyDrawer), /Default Policy/)

  vm.policyForm.expiryDays = 180
  await vm.savePolicy()
  await settle()

  const savePolicyCall = state.postCalls.find(call => call.url === '/tenants/oracle-users/password-policy')
  assert.deepEqual(savePolicyCall.data, { tenantId: '101', enablePasswordExpiry: true, expiryDays: 180 })
  assert.equal(policyDrawer.props.modelValue, false, 'policy drawer closes after saving')
})

test('mobile viewport sizes both side drawers cleanly for narrow screens', async t => {
  const { vm, container } = mountWorkspace(t, { compact: true })
  await settle()

  vm.addUser()
  await settle()
  const userDrawer = flatten(container).find(el => el.type === 'el-drawer' && String(el.props.class).includes('identity-user-drawer'))
  assert.equal(userDrawer.props.size, 'min(94vw, 460px)')

  vm.handleDrawerClose('user')
  await settle()
  assert.equal(userDrawer.props.modelValue, false)

  vm.openPolicy()
  await settle()
  const policyDrawer = flatten(container).find(el => el.type === 'el-drawer' && String(el.props.class).includes('identity-policy-drawer'))
  assert.equal(policyDrawer.props.size, 'min(94vw, 460px)')
})

test('TenantsView navigates to standalone /tenants/users route and TenantIdentityView uses PageBackButton', async () => {
  const tenantsSource = await readFile(new URL('../src/views/tenants/TenantsView.vue', import.meta.url), 'utf8')
  const viewSource = await readFile(new URL('../src/views/tenants/TenantIdentityView.vue', import.meta.url), 'utf8')
  assert.match(tenantsSource, /id:\s*'users'[\s\S]*path:\s*'\/tenants\/users'/)
  assert.match(viewSource, /<PageBackButton/)
  assert.match(viewSource, /TenantIdentityUsersWorkspace/)
})

test('TenantIdentityUsersWorkspace renders clear loading indicators for initial tenant load and users table', async t => {
  assert.match(sfcSource, /class="identity-loading-state"[\s\S]*element-loading-text="t\('tenantIdentity\.loading\.users'\)"/)
  assert.match(sfcSource, /v-loading="loading\.users"[\s\S]*element-loading-text="t\('tenantIdentity\.loading\.users'\)"/)

  const prev = globalThis.identityDrawerFixture
  let resolveUsers
  globalThis.identityDrawerFixture = {
    compact: ref(false),
    route: reactive({ query: {} }),
    async get(url) {
      if (url === '/tenants/oracle-users') {
        return await new Promise(resolve => { resolveUsers = resolve })
      }
      return []
    },
    async post() { return { success: true } },
  }

  const container = node('root')
  const app = renderer.createApp({
    render: () => h({ ...TenantIdentityUsersWorkspace, render }, { tenant: { id: '101', defName: 'Demo Tenant' } }),
  })
  app.directive('loading', {
    mounted(el, binding) { el.props['v-loading'] = Boolean(binding.value) },
    updated(el, binding) { el.props['v-loading'] = Boolean(binding.value) },
  })
  const passthrough = (name) => defineComponent({
    name,
    setup(_props, { attrs, slots }) {
      return () => h(name.toLowerCase(), attrs, slots.default?.())
    },
  })
  app.component('ElDrawer', passthrough('el-drawer'))
  app.component('ElDialog', passthrough('el-dialog'))
  app.component('ElForm', passthrough('el-form'))
  app.component('ElFormItem', passthrough('el-form-item'))
  app.component('ElInput', passthrough('el-input'))
  app.component('ElInputNumber', passthrough('el-input-number'))
  app.component('ElSelect', passthrough('el-select'))
  app.component('ElOption', passthrough('el-option'))
  app.component('ElCheckbox', passthrough('el-checkbox'))
  app.component('ElSwitch', passthrough('el-switch'))
  app.component('ElButton', passthrough('el-button'))
  app.component('ElAlert', passthrough('el-alert'))

  app.mount(container)
  t.after(() => {
    app.unmount()
    globalThis.identityDrawerFixture = prev
  })

  await nextTick()
  const stageWhileLoading = flatten(container).find(el => String(el.props.class || '').includes('identity-table-stage'))
  assert.ok(stageWhileLoading, 'users table stage renders')
  assert.equal(stageWhileLoading.props['v-loading'], true, 'users table stage shows v-loading while loading users')
  assert.equal(stageWhileLoading.props['element-loading-text'], 'tenantIdentity.loading.users')

  resolveUsers([{ id: 'u1', domain: 'Default', username: 'Default/alice', email: 'alice@example.com', lifecycleState: 'Active' }])
  await settle()

  const stageAfterLoad = flatten(container).find(el => String(el.props.class || '').includes('identity-table-stage'))
  assert.equal(stageAfterLoad.props['v-loading'], false, 'users table stage clears v-loading once users finish loading')
})
