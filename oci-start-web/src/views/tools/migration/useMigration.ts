import { computed, onBeforeUnmount, ref, shallowRef } from 'vue'
import {
  MigrationApiError, exportEncryptedBackup, importEncryptedBackup, migrationError,
  normalizeMigrationKey, validateMigrationFile, type MigrationExportArtifact,
  type MigrationFailureOutcome, type MigrationImportReceipt,
} from '@/api/migration'

export interface MigrationImportState {
  pending: boolean
  outcome: 'idle' | 'success' | MigrationFailureOutcome
  problem: MigrationApiError | null
  result: MigrationImportReceipt | null
}
export interface MigrationFileInfo { filename: string; size: number }
function emptyImport(): MigrationImportState { return { pending: false, outcome: 'idle', problem: null, result: null } }

/** All backup material stays in this page's memory. The page owns confirmation and navigation. */
export function useMigration() {
  const artifact = shallowRef<MigrationExportArtifact | null>(null), exportSaved = ref(false)
  const exportState = shallowRef<{ pending: boolean; problem: MigrationApiError | null }>({ pending: false, problem: null })
  const file = shallowRef<File | null>(null), masterKey = ref('')
  const fileValidating = ref(false), fileProblem = shallowRef<MigrationApiError | null>(null), fileReady = ref(false)
  const preparedImport = shallowRef<MigrationFileInfo | null>(null), importAttempt = shallowRef<MigrationFileInfo | null>(null)
  const importState = shallowRef<MigrationImportState>(emptyImport()), requiresReview = ref(false)
  const contextLocked = computed(() => importState.value.pending)
  const busy = computed(() => contextLocked.value || exportState.value.pending || fileValidating.value)
  const keyProblem = computed(() => {
    if (!masterKey.value) return null
    try { normalizeMigrationKey(masterKey.value); return null } catch (cause) { return migrationError(cause) }
  })
  const canImport = computed(() => !busy.value && !requiresReview.value && !preparedImport.value
    && importState.value.outcome === 'idle' && !!file.value && fileReady.value && !fileProblem.value
    && !!masterKey.value && !keyProblem.value)
  const canLeave = computed(() => !busy.value && !requiresReview.value && !preparedImport.value
    && (!artifact.value || exportSaved.value) && !file.value && !masterKey.value)
  let disposed = false, exportSequence = 0, fileSequence = 0
  let exportController: AbortController | undefined, fileController: AbortController | undefined
  let prepared: { file: File; key: string } | null = null
  const objectUrls = new Map<string, number>()

  function cancelExport(): void {
    ++exportSequence; exportController?.abort(); exportController = undefined
    exportState.value = { pending: false, problem: null }
  }
  async function exportBackup(): Promise<boolean> {
    if (disposed || busy.value || preparedImport.value || requiresReview.value || artifact.value) return false
    cancelExport()
    const sequence = exportSequence, controller = new AbortController()
    exportController = controller; exportState.value = { pending: true, problem: null }
    const current = () => !disposed && sequence === exportSequence && exportController === controller && !controller.signal.aborted
    try {
      const result = await exportEncryptedBackup(controller.signal)
      if (!current()) return false
      artifact.value = result; exportSaved.value = false
      return true
    } catch (cause) {
      if (current()) exportState.value = { pending: false, problem: migrationError(cause) }
      return false
    } finally {
      if (current()) { exportState.value = { ...exportState.value, pending: false }; exportController = undefined }
    }
  }
  function revoke(url: string): void {
    const timer = objectUrls.get(url)
    if (timer !== undefined) window.clearTimeout(timer)
    objectUrls.delete(url); URL.revokeObjectURL(url)
  }
  function download(blob: Blob, filename: string): boolean {
    if (disposed) return false
    let url: string | null = null, anchor: HTMLAnchorElement | null = null
    try {
      url = URL.createObjectURL(blob)
      // Keep the URL alive after the click; creating a download is not proof it was saved.
      objectUrls.set(url, window.setTimeout(() => revoke(url!), 60_000))
      anchor = document.createElement('a'); anchor.href = url; anchor.download = filename
      anchor.hidden = true; document.body.append(anchor); anchor.click()
      exportState.value = { ...exportState.value, problem: null }
      return true
    } catch {
      if (url) revoke(url)
      exportState.value = { ...exportState.value, problem: new MigrationApiError('downloadFailed') }
      return false
    } finally { anchor?.remove() }
  }
  function downloadBackup(): boolean { return artifact.value ? download(artifact.value.blob, artifact.value.filename) : false }
  function downloadKey(): boolean {
    const current = artifact.value
    return current ? download(new Blob([current.masterKey + '\n'], { type: 'text/plain;charset=utf-8' }),
      current.filename.replace(/\.enc$/i, '') + '.key.txt') : false
  }
  function ackExportSaved(value = true): void { exportSaved.value = !!artifact.value && value }
  function clearExport(): void {
    if (busy.value) return
    artifact.value = null; exportSaved.value = false; exportState.value = { pending: false, problem: null }
    for (const url of Array.from(objectUrls.keys())) revoke(url)
  }
  function cancelFileRead(): void {
    ++fileSequence; fileController?.abort(); fileController = undefined; fileValidating.value = false
  }
  async function selectFile(value: File | null): Promise<void> {
    if (disposed || contextLocked.value || preparedImport.value || requiresReview.value) return
    if (importState.value.outcome === 'rejected' || importState.value.outcome === 'rolledBack') resetImportResult()
    if (value === null || value !== file.value) masterKey.value = ''
    cancelFileRead(); file.value = value; fileReady.value = false; fileProblem.value = null
    if (!value) return
    const sequence = fileSequence, controller = new AbortController()
    fileController = controller; fileValidating.value = true
    const current = () => !disposed && sequence === fileSequence && fileController === controller && !controller.signal.aborted
    try { await validateMigrationFile(value, controller.signal); if (current()) fileReady.value = true }
    catch (cause) { if (current()) fileProblem.value = migrationError(cause) }
    finally { if (current()) { fileValidating.value = false; fileController = undefined } }
  }
  function setMasterKey(value: string): void {
    if (disposed || contextLocked.value || preparedImport.value || requiresReview.value) return
    if (importState.value.outcome === 'rejected' || importState.value.outcome === 'rolledBack') resetImportResult()
    masterKey.value = value
  }
  function prepareImport(): boolean {
    if (disposed || !canImport.value || !file.value) return false
    prepared = { file: file.value, key: normalizeMigrationKey(masterKey.value) }
    preparedImport.value = { filename: prepared.file.name, size: prepared.file.size }
    return true
  }
  function releasePreparation(): void {
    if (prepared) prepared.key = ''
    prepared = null; preparedImport.value = null
  }
  function cancelImportPreparation(): void { if (!contextLocked.value) releasePreparation() }
  async function confirmImport(): Promise<void> {
    if (disposed || contextLocked.value || requiresReview.value || !prepared) return
    const snapshot = prepared
    importAttempt.value = { filename: snapshot.file.name, size: snapshot.file.size }
    importState.value = { ...emptyImport(), pending: true }
    masterKey.value = ''
    try {
      const result = await importEncryptedBackup(snapshot.file, snapshot.key)
      if (disposed) return
      importState.value = { pending: true, outcome: 'success', problem: null, result }
      file.value = null; fileReady.value = false; fileProblem.value = null
    } catch (cause) {
      if (disposed) return
      const problem = migrationError(cause), outcome = problem.outcome ?? 'unknown'
      importState.value = { pending: true, outcome, problem, result: null }
      requiresReview.value = outcome === 'unknown'
    } finally {
      snapshot.key = ''
      releasePreparation()
      if (!disposed) importState.value = { ...importState.value, pending: false }
    }
  }
  function resetImportResult(): void {
    if (contextLocked.value || requiresReview.value || preparedImport.value) return
    importState.value = emptyImport(); importAttempt.value = null
  }
  function acknowledgeImportReviewed(): void {
    if (contextLocked.value || !requiresReview.value) return
    // No status endpoint can prove this outcome. The page explicitly asks the user
    // to inspect the destination database before allowing another deliberate import.
    cancelFileRead(); file.value = null; fileReady.value = false; fileProblem.value = null; masterKey.value = ''
    requiresReview.value = false; resetImportResult()
  }
  onBeforeUnmount(() => {
    disposed = true; cancelExport(); cancelFileRead(); releasePreparation()
    masterKey.value = ''; file.value = null; artifact.value = null
    for (const url of Array.from(objectUrls.keys())) revoke(url)
    importState.value = emptyImport(); importAttempt.value = null
  })
  return { artifact, exportState, exportSaved, exportBackup, cancelExport, downloadBackup, downloadKey,
    ackExportSaved, clearExport, file, masterKey, fileValidating, fileProblem, keyProblem, canImport,
    selectFile, setMasterKey, preparedImport, prepareImport, cancelImportPreparation, confirmImport,
    importAttempt, importState, requiresReview, acknowledgeImportReviewed, resetImportResult, contextLocked, busy, canLeave }
}
