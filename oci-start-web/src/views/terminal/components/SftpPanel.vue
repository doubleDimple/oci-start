<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, shallowRef, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import GhostBtn from '@/components/GhostBtn.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import {
  downloadSftpFile, sftpError, uploadSftpFile,
  type SftpApiError, type SftpCredentials, type SftpDownload, type SftpProgress,
} from '@/api/sftp'

const props = defineProps<{
  visible?: boolean
  connected: boolean
  credentials: SftpCredentials | null
  connectionKey: string | number
}>()
const emit = defineEmits<{ busy: [value: boolean] }>()
const { t, locale } = useI18n()
type Mode = 'upload' | 'download'
type UploadState = 'idle' | 'uploading' | 'success' | 'uncertain' | 'failed'
type DownloadState = 'idle' | 'downloading' | 'done' | 'cancelled' | 'failed' | 'saveFailed'
const panel = ref<HTMLElement>()
const fileInput = ref<HTMLInputElement>()
const chooseButton = ref<HTMLButtonElement>()
const downloadInput = ref<HTMLInputElement>()
const mode = ref<Mode>('upload')
const file = shallowRef<File | null>(null)
const uploadPath = ref('')
const downloadPath = ref('')
const overwriteAccepted = ref(false)
const reviewed = ref(false)
const uploadState = ref<UploadState>('idle')
const downloadState = ref<DownloadState>('idle')
const uploadProblem = shallowRef<SftpApiError | null>(null)
const downloadProblem = shallowRef<SftpApiError | null>(null)
const uploadValidation = ref('')
const downloadValidation = ref('')
const uploadProgress = ref<SftpProgress>({ loaded: 0 })
const downloadProgress = ref<SftpProgress>({ loaded: 0 })
const uploadTarget = ref('')
const uploadHost = ref('')
const uploadFilename = ref('')
const downloadTarget = ref('')
const downloadHost = ref('')
const downloadFilename = ref('')
const receivedSize = ref(0)
const active = ref<Mode | null>(null)
const cancelling = ref(false)
const receivedFile = shallowRef<SftpDownload | null>(null)
const busy = computed(() => active.value !== null)
const ready = computed(() => props.connected && props.credentials !== null)
const uploadLocked = computed(() => uploadState.value === 'success' || uploadState.value === 'uncertain')
const destination = computed(() => file.value && uploadPath.value
  ? uploadPath.value.endsWith('/') ? uploadPath.value + file.value.name : uploadPath.value
  : '')
const targetLabel = computed(() => props.credentials ? describeTarget(props.credentials) : '')
const uploadSendingDone = computed(() => uploadProgress.value.total !== undefined
  && uploadProgress.value.loaded >= uploadProgress.value.total)
const progress = computed(() => active.value === 'download' ? downloadProgress.value : uploadProgress.value)
const progressPercent = computed(() => progress.value.total && progress.value.total > 0
  ? Math.min(100, progress.value.loaded / progress.value.total * 100) : null)
const uploadMessage = computed(() => {
  if (uploadState.value === 'uploading') return t(`sftp.${uploadSendingDone.value ? 'uploadWaiting' : 'uploadSending'}`)
  return t(`sftp.${uploadState.value === 'success' ? 'uploadDone' : uploadState.value === 'uncertain' ? 'uploadUnknown' : 'uploadFailed'}`)
})
const downloadMessage = computed(() => t(`sftp.${({
  idle: 'download', downloading: 'downloading', done: 'downloadDone', cancelled: 'downloadCancelled',
  failed: 'downloadFailed', saveFailed: 'downloadSaveFailed',
} as const)[downloadState.value]}`))
let controller: AbortController | undefined
let sequence = 0
let pickerKey: string | number | undefined
let disposed = false
const objectUrls = new Map<string, ReturnType<typeof setTimeout>>()

function describeTarget(value: SftpCredentials) {
  const host = value.host.includes(':') && !value.host.startsWith('[') ? `[${value.host}]` : value.host
  return `${value.username}@${host}:${value.port}`
}
function bytes(value: number) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  const index = value > 0 ? Math.min(units.length - 1, Math.floor(Math.log(value) / Math.log(1024))) : 0
  return `${new Intl.NumberFormat(locale.value, { maximumFractionDigits: index ? 2 : 0 }).format(value / 1024 ** index)} ${units[index]}`
}
function problemText(value: SftpApiError) { return value.detail || t(`sftp.errors.${value.key}`) }
function validPath(value: string) { return !!value.trim() && !value.includes('\0') }
function clearFile() {
  if (busy.value || uploadLocked.value) return
  file.value = null
  if (fileInput.value) fileInput.value.value = ''
}
function chooseFile() {
  if (!ready.value || busy.value || uploadLocked.value) return
  pickerKey = props.connectionKey
  if (fileInput.value) {
    fileInput.value.value = ''
    fileInput.value.click()
  }
}
function selectedFile(event: Event) {
  const input = event.target as HTMLInputElement
  const selected = input.files?.[0]
  input.value = ''
  if (!selected || disposed) return
  if (!ready.value || pickerKey !== props.connectionKey || busy.value || uploadLocked.value) {
    uploadValidation.value = 'connectionChanged'
    return
  }
  file.value = selected
  uploadValidation.value = selected.size ? '' : 'emptyFile'
}

async function focusMode(value: Mode) {
  if (disposed) return
  if (!busy.value || active.value === value) mode.value = value
  await nextTick()
  if (disposed) return
  if (busy.value || !ready.value || mode.value === 'upload' && uploadLocked.value) panel.value?.focus()
  else if (mode.value === 'upload') chooseButton.value?.focus()
  else downloadInput.value?.focus()
}
function focusUpload() { void focusMode('upload') }
function focusDownload() { void focusMode('download') }
defineExpose({ focusUpload, focusDownload })

function prepareUpload() {
  if (busy.value || (uploadState.value === 'uncertain' && !reviewed.value)) return
  uploadState.value = 'idle'
  uploadProblem.value = null
  uploadValidation.value = ''
  uploadProgress.value = { loaded: 0 }
  uploadTarget.value = ''
  uploadHost.value = ''
  uploadFilename.value = ''
  reviewed.value = false
  overwriteAccepted.value = false
  file.value = null
  if (fileInput.value) fileInput.value.value = ''
  focusUpload()
}

async function upload() {
  if (busy.value || uploadLocked.value || disposed) return
  uploadValidation.value = !ready.value ? 'missingConnection' : !file.value ? 'invalidFile'
    : file.value.size === 0 ? 'emptyFile' : !validPath(uploadPath.value) ? 'pathRequired'
      : !overwriteAccepted.value ? 'confirmRequired' : ''
  if (uploadValidation.value || !props.credentials || !file.value) return
  const credentials = { ...props.credentials }
  const sourceFile = file.value
  const path = uploadPath.value
  const current = ++sequence
  const request = new AbortController()
  controller = request
  uploadTarget.value = destination.value
  uploadHost.value = describeTarget(credentials)
  uploadFilename.value = sourceFile.name
  uploadProblem.value = null
  uploadProgress.value = { loaded: 0 }
  reviewed.value = false
  uploadState.value = 'uploading'
  active.value = 'upload'
  cancelling.value = false
  const isCurrent = () => !disposed && current === sequence && controller === request
  try {
    await uploadSftpFile(credentials, path, sourceFile, {
      signal: request.signal,
      onProgress: (value) => { if (isCurrent() && !request.signal.aborted) uploadProgress.value = value },
    })
    if (!isCurrent()) return
    uploadState.value = 'success'
  } catch (cause) {
    if (!isCurrent()) return
    const error = sftpError(cause)
    uploadProblem.value = error
    uploadState.value = error.writeAttempted ? 'uncertain' : 'failed'
  } finally {
    // No credentials are copied into progress/result records or persistent state.
    credentials.password = ''
    if (isCurrent()) {
      controller = undefined
      active.value = null
      cancelling.value = false
    }
  }
}

function revokeUrl(url: string) {
  const timer = objectUrls.get(url)
  if (timer !== undefined) clearTimeout(timer)
  objectUrls.delete(url)
  URL.revokeObjectURL(url)
}
function saveReceivedFile() {
  if (disposed || !receivedFile.value) return
  let url = ''
  let link: HTMLAnchorElement | undefined
  try {
    const result = receivedFile.value
    url = URL.createObjectURL(result.blob)
    link = document.createElement('a')
    link.href = url
    link.download = result.filename
    link.style.display = 'none'
    document.body.appendChild(link)
    link.click()
    downloadState.value = 'done'
    receivedFile.value = null
    // Retain the URL briefly so the browser can consume it after the click.
    objectUrls.set(url, setTimeout(() => revokeUrl(url), 30000))
  } catch {
    if (url) revokeUrl(url)
    downloadState.value = 'saveFailed'
  } finally { link?.remove() }
}

async function download() {
  if (busy.value || disposed) return
  downloadValidation.value = !ready.value ? 'missingConnection' : !validPath(downloadPath.value) ? 'pathRequired' : ''
  if (downloadValidation.value || !props.credentials) return
  const credentials = { ...props.credentials }
  const path = downloadPath.value
  const current = ++sequence
  const request = new AbortController()
  controller = request
  downloadTarget.value = path
  downloadHost.value = describeTarget(credentials)
  downloadFilename.value = ''
  receivedSize.value = 0
  receivedFile.value = null
  downloadProblem.value = null
  downloadProgress.value = { loaded: 0 }
  downloadState.value = 'downloading'
  active.value = 'download'
  cancelling.value = false
  const isCurrent = () => !disposed && current === sequence && controller === request
  try {
    const result = await downloadSftpFile(credentials, path, {
      signal: request.signal,
      onProgress: (value) => { if (isCurrent() && !request.signal.aborted) downloadProgress.value = value },
    })
    if (!isCurrent()) return
    receivedSize.value = result.blob.size
    downloadFilename.value = result.filename
    receivedFile.value = result
    saveReceivedFile()
  } catch (cause) {
    if (!isCurrent()) return
    const error = sftpError(cause)
    downloadProblem.value = error
    downloadState.value = error.key === 'cancelled' ? 'cancelled' : 'failed'
  } finally {
    credentials.password = ''
    if (isCurrent()) {
      controller = undefined
      active.value = null
      cancelling.value = false
    }
  }
}

function cancelTransfer() {
  if (!busy.value || cancelling.value) return
  cancelling.value = true
  controller?.abort()
}

watch([file, uploadPath], () => {
  overwriteAccepted.value = false
  uploadValidation.value = ''
  if (uploadState.value === 'failed') { uploadState.value = 'idle'; uploadProblem.value = null }
}, { flush: 'sync' })
watch(downloadPath, () => { downloadValidation.value = '' })
watch(() => props.connectionKey, () => {
  // A picker opened for an older connection may still emit change later. Its key
  // check rejects that file. Existing transfers keep their own credential snapshot.
  file.value = null
  uploadPath.value = ''
  downloadPath.value = ''
  overwriteAccepted.value = false
  uploadValidation.value = ''
  downloadValidation.value = ''
  if (fileInput.value) fileInput.value.value = ''
})
watch(busy, (value) => emit('busy', value), { immediate: true, flush: 'sync' })
onBeforeUnmount(() => {
  disposed = true
  ++sequence
  controller?.abort()
  controller = undefined
  active.value = null
  file.value = null
  receivedFile.value = null
  for (const url of objectUrls.keys()) revokeUrl(url)
})
</script>

<template>
  <section ref="panel" class="sftp-panel" tabindex="-1" :aria-label="t('sftp.title')" :aria-busy="busy">
    <div v-if="targetLabel" class="sftp-target"><span>{{ t('sftp.target') }}</span><strong>{{ targetLabel }}</strong></div>
    <div v-if="!ready" class="sftp-notice" role="status">
      <strong>{{ t('sftp.disconnected') }}</strong>
      <p>{{ t(busy ? 'sftp.independentHint' : 'sftp.disconnectedHint') }}</p>
    </div>
    <div class="sftp-modes" role="group" :aria-label="t('sftp.title')">
      <button type="button" :class="{ selected: mode === 'upload' }" :aria-pressed="mode === 'upload'" :disabled="busy && active !== 'upload'" @click="focusUpload">{{ t('sftp.uploadTab') }}</button>
      <button type="button" :class="{ selected: mode === 'download' }" :aria-pressed="mode === 'download'" :disabled="busy && active !== 'download'" @click="focusDownload">{{ t('sftp.downloadTab') }}</button>
    </div>

    <form v-show="mode === 'upload'" class="sftp-form" @submit.prevent="upload">
      <input ref="fileInput" type="file" hidden @change="selectedFile" />
      <div class="sftp-file">
        <i class="i-mdi-file-outline" aria-hidden="true" />
        <div><strong v-if="file" :title="file.name">{{ file.name }}</strong><span v-else>{{ t('sftp.noFile') }}</span><small v-if="file">{{ bytes(file.size) }}</small></div>
        <button v-if="file" class="sftp-icon" type="button" :disabled="busy || uploadLocked" :title="t('sftp.removeFile')" :aria-label="t('sftp.removeFile')" @click="clearFile"><i class="i-mdi-close" aria-hidden="true" /></button>
      </div>
      <button ref="chooseButton" class="sftp-button" type="button" :disabled="!ready || busy || uploadLocked" @click="chooseFile"><i class="i-mdi-file-search-outline" aria-hidden="true" />{{ t(file ? 'sftp.replaceFile' : 'sftp.chooseFile') }}</button>
      <label class="sftp-field"><span>{{ t('sftp.uploadPath') }}</span><input v-model="uploadPath" type="text" :placeholder="t('sftp.uploadPlaceholder')" :disabled="!ready || busy || uploadLocked" autocomplete="off" spellcheck="false" /></label>
      <p class="sftp-hint">{{ t('sftp.uploadPathHint') }}</p>
      <p class="sftp-hint">{{ t('sftp.defaultLimit') }}</p>
      <div v-if="destination && !uploadLocked" class="sftp-destination"><span>{{ t('sftp.targetFile') }}</span><code>{{ destination }}</code></div>
      <label v-if="!uploadLocked" class="sftp-check"><input v-model="overwriteAccepted" type="checkbox" :disabled="!ready || busy" /><span>{{ t('sftp.overwriteConfirm') }}</span></label>
      <p v-if="uploadValidation" class="sftp-error" role="alert">{{ t(`sftp.${uploadValidation}`) }}</p>
      <button v-if="!uploadLocked" class="sftp-button sftp-primary" type="submit" :disabled="!ready || busy || !file || !overwriteAccepted"><i class="i-mdi-upload" aria-hidden="true" />{{ t('sftp.upload') }}</button>

      <PageErrorNotice v-if="visible !== false && mode === 'upload' && (uploadState === 'failed' || uploadState === 'uncertain' && uploadProblem)" :title="uploadMessage"><span>{{ uploadHost }}</span><span>{{ t('sftp.fileLabel') }}: {{ uploadFilename }}</span><span>{{ uploadTarget }}</span><p v-if="uploadProblem">{{ problemText(uploadProblem) }}</p></PageErrorNotice>
      <div v-if="uploadState !== 'idle' && uploadState !== 'failed'" class="sftp-result" :class="{ warning: uploadState === 'uncertain' }" :role="uploadState === 'uncertain' ? 'alert' : 'status'">
        <strong>{{ uploadMessage }}</strong>
        <span class="sftp-result-target">{{ uploadHost }}</span>
        <span>{{ t('sftp.fileLabel') }}: {{ uploadFilename }}</span>
        <code>{{ uploadTarget }}</code>
        <p v-if="uploadState === 'uncertain'">{{ t('sftp.uploadUnknownHint') }}</p>
      </div>
      <template v-if="uploadLocked">
        <label v-if="uploadState === 'uncertain'" class="sftp-check"><input v-model="reviewed" type="checkbox" /><span>{{ t('sftp.reviewResult') }}</span></label>
        <GhostBtn :disabled="busy || uploadState === 'uncertain' && !reviewed" @click="prepareUpload">{{ t('sftp.newUpload') }}</GhostBtn>
      </template>
    </form>

    <form v-show="mode === 'download'" class="sftp-form" @submit.prevent="download">
      <label class="sftp-field"><span>{{ t('sftp.downloadPath') }}</span><input ref="downloadInput" v-model="downloadPath" type="text" :placeholder="t('sftp.downloadPlaceholder')" :disabled="!ready || busy" autocomplete="off" spellcheck="false" /></label>
      <p class="sftp-hint">{{ t('sftp.downloadPathHint') }}</p>
      <p v-if="downloadValidation" class="sftp-error" role="alert">{{ t(`sftp.${downloadValidation}`) }}</p>
      <button class="sftp-button sftp-primary" type="submit" :disabled="!ready || busy || !downloadPath.trim()"><i class="i-mdi-download" aria-hidden="true" />{{ t('sftp.download') }}</button>
      <PageErrorNotice v-if="visible !== false && mode === 'download' && (downloadState === 'failed' || downloadState === 'saveFailed')" :title="downloadMessage"><span>{{ downloadHost }}</span><span>{{ downloadTarget }}</span><span v-if="downloadFilename">{{ downloadFilename }} · {{ t('sftp.transferred', { size: bytes(receivedSize) }) }}</span><p v-if="downloadProblem">{{ problemText(downloadProblem) }}</p><GhostBtn v-if="downloadState === 'saveFailed' && receivedFile" :disabled="busy" @click="saveReceivedFile">{{ t('sftp.saveAgain') }}</GhostBtn></PageErrorNotice>
      <div v-else-if="downloadState !== 'idle' && downloadState !== 'failed' && downloadState !== 'saveFailed'" class="sftp-result" role="status">
        <strong>{{ downloadMessage }}</strong>
        <span class="sftp-result-target">{{ downloadHost }}</span>
        <code>{{ downloadTarget }}</code>
        <span v-if="downloadFilename">{{ downloadFilename }} · {{ t('sftp.transferred', { size: bytes(receivedSize) }) }}</span>
        <p v-if="downloadProblem">{{ problemText(downloadProblem) }}</p>
      </div>
      <p class="sftp-hint">{{ t('sftp.browserSaveHint') }}</p>
    </form>

    <div v-if="busy" class="sftp-progress">
      <strong>{{ t(active === 'upload' ? 'sftp.uploadProgress' : 'sftp.downloadProgress') }}</strong>
      <progress v-if="progressPercent !== null" :value="progressPercent" max="100" :aria-label="t(active === 'upload' ? 'sftp.uploadProgress' : 'sftp.downloadProgress')" />
      <span>{{ progress.total === undefined ? bytes(progress.loaded) : t('sftp.progressAmount', { loaded: bytes(progress.loaded), total: bytes(progress.total) }) }}</span>
      <p v-if="active === 'upload'" class="sftp-hint">{{ t('sftp.progressHint') }}</p>
      <GhostBtn :disabled="cancelling" @click="cancelTransfer">{{ t(cancelling ? 'sftp.cancelling' : 'sftp.cancelTransfer') }}</GhostBtn>
    </div>
  </section>
</template>

<style scoped>
.sftp-panel { box-sizing: border-box; display: flex; flex-direction: column; gap: 14px; min-width: 0; height: 100%; overflow: auto; padding: 16px; color: var(--text-primary); background: var(--bg-card); font: var(--font-size-body)/1.47 var(--sans); }
.sftp-panel:focus-visible { outline: 2px solid var(--brand); outline-offset: -2px; }
.sftp-heading h3 { margin: 0; font-size: var(--font-size-section); font-weight: 600; }
.sftp-target, .sftp-destination { display: grid; gap: 4px; min-width: 0; }
.sftp-target > span, .sftp-destination > span { font-size: var(--font-size-secondary); color: var(--text-secondary); }
.sftp-target strong, .sftp-result-target { overflow-wrap: anywhere; }
.sftp-modes { display: flex; gap: 4px; padding: 4px; border-radius: 12px; background: var(--bg-search); }
.sftp-modes button { flex: 1; min-width: 0; border: 0; border-radius: 9px; padding: 7px 10px; background: transparent; color: var(--text-primary); font: inherit; cursor: pointer; }
.sftp-modes button.selected { background: var(--bg-card); box-shadow: var(--shadow-card); font-weight: 600; }
.sftp-form { display: flex; flex-direction: column; gap: 12px; min-width: 0; }
.sftp-panel :deep(.btn) { max-width: 100%; white-space: normal; text-align: center; }
.sftp-field { display: flex; flex-direction: column; gap: 7px; min-width: 0; }
.sftp-field input { box-sizing: border-box; width: 100%; min-width: 0; padding: 9px 11px; border: 1px solid var(--border); border-radius: 10px; color: var(--text-primary); background: var(--bg-card); font: inherit; }
.sftp-field input::placeholder { color: var(--text-muted); opacity: 1; }
.sftp-field input:focus-visible { outline: 2px solid var(--brand); outline-offset: 1px; }
.sftp-field input:disabled { background: var(--bg-search); cursor: not-allowed; }
.sftp-hint, .sftp-notice p { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; }
.sftp-file { display: flex; gap: 10px; align-items: center; padding: 12px; border: 1px dashed var(--border); border-radius: 12px; min-width: 0; }
.sftp-file > i { flex-shrink: 0; font-size: 20px; }
.sftp-file > div { flex: 1; min-width: 0; }
.sftp-file strong { display: block; overflow-wrap: anywhere; font-weight: 500; }
.sftp-file small { display: block; margin-top: 4px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.sftp-button { display: flex; align-items: center; justify-content: center; gap: 6px; min-height: 36px; padding: 8px 12px; border: 1px solid var(--border); border-radius: var(--r-pill); color: var(--text-primary); background: var(--bg-card); font: inherit; cursor: pointer; }
.sftp-button:hover:not(:disabled) { background: var(--bg-hover); }
.sftp-primary { border-color: var(--brand); background: var(--brand); color: var(--nav-active-fg); }
.sftp-primary:hover:not(:disabled) { background: var(--brand-hover); border-color: var(--brand-hover); }
.sftp-icon { display: grid; place-items: center; width: 30px; height: 30px; flex-shrink: 0; border: 0; border-radius: 50%; color: var(--text-primary); background: transparent; font-size: 18px; cursor: pointer; }
.sftp-icon:hover:not(:disabled) { background: var(--bg-hover); }
.sftp-button:disabled, .sftp-icon:disabled, .sftp-modes button:disabled { cursor: not-allowed; opacity: .55; }
.sftp-button:focus-visible, .sftp-icon:focus-visible, .sftp-modes button:focus-visible, .sftp-check input:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.sftp-check { display: flex; align-items: flex-start; gap: 8px; line-height: 1.6; }
.sftp-check input { flex-shrink: 0; margin: 4px 0 0; accent-color: var(--brand); }
.sftp-destination { padding: 10px 12px; border-radius: 10px; background: var(--bg-search); }
.sftp-destination code, .sftp-result code { color: var(--text-primary); font: inherit; white-space: pre-wrap; overflow-wrap: anywhere; }
.sftp-error { margin: 0; color: var(--status-danger); font-size: var(--font-size-secondary); }
.sftp-notice, .sftp-result { display: grid; gap: 7px; padding: 12px; border: 1px solid var(--border); border-radius: 12px; background: var(--bg-search); overflow-wrap: anywhere; }
.sftp-notice strong, .sftp-result strong { font-weight: 600; }
.sftp-result p { margin: 0; font-size: var(--font-size-secondary); line-height: 1.6; }
.sftp-result > span { font-size: var(--font-size-secondary); }
.sftp-result.warning { border-color: var(--status-warn); }
.sftp-progress { display: grid; gap: 9px; padding-top: 14px; border-top: 1px solid var(--border); }
.sftp-progress strong { font-weight: 500; }
.sftp-progress > span { font-size: var(--font-size-secondary); font-variant-numeric: tabular-nums; }
.sftp-progress progress { appearance: none; display: block; width: 100%; height: 6px; overflow: hidden; border: 0; border-radius: var(--r-pill); background: var(--bg-search); accent-color: var(--brand); }
.sftp-progress progress::-webkit-progress-bar { background: var(--bg-search); }
.sftp-progress progress::-webkit-progress-value { background: var(--brand); }
.sftp-progress progress::-moz-progress-bar { background: var(--brand); }
</style>
