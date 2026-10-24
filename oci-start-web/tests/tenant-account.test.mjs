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
const accountUrl = moduleUrl(await readFile(new URL('../src/utils/tenantAccount.ts', import.meta.url), 'utf8'))
const { describeTenantAccount, accountActiveDays, hasMultipleAccountRegions } = await import(accountUrl)
const t = key => key

test('unknown subscription metadata falls back to saved classifications without claiming a paid plan from regions', () => {
  for (const [accountType, label] of Object.entries({ FREE_ACCOUNT: 'freeTier', TRIAL_PAID_ACCOUNT: 'trial', UPGRADE_ACCOUNT: 'payg', MANY_REGION_ACCOUNT: 'multiRegion' })) {
    assert.deepEqual(describeTenantAccount({ accountTypeName: '未知', accountType,
      registerDetail: { accountType: 'UNKNOWN_ENUM_VALUE', planType: { value: 'UNKNOWN_ENUM_VALUE' } } }, t), {
      source: 'stored', label: `tenant.account.${label}`,
    })
  }
  assert.deepEqual(describeTenantAccount({ accountType: 'FREE_ACCOUNT', registerDetail: { accountType: 'PERSONAL', planType: { value: 'PAYG' } } }, t), {
    source: 'subscription', label: 'tenant.account.personal · tenant.account.payg',
  })
  assert.equal(describeTenantAccount({ accountTypeName: '个人免费账号' }, t).label, 'tenant.account.personal · tenant.account.freeTier')
})

test('multi-region fallback counts distinct region records and excludes parent clones and hasChildren-only flags', () => {
  const parent = { id: '101', region: 'ap-tokyo-1', accountTypeName: '未知', accountType: 'UN_KNOW_ACCOUNT', hasChildren: true }
  assert.equal(describeTenantAccount(parent, t).source, 'unknown')
  assert.equal(describeTenantAccount({ ...parent, children: [{ ...parent }] }, t).source, 'unknown')
  assert.equal(hasMultipleAccountRegions({ ...parent, children: [{ id: '101', region: 'Tokyo' }, { id: '102', region: 'ap-tokyo-1' }] }), false)
  const fourRegions = { ...parent, children: [{ ...parent }, { id: '102', region: 'ap-seoul-1' }, { id: '103', region: 'ap-osaka-1' }, { id: '104', region: 'ap-chuncheon-1' }] }
  assert.deepEqual(describeTenantAccount(fourRegions, t), { source: 'regions', label: 'tenant.account.multiRegion' })
  assert.equal(describeTenantAccount({ ...parent, children: [null, '101', { id: '102' }, { region: '' }] }, t).source, 'unknown')
})

test('missing or invalid account age is unknown while a real numeric zero remains zero', () => {
  for (const value of [undefined, null, '', ' ', 'unknown', 'null', NaN, Infinity, -1, false, {}, '12 days']) assert.equal(accountActiveDays(value), null)
  for (const [value, expected] of [[0, 0], ['0', 0], ['214', 214], [214, 214]]) assert.equal(accountActiveDays(value), expected)
})

const vueUrl = import.meta.resolve('vue')
const componentSource = await readFile(new URL('../src/views/tenants/components/TenantResourceDialogs.vue', import.meta.url), 'utf8')
const { descriptor } = parse(componentSource, { filename: 'TenantResourceDialogs.vue' })
const script = compileScript(descriptor, { id: 'tenant-account-offline' })
const code = script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_statement, bindings, _quote, source) => {
  if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
  if (source === '@/utils/tenantAccount') return `import ${bindings} from '${accountUrl}'`
  if (source === 'vue-i18n') return 'const useI18n = () => ({ t: key => key })'
  if (source === '@/composables/useCompactViewport') return 'const useCompactViewport = () => false'
  if (source === 'element-plus') return 'const ElMessage = {}; const ElMessageBox = {}'
  if (source === '@/api/tenant') return 'const tenantGet = () => { throw new Error("Unexpected cloud request") }; const tenantPut = tenantGet'
  if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return null } }`
  throw new Error(`Unexpected dependency: ${source}`)
})
const template = compileTemplate({ source: descriptor.template.content, filename: 'TenantResourceDialogs.vue', id: 'tenant-account-offline', compilerOptions: { bindingMetadata: script.bindings } })
assert.deepEqual(template.errors, [])
const { default: AccountDialog } = await import(moduleUrl(code))
const { render } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))
async function dialog(tenant) {
  const app = createSSRApp({ ...AccountDialog, render }, { tenant, action: 'detail' })
  for (const name of [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(match => match[1]))]) {
    app.component(name, { render() { return h('div', this.$slots.default?.()) } })
  }
  return renderToString(app)
}

test('account dialog renders saved classification and region without inventing missing subscription details', async () => {
  const html = await dialog({ id: '101', defName: 'Saved account', region: 'ap-tokyo-1', accountType: 'MANY_REGION_ACCOUNT', accountTypeName: '未知' })
  assert.match(html, /Saved account/)
  assert.match(html, /tenantResources.account.localClassification/)
  assert.match(html, /tenant.account.multiRegion/)
  assert.match(html, /ap-tokyo-1/)
  assert.match(html, /tenantResources.account.empty/)
  assert.doesNotMatch(html, /tenantResources.account.registeredAt|tenantResources.account.email|tenantResources.account.address/)
})

test('account dialog still renders real subscription data when available', async () => {
  const html = await dialog({ id: '101', region: 'ap-tokyo-1', accountType: 'MANY_REGION_ACCOUNT', registerDetail: {
    accountType: 'PERSONAL', planType: 'FREE_TIER', registerTime: '2020-01-03', subscriptionPlanNumber: 'subscription-fixture', emailAddress: 'fixture@example.invalid', country: 'Fixture country',
  } })
  assert.match(html, /tenant.account.personal · tenant.account.freeTier/)
  assert.match(html, /2020-01-03/)
  assert.match(html, /subscription-fixture/)
  assert.match(html, /fixture@example.invalid/)
  assert.doesNotMatch(html, /tenantResources.account.empty/)
})
