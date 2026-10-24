<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PagePagination from '@/components/PagePagination.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { normalizeMemoInput, type MemoRecord, type MemoApiError } from '@/api/memos'
import MemoRichEditor from './memos/MemoRichEditor.vue'
import MemoContent from './memos/MemoContent.vue'
import { memoDocument, type MemoDocument } from './memos/memoContent'
import { useMemos } from './memos/useMemos'
import './memos/memos.scss'

type Screen = 'list' | 'read' | 'edit'
const { t, locale } = useI18n(), router = useRouter(), notes = useMemos()
const route = useRoute(), compact = useCompactViewport()
const { rows, loading, loaded, problem, lastUpdated, detail, detailLoading, detailProblem, detailExists, mutation,
  canMutate, contextLocked, requiresReview, reviewReady } = notes
const screen = ref<Screen>('list'), query = ref(typeof route.query.memoSearch === 'string' ? route.query.memoSearch : ''), page = ref(routePage()), pageSize = 10
function routePage() { const value = Number(route.query.memoPage); return Number.isSafeInteger(value) && value > 0 ? value : 1 }
const editorKey = ref(0), draft = reactive({ title: '', summary: '' }), document = ref<MemoDocument>({ html: '', text: '' })
const baseline = shallowRef<MemoRecord | null>(null), baselineDraft = ref(''), validation = ref('')
const showSavedVersion = ref(false)
const entryOpen = ref(false)
const titleInput = ref<HTMLInputElement>(), readHeading = ref<HTMLElement>(), scrollArea = ref<HTMLElement>(), searchInput = ref<HTMLInputElement>()
const deleteTarget = shallowRef<MemoRecord | null>(null), discardVisible = ref(false)
let discardAction: (() => void) | undefined, cancelNavigation: (() => void) | undefined
let disposed = false, navigationSequence = 0
function draftSnapshot() { return JSON.stringify({ ...draft, ...document.value }) }
const dirty = computed(() => screen.value === 'edit' && (entryOpen.value || draftSnapshot() !== baselineDraft.value))
const locked = computed(() => contextLocked.value || !!deleteTarget.value)
const editorDisabled = computed(() => locked.value || requiresReview.value)
const filtered = computed(() => {
  const term = query.value.trim().toLocaleLowerCase(locale.value)
  if (!term) return rows.value
  return rows.value.filter(row => [row.title, row.summary, row.content].some(value => value.toLocaleLowerCase(locale.value).includes(term)))
})
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / pageSize)))
const visibleRows = computed(() => filtered.value.slice((page.value - 1) * pageSize, page.value * pageSize))
const readOnlyReady = computed(() => !!detail.value && !detailLoading.value && !detailProblem.value && !!detail.value.revision)
const canSave = computed(() => canMutate.value && dirty.value && !entryOpen.value && !locked.value && (!baseline.value || !!baseline.value.revision))
const successLabel = computed(() => t(`memo.${mutation.value.kind === 'delete' ? 'deleted' : 'saved'}`))
const readTime = computed(() => lastUpdated.value ? t('memo.lastUpdated', { time: new Intl.DateTimeFormat(locale.value, {
  hour: '2-digit', minute: '2-digit', second: '2-digit',
}).format(lastUpdated.value) }) : t('memo.notLoaded'))
function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function dateLabel(value: string | null) {
  if (!value) return '—'
  // The API returns local server wall-clock values without an offset. Format the
  // components without converting them into the browser's time zone.
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/.exec(value)
  if (!match) return value
  const parts = match.slice(1).map(Number)
  const date = new Date(Date.UTC(parts[0]!, parts[1]! - 1, parts[2]!, parts[3]!, parts[4]!, parts[5]!))
  if (!Number.isFinite(date.getTime())) return value
  return new Intl.DateTimeFormat(locale.value, { year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', timeZone: 'UTC', hourCycle: 'h23' }).format(date)
}
function errorLabel(error: MemoApiError | null) { return error ? t(`memo.errors.${error.key}`) : '' }
function preview(row: MemoRecord) { return (row.summary || row.content).replace(/\s+/g, ' ').trim() }
function clearDraft() { draft.title = ''; draft.summary = ''; document.value = { html: '', text: '' }; baseline.value = null; baselineDraft.value = ''; validation.value = ''; showSavedVersion.value = false; entryOpen.value = false }
function requestDiscard(action: () => void, onCancel?: () => void) {
  if (discardVisible.value) { onCancel?.(); return }
  discardAction = action; cancelNavigation = onCancel; discardVisible.value = true
}
function cancelDiscard() {
  discardVisible.value = false; discardAction = undefined
  const cancel = cancelNavigation; cancelNavigation = undefined; cancel?.()
}
function acceptDiscard() {
  const action = discardAction; discardVisible.value = false; discardAction = undefined; cancelNavigation = undefined
  action?.()
}
function leaveEditor(action: () => void) { if (dirty.value) requestDiscard(action); else action() }
async function focusRead() { await nextTick(); if (!disposed) { if (scrollArea.value) scrollArea.value.scrollTop = 0; readHeading.value?.focus({ preventScroll: true }) } }
async function showList() {
  ++navigationSequence; notes.clearDetail(); clearDraft(); screen.value = 'list'
  await nextTick(); if (!disposed) searchInput.value?.focus({ preventScroll: true })
}
function back() {
  if (locked.value || requiresReview.value) return
  if (screen.value !== 'list') {
    leaveEditor(() => { void showList() }); return
  }
  if (window.history.state?.back) router.back(); else void router.push('/boot/dashboard')
}
async function readNote(id: string, then: 'read' | 'edit' | 'delete' = 'read') {
  if (locked.value || (then !== 'read' && !canMutate.value)) return
  const sequence = ++navigationSequence
  if (!requiresReview.value) notes.clearMutation()
  clearDraft(); screen.value = 'read'
  await notes.selectMemo(id)
  if (disposed || sequence !== navigationSequence) return
  await focusRead()
  if (!detail.value || detail.value.id !== id || detailProblem.value) return
  if (then === 'edit') enterEditor(detail.value)
  if (then === 'delete') prepareDelete()
}
function openRow(row: MemoRecord) { void readNote(row.id) }
function editRow(row: MemoRecord) { void readNote(row.id, 'edit') }
function deleteRow(row: MemoRecord) { void readNote(row.id, 'delete') }
function enterEditor(record: MemoRecord | null) {
  if (!canMutate.value || locked.value || (record && !record.revision)) return
  draft.title = record?.title || ''; draft.summary = record?.summary || ''
  document.value = memoDocument(record?.htmlContent, record?.content || '')
  baseline.value = record ? { ...record } : null
  baselineDraft.value = draftSnapshot(); validation.value = ''; showSavedVersion.value = false; entryOpen.value = false; ++editorKey.value; screen.value = 'edit'
  void nextTick(() => { if (!disposed) { if (scrollArea.value) scrollArea.value.scrollTop = 0; titleInput.value?.focus({ preventScroll: true }) } })
}
function create() { if (canMutate.value && !locked.value) { notes.clearMutation(); notes.clearDetail(); enterEditor(null) } }
function editCurrent() { if (readOnlyReady.value) enterEditor(detail.value) }
function updateDocument(value: MemoDocument) { document.value = value; validation.value = '' }
function entryChanged(value: boolean) { entryOpen.value = value }
function resetEditor() {
  if (editorDisabled.value) return
  const reset = () => { draft.title = ''; draft.summary = ''; document.value = { html: '', text: '' }; validation.value = ''; entryOpen.value = false; ++editorKey.value }
  // Clearing an existing draft is reversible only until the next edit, so make the loss explicit.
  if (entryOpen.value || draft.title || draft.summary || document.value.text || document.value.html) requestDiscard(reset)
}
async function refresh() {
  if (locked.value) return
  const sequence = ++navigationSequence
  if (screen.value === 'read') await notes.reloadDetail()
  await notes.refresh()
  if (disposed || sequence !== navigationSequence) return
}
function requestRefresh() {
  if (locked.value) return
  if (screen.value === 'edit') {
    leaveEditor(() => { screen.value = baseline.value ? 'read' : 'list'; clearDraft(); void refresh() })
  } else void refresh()
}
async function save() {
  if (!canSave.value) return
  validation.value = ''
  const input = { title: draft.title, summary: draft.summary, content: document.value.text, htmlContent: document.value.html }
  try { normalizeMemoInput(input) } catch (cause) { validation.value = (cause as MemoApiError).key || 'invalidInput'; return }
  await notes.save(input, baseline.value ?? undefined)
  if (disposed) return
  if (mutation.value.outcome === 'success') {
    clearDraft(); screen.value = 'read'; await focusRead()
  } else if (requiresReview.value || ['conflict', 'notFound'].includes(mutation.value.problem?.key || '')) {
    showSavedVersion.value = true
    if (!baseline.value) { query.value = draft.title; page.value = 1 }
  }
}
function prepareDelete() {
  if (!canMutate.value || locked.value || !readOnlyReady.value || !detail.value) return
  deleteTarget.value = { ...detail.value }
}
function cancelDelete() { if (!contextLocked.value) deleteTarget.value = null }
async function confirmDelete() {
  const target = deleteTarget.value
  if (!target || !canMutate.value) return
  await notes.remove(target)
  if (disposed) return
  deleteTarget.value = null
  if (mutation.value.outcome === 'success') { clearDraft(); screen.value = 'list'; notes.clearDetail() }
}
async function recheck() {
  if (locked.value) return
  // Preserve the unsaved text for manual comparison after an uncertain save.
  await notes.refresh()
  if (notes.reviewTargetId.value) await notes.selectMemo(notes.reviewTargetId.value)
}
function acknowledge() { if (reviewReady.value) notes.acknowledgeReview() }
function inspectSaved() {
  if (locked.value || !detail.value) return
  const open = () => { clearDraft(); screen.value = 'read'; void focusRead() }
  leaveEditor(open)
}
function keepAsNew() {
  if (!canMutate.value || locked.value || !baseline.value) return
  // Preserve the draft while deliberately changing the next action to a new note.
  baseline.value = null; baselineDraft.value = ''; showSavedVersion.value = false
  notes.clearDetail(); notes.clearMutation()
}
function keyboard(event: KeyboardEvent) {
  if (event.isComposing || event.defaultPrevented || deleteTarget.value || discardVisible.value) return
  if (screen.value === 'edit' && (event.ctrlKey || event.metaKey) && event.key === 'Enter') { event.preventDefault(); void save() }
  if (screen.value === 'edit' && event.key === 'Escape') { event.preventDefault(); back() }
}
function reviewKeyboard(event: KeyboardEvent) {
  event.stopPropagation()
  // Searching the read-back comparison must never submit the surrounding editor.
  if (!event.isComposing && event.key === 'Enter' && event.target instanceof HTMLInputElement) event.preventDefault()
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (dirty.value || contextLocked.value || requiresReview.value) { event.preventDefault(); event.returnValue = '' }
}
watch(query, () => { page.value = 1 }, { flush: 'sync' })
watch([totalPages, loaded], ([value, ready]) => { if (ready) page.value = Math.min(page.value, value) })
watch(() => [route.query.memoSearch, route.query.memoPage], () => {
  query.value = typeof route.query.memoSearch === 'string' ? route.query.memoSearch : ''
  page.value = routePage()
})
watch([query, page], () => {
  if (!compact.value) return
  const memoSearch = query.value || undefined, memoPage = page.value > 1 ? String(page.value) : undefined
  if (route.query.memoSearch === memoSearch && route.query.memoPage === memoPage) return
  void router.replace({ query: { ...route.query, memoSearch, memoPage, mobileRecord: undefined }, hash: route.hash })
}, { flush: 'post' })
watch(page, () => { if (screen.value === 'list' && scrollArea.value) scrollArea.value.scrollTop = 0 })
onBeforeRouteLeave(() => {
  if (locked.value || requiresReview.value) return false
  if (!dirty.value) return true
  return new Promise<boolean>(resolve => requestDiscard(() => resolve(true), () => resolve(false)))
})
onMounted(() => { window.addEventListener('beforeunload', beforeUnload); void notes.refresh() })
onBeforeUnmount(() => {
  disposed = true; ++navigationSequence; clearDraft(); deleteTarget.value = null; cancelNavigation?.()
  discardAction = undefined; cancelNavigation = undefined; window.removeEventListener('beforeunload', beforeUnload)
})
</script>

<template>
  <section class="memos-page" :aria-label="t('memo.title')" @keydown="keyboard">
    <header class="memos-toolbar">
      <PageBackButton :disabled="locked || requiresReview" @click="back" />
      <div v-if="screen === 'list'" class="memos-search"><i class="i-mdi-magnify" aria-hidden="true" /><input ref="searchInput" v-model="query" type="search" :placeholder="t('memo.search')" :aria-label="t('memo.search')" :disabled="contextLocked" /></div>
      <span v-else class="memos-context">{{ t(`memo.${screen === 'edit' ? baseline ? 'editing' : 'creating' : 'reading'}`) }}</span>
      <div class="memos-toolbar-actions" data-page-error-anchor>
        <GhostBtn v-if="screen !== 'edit'" :loading="loading || detailLoading" :disabled="locked" @click="requestRefresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('memo.refresh') }}</GhostBtn>
        <PrimaryBtn v-if="screen === 'list'" :disabled="!canMutate || locked" @click="create"><i class="i-mdi-plus" aria-hidden="true" />{{ t('memo.create') }}</PrimaryBtn>
        <template v-else-if="screen === 'read'"><GhostBtn danger :disabled="!canMutate || !readOnlyReady || locked" @click="prepareDelete"><i class="i-mdi-delete-outline" aria-hidden="true" />{{ t('memo.delete') }}</GhostBtn><PrimaryBtn :disabled="!canMutate || !readOnlyReady || locked" @click="editCurrent"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('memo.edit') }}</PrimaryBtn></template>
        <GhostBtn v-else :disabled="editorDisabled" @click="resetEditor"><i class="i-mdi-eraser" aria-hidden="true" />{{ t('memo.clear') }}</GhostBtn>
      </div>
    </header>
    <div v-if="requiresReview" class="memos-notice is-warning" role="alert">
      <p>{{ t(`memo.${mutation.kind === 'create' ? 'unknownCreate' : mutation.kind === 'delete' ? 'unknownDelete' : 'unknownUpdate'}`) }}</p>
      <div class="memos-inline-actions"><GhostBtn :loading="loading || detailLoading" :disabled="locked" @click="recheck"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('memo.recheck') }}</GhostBtn><GhostBtn :disabled="!reviewReady" @click="acknowledge"><i class="i-mdi-check" aria-hidden="true" />{{ t('memo.reviewed') }}</GhostBtn></div>
    </div>
    <div v-else-if="mutation.outcome === 'success' && !contextLocked" class="memos-notice" role="status"><p>{{ successLabel }}</p><GhostBtn @click="notes.clearMutation">{{ t('memo.dismiss') }}</GhostBtn></div>
    <PageErrorNotice v-if="problem">{{ errorLabel(problem) }} {{ loaded ? t('memo.retained') : '' }}</PageErrorNotice>
    <PageErrorNotice v-if="mutation.outcome === 'failed'">{{ errorLabel(mutation.problem) }}</PageErrorNotice>
    <div v-if="screen === 'list'" ref="scrollArea" class="memos-table-scroll" :aria-busy="loading">
      <MobileRecordList v-if="compact" drilldown list-id="memos" :record-keys="visibleRows.map(row => row.id)" :loading="loading">
        <MobileRecordCard v-for="row in visibleRows" :key="row.id" :record-key="row.id" :summary-title="row.title || t('memo.untitled')" :summary-meta="preview(row) || dateLabel(row.updateTime || row.createTime)">
          <template #identity><h2 class="mobile-record-title">{{ row.title || t('memo.untitled') }}</h2></template>
          <dl class="mobile-record-fields"><div><dt>{{ t('memo.createdAt') }}</dt><dd>{{ dateLabel(row.createTime) }}</dd></div><div><dt>{{ t('memo.updatedAt') }}</dt><dd>{{ dateLabel(row.updateTime) }}</dd></div><div v-if="row.summary" class="mobile-record-wide"><dt>{{ t('memo.summary') }}</dt><dd>{{ row.summary }}</dd></div></dl>
          <MemoContent :html="row.htmlContent" :text="row.content" />
          <template #footer>
            <button type="button" class="mobile-record-button" :disabled="locked" @click="openRow(row)"><i class="i-mdi-eye-outline" aria-hidden="true" />{{ t('memo.view') }}</button>
            <button type="button" class="mobile-record-button" :disabled="!canMutate || locked" @click="editRow(row)"><i class="i-mdi-pencil-outline" aria-hidden="true" />{{ t('memo.edit') }}</button>
            <button type="button" class="mobile-record-button" :disabled="!canMutate || locked" @click="deleteRow(row)"><i class="i-mdi-delete-outline" aria-hidden="true" />{{ t('memo.delete') }}</button>
          </template>
        </MobileRecordCard>
        <p v-if="!visibleRows.length" class="memos-empty" role="status">{{ loading ? t('memo.loading') : problem ? t('memo.loadFailed') : query.trim() ? t('memo.noMatches') : t('memo.empty') }}</p>
      </MobileRecordList>
      <table v-else class="memos-table">
        <caption class="memos-sr-only">{{ t('memo.title') }}</caption>
        <colgroup><col /><col class="memos-date-col" /><col class="memos-date-col" /><col class="memos-actions-col" /></colgroup>
        <thead><tr><th scope="col">{{ t('memo.note') }}</th><th scope="col">{{ t('memo.createdAt') }}</th><th scope="col">{{ t('memo.updatedAt') }}</th><th scope="col" class="memos-sticky-actions">{{ t('memo.actions') }}</th></tr></thead>
        <tbody><tr v-for="row in visibleRows" :key="row.id">
          <td><button class="memos-note-link" type="button" :disabled="locked" @click="openRow(row)"><strong :title="row.title">{{ row.title || t('memo.untitled') }}</strong><span :title="preview(row)">{{ preview(row) || '—' }}</span></button></td>
          <td><time :datetime="row.createTime || undefined">{{ dateLabel(row.createTime) }}</time></td><td><time :datetime="row.updateTime || undefined">{{ dateLabel(row.updateTime) }}</time></td>
          <td class="memos-sticky-actions"><div class="memos-row-actions"><button type="button" :disabled="locked" :title="t('memo.view')" :aria-label="t('memo.viewNamed', { title: row.title })" @click="openRow(row)"><i class="i-mdi-eye-outline" aria-hidden="true" /><span>{{ t('memo.view') }}</span></button><button type="button" :disabled="!canMutate || locked" :title="t('memo.edit')" :aria-label="t('memo.editNamed', { title: row.title })" @click="editRow(row)"><i class="i-mdi-pencil-outline" aria-hidden="true" /><span>{{ t('memo.edit') }}</span></button><button type="button" class="is-danger" :disabled="!canMutate || locked" :title="t('memo.delete')" :aria-label="t('memo.deleteNamed', { title: row.title })" @click="deleteRow(row)"><i class="i-mdi-delete-outline" aria-hidden="true" /><span>{{ t('memo.delete') }}</span></button></div></td>
        </tr><tr v-if="!visibleRows.length"><td colspan="4" class="memos-empty"><i class="i-mdi-note-text-outline" aria-hidden="true" /><span>{{ loading ? t('memo.loading') : problem ? t('memo.loadFailed') : query.trim() ? t('memo.noMatches') : t('memo.empty') }}</span></td></tr></tbody>
      </table>
    </div>
    <div v-else ref="scrollArea" class="memos-body" :aria-busy="detailLoading || contextLocked">
      <template v-if="screen === 'read'">
        <p v-if="detailLoading" class="memos-body-status" role="status">{{ t('memo.loadingDetail') }}</p>
        <PageErrorNotice v-if="detailProblem">{{ errorLabel(detailProblem) }}</PageErrorNotice>
        <article v-if="detail" class="memo-reading">
          <h2 ref="readHeading" tabindex="-1">{{ detail.title || t('memo.untitled') }}</h2>
          <dl class="memo-metadata"><div><dt>{{ t('memo.createdAt') }}</dt><dd>{{ dateLabel(detail.createTime) }}</dd></div><div><dt>{{ t('memo.updatedAt') }}</dt><dd>{{ dateLabel(detail.updateTime) }}</dd></div><div><dt>{{ t('memo.timeZone') }}</dt><dd>{{ t('memo.serverTime') }}</dd></div></dl>
          <p v-if="detail.summary" class="memo-summary">{{ detail.summary }}</p>
          <MemoContent :html="detail.htmlContent" :text="detail.content" />
        </article>
        <p v-else-if="!detailLoading && !detailProblem" class="memos-body-status">{{ t('memo.noSelection') }}</p>
      </template>
      <form v-else id="memo-editor-form" class="memo-form" @submit.prevent="save">
        <fieldset :disabled="editorDisabled">
          <div class="memo-field"><label for="memo-title">{{ t('memo.noteTitle') }}</label><input id="memo-title" ref="titleInput" v-model="draft.title" type="text" maxlength="255" autocomplete="off" :placeholder="t('memo.titlePlaceholder')" /></div>
          <div class="memo-field"><label for="memo-summary">{{ t('memo.summary') }}</label><textarea id="memo-summary" v-model="draft.summary" rows="2" maxlength="200" :placeholder="t('memo.summaryPlaceholder')" /><small>{{ number(draft.summary.length) }} / {{ number(200) }}</small></div>
          <MemoRichEditor :key="editorKey" :value="document" :disabled="editorDisabled" @update:value="updateDocument" @entry-change="entryChanged" />
        </fieldset>
        <p v-if="validation" class="memos-body-error" role="alert">{{ t(`memo.errors.${validation}`) }}</p>
        <div v-if="showSavedVersion && baseline" class="memo-compare" @keydown="reviewKeyboard">
          <div class="memo-compare-heading"><h3>{{ t('memo.savedVersion') }}</h3><GhostBtn :loading="detailLoading" :disabled="locked" @click="notes.reloadDetail"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('memo.refresh') }}</GhostBtn></div>
          <PageErrorNotice v-if="detailProblem">{{ errorLabel(detailProblem) }}</PageErrorNotice>
          <template v-if="detail"><strong>{{ detail.title }}</strong><p v-if="detail.summary">{{ detail.summary }}</p><MemoContent :html="detail.htmlContent" :text="detail.content" /><GhostBtn :disabled="locked || detailLoading || !!detailProblem || requiresReview" @click="inspectSaved">{{ t('memo.useSaved') }}</GhostBtn></template>
          <p v-else-if="detailExists === false">{{ t('memo.removedDraft') }}</p>
          <GhostBtn :disabled="!canMutate || locked" @click="keepAsNew"><i class="i-mdi-note-plus-outline" aria-hidden="true" />{{ t('memo.keepAsNew') }}</GhostBtn>
        </div>
        <div v-else-if="showSavedVersion" class="memo-compare" @keydown="reviewKeyboard">
          <h3>{{ t('memo.reviewList') }}</h3><p>{{ t('memo.reviewCreateHint') }}</p>
          <input v-model="query" class="memo-review-search" type="search" :aria-label="t('memo.search')" :placeholder="t('memo.search')" />
          <details v-for="row in visibleRows" :key="row.id" class="memo-review-item"><summary>{{ row.title || t('memo.untitled') }} · #{{ row.id }} · {{ dateLabel(row.createTime) }}</summary><p v-if="row.summary">{{ row.summary }}</p><MemoContent :html="row.htmlContent" :text="row.content" /></details>
          <p v-if="!visibleRows.length">{{ t('memo.noMatches') }}</p>
          <PagePagination v-model:current-page="page" :page-size="pageSize" :total="filtered.length" embedded />
        </div>
      </form>
    </div>
    <PagePagination v-if="screen === 'list'" v-model:current-page="page" :page-size="pageSize" :total="filtered.length" :disabled="contextLocked"><span>{{ loaded ? t('memo.count', { count: number(filtered.length), total: number(rows.length) }) : readTime }}</span></PagePagination>
    <footer v-else-if="screen === 'edit'" class="memos-footer"><span role="status">{{ contextLocked ? t('memo.submitting') : entryOpen ? t('memo.finishInsert') : dirty ? t('memo.dirty') : t('memo.shortcut') }}</span><PrimaryBtn type="submit" form="memo-editor-form" :loading="contextLocked && mutation.kind !== 'delete'" :disabled="!canSave"><i class="i-mdi-content-save-outline" aria-hidden="true" />{{ t('memo.save') }}</PrimaryBtn></footer>
    <footer v-else class="memos-footer"><span>{{ detail ? `#${detail.id}` : '—' }}</span><span>{{ readTime }}</span></footer>
    <el-dialog :model-value="!!deleteTarget" class="memo-confirm-dialog" :title="t('memo.deleteTitle')" width="480px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!contextLocked" :show-close="!contextLocked" :before-close="cancelDelete">
      <p>{{ t('memo.deleteHint', { title: deleteTarget?.title || t('memo.untitled') }) }}</p><p v-if="contextLocked" role="status">{{ t('memo.submitting') }}</p><template #footer><GhostBtn :disabled="contextLocked" @click="cancelDelete">{{ t('memo.cancel') }}</GhostBtn><PrimaryBtn :disabled="!canMutate" :loading="contextLocked" @click="confirmDelete">{{ t('memo.confirmDelete') }}</PrimaryBtn></template>
    </el-dialog>
    <el-dialog :model-value="discardVisible" class="memo-confirm-dialog" :title="t('memo.discardTitle')" width="480px" append-to-body :close-on-click-modal="false" :before-close="cancelDiscard">
      <p>{{ t('memo.discardHint') }}</p><template #footer><GhostBtn @click="cancelDiscard">{{ t('memo.keepEditing') }}</GhostBtn><PrimaryBtn @click="acceptDiscard">{{ t('memo.discard') }}</PrimaryBtn></template>
    </el-dialog>
  </section>
</template>
