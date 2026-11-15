import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'
import { compileScript, compileTemplate, parse } from 'vue/compiler-sfc'
import { createRenderer, defineComponent, h, nextTick, reactive, ref, watch } from 'vue'

const moduleUrl = source => {
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  })
  return `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
}

const vueUrl = import.meta.resolve('vue')
const sfcSource = await readFile(new URL('../src/views/instances/InstancesView.vue', import.meta.url), 'utf8')
const { descriptor } = parse(sfcSource, { filename: 'InstancesView.vue' })
const script = compileScript(descriptor, { id: 'instances-pagination-test' })

const setupSource = `import { h as __testH } from '${vueUrl}';\n` + script.content
  .replace(/import\s*\(\s*(['"])\.\/components\/[^'"]+\1\s*\)/g, 'Promise.resolve({ render() { return null } })')
  .replace(/import\s+(['"])[^'"]+\.scss\1;?/g, '')
  .replace(/import\s+([\s\S]*?)\s+from\s+(['"])([^'"]+)\2;?/g, (_statement, bindings, _quote, source) => {
    if (source === 'vue') return `import ${bindings} from '${vueUrl}'`
    if (source === '@/utils/tenantPermissions') return 'const allowsInstanceAction = () => true'
    if (source === '@/composables/useCompactViewport') return 'const useCompactViewport = () => ref(false)'
    if (source === '@/composables/usePageMotion') return 'const usePageMotion = () => ({ revealRows() {} })'
    if (source === 'vue-i18n') return "const useI18n = () => ({ t: (key, params) => params ? `${key}:${JSON.stringify(params)}` : key, locale: ref('zh') })"
    if (source === 'vue-router') return 'const useRoute = () => globalThis.instancesPaginationFixture.route; const useRouter = () => globalThis.instancesPaginationFixture.router'
    if (source === 'axios') return 'const isCancel = err => Boolean(err?.__CANCEL__)'
    if (source === 'element-plus') return 'const ElMessage = { success() {}, error() {}, warning() {} }'
    if (source === '@/api/instances') {
      return `
        const getInstances = (...args) => globalThis.instancesPaginationFixture.getInstances(...args)
        const getInstanceTenants = (...args) => globalThis.instancesPaginationFixture.getInstanceTenants(...args)
        const getInstanceRegions = () => Promise.resolve([])
        const getInstanceParent = () => Promise.resolve('')
        const instanceError = err => String(err?.message || err || '')
        const isInstanceTenantId = value => Boolean(value)
      `
    }
    if (source.endsWith('PagePagination.vue')) {
      return `const ${bindings.trim()} = { inheritAttrs: false, setup(_props, { attrs, slots }) { return () => __testH(globalThis.instancesPaginationFixture.PagePaginationStub, attrs, slots) } }`
    }
    if (source.endsWith('.vue')) return `const ${bindings.trim()} = { render() { return __testH('div', this.$slots.default?.()) } }`
    throw new Error(`Unexpected dependency: ${source}`)
  })

const template = compileTemplate({
  source: descriptor.template.content,
  filename: 'InstancesView.vue',
  id: 'instances-pagination-test',
  compilerOptions: { bindingMetadata: script.bindings, hoistStatic: false },
})
assert.deepEqual(template.errors, [])
const { default: InstancesView } = await import(moduleUrl(setupSource))
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
async function settle() {
  for (let i = 0; i < 6; i++) {
    await Promise.resolve()
    await nextTick()
  }
}

function createFixture(t, { initialQuery = { page: '0', size: '10' }, deferFetch = false } = {}) {
  const prevFixture = globalThis.instancesPaginationFixture
  const requests = []
  const routeTransitions = []
  const clampedEmissions = []
  const observedTotalsDuringFetch = []
  const deferred = []

  const route = reactive({ path: '/oci/list', query: { ...initialQuery } })
  const router = {
    async push(next) {
      routeTransitions.push({ method: 'push', page: next.query.page, size: next.query.size })
      route.query = { ...next.query }
    },
    async replace(next) {
      routeTransitions.push({ method: 'replace', page: next.query.page, size: next.query.size })
      route.query = { ...next.query }
    },
  }

  // Reproduces Element Plus ElPagination's internal pageCountBridge clamp watch:
  // whenever total drops such that currentPage > ceil(total / pageSize), ElPagination
  // emits 'current-change' even while disabled.
  let latestTriggerPageChange = null
  const PagePaginationStub = defineComponent({
    name: 'PagePagination',
    props: ['disabled', 'currentPage', 'pageSize', 'total', 'pageSizes'],
    emits: ['current-change', 'size-change'],
    setup(props, { emit, slots }) {
      watch(
        () => Math.max(1, Math.ceil((props.total || 0) / (props.pageSize || 10))),
        (pageCount) => {
          if ((props.currentPage || 1) > pageCount) {
            clampedEmissions.push({ clampedTo: pageCount, total: props.total, disabled: props.disabled })
            emit('current-change', pageCount)
          }
        },
        { immediate: true, flush: 'sync' },
      )
      latestTriggerPageChange = value => emit('current-change', value)
      return () => h('page-pagination', {
        disabled: props.disabled,
        currentPage: props.currentPage,
        pageSize: props.pageSize,
        total: props.total,
      }, slots.default?.())
    },
  })

  const state = {
    route,
    router,
    PagePaginationStub,
    requests,
    routeTransitions,
    clampedEmissions,
    observedTotalsDuringFetch,
    deferred,
    async getInstanceTenants() {
      return [{ id: '101', name: 'Demo Tenant', region: 'ap-tokyo-1' }]
    },
    getInstances(page, size, tenantId, signal) {
      requests.push({ page, size, tenantId })
      observedTotalsDuringFetch.push(vm?.total ?? null)
      const makeRows = p => Array.from({ length: p === 2 ? 5 : 10 }, (_, idx) => ({
        id: `ocid1.instance.p${p}.${idx}`,
        name: `instance-p${p}-${idx}`,
        region: 'ap-tokyo-1',
        shape: 'VM.Standard.A1.Flex',
        state: 'RUNNING',
        publicIp: '',
        ipv6Addresses: '',
        availabilityDomain: 'AD-1',
        createdAt: '2026-10-01 10:00:00',
        remark: '',
      }))
      const payload = { rows: makeRows(page), total: 25, totalPages: 3 }
      if (!deferFetch) return Promise.resolve(payload)
      return new Promise((resolve, reject) => {
        signal?.addEventListener('abort', () => reject({ __CANCEL__: true }))
        deferred.push({ page, resolve: () => resolve(payload) })
      })
    },
  }

  let vm = null
  globalThis.instancesPaginationFixture = state
  const container = node('root')
  const app = renderer.createApp({ ...InstancesView, render })
  for (const name of [...new Set([...descriptor.template.content.matchAll(/<(el-[\w-]+)/g)].map(m => m[1]))]) {
    app.component(name, { render() { return h('div', this.$slots.default?.()) } })
  }
  const instance = app.mount(container)
  vm = instance.$.setupState
  t.after(() => {
    app.unmount()
    globalThis.instancesPaginationFixture = prevFixture
  })

  return {
    state,
    vm,
    container,
    triggerPage: value => latestTriggerPageChange?.(value),
  }
}

test('clicking next page keeps total intact so ElPagination never clamps and snaps back to page 1', async t => {
  const { state, vm, container, triggerPage } = createFixture(t)
  await settle()

  assert.equal(state.requests.length, 1)
  assert.deepEqual(state.requests[0], { page: 0, size: 10, tenantId: '' })
  assert.equal(vm.total, 25)
  assert.equal(state.clampedEmissions.length, 0)

  triggerPage(2)
  await settle()

  assert.equal(state.clampedEmissions.length, 0, 'total should not reset to 0 during page turn')
  assert.deepEqual(
    state.routeTransitions.map(item => item.page),
    ['1'],
    'route should stay on page=1 (2nd page) without bouncing back to page=0',
  )
  assert.deepEqual(state.requests.map(r => r.page), [0, 1])
  assert.equal(vm.rows[0].id, 'ocid1.instance.p1.0')
  const pager = flatten(container).find(el => el.type === 'page-pagination')
  assert.equal(pager.props.currentPage, 2)
  assert.equal(pager.props.total, 25)
})

test('direct navigation to page 2 ignores ElPagination initial-load clamp back to page 1', async t => {
  const { state, vm, container } = createFixture(t, { initialQuery: { page: '1', size: '10' }, deferFetch: true })
  await nextTick()

  // On mount with initial total=0 and currentPage=2, ElPagination emits current-change(1) synchronously.
  assert.ok(state.clampedEmissions.length >= 1)
  assert.equal(state.routeTransitions.length, 0, 'changePage must ignore clamping while loading / unloaded')
  assert.equal(state.requests.length, 1)
  assert.equal(state.requests[0].page, 1)

  state.deferred.shift().resolve()
  await settle()

  assert.equal(state.routeTransitions.length, 0)
  assert.equal(state.requests.length, 1)
  assert.equal(vm.total, 25)
  assert.equal(vm.rows[0].id, 'ocid1.instance.p1.0')
  const pager = flatten(container).find(el => el.type === 'page-pagination')
  assert.equal(pager.props.currentPage, 2)
})
