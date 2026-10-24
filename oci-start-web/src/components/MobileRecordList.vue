<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, provide, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from './PageBackButton.vue'
import { isMobileRecordNavigation, mobileRecordBackMethod, mobileRecordBackQuery, mobileRecordCloseQuery, mobileRecordOpenQuery, mobileRecordSelection, mobileRecordsKey } from '@/composables/useMobileRecords'

const props = withDefaults(defineProps<{
  drilldown?: boolean
  listId?: string
  recordKeys?: Array<string | number>
  loading?: boolean
  /** Pass the visibility flag when an enclosing dialog keeps its body mounted. */
  active?: boolean
}>(), { drilldown: false, listId: '', loading: false, active: true })
const { t } = useI18n()
const route = useRoute()
const router = useRouter()
let mountedLocation = { path: route.path, hash: route.hash, query: { ...route.query } }
const root = ref<HTMLElement | null>(null)
const heading = ref<HTMLElement | null>(null)
const enabled = computed(() => props.drilldown && !!props.listId)
const selected = computed(() => enabled.value ? mobileRecordSelection(route.query, props.listId) : '')
const unavailable = computed(() => !!selected.value && !props.loading && props.recordKeys != null && !props.recordKeys.some(key => String(key) === selected.value))
let origin: HTMLElement | null = null
let positions: Array<{ element: HTMLElement; top: number; left: number }> = []
let disposed = false

function scrollContainers() {
  const elements: HTMLElement[] = []
  for (let element = root.value; element; element = element.parentElement) {
    const style = getComputedStyle(element)
    if (/(auto|scroll)/.test(`${style.overflowY} ${style.overflowX}`)) elements.push(element)
  }
  return elements
}
function open(key: string) {
  origin = document.activeElement instanceof HTMLElement ? document.activeElement : null
  const overlay = root.value?.closest('.el-dialog, .el-drawer')
  const peers = overlay ? Array.from(overlay.querySelectorAll<HTMLElement>('[data-mobile-record-list-id]'))
    .filter(element => element.closest('.el-dialog, .el-drawer') === overlay)
    .map(element => element.dataset.mobileRecordListId || '').filter(Boolean) : undefined
  const query = mobileRecordOpenQuery(route.query, props.listId, key, peers)
  void router.push({ path: route.path, query, hash: route.hash })
}
function back() {
  const query = mobileRecordBackQuery(route.query, props.listId)
  if (!query) return
  const location = { path: route.path, query, hash: route.hash }
  const method = mobileRecordBackMethod(route.fullPath, router.resolve(location).fullPath, window.history.state?.back)
  if (method === 'back') router.back()
  else if (method === 'replace') void router.replace(location)
}
function closeSelection() {
  if (root.value?.closest('.el-dialog, .el-drawer') && window.matchMedia('(max-width: 760px)').matches
    && isMobileRecordNavigation(route, mountedLocation)) {
    const query = mobileRecordCloseQuery(route.query, props.listId)
    if (query) void router.replace({ path: route.path, query, hash: route.hash })
  }
}
watch(() => props.active, (active, previous) => {
  if (active) mountedLocation = { path: route.path, hash: route.hash, query: { ...route.query } }
  else if (previous) closeSelection()
})
watch(selected, async (value, previous) => {
  if (value && !previous) positions = scrollContainers().map(element => ({ element, top: element.scrollTop, left: element.scrollLeft }))
  await nextTick()
  if (disposed) return
  if (value) {
    scrollContainers().forEach(element => { element.scrollTop = 0 })
    heading.value?.focus({ preventScroll: true })
  } else if (previous) {
    positions.forEach(({ element, top, left }) => { if (element.isConnected) element.scrollTo({ top, left }) })
    if (origin?.isConnected) origin.focus({ preventScroll: true })
    else Array.from(root.value?.querySelectorAll<HTMLButtonElement>('.mobile-record-summary') || []).find(button => button.dataset.recordKey === previous)?.focus({ preventScroll: true })
  }
})
provide(mobileRecordsKey, { enabled, selected, open })
onBeforeUnmount(() => {
  disposed = true
  // Closing a nested resource dialog returns to its parent record. A page
  // navigation or desktop resize keeps its own route lifecycle untouched.
  closeSelection()
})
</script>

<template>
  <div ref="root" class="mobile-record-list" :data-mobile-record-list-id="enabled ? listId : undefined" :class="{ 'is-drilldown': enabled, 'is-record-detail': !!selected }">
    <div v-if="selected" class="mobile-record-detail-toolbar">
      <PageBackButton @click="back" />
      <span ref="heading" tabindex="-1">{{ t('mobileRecords.details') }}</span>
    </div>
    <p v-if="unavailable" class="mobile-record-unavailable" role="status">{{ t('mobileRecords.unavailable') }}</p>
    <slot />
  </div>
</template>

<style scoped>
.mobile-record-list { display: grid; align-content: start; gap: 12px; min-width: 0; padding: 12px; }
.mobile-record-list.is-drilldown:not(.is-record-detail) { gap: 0; padding: 0; }
.mobile-record-list.is-drilldown:not(.is-record-detail) :deep(.mobile-record-entry + .mobile-record-entry) { border-top: 1px solid color-mix(in srgb, var(--border) 45%, transparent); }
.mobile-record-detail-toolbar { display: flex; align-items: center; gap: 12px; min-width: 0; }
.mobile-record-detail-toolbar > span { color: var(--text-primary); font: 600 var(--font-size-body)/1.5 var(--sans); }
.mobile-record-unavailable { margin: 0; padding: 16px 4px; color: var(--text-secondary); font: var(--font-size-body)/1.6 var(--sans); }
</style>
