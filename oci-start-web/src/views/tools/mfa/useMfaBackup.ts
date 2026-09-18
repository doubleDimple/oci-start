import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch, type Ref } from 'vue'
import {
  MfaApiError, deleteMfaEntry, exportMfaEntries, getMfaCodes, getMfaMaterial, importMfaEntries,
  isMfaId, isMfaRevision, listMfaEntries, mfaError, normalizeMfaCandidate, previewMfa,
  type MfaCandidate, type MfaCodeItem, type MfaEntry, type MfaExportEntry,
  type MfaImportResult, type MfaMaterial, type MfaPreviewInput, type MfaPreviewResult,
} from '@/api/mfaBackup'

export interface MfaMutation {
  kind: 'import' | 'delete' | null
  targetId: string | null
  pending: boolean
  outcome: 'idle' | 'success' | 'unknown' | 'failed'
  problem: MfaApiError | null
  result: MfaImportResult | null
}
function emptyMutation(): MfaMutation { return { kind: null, targetId: null, pending: false, outcome: 'idle', problem: null, result: null } }
function clearSecrets(entries: MfaCandidate[]): void { entries.forEach(entry => { entry.secretKey = '' }) }
function csvCell(value: string): string {
  // Quoting alone does not prevent a spreadsheet from evaluating a cell as a formula.
  const safe = /^[=+\-@]/.test(value.trimStart()) || /^[\t\r\n]/.test(value) ? "'" + value : value
  return '"' + safe.replace(/"/g, '""') + '"'
}

/** The page owns list pagination, drafts, confirmation and navigation. */
export function useMfaBackup(paused?: Readonly<Ref<boolean>>) {
  const rows = shallowRef<MfaEntry[]>([]), loading = ref(false), loaded = ref(false)
  const problem = shallowRef<MfaApiError | null>(null), lastUpdated = ref<number | null>(null)
  const preview = shallowRef<MfaPreviewResult | null>(null), previewLoading = ref(false)
  const previewProblem = shallowRef<MfaApiError | null>(null)
  const material = shallowRef<MfaMaterial | null>(null), materialLoading = ref(false)
  const materialProblem = shallowRef<MfaApiError | null>(null)
  const codes = shallowRef<Record<string, MfaCodeItem>>({}), codesLoading = ref(false)
  const codesProblem = shallowRef<MfaApiError | null>(null), remainingSeconds = ref(0)
  const visibleIds = shallowRef<string[]>([]), hidden = ref(document.hidden)
  const exportState = shallowRef<{ pending: boolean; problem: MfaApiError | null; count: number | null }>({ pending: false, problem: null, count: null })
  const mutation = shallowRef<MfaMutation>(emptyMutation()), requiresReview = ref(false)
  const listRevision = ref(0), reviewAfter = ref(0)
  const contextLocked = computed(() => mutation.value.pending)
  const canMutate = computed(() => loaded.value && !loading.value && !problem.value && !contextLocked.value
    && !requiresReview.value && !previewLoading.value && !materialLoading.value && !exportState.value.pending && !hidden.value)
  const reviewReady = computed(() => requiresReview.value && !contextLocked.value && loaded.value
    && !loading.value && !problem.value && listRevision.value >= reviewAfter.value)
  const rowMap = computed(() => new Map(rows.value.map(row => [row.id, row])))
  const currentIds = computed(() => visibleIds.value.filter(id => rowMap.value.has(id)))
  const codeScope = computed(() => currentIds.value.map(id => id + ':' + rowMap.value.get(id)!.revision).join('|'))
  const codesActive = computed(() => loaded.value && !loading.value && !problem.value && !hidden.value
    && !paused?.value && !contextLocked.value && currentIds.value.length > 0)
  let disposed = false, listSequence = 0, previewSequence = 0, materialSequence = 0, codeSequence = 0, exportSequence = 0
  let listController: AbortController | undefined, previewController: AbortController | undefined
  let materialController: AbortController | undefined, codeController: AbortController | undefined, exportController: AbortController | undefined
  let pollTimer: number | undefined, expiryTimer: number | undefined, clockTimer: number | undefined
  let validUntil = 0, wallUntil = 0
  const urls = new Map<string, number>()
  const writeSnapshots = new Set<MfaCandidate[]>()

  function cancelList(): void { ++listSequence; listController?.abort(); listController = undefined; loading.value = false }
  async function loadList(): Promise<void> {
    if (disposed) return
    cancelList()
    const sequence = listSequence, controller = new AbortController()
    listController = controller; loading.value = true; problem.value = null
    const current = () => !disposed && sequence === listSequence && listController === controller && !controller.signal.aborted
    try {
      const result = await listMfaEntries(controller.signal)
      if (current()) { rows.value = result; loaded.value = true; lastUpdated.value = Date.now(); ++listRevision.value }
    } catch (cause) { if (current()) problem.value = mfaError(cause) }
    finally { if (current()) { loading.value = false; listController = undefined } }
  }
  async function refresh(): Promise<void> { if (!contextLocked.value) await loadList() }
  function clearPreview(): void {
    ++previewSequence; previewController?.abort(); previewController = undefined
    if (preview.value) clearSecrets(preview.value.entries)
    preview.value = null; previewLoading.value = false; previewProblem.value = null
  }
  async function previewInput(input: MfaPreviewInput): Promise<void> {
    if (disposed || hidden.value || contextLocked.value || requiresReview.value) return
    clearPreview()
    const sequence = previewSequence, controller = new AbortController()
    previewController = controller; previewLoading.value = true
    const current = () => !disposed && !hidden.value && sequence === previewSequence && previewController === controller && !controller.signal.aborted
    try {
      const result = await previewMfa(input, controller.signal)
      if (current()) preview.value = result
      else clearSecrets(result.entries)
    } catch (cause) { if (current()) previewProblem.value = mfaError(cause) }
    finally { if (current()) { previewLoading.value = false; previewController = undefined } }
  }
  function clearMaterial(): void {
    ++materialSequence; materialController?.abort(); materialController = undefined
    if (material.value) { material.value.secretKey = ''; material.value.qrCode = '' }
    material.value = null; materialLoading.value = false; materialProblem.value = null
  }
  async function loadMaterial(id: string): Promise<void> {
    if (disposed || hidden.value || contextLocked.value || !rowMap.value.has(id)) return
    clearMaterial()
    const sequence = materialSequence, controller = new AbortController()
    materialController = controller; materialLoading.value = true
    const current = () => !disposed && !hidden.value && sequence === materialSequence && materialController === controller && !controller.signal.aborted
    try {
      const result = await getMfaMaterial(id, controller.signal)
      if (current()) material.value = result
      else { result.secretKey = ''; result.qrCode = '' }
    } catch (cause) { if (current()) materialProblem.value = mfaError(cause) }
    finally { if (current()) { materialLoading.value = false; materialController = undefined } }
  }
  function clearClock(): void {
    if (expiryTimer !== undefined) window.clearTimeout(expiryTimer)
    if (clockTimer !== undefined) window.clearInterval(clockTimer)
    expiryTimer = undefined; clockTimer = undefined; validUntil = 0; wallUntil = 0; remainingSeconds.value = 0
  }
  function expireCodes(): void {
    clearClock()
    codes.value = Object.fromEntries(Object.entries(codes.value).map(([id, value]) => [id, { ...value, code: null }]))
  }
  function cancelCodes(): void {
    ++codeSequence; codeController?.abort(); codeController = undefined
    if (pollTimer !== undefined) window.clearTimeout(pollTimer)
    pollTimer = undefined; clearClock(); codes.value = {}; codesLoading.value = false; codesProblem.value = null
  }
  function scheduleCodes(delay: number): void {
    if (disposed || !codesActive.value) return
    if (pollTimer !== undefined) window.clearTimeout(pollTimer)
    pollTimer = window.setTimeout(() => { pollTimer = undefined; void readCodes() }, Math.max(1000, delay))
  }
  function clockTick(): void {
    const remaining = Math.min(validUntil - performance.now(), wallUntil - Date.now())
    if (remaining <= 0) expireCodes()
    else remainingSeconds.value = Math.ceil(remaining / 1000)
  }
  async function readCodes(): Promise<void> {
    if (disposed || !codesActive.value || codesLoading.value) return
    const sequence = codeSequence, controller = new AbortController(), requested = [...currentIds.value]
    codeController = controller; codesLoading.value = true; codesProblem.value = null
    const started = performance.now()
    const current = () => !disposed && codesActive.value && sequence === codeSequence && codeController === controller && !controller.signal.aborted
    try {
      const result = await getMfaCodes(requested, controller.signal)
      if (!current()) return
      const now = performance.now(), lifetime = result.expiresAt - result.serverTime - (now - started)
      clearClock()
      codes.value = Object.fromEntries(result.items.map(item => [item.id, { ...item, code: lifetime > 0 ? item.code : null }]))
      if (lifetime > 0 && result.items.some(item => item.code !== null)) {
        validUntil = now + lifetime; wallUntil = Date.now() + lifetime; clockTick()
        expiryTimer = window.setTimeout(expireCodes, lifetime)
        clockTimer = window.setInterval(clockTick, 250)
      }
      // Re-read after the server's next boundary. Conservative expiry may blank the
      // preceding code slightly earlier; it never extends a code with client time.
      scheduleCodes(result.expiresAt - result.serverTime + 100)
    } catch (cause) {
      if (current()) { clearClock(); codes.value = {}; codesProblem.value = mfaError(cause); scheduleCodes(10_000) }
    } finally { if (current()) { codesLoading.value = false; codeController = undefined } }
  }
  function restartCodes(): void { cancelCodes(); if (!disposed && codesActive.value) void readCodes() }
  function setVisibleIds(values: string[]): void {
    if (!Array.isArray(values) || values.length > 100 || values.some(value => !isMfaId(value)) || new Set(values).size !== values.length) {
      visibleIds.value = []; cancelCodes(); codesProblem.value = new MfaApiError('invalidInput'); return
    }
    if (visibleIds.value.join('|') !== values.join('|')) visibleIds.value = [...values]
  }
  function codeFor(id: string): string | null {
    if (!codesActive.value || performance.now() >= validUntil || Date.now() >= wallUntil) return null
    return codes.value[id]?.code ?? null
  }
  function codeErrorFor(id: string) { return codes.value[id]?.errorKey ?? null }
  async function copyCode(id: string): Promise<boolean> {
    const code = codeFor(id)
    if (!code) return false
    try { await navigator.clipboard.writeText(code); return !disposed && codeFor(id) === code } catch { return false }
  }
  function revoke(url: string): void {
    const timer = urls.get(url)
    if (timer !== undefined) window.clearTimeout(timer)
    urls.delete(url); URL.revokeObjectURL(url)
  }
  function cancelExport(): void {
    ++exportSequence; exportController?.abort(); exportController = undefined
    exportState.value = { pending: false, problem: null, count: null }
  }
  async function exportCsv(values: string[], headers: [string, string, string]): Promise<boolean> {
    if (disposed || hidden.value || contextLocked.value || exportState.value.pending) return false
    cancelExport()
    const sequence = exportSequence, controller = new AbortController(), requested = [...values]
    exportController = controller; exportState.value = { pending: true, problem: null, count: null }
    let entries: MfaExportEntry[] = [], url: string | undefined, anchor: HTMLAnchorElement | undefined
    const current = () => !disposed && !hidden.value && sequence === exportSequence && exportController === controller && !controller.signal.aborted
    try {
      entries = await exportMfaEntries(requested, controller.signal)
      if (!current()) return false
      const text = '\uFEFF' + [headers.map(csvCell).join(','), ...entries.map(row =>
        [row.keyName, row.issuer, row.secretKey].map(csvCell).join(','))].join('\r\n') + '\r\n'
      url = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }))
      const downloadUrl = url
      urls.set(url, window.setTimeout(() => revoke(downloadUrl), 60_000))
      anchor = document.createElement('a'); anchor.href = url; anchor.download = 'oci-start_mfa_' + Date.now() + '.csv'
      anchor.hidden = true; document.body.append(anchor); anchor.click()
      exportState.value = { pending: true, problem: null, count: entries.length }
      return true
    } catch (cause) {
      if (url) revoke(url)
      if (current()) exportState.value = { pending: true, problem: url ? new MfaApiError('downloadFailed') : mfaError(cause), count: null }
      return false
    } finally {
      clearSecrets(entries); anchor?.remove()
      if (current()) { exportState.value = { ...exportState.value, pending: false }; exportController = undefined }
    }
  }
  function clearMutation(): void { if (!contextLocked.value && !requiresReview.value) mutation.value = emptyMutation() }
  function acknowledgeReview(): void {
    if (!reviewReady.value) return
    requiresReview.value = false; clearMutation()
  }
  async function perform(kind: 'import' | 'delete', targetId: string | null, send: () => Promise<MfaImportResult | null>): Promise<void> {
    if (disposed || !canMutate.value) return
    mutation.value = { kind, targetId, pending: true, outcome: 'idle', problem: null, result: null }
    cancelList(); clearMaterial(); cancelExport()
    let readBack = false
    try {
      const result = await send()
      if (disposed) return
      mutation.value = { ...mutation.value, outcome: 'success', result }; readBack = true
      if (kind === 'delete') rows.value = rows.value.filter(row => row.id !== targetId)
      else clearPreview()
    } catch (cause) {
      if (disposed) return
      const failure = mfaError(cause)
      mutation.value = { ...mutation.value, outcome: failure.writeAttempted ? 'unknown' : 'failed', problem: failure }
      if (failure.writeAttempted) { requiresReview.value = true; reviewAfter.value = listRevision.value + 1; readBack = true }
      else if (failure.key === 'conflict' || failure.key === 'notFound') readBack = true
    } finally {
      if (!disposed) {
        if (readBack) await loadList()
        if (!disposed) mutation.value = { ...mutation.value, pending: false }
      }
    }
  }
  async function importEntries(entries: MfaCandidate[]): Promise<void> {
    if (!canMutate.value || disposed) return
    let snapshot: MfaCandidate[]
    try {
      if (!Array.isArray(entries) || !entries.length || entries.length > 100) throw new MfaApiError('tooManyEntries')
      snapshot = entries.map(normalizeMfaCandidate)
    } catch (cause) { mutation.value = { ...emptyMutation(), kind: 'import', outcome: 'failed', problem: mfaError(cause) }; return }
    writeSnapshots.add(snapshot)
    try { await perform('import', null, () => importMfaEntries(snapshot)) }
    finally { clearSecrets(snapshot); writeSnapshots.delete(snapshot) }
  }
  async function removeEntry(row: MfaEntry): Promise<void> {
    if (!canMutate.value || disposed) return
    if (!isMfaId(row.id) || !isMfaRevision(row.revision) || rowMap.value.get(row.id)?.revision !== row.revision) {
      mutation.value = { ...emptyMutation(), kind: 'delete', targetId: row.id, outcome: 'failed', problem: new MfaApiError('conflict') }; return
    }
    const id = row.id, revision = row.revision
    await perform('delete', id, async () => { await deleteMfaEntry(id, revision); return null })
  }
  function visibilityChanged(): void {
    hidden.value = document.hidden
    if (hidden.value) {
      clearPreview(); clearMaterial(); cancelExport()
      for (const url of Array.from(urls.keys())) revoke(url)
    }
  }
  watch([codesActive, codeScope], restartCodes, { flush: 'sync' })
  onMounted(() => document.addEventListener('visibilitychange', visibilityChanged))
  onBeforeUnmount(() => {
    disposed = true; cancelList(); cancelCodes(); clearPreview(); clearMaterial(); cancelExport()
    writeSnapshots.forEach(clearSecrets); writeSnapshots.clear(); rows.value = []
    for (const url of Array.from(urls.keys())) revoke(url)
    document.removeEventListener('visibilitychange', visibilityChanged)
  })
  return { rows, loading, loaded, problem, lastUpdated, refresh, setVisibleIds, codesLoading, codesProblem,
    remainingSeconds, codeFor, codeErrorFor, copyCode, preview, previewLoading, previewProblem, previewInput,
    clearPreview, material, materialLoading, materialProblem, loadMaterial, clearMaterial, mutation, canMutate,
    contextLocked, importEntries, removeEntry, clearMutation, requiresReview, reviewReady, acknowledgeReview,
    exportState, exportCsv, cancelExport }
}
