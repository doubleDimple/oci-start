<script setup lang="ts">
import { computed, getCurrentInstance, nextTick, onBeforeUnmount, onMounted, ref, shallowRef, type CSSProperties } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import {
  clearAllHeaderMessages, deleteHeaderMessage, deleteHeaderMessages, getHeaderMessage, getHeaderMessages,
  getHeaderUnreadCount, headerMessagesError, readAllHeaderMessages, type HeaderMessage,
} from '@/api/headerMessages'

type Action = 'all' | 'delete' | 'batchDelete' | 'clearAll'
interface ActionFailure { action: Action; businessId: string; businessIds?: string[]; error: unknown }

const emit = defineEmits<{ open: [] }>()
const { t, locale } = useI18n()
const panelId = `header-messages-${getCurrentInstance()?.uid ?? 'center'}`
const trigger = ref<HTMLButtonElement | null>(null)
const panel = ref<HTMLElement | null>(null)
const panelOpen = ref(false)
const panelStyle = ref<CSSProperties>({})
const unread = ref<number | null>(null)
const unreadError = shallowRef<unknown>(null)
const unreadLoading = ref(false)
const rows = shallowRef<HeaderMessage[]>([])
const loaded = ref(false)
const page = ref(1)
const requestedPage = ref(1)
const totalPages = ref(0)
const totalElements = ref(0)
const listLoading = ref(false)
const listError = shallowRef<unknown>(null)
const action = ref<Action | ''>('')
const actionId = ref('')
const actionError = shallowRef<ActionFailure | null>(null)
const notice = ref('')
const selectedIds = ref<string[]>([])
const clearConfirmOpen = ref(false)
const detailOpen = ref(false)
const detailId = ref('')
const detail = shallowRef<HeaderMessage | null>(null)
const detailReady = ref(false)
const detailLoading = ref(false)
const detailError = shallowRef<unknown>(null)
const busy = computed(() => Boolean(action.value))
const canMarkAll = computed(() => unread.value !== 0 || rows.value.some(row => row.readStatus === 0))
const selectedSet = computed(() => new Set(selectedIds.value))
const pageSelectedCount = computed(() => rows.value.filter(row => selectedSet.value.has(row.businessId)).length)
const allPageSelected = computed(() => rows.value.length > 0 && pageSelectedCount.value === rows.value.length)
const somePageSelected = computed(() => pageSelectedCount.value > 0 && !allPageSelected.value)
const numberFormat = computed(() => new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN'))
const dateFormat = computed(() => new Intl.DateTimeFormat(locale.value === 'en' ? 'en-US' : 'zh-CN', {
  year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
}))
const formatNumber = (value: number) => numberFormat.value.format(value)
const bellLabel = computed(() => {
  const label = unread.value === null ? t('headerMessages.title') : t('headerMessages.bellUnread', { count: formatNumber(unread.value) })
  return unreadError.value ? `${label}. ${t('headerMessages.unreadFailed')}` : label
})
let disposed = false
let unreadVersion = 0
let listVersion = 0
let detailVersion = 0
let unreadController: AbortController | undefined
let listController: AbortController | undefined
let detailController: AbortController | undefined
let actionController: AbortController | undefined

function subject(message: HeaderMessage): string { return message.subject || t('headerMessages.untitled') }
function status(message: HeaderMessage): string {
  return t(`headerMessages.${message.readStatus === 0 ? 'unread' : message.readStatus === 1 ? 'read' : 'unknownStatus'}`)
}
function messageType(message: HeaderMessage): string {
  if (message.messageType === 'INNER') return t('headerMessages.innerType')
  if (message.messageType === 'SYSTEM') return t('headerMessages.systemType')
  return message.messageType || t('headerMessages.messageType')
}
function messageTime(value: string): string {
  if (!value) return t('headerMessages.unknownTime')
  const parts = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?$/.exec(value)
  if (!parts) return value
  const year = Number(parts[1])
  const month = Number(parts[2])
  const day = Number(parts[3])
  const hour = Number(parts[4])
  const minute = Number(parts[5])
  const second = Number(parts[6] || 0)
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) return value
  // LocalDateTime has no offset. Build a local wall-clock date without adding a time zone.
  const date = new Date(0)
  date.setFullYear(year, month - 1, day)
  date.setHours(hour, minute, second, 0)
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day
    || date.getHours() !== hour || date.getMinutes() !== minute || date.getSeconds() !== second) return value
  return dateFormat.value.format(date)
}
function positionPanel() {
  if (!panelOpen.value || !trigger.value) return
  const bounds = trigger.value.getBoundingClientRect()
  const width = Math.min(392, Math.max(0, window.innerWidth - 24))
  const top = Math.max(12, Math.min(bounds.bottom + 10, window.innerHeight - 120))
  panelStyle.value = {
    left: `${Math.max(12, Math.min(bounds.right - width, window.innerWidth - width - 12))}px`,
    top: `${top}px`,
    maxHeight: `${Math.max(100, window.innerHeight - top - 12)}px`,
  }
}
function stopList() {
  listVersion += 1
  listController?.abort()
  listController = undefined
  listLoading.value = false
}
function stopUnread() {
  unreadVersion += 1
  unreadController?.abort()
  unreadController = undefined
  unreadLoading.value = false
}
function closePanel(restoreFocus = false) {
  if (!panelOpen.value) return
  if (panel.value) panel.value.inert = true
  panelOpen.value = false
  clearConfirmOpen.value = false
  stopList()
  if (restoreFocus) trigger.value?.focus()
}
async function togglePanel() {
  if (panelOpen.value) { closePanel(true); return }
  panelOpen.value = true
  emit('open')
  positionPanel()
  await nextTick()
  if (disposed || !panelOpen.value) return
  if (panel.value) panel.value.inert = false
  panel.value?.focus()
  void loadPage(1)
  void refreshUnread()
}
async function refreshUnread() {
  if (disposed || busy.value) return
  stopUnread()
  const version = unreadVersion
  const controller = new AbortController()
  unreadController = controller
  unreadLoading.value = true
  try {
    const result = await getHeaderUnreadCount(controller.signal)
    if (disposed || controller.signal.aborted || version !== unreadVersion) return
    unread.value = result
    unreadError.value = null
  } catch (error) {
    if (disposed || controller.signal.aborted || version !== unreadVersion) return
    unreadError.value = error
  } finally {
    if (!disposed && version === unreadVersion) unreadLoading.value = false
  }
}
async function loadPage(target: number) {
  if (disposed || !panelOpen.value || busy.value) return
  stopList()
  const version = listVersion
  const controller = new AbortController()
  listController = controller
  requestedPage.value = target
  listLoading.value = true
  listError.value = null
  try {
    const result = await getHeaderMessages(target, controller.signal)
    if (disposed || controller.signal.aborted || version !== listVersion) return
    const last = Math.max(1, result.totalPages)
    if (target > last) { await loadPage(last); return }
    rows.value = result.content
    totalPages.value = result.totalPages
    totalElements.value = result.totalElements
    page.value = result.pageNum
    loaded.value = true
  } catch (error) {
    if (disposed || controller.signal.aborted || version !== listVersion) return
    listError.value = error
  } finally {
    if (!disposed && version === listVersion) listLoading.value = false
  }
}
function refreshPanel() {
  if (listLoading.value || busy.value) return
  void loadPage(page.value)
  void refreshUnread()
}
function changePage(direction: number) {
  const target = page.value + direction
  if (busy.value || listLoading.value || target < 1 || target > totalPages.value) return
  void loadPage(target)
  void refreshUnread()
}
function selectPage(value: number) { changePage(value - page.value) }
function markCachedRead(businessId: string) {
  const previous = rows.value.find(row => row.businessId === businessId)
  rows.value = rows.value.map(row => row.businessId === businessId ? { ...row, readStatus: 1 as const } : row)
  if (previous?.readStatus === 0 && unread.value !== null) unread.value = Math.max(0, unread.value - 1)
}
function removeCachedMessage(businessId: string) {
  removeCachedMessages([businessId])
}
function removeCachedMessages(businessIds: string[]) {
  const removedIds = new Set(businessIds)
  if (!removedIds.size) return
  const removedUnread = rows.value.filter(row => removedIds.has(row.businessId) && row.readStatus === 0).length
  rows.value = rows.value.filter(row => !removedIds.has(row.businessId))
  selectedIds.value = selectedIds.value.filter(id => !removedIds.has(id))
  totalElements.value = Math.max(0, totalElements.value - removedIds.size)
  totalPages.value = Math.ceil(totalElements.value / 5)
  page.value = Math.min(page.value, Math.max(1, totalPages.value))
  if (removedUnread > 0 && unread.value !== null) unread.value = Math.max(0, unread.value - removedUnread)
}
function toggleSelect(businessId: string) {
  clearConfirmOpen.value = false
  if (selectedSet.value.has(businessId)) {
    selectedIds.value = selectedIds.value.filter(id => id !== businessId)
  } else {
    selectedIds.value = [...selectedIds.value, businessId]
  }
}
function toggleSelectAllPage() {
  clearConfirmOpen.value = false
  const pageIds = rows.value.map(row => row.businessId)
  if (!pageIds.length) return
  if (allPageSelected.value) {
    const pageSet = new Set(pageIds)
    selectedIds.value = selectedIds.value.filter(id => !pageSet.has(id))
  } else {
    const next = new Set(selectedIds.value)
    for (const id of pageIds) next.add(id)
    selectedIds.value = [...next]
  }
}
async function openDetail(message: HeaderMessage) {
  if (busy.value || listLoading.value) return
  closePanel()
  detailId.value = message.businessId
  detail.value = null
  detailReady.value = false
  detailError.value = null
  detailOpen.value = true
  await readDetail()
}
async function readDetail() {
  if (disposed || busy.value || !detailOpen.value || !detailId.value) return
  detailVersion += 1
  detailController?.abort()
  stopUnread()
  const version = detailVersion
  const businessId = detailId.value
  const controller = new AbortController()
  detailController = controller
  detailLoading.value = true
  detailError.value = null
  try {
    const result = await getHeaderMessage(businessId, controller.signal)
    if (disposed || controller.signal.aborted || version !== detailVersion) return
    detail.value = result
    detailReady.value = true
    if (result) markCachedRead(businessId)
    else removeCachedMessage(businessId)
  } catch (error) {
    if (disposed || controller.signal.aborted || version !== detailVersion) return
    detailError.value = error
  } finally {
    if (!disposed && version === detailVersion) {
      detailLoading.value = false
      void refreshUnread()
    }
  }
}
function detailClosing() {
  detailVersion += 1
  detailController?.abort()
  detailController = undefined
  detailLoading.value = false
  if (!disposed) void refreshUnread()
}
function detailClosed() {
  if (detailOpen.value) return
  detail.value = null
  detailId.value = ''
  detailReady.value = false
  detailError.value = null
  if (!disposed) trigger.value?.focus()
}
async function runAction(target: Action, businessId = '', batchIds?: string[]) {
  const targetIds = target === 'batchDelete' ? [...(batchIds ?? selectedIds.value)] : []
  if (disposed || busy.value || (target === 'delete' && !businessId) || (target === 'batchDelete' && !targetIds.length)) return
  clearConfirmOpen.value = false
  stopList()
  stopUnread()
  action.value = target
  actionId.value = businessId
  actionError.value = null
  notice.value = ''
  const controller = new AbortController()
  actionController = controller
  try {
    if (target === 'all') await readAllHeaderMessages(controller.signal)
    else if (target === 'delete') await deleteHeaderMessage(businessId, controller.signal)
    else if (target === 'batchDelete') await deleteHeaderMessages(targetIds, controller.signal)
    else await clearAllHeaderMessages(controller.signal)
    if (disposed || controller.signal.aborted) return
    if (target === 'all') {
      rows.value = rows.value.map(row => ({ ...row, readStatus: 1 as const }))
      if (detail.value) detail.value = { ...detail.value, readStatus: 1 }
      unread.value = 0
      notice.value = t('headerMessages.allReadDone')
      ElMessage.success(notice.value)
    } else if (target === 'delete') {
      removeCachedMessage(businessId)
      if (detailId.value === businessId) detailOpen.value = false
      notice.value = t('headerMessages.deleted')
      ElMessage.success(notice.value)
    } else if (target === 'batchDelete') {
      removeCachedMessages(targetIds)
      if (targetIds.includes(detailId.value)) detailOpen.value = false
      notice.value = t('headerMessages.batchDeleted', { count: formatNumber(targetIds.length) })
      ElMessage.success(notice.value)
    } else {
      rows.value = []
      selectedIds.value = []
      totalElements.value = 0
      totalPages.value = 0
      page.value = 1
      unread.value = 0
      detailOpen.value = false
      notice.value = t('headerMessages.clearedAll')
      ElMessage.success(notice.value)
    }
  } catch (error) {
    if (disposed || controller.signal.aborted) return
    actionError.value = { action: target, businessId, businessIds: targetIds.length ? targetIds : undefined, error }
  } finally {
    if (!disposed) {
      action.value = ''
      actionId.value = ''
      actionController = undefined
      void refreshUnread()
      if (panelOpen.value) void loadPage(Math.min(page.value, Math.max(1, totalPages.value)))
    }
  }
}
function retryAction() {
  const failure = actionError.value
  if (failure) void runAction(failure.action, failure.businessId, failure.businessIds)
}
function outsidePointer(event: PointerEvent) {
  const target = event.target
  if (target instanceof Element && target.closest('.header-message-error-popover')) return
  if (target instanceof Node && !trigger.value?.contains(target) && !panel.value?.contains(target)) closePanel()
}
function outsideFocus(event: FocusEvent) {
  const target = event.target
  if (target instanceof Element && target.closest('.header-message-error-popover')) return
  if (target instanceof Node && !trigger.value?.contains(target) && !panel.value?.contains(target)) closePanel()
}
function escapePanel(event: KeyboardEvent) {
  if (!panelOpen.value || event.key !== 'Escape') return
  const target = event.target
  if (target instanceof Element && target.closest('.header-message-error-popover')) return
  event.preventDefault()
  event.stopPropagation()
  closePanel(true)
}
onMounted(() => {
  // Match the legacy header: refresh on mount and interactions, without background polling.
  void refreshUnread()
  document.addEventListener('pointerdown', outsidePointer, true)
  document.addEventListener('focusin', outsideFocus)
  document.addEventListener('keydown', escapePanel, true)
  window.addEventListener('resize', positionPanel)
  window.addEventListener('scroll', positionPanel, true)
})
onBeforeUnmount(() => {
  disposed = true
  stopList()
  stopUnread()
  detailVersion += 1
  detailController?.abort()
  actionController?.abort()
  document.removeEventListener('pointerdown', outsidePointer, true)
  document.removeEventListener('focusin', outsideFocus)
  document.removeEventListener('keydown', escapePanel, true)
  window.removeEventListener('resize', positionPanel)
  window.removeEventListener('scroll', positionPanel, true)
})
defineExpose({ close: () => closePanel() })
</script>

<template>
  <span class="header-messages">
    <button ref="trigger" class="message-trigger" type="button" :title="bellLabel" :aria-label="bellLabel" aria-haspopup="dialog" :aria-expanded="panelOpen" :aria-controls="panelOpen ? panelId : undefined" @click="togglePanel">
      <i class="i-mdi-bell-outline" aria-hidden="true" />
      <span v-if="unread !== null && unread > 0" class="message-badge" aria-hidden="true">{{ unread > 99 ? '99+' : formatNumber(unread) }}</span>
      <span v-else-if="unreadError" class="count-warning" aria-hidden="true" />
    </button>
    <span class="sr-only" role="status">{{ notice }}</span>
  </span>

  <Teleport to="body">
    <Transition name="header-message-panel">
      <section v-if="panelOpen" :id="panelId" ref="panel" class="message-panel" :style="panelStyle" role="dialog" :aria-label="t('headerMessages.title')" tabindex="-1">
        <header class="message-panel-header" data-page-error-anchor>
          <div class="panel-heading"><strong>{{ t('headerMessages.title') }}</strong><span>{{ unread === null ? t('headerMessages.countUnavailable') : t('headerMessages.unreadCount', { count: formatNumber(unread) }) }}</span></div>
          <button class="message-text-button" type="button" :disabled="busy || !canMarkAll" @click="runAction('all')">{{ t(`headerMessages.${action === 'all' ? 'markingRead' : 'allRead'}`) }}</button>
          <button class="message-icon-button" type="button" :title="t('headerMessages.close')" :aria-label="t('headerMessages.close')" @click="closePanel(true)"><i class="i-mdi-close" aria-hidden="true" /></button>
        </header>

        <div v-if="rows.length > 0 || totalElements > 0" class="message-batch-bar">
          <template v-if="!clearConfirmOpen">
            <label class="batch-select-all">
              <input type="checkbox" :checked="allPageSelected" :indeterminate.prop="somePageSelected" :disabled="busy || listLoading || rows.length === 0" @change="toggleSelectAllPage" />
              <span>{{ t('headerMessages.selectAll') }}</span>
              <span v-if="selectedIds.length > 0" class="batch-selected-pill">{{ t('headerMessages.selectedCount', { count: formatNumber(selectedIds.length) }) }}</span>
            </label>
            <div class="batch-actions">
              <button class="message-danger-chip" type="button" :disabled="busy || listLoading || selectedIds.length === 0" @click="runAction('batchDelete')">
                <i :class="action === 'batchDelete' ? 'i-mdi-loading message-spin' : 'i-mdi-trash-can-outline'" aria-hidden="true" />
                <span>{{ t(action === 'batchDelete' ? 'headerMessages.batchDeleting' : 'headerMessages.batchDelete') }}</span>
              </button>
              <button class="message-clear-button" type="button" :disabled="busy || listLoading || totalElements === 0" @click="clearConfirmOpen = true">
                {{ t('headerMessages.clearAll') }}
              </button>
            </div>
          </template>
          <div v-else class="batch-confirm-row" role="alert">
            <span class="batch-confirm-text">{{ t('headerMessages.clearConfirm', { count: formatNumber(totalElements) }) }}</span>
            <div class="batch-confirm-actions">
              <button class="batch-confirm-cancel" type="button" :disabled="busy" @click="clearConfirmOpen = false">{{ t('headerMessages.cancel') }}</button>
              <button class="batch-confirm-submit" type="button" :disabled="busy" @click="runAction('clearAll')">{{ t(action === 'clearAll' ? 'headerMessages.clearingAll' : 'headerMessages.confirmClear') }}</button>
            </div>
          </div>
        </div>

        <div class="message-panel-scroll" :aria-busy="listLoading || busy || undefined">
          <PageErrorNotice v-if="unreadError" :title="t('headerMessages.unreadFailed')" popper-class="header-message-error-popover"><p>{{ headerMessagesError(unreadError) }}</p><button type="button" :disabled="unreadLoading || busy" @click="refreshUnread">{{ t('headerMessages.retry') }}</button></PageErrorNotice>
          <PageErrorNotice v-if="actionError" :title="t('headerMessages.actionFailed')" popper-class="header-message-error-popover"><p>{{ headerMessagesError(actionError.error) }}</p><button type="button" :disabled="busy" @click="retryAction">{{ t('headerMessages.retry') }}</button></PageErrorNotice>
          <PageErrorNotice v-if="listError" :title="t('headerMessages.listFailed')" popper-class="header-message-error-popover"><p>{{ headerMessagesError(listError) }}</p><button type="button" :disabled="listLoading || busy" @click="loadPage(requestedPage)">{{ t('headerMessages.retry') }}</button></PageErrorNotice>
          <div v-if="listLoading" class="message-loading" role="status"><i class="i-mdi-loading message-spin" aria-hidden="true" />{{ t(loaded ? 'headerMessages.refreshing' : 'headerMessages.loading') }}</div>
          <ul v-if="rows.length" class="message-list">
            <li v-for="message in rows" :key="message.businessId" :class="{ 'is-unread': message.readStatus === 0, 'is-selected': selectedSet.has(message.businessId) }">
              <label class="message-check">
                <input type="checkbox" :checked="selectedSet.has(message.businessId)" :aria-label="t('headerMessages.selectMessage', { subject: subject(message) })" :disabled="busy || listLoading" @change="toggleSelect(message.businessId)" />
              </label>
              <button class="message-open" type="button" :disabled="busy || listLoading" :aria-label="t('headerMessages.openMessage', { subject: subject(message), status: status(message) })" @click="openDetail(message)">
                <span class="message-read-dot" :class="{ 'is-unread': message.readStatus === 0 }" aria-hidden="true" />
                <span class="message-summary"><strong>{{ subject(message) }}</strong><span class="message-meta"><time :datetime="message.createTime || undefined">{{ messageTime(message.createTime) }}</time><span class="message-type">{{ messageType(message) }}</span></span></span>
              </button>
              <button class="message-icon-button message-delete" type="button" :disabled="busy || listLoading" :title="t('headerMessages.deleteMessage', { subject: subject(message) })" :aria-label="t('headerMessages.deleteMessage', { subject: subject(message) })" @click="runAction('delete', message.businessId)"><i :class="action === 'delete' && actionId === message.businessId ? 'i-mdi-loading message-spin' : 'i-mdi-trash-can-outline'" aria-hidden="true" /></button>
            </li>
          </ul>
          <div v-else-if="!listLoading && !listError" class="message-empty"><i class="i-mdi-bell-check-outline" aria-hidden="true" /><strong>{{ t('headerMessages.empty') }}</strong><p>{{ t('headerMessages.emptyHint') }}</p></div>
        </div>

        <footer class="message-panel-footer">
          <PagePagination :current-page="page" :page-size="5" :page-count="Math.max(1, totalPages)" :disabled="listLoading || busy" embedded @current-change="selectPage">
            <button class="message-icon-button" type="button" :disabled="listLoading || busy" :title="t('headerMessages.refresh')" :aria-label="t('headerMessages.refresh')" @click="refreshPanel"><i class="i-mdi-refresh" aria-hidden="true" /></button>
            <span>{{ t('headerMessages.total', { count: formatNumber(totalElements) }) }}</span>
          </PagePagination>
        </footer>
      </section>
    </Transition>
  </Teleport>

  <el-dialog v-model="detailOpen" :title="detail ? subject(detail) : t('headerMessages.detail')" width="min(640px, calc(100vw - 24px))" align-center append-to-body class="header-message-dialog" @close="detailClosing" @closed="detailClosed">
    <div class="message-detail" :aria-busy="detailLoading || busy || undefined">
      <div v-if="detailLoading" class="message-loading" role="status"><i class="i-mdi-loading message-spin" aria-hidden="true" />{{ t('headerMessages.detailLoading') }}</div>
      <PageErrorNotice v-if="detailError" :title="t('headerMessages.detailFailed')"><p>{{ headerMessagesError(detailError) }}</p><button type="button" :disabled="detailLoading || busy" @click="readDetail">{{ t('headerMessages.retry') }}</button></PageErrorNotice>
      <PageErrorNotice v-if="actionError && actionError.businessId === detailId" :title="t('headerMessages.actionFailed')"><p>{{ headerMessagesError(actionError.error) }}</p><button type="button" :disabled="busy" @click="retryAction">{{ t('headerMessages.retry') }}</button></PageErrorNotice>
      <template v-if="detail">
        <div class="detail-meta"><time :datetime="detail.createTime || undefined">{{ messageTime(detail.createTime) }}</time><span class="message-type">{{ messageType(detail) }}</span></div>
        <div class="message-body">{{ detail.content || t('headerMessages.noContent') }}</div>
      </template>
      <div v-else-if="detailReady && !detailLoading && !detailError" class="message-empty"><i class="i-mdi-email-off-outline" aria-hidden="true" /><strong>{{ t('headerMessages.notFound') }}</strong><p>{{ t('headerMessages.notFoundHint') }}</p></div>
    </div>
    <template #footer><div class="detail-actions"><GhostBtn v-if="detail" danger :loading="action === 'delete' && actionId === detail.businessId" :disabled="busy || detailLoading" @click="runAction('delete', detail.businessId)">{{ t(action === 'delete' ? 'headerMessages.deleting' : 'headerMessages.delete') }}</GhostBtn><GhostBtn @click="detailOpen = false">{{ t('headerMessages.close') }}</GhostBtn></div></template>
  </el-dialog>
</template>

<style scoped lang="scss">
.header-messages { display: inline-flex; position: relative; flex: none; }
.message-trigger { position: relative; display: inline-grid; place-items: center; width: 38px; height: 38px; padding: 0; border: 1px solid transparent; border-radius: var(--r-pill); background: var(--bg-card); box-shadow: var(--shadow-card); color: var(--text-secondary); cursor: pointer; transition: background-color 160ms ease, color 160ms ease; }
.message-trigger > i { font-size: 20px; }
.message-trigger:hover, .message-trigger[aria-expanded='true'] { color: var(--text-primary); background: var(--bg-hover); }
.message-badge { position: absolute; top: -3px; right: -5px; display: grid; place-items: center; min-width: 19px; height: 19px; padding: 0 4px; border: 2px solid var(--bg-card); border-radius: var(--r-pill); background: var(--status-danger); color: #fff; font: 600 var(--font-size-caption)/1 var(--sans); font-variant-numeric: tabular-nums; }
.count-warning { position: absolute; top: 3px; right: 3px; width: 6px; height: 6px; border-radius: 50%; background: var(--status-warn); }
.message-panel { position: fixed; z-index: 2200; display: flex; flex-direction: column; width: min(392px, calc(100vw - 24px)); overflow: hidden; border: 1px solid var(--border); border-radius: 16px; background: var(--bg-card); color: var(--text-primary); box-shadow: 0 16px 48px color-mix(in srgb, var(--text-primary) 14%, transparent), var(--shadow-card); font: var(--font-size-body)/1.5 var(--sans); outline: none; }
.message-panel-header { display: flex; align-items: center; flex-wrap: wrap; flex: none; gap: 9px; padding: 13px 12px 13px 16px; border-bottom: 1px solid var(--border); }
:global(.el-popover.header-message-error-popover) { z-index: 2210 !important; }
.panel-heading { display: flex; flex: 1; flex-direction: column; min-width: 0; gap: 2px; }
.panel-heading strong { font-size: var(--font-size-body); font-weight: 600; }
.panel-heading > span { color: var(--text-muted); font-size: var(--font-size-secondary); }
.message-text-button { flex: none; padding: 4px 0; border: 0; background: transparent; color: var(--brand); font: 500 var(--font-size-body)/1.5 var(--sans); cursor: pointer; }
.message-text-button:not(:disabled):hover { color: var(--brand-hover); text-decoration: underline; text-underline-offset: 3px; }
.message-batch-bar { display: flex; align-items: center; justify-content: space-between; flex: none; gap: 8px; min-height: 38px; padding: 6px 12px 6px 14px; border-bottom: 1px solid var(--border); background: color-mix(in srgb, var(--bg-search) 60%, var(--bg-card)); font-size: var(--font-size-secondary); }
.batch-select-all { display: inline-flex; align-items: center; gap: 6px; min-width: 0; min-height: 28px; color: var(--text-secondary); font-weight: 500; cursor: pointer; user-select: none; }
.batch-select-all input, .message-check input { width: 15px; height: 15px; margin: 0; accent-color: var(--brand); cursor: pointer; }
.batch-selected-pill { padding: 1px 6px; border-radius: 999px; background: color-mix(in srgb, var(--brand) 14%, var(--bg-card)); color: var(--brand); font-size: var(--font-size-caption); font-weight: 600; font-variant-numeric: tabular-nums; }
.batch-actions { display: inline-flex; align-items: center; gap: 6px; flex-shrink: 0; }
.message-danger-chip { display: inline-flex; align-items: center; gap: 4px; height: 26px; padding: 0 9px; border: 1px solid color-mix(in srgb, var(--status-danger) 30%, var(--border)); border-radius: 999px; background: var(--status-danger-bg); color: var(--status-danger); font: 500 var(--font-size-caption)/1 var(--sans); cursor: pointer; transition: background-color 150ms ease, border-color 150ms ease; }
.message-danger-chip > i { font-size: 14px; }
.message-danger-chip:not(:disabled):hover { border-color: var(--status-danger); background: color-mix(in srgb, var(--status-danger) 18%, var(--bg-card)); }
.message-clear-button { padding: 4px 4px; border: 0; background: transparent; color: var(--status-danger); font: 500 var(--font-size-caption)/1.2 var(--sans); cursor: pointer; }
.message-clear-button:not(:disabled):hover { text-decoration: underline; text-underline-offset: 3px; }
.batch-confirm-row { display: flex; align-items: center; justify-content: space-between; width: 100%; gap: 8px; }
.batch-confirm-text { color: var(--status-danger); font-size: var(--font-size-caption); font-weight: 600; overflow-wrap: anywhere; }
.batch-confirm-actions { display: inline-flex; align-items: center; gap: 6px; flex-shrink: 0; }
.batch-confirm-cancel, .batch-confirm-submit { height: 26px; padding: 0 10px; border-radius: 999px; font: 600 var(--font-size-caption)/1 var(--sans); cursor: pointer; }
.batch-confirm-cancel { border: 1px solid var(--border); background: var(--bg-card); color: var(--text-secondary); }
.batch-confirm-submit { border: 0; background: var(--status-danger); color: #fff; }
.message-check { display: inline-flex; align-items: center; justify-content: center; flex: none; width: 26px; height: 32px; cursor: pointer; }
.message-list > li.is-selected { background: color-mix(in srgb, var(--brand) 7%, var(--bg-card)); }
.message-icon-button { display: inline-grid; place-items: center; flex: none; width: 32px; height: 32px; padding: 0; border: 0; border-radius: 9px; background: transparent; color: var(--text-secondary); cursor: pointer; transition: background-color 160ms ease, color 160ms ease; }
.message-icon-button > i { font-size: 18px; }
.message-icon-button:not(:disabled):hover { background: var(--bg-hover); color: var(--text-primary); }
.message-delete:not(:disabled):hover { background: var(--status-danger-bg); color: var(--status-danger); }
button:disabled { cursor: default; opacity: .5; }
button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
.message-panel-scroll { min-height: 0; overflow: auto; overscroll-behavior: contain; scrollbar-width: thin; }
.message-list { margin: 0; padding: 0; list-style: none; }
.message-list > li { display: flex; align-items: center; gap: 2px; padding: 4px 10px 4px 4px; border-bottom: 1px solid color-mix(in srgb, var(--border) 65%, transparent); }
.message-list > li:last-child { border-bottom: 0; }
.message-list > li.is-unread { background: color-mix(in srgb, var(--brand) 4%, var(--bg-card)); }
.message-open { display: flex; align-items: flex-start; flex: 1; min-width: 0; gap: 8px; padding: 11px 8px; border: 0; border-radius: 9px; background: transparent; color: var(--text-primary); font: var(--font-size-body)/1.55 var(--sans); text-align: left; cursor: pointer; }
.message-open:not(:disabled):hover { background: var(--bg-hover); }
.message-read-dot { width: 6px; height: 6px; flex: none; margin-top: 8px; border-radius: 50%; background: transparent; }
.message-read-dot.is-unread { background: var(--brand); }
.message-summary { min-width: 0; flex: 1; }
.message-summary > strong { display: -webkit-box; overflow: hidden; -webkit-line-clamp: 2; -webkit-box-orient: vertical; font-weight: 500; overflow-wrap: anywhere; }
.is-unread .message-summary > strong { font-weight: 600; }
.message-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 8px; margin-top: 6px; color: var(--text-muted); font-size: var(--font-size-secondary); }
.message-type { display: inline-block; max-width: 100%; padding: 1px 6px; border-radius: 5px; background: var(--bg-search); color: var(--text-secondary); font-size: var(--font-size-caption); overflow-wrap: anywhere; }
.message-panel-footer { display: flex; align-items: center; justify-content: space-between; flex: none; gap: 8px; padding: 8px 10px; border-top: 1px solid var(--border); color: var(--text-muted); font-size: var(--font-size-secondary); font-variant-numeric: tabular-nums; }
.message-loading { display: flex; align-items: center; justify-content: center; gap: 8px; padding: 18px 16px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.message-loading > i { font-size: 18px; }
.message-empty { display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 32px 20px; text-align: center; color: var(--text-secondary); }
.message-empty > i { color: var(--text-muted); font-size: 30px; }
.message-empty strong { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 500; }
.message-empty p { max-width: 32ch; margin: 0; font-size: var(--font-size-secondary); line-height: 1.65; }
.message-detail { max-height: min(65vh, 650px); overflow: auto; overscroll-behavior: contain; color: var(--text-primary); font: var(--font-size-body)/1.75 var(--sans); }
:global(.header-message-dialog .el-dialog__title) { font-size: var(--font-size-dialog-title); overflow-wrap: anywhere; }
.detail-meta { display: flex; align-items: center; flex-wrap: wrap; gap: 8px 12px; margin-bottom: 18px; color: var(--text-muted); font-size: var(--font-size-secondary); }
.message-body { white-space: pre-wrap; overflow-wrap: anywhere; }
.detail-actions { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 8px; }
.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
.header-message-panel-enter-active, .header-message-panel-leave-active { transition: opacity 140ms ease, transform 140ms ease; transform-origin: top right; }
.header-message-panel-enter-from, .header-message-panel-leave-to { opacity: 0; transform: translateY(-5px) scale(.985); }
.header-message-panel-leave-active { pointer-events: none; }
.message-spin { animation: header-message-spin 1s linear infinite; }
@keyframes header-message-spin { to { transform: rotate(360deg); } }
@media (max-width: 480px) { .message-panel-header { gap: 7px; padding-left: 12px; } .message-meta { gap: 4px; } .message-detail { max-height: 60dvh; } }
@media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation: none !important; transition: none !important; } }
</style>
