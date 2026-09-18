<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import SecuritySecretInput from '@/views/settings/security/SecuritySecretInput.vue'
import { useMigration } from './migration/useMigration'
import './migration/migration.scss'

const { t, locale } = useI18n()
const router = useRouter()
const compact = useCompactViewport()
const currentSite = window.location.origin
const page = useMigration()
const {
  artifact, exportState, exportSaved, file, masterKey, fileValidating, fileProblem, keyProblem,
  canImport, preparedImport, importState, importAttempt, contextLocked, busy, requiresReview,
} = page
const active = ref<'export' | 'import'>('export')
const fileInput = ref<HTMLInputElement | null>(null)
const scrollArea = ref<HTMLElement | null>(null)
const sectionHeading = ref<HTMLElement | null>(null)
const confirmChecked = ref(false)
const reviewChecked = ref(false)
const dragDepth = ref(0)
const clearVisible = ref(false)
const leaveVisible = ref(false)
const downloadNotice = ref(false)
const actionLocked = computed(() => busy.value || !!preparedImport.value || clearVisible.value || leaveVisible.value)
const unsavedExport = computed(() => !!artifact.value && !exportSaved.value)
const importDraft = computed(() => !!file.value || !!masterKey.value)
const resultVisible = computed(() => importState.value.outcome === 'success' || requiresReview.value)
const tableRows = computed(() => importState.value.result?.tables ?? [])
let finishNavigation: ((value: boolean) => void) | undefined

function number(value: number) { return new Intl.NumberFormat(locale.value).format(value) }
function size(value: number) {
  if (value < 1024) return `${number(value)} B`
  const unit = value < 1024 * 1024 ? 'KiB' : 'MiB'
  return `${new Intl.NumberFormat(locale.value, { maximumFractionDigits: 2 }).format(value / (unit === 'KiB' ? 1024 : 1024 * 1024))} ${unit}`
}
function errorLabel(problem: { key: string } | null) { return problem ? t(`migration.errors.${problem.key}`) : '' }
function back() { if (window.history.state?.back) router.back(); else void router.push('/boot/dashboard') }
async function selectSection(section: 'export' | 'import') {
  if (actionLocked.value || contextLocked.value || requiresReview.value || active.value === section) return
  active.value = section; dragDepth.value = 0; downloadNotice.value = false
  await nextTick()
  if (scrollArea.value) scrollArea.value.scrollTop = 0
  sectionHeading.value?.focus({ preventScroll: true })
}
function exportTab() { void selectSection('export') }
function importTab() { void selectSection('import') }
async function generateBackup() {
  if (actionLocked.value || requiresReview.value || artifact.value) return
  downloadNotice.value = false
  await page.exportBackup()
  if (scrollArea.value) scrollArea.value.scrollTop = 0
}
async function downloadBackup() { downloadNotice.value = await page.downloadBackup() }
async function downloadKey() { downloadNotice.value = await page.downloadKey() }
function updateSaved(event: Event) { page.ackExportSaved((event.target as HTMLInputElement).checked) }
function requestClear() { if (!actionLocked.value) clearVisible.value = true }
function cancelClear() { clearVisible.value = false }
function clearBackup() { page.clearExport(); downloadNotice.value = false; clearVisible.value = false }
function chooseFile() { if (!actionLocked.value && !requiresReview.value && !resultVisible.value) fileInput.value?.click() }
function selectedFile(event: Event) {
  const input = event.target as HTMLInputElement
  const selected = input.files?.[0]
  input.value = ''
  if (selected && !actionLocked.value && !requiresReview.value) void page.selectFile(selected)
}
function removeFile() { if (!actionLocked.value && !requiresReview.value) void page.selectFile(null) }
function dragEnter(event: DragEvent) {
  if (!event.dataTransfer?.types.includes('Files')) return
  event.preventDefault()
  if (!actionLocked.value && !requiresReview.value) dragDepth.value += 1
}
function dragOver(event: DragEvent) {
  if (!event.dataTransfer?.types.includes('Files')) return
  event.preventDefault()
  if (event.dataTransfer) event.dataTransfer.dropEffect = actionLocked.value || requiresReview.value ? 'none' : 'copy'
}
function dragLeave(event: DragEvent) { event.preventDefault(); dragDepth.value = Math.max(0, dragDepth.value - 1) }
function dropFile(event: DragEvent) {
  event.preventDefault(); dragDepth.value = 0
  if (actionLocked.value || requiresReview.value || resultVisible.value) return
  const selected = event.dataTransfer?.files[0]
  if (selected) void page.selectFile(selected)
}
function updateKey(value: string) { page.setMasterKey(value) }
function prepareImport() {
  if (actionLocked.value || requiresReview.value) return
  confirmChecked.value = false
  page.prepareImport()
}
function importEnter(event: KeyboardEvent) {
  if (!(event.target instanceof HTMLInputElement)) return
  if (event.isComposing || event.keyCode === 229) return
  event.preventDefault(); prepareImport()
}
function cancelImport() { if (!contextLocked.value) { page.cancelImportPreparation(); confirmChecked.value = false } }
async function confirmImport() {
  if (!confirmChecked.value || contextLocked.value) return
  await page.confirmImport()
  confirmChecked.value = false
  if (scrollArea.value) scrollArea.value.scrollTop = 0
}
function finishImport() { page.resetImportResult(); reviewChecked.value = false }
function acknowledgeReview() {
  if (!reviewChecked.value) return
  page.acknowledgeImportReviewed(); reviewChecked.value = false
}
function cancelLeave() {
  leaveVisible.value = false
  const resolve = finishNavigation; finishNavigation = undefined; resolve?.(false)
}
function acceptLeave() {
  leaveVisible.value = false
  const resolve = finishNavigation; finishNavigation = undefined; resolve?.(true)
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (busy.value || unsavedExport.value || importDraft.value || requiresReview.value) {
    event.preventDefault(); event.returnValue = ''
  }
}
onBeforeRouteLeave(() => {
  if (busy.value || preparedImport.value || requiresReview.value || clearVisible.value || leaveVisible.value) return false
  if (!unsavedExport.value && !importDraft.value) return true
  return new Promise<boolean>(resolve => { finishNavigation = resolve; leaveVisible.value = true })
})
onMounted(() => window.addEventListener('beforeunload', beforeUnload))
onBeforeUnmount(() => {
  finishNavigation?.(false); finishNavigation = undefined
  window.removeEventListener('beforeunload', beforeUnload)
})
</script>

<template>
  <section class="migration-page">
    <header class="migration-toolbar">
      <PageBackButton :disabled="actionLocked || requiresReview" @click="back" />
      <nav class="migration-tabs" :aria-label="t('migration.navigation')">
        <button type="button" :class="{ 'is-active': active === 'export' }" :aria-current="active === 'export' ? 'page' : undefined" :disabled="actionLocked || requiresReview" @click="exportTab"><i class="i-mdi-tray-arrow-down" aria-hidden="true" />{{ t('migration.export') }}</button>
        <button type="button" :class="{ 'is-active': active === 'import' }" :aria-current="active === 'import' ? 'page' : undefined" :disabled="actionLocked || requiresReview" @click="importTab"><i class="i-mdi-tray-arrow-up" aria-hidden="true" />{{ t('migration.import') }}</button>
      </nav>
      <div class="migration-toolbar-errors" data-page-error-anchor />
    </header>

    <div ref="scrollArea" class="migration-scroll">
      <div class="migration-body">
        <template v-if="active === 'export'">
          <div class="migration-heading"><h2 ref="sectionHeading" tabindex="-1">{{ t(artifact ? 'migration.generated' : 'migration.exportTitle') }}</h2><p>{{ t(artifact ? 'migration.generatedHint' : 'migration.exportHint') }}</p></div>
          <PageErrorNotice v-if="exportState.problem">{{ errorLabel(exportState.problem) }}</PageErrorNotice>
          <template v-if="artifact">
            <dl class="migration-details">
              <div><dt>{{ t('migration.fileName') }}</dt><dd class="migration-filename">{{ artifact.filename }}</dd></div>
              <div><dt>{{ t('migration.fileSize') }}</dt><dd>{{ size(artifact.blob.size) }}</dd></div>
            </dl>
            <div class="migration-download-row"><GhostBtn :disabled="actionLocked" @click="downloadBackup"><i class="i-mdi-download" aria-hidden="true" />{{ t('migration.downloadBackup') }}</GhostBtn></div>
            <div class="migration-key-section">
              <SecuritySecretInput id="migration-export-key" :label="t('migration.masterKey')" :model-value="artifact.masterKey" readonly copyable autocomplete="off" :disabled="actionLocked" />
              <p class="migration-help">{{ t('migration.keyHint') }}</p>
              <GhostBtn :disabled="actionLocked" @click="downloadKey"><i class="i-mdi-key-outline" aria-hidden="true" />{{ t('migration.downloadKey') }}</GhostBtn>
            </div>
            <p v-if="downloadNotice" class="migration-help" role="status">{{ t('migration.downloadStarted') }}</p>
            <label class="migration-check migration-saved-check"><input type="checkbox" :checked="exportSaved" :disabled="actionLocked" @change="updateSaved" /><span>{{ t('migration.exportSaved') }}</span></label>
            <p class="migration-help">{{ t('migration.exportSavedHint') }}</p>
          </template>
          <template v-else>
            <dl class="migration-details">
              <div><dt>{{ t('migration.format') }}</dt><dd>{{ t('migration.formatValue') }}</dd></div>
              <div><dt>{{ t('migration.sizeLimits') }}</dt><dd>{{ t('migration.sizeLimitsValue') }}</dd></div>
              <div><dt>{{ t('migration.includes') }}</dt><dd>{{ t('migration.includesValue') }}</dd></div>
              <div><dt>{{ t('migration.excludes') }}</dt><dd>{{ t('migration.excludesValue') }}</dd></div>
            </dl>
            <p class="migration-help migration-scope">{{ t('migration.scopeHint') }}</p>
            <p class="migration-help">{{ t('migration.keyHint') }}</p>
          </template>
        </template>

        <template v-else>
          <div class="migration-heading"><h2 ref="sectionHeading" tabindex="-1">{{ t(requiresReview ? 'migration.unknownTitle' : importState.outcome === 'success' ? 'migration.importSuccess' : 'migration.importTitle') }}</h2><p>{{ t(requiresReview ? 'migration.unknownHint' : importState.outcome === 'success' ? 'migration.importSuccessHint' : 'migration.importHint') }}</p></div>
          <template v-if="resultVisible">
            <dl v-if="importAttempt" class="migration-details"><div><dt>{{ t('migration.resultFile') }}</dt><dd class="migration-filename">{{ importAttempt.filename }}</dd></div></dl>
            <template v-if="importState.result">
              <dl class="migration-details">
                <div><dt>{{ t('migration.importedRows') }}</dt><dd>{{ number(importState.result.importedRows) }}</dd></div>
                <div><dt>{{ t('migration.preservedRows') }}</dt><dd>{{ number(importState.result.preservedRows) }}</dd></div>
              </dl>
              <MobileRecordList v-if="compact" drilldown list-id="migration-table-results" :record-keys="tableRows.map(row => row.table)" class="migration-mobile-list" :aria-label="t('migration.tableResults')">
                <MobileRecordCard v-for="row in tableRows" :key="row.table" :record-key="row.table" :summary-title="row.table" :summary-meta="`${t('migration.importedRows')}: ${number(row.importedRows)}`">
                  <template #identity><h3 class="mobile-record-title">{{ row.table }}</h3></template>
                  <dl class="mobile-record-fields"><div><dt>{{ t('migration.importedRows') }}</dt><dd>{{ number(row.importedRows) }}</dd></div><div><dt>{{ t('migration.preservedRows') }}</dt><dd>{{ number(row.preservedRows) }}</dd></div></dl>
                </MobileRecordCard>
              </MobileRecordList>
              <div v-else class="migration-table-scroll"><table class="migration-result-table"><caption>{{ t('migration.tableResults') }}</caption><thead><tr><th scope="col">{{ t('migration.dataTable') }}</th><th scope="col">{{ t('migration.importedRows') }}</th><th scope="col">{{ t('migration.preservedRows') }}</th></tr></thead><tbody><tr v-for="row in tableRows" :key="row.table"><th scope="row">{{ row.table }}</th><td>{{ number(row.importedRows) }}</td><td>{{ number(row.preservedRows) }}</td></tr></tbody></table></div>
            </template>
            <label v-if="requiresReview" class="migration-check migration-review-check"><input v-model="reviewChecked" type="checkbox" /><span>{{ t('migration.unknownReview') }}</span></label>
          </template>
          <template v-else>
            <PageErrorNotice v-if="importState.problem"><p>{{ errorLabel(importState.problem) }}</p><p>{{ t(importState.outcome === 'rolledBack' ? 'migration.rolledBack' : 'migration.rejected') }}</p><GhostBtn @click="finishImport">{{ t('migration.editAfterFailure') }}</GhostBtn></PageErrorNotice>
            <form id="migration-import-form" class="migration-form" @submit.prevent="prepareImport">
              <div class="migration-file-field">
                <span id="migration-file-label" class="migration-label">{{ t('migration.selectFile') }}</span>
                <input ref="fileInput" class="migration-hidden-file" type="file" accept=".enc" tabindex="-1" :disabled="actionLocked" :aria-label="t('migration.selectFile')" @change="selectedFile" />
                <div class="migration-drop-zone" :class="{ 'is-dragging': dragDepth > 0, 'is-disabled': actionLocked }" @dragenter="dragEnter" @dragover="dragOver" @dragleave="dragLeave" @drop="dropFile">
                  <button type="button" class="migration-file-choose" :disabled="actionLocked" aria-labelledby="migration-file-label migration-selected-name" aria-describedby="migration-file-help" @click="chooseFile">
                    <i :class="file ? 'i-mdi-file-lock-outline' : 'i-mdi-upload'" aria-hidden="true" />
                    <span><strong id="migration-selected-name">{{ file?.name || t('migration.dropHint') }}</strong><small v-if="file">{{ size(file.size) }} · {{ t('migration.replaceFile') }}</small></span>
                  </button>
                  <button v-if="file" type="button" class="migration-file-remove" :disabled="actionLocked" :aria-label="t('migration.removeFile')" :title="t('migration.removeFile')" @click="removeFile"><i class="i-mdi-close" aria-hidden="true" /></button>
                </div>
                <small id="migration-file-help" class="migration-help">{{ t('migration.fileHint') }}</small>
                <p v-if="fileValidating" class="migration-help" role="status">{{ t('migration.validatingFile') }}</p>
                <p v-if="fileProblem" class="migration-error" role="alert">{{ errorLabel(fileProblem) }}</p>
              </div>
              <div @keydown.enter="importEnter"><SecuritySecretInput id="migration-import-key" :label="t('migration.masterKey')" :model-value="masterKey" :placeholder="t('migration.keyPlaceholder')" autocomplete="off" :disabled="actionLocked" @update:model-value="updateKey" /></div>
              <p v-if="keyProblem" class="migration-error" role="alert">{{ t('migration.errors.keyFormat') }}</p>
            </form>
            <div class="migration-policy"><h3>{{ t('migration.importPolicyTitle') }}</h3><p>{{ t('migration.importPolicy') }}</p><p>{{ t('migration.importFiles') }}</p><p>{{ t('migration.sizeLimitsValue') }}</p><p>{{ t('migration.importRuntime') }}</p></div>
          </template>
        </template>
      </div>
    </div>

    <footer class="migration-footer">
      <span role="status" aria-live="polite">{{ exportState.pending ? t('migration.generating') : contextLocked ? t('migration.importing') : active === 'import' && file && !resultVisible ? t('migration.importPrepared') : '' }}</span>
      <template v-if="active === 'export'"><GhostBtn v-if="exportState.pending" @click="page.cancelExport">{{ t('migration.cancel') }}</GhostBtn><GhostBtn v-else-if="artifact" :disabled="actionLocked" @click="requestClear"><i class="i-mdi-close" aria-hidden="true" />{{ t('migration.clearExport') }}</GhostBtn><PrimaryBtn v-else :disabled="actionLocked || requiresReview" @click="generateBackup"><i class="i-mdi-lock-outline" aria-hidden="true" />{{ t('migration.generate') }}</PrimaryBtn></template>
      <template v-else><PrimaryBtn v-if="requiresReview" :disabled="!reviewChecked" @click="acknowledgeReview">{{ t('migration.reviewed') }}</PrimaryBtn><PrimaryBtn v-else-if="importState.outcome === 'success'" @click="finishImport">{{ t('migration.complete') }}</PrimaryBtn><PrimaryBtn v-else type="submit" form="migration-import-form" :disabled="!canImport || actionLocked" :loading="contextLocked"><i class="i-mdi-database-import-outline" aria-hidden="true" />{{ t('migration.startImport') }}</PrimaryBtn></template>
    </footer>

    <el-dialog :model-value="!!preparedImport" class="migration-dialog" :title="t('migration.confirmTitle')" width="560px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!contextLocked" :show-close="!contextLocked" :before-close="cancelImport">
      <p>{{ t('migration.confirmHint') }}</p><dl v-if="preparedImport" class="migration-details"><div><dt>{{ t('migration.currentSite') }}</dt><dd>{{ currentSite }}</dd></div><div><dt>{{ t('migration.fileName') }}</dt><dd class="migration-filename">{{ preparedImport.filename }}</dd></div><div><dt>{{ t('migration.fileSize') }}</dt><dd>{{ size(preparedImport.size) }}</dd></div></dl><p>{{ t('migration.importPolicy') }}</p>
      <label class="migration-check"><input v-model="confirmChecked" type="checkbox" :disabled="contextLocked" /><span>{{ t('migration.confirmCheck') }}</span></label><p v-if="contextLocked" class="migration-help" role="status">{{ t('migration.importing') }}</p>
      <template #footer><GhostBtn :disabled="contextLocked" @click="cancelImport">{{ t('migration.cancel') }}</GhostBtn><PrimaryBtn :disabled="!confirmChecked" :loading="contextLocked" @click="confirmImport">{{ t('migration.confirmImport') }}</PrimaryBtn></template>
    </el-dialog>
    <el-dialog :model-value="clearVisible" class="migration-dialog" :title="t('migration.clearTitle')" width="480px" append-to-body :close-on-click-modal="false" :before-close="cancelClear"><p>{{ t('migration.clearHint') }}</p><template #footer><GhostBtn @click="cancelClear">{{ t('migration.cancel') }}</GhostBtn><PrimaryBtn @click="clearBackup">{{ t('migration.clear') }}</PrimaryBtn></template></el-dialog>
    <el-dialog :model-value="leaveVisible" class="migration-dialog" :title="t('migration.leaveTitle')" width="500px" append-to-body :close-on-click-modal="false" :before-close="cancelLeave"><p v-if="unsavedExport">{{ t('migration.leaveExport') }}</p><p v-if="importDraft">{{ t('migration.leaveImport') }}</p><template #footer><GhostBtn @click="cancelLeave">{{ t('migration.keepPage') }}</GhostBtn><PrimaryBtn @click="acceptLeave">{{ t('migration.leave') }}</PrimaryBtn></template></el-dialog>
  </section>
</template>

<style scoped>
.migration-mobile-list { padding-inline: 0; margin-top: 16px; }
</style>
