import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, defineComponent, h, nextTick, reactive } from 'vue'

const moduleUrl = source => `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText).toString('base64')}`

const vueUrl = import.meta.resolve('vue')
const cfSource = (await readFile(new URL('../src/api/cloudflare.ts', import.meta.url), 'utf8'))
  .replace("import { isAxiosError, isCancel } from 'axios'", 'const isAxiosError = e => Boolean(e && e.isAxiosError); const isCancel = e => Boolean(e && e.__CANCEL__)')
  .replace("import request from './request'", 'const request = { delete: async () => ({}) }')
  .replace(
    "import { tenantCsrfToken, tenantGet, tenantPost, tenantPut } from './tenant'",
    `
      const tenantCsrfToken = () => 'csrf-token'
      const tenantGet = (...args) => globalThis.cfFixture.tenantGet(...args)
      const tenantPost = async () => ({})
      const tenantPut = async () => ({})
    `,
  )

const cfApiUrl = moduleUrl(cfSource)
const cfApi = await import(cfApiUrl)

const parseDrawerComponent = async (fileName, idPrefix) => {
  const source = await readFile(new URL(`../src/views/dns/components/${fileName}`, import.meta.url), 'utf8')
  const { descriptor } = parse(source, { filename: fileName })
  const script = compileScript(descriptor, { id: idPrefix })
  const setupSource = `import { h as __testH } from '${vueUrl}';\n` + script.content.replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_m, bindings, _q, mod) => {
    if (mod === 'vue') return `import ${bindings} from '${vueUrl}'`
    if (mod === 'element-plus') return 'const ElMessage = { success(m) { globalThis.cfFixture.messages.push(["success", m]) }, error(m) { globalThis.cfFixture.messages.push(["error", m]) } }'
    if (mod === 'vue-i18n') return "const useI18n = () => ({ t: (k, p) => p ? `${k}:${JSON.stringify(p)}` : k, locale: { value: 'zh' } })"
    if (mod === '@/api/cloudflare') return `import ${bindings} from '${cfApiUrl}'`
    if (mod === '@/composables/useCompactViewport') return 'const useCompactViewport = () => ({ value: false })'
    if (mod === '@/utils/initialCredentials') return 'const copyCredentialText = v => globalThis.cfFixture.copy(v)'
    if (mod.endsWith('.vue')) return `const ${bindings.trim()} = { props: ['loading', 'disabled'], emits: ['click'], render() { return __testH('button', { disabled: this.disabled, onClick: e => this.$emit('click', e) }, this.$slots.default?.()) } }`
    throw new Error(`Unexpected import: ${mod}`)
  })
  const template = compileTemplate({
    source: descriptor.template.content,
    filename: fileName,
    id: idPrefix,
    compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
  })
  assert.deepEqual(template.errors, [])
  const { default: Component } = await import(moduleUrl(setupSource))
  const { render: compRender } = await import(moduleUrl(template.code.replace(/from "vue"/g, `from '${vueUrl}'`)))
  return { ...Component, render: compRender }
}

const CloudflarePublicIpsDialogComp = await parseDrawerComponent('CloudflarePublicIpsDialog.vue', 'cf-public-ips-test')
const CloudflareOfficialIpsDialogComp = await parseDrawerComponent('CloudflareOfficialIpsDialog.vue', 'cf-official-ips-test')

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

const walk = (node, visit) => {
  visit(node)
  for (const child of node.children || []) walk(child, visit)
}
const textOf = node => node.tag === '#text'
  ? (node.text || '')
  : (node.children || []).map(textOf).join('')

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    await nextTick()
    await new Promise(resolve => setTimeout(resolve, 0))
  }
}

test('classifyPublicIp excludes private/reserved addresses and accepts public IPv4 and IPv6', () => {
  assert.equal(cfApi.classifyPublicIp('1.1.1.1'), 'IPv4')
  assert.equal(cfApi.classifyPublicIp('140.238.10.20'), 'IPv4')
  assert.equal(cfApi.classifyPublicIp('172.32.0.1'), 'IPv4')
  assert.equal(cfApi.classifyPublicIp('2603:c020:4001::10'), 'IPv6')
  assert.equal(cfApi.classifyPublicIp('2400:6180:0:d0::1'), 'IPv6')

  for (const excluded of [
    '', 'example.com', '127.0.0.1', '10.0.0.8', '192.168.1.1',
    '172.16.0.1', '172.31.255.254', '100.64.0.1', '169.254.169.254',
    '0.0.0.0', '::1', '::', 'fc00::1', 'fd12::1', 'fe80::1', '::ffff:192.168.1.5',
  ]) {
    assert.equal(cfApi.classifyPublicIp(excluded), null, `expected ${excluded} to be excluded`)
  }
})

test('fetchCloudflareAllPublicIps aggregates, filters private/non-IP records, and deduplicates public IPs', async () => {
  globalThis.cfFixture = {
    tenantGet: async path => {
      assert.equal(path, '/dns/cloudflare/api/records/all')
      return {
        success: true,
        data: {
          'alpha.example.com': [
            { id: '1', type: 'A', name: 'www', content: '140.238.10.20', ttl: 1, proxied: true },
            { id: '2', type: 'A', name: 'api', content: '140.238.10.20', ttl: 1, proxied: false },
            { id: '3', type: 'A', name: 'lan', content: '192.168.1.10', ttl: 1, proxied: false },
            { id: '4', type: 'CNAME', name: 'blog', content: 'www.alpha.example.com', ttl: 1, proxied: true },
          ],
          'beta.example.org': [
            { id: '5', type: 'A', name: 'beta.example.org', content: '140.238.10.20', ttl: 1, proxied: true },
            { id: '6', type: 'AAAA', name: 'v6', content: '2603:c020:4001::10', ttl: 1, proxied: false },
            { id: '7', type: 'AAAA', name: 'local6', content: 'fe80::1', ttl: 1, proxied: false },
          ],
        },
      }
    },
  }

  const result = await cfApi.fetchCloudflareAllPublicIps()
  assert.deepEqual(result.zones, ['alpha.example.com', 'beta.example.org'])
  assert.equal(result.totalRecords, 4)
  assert.equal(result.groups.length, 2)
  assert.equal(result.groups[0].ip, '140.238.10.20')
  assert.equal(result.groups[0].family, 'IPv4')
  assert.equal(result.groups[0].records.length, 3)
  assert.equal(result.groups[1].ip, '2603:c020:4001::10')
  assert.equal(result.groups[1].family, 'IPv6')
})

test('CloudflarePublicIpsDialog filters public IPs and supports single & bulk copy', async () => {
  const copiedValues = []
  globalThis.cfFixture = {
    messages: [],
    copy: async value => { copiedValues.push(value); return true },
    tenantGet: async () => ({
      success: true,
      data: {
        'alpha.example.com': [
          { id: '1', type: 'A', name: 'www', content: '140.238.10.20', ttl: 1, proxied: true },
          { id: '2', type: 'AAAA', name: 'v6', content: '2603:c020:4001::10', ttl: 1, proxied: false },
        ],
        'beta.example.org': [
          { id: '3', type: 'A', name: 'app', content: '129.153.40.8', ttl: 1, proxied: false },
        ],
      },
    }),
  }

  const root = makeNode('div')
  const state = reactive({ visible: true })
  const ElStub = name => defineComponent({
    name,
    props: ['modelValue', 'direction', 'size', 'clearable', 'placeholder'],
    emits: ['update:modelValue'],
    setup(_p, { slots }) {
      return () => h('div', { 'data-stub': name }, [slots.header?.(), slots.default?.(), slots.footer?.()])
    },
  })

  const app = createApp({
    setup: () => () => h(CloudflarePublicIpsDialogComp, { visible: state.visible, onClose: () => { state.visible = false } }),
  })
  app.component('el-drawer', ElStub('el-drawer'))
  app.component('el-input', ElStub('el-input'))
  app.component('el-select', ElStub('el-select'))
  app.component('el-option', ElStub('el-option'))
  app.mount(root)

  await flush()

  const ipTexts = []
  walk(root, n => { if (n.tag === 'code') ipTexts.push(textOf(n)) })
  assert.deepEqual(ipTexts, ['129.153.40.8', '140.238.10.20', '2603:c020:4001::10'])

  const buttons = []
  walk(root, n => { if (n.tag === 'button') buttons.push(n) })

  const ipv6Filter = buttons.find(b => textOf(b).trim() === 'IPv6')
  assert.ok(ipv6Filter)
  ipv6Filter.listeners.click?.()
  await flush()

  const filteredIps = []
  walk(root, n => { if (n.tag === 'code') filteredIps.push(textOf(n)) })
  assert.deepEqual(filteredIps, ['2603:c020:4001::10'])

  const singleCopyBtn = (() => {
    const btns = []
    walk(root, n => { if (n.tag === 'button' && String(n.props.class || '').includes('cf-ips-copy-btn')) btns.push(n) })
    return btns[0]
  })()
  assert.ok(singleCopyBtn)
  await singleCopyBtn.listeners.click?.()
  assert.equal(copiedValues[0], '2603:c020:4001::10')

  const allFilter = buttons.find(b => textOf(b).includes('allFamilies'))
  allFilter.listeners.click?.()
  await flush()

  const copyAllBtn = buttons.find(b => textOf(b).includes('copyAll'))
  assert.ok(copyAllBtn)
  await copyAllBtn.listeners.click?.()
  assert.equal(copiedValues[1], '129.153.40.8\n140.238.10.20\n2603:c020:4001::10')

  app.unmount()
})

test('fetchCloudflareOfficialIps parses live payload, falls back to verified built-in ranges, and formats nginx config', async () => {
  assert.equal(cfApi.CLOUDFLARE_OFFICIAL_IPV4_CIDRS.length, 15)
  assert.equal(cfApi.CLOUDFLARE_OFFICIAL_IPV6_CIDRS.length, 7)

  globalThis.cfFixture = {
    messages: [],
    copy: async () => true,
    tenantGet: async () => ({
      success: true,
      data: {
        ipv4: ['104.16.0.0/13', '172.64.0.0/13'],
        ipv6: ['2606:4700::/32'],
        etag: 'cf-etag-1',
        source: 'live',
      },
    }),
  }

  const live = await cfApi.fetchCloudflareOfficialIps()
  assert.equal(live.source, 'live')
  assert.equal(live.etag, 'cf-etag-1')
  assert.deepEqual(live.ipv4, ['104.16.0.0/13', '172.64.0.0/13'])
  assert.deepEqual(live.ipv6, ['2606:4700::/32'])

  globalThis.cfFixture.tenantGet = async () => {
    throw new Error('network down')
  }
  const fallback = await cfApi.fetchCloudflareOfficialIps()
  assert.equal(fallback.source, 'builtin')
  assert.equal(fallback.ipv4.length, 15)
  assert.equal(fallback.ipv6.length, 7)

  const nginx = cfApi.formatCloudflareNginxRealIpConfig(['104.16.0.0/13', '2606:4700::/32'])
  assert.equal(
    nginx,
    'set_real_ip_from 104.16.0.0/13;\nset_real_ip_from 2606:4700::/32;\nreal_ip_header CF-Connecting-IP;',
  )
})

test('CloudflareOfficialIpsDialog filters IPv4/IPv6 official CIDRs and copies single CIDR, all CIDRs, and nginx snippet', async () => {
  const copiedValues = []
  globalThis.cfFixture = {
    messages: [],
    copy: async value => { copiedValues.push(value); return true },
    tenantGet: async () => ({
      success: true,
      data: {
        ipv4: [...cfApi.CLOUDFLARE_OFFICIAL_IPV4_CIDRS],
        ipv6: [...cfApi.CLOUDFLARE_OFFICIAL_IPV6_CIDRS],
        source: 'live',
      },
    }),
  }

  const root = makeNode('div')
  const state = reactive({ visible: true })
  const ElStub = name => defineComponent({
    name,
    props: ['modelValue', 'direction', 'size', 'clearable', 'placeholder'],
    emits: ['update:modelValue'],
    setup(_p, { slots }) {
      return () => h('div', { 'data-stub': name }, [slots.header?.(), slots.default?.(), slots.footer?.()])
    },
  })

  const app = createApp({
    setup: () => () => h(CloudflareOfficialIpsDialogComp, { visible: state.visible, onClose: () => { state.visible = false } }),
  })
  app.component('el-drawer', ElStub('el-drawer'))
  app.component('el-input', ElStub('el-input'))
  app.mount(root)

  await flush()

  const allCidrs = []
  walk(root, n => { if (n.tag === 'code') allCidrs.push(textOf(n)) })
  assert.equal(allCidrs.length, 22)
  assert.ok(allCidrs.includes('104.16.0.0/13'))
  assert.ok(allCidrs.includes('2606:4700::/32'))

  const buttons = []
  walk(root, n => { if (n.tag === 'button') buttons.push(n) })

  const ipv6Filter = buttons.find(b => textOf(b).trim() === 'IPv6')
  assert.ok(ipv6Filter)
  ipv6Filter.listeners.click?.()
  await flush()

  const ipv6Cidrs = []
  walk(root, n => { if (n.tag === 'code') ipv6Cidrs.push(textOf(n)) })
  assert.equal(ipv6Cidrs.length, 7)

  const singleCopyBtn = (() => {
    const btns = []
    walk(root, n => { if (n.tag === 'button' && String(n.props.class || '').includes('cf-ips-copy-btn')) btns.push(n) })
    return btns[0]
  })()
  await singleCopyBtn.listeners.click?.()
  assert.equal(copiedValues[0], ipv6Cidrs[0])

  const copyNginxBtn = buttons.find(b => textOf(b).includes('copyNginx'))
  assert.ok(copyNginxBtn)
  await copyNginxBtn.listeners.click?.()
  assert.ok(copiedValues[1].includes('set_real_ip_from 2400:cb00::/32;'))
  assert.ok(copiedValues[1].includes('real_ip_header CF-Connecting-IP;'))

  const copyAllBtn = buttons.find(b => textOf(b).includes('copyAll'))
  await copyAllBtn.listeners.click?.()
  assert.equal(copiedValues[2].split('\n').length, 7)

  app.unmount()
})
