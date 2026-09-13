<script setup lang="ts">
import {
  computed,
  defineAsyncComponent,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { isCancel } from 'axios'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { useShellStore } from '@/stores/shell'
import { usePageMotion } from '@/composables/usePageMotion'
import {
  tenantError,
  tenantGet,
  tenantPost,
  type TenantRow,
} from '@/api/tenant'
import './tenants.scss'

const TenantIdentityDialogs = defineAsyncComponent(
  () => import('./components/TenantIdentityDialogs.vue'),
)
const TenantResourceDialogs = defineAsyncComponent(
  () => import('./components/TenantResourceDialogs.vue'),
)
const TenantOperationDialogs = defineAsyncComponent(
  () => import('./components/TenantOperationDialogs.vue'),
)
const TenantUpdateDialog = defineAsyncComponent(
  () => import('./components/TenantUpdateDialog.vue'),
)
const { t, locale } = useI18n()
const numberFormat = computed(() => new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN'))
const shell = useShellStore()
const route = useRoute()
const router = useRouter()
const root = ref<HTMLElement | null>(null)
const searchInput = ref<HTMLInputElement | null>(null)
const tableScroll = ref<HTMLElement | null>(null)
const { revealRows } = usePageMotion(root)
function readPage(value: unknown) {
  return Math.max(0, Math.floor(Number(value) || 0))
}
function readSize(value: unknown) {
  return [10, 20, 50, 100].includes(Number(value)) ? Number(value) : 10
}
const keyword = ref(String(route.query.keyword || ''))
const submittedKeyword = ref(keyword.value.trim())
const page = ref(readPage(route.query.page))
const size = ref(readSize(route.query.size))
const rows = ref<TenantRow[]>([])
const total = ref(0)
const loading = ref(false)
const loaded = ref(false)
const error = ref('')
const errorKey = ref('')
const errorMessage = computed(() => errorKey.value ? t(errorKey.value) : error.value)
const updatedAt = ref<Date | null>(null)
const updatedTime = computed(() => updatedAt.value?.toLocaleTimeString(locale.value === 'en' ? 'en-US' : 'zh-CN', { hour: '2-digit', minute: '2-digit' }) || '')
const showAllNames = ref(false)
const revealedNames = ref(new Set<string>())
const busyRow = ref('')
const highlightedRow = ref('')
const selected = ref<TenantRow | null>(null)
const action = ref('')
const editingValue = ref('')
const editError = ref('')
const saving = ref(false)
const editorInput = ref<{ focus: () => void; select: () => void } | null>(null)
let requestId = 0
let controller: AbortController | undefined
let searchTimer: ReturnType<typeof setTimeout> | undefined
let highlightTimer: ReturnType<typeof setTimeout> | undefined
let restoreFocus: HTMLElement | null = null
let disposed = false
const isOci = computed(() => shell.cloudType === 1)
const pages = computed(() => Math.max(1, Math.ceil(total.value / size.value)))
const rangeStart = computed(() =>
  rows.value.length ? page.value * size.value + 1 : 0,
)
const rangeEnd = computed(() =>
  Math.min(total.value, page.value * size.value + rows.value.length),
)
const identityAction = computed(() =>
  ['users', 'email', 'social'].includes(action.value),
)
const resourceAction = computed(() =>
  ['detail', 'quota', 'audit'].includes(action.value),
)
const operationAction = computed(() =>
  ['proxy', 'traffic', 'import', 'export', 'batchCheck'].includes(action.value),
)
const editOpen = computed(() => ['name', 'cost'].includes(action.value))
function isActive(row: TenantRow) {
  return row.active !== false && row.isActive !== false
}
function isMultiRegion(row: TenantRow) {
  if (Array.isArray(row.children))
    return (
      row.children.length > 1 ||
      (row.children.length === 1 && row.children[0].region !== row.region)
    )
  return row.hasChildren === true
}
function nameVisible(row: TenantRow) {
  return showAllNames.value !== revealedNames.value.has(row.id)
}
function maskName(name = '') {
  return name.length > 2
    ? `${name[0]}***${name.at(-1)}`
    : name
      ? '***'
      : t('tenant.common.unnamed')
}
function toggleName(row: TenantRow) {
  const values = new Set(revealedNames.value)
  if (values.has(row.id)) values.delete(row.id)
  else values.add(row.id)
  revealedNames.value = values
}
function toggleNames() {
  showAllNames.value = !showAllNames.value
  revealedNames.value = new Set()
}
function createdAt(row: TenantRow) {
  const raw = row.createdAtStr || row.createdAt
  if (!raw) return t('tenant.common.unrecorded')
  const date = Array.isArray(raw)
    ? new Date(Number(raw[0]), Number(raw[1]) - 1, Number(raw[2]))
    : new Date(String(raw).replace(' ', 'T'))
  if (Number.isNaN(date.getTime())) return String(raw)
  const options: Intl.DateTimeFormatOptions = { year: 'numeric', month: '2-digit', day: '2-digit' }
  if (!Array.isArray(raw) && /[T ]\d{2}:\d{2}/.test(String(raw))) {
    options.hour = '2-digit'
    options.minute = '2-digit'
  }
  return date.toLocaleString(locale.value === 'en' ? 'en-US' : 'zh-CN', options)
}
function accountType(row: TenantRow) {
  const labels: Record<string, string> = {
    PERSONAL: 'personal', CORPORATE: 'corporate', CORPORATE_SUBMITTED: 'corporateSubmitted',
    FREE_TIER: 'freeTier', PAYG: 'payg', UNKNOWN_ENUM_VALUE: 'unknown',
  }
  const detail = row.registerDetail
  const values = [detail?.accountType, detail?.planType]
    .map((value) => typeof value === 'object' && value ? value.value ?? value.code : value)
    .filter((value) => value)
  if (values.length) return values.map((value) => {
    const key = labels[String(value).toUpperCase()]
    return key ? t(`tenant.account.${key}`) : String(value)
  }).join(' · ')
  // Older responses expose only the enum's Chinese display name.
  const legacy: Record<string, string> = {
    '个人': 'personal', '公司': 'corporate', '正在审核中的企业': 'corporateSubmitted',
    '免费账号': 'freeTier', '升级账号': 'payg',
  }
  const raw = String(row.accountTypeName || '')
  if (raw === '未知' || raw === '未知类型') return t('tenant.account.unknown')
  if (raw === '多区域账号') return t('tenant.account.multiRegion')
  if (raw) {
    for (const account of ['', '个人', '公司', '正在审核中的企业']) {
      for (const plan of ['', '免费账号', '升级账号']) {
        if (account + plan === raw) return [account, plan].filter(Boolean).map((label) => t(`tenant.account.${legacy[label]}`)).join(' · ')
      }
    }
    return raw
  }
  return t(row.hasChildren ? 'tenant.account.multiRegion' : 'tenant.account.unknown')
}
function proxyLabel(row: TenantRow) {
  return row.proxyForce
    ? t('tenant.proxy.forced')
    : row.proxyBound
      ? t('tenant.proxy.bound')
      : t('tenant.proxy.configure')
}
async function syncUrl() {
  await router.replace({
    path: '/tenants/list',
    query: {
      ...route.query,
      cloudType: String(shell.cloudType),
      page: String(page.value),
      size: String(size.value),
      keyword: submittedKeyword.value || undefined,
    },
  })
}
async function load(resetScroll = false) {
  const id = ++requestId
  controller?.abort()
  controller = new AbortController()
  loading.value = true
  error.value = ''
  errorKey.value = ''
  try {
    const result = await tenantGet<{
      content: Record<string, any>[]
      totalElements: number
    }>(
      '/tenants/list/json',
      {
        cloudType: shell.cloudType,
        page: page.value,
        size: size.value,
        keyword: submittedKeyword.value || undefined,
      },
      { signal: controller.signal },
    )
    if (id !== requestId || disposed) return
    if (!Array.isArray(result?.content)) {
      errorKey.value = 'tenant.list.loadFailed'
      return
    }
    total.value = Number(result.totalElements || 0)
    if (page.value >= pages.value) {
      page.value = pages.value - 1
      await syncUrl()
      void load(resetScroll)
      return
    }
    rows.value = result.content.map((row) => ({
      ...row,
      id: String(row.idStr ?? row.id),
    }))
    loaded.value = true
    updatedAt.value = new Date()
    await nextTick()
    if (resetScroll && tableScroll.value) tableScroll.value.scrollTop = 0
    revealRows()
  } catch (cause) {
    if (id === requestId && !disposed && !isCancel(cause))
      error.value = tenantError(cause)
  } finally {
    if (id === requestId && !disposed) loading.value = false
  }
}
async function search() {
  clearTimeout(searchTimer)
  submittedKeyword.value = keyword.value.trim()
  page.value = 0
  await syncUrl()
  void load(true)
}
function queueSearch(event: Event) {
  if ((event as InputEvent).isComposing) return
  clearTimeout(searchTimer)
  searchTimer = setTimeout(() => void search(), 320)
}
function clearSearch() {
  keyword.value = ''
  void search()
  searchInput.value?.focus()
}
async function changePage(nextPage: number) {
  if (nextPage < 1 || nextPage > pages.value) return
  clearTimeout(searchTimer)
  page.value = nextPage - 1
  await syncUrl()
  void load(true)
}
async function changeSize(nextSize: number) {
  size.value = nextSize
  page.value = 0
  await syncUrl()
  void load(true)
}
function navigate(path: string, row?: TenantRow) {
  void router.push({
    path,
    query: {
      cloudType: String(shell.cloudType),
      ...(row ? { tenantId: row.id } : {}),
    },
  })
}
function openAction(nextAction: string, row: TenantRow | null = null) {
  restoreFocus =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null
  selected.value = row
  editingValue.value = String(
    (nextAction === 'name' ? row?.defName : row?.accountCost) ?? '',
  )
  editError.value = ''
  action.value = nextAction
}
function closeAction() {
  action.value = ''
  selected.value = null
  void nextTick(() => {
    if (restoreFocus?.isConnected) restoreFocus.focus({ preventScroll: true })
  })
}
function focusEditor() {
  editorInput.value?.focus()
  editorInput.value?.select()
}
function highlight(id: string) {
  clearTimeout(highlightTimer)
  highlightedRow.value = id
  highlightTimer = setTimeout(() => {
    highlightedRow.value = ''
  }, 1600)
}
async function saveEdit() {
  if (!selected.value || saving.value) return
  const row = selected.value
  const kind = action.value
  const value = editingValue.value.trim()
  saving.value = true
  editError.value = ''
  try {
    await tenantPost(
      kind === 'name'
        ? '/tenants/updateCustomName'
        : '/tenants/updateAccountCost',
      {
        tenantId: row.id,
        ...(kind === 'name' ? { defName: value } : { accountCost: value }),
      },
    )
    if (disposed) return
    const existing = rows.value.find((item) => item.id === row.id)
    if (existing) existing[kind === 'name' ? 'defName' : 'accountCost'] = value
    closeAction()
    highlight(row.id)
    ElMessage.success(t('tenant.common.saved'))
  } catch (cause) {
    editError.value = tenantError(cause)
  } finally {
    saving.value = false
  }
}
interface RowAction {
  id: string
  label: string
  icon: string
  path?: string
  danger?: boolean
}
function rowActions(row: TenantRow): RowAction[] {
  const items: RowAction[] = []
  if (
    Number(row.cloudType ?? shell.cloudType) === 1 &&
    Number(row.transferStatus || 0) !== 1
  ) {
    if (Number(row.supportAI) === 1)
      items.push({
        id: 'chat',
        label: t('tenant.actions.chat'),
        icon: 'i-mdi-brain',
        path: '/ai/chat',
      })
    items.push(
      {
        id: 'boot',
        label: t('tenant.actions.boot'),
        icon: 'i-mdi-plus-circle-outline',
        path: '/tenants/bootPage',
      },
      { id: 'update', label: t('tenant.actions.update'), icon: 'i-mdi-refresh' },
      {
        id: 'regions',
        label: t('tenant.actions.regions'),
        icon: 'i-mdi-information-outline',
        path: '/tenants/regionList',
      },
      {
        id: 'subscribe',
        label: t('tenant.actions.subscribe'),
        icon: 'i-mdi-earth',
        path: '/tenants/regionSubList',
      },
      { id: 'users', label: t('tenant.actions.users'), icon: 'i-mdi-account-group-outline' },
      { id: 'traffic', label: t('tenant.actions.traffic'), icon: 'i-mdi-bell-outline' },
      {
        id: 'monitor',
        label: t('tenant.actions.monitor'),
        icon: 'i-mdi-chart-line',
        path: '/monitor/homePage',
      },
      { id: 'audit', label: t('tenant.actions.audit'), icon: 'i-mdi-text-box-search-outline' },
      {
        id: 'costs',
        label: t('tenant.actions.costs'),
        icon: 'i-mdi-wallet-outline',
        path: '/cost/costPage',
      },
      { id: 'export', label: t('tenant.actions.export'), icon: 'i-mdi-tray-arrow-down' },
      { id: 'email', label: t('tenant.actions.email'), icon: 'i-mdi-email-outline' },
      { id: 'social', label: t('tenant.actions.social'), icon: 'i-mdi-share-variant-outline' },
      { id: 'quota', label: t('tenant.actions.quota'), icon: 'i-mdi-chart-box-outline' },
    )
  } else if (Number(row.cloudType ?? shell.cloudType) === 2) {
    items.push({
      id: 'regions',
      label: t('tenant.actions.accountDetails'),
      icon: 'i-mdi-information-outline',
      path: '/tenants/regionList',
    })
  }
  items.push({
    id: 'delete',
    label: t('tenant.actions.delete'),
    icon: 'i-mdi-trash-can-outline',
    danger: true,
  })
  return items
}
function runAction(item: RowAction, row: TenantRow) {
  if (item.path) navigate(item.path, row)
  else if (item.id === 'delete') void removeRow(row)
  else openAction(item.id, row)
}
async function removeRow(row: TenantRow) {
  if (busyRow.value) return
  busyRow.value = row.id
  try {
    await ElMessageBox.confirm(
      t('tenant.delete.description'),
      t('tenant.actions.delete'),
      {
        confirmButtonText: t('tenant.actions.delete'),
        cancelButtonText: t('tenant.delete.keep'),
        type: 'warning',
        confirmButtonClass: 'tenant-delete-confirm',
      },
    )
    if (disposed) return
    await tenantGet('/tenants/deleteApi', { tenantId: row.id })
    ElMessage.success(t('tenant.delete.success'))
    await load()
  } catch (cause) {
    if (cause !== 'cancel' && cause !== 'close')
      ElMessage.error(tenantError(cause))
  } finally {
    busyRow.value = ''
  }
}
function handleShortcut(event: KeyboardEvent) {
  const target = event.target as HTMLElement
  if (
    event.key !== '/' ||
    event.ctrlKey ||
    event.metaKey ||
    event.altKey ||
    action.value ||
    target.closest(
      'input, textarea, select, [contenteditable="true"], [role="dialog"]',
    )
  )
    return
  event.preventDefault()
  searchInput.value?.focus()
}
watch(
  () => shell.cloudType,
  async () => {
    closeAction()
    clearTimeout(searchTimer)
    page.value = 0
    rows.value = []
    total.value = 0
    loaded.value = false
    await syncUrl()
    void load(true)
  },
)
watch(
  () => [
    route.query.page,
    route.query.size,
    route.query.keyword,
    route.query.cloudType,
  ],
  () => {
    if (route.path !== '/tenants/list') return
    const cloud = Number(route.query.cloudType)
    if ([1, 2, 3, 4].includes(cloud) && cloud !== shell.cloudType) {
      shell.setCloud(cloud)
      return
    }
    const nextPage = readPage(route.query.page),
      nextSize = readSize(route.query.size),
      nextKeyword = String(route.query.keyword || '')
    if (
      nextPage === page.value &&
      nextSize === size.value &&
      nextKeyword === submittedKeyword.value
    )
      return
    page.value = nextPage
    size.value = nextSize
    keyword.value = nextKeyword
    submittedKeyword.value = nextKeyword
    void load(true)
  },
)
onMounted(() => {
  const cloud = Number(route.query.cloudType)
  if ([1, 2, 3, 4].includes(cloud) && cloud !== shell.cloudType)
    shell.setCloud(cloud)
  else void load()
  document.addEventListener('keydown', handleShortcut)
})
onBeforeUnmount(() => {
  disposed = true
  requestId++
  controller?.abort()
  clearTimeout(searchTimer)
  clearTimeout(highlightTimer)
  document.removeEventListener('keydown', handleShortcut)
})
</script>

<template>
  <div ref="root" class="tenants-page">
    <section
      class="tenant-card"
      data-motion-enter
      :aria-label="t('tenant.list.label')"
      :aria-busy="loading"
    >
      <div class="list-toolbar">
        <form class="tenant-search" role="search" @submit.prevent="search">
          <i class="i-mdi-magnify" aria-hidden="true" /><input
            ref="searchInput"
            v-model="keyword"
            :aria-label="t('tenant.list.searchLabel')"
            :placeholder="t('tenant.list.searchPlaceholder')"
            autocomplete="off"
            @input="queueSearch"
            @compositionend="queueSearch"
            @keydown.esc.prevent="clearSearch"
          /><button
            v-if="keyword"
            type="button"
            :aria-label="t('tenant.list.clearSearch')"
            @click="clearSearch"
          >
            <i class="i-mdi-close-circle" /></button
          ><kbd v-else aria-hidden="true">/</kbd>
        </form>
        <div class="toolbar-actions">
          <button
            class="toolbar-button privacy-toggle"
            :aria-pressed="showAllNames"
            :aria-label="showAllNames ? t('tenant.list.hideNames') : t('tenant.list.showNames')"
            :title="showAllNames ? t('tenant.list.hideNames') : t('tenant.list.showNames')"
            @click="toggleNames"
          >
            <i
              :class="
                showAllNames ? 'i-mdi-eye-outline' : 'i-mdi-eye-off-outline'
              "
              aria-hidden="true"
            />
          </button>
          <button
            class="toolbar-button"
            :aria-label="t('tenant.list.refreshLabel')"
            :title="updatedAt ? t('tenant.list.refreshedAt', { time: updatedTime }) : t('tenant.common.refresh')"
            :disabled="loading"
            @click="load()"
          >
            <i class="i-mdi-refresh" :class="{ 'is-spinning': loading }" aria-hidden="true" />
          </button>
          <el-dropdown
            v-if="isOci"
            trigger="click"
            popper-class="tenant-tools-menu"
            @command="(command: string) => openAction(command)"
            ><button class="toolbar-button" :aria-label="t('tenant.list.moreLabel')" :title="t('tenant.list.more')">
              <i class="i-mdi-dots-horizontal" aria-hidden="true" /></button
            ><template #dropdown
              ><el-dropdown-menu
                ><el-dropdown-item command="import"
                  ><i class="i-mdi-tray-arrow-up" />{{ t('tenant.list.import') }}</el-dropdown-item
                ><el-dropdown-item command="export"
                  ><i class="i-mdi-tray-arrow-down" />{{ t('tenant.list.exportAll') }}</el-dropdown-item
                ><el-dropdown-item command="batchCheck" divided
                  ><i
                    class="i-mdi-shield-check-outline"
                  />{{ t('tenant.list.batchCheck') }}</el-dropdown-item
                ></el-dropdown-menu
              ></template
            ></el-dropdown
          >
          <PrimaryBtn class="tenant-import" @click="navigate('/tenants/addSpeed')"
            ><i class="i-mdi-plus" aria-hidden="true" />{{ t('tenant.list.apiImport') }}</PrimaryBtn
          >
        </div>
      </div>
      <div v-if="submittedKeyword" class="search-context">
        {{ t('tenant.list.searchResults', { keyword: submittedKeyword }) }}
        <button @click="clearSearch">{{ t('tenant.list.clearFilter') }}<i class="i-mdi-close" /></button>
      </div>
      <div v-if="errorMessage" class="list-error" role="alert">
        <i class="i-mdi-alert-circle-outline" />
        <div>
          <strong>{{ t('tenant.list.refreshFailed') }}</strong>
          <p>{{ errorMessage }}</p>
        </div>
        <GhostBtn @click="load()">{{ t('tenant.common.retry') }}</GhostBtn>
      </div>
      <div class="table-stage" :class="{ 'is-refreshing': loading && loaded }">
        <div v-if="loading && loaded" class="refresh-track" aria-hidden="true">
          <span />
        </div>
        <div
          ref="tableScroll"
          class="table-scroll"
          tabindex="0"
          :aria-label="t('tenant.list.tableLabel')"
        >
          <table class="tenant-table">
            <thead>
              <tr>
                <th scope="col" class="identity-column">{{ t('tenant.list.columns.tenant') }}</th>
                <th scope="col">{{ t('tenant.list.columns.cost') }}</th>
                <th scope="col">{{ t('tenant.list.columns.region') }}</th>
                <th scope="col">{{ t('tenant.list.columns.boot') }}</th>
                <th scope="col">{{ t('tenant.list.columns.type') }}</th>
                <th scope="col">{{ t('tenant.list.columns.created') }}</th>
                <th scope="col">{{ t('tenant.list.columns.status') }}</th>
                <th scope="col" class="row-actions-column">{{ t('tenant.list.columns.actions') }}</th>
              </tr>
            </thead>
            <tbody v-if="!loaded && loading" aria-hidden="true">
              <tr v-for="n in 6" :key="n" class="skeleton-row">
                <td v-for="c in 8" :key="c">
                  <span
                    class="skeleton"
                    :class="{ 'skeleton-name': c === 1 }"
                  />
                </td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr
                v-for="row in rows"
                :key="row.id"
                data-motion-row
                :data-tenant-id="row.id"
                :class="{ 'row-saved': highlightedRow === row.id }"
              >
                <td class="identity-column">
                  <div class="tenant-identity">
                    <button
                      class="proxy-button"
                      :class="{
                        'proxy-bound': row.proxyBound,
                        'proxy-force': row.proxyForce,
                      }"
                      :aria-label="proxyLabel(row)"
                      :title="proxyLabel(row)"
                      @click="openAction('proxy', row)"
                    >
                      <i
                        :class="
                          row.proxyBound || row.proxyForce
                            ? 'i-mdi-shield-check-outline'
                            : 'i-mdi-shield-outline'
                        "
                      />
                    </button>
                    <div class="identity-text">
                      <button
                        class="edit-name"
                        :title="row.defName || t('tenant.list.editName')"
                        :aria-label="t('tenant.list.editName')"
                        @click="openAction('name', row)"
                      >
                        {{ row.defName || t('tenant.list.addName')
                        }}<i class="i-mdi-pencil-outline" /></button
                      ><button
                        class="private-name"
                        :aria-label="
                          nameVisible(row) ? t('tenant.list.hideName') : t('tenant.list.showName')
                        "
                        :aria-pressed="nameVisible(row)"
                        @click="toggleName(row)"
                      >
                        <span>{{
                          nameVisible(row)
                            ? row.tenancyName || t('tenant.common.unnamed')
                            : maskName(row.tenancyName)
                        }}</span
                        ><i
                          :class="
                            nameVisible(row)
                              ? 'i-mdi-eye-outline'
                              : 'i-mdi-eye-off-outline'
                          "
                        />
                      </button>
                    </div>
                  </div>
                </td>
                <td>
                  <button
                    class="cell-link cost-link"
                    :aria-label="t('tenant.list.editCost')"
                    @click="openAction('cost', row)"
                  >
                    {{ row.accountCost || t('tenant.common.unset')
                    }}<i class="i-mdi-pencil-outline" /></button
                  ><small class="cell-secondary"
                    >{{ t('tenant.list.activeDays', { days: numberFormat.format(Number(row.activeDays) || 0) }, Number(row.activeDays) || 0) }}</small
                  >
                </td>
                <td>
                  <span class="region-name" :title="row.region">{{
                    row.region || t('tenant.common.unrecorded')
                  }}</span
                  ><small class="cell-secondary"
                    ><i class="i-mdi-earth" />{{
                      isMultiRegion(row) ? t('tenant.list.multiRegion') : t('tenant.list.singleRegion')
                    }}</small
                  >
                </td>
                <td>
                  <span
                    class="task-state"
                    :class="{ 'task-running': row.openBootFlag }"
                    ><span v-if="row.openBootFlag" class="live-dot" />{{
                      row.openBootFlag ? t('tenant.list.bootRunning') : t('tenant.list.noTask')
                    }}</span
                  >
                </td>
                <td>
                  <button
                    class="cell-link account-type"
                    @click="openAction('detail', row)"
                  >
                    {{
                      accountType(row)
                    }}<i class="i-mdi-chevron-right" />
                  </button>
                </td>
                <td>
                  <time class="created-at">{{ createdAt(row) }}</time>
                </td>
                <td>
                  <span
                    class="tenant-status"
                    :class="isActive(row) ? 'status-active' : 'status-inactive'"
                    ><span />{{ isActive(row) ? t('tenant.list.active') : t('tenant.list.inactive') }}</span
                  >
                </td>
                <td class="row-actions-column">
                  <div class="row-actions">
                    <button
                      v-if="Number(row.cloudType ?? shell.cloudType) === 1"
                      class="boot-button"
                      :aria-label="t('tenant.actions.boot')"
                      :title="t('tenant.actions.boot')"
                      @click="navigate('/tenants/bootPage', row)"
                    >
                      <i class="i-mdi-play-outline" /></button
                    ><el-dropdown
                      trigger="click"
                      placement="bottom-end"
                      popper-class="tenant-action-menu"
                      :show-timeout="0"
                      :hide-timeout="80"
                      @command="(item: RowAction) => runAction(item, row)"
                      ><button
                        class="more-button"
                        :disabled="busyRow === row.id"
                        :aria-label="t('tenant.list.actions')"
                        :title="t('tenant.list.actions')"
                      >
                        <i
                          :class="
                            busyRow === row.id
                              ? 'i-mdi-loading is-spinning'
                              : 'i-mdi-dots-horizontal'
                          "
                        /></button
                      ><template #dropdown
                        ><el-dropdown-menu
                          ><el-dropdown-item
                            v-for="item in rowActions(row)"
                            :key="item.id"
                            :command="item"
                            :class="{ 'danger-action': item.danger }"
                            ><i :class="item.icon" /><span>{{
                              item.label
                            }}</span></el-dropdown-item
                          ></el-dropdown-menu
                        ></template
                      ></el-dropdown
                    >
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
          <div
            v-if="!loading && !rows.length && !errorMessage"
            class="tenant-empty"
            role="status"
          >
            <span class="empty-icon"
              ><i
                :class="
                  submittedKeyword
                    ? 'i-mdi-magnify'
                    : 'i-mdi-account-group-outline'
                "
            /></span>
            <h3>
              {{
                submittedKeyword ? t('tenant.list.noMatches') : t('tenant.list.noTenants')
              }}
            </h3>
            <p>
              {{
                submittedKeyword
                  ? t('tenant.list.noMatchesHint')
                  : t('tenant.list.noTenantsHint')
              }}
            </p>
            <GhostBtn v-if="submittedKeyword" @click="clearSearch"
              >{{ t('tenant.list.viewAll') }}</GhostBtn
            >
          </div>
        </div>
      </div>
      <footer class="list-footer">
        <p aria-live="polite">
          {{
            loading && !loaded
              ? t('tenant.list.loading')
              : t('tenant.list.range', { start: numberFormat.format(rangeStart), end: numberFormat.format(rangeEnd), total: numberFormat.format(total) })
          }}
        </p>
        <el-pagination
          background
          :current-page="page + 1"
          :page-size="size"
          :total="total"
          :page-sizes="[10, 20, 50, 100]"
          :pager-count="5"
          layout="sizes, prev, pager, next"
          @current-change="changePage"
          @size-change="changeSize"
        />
      </footer>
    </section>
    <TenantIdentityDialogs
      v-if="identityAction"
      :tenant="selected"
      :action="action"
      @close="closeAction"
      @changed="load()"
    />
    <TenantResourceDialogs
      v-if="resourceAction"
      :tenant="selected"
      :action="action"
      @close="closeAction"
      @changed="load()"
    />
    <TenantOperationDialogs
      v-if="operationAction"
      :tenant="selected"
      :action="action"
      :cloud-type="shell.cloudType"
      @close="closeAction"
      @changed="load()"
    />
    <TenantUpdateDialog
      v-if="action === 'update' && selected"
      :tenant="selected"
      @close="closeAction"
      @changed="load()"
    />
    <el-dialog
      :model-value="editOpen"
      :title="action === 'name' ? t('tenant.edit.nameTitle') : t('tenant.edit.costTitle')"
      width="440px"
      class="tenant-edit-dialog"
      align-center
      :close-on-click-modal="!saving"
      :close-on-press-escape="!saving"
      :show-close="!saving"
      @close="closeAction"
      @opened="focusEditor"
      ><form @submit.prevent="saveEdit">
        <p class="edit-description">
          {{
            action === 'name'
              ? t('tenant.edit.nameHint')
              : t('tenant.edit.costHint')
          }}
        </p>
        <label class="edit-field-label" for="tenant-edit-value">{{
          action === 'name' ? t('tenant.edit.name') : t('tenant.edit.cost')
        }}</label
        ><el-input
          id="tenant-edit-value"
          ref="editorInput"
          v-model="editingValue"
          :maxlength="action === 'name' ? 100 : undefined"
          :show-word-limit="action === 'name'"
          :disabled="saving"
        />
        <p v-if="editError" class="field-error" role="alert">{{ editError }}</p>
      </form>
      <template #footer
        ><GhostBtn :disabled="saving" @click="closeAction">{{ t('tenant.common.cancel') }}</GhostBtn
        ><PrimaryBtn :loading="saving" @click="saveEdit">{{
          saving ? t('tenant.common.saving') : t('tenant.common.save')
        }}</PrimaryBtn></template
      ></el-dialog
    >
  </div>
</template>
