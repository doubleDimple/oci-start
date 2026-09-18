<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import GhostBtn from '@/components/GhostBtn.vue'
import {
  getStorageDownloadUrl, getStoragePreview, storageError, STORAGE_PREVIEW_LIMIT,
  type StorageObjectContext,
} from '@/api/objectStorage'

const props = defineProps<{ modelValue: boolean; target: StorageObjectContext | null; size: number | null }>()
const emit = defineEmits<{ 'update:modelValue': [value: boolean] }>()
const { t, locale } = useI18n()
const TEXT_LIMIT = 2 * 1024 * 1024
const imageTypes = new Map([
  ['png', 'image/png'], ['jpg', 'image/jpeg'], ['jpeg', 'image/jpeg'],
  ['gif', 'image/gif'], ['webp', 'image/webp'], ['svg', 'image/svg+xml'],
])
const textExtensions = new Set(['txt', 'log', 'md', 'json', 'xml', 'html', 'htm'])
const extension = computed(() => props.target?.objectName.split('/').pop()?.split('.').pop()?.toLowerCase() || '')
const kind = computed(() => imageTypes.has(extension.value) ? 'image' : extension.value === 'pdf' ? 'pdf' : textExtensions.has(extension.value) ? 'text' : 'unsupported')
const previewLimit = computed(() => kind.value === 'text' ? TEXT_LIMIT : STORAGE_PREVIEW_LIMIT)
const limitLabel = computed(() => `${new Intl.NumberFormat(locale.value).format(previewLimit.value / 1024 / 1024)} MiB`)
const fileName = computed(() => props.target?.objectName.split('/').pop() || props.target?.objectName || '')
const downloadUrl = computed(() => {
  if (!props.target) return ''
  try { return getStorageDownloadUrl(props.target) } catch { return '' }
})
const loading = ref(false)
const imageLoading = ref(false)
const ready = ref(false)
const objectUrl = ref('')
const textContent = ref('')
const problem = ref<ReturnType<typeof storageError> | null>(null)
const localProblem = ref<'unsupported' | 'tooLarge' | 'invalidPdf' | 'imageFailed' | 'missingTarget' | ''>('')
const problemText = computed(() => {
  if (localProblem.value) return t(`storagePreview.${localProblem.value}`, { limit: limitLabel.value })
  if (problem.value?.key === 'previewTooLarge') return t('storagePreview.tooLarge', { limit: limitLabel.value })
  return problem.value ? problem.value.detail || t(`storagePreview.errors.${problem.value.key}`) : ''
})
const busy = computed(() => loading.value || imageLoading.value)
const retryable = computed(() => (!!problem.value && problem.value.key !== 'previewTooLarge') || ['imageFailed', 'invalidPdf'].includes(localProblem.value))
let sequence = 0
let controller: AbortController | undefined
let disposed = false

function clearPreview() {
  sequence++
  controller?.abort()
  controller = undefined
  loading.value = imageLoading.value = ready.value = false
  if (objectUrl.value) URL.revokeObjectURL(objectUrl.value)
  objectUrl.value = textContent.value = ''
  problem.value = null
  localProblem.value = ''
}
async function loadPreview() {
  clearPreview()
  if (disposed || !props.modelValue) return
  if (!props.target) { localProblem.value = 'missingTarget'; return }
  if (kind.value === 'unsupported') { localProblem.value = 'unsupported'; return }
  const context = { ...props.target }
  const mode = kind.value
  const mime = mode === 'pdf' ? 'application/pdf' : imageTypes.get(extension.value)
  const limit = previewLimit.value
  const expectedSize = props.size
  if (typeof expectedSize === 'number' && expectedSize > limit) { localProblem.value = 'tooLarge'; return }
  const current = sequence
  const active = new AbortController()
  controller = active
  loading.value = true
  const isCurrent = () => !disposed && !active.signal.aborted && current === sequence
  try {
    const blob = await getStoragePreview(context, active.signal, expectedSize, limit)
    if (!isCurrent()) return
    if (blob.size > limit) { localProblem.value = 'tooLarge'; return }
    if (mode === 'text') {
      const content = await blob.text()
      if (!isCurrent()) return
      textContent.value = content
    } else {
      if (mode === 'pdf') {
        const header = await blob.slice(0, 5).text()
        if (!isCurrent()) return
        if (header !== '%PDF-') { localProblem.value = 'invalidPdf'; return }
      }
      // Ignore the server's Content-Type. SVG remains in an image context, and
      // only a verified PDF is handed to the browser's native PDF viewer.
      objectUrl.value = URL.createObjectURL(new Blob([blob], { type: mime }))
      imageLoading.value = mode === 'image'
    }
    ready.value = true
  } catch (cause) {
    if (isCurrent()) problem.value = storageError(cause)
  } finally {
    if (isCurrent()) loading.value = false
  }
}
function imageFinished(event: Event, failed = false) {
  const element = event.currentTarget
  if (!(element instanceof HTMLImageElement) || element.src !== objectUrl.value) return
  imageLoading.value = false
  if (failed) {
    localProblem.value = 'imageFailed'
    ready.value = false
    URL.revokeObjectURL(objectUrl.value)
    objectUrl.value = ''
  }
}
function close() {
  clearPreview()
  emit('update:modelValue', false)
}
function visibilityChanged(value: boolean) {
  if (!value) close()
}
watch([
  () => props.modelValue, () => props.target?.tenantId, () => props.target?.namespace,
  () => props.target?.bucketName, () => props.target?.objectName, () => props.size,
], () => { void loadPreview() }, { immediate: true, flush: 'sync' })
onBeforeUnmount(() => { disposed = true; clearPreview() })
</script>

<template>
  <el-dialog :model-value="modelValue" :title="t('storagePreview.title')" width="1040px" class="storage-preview-dialog" append-to-body @update:model-value="visibilityChanged">
    <div v-if="target" class="storage-preview-meta">
      <p class="storage-preview-name">{{ target.objectName }}</p>
      <p class="storage-preview-context">{{ t('storagePreview.bucket', { name: target.bucketName }) }}</p>
    </div>
    <p class="storage-preview-note">{{ t(kind === 'text' ? 'storagePreview.textLimit' : 'storagePreview.mediaLimit', { limit: limitLabel }) }}</p>
    <PageErrorNotice v-if="problemText" style="margin-bottom: 12px"><span>{{ problemText }}</span><GhostBtn v-if="retryable" :loading="busy" @click="loadPreview">{{ t('storagePreview.retry') }}</GhostBtn></PageErrorNotice>
    <div class="storage-preview-stage" :aria-busy="busy">
      <p v-if="busy" class="storage-preview-loading" role="status"><i class="i-mdi-loading" aria-hidden="true" />{{ t('storagePreview.loading') }}</p>
      <template v-if="ready">
        <img v-if="kind === 'image' && objectUrl" :key="objectUrl" :src="objectUrl" :alt="target?.objectName || ''" class="storage-preview-image" :class="{ pending: imageLoading }" @load="imageFinished($event)" @error="imageFinished($event, true)" />
        <object v-else-if="kind === 'pdf' && objectUrl" :key="objectUrl" :data="objectUrl" type="application/pdf" :aria-label="t('storagePreview.pdfLabel', { name: fileName })" class="storage-preview-pdf">
          <p>{{ t('storagePreview.pdfFallback') }} <a v-if="downloadUrl" :href="downloadUrl" :download="fileName">{{ t('storagePreview.download') }}</a></p>
        </object>
        <template v-else-if="kind === 'text'"><pre v-if="textContent" class="storage-preview-text" :class="{ technical: extension !== 'txt' }">{{ textContent }}</pre><p v-else class="storage-preview-empty">{{ t('storagePreview.emptyText') }}</p></template>
      </template>
    </div>
    <p v-if="kind === 'pdf' && ready" class="storage-preview-note">{{ t('storagePreview.pdfFallback') }}</p>
    <template #footer><a v-if="downloadUrl" :href="downloadUrl" :download="fileName" class="storage-preview-download"><i class="i-mdi-download" aria-hidden="true" />{{ t('storagePreview.download') }}</a><GhostBtn @click="close">{{ t('storagePreview.close') }}</GhostBtn></template>
  </el-dialog>
</template>

<style lang="scss">
.storage-preview-dialog {
  max-width: calc(100vw - 28px); color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans);
  .el-dialog__title { font: 600 var(--font-size-dialog-title)/1.4 var(--sans); }
  .el-dialog__body { max-height: min(74vh, 1000px); overflow: auto; }
  .el-dialog__footer { display: flex; justify-content: flex-end; align-items: center; flex-wrap: wrap; gap: 10px; border-top: 1px solid var(--border); }
  .el-dialog__footer .btn, .storage-preview-download { min-height: 36px; padding: 7px 12px; }
  .storage-preview-meta { min-width: 0; }
  .storage-preview-name { margin: 0; font-weight: 600; overflow-wrap: anywhere; }
  .storage-preview-context, .storage-preview-note { margin: 6px 0 12px; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
  .storage-preview-stage { position: relative; min-width: 0; }
  .storage-preview-loading { display: flex; align-items: center; justify-content: center; gap: 8px; min-height: 120px; margin: 0; color: var(--text-primary); }
  .storage-preview-loading i { animation: storage-preview-spin 900ms linear infinite; }
  .storage-preview-image { display: block; max-width: 100%; max-height: 58vh; margin: 0 auto; object-fit: contain; }
  .storage-preview-image.pending { position: absolute; visibility: hidden; }
  .storage-preview-pdf { display: block; width: 100%; height: 58vh; min-height: 260px; border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg-search); color: var(--text-primary); }
  .storage-preview-pdf a { color: var(--text-primary); text-underline-offset: 3px; }
  .storage-preview-text { max-height: 58vh; margin: 0; overflow: auto; padding: 14px; border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg-search); color: var(--text-primary); white-space: pre-wrap; overflow-wrap: anywhere; font: var(--font-size-body)/1.6 var(--sans); }
  .storage-preview-text.technical { font-family: var(--mono); }
  .storage-preview-empty { margin: 0; padding: 24px 0; text-align: center; color: var(--text-primary); }
  .storage-preview-download { display: inline-flex; align-items: center; justify-content: center; gap: 6px; border: 1px solid var(--border-strong); border-radius: var(--r-pill); background: var(--bg-card); color: var(--text-primary); font: 600 var(--font-size-body)/1.5 var(--sans); text-decoration: none; white-space: nowrap; }
  .storage-preview-download:hover { background: var(--bg-hover); }
  .storage-preview-download:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
}
@keyframes storage-preview-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .storage-preview-dialog .storage-preview-loading i { animation: none; } }
</style>
