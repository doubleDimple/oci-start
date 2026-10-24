import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { File } from 'node:buffer'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, h, nextTick, reactive, ref } from 'vue'
import { AxiosError } from 'axios'

// Exercise the production API and SFC template with local transports and a tiny
// renderer. No backend, OCI call, browser, or credentials are needed.
const moduleUrl = source => {
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  })
  return `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
}
const vueUrl = import.meta.resolve('vue')
const apiSource = (await readFile(new URL('../src/api/tenantImport.ts', import.meta.url), 'utf8'))
  .replace("from 'axios'", `from '${import.meta.resolve('axios')}'`)
  .replace("import { i18n } from '@/i18n'", 'const i18n = { global: { t: key => key } }')
  .replace("import { tenantGet, tenantPost } from './tenant'", `
    const tenantGet = (...args: unknown[]) => globalThis.tenantImportFixture.get(...args)
    const tenantPost = (...args: unknown[]) => globalThis.tenantImportFixture.post(...args)
  `)
const apiUrl = moduleUrl(apiSource)
const api = await import(apiUrl)
const sfcSource = await readFile(new URL('../src/views/tenants/TenantImportView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(sfcSource, { filename: 'TenantImportView.vue' })
const script = compileScript(descriptor, { id: 'tenant-import-offline' })
const setupSource = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g,
  (statement, bindings, _quote, source) => {
    if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
    if (source === '@/api/tenantImport') return `import ${bindings} from '${apiUrl}'`
    if (source === 'vue-router') return 'const useRoute = () => globalThis.tenantImportFixture.route; const useRouter = () => globalThis.tenantImportFixture.router'
    if (source === 'vue-i18n') return 'const useI18n = () => globalThis.tenantImportFixture.i18n'
    if (source === '@/stores/shell') return 'const useShellStore = () => globalThis.tenantImportFixture.shell'
    if (source === '@/composables/usePageMotion') return 'const usePageMotion = () => {}'
    if (source === '@/utils/tenantPermissions') return 'const isManagedTenant = tenant => Boolean(tenant?.permissionMode); const loadTenantPermissionContext = async () => globalThis.tenantImportFixture.contextTenant'
    if (source === '@/views/regions/regionCoords') return "const REGION_COORDINATES = { 'ap-tokyo-1': {} }; const regionCityName = value => value"
    if (source === 'element-plus') return 'const ElMessage = { success(message) { globalThis.tenantImportFixture.messages.push(message) } }'
    if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
    throw new Error(`Unexpected production dependency: ${source}`)
  })
const template = compileTemplate({ source: descriptor.template.content, filename: 'TenantImportView.vue', id: 'tenant-import-offline',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false } })
assert.deepEqual(template.errors, [])
const { default: ImportView } = await import(moduleUrl(setupSource))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))

const fields = { userName: 'Fixture', tenantId: 'ocid1.user.oc1..fixture', fingerprint: 'fixture', tenancy: 'ocid1.tenancy.oc1..fixture', region: 'ap-tokyo-1' }
const options = { managedUserName: 'fixture-operator', permissions: ['BASIC_READ'], accountScope: { allUsers: false, passwordResetUserIds: [], userManagementGroupIds: [] } }
const catalog = [{ code: 'BASIC_READ', label: 'Basic', group: 'basic', defaultEnabled: true, required: true, supported: true }]
const keyFile = () => new File(['offline fixture only'], 'fixture.pem')
function transport(t) {
  const previousFixture = globalThis.tenantImportFixture, previousFile = globalThis.File, previousDocument = globalThis.document
  const previousDocumentClass = globalThis.Document, previousShadowRoot = globalThis.ShadowRoot
  const state = {
    calls: [], getCalls: [], messages: [], result: { success: true, code: 200 }, error: null,
    contextTenant: { id: '353', cloudType: 1, tenantId: fields.tenantId, tenancy: fields.tenancy, userName: 'Fixture', regionEn: fields.region },
    route: reactive({ query: { cloudType: '1' } }), router: { push: async () => {}, replace: async () => {} },
    shell: reactive({ cloudType: 1, setCloud(value) { this.cloudType = value } }),
    i18n: { t: key => key, locale: ref('zh') },
    async get(url, params, config) {
      this.getCalls.push({ url, params, config })
      return url === '/tenants/exportByTenant' ? this.backup : { success: true, data: catalog }
    },
    async post(url, data, config) { this.calls.push({ url, data, config }); if (this.error) throw this.error; return this.result },
  }
  globalThis.tenantImportFixture = state
  globalThis.File = File
  globalThis.document = { activeElement: null }
  globalThis.Document = class {}
  globalThis.ShadowRoot = class {}
  t.mock.method(globalThis, 'fetch', () => { throw new Error('Network is forbidden in this fixture') })
  t.after(() => {
    state.unmount?.()
    globalThis.tenantImportFixture = previousFixture
    globalThis.File = previousFile
    globalThis.document = previousDocument
    globalThis.Document = previousDocumentClass
    globalThis.ShadowRoot = previousShadowRoot
  })
  return state
}
const node = type => ({ type, children: [], parent: null, props: {}, style: {}, addEventListener() {}, removeEventListener() {},
  getRootNode() { return { activeElement: null } },
  querySelector(selector) { return selector.startsWith('#') ? flatten(this).find(el => el.props.id === selector.slice(1)) || null : null },
  focus() {},
  setAttribute(key, value) { this.props[key] = value }, removeAttribute(key) { delete this.props[key] } })
const renderer = createRenderer({
  createElement: node, createText: text => ({ ...node('#text'), text }), createComment: text => ({ ...node('#comment'), text }),
  setText: (el, text) => { el.text = text }, setElementText: (el, text) => { el.text = text; el.children = [] },
  patchProp: (el, key, _previous, value) => { el.props[key] = value },
  insert(el, parent, anchor) {
    if (el.parent) el.parent.children = el.parent.children.filter(child => child !== el)
    const index = anchor ? parent.children.indexOf(anchor) : -1
    if (index < 0) parent.children.push(el); else parent.children.splice(index, 0, el)
    el.parent = parent
  },
  remove: el => { if (el.parent) el.parent.children = el.parent.children.filter(child => child !== el) },
  parentNode: el => el.parent, nextSibling: el => el.parent?.children[el.parent.children.indexOf(el) + 1] || null,
})
const flatten = el => [el, ...el.children.flatMap(flatten)]
const textContent = el => el.type === '#comment' ? '' : `${el.text || ''}${el.children.map(textContent).join('')}`
async function settle() { for (let count = 0; count < 4; count++) { await Promise.resolve(); await nextTick() } }
async function view(t, overrides = {}) {
  const state = transport(t)
  Object.assign(state, overrides)
  const container = node('root')
  const app = renderer.createApp({ ...ImportView, render })
  for (const name of [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(match => match[1]))]) {
    app.component(name, { render() { return h('fixture-control', this.$slots.default?.()) } })
  }
  const vm = app.mount(container).$.setupState
  state.unmount = () => app.unmount()
  vm.chooseImportMode(true)
  await settle()
  if (!vm.downgradingTenant) {
    Object.assign(vm.form, fields)
    vm.keyFile = keyFile()
  }
  return { state, container, vm }
}

test('restricted and ordinary imports keep multipart fields and disable the Axios timeout', async t => {
  const state = transport(t)
  for (const restricted of [options, undefined]) {
    await api.saveTenantCredentials(1, fields, keyFile(), undefined, restricted)
    const request = state.calls.at(-1)
    assert.equal(request.url, restricted ? '/tenants/restricted/save' : '/tenants/save')
    assert.equal(request.config.timeout, 0)
    assert.equal(request.data.get('tenantId'), fields.tenantId)
    assert.equal(request.data.get('keyFileStr').name, 'fixture.pem')
    assert.equal(request.data.has('permissions'), Boolean(restricted))
  }
})

test('explicit business rejections preserve message/error/msg without an uncertain-outcome warning', async t => {
  const state = transport(t)
  for (const key of ['message', 'error', 'msg']) for (const rejectedByInterceptor of [true, false]) {
    const body = { success: false, code: 500, [key]: '原 API 私钥与指纹不匹配' }
    state.error = rejectedByInterceptor ? body : null
    state.result = body
    await assert.rejects(api.saveTenantCredentials(1, fields, keyFile(), undefined, options), error => {
      assert.equal(api.tenantImportError(error), body[key])
      assert.equal(api.tenantImportOutcomeUnknown(error), false)
      return true
    })
  }
})

test('local validation and explicit HTTP rejections are distinct from interrupted writes', async t => {
  const state = transport(t)
  await assert.rejects(api.saveTenantCredentials(1, { ...fields, tenantId: '' }, keyFile()), error => {
    assert.equal(api.tenantImportOutcomeUnknown(error), false)
    return true
  })
  assert.equal(state.calls.length, 0)
  for (const status of [400, 401, 403, 404, 413, 429]) {
    const error = new AxiosError('Rejected', 'ERR_BAD_REQUEST', {}, {}, { status, data: { message: 'Request rejected' } })
    assert.equal(api.tenantImportOutcomeUnknown(error), false)
    assert.equal(api.tenantImportError(error), 'Request rejected')
  }
  for (const code of ['ERR_NETWORK', 'ECONNABORTED', 'ETIMEDOUT', 'ERR_CANCELED']) {
    assert.equal(api.tenantImportOutcomeUnknown(new AxiosError('Interrupted', code, {}, {})), true)
  }
  for (const status of [408, 500, 502, 504]) {
    assert.equal(api.tenantImportOutcomeUnknown(new AxiosError('Gateway failure', 'ERR_BAD_RESPONSE', {}, {}, { status, data: '<html>Upstream unavailable</html>' })), true)
  }
  state.result = '<html>Unexpected response</html>'
  await assert.rejects(api.saveTenantCredentials(1, fields, keyFile()), error => {
    assert.equal(api.tenantImportOutcomeUnknown(error), true)
    assert.equal(api.tenantImportError(error), 'tenantImport.invalidResponse')
    return true
  })
})

test('a submitted business error renders its actual reason inline without the connection warning', async t => {
  const { state, container, vm } = await view(t)
  state.error = { success: false, code: 500, message: '原 API 私钥与指纹不匹配' }
  await vm.submit()
  await nextTick()
  assert.equal(state.calls.length, 1)
  const alerts = flatten(container).filter(el => el.props.role === 'alert')
  assert.ok(alerts.some(el => textContent(el).includes('原 API 私钥与指纹不匹配')))
  assert.match(textContent(container), /tenantImport.saveFailed/)
  assert.doesNotMatch(textContent(container), /tenantImport.saveUnknown/)
  assert.equal(vm.saving, false)
})

test('a submitted network failure renders the uncertainty reminder and retains the draft', async t => {
  const { state, container, vm } = await view(t)
  state.error = new AxiosError('Network Error', 'ERR_NETWORK', {}, {})
  await vm.submit()
  await nextTick()
  assert.match(textContent(container), /tenantImport.networkError/)
  assert.match(textContent(container), /tenantImport.saveUnconfirmed/)
  assert.match(textContent(container), /tenantImport.saveUnknown/)
  assert.match(textContent(container), /tenantImport.checkList/)
  assert.equal(vm.saved, false)
  assert.equal(vm.form.tenantId, fields.tenantId)
  assert.equal(vm.keyFile.name, 'fixture.pem')
})

const downgradeSource = { id: '9223372036854775807', userId: fields.tenantId, tenancy: fields.tenancy, name: 'Fixture', region: fields.region }
const backupRow = () => ({ id: downgradeSource.id, id_str: downgradeSource.id, cloud_type: 1, tenant_id: fields.tenantId,
  tenancy: fields.tenancy, fingerprint: fields.fingerprint, region: fields.region, key_file_content: 'PRIVATE KEY FIXTURE — DO NOT PRINT', children: [] })
const downgradeRoute = () => reactive({ query: { cloudType: '2', downgradeTenantId: '353' } })

test('downgrade sends only local ID, selected grants and backup confirmation with no credentials', async t => {
  const state = transport(t)
  await assert.rejects(api.downgradeTenantCredentials('353', options, false), error => {
    assert.equal(api.tenantImportError(error), 'tenantImport.backupRequired')
    assert.equal(api.tenantImportOutcomeUnknown(error), false)
    return true
  })
  for (const id of ['0', '-1', '9223372036854775808', fields.tenantId]) {
    await assert.rejects(api.downgradeTenantCredentials(id, options, true))
  }
  assert.equal(state.calls.length, 0)
  await api.downgradeTenantCredentials(downgradeSource.id, options, true)
  const request = state.calls[0]
  assert.equal(request.url, '/tenants/restricted/downgrade')
  assert.equal(request.config.timeout, 0)
  assert.deepEqual(request.data, { tenantId: downgradeSource.id, managedUserName: options.managedUserName,
    permissions: JSON.stringify(options.permissions), accountScope: JSON.stringify(options.accountScope), backupConfirmed: true })
  state.result = { success: false, message: '原 API 没有创建策略权限' }
  await assert.rejects(api.downgradeTenantCredentials('353', options, true), error => {
    assert.equal(api.tenantImportError(error), state.result.message)
    assert.equal(api.tenantImportOutcomeUnknown(error), false)
    return true
  })
})

test('backup validates identity and every private key, preserves raw Long IDs, and never exposes key contents in errors', async t => {
  const state = transport(t)
  const root = backupRow()
  root.children = [{ ...backupRow(), id: '9223372036854775806', id_str: '9223372036854775806', paren_id: downgradeSource.id }]
  const raw = JSON.stringify([root]).replace(/"(922337203685477580[67])"/g, (_match, id) => id)
    .replace(/"id_str":(922337203685477580[67])/g, '"id_str":"$1"')
  state.backup = raw
  const blob = await api.loadTenantDowngradeBackup(downgradeSource, ' ab12cd34 ')
  assert.equal(await blob.text(), raw)
  assert.deepEqual(state.getCalls[0].params, { id: downgradeSource.id })
  assert.equal(state.getCalls[0].config.headers['X-Verify-Code'], 'AB12CD34')
  assert.equal(state.getCalls[0].config.responseType, 'text')
  const badBackups = [[], [root, root], [{ ...root, id: '12' }], [{ ...root, tenant_id: 'ocid1.user.oc1..other' }],
    [{ ...root, key_file_content: '' }], [{ ...root, key_file_content: null }], [{ ...root, tenancy: 'ocid1.tenancy.oc1..other' }],
    [{ ...root, children: [{ ...root.children[0], key_file_content: null }] }],
    [{ ...root, permission_mode: 'managed-v1' }], [{ ...root, region: '' }], '<html>Not a backup</html>']
  for (const value of badBackups) {
    state.backup = typeof value === 'string' ? value : JSON.stringify(value)
    await assert.rejects(api.loadTenantDowngradeBackup(downgradeSource, 'AB12CD34'), error => {
      assert.equal(api.tenantImportError(error), 'tenantImport.backupInvalid')
      assert.doesNotMatch(String(error), /PRIVATE KEY|DO NOT PRINT/)
      return true
    })
  }
})

test('backup rejects old six-digit codes locally and preserves an explicit export lock reason', async t => {
  const state = transport(t)
  await assert.rejects(api.loadTenantDowngradeBackup(downgradeSource, '123456'))
  assert.equal(state.getCalls.length, 0)
  state.backup = JSON.stringify({ success: false, message: '今日已暂停导出，请明天重试' })
  await assert.rejects(api.loadTenantDowngradeBackup(downgradeSource, 'AB12CD34'), error => {
    assert.equal(api.tenantImportError(error), '今日已暂停导出，请明天重试')
    return true
  })
  assert.equal(state.getCalls.length, 1)
  assert.equal(state.calls.length, 0)
})

test('downgrade view locks cloud and mode, omits credential inputs, and requires explicit backup confirmation', async t => {
  const { state, vm, container } = await view(t, { route: downgradeRoute() })
  assert.equal(vm.provider, 1)
  assert.equal(vm.restrictedMode, true)
  vm.chooseImportMode(false)
  assert.equal(vm.restrictedMode, true)
  assert.equal(vm.keyFile, null)
  assert.equal(vm.form.tenantId, '')
  assert.ok(!flatten(container).some(el => el.props.id === 'import-config' || el.props.id === 'import-tenantId'))
  assert.match(textContent(container), /tenantImport.backupWarning/)
  await vm.submit()
  assert.equal(state.calls.length, 0)
  assert.equal(vm.backupConfirmationInvalid, true)
  vm.backupConfirmed = true
  state.error = { success: false, message: '原 API 没有创建策略权限' }
  await vm.submit()
  await settle()
  assert.equal(state.calls.length, 1)
  assert.equal(state.calls[0].url, '/tenants/restricted/downgrade')
  assert.equal(state.calls[0].data.tenantId, '353')
  assert.equal(vm.backupConfirmed, true)
  assert.equal(vm.managedUserName, 'oci-start-operator')
  assert.deepEqual(vm.selectedPermissions, ['BASIC_READ'])
  assert.match(textContent(container), /原 API 没有创建策略权限/)
  assert.doesNotMatch(textContent(container), /tenantImport.downgradeUnknown/)
  state.error = null
  await vm.submit()
  await settle()
  assert.equal(vm.saved, true)
  assert.ok(state.messages.includes('tenantImport.downgradeSuccess'))
})

test('invalid downgrade source cannot submit even with a manually checked backup confirmation', async t => {
  const { state, vm, container } = await view(t, { route: downgradeRoute(), contextTenant: {
    id: '353', cloudType: 1, permissionMode: 'future-mode', tenantId: fields.tenantId, tenancy: fields.tenancy,
  } })
  vm.backupConfirmed = true
  await vm.submit()
  await settle()
  assert.equal(state.calls.length, 0)
  assert.equal(vm.downgradeSource, null)
  assert.match(textContent(container), /tenantImport.invalidDowngradeTenant/)
})

test('download is triggered only after validating backup and never auto-confirms that it was saved', async t => {
  const { state, vm, container } = await view(t, { route: downgradeRoute() })
  const downloads = []
  t.mock.method(URL, 'createObjectURL', () => 'blob:offline-backup')
  t.mock.method(URL, 'revokeObjectURL', value => downloads.push({ revoked: value }))
  globalThis.document.body = { appendChild() {} }
  globalThis.document.createElement = () => ({ click() { downloads.push({ href: this.href, filename: this.download }) }, remove() {} })
  vm.backupCodeSent = true
  await settle()
  const input = flatten(container).find(element => element.props.id === 'downgrade-backup-code')
  assert.equal(input.props.maxlength, '8')
  assert.equal(input.props.pattern, '[A-Z0-9]{8}')
  assert.match(textContent(container), /tenantImport.backupCodeLimit/)
  const target = { value: 'ab12cd34' }
  vm.setBackupCode({ target })
  assert.equal(target.value, 'AB12CD34')
  state.backup = JSON.stringify([{ ...backupRow(), id: '353', id_str: '353', key_file_content: null }])
  await vm.downloadBackup()
  assert.equal(downloads.length, 0)
  assert.equal(vm.backupDownloaded, false)
  state.backup = JSON.stringify([{ ...backupRow(), id: '353', id_str: '353' }])
  await vm.downloadBackup()
  assert.equal(downloads[0].filename, 'tenant_353_original_api.json')
  assert.equal(downloads[1].revoked, 'blob:offline-backup')
  assert.equal(vm.backupDownloaded, true)
  assert.equal(vm.backupConfirmed, false)
})

test('tenant list distinguishes unknown access and exposes downgrade only for ordinary non-transferred OCI tenants', async () => {
  const source = await readFile(new URL('../src/views/tenants/TenantsView.vue', import.meta.url), 'utf8')
  const functions = source.slice(source.indexOf('interface RowAction {'), source.indexOf('const deleteDialogVisible'))
  const list = await import(moduleUrl(`
    const t = key => key, shell = { cloudType: 1 }, compact = { value: false };
    const isManagedTenant = row => Boolean(row.permissionMode), hasTenantPermission = () => false;
    export const visits = []; const router = { push(value) { visits.push(value) } };
    ${functions}
    export { apiMode, canDowngrade, rowActions, runAction };
  `))
  const ordinary = { id: '9223372036854775807', cloudType: 1 }
  assert.equal(list.apiMode(ordinary), 'ordinary')
  assert.equal(list.apiMode({ ...ordinary, permissionMode: 'managed-v1' }), 'restricted')
  assert.equal(list.apiMode({ ...ordinary, permissionMode: 'future-mode' }), 'unknown')
  assert.ok(list.rowActions(ordinary).some(item => item.id === 'downgrade'))
  for (const row of [{ ...ordinary, permissionMode: 'managed-v1' }, { ...ordinary, permissionMode: 'future-mode' },
    { ...ordinary, transferStatus: 1 }, { ...ordinary, cloudType: 2 }]) {
    assert.equal(list.canDowngrade(row), false)
    assert.ok(!list.rowActions(row).some(item => item.id === 'downgrade'))
    list.runAction({ id: 'downgrade' }, row)
  }
  assert.equal(list.visits.length, 0)
  list.runAction({ id: 'downgrade' }, ordinary)
  assert.deepEqual(list.visits[0], { path: '/tenants/addSpeed', query: { cloudType: '1', downgradeTenantId: ordinary.id } })
})

test('desktop API type has its own header and cells, with aligned loading placeholders', async t => {
  const source = await readFile(new URL('../src/views/tenants/TenantsView.vue', import.meta.url), 'utf8')
  const start = source.indexOf('<table v-else class="tenant-table"')
  const tableTemplate = source.slice(start, source.indexOf('</table>', start) + '</table>'.length).replace('<table v-else', '<table')
  const compiled = compileTemplate({ source: tableTemplate, filename: 'TenantsView.vue', id: 'tenant-table-offline',
    compilerOptions: { expressionPlugins: ['typescript'], hoistStatic: false } })
  assert.deepEqual(compiled.errors, [])
  const { render: renderTable } = await import(moduleUrl(compiled.code.replace(/from "vue"/g, `from '${vueUrl}'`)))
  const { apiMode } = await import(moduleUrl(source.slice(source.indexOf('function apiMode('), source.indexOf('function canDowngrade(')) + '\nexport { apiMode };'))
  const state = reactive({ shell: { cloudType: 1 }, loaded: true, loading: false, highlightedRow: '', busyRow: '',
    rows: [{ id: '1' }, { id: '2', permissionMode: 'managed-v1' }, { id: '3', permissionMode: 'future-mode' }] })
  const container = node('root')
  const app = renderer.createApp({ render: renderTable, setup: () => ({ ...Object.fromEntries(Object.keys(state).map(key => [key, ref()])),
    ...state, t: key => key, numberFormat: { format: String }, apiMode, nameVisible: () => true,
    maskName: () => 'hidden', proxyLabel: () => '', accountType: () => 'free', activeDaysText: () => 'unavailable', createdAt: () => '', isActive: () => true,
    isMultiRegion: () => false, rowActions: () => [], openAction() {}, toggleName() {}, navigate() {}, runAction() {}, handleOpenDeleteTenant() {},
  }) })
  app.component('el-dropdown', { render() { return h('fixture-control', this.$slots.default?.()) } })
  app.component('el-dropdown-menu', { render() { return null } })
  app.component('el-dropdown-item', { render() { return null } })
  const instance = app.mount(container)
  t.after(() => app.unmount())
  const header = flatten(container).find(el => el.type === 'thead')
  assert.equal(flatten(header).filter(el => el.type === 'th').length, 9)
  assert.match(textContent(header), /tenant.list.columns.apiType/)
  const body = flatten(container).find(el => el.type === 'tbody')
  for (const [index, row] of body.children.filter(el => el.type === 'tr').entries()) {
    const cells = row.children.filter(el => el.type === 'td')
    assert.equal(cells.length, 9)
    assert.doesNotMatch(textContent(cells[0]), /tenant.apiMode/)
    assert.equal(cells[5].props.class, 'api-type-column')
    assert.match(textContent(cells[5]), new RegExp(`tenant.apiMode.${['ordinary', 'restricted', 'unknown'][index]}`))
  }
  instance.loaded = false
  instance.loading = true
  await nextTick()
  for (const row of flatten(container).filter(el => el.type === 'tr' && el.props.class === 'skeleton-row')) {
    assert.equal(row.children.filter(el => el.type === 'td').length, 9)
  }
})

test('downgrade success reads only cleanup warning strings and leaves unrelated response fields behind', async t => {
  const state = transport(t)
  state.result = { success: true, data: { id: '353', cleanupWarnings: ['  原密钥仍被其他记录使用，已保留。  ', ''], credentials: { privateKey: 'NEVER EXPOSE' } } }
  const warnings = await api.downgradeTenantCredentials('353', options, true)
  assert.deepEqual(warnings, ['原密钥仍被其他记录使用，已保留。'])
  state.result.data.cleanupWarnings.push('Later mutation')
  assert.equal(warnings.length, 1)
  for (const malformed of [null, 'not-an-array', [{ privateKey: 'NEVER EXPOSE' }]]) {
    state.result = { success: true, data: { cleanupWarnings: malformed } }
    assert.deepEqual(await api.downgradeTenantCredentials('353', options, true), ['tenantImport.cleanupWarningsUnavailable'])
  }
  for (const data of [{ id: '353' }, { id: '353', cleanupWarnings: [] }]) {
    state.result = { success: true, data }
    assert.deepEqual(await api.downgradeTenantCredentials('353', options, true), [])
  }
})

test('successful downgrade with cleanup warnings renders success and warnings, stays on the page and prevents resubmission', async t => {
  const visits = []
  const warning = '原密钥位于外部路径，已保留，请手动确认。'
  const { vm, state, container } = await view(t, { route: downgradeRoute(),
    router: { push: async value => visits.push(value), replace: async () => {} },
    result: { success: true, data: { id: '353', cleanupWarnings: [warning] } },
  })
  vm.backupConfirmed = true
  await vm.submit()
  await settle()
  assert.equal(vm.saved, true)
  assert.equal(vm.saving, false)
  assert.equal(vm.saveError, null)
  assert.equal(vm.locked, true)
  assert.equal(visits.length, 0)
  assert.match(textContent(container), /tenantImport.downgradeSuccess/)
  assert.match(textContent(container), /tenantImport.cleanupWarningsTitle/)
  assert.ok(flatten(container).some(el => el.props.role === 'alert' && textContent(el).includes(warning)))
  assert.match(textContent(container), /tenantImport.checkList/)
  assert.doesNotMatch(textContent(container), /tenantImport.saveFailed|tenantImport.downgradeUnknown/)
  await vm.clearForm()
  await vm.submit()
  assert.equal(vm.saved, true)
  assert.equal(state.calls.length, 1)
  vm.goBack()
  assert.deepEqual(visits[0], { path: '/tenants/list', query: { cloudType: '1' } })
})

test('successful downgrade without cleanup warnings still navigates to the tenant list', async t => {
  const visits = []
  const { vm } = await view(t, { route: downgradeRoute(), router: { push: async value => visits.push(value), replace: async () => {} },
    result: { success: true, data: { id: '353', cleanupWarnings: [] } },
  })
  vm.backupConfirmed = true
  await vm.submit()
  assert.equal(vm.saved, true)
  assert.deepEqual(visits, [{ path: '/tenants/list', query: { cloudType: '1' } }])
})
