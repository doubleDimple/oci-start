<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import { computed, nextTick, onBeforeUnmount, reactive, ref, shallowRef, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { useShellStore } from '@/stores/shell'
import { usePageMotion } from '@/composables/usePageMotion'
import { REGION_COORDINATES, regionCityName } from '@/views/regions/regionCoords'
import {
  parseOciConfig, parseGcpConfig, saveTenantCredentials, tenantImportError,
  type ImportProvider, type TenantImportFields, type OciProfile,
} from '@/api/tenantImport'

type Field = keyof TenantImportFields
interface FieldDefinition { id: Field; label: string; placeholder: string }
const route = useRoute()
const router = useRouter()
const shell = useShellStore()
const { t, locale } = useI18n()
const root = ref<HTMLElement | null>(null)
const configInput = ref<HTMLTextAreaElement | null>(null)
const configPicker = ref<HTMLInputElement | null>(null)
const keyPicker = ref<HTMLInputElement | null>(null)
const keyButton = ref<HTMLButtonElement | null>(null)
usePageMotion(root)
const provider = computed<ImportProvider | null>(() => {
  const value = route.query.cloudType ?? String(shell.cloudType)
  return value === '1' ? 1 : value === '2' ? 2 : null
})
const providerOptions: ImportProvider[] = [1, 2]
const emptyFields = (): TenantImportFields => ({ userName: '', tenantId: '', fingerprint: '', tenancy: '', region: '' })
const form = reactive<TenantImportFields>(emptyFields())
const fieldDefinitions = computed<FieldDefinition[]>(() => [
  { id: 'userName', label: 'userName', placeholder: 'userNamePlaceholder' },
  { id: 'tenantId', label: provider.value === 2 ? 'clientEmail' : 'ociUser', placeholder: provider.value === 2 ? 'clientEmailPlaceholder' : 'ociUserPlaceholder' },
  { id: 'fingerprint', label: provider.value === 2 ? 'privateKeyId' : 'fingerprint', placeholder: provider.value === 2 ? 'privateKeyIdPlaceholder' : 'fingerprintPlaceholder' },
  { id: 'tenancy', label: provider.value === 2 ? 'projectId' : 'tenancy', placeholder: provider.value === 2 ? 'projectIdPlaceholder' : 'tenancyPlaceholder' },
])
const regions = computed(() => Object.keys(REGION_COORDINATES).map(value => ({ value, label: `${regionCityName(value, locale.value)} · ${value}` })))
const unknownRegion = computed(() => Boolean(form.region) && !Object.prototype.hasOwnProperty.call(REGION_COORDINATES, form.region))
const configText = ref('')
const parsedText = ref('')
const profiles = shallowRef<OciProfile[]>([])
const profileId = ref('')
const activeProfile = computed(() => profiles.value.find(profile => profile.id === profileId.value))
const keyFile = shallowRef<File | null>(null)
const gcpIdentity = shallowRef<Pick<TenantImportFields, 'tenantId' | 'fingerprint'> | null>(null)
const gcpMismatch = computed(() => provider.value === 2 && keyFile.value && gcpIdentity.value
  && (form.tenantId.trim() !== gcpIdentity.value.tenantId.trim() || form.fingerprint.trim() !== gcpIdentity.value.fingerprint.trim()))
const reading = ref(false)
const saving = ref(false)
const saved = ref(false)
const dragging = ref(false)
const parseError = shallowRef<unknown>(null)
const parseNote = ref('')
const fileErrorKey = ref('')
const invalidFields = ref(new Set<Field>())
const saveError = shallowRef<unknown>(null)
const locked = computed(() => saving.value || saved.value)
const configDirty = computed(() => Boolean(configText.value.trim()) && configText.value !== parsedText.value)
const fileSize = computed(() => {
  if (!keyFile.value) return ''
  const size = keyFile.value.size
  const unit = size >= 1024 * 1024 ? 'megabyte' : size >= 1024 ? 'kilobyte' : 'byte'
  const divisor = unit === 'megabyte' ? 1024 * 1024 : unit === 'kilobyte' ? 1024 : 1
  return new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN', { style: 'unit', unit, maximumFractionDigits: 1 }).format(size / divisor)
})
let parseTimer: ReturnType<typeof setTimeout> | undefined
let reader: FileReader | undefined
let inputVersion = 0
let pageVersion = 0
let dragDepth = 0
let saveController: AbortController | undefined

function stopInputWork() {
  inputVersion += 1
  if (parseTimer) clearTimeout(parseTimer)
  parseTimer = undefined
  reader?.abort()
  reader = undefined
  reading.value = false
}
function resetInputs() {
  stopInputWork()
  Object.assign(form, emptyFields())
  configText.value = ''
  parsedText.value = ''
  profiles.value = []
  profileId.value = ''
  keyFile.value = null
  gcpIdentity.value = null
  parseError.value = null
  parseNote.value = ''
  fileErrorKey.value = ''
  invalidFields.value = new Set()
  saveError.value = null
  saved.value = false
  dragging.value = false
  dragDepth = 0
  if (configPicker.value) configPicker.value.value = ''
  if (keyPicker.value) keyPicker.value.value = ''
}
function clearForm() {
  if (saving.value) return
  resetInputs()
  void nextTick(() => configInput.value?.focus())
}
function changeProvider(next: ImportProvider) {
  if (saving.value || next === provider.value) return
  shell.setCloud(next)
  void router.replace({ path: '/tenants/addSpeed', query: { cloudType: String(next) } })
}
function goBack() {
  void router.push({ path: '/tenants/list', query: { cloudType: String(provider.value || 1) } })
}
function editField(field: Field) {
  const next = new Set(invalidFields.value)
  next.delete(field)
  invalidFields.value = next
  if (fileErrorKey.value === 'fileMismatch' && !gcpMismatch.value) fileErrorKey.value = ''
}
function removeFile() {
  if (locked.value) return
  stopInputWork()
  keyFile.value = null
  gcpIdentity.value = null
  fileErrorKey.value = ''
  if (keyPicker.value) keyPicker.value.value = ''
}
function applyProfile(profile: OciProfile) {
  // Do not carry a selected private key into a different account/profile.
  const changedAccount = (['tenantId', 'fingerprint', 'tenancy'] as const)
    .some(field => form[field] && form[field] !== profile.fields[field])
  if (changedAccount) keyFile.value = null
  Object.assign(form, profile.fields)
  profileId.value = profile.id
  invalidFields.value = new Set()
  parseNote.value = keyFile.value ? 'parsedOci' : 'waitingForKey'
}
function changeProfile(id: string) {
  const profile = profiles.value.find(item => item.id === id)
  if (profile && !locked.value) applyProfile(profile)
}
function parseConfig(originalFile?: File): boolean {
  if (!provider.value || locked.value || !configText.value.trim()) return false
  if (parseTimer) clearTimeout(parseTimer)
  parseTimer = undefined
  try {
    if (provider.value === 1) {
      const parsed = parseOciConfig(configText.value)
      const previousName = activeProfile.value?.name
      const profile = parsed.find(item => item.name === previousName) || parsed.find(item => item.name === 'DEFAULT') || parsed[0]
      profiles.value = parsed
      if (!profile) return false
      applyProfile(profile)
    } else {
      const unchangedFile = configText.value === parsedText.value ? keyFile.value ?? undefined : undefined
      const parsed = parseGcpConfig(configText.value, originalFile || unchangedFile)
      Object.assign(form, parsed.fields)
      keyFile.value = parsed.file
      gcpIdentity.value = { tenantId: parsed.fields.tenantId, fingerprint: parsed.fields.fingerprint }
      invalidFields.value = new Set()
      parseNote.value = 'parsedGcp'
    }
    parsedText.value = configText.value
    parseError.value = null
    fileErrorKey.value = ''
    return true
  } catch (error) {
    parseError.value = error
    parseNote.value = ''
    return false
  }
}
function parseNow() { if (!reading.value) parseConfig() }
function configChanged(event: Event) {
  if (locked.value) return
  stopInputWork()
  configText.value = (event.target as HTMLTextAreaElement).value
  parseError.value = null
  parseNote.value = ''
  fileErrorKey.value = ''
  if (provider.value === 2) { keyFile.value = null; gcpIdentity.value = null }
  if (!configText.value.trim()) {
    profiles.value = []
    profileId.value = ''
    parsedText.value = ''
    return
  }
  // Let a paste or a short edit finish before updating the derived form.
  parseTimer = setTimeout(() => { parseTimer = undefined; parseConfig() }, 300)
}
function clearConfig() {
  if (locked.value) return
  stopInputWork()
  configText.value = ''
  parsedText.value = ''
  profiles.value = []
  profileId.value = ''
  parseError.value = null
  parseNote.value = ''
  void nextTick(() => configInput.value?.focus())
}
function readText(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const currentReader = new FileReader()
    reader = currentReader
    currentReader.onload = () => resolve(String(currentReader.result || ''))
    currentReader.onerror = () => reject(currentReader.error)
    currentReader.onabort = () => reject(new DOMException('Aborted', 'AbortError'))
    currentReader.readAsText(file)
  })
}
async function acceptFile(file: File, asKey = false) {
  if (!provider.value || locked.value) return
  stopInputWork()
  const version = inputVersion
  const cloud = provider.value
  parseError.value = null
  parseNote.value = ''
  fileErrorKey.value = ''
  if (!file.size) { fileErrorKey.value = 'emptyFile'; return }
  if (cloud === 1 && (asKey || /\.(pem|key)$/i.test(file.name))) {
    keyFile.value = file
    return
  }
  reading.value = true
  try {
    const text = await readText(file)
    if (version !== inputVersion) return
    if (!text.trim()) { fileErrorKey.value = 'emptyFile'; return }
    if (cloud === 1 && /^\s*-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----/.test(text)) {
      keyFile.value = file
    } else {
      if (cloud === 2) { keyFile.value = null; gcpIdentity.value = null }
      configText.value = text
      parseConfig(cloud === 2 ? file : undefined)
    }
  } catch {
    if (version === inputVersion) fileErrorKey.value = 'fileReadFailed'
  } finally {
    if (version === inputVersion) { reader = undefined; reading.value = false }
  }
}
function fileSelected(event: Event, asKey: boolean) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (file) void acceptFile(file, asKey)
}
function chooseConfigFile() { configPicker.value?.click() }
function chooseKeyFile() { keyPicker.value?.click() }
function dragEnter(event: DragEvent) {
  if (locked.value || !event.dataTransfer?.types.includes('Files')) return
  event.preventDefault()
  dragDepth += 1
  dragging.value = true
}
function dragLeave() { dragDepth = Math.max(0, dragDepth - 1); dragging.value = dragDepth > 0 }
function dropFile(event: DragEvent) {
  dragging.value = false
  dragDepth = 0
  if (locked.value) return
  const files = event.dataTransfer?.files
  if (!files?.length) return
  if (files.length !== 1) { fileErrorKey.value = 'onlyOneFile'; return }
  void acceptFile(files[0])
}
function pasteFile(event: ClipboardEvent) {
  const files = event.clipboardData?.files
  if (!files?.length || locked.value) return
  event.preventDefault()
  if (files.length !== 1) { fileErrorKey.value = 'onlyOneFile'; return }
  void acceptFile(files[0])
}
function fieldError(field: Field, label: string) {
  return invalidFields.value.has(field) ? t('tenantImport.requiredField', { field: t(`tenantImport.${label}`) }) : ''
}
async function focusInvalid() {
  await nextTick()
  if (parseError.value || configDirty.value) { configInput.value?.focus(); return }
  const first = fieldDefinitions.value.find(field => invalidFields.value.has(field.id))
  if (first) root.value?.querySelector<HTMLInputElement>(`#import-${first.id}`)?.focus()
  else if (invalidFields.value.has('region')) root.value?.querySelector<HTMLInputElement>('.import-region-select input')?.focus()
  else keyButton.value?.focus()
}
async function submit() {
  if (!provider.value || locked.value || reading.value) return
  if (configDirty.value && !parseConfig()) { await focusInvalid(); return }
  const missing = new Set<Field>()
  for (const field of fieldDefinitions.value) if (!form[field.id].trim()) missing.add(field.id)
  if (provider.value === 1 && !form.region.trim()) missing.add('region')
  invalidFields.value = missing
  fileErrorKey.value = !keyFile.value ? 'requiredFile' : !keyFile.value.size ? 'emptyFile' : fileErrorKey.value
  // Authentication reads the JSON identity; the target project remains editable
  // for service accounts authorized to manage resources in another project.
  if (gcpMismatch.value) fileErrorKey.value = 'fileMismatch'
  if (missing.size || fileErrorKey.value || parseError.value || !keyFile.value) { await focusInvalid(); return }
  const cloud = provider.value
  const file = keyFile.value
  const fields = { ...form }
  for (const field of Object.keys(fields) as Field[]) fields[field] = fields[field].trim()
  const version = pageVersion
  const controller = new AbortController()
  saveController = controller
  saving.value = true
  saveError.value = null
  try {
    await saveTenantCredentials(cloud, fields, file, controller.signal)
    if (version !== pageVersion || controller.signal.aborted) return
    saved.value = true
    ElMessage.success(t('tenantImport.saveSuccess'))
  } catch (error) {
    if (version === pageVersion && !controller.signal.aborted) saveError.value = error
  } finally {
    if (version === pageVersion && !controller.signal.aborted) { saving.value = false; saveController = undefined }
  }
  if (saved.value && version === pageVersion) {
    shell.setCloud(cloud)
    // Saving and navigation have separate outcomes. Keep the saved state if navigation fails.
    void router.push({ path: '/tenants/list', query: { cloudType: String(cloud) } }).catch(() => {})
  }
}
watch(provider, cloud => {
  pageVersion += 1
  saveController?.abort()
  saveController = undefined
  saving.value = false
  resetInputs()
  if (cloud && shell.cloudType !== cloud) shell.setCloud(cloud)
}, { immediate: true })
onBeforeUnmount(() => {
  pageVersion += 1
  saveController?.abort()
  saveController = undefined
  resetInputs()
})
</script>

<template>
  <div ref="root" class="tenant-import-page">
    <form class="import-card" novalidate data-motion-enter @submit.prevent="submit">
      <div class="import-toolbar">
        <PageBackButton :disabled="saving" :title="t('tenantImport.back')" @click="goBack" />
        <div class="provider-switch" role="group" :aria-label="t('tenantImport.providerLabel')">
          <button v-for="cloud in providerOptions" :key="cloud" type="button" :aria-pressed="provider === cloud" :disabled="saving" @click="changeProvider(cloud)">
            <img :src="cloud === 1 ? '/images/oracle.png' : '/images/google.png'" alt="" />{{ t(`tenantImport.${cloud === 1 ? 'ociProvider' : 'gcpProvider'}`) }}
          </button>
        </div>
        <div class="import-toolbar-actions" data-page-error-anchor>
          <GhostBtn :disabled="saving || !provider" @click="clearForm">{{ t('tenantImport.clear') }}</GhostBtn>
          <PrimaryBtn type="submit" :loading="saving" :disabled="!provider || reading || saved"><i v-if="!saving" class="i-mdi-check" aria-hidden="true" />{{ t(`tenantImport.${saving ? 'saving' : 'save'}`) }}</PrimaryBtn>
        </div>
      </div>

      <div v-if="!provider" class="unsupported-provider" role="status"><i class="i-mdi-cloud-outline" aria-hidden="true" /><p>{{ t('tenantImport.unsupportedProvider') }}</p></div>
      <template v-else>
        <div v-if="saving" class="save-notice" role="status"><i class="i-mdi-loading import-spin" aria-hidden="true" /><span>{{ t('tenantImport.savePending') }}</span></div>
        <PageErrorNotice v-if="saveError"><strong>{{ t('tenantImport.saveFailed') }}</strong><p>{{ tenantImportError(saveError) }}</p></PageErrorNotice>
        <div v-if="saveError" class="save-notice is-warning" role="alert"><span>{{ t('tenantImport.saveUnknown') }}</span><button type="button" @click="goBack">{{ t('tenantImport.checkList') }}</button></div>
        <div v-if="saved" class="save-notice" role="status"><i class="i-mdi-check-circle-outline" aria-hidden="true" /><span>{{ t('tenantImport.saveSuccess') }}</span><button type="button" @click="goBack">{{ t('tenantImport.checkList') }}</button></div>

        <div class="import-scroll">
          <div class="import-columns">
            <section class="config-section" aria-labelledby="import-config-label">
              <div class="section-label-row"><label id="import-config-label" for="import-config">{{ t('tenantImport.configLabel') }}</label><button type="button" class="text-button" :disabled="locked || reading" @click="chooseConfigFile"><i class="i-mdi-file-upload-outline" aria-hidden="true" />{{ t('tenantImport.chooseFile') }}</button></div>
              <p id="import-config-hint" class="section-hint">{{ t(`tenantImport.${provider === 1 ? 'configHintOci' : 'configHintGcp'}`) }}</p>
              <input ref="configPicker" type="file" class="sr-only" tabindex="-1" :disabled="locked" :accept="provider === 2 ? '.json,application/json' : undefined" :aria-label="t('tenantImport.chooseFile')" @change="fileSelected($event, false)" />
              <div class="config-editor" :class="{ 'is-dragging': dragging, 'has-error': parseError }" @dragenter="dragEnter" @dragover.prevent @dragleave.prevent="dragLeave" @drop.prevent="dropFile">
                <textarea id="import-config" ref="configInput" :value="configText" :disabled="locked" :placeholder="t(`tenantImport.${provider === 1 ? 'configPlaceholderOci' : 'configPlaceholderGcp'}`)" autocomplete="off" autocapitalize="off" spellcheck="false" :aria-invalid="Boolean(parseError)" :aria-describedby="parseError ? 'import-config-hint import-parse-error' : 'import-config-hint'" @input="configChanged" @paste="pasteFile" />
                <div v-if="dragging" class="drop-overlay" aria-hidden="true"><i class="i-mdi-file-download-outline" /><span>{{ t('tenantImport.dropActive') }}</span></div>
                <div class="editor-footer"><span>{{ t(`tenantImport.${provider === 1 ? 'dropHintOci' : 'dropHintGcp'}`) }}</span><button v-if="configText" type="button" class="icon-button" :disabled="locked || reading" :aria-label="t('tenantImport.clearConfig')" :title="t('tenantImport.clearConfig')" @click="clearConfig"><i class="i-mdi-close" aria-hidden="true" /></button></div>
              </div>
              <div v-if="profiles.length > 1" class="profile-picker">
                <label for="import-profile">{{ t('tenantImport.profileLabel') }}</label>
                <el-select id="import-profile" :model-value="profileId" :disabled="locked || reading || configDirty" :aria-label="t('tenantImport.profileLabel')" @change="changeProfile"><el-option v-for="profile in profiles" :key="profile.id" :value="profile.id" :label="profile.name || t('tenantImport.unnamedProfile')" /></el-select>
                <p class="section-hint">{{ t('tenantImport.profileHint') }}</p>
              </div>
              <div class="parse-feedback" aria-live="polite">
                <span v-if="reading" class="parse-message"><i class="i-mdi-loading import-spin" aria-hidden="true" />{{ t('tenantImport.readFile') }}</span>
                <span v-else-if="parseError" id="import-parse-error" class="parse-message is-error">{{ tenantImportError(parseError) }}</span>
                <span v-else-if="configDirty" class="parse-message">{{ t('tenantImport.configChanged') }}</span>
                <span v-else-if="parseNote" class="parse-message is-success"><i class="i-mdi-check-circle-outline" aria-hidden="true" />{{ t(`tenantImport.${parseNote}`) }}</span>
                <button v-if="configText.trim()" type="button" class="text-button" :disabled="locked || reading" @click="parseNow">{{ t('tenantImport.parse') }}</button>
              </div>
            </section>

            <section class="credentials-section" aria-labelledby="import-fields-label">
              <div id="import-fields-label" class="section-label-row">{{ t('tenantImport.fieldsLabel') }}</div>
              <p class="section-hint">{{ t('tenantImport.fieldsHint') }}</p>
              <div class="credentials-fields">
                <div v-for="field in fieldDefinitions" :key="field.id" class="form-field">
                  <label :for="`import-${field.id}`">{{ t(`tenantImport.${field.label}`) }}<span class="required-mark" aria-hidden="true">*</span></label>
                  <input :id="`import-${field.id}`" v-model="form[field.id]" :name="field.id" type="text" :disabled="locked" :placeholder="t(`tenantImport.${field.placeholder}`)" autocomplete="off" autocapitalize="off" spellcheck="false" required :aria-invalid="invalidFields.has(field.id)" :aria-describedby="invalidFields.has(field.id) ? `import-error-${field.id}` : undefined" @input="editField(field.id)" />
                  <p v-if="invalidFields.has(field.id)" :id="`import-error-${field.id}`" class="field-error">{{ fieldError(field.id, field.label) }}</p>
                </div>
                <div v-if="provider === 1" class="form-field">
                  <label for="import-region">{{ t('tenantImport.region') }}<span class="required-mark" aria-hidden="true">*</span></label>
                  <el-select id="import-region" v-model="form.region" class="import-region-select" filterable allow-create default-first-option :disabled="locked" :placeholder="t('tenantImport.regionPlaceholder')" :aria-label="t('tenantImport.region')" :aria-invalid="invalidFields.has('region')" :aria-describedby="invalidFields.has('region') ? 'import-error-region' : undefined" @change="editField('region')"><el-option v-for="region in regions" :key="region.value" :label="region.label" :value="region.value" /></el-select>
                  <p v-if="invalidFields.has('region')" id="import-error-region" class="field-error">{{ fieldError('region', 'region') }}</p>
                  <p v-else-if="unknownRegion" class="field-hint">{{ t('tenantImport.regionUnknown') }}</p>
                </div>
              </div>

              <div class="key-file-section">
                <label class="file-label">{{ t(`tenantImport.${provider === 1 ? 'keyFileOci' : 'keyFileGcp'}`) }}<span class="required-mark" aria-hidden="true">*</span></label>
                <input ref="keyPicker" type="file" class="sr-only" tabindex="-1" :disabled="locked" :accept="provider === 2 ? '.json,application/json' : undefined" :aria-label="t(`tenantImport.${provider === 1 ? 'keyFileOci' : 'keyFileGcp'}`)" @change="fileSelected($event, true)" />
                <div class="key-file" :class="{ 'has-file': keyFile, 'has-error': fileErrorKey }">
                  <button ref="keyButton" type="button" class="file-picker-button" :disabled="locked || reading" :aria-describedby="fileErrorKey ? 'import-file-error' : 'import-file-hint'" @click="chooseKeyFile">
                    <span class="file-icon"><i :class="keyFile ? 'i-mdi-file-check-outline' : 'i-mdi-key-outline'" aria-hidden="true" /></span>
                    <span class="file-description"><strong>{{ keyFile?.name || t('tenantImport.chooseFile') }}</strong><small>{{ keyFile ? fileSize : t(`tenantImport.${provider === 1 ? 'keyFileHintOci' : 'keyFileHintGcp'}`) }}</small></span>
                    <span class="file-action">{{ t(`tenantImport.${keyFile ? 'replaceFile' : 'chooseFile'}`) }}</span>
                  </button>
                  <button v-if="keyFile" type="button" class="icon-button" :disabled="locked || reading" :aria-label="t('tenantImport.removeFile')" :title="t('tenantImport.removeFile')" @click="removeFile"><i class="i-mdi-close" aria-hidden="true" /></button>
                </div>
                <p v-if="fileErrorKey" id="import-file-error" class="field-error" role="alert">{{ t(`tenantImport.${fileErrorKey}`) }}</p>
                <p v-if="provider === 1 && activeProfile?.keyFileHint" id="import-file-hint" class="field-hint file-path-hint">{{ t('tenantImport.keyFilePathHint', { path: activeProfile.keyFileHint }) }}</p>
                <p v-else id="import-file-hint" class="field-hint">{{ t(`tenantImport.${provider === 1 ? 'keyFileHintOci' : 'keyFileHintGcp'}`) }}</p>
              </div>
            </section>
          </div>
        </div>
        <footer class="import-footer"><span v-if="invalidFields.size || fileErrorKey" role="status" class="is-error">{{ t('tenantImport.validationSummary') }}</span><span v-else>{{ t(`tenantImport.${provider === 1 ? 'ociSaveHint' : 'gcpSaveHint'}`) }}</span><button type="button" class="text-button" :disabled="saving" @click="goBack">{{ t('tenantImport.cancel') }}</button></footer>
      </template>
    </form>
  </div>
</template>

<style scoped lang="scss" src="./tenant-import.scss"></style>
