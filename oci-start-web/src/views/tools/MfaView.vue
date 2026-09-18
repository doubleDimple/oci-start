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
import SecuritySecretInput from '@/views/settings/security/SecuritySecretInput.vue'
import type { MfaCandidate, MfaEntry, MfaPreviewInput, MfaApiError } from '@/api/mfaBackup'
import { useMfaBackup } from './mfa/useMfaBackup'
import './mfa/mfa-backup.scss'

const { t, locale } = useI18n(), router = useRouter()
const route = useRoute(), compact = useCompactViewport()
const screen = ref<'list' | 'add'>('list'), query = ref(typeof route.query.mfaSearch === 'string' ? route.query.mfaSearch : ''), currentPage = ref(routePage()), pageSize = 15
function routePage() { const value = Number(route.query.mfaPage); return Number.isSafeInteger(value) && value > 0 ? value : 1 }
const mode = ref<'manual' | 'image' | 'uri'>('manual')
const draft = reactive({ keyName: '', issuer: '', secretKey: '', qrUrl: '' })
const selectedImage = shallowRef<File | null>(null), imageUrl = ref(''), documentVisible = ref(!document.hidden)
const candidates = ref<MfaCandidate[]>([]), validation = ref(''), dragDepth = ref(0)
const fileInput = ref<HTMLInputElement>(), nameInput = ref<HTMLInputElement>(), scrollArea = ref<HTMLElement>()
const deleteTarget = shallowRef<MfaEntry | null>(null), materialTarget = shallowRef<MfaEntry | null>(null)
const exportIds = ref<string[] | null>(null), exportSearch = ref(''), discardVisible = ref(false), showQr = ref(true)
const reviewChecked = ref(false), copyNotice = ref(''), downloadNotice = ref(false)
const paused = computed(() => screen.value === 'add' || !!deleteTarget.value || !!materialTarget.value || !!exportIds.value || discardVisible.value)
const page = useMfaBackup(paused)
const { rows, loading, loaded, problem, lastUpdated, codesLoading, codesProblem, remainingSeconds,
  preview, previewLoading, previewProblem, material, materialLoading, materialProblem,
  mutation, requiresReview, reviewReady, contextLocked, canMutate, exportState } = page
const filtered = computed(() => {
  const term = query.value.trim().toLocaleLowerCase(locale.value)
  return term ? rows.value.filter(row => [row.keyName, row.issuer].some(value => value.toLocaleLowerCase(locale.value).includes(term))) : rows.value
})
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / pageSize)))
const visibleRows = computed(() => filtered.value.slice((currentPage.value - 1) * pageSize, currentPage.value * pageSize))
const dialogOpen = computed(() => !!deleteTarget.value || !!materialTarget.value || !!exportIds.value || discardVisible.value)
const locked = computed(() => contextLocked.value || exportState.value.pending || previewLoading.value)
const dirty = computed(() => screen.value === 'add' && (!!selectedImage.value || !!preview.value || !!candidates.value.length || Object.values(draft).some(Boolean)))
const canPreview = computed(() => !locked.value && !requiresReview.value && (mode.value === 'manual'
  ? !!draft.keyName.trim() && !!draft.secretKey.trim() : mode.value === 'image' ? !!selectedImage.value : !!draft.qrUrl.trim()))
const canSave = computed(() => canMutate.value && !locked.value && candidates.value.length > 0
  && candidates.value.every(row => row.keyName.trim().length > 0 && row.keyName.length <= 255 && row.issuer.length <= 255))
const readTime = computed(() => lastUpdated.value ? t('mfaBackup.lastUpdated', { time: new Intl.DateTimeFormat(locale.value, {
  hour: '2-digit', minute: '2-digit', second: '2-digit',
}).format(lastUpdated.value) }) : t('mfaBackup.notLoaded'))
let discardAction: (() => void) | undefined, cancelNavigation: (() => void) | undefined
let disposed = false, copyGeneration = 0, copyTimer: number | undefined

function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function dateLabel(value: string | null) {
  if (!value) return '—'
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(value)
  if (!match) return value
  const values = match.slice(1).map(Number)
  const date = new Date(Date.UTC(values[0]!, values[1]! - 1, values[2]!, values[3]!, values[4]!, values[5]!))
  return new Intl.DateTimeFormat(locale.value, { year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'UTC' }).format(date)
}
function errorLabel(error: MfaApiError | null) { return error ? t(`mfaBackup.errors.${error.key}`) : '' }
function codeLabel(id: string) {
  const code = page.codeFor(id)
  return code ? `${code.slice(0, 3)} ${code.slice(3)}` : t(page.codeErrorFor(id) ? 'mfaBackup.codeFailed' : codesLoading.value ? 'mfaBackup.codeLoading' : 'mfaBackup.codeExpired')
}
function back() {
  if (screen.value === 'add') { requestCloseEditor(); return }
  if (window.history.state?.back) router.back(); else void router.push('/boot/dashboard')
}
function releaseImage() { if (imageUrl.value) URL.revokeObjectURL(imageUrl.value); imageUrl.value = '' }
function clearEditor() {
  Object.assign(draft, { keyName: '', issuer: '', secretKey: '', qrUrl: '' })
  selectedImage.value = null; releaseImage(); candidates.value = []; validation.value = ''; dragDepth.value = 0
  page.clearPreview()
}
function openEditor() {
  if (!canMutate.value || locked.value || dialogOpen.value) return
  clearEditor(); page.clearMutation(); downloadNotice.value = false; mode.value = 'manual'; screen.value = 'add'
  void nextTick(() => nameInput.value?.focus())
}
function leaveEditor() { clearEditor(); screen.value = 'list' }
function requestDiscard(action: () => void, cancel?: () => void) {
  if (discardVisible.value) { cancel?.(); return }
  discardAction = action; cancelNavigation = cancel; discardVisible.value = true
}
function cancelDiscard() {
  discardVisible.value = false; discardAction = undefined
  const cancel = cancelNavigation; cancelNavigation = undefined; cancel?.()
}
function acceptDiscard() {
  const action = discardAction; discardAction = undefined; cancelNavigation = undefined
  discardVisible.value = false; clearEditor(); action?.()
}
function requestCloseEditor() {
  if (locked.value || requiresReview.value) return
  if (dirty.value) requestDiscard(leaveEditor); else leaveEditor()
}
function chooseMode(next: typeof mode.value) {
  if (locked.value || mode.value === next || preview.value) return
  const switchMode = () => { clearEditor(); mode.value = next }
  if (dirty.value) requestDiscard(switchMode); else switchMode()
}
function manualMode() { chooseMode('manual') }
function imageMode() { chooseMode('image') }
function uriMode() { chooseMode('uri') }
function updateSecret(value: string) { draft.secretKey = value; validation.value = '' }
function updateUri(value: string) { draft.qrUrl = value; validation.value = '' }
function chooseImage() { if (!locked.value && !preview.value) fileInput.value?.click() }
function selectImage(file: File) {
  if (locked.value || preview.value) return
  validation.value = ''; selectedImage.value = null; releaseImage()
  if (!['image/png', 'image/jpeg', 'image/gif'].includes(file.type) || !file.size) { validation.value = 'invalidImage'; return }
  if (file.size > 5 * 1024 * 1024) { validation.value = 'imageTooLarge'; return }
  selectedImage.value = file
  if (documentVisible.value) imageUrl.value = URL.createObjectURL(file)
}
function imageChanged(event: Event) {
  const input = event.target as HTMLInputElement, file = input.files?.[0]
  input.value = ''; if (file) selectImage(file)
}
function removeImage() { if (!locked.value) { selectedImage.value = null; releaseImage(); validation.value = '' } }
function dragEnter(event: DragEvent) { if (event.dataTransfer?.types.includes('Files')) { event.preventDefault(); if (!locked.value) dragDepth.value += 1 } }
function dragOver(event: DragEvent) { if (event.dataTransfer?.types.includes('Files')) { event.preventDefault(); event.dataTransfer.dropEffect = locked.value ? 'none' : 'copy' } }
function dragLeave(event: DragEvent) { event.preventDefault(); dragDepth.value = Math.max(0, dragDepth.value - 1) }
function dropImage(event: DragEvent) { event.preventDefault(); dragDepth.value = 0; const file = event.dataTransfer?.files[0]; if (file) selectImage(file) }
function pasteImage(event: ClipboardEvent) {
  if (mode.value !== 'image' || locked.value || preview.value) return
  const item = Array.from(event.clipboardData?.items ?? []).find(value => value.kind === 'file' && value.type.startsWith('image/'))
  const file = item?.getAsFile(); if (file) { event.preventDefault(); selectImage(file) }
}
async function parseInput() {
  if (!canPreview.value) return
  validation.value = ''; page.clearMutation()
  let input: MfaPreviewInput
  if (mode.value === 'image') { if (!selectedImage.value) return; input = { mode: 'image', qrCode: selectedImage.value } }
  else if (mode.value === 'uri') input = { mode: 'uri', qrUrl: draft.qrUrl }
  else input = { mode: 'manual', keyName: draft.keyName, issuer: draft.issuer, secretKey: draft.secretKey }
  await page.previewInput(input)
  if (disposed) return
  candidates.value = preview.value ? preview.value.entries.map(row => ({ ...row })) : []
  if (scrollArea.value) scrollArea.value.scrollTop = 0
}
function formEnter(event: KeyboardEvent) {
  if (!(event.target instanceof HTMLInputElement) || event.isComposing || event.keyCode === 229) return
  event.preventDefault(); if (!preview.value) void parseInput()
}
function backToInput() { if (!locked.value) { candidates.value = []; page.clearPreview(); page.clearMutation() } }
async function save() {
  if (!canSave.value) return
  await page.importEntries(candidates.value.map(row => ({ ...row })))
  if (disposed) return
  if (mutation.value.outcome === 'success' || mutation.value.outcome === 'unknown') leaveEditor()
}
function requestDelete(row: MfaEntry) { if (canMutate.value && !dialogOpen.value) { page.clearMaterial(); deleteTarget.value = { ...row }; page.clearMutation() } }
function cancelDelete() { if (!contextLocked.value) deleteTarget.value = null }
async function confirmDelete() {
  if (!deleteTarget.value || contextLocked.value) return
  await page.removeEntry(deleteTarget.value)
  if (!disposed) deleteTarget.value = null
}
async function openMaterial(row: MfaEntry) {
  if (locked.value || dialogOpen.value) return
  materialTarget.value = { ...row }; showQr.value = true
  await page.loadMaterial(row.id)
}
function closeMaterial() { materialTarget.value = null; page.clearMaterial(); showQr.value = false }
function toggleQr() { showQr.value = !showQr.value }
function requestExport() {
  if (!loaded.value || loading.value || problem.value || !filtered.value.length || locked.value || dialogOpen.value || requiresReview.value) return
  exportIds.value = filtered.value.map(row => row.id); exportSearch.value = query.value.trim(); downloadNotice.value = false
}
function cancelExport() { page.cancelExport(); exportIds.value = null; exportSearch.value = '' }
async function confirmExport() {
  if (!exportIds.value || exportState.value.pending) return
  const started = await page.exportCsv([...exportIds.value], [t('mfaBackup.name'), t('mfaBackup.issuer'), t('mfaBackup.secret')])
  if (!disposed && started) { downloadNotice.value = true; exportIds.value = null; exportSearch.value = '' }
}
async function copyCode(id: string) {
  const sequence = ++copyGeneration
  window.clearTimeout(copyTimer); copyNotice.value = 'copying'
  const copied = await page.copyCode(id)
  if (disposed || sequence !== copyGeneration || document.hidden) return
  copyNotice.value = copied ? 'copySuccess' : 'copyFailed'
  copyTimer = window.setTimeout(() => { copyNotice.value = '' }, 3000)
}
function acknowledgeReview() { if (reviewChecked.value && reviewReady.value) { page.acknowledgeReview(); reviewChecked.value = false } }
function beforeUnload(event: BeforeUnloadEvent) { if (dirty.value || contextLocked.value || requiresReview.value) { event.preventDefault(); event.returnValue = '' } }
function visibilityChanged() {
  documentVisible.value = !document.hidden
  if (document.hidden) {
    closeMaterial(); releaseImage(); candidates.value = []; ++copyGeneration; copyNotice.value = ''; window.clearTimeout(copyTimer)
  } else if (selectedImage.value && mode.value === 'image' && screen.value === 'add') imageUrl.value = URL.createObjectURL(selectedImage.value)
}
watch(query, () => { currentPage.value = 1 }, { flush: 'sync' })
watch([totalPages, loaded], ([value, ready]) => { if (ready) currentPage.value = Math.min(currentPage.value, value) })
watch(() => [route.query.mfaSearch, route.query.mfaPage], () => {
  query.value = typeof route.query.mfaSearch === 'string' ? route.query.mfaSearch : ''
  currentPage.value = routePage()
})
watch([query, currentPage], () => {
  if (!compact.value) return
  const mfaSearch = query.value || undefined, mfaPage = currentPage.value > 1 ? String(currentPage.value) : undefined
  if (route.query.mfaSearch === mfaSearch && route.query.mfaPage === mfaPage) return
  void router.replace({ query: { ...route.query, mfaSearch, mfaPage, mobileRecord: undefined }, hash: route.hash })
}, { flush: 'post' })
watch(() => visibleRows.value.map(row => row.id), ids => page.setVisibleIds(ids), { immediate: true })
watch(reviewReady, () => { reviewChecked.value = false })
onBeforeRouteLeave(() => {
  if (locked.value || requiresReview.value || dialogOpen.value) return false
  if (!dirty.value) return true
  return new Promise<boolean>(resolve => requestDiscard(() => resolve(true), () => resolve(false)))
})
onMounted(() => { void page.refresh(); window.addEventListener('beforeunload', beforeUnload); document.addEventListener('visibilitychange', visibilityChanged) })
onBeforeUnmount(() => {
  disposed = true; ++copyGeneration; window.clearTimeout(copyTimer); releaseImage(); clearEditor(); cancelNavigation?.()
  window.removeEventListener('beforeunload', beforeUnload); document.removeEventListener('visibilitychange', visibilityChanged)
})
</script>

<template>
  <section class="mfa-page">
    <header class="mfa-toolbar" data-page-error-anchor>
      <PageBackButton :disabled="locked || dialogOpen || requiresReview" @click="back" />
      <template v-if="screen === 'list'">
        <label class="mfa-search"><i class="i-mdi-magnify" aria-hidden="true" /><input v-model="query" type="search" :placeholder="t('mfaBackup.search')" :aria-label="t('mfaBackup.search')" :disabled="contextLocked" /></label>
        <div class="mfa-toolbar-actions"><GhostBtn :loading="loading" :disabled="locked || dialogOpen" @click="page.refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('mfaBackup.refresh') }}</GhostBtn><GhostBtn :disabled="!loaded || loading || !!problem || !filtered.length || locked || dialogOpen || requiresReview" @click="requestExport"><i class="i-mdi-download" aria-hidden="true" />{{ t('mfaBackup.export') }}</GhostBtn><PrimaryBtn :disabled="!canMutate || locked || dialogOpen" @click="openEditor"><i class="i-mdi-plus" aria-hidden="true" />{{ t('mfaBackup.add') }}</PrimaryBtn></div>
      </template>
      <template v-else><span class="mfa-editor-title">{{ t('mfaBackup.addTitle') }}</span><GhostBtn :disabled="locked || requiresReview" @click="requestCloseEditor">{{ t('mfaBackup.cancel') }}</GhostBtn></template>
    </header>
    <div v-if="mutation.outcome === 'success'" class="mfa-notice" role="status"><p>{{ mutation.kind === 'delete' ? t('mfaBackup.deleted') : t('mfaBackup.savedCount', { created: number(mutation.result?.importedCount ?? 0), preserved: number(mutation.result?.preservedCount ?? 0) }) }}<span v-if="problem"> {{ t('mfaBackup.savedReadFailed') }}</span></p><GhostBtn @click="page.clearMutation">{{ t('mfaBackup.close') }}</GhostBtn></div>
    <div v-if="requiresReview" class="mfa-notice is-warning" role="status"><div><strong>{{ t('mfaBackup.unknown') }}</strong><p>{{ t('mfaBackup.unknownHint') }}</p><label class="mfa-check"><input v-model="reviewChecked" type="checkbox" :disabled="!reviewReady" /><span>{{ t('mfaBackup.reviewLabel') }}</span></label></div><GhostBtn :disabled="loading || contextLocked" :loading="loading" @click="page.refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('mfaBackup.refresh') }}</GhostBtn><GhostBtn :disabled="!reviewReady || !reviewChecked" @click="acknowledgeReview">{{ t('mfaBackup.review') }}</GhostBtn></div>
    <PageErrorNotice v-if="mutation.outcome === 'failed' && mutation.problem">{{ errorLabel(mutation.problem) }} {{ t('mfaBackup.submitRejected') }}</PageErrorNotice>
    <PageErrorNotice v-if="problem"><p>{{ errorLabel(problem) }}</p><GhostBtn v-if="screen === 'add'" :disabled="locked || dialogOpen" :loading="loading" @click="page.refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('mfaBackup.refresh') }}</GhostBtn></PageErrorNotice>
    <p v-if="downloadNotice" class="mfa-feedback" role="status">{{ t('mfaBackup.exportStarted') }}</p>
    <PageErrorNotice v-if="copyNotice === 'copyFailed'" :label="t('mfaBackup.copyFailed')">{{ t('mfaBackup.copyFailed') }}</PageErrorNotice>
    <p v-else-if="copyNotice" class="mfa-feedback" role="status">{{ t(`mfaBackup.${copyNotice}`) }}</p>

    <template v-if="screen === 'list'">
      <div v-if="compact" class="mfa-table-scroll">
        <MobileRecordList drilldown list-id="mfa" :record-keys="visibleRows.map(row => row.id)" :loading="loading">
          <MobileRecordCard v-for="row in visibleRows" :key="row.id" :record-key="row.id" :summary-title="row.keyName" :summary-meta="[row.issuer, dateLabel(row.createTime)].filter(Boolean).join(' · ')">
            <template #identity><h2 class="mobile-record-title">{{ row.keyName }}</h2><span v-if="row.issuer" class="mobile-record-subtitle">{{ row.issuer }}</span></template>
            <dl class="mobile-record-fields">
              <div class="mobile-record-wide"><dt>{{ t('mfaBackup.code') }}</dt><dd><button type="button" class="mfa-code" :disabled="!page.codeFor(row.id) || contextLocked" :aria-label="t('mfaBackup.copyCode')" :title="t('mfaBackup.copyCode')" @click="copyCode(row.id)"><span>{{ codeLabel(row.id) }}</span><i v-if="page.codeFor(row.id)" class="i-mdi-content-copy" aria-hidden="true" /></button><small v-if="page.codeFor(row.id)" class="mfa-countdown" :class="{ 'is-ending': remainingSeconds <= 5 }">{{ t('mfaBackup.secondsLeft', { seconds: number(remainingSeconds) }) }}</small></dd></div>
              <div><dt>{{ t('mfaBackup.created') }}</dt><dd><time :datetime="row.createTime || undefined">{{ dateLabel(row.createTime) }}</time></dd></div>
            </dl>
            <template #footer><button type="button" class="mobile-record-button" :disabled="locked || dialogOpen" @click="openMaterial(row)"><i class="i-mdi-qrcode" aria-hidden="true" />{{ t('mfaBackup.material') }}</button><button type="button" class="mobile-record-button" :disabled="!canMutate || locked || dialogOpen" @click="requestDelete(row)"><i class="i-mdi-trash-can-outline" aria-hidden="true" />{{ t('mfaBackup.remove') }}</button></template>
          </MobileRecordCard>
          <p v-if="!visibleRows.length" class="mfa-empty" role="status">{{ t(loading ? 'mfaBackup.loading' : !loaded ? 'mfaBackup.notLoaded' : query.trim() ? 'mfaBackup.noMatches' : 'mfaBackup.empty') }}</p>
        </MobileRecordList>
      </div>
      <div v-else class="mfa-table-scroll"><table class="mfa-table"><colgroup><col /><col class="mfa-issuer-col" /><col class="mfa-code-col" /><col class="mfa-date-col" /><col class="mfa-actions-col" /></colgroup><thead><tr><th scope="col">{{ t('mfaBackup.name') }}</th><th scope="col">{{ t('mfaBackup.issuer') }}</th><th scope="col">{{ t('mfaBackup.code') }}</th><th scope="col">{{ t('mfaBackup.created') }}</th><th scope="col" class="mfa-sticky-actions">{{ t('mfaBackup.actions') }}</th></tr></thead><tbody>
        <tr v-for="row in visibleRows" :key="row.id"><td><strong class="mfa-account-name" :title="row.keyName">{{ row.keyName }}</strong></td><td><span class="mfa-issuer" :title="row.issuer">{{ row.issuer || '—' }}</span></td><td><button type="button" class="mfa-code" :disabled="!page.codeFor(row.id) || contextLocked" :aria-label="t('mfaBackup.copyCode')" :title="t('mfaBackup.copyCode')" @click="copyCode(row.id)"><span>{{ codeLabel(row.id) }}</span><i v-if="page.codeFor(row.id)" class="i-mdi-content-copy" aria-hidden="true" /></button><small v-if="page.codeFor(row.id)" class="mfa-countdown" :class="{ 'is-ending': remainingSeconds <= 5 }">{{ t('mfaBackup.secondsLeft', { seconds: number(remainingSeconds) }) }}</small></td><td><time :datetime="row.createTime || undefined">{{ dateLabel(row.createTime) }}</time></td><td class="mfa-sticky-actions"><div class="mfa-row-actions"><button type="button" :disabled="locked || dialogOpen" :title="t('mfaBackup.material')" :aria-label="t('mfaBackup.material')" @click="openMaterial(row)"><i class="i-mdi-qrcode" aria-hidden="true" /><span>{{ t('mfaBackup.material') }}</span></button><button type="button" class="is-danger" :disabled="!canMutate || locked || dialogOpen" :title="t('mfaBackup.remove')" :aria-label="t('mfaBackup.remove')" @click="requestDelete(row)"><i class="i-mdi-trash-can-outline" aria-hidden="true" /><span>{{ t('mfaBackup.remove') }}</span></button></div></td></tr>
        <tr v-if="!visibleRows.length"><td colspan="5" class="mfa-empty"><i class="i-mdi-shield-key-outline" aria-hidden="true" />{{ t(loading ? 'mfaBackup.loading' : !loaded ? 'mfaBackup.notLoaded' : query.trim() ? 'mfaBackup.noMatches' : 'mfaBackup.empty') }}</td></tr>
      </tbody></table></div>
      <PagePagination v-model:current-page="currentPage" :page-size="pageSize" :total="filtered.length" :disabled="contextLocked"><span>{{ loaded ? t('mfaBackup.count', { count: number(filtered.length), total: number(rows.length) }) : readTime }}<span v-if="codesProblem"> · {{ errorLabel(codesProblem) }}</span></span></PagePagination>
    </template>

    <template v-else>
      <div ref="scrollArea" class="mfa-editor-scroll">
        <template v-if="preview">
          <div class="mfa-section-heading"><h2>{{ t('mfaBackup.previewTitle') }}</h2><p>{{ t('mfaBackup.previewHint') }}</p><p>{{ t('mfaBackup.duplicateHint') }}</p></div>
          <p v-if="preview.partialBatch" class="mfa-batch-hint">{{ t('mfaBackup.batchHint', { index: number(preview.batchIndex + 1), total: number(preview.batchSize) }) }}</p>
          <div class="mfa-preview-scroll"><table class="mfa-preview-table"><caption>{{ t('mfaBackup.previewCount', { count: number(candidates.length) }) }}</caption><thead><tr><th scope="col">{{ t('mfaBackup.name') }}</th><th scope="col">{{ t('mfaBackup.issuer') }}</th></tr></thead><tbody><tr v-for="(candidate, index) in candidates" :key="index"><td><input v-model="candidate.keyName" type="text" maxlength="255" :disabled="locked" :aria-label="`${t('mfaBackup.name')} ${index + 1}`" /></td><td><input v-model="candidate.issuer" type="text" maxlength="255" :disabled="locked" :aria-label="`${t('mfaBackup.issuer')} ${index + 1}`" /></td></tr></tbody></table></div>
        </template>
        <form v-else id="mfa-preview-form" class="mfa-input-form" @submit.prevent="parseInput" @paste="pasteImage" @keydown.enter="formEnter">
          <p class="mfa-help">{{ t('mfaBackup.addHint') }}</p>
          <nav class="mfa-input-tabs" :aria-label="t('mfaBackup.modeLabel')"><button type="button" :class="{ 'is-active': mode === 'manual' }" :aria-current="mode === 'manual' ? 'page' : undefined" :disabled="locked" @click="manualMode"><i class="i-mdi-key-outline" aria-hidden="true" />{{ t('mfaBackup.manual') }}</button><button type="button" :class="{ 'is-active': mode === 'image' }" :aria-current="mode === 'image' ? 'page' : undefined" :disabled="locked" @click="imageMode"><i class="i-mdi-qrcode" aria-hidden="true" />{{ t('mfaBackup.image') }}</button><button type="button" :class="{ 'is-active': mode === 'uri' }" :aria-current="mode === 'uri' ? 'page' : undefined" :disabled="locked" @click="uriMode"><i class="i-mdi-link-variant" aria-hidden="true" />{{ t('mfaBackup.uri') }}</button></nav>
          <template v-if="mode === 'manual'"><div class="mfa-field"><label for="mfa-key-name">{{ t('mfaBackup.name') }}</label><input id="mfa-key-name" ref="nameInput" v-model="draft.keyName" type="text" maxlength="255" autocomplete="off" :disabled="locked" :placeholder="t('mfaBackup.namePlaceholder')" /></div><div class="mfa-field"><label for="mfa-issuer">{{ t('mfaBackup.issuer') }}</label><input id="mfa-issuer" v-model="draft.issuer" type="text" maxlength="255" autocomplete="off" :disabled="locked" :placeholder="t('mfaBackup.issuerPlaceholder')" /></div><SecuritySecretInput id="mfa-new-key" :label="t('mfaBackup.secret')" :model-value="draft.secretKey" autocomplete="off" :disabled="locked" :placeholder="t('mfaBackup.secretPlaceholder')" @update:model-value="updateSecret" /></template>
          <template v-else-if="mode === 'image'"><input ref="fileInput" type="file" class="mfa-file-input" accept="image/png,image/jpeg,image/gif" :disabled="locked" :aria-label="t('mfaBackup.chooseImage')" @change="imageChanged" /><div class="mfa-drop" :class="{ 'is-dragging': dragDepth > 0 }" @dragenter="dragEnter" @dragover="dragOver" @dragleave="dragLeave" @drop="dropImage"><button type="button" :disabled="locked" @click="chooseImage"><i class="i-mdi-image-outline" aria-hidden="true" /><span>{{ selectedImage?.name || t('mfaBackup.dropImage') }}<small v-if="selectedImage">{{ t('mfaBackup.replaceImage') }}</small></span></button><button v-if="selectedImage" type="button" class="mfa-remove-image" :disabled="locked" :title="t('mfaBackup.removeImage')" :aria-label="t('mfaBackup.removeImage')" @click="removeImage"><i class="i-mdi-close" aria-hidden="true" /></button></div><p class="mfa-help">{{ t('mfaBackup.imageHint') }}</p><img v-if="imageUrl && documentVisible" class="mfa-upload-preview" :src="imageUrl" :alt="t('mfaBackup.imagePreview')" /></template>
          <SecuritySecretInput v-else id="mfa-qr-text" :label="t('mfaBackup.uriLabel')" :model-value="draft.qrUrl" autocomplete="off" :disabled="locked" :placeholder="t('mfaBackup.uriPlaceholder')" @update:model-value="updateUri" />
          <p class="mfa-help">{{ t('mfaBackup.supportHint') }}</p>
          <p v-if="validation" class="mfa-input-error" role="alert">{{ t(`mfaBackup.errors.${validation}`) }}</p><PageErrorNotice v-if="previewProblem">{{ errorLabel(previewProblem) }}</PageErrorNotice>
        </form>
      </div>
      <footer class="mfa-footer"><span role="status">{{ contextLocked ? t('mfaBackup.saving') : previewLoading ? t('mfaBackup.parsing') : '' }}</span><GhostBtn v-if="previewLoading" @click="page.clearPreview">{{ t('mfaBackup.cancelParsing') }}</GhostBtn><template v-else-if="preview"><GhostBtn :disabled="locked" @click="backToInput">{{ t('mfaBackup.backToInput') }}</GhostBtn><PrimaryBtn :loading="contextLocked" :disabled="!canSave" @click="save"><i class="i-mdi-check" aria-hidden="true" />{{ t('mfaBackup.save') }}</PrimaryBtn></template><PrimaryBtn v-else type="submit" form="mfa-preview-form" :disabled="!canPreview"><i class="i-mdi-arrow-right" aria-hidden="true" />{{ t('mfaBackup.preview') }}</PrimaryBtn></footer>
    </template>

    <el-dialog :model-value="!!materialTarget" class="mfa-dialog mfa-material-dialog" :title="material?.keyName || materialTarget?.keyName || t('mfaBackup.material')" width="540px" append-to-body :close-on-click-modal="false" :before-close="closeMaterial">
      <p>{{ t('mfaBackup.materialHint') }}</p><p v-if="materialLoading" role="status">{{ t('mfaBackup.materialLoading') }}</p>
      <PageErrorNotice v-if="materialProblem">{{ errorLabel(materialProblem) }}</PageErrorNotice>
      <template v-if="material && materialTarget && material.id === materialTarget.id"><p v-if="material.issuer">{{ t('mfaBackup.issuer') }}：{{ material.issuer }}</p><div class="mfa-qr-area"><img v-if="showQr" class="mfa-qr-image" :src="`data:image/png;base64,${material.qrCode}`" :alt="t('mfaBackup.qrAlt')" /><span v-else class="mfa-qr-placeholder">{{ t('mfaBackup.qrHidden') }}</span><GhostBtn @click="toggleQr">{{ t(showQr ? 'mfaBackup.hideQr' : 'mfaBackup.revealQr') }}</GhostBtn></div><SecuritySecretInput id="mfa-saved-key" :label="t('mfaBackup.secret')" :model-value="material.secretKey" readonly copyable :reveal-duration="5000" autocomplete="off" /></template>
      <template #footer><GhostBtn @click="closeMaterial">{{ t('mfaBackup.close') }}</GhostBtn></template>
    </el-dialog>
    <el-dialog :model-value="!!deleteTarget" class="mfa-dialog" :title="t('mfaBackup.deleteTitle')" width="500px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!contextLocked" :show-close="!contextLocked" :before-close="cancelDelete"><p>{{ t('mfaBackup.deleteHint', { name: deleteTarget?.keyName || '' }) }}</p><p>{{ t('mfaBackup.deleteBackupHint') }}</p><p v-if="contextLocked" role="status">{{ t('mfaBackup.pending') }}</p><template #footer><GhostBtn :disabled="contextLocked" @click="cancelDelete">{{ t('mfaBackup.cancel') }}</GhostBtn><PrimaryBtn :loading="contextLocked" @click="confirmDelete">{{ t('mfaBackup.confirmDelete') }}</PrimaryBtn></template></el-dialog>
    <el-dialog :model-value="!!exportIds" class="mfa-dialog" :title="t('mfaBackup.exportTitle')" width="520px" append-to-body :close-on-click-modal="false" :before-close="cancelExport"><p>{{ t('mfaBackup.exportHint', { count: number(exportIds?.length ?? 0) }) }}</p><p v-if="exportSearch">{{ t('mfaBackup.search') }}：{{ exportSearch }}</p><p>{{ t('mfaBackup.exportSecretHint') }}</p><PageErrorNotice v-if="exportState.problem">{{ errorLabel(exportState.problem) }}</PageErrorNotice><template #footer><GhostBtn @click="cancelExport">{{ t('mfaBackup.cancel') }}</GhostBtn><PrimaryBtn :loading="exportState.pending" @click="confirmExport"><i class="i-mdi-download" aria-hidden="true" />{{ t('mfaBackup.confirmExport') }}</PrimaryBtn></template></el-dialog>
    <el-dialog :model-value="discardVisible" class="mfa-dialog" :title="t('mfaBackup.discardTitle')" width="480px" append-to-body :close-on-click-modal="false" :before-close="cancelDiscard"><p>{{ t('mfaBackup.discardHint') }}</p><template #footer><GhostBtn @click="cancelDiscard">{{ t('mfaBackup.keepEditing') }}</GhostBtn><PrimaryBtn @click="acceptDiscard">{{ t('mfaBackup.discard') }}</PrimaryBtn></template></el-dialog>
  </section>
</template>
