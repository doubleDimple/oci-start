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
import { isManagedTenant, loadTenantPermissionContext } from '@/utils/tenantPermissions'
import { REGION_COORDINATES, regionCityName } from '@/views/regions/regionCoords'
import {
  parseOciConfig, parseGcpConfig, saveTenantCredentials, tenantImportError, tenantImportOutcomeUnknown, getTenantPermissionCatalog,
  downgradeTenantCredentials, isLocalTenantId, loadTenantDowngradeBackup, sendTenantBackupCode,
  type ImportProvider, type TenantImportFields, type OciProfile, type TenantPermissionOption, type TenantDowngradeSource,
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
const providerOptions: ImportProvider[] = [1]
const downgradingTenant = computed(() => route.query.downgradeTenantId !== undefined)
const provider = computed<ImportProvider | null>(() => {
  if (downgradingTenant.value) return 1
  const value = route.query.cloudType ?? String(shell.cloudType)
  const parsed = value === '1' ? 1 : value === '2' ? 2 : null
  if (parsed && !providerOptions.includes(parsed)) return 1
  return parsed ?? 1
})
const emptyFields = (): TenantImportFields => ({ userName: '', tenantId: '', fingerprint: '', tenancy: '', region: '' })
const form = reactive<TenantImportFields>(emptyFields())
const defaultManagedUserName = 'oci-start-operator'
const managedUserName = ref(defaultManagedUserName)
const managedNameInvalid = ref(false)
const updatingManagedTenant = computed(() => typeof route.query.managedTenantId === 'string' && Boolean(route.query.managedTenantId))
const downgradeSource = shallowRef<TenantDowngradeSource | null>(null)
const backupConfirmed = ref(false)
const backupConfirmationInvalid = ref(false)
const backupCode = ref('')
const backupCodeSent = ref(false)
const backupBusy = ref(false)
const backupError = ref('')
const backupDownloaded = ref(false)
let backupController: AbortController | undefined
const restrictedMode = ref(false)
const passwordResetUsers = ref('')
const userManagementGroups = ref('')
const invalidScopeFields = ref(new Set<string>())
const parseScopeIds = (value: string) => [...new Set(value.split(/[\s,;，；]+/).filter(Boolean))]
const configHintKey = computed(() => provider.value === 2 ? 'configHintGcp' : restrictedMode.value ? 'configHintOci' : 'directConfigHint')
const keyHintKey = computed(() => provider.value === 2 ? 'keyFileHintGcp' : restrictedMode.value ? 'keyFileHintOci' : 'directKeyHint')
const saveHintKey = computed(() => downgradingTenant.value ? 'downgradeSaveHint' : provider.value === 2 ? 'gcpSaveHint' : restrictedMode.value ? 'ociSaveHint' : 'directSaveHint')
const permissionCatalog = ref<TenantPermissionOption[]>([])
const selectedPermissions = ref<string[]>([])
const catalogLoading = ref(false)
const catalogError = shallowRef<unknown>(null)
const permissionGroups = computed(() => [...new Set(permissionCatalog.value.map(item => item.group))].map(group => ({
  name: group,
  items: permissionCatalog.value.filter(item => item.group === group && item.supported),
  unavailable: permissionCatalog.value.filter(item => item.group === group && !item.supported),
})))
const selectedPermissionCount = computed(() => permissionCatalog.value.filter(item => item.supported && selectedPermissions.value.includes(item.code)).length)
const permissionGroupIcons: Record<string, string> = {
  basic: 'i-mdi-magnify', compute: 'i-mdi-server', storage: 'i-mdi-harddisk',
  network: 'i-mdi-lan', observability: 'i-mdi-chart-line', database: 'i-mdi-database-outline',
  account: 'i-mdi-account-cog-outline',
}
const destructivePermissions = new Set(['INSTANCE_DELETE', 'BOOT_VOLUME_DELETE', 'BLOCK_VOLUME_DELETE', 'USER_DELETE', 'MYSQL_MANAGE', 'NETWORK_MANAGE', 'DOMAIN_SECURITY_MANAGE', 'DOMAIN_USER_MANAGE'])
function permissionLabel(item: TenantPermissionOption) {
  return locale.value.startsWith('en') ? item.labelEn || item.label : item.label
}
function permissionDependencies(item: TenantPermissionOption) {
  return permissionCatalog.value.filter(option => item.dependencies?.includes(option.code)).map(permissionLabel).join(locale.value.startsWith('en') ? ', ' : '、')
}
function permissionGroupLabel(group: string) {
  const labels: Record<string, [string, string]> = {
    basic: ['基础查询', 'Basic access'], compute: ['实例操作', 'Instances'], storage: ['存储卷', 'Storage volumes'],
    network: ['网络与区域', 'Networking and regions'], observability: ['账单、流量与审计', 'Cost, traffic and audit'],
    database: ['数据库', 'Databases'], account: ['账号管理', 'Account management'],
  }
  return labels[group]?.[locale.value.startsWith('en') ? 1 : 0] || group
}
let catalogController: AbortController | undefined
async function loadPermissionCatalog() {
  catalogController?.abort()
  const controller = new AbortController()
  catalogController = controller
  catalogLoading.value = true
  catalogError.value = null
  try {
    const catalog = await getTenantPermissionCatalog(controller.signal)
    if (controller.signal.aborted) return
    permissionCatalog.value = catalog
    selectedPermissions.value = catalog.filter(item => item.supported && (item.required || item.defaultEnabled)).map(item => item.code)
    if (downgradingTenant.value) {
      downgradeSource.value = null
      const sourceId = route.query.downgradeTenantId
      if (!isLocalTenantId(sourceId) || updatingManagedTenant.value) throw new Error(t('tenantImport.invalidDowngradeTenant'))
      const source = await loadTenantPermissionContext(sourceId, controller.signal)
      if (controller.signal.aborted) return
      if ((source.permissionMode != null && source.permissionMode !== '') || Number(source.cloudType) !== 1 || Number(source.transferStatus || 0) === 1
        || typeof source.tenantId !== 'string' || !source.tenantId.trim()
        || typeof source.tenancy !== 'string' || !source.tenancy.trim()) throw new Error(t('tenantImport.invalidDowngradeTenant'))
      // Retain display/identity metadata only. Bootstrap credentials stay on the server.
      downgradeSource.value = {
        id: sourceId, userId: source.tenantId, tenancy: source.tenancy,
        name: source.defName || source.tenancyName || source.userName || sourceId,
        region: source.regionEn || source.region || '',
      }
      return
    }
    const existingId = route.query.managedTenantId
    if (updatingManagedTenant.value && (typeof existingId !== 'string' || !/^[1-9]\d*$/.test(existingId))) {
      throw new Error(t('tenantImport.invalidManagedTenant'))
    }
    if (typeof existingId === 'string' && /^[1-9]\d*$/.test(existingId)) {
      const existing = await loadTenantPermissionContext(existingId, controller.signal)
      if (controller.signal.aborted) return
      if (!isManagedTenant(existing)) throw new Error(t('tenantImport.invalidManagedTenant'))
      managedUserName.value = existing.managedUserName || ''
      form.userName = existing.userName || existing.defName || ''
      form.tenancy = existing.tenancy || ''
      form.region = existing.regionEn || existing.region || ''
      const savedGrants: unknown = JSON.parse(existing.permissionsJson || '[]')
      if (!Array.isArray(savedGrants)) throw new Error(t('tenantImport.invalidManagedTenant'))
      selectedPermissions.value = catalog.filter(item => item.supported && (item.required || savedGrants.includes(item.code))).map(item => item.code)
      const scope = JSON.parse(existing.accountScopeJson || '{}')
      passwordResetUsers.value = Array.isArray(scope.passwordResetUserIds) ? scope.passwordResetUserIds.filter((id: unknown) => typeof id === 'string').join('\n') : ''
      userManagementGroups.value = Array.isArray(scope.userManagementGroupIds) ? scope.userManagementGroupIds.filter((id: unknown) => typeof id === 'string').join('\n') : ''
    }
  } catch (error) {
    if (!controller.signal.aborted) catalogError.value = error
  } finally {
    if (!controller.signal.aborted) catalogLoading.value = false
  }
}
function chooseImportMode(restricted: boolean) {
  if (saving.value || saved.value || updatingManagedTenant.value || downgradingTenant.value || restrictedMode.value === restricted) return
  restrictedMode.value = restricted
  saveError.value = null
  managedNameInvalid.value = false
  invalidScopeFields.value = new Set()
  if (restricted) void loadPermissionCatalog()
  else {
    catalogController?.abort()
    catalogLoading.value = false
    catalogError.value = null
  }
}
function togglePermission(item: TenantPermissionOption, enabled: boolean) {
  if (item.required || !item.supported || locked.value) return
  const next = new Set(selectedPermissions.value)
  if (enabled) next.add(item.code)
  else next.delete(item.code)
  // Follow the server catalog so visible selections match the resulting cloud policy.
  let changed = true
  while (changed) {
    changed = false
    for (const capability of permissionCatalog.value) {
      if (!next.has(capability.code)) continue
      for (const dependency of capability.dependencies || []) {
        if (next.has(dependency)) continue
        if (enabled) next.add(dependency)
        else next.delete(capability.code)
        changed = true
      }
    }
  }
  selectedPermissions.value = [...next]
}
function selectAllPermissions() {
  if (locked.value || catalogError.value) return
  selectedPermissions.value = permissionCatalog.value.filter(item => item.supported).map(item => item.code)
}
function restoreDefaultPermissions() {
  if (locked.value || catalogError.value) return
  const defaults = new Set(permissionCatalog.value.filter(item => item.supported && (item.required || item.defaultEnabled)).map(item => item.code))
  // Keep dependency selections in sync if the server's defaults change.
  for (const code of defaults) {
    for (const dependency of permissionCatalog.value.find(item => item.code === code)?.dependencies || []) {
      if (permissionCatalog.value.some(item => item.code === dependency && item.supported)) defaults.add(dependency)
    }
  }
  selectedPermissions.value = [...defaults]
}
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
const cleanupWarnings = ref<string[]>([])
const saveOutcomeUnknown = computed(() => Boolean(saveError.value) && tenantImportOutcomeUnknown(saveError.value))
const locked = computed(() => saving.value || saved.value || (provider.value === 1 && restrictedMode.value && catalogLoading.value))
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
  backupController?.abort()
  backupController = undefined
  downgradeSource.value = null
  backupConfirmed.value = false
  backupConfirmationInvalid.value = false
  backupCode.value = ''
  backupCodeSent.value = false
  backupBusy.value = false
  backupError.value = ''
  backupDownloaded.value = false
  Object.assign(form, emptyFields())
  managedUserName.value = defaultManagedUserName
  managedNameInvalid.value = false
  passwordResetUsers.value = ''
  userManagementGroups.value = ''
  invalidScopeFields.value = new Set()
  selectedPermissions.value = permissionCatalog.value.filter(item => item.supported && (item.required || item.defaultEnabled)).map(item => item.code)
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
  cleanupWarnings.value = []
  saved.value = false
  dragging.value = false
  dragDepth = 0
  if (configPicker.value) configPicker.value.value = ''
  if (keyPicker.value) keyPicker.value.value = ''
}
async function clearForm() {
  if (saving.value || saved.value || catalogLoading.value) return
  resetInputs()
  if (provider.value === 1 && (updatingManagedTenant.value || downgradingTenant.value)) await loadPermissionCatalog()
  void nextTick(() => configInput.value?.focus())
}
function changeProvider(next: ImportProvider) {
  if (saving.value || downgradingTenant.value || next === provider.value) return
  shell.setCloud(next)
  void router.replace({ path: '/tenants/addSpeed', query: { cloudType: String(next) } })
}
function goBack() {
  void router.push({ path: '/tenants/list', query: { cloudType: String(provider.value || 1) } })
}
async function sendBackupCode() {
  if (!downgradeSource.value || backupBusy.value || locked.value) return
  const controller = new AbortController()
  backupController = controller
  backupBusy.value = true
  backupError.value = ''
  try {
    await sendTenantBackupCode(controller.signal)
    if (controller.signal.aborted) return
    backupCodeSent.value = true
    backupCode.value = ''
  } catch (error) {
    if (!controller.signal.aborted) backupError.value = tenantImportError(error)
  } finally {
    if (!controller.signal.aborted) { backupBusy.value = false; backupController = undefined }
  }
}
function setBackupCode(event: Event) {
  const input = event.target as HTMLInputElement
  backupCode.value = input.value.trim().toUpperCase()
  input.value = backupCode.value
}
async function downloadBackup() {
  if (!downgradeSource.value || backupBusy.value || locked.value || !/^[A-Z0-9]{8}$/.test(backupCode.value)) return
  const controller = new AbortController()
  backupController = controller
  backupBusy.value = true
  backupError.value = ''
  backupDownloaded.value = false
  try {
    const source = downgradeSource.value
    const blob = await loadTenantDowngradeBackup(source, backupCode.value, controller.signal)
    if (controller.signal.aborted) return
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    try {
      anchor.href = url
      anchor.download = `tenant_${source.id}_original_api.json`
      document.body.appendChild(anchor)
      anchor.click()
      backupDownloaded.value = true
      backupCode.value = ''
    } finally {
      anchor.remove()
      URL.revokeObjectURL(url)
    }
  } catch (error) {
    if (!controller.signal.aborted) backupError.value = tenantImportError(error)
  } finally {
    if (!controller.signal.aborted) { backupBusy.value = false; backupController = undefined }
  }
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
  const displayName = typeof route.query.managedTenantId === 'string' ? form.userName : ''
  Object.assign(form, profile.fields)
  // The pasted profile is the bootstrap administrator, not the dedicated target account.
  if (displayName) form.userName = displayName
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
  if (!provider.value || locked.value || reading.value || backupBusy.value) return
  if (downgradingTenant.value) {
    if (!downgradeSource.value) return
    backupConfirmationInvalid.value = !backupConfirmed.value
    if (!backupConfirmed.value) { root.value?.querySelector<HTMLInputElement>('#downgrade-backup-confirmed')?.focus(); return }
  }
  if (provider.value === 1 && restrictedMode.value) {
    managedNameInvalid.value = !managedUserName.value.trim()
    if (managedNameInvalid.value) {
      root.value?.querySelector<HTMLInputElement>('#import-managed-user')?.focus()
      return
    }
    if (catalogLoading.value || catalogError.value || !permissionCatalog.value.length) return
    const errors = new Set<string>()
    if (selectedPermissions.value.includes('USER_PASSWORD_RESET')) {
      const ids = parseScopeIds(passwordResetUsers.value)
      if (!ids.length || ids.some(id => !/^ocid1\.user\.[A-Za-z0-9._-]+$/.test(id))) errors.add('passwordResetUserIds')
    }
    if (selectedPermissions.value.includes('DOMAIN_USER_MANAGE')) {
      const ids = parseScopeIds(userManagementGroups.value)
      if (!ids.length || ids.some(id => !/^ocid1\.group\.[A-Za-z0-9._-]+$/.test(id))) errors.add('userManagementGroupIds')
    }
    invalidScopeFields.value = errors
    if (errors.size) {
      await nextTick()
      root.value?.querySelector<HTMLTextAreaElement>('.permission-scope-field textarea[aria-invalid="true"]')?.focus()
      return
    }
  }
  if (!downgradingTenant.value) {
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
  }
  const cloud = provider.value
  const file = keyFile.value
  const fields = { ...form }
  for (const field of Object.keys(fields) as Field[]) fields[field] = fields[field].trim()
  const version = pageVersion
  const controller = new AbortController()
  saveController = controller
  saving.value = true
  saveError.value = null
  cleanupWarnings.value = []
  try {
    let warnings: string[] = []
    const options = cloud === 1 && restrictedMode.value
      ? { managedUserName: managedUserName.value, permissions: selectedPermissions.value, accountScope: {
        allUsers: false,
        passwordResetUserIds: selectedPermissions.value.includes('USER_PASSWORD_RESET') ? parseScopeIds(passwordResetUsers.value) : [],
        userManagementGroupIds: selectedPermissions.value.includes('DOMAIN_USER_MANAGE') ? parseScopeIds(userManagementGroups.value) : [],
      } }
      : undefined
    if (downgradingTenant.value && downgradeSource.value && options) {
      warnings = await downgradeTenantCredentials(downgradeSource.value.id, options, backupConfirmed.value, controller.signal)
    } else {
      await saveTenantCredentials(cloud, fields, file!, controller.signal, options)
    }
    if (version !== pageVersion || controller.signal.aborted) return
    cleanupWarnings.value = warnings
    saved.value = true
    // Drop the bootstrap identity immediately after success, even if navigation fails.
    keyFile.value = null
    configText.value = ''
    parsedText.value = ''
    profiles.value = []
    form.tenantId = ''
    form.fingerprint = ''
    ElMessage.success(t(downgradingTenant.value ? 'tenantImport.downgradeSuccess' : 'tenantImport.saveSuccess'))
  } catch (error) {
    if (version === pageVersion && !controller.signal.aborted) saveError.value = error
  } finally {
    if (version === pageVersion && !controller.signal.aborted) { saving.value = false; saveController = undefined }
  }
  if (saved.value && version === pageVersion && !cleanupWarnings.value.length) {
    shell.setCloud(cloud)
    // Saving and navigation have separate outcomes. Keep the saved state if navigation fails.
    void router.push({ path: '/tenants/list', query: { cloudType: String(cloud) } }).catch(() => {})
  }
}
watch([provider, () => route.query.managedTenantId, () => route.query.downgradeTenantId], ([cloud]) => {
  pageVersion += 1
  saveController?.abort()
  saveController = undefined
  saving.value = false
  resetInputs()
  restrictedMode.value = cloud === 1 && (updatingManagedTenant.value || downgradingTenant.value)
  if (restrictedMode.value) void loadPermissionCatalog()
  else {
    catalogController?.abort()
    catalogLoading.value = false
    catalogError.value = null
  }
  if (cloud && shell.cloudType !== cloud) shell.setCloud(cloud)
}, { immediate: true })
watch(selectedPermissions, permissions => {
  const errors = new Set(invalidScopeFields.value)
  if (!permissions.includes('USER_PASSWORD_RESET')) errors.delete('passwordResetUserIds')
  if (!permissions.includes('DOMAIN_USER_MANAGE')) errors.delete('userManagementGroupIds')
  invalidScopeFields.value = errors
})
onBeforeUnmount(() => {
  pageVersion += 1
  saveController?.abort()
  saveController = undefined
  catalogController?.abort()
  resetInputs()
})
</script>

<template>
  <div ref="root" class="tenant-import-page">
    <form class="import-card" novalidate data-motion-enter @submit.prevent="submit">
      <div class="import-toolbar">
        <PageBackButton :disabled="saving" :title="t('tenantImport.back')" @click="goBack" />
        <div class="provider-switch" role="group" :aria-label="t('tenantImport.providerLabel')">
          <button v-for="cloud in providerOptions" :key="cloud" type="button" :aria-pressed="provider === cloud" :disabled="saving || downgradingTenant" @click="changeProvider(cloud)">
            <img :src="cloud === 1 ? '/images/oracle.png' : '/images/google.png'" alt="" />{{ t(`tenantImport.${cloud === 1 ? 'ociProvider' : 'gcpProvider'}`) }}
          </button>
        </div>
        <div class="import-toolbar-actions" data-page-error-anchor>
          <GhostBtn :disabled="saving || saved || catalogLoading || !provider" @click="clearForm">{{ t('tenantImport.clear') }}</GhostBtn>
          <PrimaryBtn type="submit" :loading="saving" :disabled="!provider || reading || saved || backupBusy || (downgradingTenant && (!downgradeSource || !backupConfirmed)) || (provider === 1 && restrictedMode && (catalogLoading || !!catalogError || !permissionCatalog.length))"><i v-if="!saving" class="i-mdi-check" aria-hidden="true" />{{ t(`tenantImport.${saving ? 'saving' : downgradingTenant ? 'downgradeSubmit' : 'save'}`) }}</PrimaryBtn>
        </div>
      </div>

      <div v-if="!provider" class="unsupported-provider" role="status"><i class="i-mdi-cloud-outline" aria-hidden="true" /><p>{{ t('tenantImport.unsupportedProvider') }}</p></div>
      <template v-else>
        <div v-if="saving" class="save-notice" role="status"><i class="i-mdi-loading import-spin" aria-hidden="true" /><span>{{ t(downgradingTenant ? 'tenantImport.downgradePending' : 'tenantImport.savePending') }}</span></div>
        <div v-if="saveError" class="save-notice is-error" role="alert"><div><strong>{{ t(saveOutcomeUnknown ? 'tenantImport.saveUnconfirmed' : 'tenantImport.saveFailed') }}</strong><p>{{ tenantImportError(saveError) }}</p></div></div>
        <div v-if="saveOutcomeUnknown" class="save-notice is-warning" role="status"><span>{{ t(downgradingTenant ? 'tenantImport.downgradeUnknown' : 'tenantImport.saveUnknown') }}</span><button type="button" @click="goBack">{{ t('tenantImport.checkList') }}</button></div>
        <div v-if="saved" class="save-notice" role="status"><i class="i-mdi-check-circle-outline" aria-hidden="true" /><span>{{ t(downgradingTenant ? 'tenantImport.downgradeSuccess' : 'tenantImport.saveSuccess') }}</span><button v-if="!cleanupWarnings.length" type="button" @click="goBack">{{ t('tenantImport.checkList') }}</button></div>
        <div v-if="saved && cleanupWarnings.length" class="save-notice is-warning cleanup-warning" role="alert">
          <div><strong>{{ t('tenantImport.cleanupWarningsTitle') }}</strong><ul><li v-for="(warning, index) in cleanupWarnings" :key="index">{{ warning }}</li></ul><button type="button" @click="goBack">{{ t('tenantImport.checkList') }}</button></div>
        </div>

        <div class="import-scroll">
          <section v-if="downgradingTenant" class="downgrade-section" aria-labelledby="downgrade-title">
            <h2 id="downgrade-title">{{ t('tenantImport.downgradeTitle') }}</h2>
            <p v-if="downgradeSource" class="downgrade-account"><strong>{{ downgradeSource.name }}</strong><span>{{ downgradeSource.region }}</span><span>{{ t('tenantImport.downgradeSourceId', { id: downgradeSource.id }) }}</span></p>
            <p class="section-hint">{{ t('tenantImport.downgradeDescription') }}</p>
            <div class="downgrade-backup" role="note" aria-labelledby="downgrade-backup-title">
              <h3 id="downgrade-backup-title">{{ t('tenantImport.backupTitle') }}</h3>
              <p>{{ t('tenantImport.backupWarning') }}</p>
              <p>{{ t('tenantImport.backupPrivacy') }}</p>
              <p>{{ t('tenantImport.backupCodeLimit') }}</p>
              <div class="backup-actions">
                <button type="button" class="text-button" :disabled="locked || backupBusy || !downgradeSource" @click="sendBackupCode">{{ t(backupCodeSent ? 'tenantImport.backupResendCode' : 'tenantImport.backupSendCode') }}</button>
                <template v-if="backupCodeSent">
                  <label for="downgrade-backup-code">{{ t('tenantImport.backupCode') }}</label>
                  <input id="downgrade-backup-code" :value="backupCode" type="text" inputmode="text" autocapitalize="characters" spellcheck="false" autocomplete="one-time-code" pattern="[A-Z0-9]{8}" maxlength="8" :placeholder="t('tenantImport.backupCodePlaceholder')" :disabled="locked || backupBusy" @input="setBackupCode" @keydown.enter.prevent="downloadBackup" />
                  <button type="button" class="text-button" :disabled="locked || backupBusy || !/^[A-Z0-9]{8}$/.test(backupCode)" @click="downloadBackup">{{ t('tenantImport.backupDownload') }}</button>
                </template>
              </div>
              <p v-if="backupBusy" role="status">{{ t('tenantImport.backupWorking') }}</p>
              <p v-else-if="backupDownloaded" role="status">{{ t('tenantImport.backupDownloaded') }}</p>
              <p v-else-if="backupCodeSent" role="status">{{ t('tenantImport.backupCodeSent') }}</p>
              <p v-if="backupError" class="field-error" role="alert">{{ backupError }}</p>
              <label class="backup-confirmation"><input id="downgrade-backup-confirmed" v-model="backupConfirmed" type="checkbox" :disabled="locked || backupBusy || !downgradeSource" :aria-invalid="backupConfirmationInvalid" @change="backupConfirmationInvalid = false" /><span>{{ t('tenantImport.backupConfirmation') }}</span></label>
              <p v-if="backupConfirmationInvalid" class="field-error" role="alert">{{ t('tenantImport.backupRequired') }}</p>
            </div>
          </section>
          <section v-if="provider === 1 && !downgradingTenant" class="import-mode-section" :aria-label="t('tenantImport.importMode')">
            <h2>{{ t('tenantImport.importMode') }}</h2>
            <div class="import-mode-options">
              <label class="import-mode-option" :class="{ 'is-selected': !restrictedMode }">
                <input type="radio" name="tenant-import-mode" :checked="!restrictedMode" :disabled="saving || saved || updatingManagedTenant" @change="chooseImportMode(false)" />
                <span><strong>{{ t('tenantImport.directMode') }}</strong><small>{{ t('tenantImport.directModeHint') }}</small></span>
              </label>
              <label class="import-mode-option" :class="{ 'is-selected': restrictedMode }">
                <input type="radio" name="tenant-import-mode" :checked="restrictedMode" :disabled="saving || saved || updatingManagedTenant" @change="chooseImportMode(true)" />
                <span><strong>{{ t('tenantImport.restrictedMode') }}</strong><small>{{ t(updatingManagedTenant ? 'tenantImport.managedModeLocked' : 'tenantImport.restrictedModeHint') }}</small></span>
              </label>
            </div>
          </section>
          <div v-if="!downgradingTenant" class="import-columns">
            <section class="config-section" aria-labelledby="import-config-label">
              <div class="section-label-row"><label id="import-config-label" for="import-config">{{ t('tenantImport.configLabel') }}</label><button type="button" class="text-button" :disabled="locked || reading" @click="chooseConfigFile"><i class="i-mdi-file-upload-outline" aria-hidden="true" />{{ t('tenantImport.chooseFile') }}</button></div>
              <p id="import-config-hint" class="section-hint">{{ t(`tenantImport.${configHintKey}`) }}</p>
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
                    <span class="file-description"><strong>{{ keyFile?.name || t('tenantImport.chooseFile') }}</strong><small>{{ keyFile ? fileSize : t(`tenantImport.${keyHintKey}`) }}</small></span>
                    <span class="file-action">{{ t(`tenantImport.${keyFile ? 'replaceFile' : 'chooseFile'}`) }}</span>
                  </button>
                  <button v-if="keyFile" type="button" class="icon-button" :disabled="locked || reading" :aria-label="t('tenantImport.removeFile')" :title="t('tenantImport.removeFile')" @click="removeFile"><i class="i-mdi-close" aria-hidden="true" /></button>
                </div>
                <p v-if="fileErrorKey" id="import-file-error" class="field-error" role="alert">{{ t(`tenantImport.${fileErrorKey}`) }}</p>
                <p v-if="provider === 1 && activeProfile?.keyFileHint" id="import-file-hint" class="field-hint file-path-hint">{{ t('tenantImport.keyFilePathHint', { path: activeProfile.keyFileHint }) }}</p>
                <p v-else id="import-file-hint" class="field-hint">{{ t(`tenantImport.${keyHintKey}`) }}</p>
              </div>
            </section>
          </div>
          <section v-if="provider === 1 && restrictedMode" class="import-permissions" aria-labelledby="import-permissions-title">
            <h2 id="import-permissions-title" class="permission-section-heading"><i class="i-mdi-shield-key-outline" aria-hidden="true" />{{ t('tenantImport.permissionsTitle') }}</h2>
            <div class="form-field managed-user-field">
              <div class="permission-field-label">
                <label for="import-managed-user">{{ t('tenantImport.managedUserName') }}<span class="required-mark" aria-hidden="true">*</span></label>
                <el-popover trigger="click" :width="340" placement="top" popper-class="permission-info-popover">
                  <template #reference><button type="button" class="permission-info-button" :aria-label="t('tenantImport.permissionDetailsFor', { name: t('tenantImport.managedUserName') })" @click.stop.prevent><i class="i-mdi-alert-circle-outline" aria-hidden="true" /></button></template>
                  <div class="permission-info-content"><p>{{ t('tenantImport.managedUserHint') }}</p></div>
                </el-popover>
              </div>
              <input id="import-managed-user" v-model="managedUserName" type="text" autocomplete="off" autocapitalize="off" spellcheck="false" required :disabled="locked" :aria-invalid="managedNameInvalid" :aria-describedby="managedNameInvalid ? 'import-managed-user-error' : undefined" :placeholder="t('tenantImport.managedUserPlaceholder')" @input="managedNameInvalid = false" />
              <p v-if="managedNameInvalid" id="import-managed-user-error" class="field-error">{{ t('tenantImport.requiredField', { field: t('tenantImport.managedUserName') }) }}</p>
            </div>
            <p v-if="catalogLoading" class="permission-loading" role="status"><i class="i-mdi-loading import-spin" aria-hidden="true" />{{ t('tenantImport.permissionsLoading') }}</p>
            <div v-else-if="catalogError && downgradingTenant" class="save-notice is-error" role="alert">{{ tenantImportError(catalogError) }} <button type="button" class="text-button" @click="loadPermissionCatalog">{{ t('tenantImport.retryPermissions') }}</button></div>
            <PageErrorNotice v-else-if="catalogError">{{ tenantImportError(catalogError) }} <button type="button" class="text-button" @click="loadPermissionCatalog">{{ t('tenantImport.retryPermissions') }}</button></PageErrorNotice>
            <template v-else>
              <div class="permission-toolbar">
                <div class="permission-toolbar-title">
                  <h3>{{ t('tenantImport.permissionSelectionTitle') }}</h3>
                  <el-popover trigger="click" :width="340" placement="top" popper-class="permission-info-popover">
                    <template #reference><button type="button" class="permission-info-button" :aria-label="t('tenantImport.permissionNotesTitle')" @click.stop.prevent><i class="i-mdi-alert-circle-outline" aria-hidden="true" /></button></template>
                    <div class="permission-info-content">
                      <p>{{ t(downgradingTenant ? 'tenantImport.downgradeSaveHint' : 'tenantImport.provisionHint') }}</p>
                      <p>{{ t('tenantImport.permissionDefaultsHint') }}</p>
                      <p>{{ t('tenantImport.permissionAccountHint') }}</p>
                      <p v-if="selectedPermissions.includes('INSTANCE_DELETE')">{{ t('tenantImport.permissionDeleteHint') }}</p>
                      <p>{{ t('tenantImport.permissionBoundaryHint') }}</p>
                    </div>
                  </el-popover>
                  <span class="permission-count" role="status">{{ t('tenantImport.permissionSelectedCount', { count: selectedPermissionCount }) }}</span>
                </div>
                <div class="permission-toolbar-actions">
                  <button type="button" class="permission-action" :disabled="locked || !permissionCatalog.length" @click="selectAllPermissions"><i class="i-mdi-checkbox-multiple-marked-outline" aria-hidden="true" />{{ t('tenantImport.permissionSelectAll') }}</button>
                  <button type="button" class="permission-action" :disabled="locked || !permissionCatalog.length" @click="restoreDefaultPermissions"><i class="i-mdi-restore" aria-hidden="true" />{{ t('tenantImport.permissionRestoreDefaults') }}</button>
                </div>
              </div>
              <div class="permission-groups">
                <fieldset v-for="group in permissionGroups" :key="group.name" class="permission-group" :disabled="locked">
                  <legend>
                    <i :class="permissionGroupIcons[group.name]" aria-hidden="true" />
                    <span>{{ permissionGroupLabel(group.name) }}</span>
                    <span class="permission-group-count">{{ group.items.filter(item => selectedPermissions.includes(item.code)).length }} / {{ group.items.length }}</span>
                  </legend>
                  <div class="permission-options">
                    <label v-for="item in group.items" :key="item.code" class="permission-option" :class="{ 'is-selected': selectedPermissions.includes(item.code), 'is-required': item.required, 'is-locked': locked }">
                      <input type="checkbox" :checked="selectedPermissions.includes(item.code)" :disabled="locked || item.required" @change="togglePermission(item, ($event.target as HTMLInputElement).checked)" />
                      <span class="permission-option-content">
                        <span class="permission-option-title">
                          <span>{{ permissionLabel(item) }}</span>
                          <span v-if="item.required" class="permission-badge is-required">{{ t('tenantImport.permissionRequired') }}</span>
                          <span v-else-if="item.defaultEnabled" class="permission-badge">{{ t('tenantImport.permissionDefault') }}</span>
                          <span v-else-if="item.code.startsWith('DOMAIN_')" class="permission-badge is-destructive">{{ t('tenantImport.permissionCombined') }}</span>
                          <span v-else-if="destructivePermissions.has(item.code)" class="permission-badge is-destructive">{{ t('tenantImport.permissionDestructive') }}</span>
                        </span>
                      </span>
                      <el-popover trigger="click" :width="340" placement="top" popper-class="permission-info-popover">
                        <template #reference><button type="button" class="permission-info-button" :aria-label="t('tenantImport.permissionDetailsFor', { name: permissionLabel(item) })" @click.stop.prevent><i class="i-mdi-alert-circle-outline" aria-hidden="true" /></button></template>
                        <div class="permission-info-content">
                          <strong>{{ permissionLabel(item) }}</strong>
                          <p v-if="item.reason">{{ item.reason }}</p>
                          <p v-if="item.code === 'DOMAIN_SECURITY_MANAGE'">{{ t('tenantImport.domainSecurityScope') }}</p>
                          <p v-if="item.code === 'DOMAIN_USER_MANAGE'">{{ t('tenantImport.domainUserScope') }}</p>
                          <p v-if="item.dependencies?.length">{{ t('tenantImport.permissionDependencies', { permissions: permissionDependencies(item) }) }}</p>
                          <p v-if="!item.reason && !item.dependencies?.length">{{ t('tenantImport.permissionBasicInfo') }}</p>
                        </div>
                      </el-popover>
                    </label>
                  </div>
                  <div v-if="group.name === 'account' && (selectedPermissions.includes('USER_PASSWORD_RESET') || selectedPermissions.includes('DOMAIN_USER_MANAGE'))" class="permission-account-scope">
                    <div v-if="selectedPermissions.includes('USER_PASSWORD_RESET')" class="permission-scope-field">
                      <div class="permission-field-label">
                        <label for="password-reset-users">{{ t('tenantImport.passwordResetUsers') }}<span aria-hidden="true">*</span></label>
                        <el-popover trigger="click" :width="340" placement="top" popper-class="permission-info-popover">
                          <template #reference><button type="button" class="permission-info-button" :aria-label="t('tenantImport.permissionDetailsFor', { name: t('tenantImport.passwordResetUsers') })" @click.stop.prevent><i class="i-mdi-alert-circle-outline" aria-hidden="true" /></button></template>
                          <div class="permission-info-content"><p>{{ t('tenantImport.passwordResetUsersHint') }}</p></div>
                        </el-popover>
                      </div>
                      <textarea id="password-reset-users" v-model="passwordResetUsers" rows="3" :disabled="locked" :placeholder="t('tenantImport.passwordResetUsersPlaceholder')" :aria-invalid="invalidScopeFields.has('passwordResetUserIds')" @input="invalidScopeFields.delete('passwordResetUserIds')" />
                      <p v-if="invalidScopeFields.has('passwordResetUserIds')" class="field-error">{{ t('tenantImport.passwordResetUsersInvalid') }}</p>
                    </div>
                    <div v-if="selectedPermissions.includes('DOMAIN_USER_MANAGE')" class="permission-scope-field">
                      <div class="permission-field-label">
                        <label for="user-management-groups">{{ t('tenantImport.userManagementGroups') }}<span aria-hidden="true">*</span></label>
                        <el-popover trigger="click" :width="340" placement="top" popper-class="permission-info-popover">
                          <template #reference><button type="button" class="permission-info-button" :aria-label="t('tenantImport.permissionDetailsFor', { name: t('tenantImport.userManagementGroups') })" @click.stop.prevent><i class="i-mdi-alert-circle-outline" aria-hidden="true" /></button></template>
                          <div class="permission-info-content"><p>{{ t('tenantImport.userManagementGroupsHint') }}</p></div>
                        </el-popover>
                      </div>
                      <textarea id="user-management-groups" v-model="userManagementGroups" rows="3" :disabled="locked" :placeholder="t('tenantImport.userManagementGroupsPlaceholder')" :aria-invalid="invalidScopeFields.has('userManagementGroupIds')" @input="invalidScopeFields.delete('userManagementGroupIds')" />
                      <p v-if="invalidScopeFields.has('userManagementGroupIds')" class="field-error">{{ t('tenantImport.userManagementGroupsInvalid') }}</p>
                    </div>
                  </div>
                  <details v-if="group.unavailable.length" class="permission-unavailable">
                    <summary><i class="i-mdi-information-outline" aria-hidden="true" /><span>{{ t('tenantImport.permissionUnavailableTitle', { count: group.unavailable.length }) }}</span><i class="i-mdi-chevron-down permission-disclosure" aria-hidden="true" /></summary>
                    <p class="permission-unavailable-intro">{{ t('tenantImport.permissionUnavailableHint') }}</p>
                    <ul>
                      <li v-for="item in group.unavailable" :key="item.code">
                        <span class="permission-unavailable-name">{{ permissionLabel(item) }}</span>
                        <span>{{ item.reason || t('tenantImport.permissionUnsupported') }}</span>
                      </li>
                    </ul>
                  </details>
                </fieldset>
              </div>
            </template>
          </section>
        </div>
        <footer class="import-footer"><span v-if="invalidFields.size || fileErrorKey || invalidScopeFields.size" role="status" class="is-error">{{ t('tenantImport.validationSummary') }}</span><span v-else>{{ t(`tenantImport.${saveHintKey}`) }}</span><button type="button" class="text-button" :disabled="saving" @click="goBack">{{ t('tenantImport.cancel') }}</button></footer>
      </template>
    </form>
  </div>
</template>

<style scoped lang="scss" src="./tenant-import.scss"></style>
