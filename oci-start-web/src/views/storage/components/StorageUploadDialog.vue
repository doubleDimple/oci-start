<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, markRaw, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import {
  abortStorageMultipart, commitStorageMultipart, initiateStorageMultipart, listStorageResumableUploads,
  storageError, uploadStorageObject, uploadStoragePart,
  STORAGE_MULTIPART_CHUNK_SIZE as CHUNK_SIZE,
  type StorageBucketContext, type StorageMultipartPart, type StorageMultipartRecord, type StorageUploadProgress,
} from '@/api/objectStorage'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { mobileRecordParents, mobileRecordSelection } from '@/composables/useMobileRecords'

const props = defineProps<{ modelValue: boolean; context: StorageBucketContext | null }>()
const emit = defineEmits<{ 'update:modelValue': [value: boolean]; busy: [value: boolean]; changed: [] }>()
const { t, n, locale } = useI18n()
const route = useRoute(), router = useRouter(), compact = useCompactViewport()
const taskSessionKey = Array.from(crypto.getRandomValues(new Uint32Array(3)), value => value.toString(36)).join('-')
// The shared chunk size follows application.yml's per-file multipart limit.
type Failure = ReturnType<typeof storageError>
type State = 'queued' | 'needsFile' | 'ready' | 'checking' | 'initiating' | 'uploading' | 'paused' | 'committing' | 'completed' | 'aborting' | 'cancelled' | 'unknown' | 'failed' | 'unavailable'
type Stage = '' | 'check' | 'single' | 'initiate' | 'part' | 'commit' | 'abort'
interface UploadTask {
  id: number
  context: StorageBucketContext
  objectName: string
  file?: File
  size: number | null
  mode: 'single' | 'multipart'
  state: State
  uploadId: string
  chunkSize: number | null
  totalParts: number | null
  parts: StorageMultipartPart[]
  sourceConfirmed: boolean
  resumed: boolean
  currentPart: number
  transferRatio: number | null
  request: '' | 'pause' | 'cancel'
  failureStage: Stage
  failure: Failure | null
  issue: string
}
const session = ref<StorageBucketContext | null>(null)
const tasks = ref<UploadTask[]>([])
const records = ref<StorageMultipartRecord[]>([])
const recordsLoading = ref(false)
const recordsLoaded = ref(false)
const recordsFailure = ref<Failure | null>(null)
const busy = ref(false)
const currentTaskId = ref<number | null>(null)
const confirmCancelId = ref<number | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)
const sourceInput = ref<HTMLInputElement | null>(null)
const sourceTarget = ref<number | null>(null)
const notice = ref<{ key: string; name?: string } | null>(null)
const availableRecords = computed(() => records.value.filter((record) => !tasks.value.some((task) => task.uploadId === record.uploadId)))
const recordListId = computed(() => `storage-upload-records-${encodeURIComponent(contextKey(session.value))}`)
const taskListId = computed(() => `storage-upload-tasks-${encodeURIComponent(contextKey(session.value))}`)
const selectedRecord = computed(() => mobileRecordSelection(route.query, recordListId.value))
const selectedTask = computed(() => mobileRecordSelection(route.query, taskListId.value))
// Local file tasks cannot survive refresh; a per-session key must never match
// a different file that happens to receive the same incrementing task ID.
function taskRecordKey(task: UploadTask) { return `${taskSessionKey}-${task.id}` }
function showMobileTask(task: UploadTask) {
  if (!compact.value) return
  const parents = mobileRecordParents(route.query).filter(value => !value.startsWith(`${recordListId.value}:`) && !value.startsWith(`${taskListId.value}:`))
  void router.replace({ query: { ...route.query, mobileRecord: `${taskListId.value}:${taskRecordKey(task)}`, mobileRecordParents: parents.length ? parents : undefined }, hash: route.hash })
}
const completedCount = computed(() => tasks.value.filter((task) => task.state === 'completed').length)
const queuedTasks = computed(() => tasks.value.filter((task) => ['queued', 'ready'].includes(task.state) && canRun(task)))
const totalBytes = computed(() => {
  if (tasks.value.some((task) => task.size === null)) return null
  const sum = tasks.value.reduce((total, task) => total + task.size!, 0)
  return Number.isSafeInteger(sum) ? sum : null
})
const acknowledgedBytes = computed(() => {
  if (tasks.value.some((task) => task.size === null || (task.parts.length && task.chunkSize === null))) return null
  const sum = tasks.value.reduce((total, task) => total + acknowledged(task), 0)
  return Number.isSafeInteger(sum) ? sum : null
})
let nextTaskId = 1
let readRevision = 0
let readController: AbortController | undefined
let preflightController: AbortController | undefined
let singleController: AbortController | undefined
let fileSelectionContext = ''
let sourceSelectionContext = ''
let disposed = false

function contextKey(value: StorageBucketContext | null) {
  return value ? JSON.stringify([value.tenantId, value.namespace, value.bucketName]) : ''
}
function positive(value: number | null): value is number { return value !== null && Number.isSafeInteger(value) && value > 0 }
function sizeText(value: number | null) {
  if (value === null) return '—'
  if (value < 1024) return `${n(value)} B`
  const units = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB']
  const power = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length)
  return `${new Intl.NumberFormat(locale.value, { maximumFractionDigits: 1 }).format(value / 1024 ** power)} ${units[power - 1]}`
}
function failureText(value: Failure | null) {
  if (!value) return ''
  const key = ['invalidResponse', 'invalidInput', 'timeout', 'cancelled'].includes(value.key) ? value.key : 'requestFailed'
  return value.detail || t(`storageUpload.errors.${key}`)
}
function recordDate(value: string) {
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/)
  if (!match) return value || '—'
  const [year, month, day, hour, minute, second] = match.slice(1).map(Number)
  const date = new Date(0)
  date.setUTCFullYear(year!, month! - 1, day!)
  date.setUTCHours(hour!, minute!, second!, 0)
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month! - 1 || date.getUTCDate() !== day
    || date.getUTCHours() !== hour || date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second) return value
  // The server value has no timezone. UTC is only a formatting container here;
  // preserve its original wall-clock components instead of converting timezones.
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'medium', timeZone: 'UTC' }).format(date)
}
function setBusy(value: boolean) { busy.value = value; emit('busy', value) }
function sameContext(record: StorageMultipartRecord, context: StorageBucketContext) {
  return record.namespace === context.namespace && record.bucketName === context.bucketName
}
function metadataProblem(size: number | null, chunk: number | null, count: number | null, parts: StorageMultipartPart[]) {
  if (!positive(size) || !positive(chunk) || !positive(count) || Math.ceil(size / chunk) !== count
    || new Set(parts.map((part) => part.partNum)).size !== parts.length
    || parts.some((part) => !Number.isSafeInteger(part.partNum) || part.partNum < 1 || part.partNum > count || !part.etag)) return 'invalidRecord'
  return chunk > CHUNK_SIZE ? 'chunkLimit' : ''
}
function recordProblem(record: StorageMultipartRecord) {
  return metadataProblem(record.totalSize, record.chunkSize, record.totalParts, record.completedParts)
}
function matchesSource(task: UploadTask, file: File) {
  return file.size === task.size && (file.name === task.objectName || file.name === task.objectName.split('/').pop())
}
function acknowledged(task: UploadTask) {
  if (task.state === 'completed') return task.size || 0
  if (task.mode !== 'multipart' || !positive(task.size) || !positive(task.chunkSize)) return 0
  const size = task.size
  const chunkSize = task.chunkSize
  return Math.min(size, task.parts.reduce((sum, part) => sum + Math.max(0, Math.min(chunkSize, size - (part.partNum - 1) * chunkSize)), 0))
}
function progress(task: UploadTask) {
  if (!positive(task.size)) return 0
  let bytes = acknowledged(task)
  if (task.state === 'uploading' && task.transferRatio !== null) {
    const currentSize = task.mode === 'single' ? task.size : Math.min(task.chunkSize || 0, task.size - (task.currentPart - 1) * (task.chunkSize || 0))
    bytes += currentSize * task.transferRatio
  }
  return Math.min(100, Math.floor(bytes / task.size * 100))
}
function progressLabel(task: UploadTask) {
  if (task.state !== 'uploading') return t(`storageUpload.states.${task.state}`)
  if (task.transferRatio === null) return t('storageUpload.progressUnknown')
  if (task.transferRatio >= 1) return t('storageUpload.waitingAck')
  return t('storageUpload.transferred', { percent: n(progress(task)) })
}
function writeHint(task: UploadTask) {
  if (task.issue === 'singleStopped') return t('storageUpload.singleStopped')
  const key = task.failureStage === 'initiate' ? 'initUnknown' : task.failureStage === 'commit' ? 'commitUnknown' : task.failureStage === 'abort' ? 'abortUnknown' : 'unknownHint'
  return t(`storageUpload.${key}`)
}
function canRun(task: UploadTask) {
  if (!task.file || !positive(task.size)) return false
  if (!['queued', 'ready', 'paused', 'failed'].includes(task.state) && !(task.state === 'unknown' && task.failureStage === 'part')) return false
  if (task.mode === 'multipart' && (metadataProblem(task.size, task.chunkSize, task.totalParts, task.parts) || !task.sourceConfirmed)) return false
  return true
}
function canReselect(task: UploadTask) {
  return !busy.value && task.mode === 'multipart' && !!task.uploadId
    && !['completed', 'cancelled'].includes(task.state) && !['commit', 'abort'].includes(task.failureStage)
}
function canCancel(task: UploadTask) {
  return task.mode === 'multipart' && !['completed', 'cancelled', 'committing', 'aborting'].includes(task.state)
    && (!!task.uploadId || task.state === 'initiating') && (!busy.value || currentTaskId.value === task.id)
}
function canRemove(task: UploadTask) {
  return !task.uploadId && ['', 'check'].includes(task.failureStage) && ['queued', 'needsFile', 'paused', 'failed', 'unavailable'].includes(task.state)
}
function cancellationRequested(task: UploadTask) { return task.request === 'cancel' }
function makeTask(objectName: string, file?: File): UploadTask {
  const mode = file && file.size < CHUNK_SIZE ? 'single' : 'multipart'
  const task: UploadTask = {
    id: nextTaskId++, context: { ...session.value! }, objectName, file: file ? markRaw(file) : undefined,
    size: file?.size ?? null, mode, state: file ? 'queued' : 'needsFile', uploadId: '',
    chunkSize: mode === 'multipart' ? CHUNK_SIZE : null,
    totalParts: file && mode === 'multipart' ? Math.ceil(file.size / CHUNK_SIZE) : null,
    parts: [], sourceConfirmed: true, resumed: false, currentPart: 0, transferRatio: null,
    request: '', failureStage: '', failure: null, issue: '',
  }
  tasks.value.push(task)
  return tasks.value[tasks.value.length - 1]!
}
function attachRecord(task: UploadTask, record: StorageMultipartRecord) {
  task.objectName = record.objectName
  task.uploadId = record.uploadId
  task.mode = 'multipart'
  task.size = record.totalSize
  task.chunkSize = record.chunkSize
  task.totalParts = record.totalParts
  task.parts = record.completedParts.map((part) => ({ ...part }))
  task.resumed = true
  task.sourceConfirmed = false
  task.failure = null
  task.failureStage = ''
  task.issue = recordProblem(record)
  if (task.file && !matchesSource(task, task.file)) task.file = undefined
  task.state = task.issue ? 'unavailable' : task.file ? 'ready' : 'needsFile'
}
function taskForRecord(record: StorageMultipartRecord) {
  if (!session.value || !sameContext(record, session.value)) return null
  const known = tasks.value.find((task) => task.uploadId === record.uploadId)
  if (known) return known
  const pendingInit = tasks.value.find((task) => task.objectName === record.objectName && !task.uploadId && task.failureStage === 'initiate')
  const task = pendingInit || makeTask(record.objectName)
  attachRecord(task, record)
  return task
}
function chooseSource(task: UploadTask) {
  if (!canReselect(task) || metadataProblem(task.size, task.chunkSize, task.totalParts, task.parts)) return
  sourceTarget.value = task.id
  task.resumed = true
  sourceSelectionContext = contextKey(session.value)
  sourceInput.value?.click()
}
function chooseFiles() {
  if (busy.value || !session.value || !recordsLoaded.value || recordsFailure.value) return
  fileSelectionContext = contextKey(session.value)
  fileInput.value?.click()
}
function chooseRecord(record: StorageMultipartRecord) {
  if (busy.value || recordProblem(record)) return
  const task = taskForRecord(record)
  if (task) { chooseSource(task); showMobileTask(task) }
}
function onSourceSelected(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  const task = tasks.value.find((item) => item.id === sourceTarget.value)
  const expectedContext = sourceSelectionContext
  sourceTarget.value = null
  sourceSelectionContext = ''
  if (!file || !task || busy.value || !props.modelValue || !expectedContext
    || expectedContext !== contextKey(session.value) || expectedContext !== contextKey(props.context)
    || expectedContext !== contextKey(task.context)) return
  task.sourceConfirmed = false
  if (!matchesSource(task, file)) {
    task.file = undefined
    task.issue = 'fileMismatch'
    return
  }
  task.file = markRaw(file)
  task.issue = ''
  if (['needsFile', 'unavailable'].includes(task.state)) task.state = 'ready'
}
function onFilesSelected(event: Event) {
  const input = event.target as HTMLInputElement
  const files = Array.from(input.files || [])
  input.value = ''
  const expectedContext = fileSelectionContext
  fileSelectionContext = ''
  if (busy.value || !session.value || !recordsLoaded.value || recordsFailure.value || !props.modelValue || !expectedContext
    || expectedContext !== contextKey(session.value) || expectedContext !== contextKey(props.context)) return
  notice.value = null
  for (const file of files) {
    if (!Number.isSafeInteger(file.size) || file.size <= 0) { notice.value = { key: 'validation.emptyFile', name: file.name }; continue }
    if (tasks.value.some((task) => task.objectName === file.name)) { notice.value = { key: 'validation.duplicate', name: file.name }; continue }
    const sameName = records.value.filter((record) => record.objectName === file.name)
    if (sameName.length > 1) { notice.value = { key: 'validation.recordConflict' }; continue }
    const task = makeTask(file.name, file)
    if (sameName[0]) {
      attachRecord(task, sameName[0])
      notice.value = { key: 'sameNameRecord' }
    }
  }
}
function removeQueued(task: UploadTask) {
  if (busy.value || !canRemove(task)) return
  tasks.value = tasks.value.filter((item) => item.id !== task.id)
}
function clearFinished() {
  if (!busy.value) tasks.value = tasks.value.filter((task) => !['completed', 'cancelled'].includes(task.state))
}
function stopRead() { ++readRevision; readController?.abort(); recordsLoading.value = false }
async function refreshRecords() {
  if (!session.value || busy.value) return
  stopRead()
  const revision = ++readRevision
  const controller = new AbortController()
  readController = controller
  recordsLoading.value = true
  recordsFailure.value = null
  recordsLoaded.value = false
  try {
    const response = await listStorageResumableUploads({ ...session.value }, controller.signal)
    if (disposed || revision !== readRevision || !props.modelValue) return
    records.value = response
    recordsLoaded.value = true
  } catch (cause) {
    if (!disposed && revision === readRevision && !controller.signal.aborted) recordsFailure.value = storageError(cause)
  } finally {
    if (!disposed && revision === readRevision) recordsLoading.value = false
  }
}

function multipartContext(task: UploadTask) {
  return { ...task.context, objectName: task.objectName, uploadId: task.uploadId }
}
function onProgress(task: UploadTask, value: StorageUploadProgress, partNumber = 0) {
  if (disposed || task.state !== 'uploading' || task.currentPart !== partNumber) return
  task.transferRatio = value.total && value.total > 0 ? Math.min(1, Math.max(0, value.loaded / value.total)) : null
}
async function abortTask(task: UploadTask) {
  if (!task.uploadId || disposed) return
  task.state = 'aborting'
  task.failureStage = 'abort'
  task.failure = null
  task.request = ''
  try {
    await abortStorageMultipart(multipartContext(task))
    if (disposed) return
    task.state = 'cancelled'
    task.parts = []
    task.file = undefined
    task.failureStage = ''
    task.issue = ''
    records.value = records.value.filter((record) => record.uploadId !== task.uploadId)
  } catch (cause) {
    if (!disposed) { task.state = 'unknown'; task.failure = storageError(cause) }
  } finally {
    if (!disposed) emit('changed')
  }
}
async function honorRequest(task: UploadTask) {
  if (disposed) return true
  if (task.request === 'cancel') { await abortTask(task); return true }
  if (task.request === 'pause') { task.state = 'paused'; task.request = ''; task.transferRatio = null; return true }
  return false
}
async function perform(task: UploadTask) {
  task.request = ''
  task.failure = null
  task.issue = ''
  task.currentPart = 0
  task.transferRatio = null
  task.state = 'checking'
  task.failureStage = 'check'
  try {
    // Read immediately before starting. Initiate destroys same-name old uploads,
    // so a pre-existing record must be chosen explicitly instead of recreated.
    const controller = new AbortController()
    preflightController = controller
    const latest = await listStorageResumableUploads(task.context, controller.signal)
    if (disposed) return
    records.value = latest
    recordsLoaded.value = true
    recordsFailure.value = null
    if (task.uploadId) {
      const record = latest.find((item) => item.uploadId === task.uploadId)
      if (!record) { task.state = 'unavailable'; task.issue = 'missingRecord'; return }
      if (record.objectName !== task.objectName || !sameContext(record, task.context)
        || record.totalSize !== task.size || record.chunkSize !== task.chunkSize || record.totalParts !== task.totalParts) {
        task.state = 'unavailable'; task.issue = 'changedRecord'; return
      }
      const parts = new Map(task.parts.map((part) => [part.partNum, part]))
      for (const part of record.completedParts) parts.set(part.partNum, { ...part })
      task.parts = [...parts.values()].sort((a, b) => a.partNum - b.partNum)
      task.issue = metadataProblem(task.size, task.chunkSize, task.totalParts, task.parts)
      if (task.issue) { task.state = 'unavailable'; return }
    } else {
      const sameName = latest.filter((record) => record.objectName === task.objectName)
      if (sameName.length > 1) { task.state = 'unavailable'; task.issue = 'recordConflict'; return }
      if (sameName[0]) { attachRecord(task, sameName[0]); notice.value = { key: 'sameNameRecord' }; return }
    }
    if (await honorRequest(task)) return
    if (task.mode === 'single') {
      task.state = 'uploading'
      task.failureStage = 'single'
      const controller = new AbortController()
      singleController = controller
      await uploadStorageObject(task.context, task.file!, { objectName: task.objectName, signal: controller.signal, onProgress: (value) => onProgress(task, value) })
      if (disposed) return
      task.state = 'completed'
      task.failureStage = ''
      task.issue = ''
      task.transferRatio = 1
      emit('changed')
      return
    }
    if (!task.uploadId) {
      task.state = 'initiating'
      task.failureStage = 'initiate'
      const result = await initiateStorageMultipart({ ...task.context, objectName: task.objectName, contentType: task.file!.type || 'application/octet-stream', totalSize: task.size!, chunkSize: task.chunkSize! })
      if (disposed) return
      task.uploadId = result.uploadId
    }
    // Skip every acknowledged part, including non-contiguous completed parts.
    for (let partNumber = 1; partNumber <= task.totalParts!; partNumber++) {
      if (await honorRequest(task)) return
      if (task.parts.some((part) => part.partNum === partNumber)) continue
      const start = (partNumber - 1) * task.chunkSize!
      const chunk = task.file!.slice(start, Math.min(start + task.chunkSize!, task.size!))
      task.state = 'uploading'
      task.failureStage = 'part'
      task.currentPart = partNumber
      task.transferRatio = null
      // Pausing/cancelling waits for this response; aborting its HTTP request
      // cannot prove that OCI stopped writing the part.
      const result = await uploadStoragePart({ ...multipartContext(task), partNumber }, chunk, { onProgress: (value) => onProgress(task, value, partNumber) })
      if (disposed) return
      const parts = new Map(task.parts.map((part) => [part.partNum, part]))
      parts.set(result.partNum, result)
      task.parts = [...parts.values()].sort((a, b) => a.partNum - b.partNum)
      task.transferRatio = null
    }
    if (await honorRequest(task)) return
    task.state = 'committing'
    task.failureStage = 'commit'
    await commitStorageMultipart({ ...multipartContext(task), parts: task.parts.map((part) => ({ ...part })) })
    if (disposed) return
    task.state = 'completed'
    task.failureStage = ''
    records.value = records.value.filter((record) => record.uploadId !== task.uploadId)
    emit('changed')
  } catch (cause) {
    if (disposed) return
    task.failure = storageError(cause)
    task.state = task.failureStage === 'check' ? 'failed' : 'unknown'
    task.transferRatio = null
    // Even an explicit write failure can follow a cloud-side success. Do not
    // initialize or commit again automatically and always let the list refresh.
    if (task.failureStage !== 'check') emit('changed')
    if (cancellationRequested(task) && task.uploadId && task.failureStage !== 'commit') await abortTask(task)
  } finally {
    preflightController = undefined
    singleController = undefined
    task.request = ''
  }
}
async function runTasks(queue: UploadTask[]) {
  if (busy.value || !session.value || !queue.length) return
  stopRead()
  setBusy(true)
  confirmCancelId.value = null
  try {
    for (const task of queue) {
      if (disposed || !canRun(task)) break
      currentTaskId.value = task.id
      await perform(task)
      if (task.state !== 'completed') break
    }
  } finally {
    currentTaskId.value = null
    if (!disposed) setBusy(false)
  }
}
function pause(task: UploadTask) {
  if (currentTaskId.value === task.id && task.mode === 'multipart' && ['checking', 'initiating', 'uploading'].includes(task.state)) task.request = 'pause'
}
function stopSingle(task: UploadTask) {
  if (currentTaskId.value !== task.id || task.mode !== 'single' || task.state !== 'uploading') return
  task.issue = 'singleStopped'
  singleController?.abort()
}
function requestCancel(task: UploadTask) { if (canCancel(task)) confirmCancelId.value = task.id }
function requestRecordCancel(record: StorageMultipartRecord) {
  if (busy.value) return
  const task = taskForRecord(record)
  if (task) { requestCancel(task); showMobileTask(task) }
}
async function confirmCancel(task: UploadTask) {
  confirmCancelId.value = null
  if (!canCancel(task)) return
  if (busy.value) { task.request = 'cancel'; return }
  stopRead()
  setBusy(true)
  currentTaskId.value = task.id
  try { await abortTask(task) }
  finally { currentTaskId.value = null; if (!disposed) setBusy(false) }
}
function close(inspect = false) {
  if (busy.value) return
  stopRead()
  confirmCancelId.value = null
  fileSelectionContext = ''
  sourceSelectionContext = ''
  sourceTarget.value = null
  if (inspect) emit('changed')
  emit('update:modelValue', false)
}
function beforeClose(done: () => void) { if (!busy.value) { stopRead(); confirmCancelId.value = null; fileSelectionContext = ''; sourceSelectionContext = ''; sourceTarget.value = null; done() } }
function beforeUnload(event: BeforeUnloadEvent) { if (busy.value) { event.preventDefault(); event.returnValue = '' } }
window.addEventListener('beforeunload', beforeUnload)
watch(() => [props.modelValue, contextKey(props.context)] as const, ([open]) => {
  if (!open) { stopRead(); fileSelectionContext = ''; sourceSelectionContext = ''; sourceTarget.value = null; return }
  if (busy.value) return
  if (contextKey(props.context) !== contextKey(session.value)) {
    session.value = props.context ? { ...props.context } : null
    tasks.value = []
    records.value = []
    recordsLoaded.value = false
    recordsFailure.value = null
    notice.value = null
    confirmCancelId.value = null
    fileSelectionContext = ''
    sourceSelectionContext = ''
    sourceTarget.value = null
  }
  void refreshRecords()
}, { immediate: true })
onBeforeUnmount(() => {
  disposed = true
  stopRead()
  preflightController?.abort()
  window.removeEventListener('beforeunload', beforeUnload)
  // Do not send cleanup or another part on unmount. An in-flight cloud write may
  // still finish; persisted multipart records remain available for manual resume.
  emit('busy', false)
})
</script>

<template>
  <el-dialog :model-value="modelValue || busy" :title="t('storageUpload.title')" width="790px" align-center append-to-body class="storage-upload-dialog" :show-close="!busy" :close-on-click-modal="false" :close-on-press-escape="!busy" :before-close="beforeClose" @update:model-value="(value: boolean) => { if (!value) close() }">
    <input ref="fileInput" class="upload-file-input" type="file" multiple tabindex="-1" aria-hidden="true" @change="onFilesSelected">
    <input ref="sourceInput" class="upload-file-input" type="file" tabindex="-1" aria-hidden="true" @change="onSourceSelected">
    <p v-if="!session" class="upload-note">{{ t('storageUpload.chooseBucket') }}</p>
    <div v-else class="upload-workspace">
      <dl class="upload-context"><dt>{{ t('storageUpload.bucket') }}</dt><dd>{{ session.bucketName }}</dd><dt>{{ t('storageUpload.namespace') }}</dt><dd>{{ session.namespace }}</dd></dl>
      <p class="upload-note">{{ t('storageUpload.overwriteHint') }} {{ t('storageUpload.sizeHint') }}</p>
      <div class="upload-toolbar">
        <GhostBtn :disabled="busy || recordsLoading || !recordsLoaded || !!recordsFailure" @click="chooseFiles"><i class="i-mdi-plus" aria-hidden="true" />{{ t(`storageUpload.${tasks.length ? 'addFiles' : 'chooseFiles'}`) }}</GhostBtn>
        <GhostBtn :loading="recordsLoading" :disabled="busy" @click="refreshRecords">{{ t('storageUpload.refreshRecords') }}</GhostBtn>
        <GhostBtn v-if="tasks.some((task) => ['completed', 'cancelled'].includes(task.state))" :disabled="busy" @click="clearFinished">{{ t('storageUpload.clearFinished') }}</GhostBtn>
      </div>
      <p v-if="notice" class="upload-note" role="status">{{ t(`storageUpload.${notice.key}`, { name: notice.name || '' }) }}</p>
      <PageErrorNotice v-if="recordsFailure"><span>{{ failureText(recordsFailure) }}</span><GhostBtn :disabled="busy || recordsLoading" @click="refreshRecords">{{ t('storageUpload.retry') }}</GhostBtn></PageErrorNotice>
      <p v-if="recordsLoading" class="upload-note" role="status">{{ t('storageUpload.loading') }}</p>

      <section v-if="availableRecords.length || (compact && selectedRecord)" class="upload-records" :aria-label="t('storageUpload.resumable')">
        <h3>{{ t('storageUpload.resumable') }}</h3>
        <p class="upload-note">{{ t('storageUpload.recordsHint') }}</p>
        <component :is="compact ? MobileRecordList : 'div'" :class="{ 'upload-records': !compact }" v-bind="compact ? { drilldown: true, listId: recordListId, recordKeys: availableRecords.map(record => record.uploadId), loading: recordsLoading, active: modelValue || busy } : {}">
        <component :is="compact ? MobileRecordCard : 'article'" v-for="record in availableRecords" :key="record.uploadId" :class="{ 'upload-record': !compact }" v-bind="compact ? { recordKey: record.uploadId, summaryTitle: record.objectName, summaryMeta: `${sizeText(record.totalSize)} · ${t('storageUpload.recordParts', { done: n(record.completedParts.length), total: record.totalParts === null ? '—' : n(record.totalParts) })}`, summaryStatus: recordProblem(record) ? t(`storageUpload.validation.${recordProblem(record)}`) : '', summaryTone: recordProblem(record) ? 'warning' : 'neutral' } : {}">
          <div :class="{ 'upload-mobile-detail': compact }">
          <strong>{{ record.objectName }}</strong>
          <span class="upload-note">{{ sizeText(record.totalSize) }} · {{ t('storageUpload.recordParts', { done: n(record.completedParts.length), total: record.totalParts === null ? '—' : n(record.totalParts) }) }} · {{ t('storageUpload.recordedAt', { date: recordDate(record.createTime) }) }}</span>
          <p v-if="recordProblem(record)" class="upload-error">{{ t(`storageUpload.validation.${recordProblem(record)}`) }}</p>
          <div class="upload-actions"><GhostBtn :disabled="busy || !!recordProblem(record)" @click="chooseRecord(record)">{{ t('storageUpload.prepareResume') }}</GhostBtn><GhostBtn danger :disabled="busy" @click="requestRecordCancel(record)">{{ t('storageUpload.cancel') }}</GhostBtn></div>
          </div>
        </component>
        </component>
      </section>
      <p v-else-if="recordsLoaded && !recordsLoading && !recordsFailure && !tasks.length" class="upload-note">{{ t('storageUpload.noRecords') }}</p>

      <p v-if="!tasks.length" class="upload-empty">{{ t('storageUpload.emptyQueue') }}</p>
      <component :is="compact ? MobileRecordList : 'section'" v-if="tasks.length || (compact && selectedTask)" :class="{ 'upload-tasks': !compact }" :aria-label="t('storageUpload.title')" v-bind="compact ? { drilldown: true, listId: taskListId, recordKeys: tasks.map(taskRecordKey), active: modelValue || busy } : {}">
        <component :is="compact ? MobileRecordCard : 'article'" v-for="task in tasks" :key="task.id" :class="{ 'upload-task': !compact }" v-bind="compact ? { recordKey: taskRecordKey(task), summaryTitle: task.objectName, summaryMeta: `${sizeText(task.size)} · ${progressLabel(task)}`, summaryStatus: t(`storageUpload.states.${task.state}`), summaryTone: task.state === 'completed' ? 'success' : ['unknown', 'unavailable', 'failed'].includes(task.state) ? 'warning' : 'neutral' } : {}">
          <div :class="{ 'upload-mobile-detail': compact }">
          <div class="upload-task-title"><strong>{{ task.objectName }}</strong><span class="upload-state" :class="{ 'is-complete': task.state === 'completed', 'is-warning': ['unknown', 'unavailable', 'failed'].includes(task.state) }">{{ t(`storageUpload.states.${task.state}`) }}</span></div>
          <p class="upload-note">{{ sizeText(task.size) }} · {{ t(`storageUpload.${task.mode}`) }}<template v-if="task.mode === 'multipart'"> · {{ t('storageUpload.recordParts', { done: n(task.parts.length), total: task.totalParts === null ? '—' : n(task.totalParts) }) }}</template></p>
          <progress class="upload-progress" :value="task.state === 'uploading' && task.transferRatio === null ? undefined : progress(task)" max="100" :aria-label="task.objectName" />
          <div class="upload-progress-detail"><span>{{ progressLabel(task) }}</span><span v-if="task.state === 'uploading' && task.currentPart">{{ t('storageUpload.currentPart', { part: n(task.currentPart), total: task.totalParts === null ? '—' : n(task.totalParts) }) }}</span></div>
          <p v-if="task.issue && task.issue !== 'singleStopped'" class="upload-error" role="alert">{{ t(`storageUpload.validation.${task.issue}`) }}</p>
          <PageErrorNotice v-if="task.failure" :title="task.objectName">{{ failureText(task.failure) }}</PageErrorNotice>
          <p v-if="task.state === 'unknown'" class="upload-note">{{ writeHint(task) }}</p>
          <p v-if="task.state === 'committing'" class="upload-note" role="status">{{ t('storageUpload.commitHint') }}</p>
          <p v-if="task.request" class="upload-note" role="status">{{ t(`storageUpload.${task.request === 'pause' ? 'pausePending' : 'cancelPending'}`) }}</p>
          <template v-if="task.resumed && !['completed', 'cancelled'].includes(task.state)">
            <p class="upload-note">{{ task.file ? t('storageUpload.sourceSelected', { name: task.file.name }) : t('storageUpload.sourceRequired') }}</p>
            <label v-if="task.file" class="upload-source-confirm"><input v-model="task.sourceConfirmed" type="checkbox" :disabled="busy"><span>{{ t('storageUpload.sourceConfirmation') }}</span></label>
          </template>
          <div class="upload-actions">
            <GhostBtn v-if="canReselect(task)" :disabled="!!metadataProblem(task.size, task.chunkSize, task.totalParts, task.parts)" @click="chooseSource(task)">{{ t('storageUpload.reselect') }}</GhostBtn>
            <GhostBtn v-if="!['queued', 'completed', 'cancelled'].includes(task.state) && canRun(task)" :disabled="busy" @click="runTasks([task])">{{ t(`storageUpload.${task.state === 'failed' ? 'retryRead' : 'continue'}`) }}</GhostBtn>
            <GhostBtn v-if="task.mode === 'multipart' && currentTaskId === task.id && ['checking', 'initiating', 'uploading'].includes(task.state)" :disabled="!!task.request" @click="pause(task)">{{ t('storageUpload.pause') }}</GhostBtn>
            <GhostBtn v-if="task.mode === 'single' && currentTaskId === task.id && task.state === 'uploading'" danger :disabled="task.issue === 'singleStopped'" @click="stopSingle(task)">{{ t('storageUpload.stopTransfer') }}</GhostBtn>
            <GhostBtn v-if="canCancel(task)" danger :disabled="task.request === 'cancel'" @click="requestCancel(task)">{{ t('storageUpload.cancel') }}</GhostBtn>
            <GhostBtn v-if="canRemove(task)" :disabled="busy" @click="removeQueued(task)">{{ t('storageUpload.remove') }}</GhostBtn>
            <GhostBtn v-if="['unknown', 'unavailable'].includes(task.state)" :disabled="busy" @click="close(true)">{{ t('storageUpload.inspectObjects') }}</GhostBtn>
          </div>
          <div v-if="confirmCancelId === task.id" class="upload-cancel-confirm" role="alert"><strong>{{ t('storageUpload.cancelTitle') }}</strong><p>{{ t('storageUpload.cancelHint') }}</p><div class="upload-actions"><GhostBtn @click="confirmCancelId = null">{{ t('storageUpload.keep') }}</GhostBtn><GhostBtn danger :disabled="!canCancel(task)" @click="confirmCancel(task)">{{ t('storageUpload.confirmCancel') }}</GhostBtn></div></div>
          </div>
        </component>
      </component>
      <div v-if="tasks.length" class="upload-overall" role="status"><span>{{ t('storageUpload.completedCount', { done: n(completedCount), total: n(tasks.length) }) }}</span><span>{{ t('storageUpload.acknowledged', { done: sizeText(acknowledgedBytes), total: sizeText(totalBytes) }) }}</span></div>
      <p class="upload-note">{{ t('storageUpload.progressHint') }} {{ t('storageUpload.pauseHint') }}</p>
      <p class="upload-note">{{ t('storageUpload.draftHint') }}</p>
    </div>
    <template #footer><GhostBtn :disabled="busy" @click="close()">{{ t('storageUpload.close') }}</GhostBtn><PrimaryBtn :loading="busy" :disabled="!session || !queuedTasks.length || recordsLoading" @click="runTasks([...queuedTasks])">{{ t('storageUpload.start') }}</PrimaryBtn></template>
  </el-dialog>
</template>

<style>
.storage-upload-dialog { max-width: calc(100vw - 24px); padding: 24px; background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); font-size: var(--font-size-body); }
.storage-upload-dialog .el-dialog__title { color: var(--text-primary); font-size: var(--font-size-dialog-title); font-weight: 600; }
.storage-upload-dialog .el-dialog__body { max-height: min(72vh, 820px); overflow-y: auto; padding-right: 4px; color: var(--text-primary); }
.storage-upload-dialog .el-dialog__footer { display: flex; justify-content: flex-end; gap: 8px; flex-wrap: wrap; }
.storage-upload-dialog .upload-file-input { display: none; }
.storage-upload-dialog .upload-workspace { display: grid; gap: 14px; }
.storage-upload-dialog .upload-context { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 5px 12px; margin: 0; font-size: var(--font-size-body); }
.storage-upload-dialog .upload-context dt { color: var(--text-secondary); }
.storage-upload-dialog .upload-context dd { margin: 0; color: var(--text-primary); overflow-wrap: anywhere; }
.storage-upload-dialog .upload-note { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; overflow-wrap: anywhere; }
.storage-upload-dialog .upload-toolbar, .storage-upload-dialog .upload-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.storage-upload-dialog .upload-actions .btn { min-height: 34px; padding: 6px 12px; font-weight: 500; }
.storage-upload-dialog .upload-error { margin: 0; color: var(--status-danger); font-size: var(--font-size-secondary); line-height: 1.6; overflow-wrap: anywhere; }
.storage-upload-dialog .upload-records, .storage-upload-dialog .upload-tasks { display: grid; gap: 12px; }
.storage-upload-dialog .upload-records h3 { margin: 0; color: var(--text-primary); font-size: var(--font-size-section); font-weight: 600; }
.storage-upload-dialog .upload-record, .storage-upload-dialog .upload-task { display: grid; gap: 9px; min-width: 0; padding: 14px; border: 1px solid var(--border); border-radius: 14px; background: var(--bg-card); }
.storage-upload-dialog .upload-record > div, .storage-upload-dialog .upload-task > div, .storage-upload-dialog .upload-mobile-detail { display: grid; gap: 9px; min-width: 0; }
.storage-upload-dialog .upload-record strong, .storage-upload-dialog .upload-mobile-detail > strong { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; overflow-wrap: anywhere; }
.storage-upload-dialog .upload-record > strong, .storage-upload-dialog .upload-task-title > strong { min-width: 0; color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; overflow-wrap: anywhere; }
.storage-upload-dialog .upload-task-title { display: flex; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; gap: 6px 14px; }
.storage-upload-dialog .upload-state { color: var(--text-primary); font-size: var(--font-size-body); }
.storage-upload-dialog .upload-state.is-complete { color: var(--status-ok); }
.storage-upload-dialog .upload-state.is-warning { color: var(--status-warn); }
.storage-upload-dialog .upload-empty { margin: 0; padding: 24px 14px; border: 1px dashed var(--border); border-radius: 14px; text-align: center; color: var(--text-primary); font-size: var(--font-size-body); line-height: 1.6; }
.storage-upload-dialog .upload-progress { width: 100%; height: 7px; overflow: hidden; border: 0; border-radius: 999px; background: var(--bg-search); color: var(--brand); accent-color: var(--brand); }
.storage-upload-dialog .upload-progress::-webkit-progress-bar { background: var(--bg-search); border-radius: 999px; }
.storage-upload-dialog .upload-progress::-webkit-progress-value { background: var(--brand); border-radius: 999px; }
.storage-upload-dialog .upload-progress::-moz-progress-bar { background: var(--brand); border-radius: 999px; }
.storage-upload-dialog .upload-progress-detail, .storage-upload-dialog .upload-overall { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 6px 12px; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; }
.storage-upload-dialog .upload-source-confirm { display: flex; align-items: flex-start; gap: 9px; color: var(--text-primary); font-size: var(--font-size-body); line-height: 1.6; cursor: pointer; }
.storage-upload-dialog input[type="checkbox"] { width: 16px; height: 16px; margin: 4px 0 0; flex-shrink: 0; accent-color: var(--brand); }
.storage-upload-dialog input[type="checkbox"]:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.storage-upload-dialog .upload-cancel-confirm { display: grid; gap: 8px; padding: 12px; border: 1px solid var(--status-warn); border-radius: 12px; background: var(--bg-search); color: var(--text-primary); font-size: var(--font-size-body); }
.storage-upload-dialog .upload-cancel-confirm p { margin: 0; line-height: 1.6; }
@media (max-width: 580px) { .storage-upload-dialog { padding: 18px; } .storage-upload-dialog .upload-context { grid-template-columns: 1fr; } }
</style>
