<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, shallowRef, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import { isAxiosError } from 'axios'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import PageBackButton from '@/components/PageBackButton.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { usePageMotion } from '@/composables/usePageMotion'
import { useShellStore } from '@/stores/shell'
import { REGION_COORDINATES, regionCityName } from '@/views/regions/regionCoords'
import {
  bootError, generateBootPassword, getBootImages, getBootRegions, isBootTenantId, saveBootTask,
  type BootArchitecture, type BootImage, type BootRegion, type BootTaskInput,
} from '@/api/ociBoot'

type Mode = 'quick' | 'custom'
interface BootTemplate {
  id: string
  label: string
  architecture: BootArchitecture
  ocpu: number
  memory: number
  disk: number
  paid: boolean
}
interface Confirmation {
  input: Omit<BootTaskInput, 'rootPassword'>
  template: BootTemplate
  region: BootRegion
}
interface SaveFailure { key: string; message: string }

const templates: readonly BootTemplate[] = [
  { id: 'arm-basic', label: 'armBasic', architecture: 'ARM', ocpu: 1, memory: 6, disk: 50, paid: false },
  { id: 'arm-standard', label: 'armStandard', architecture: 'ARM', ocpu: 2, memory: 12, disk: 50, paid: false },
  { id: 'arm-performance', label: 'armPerformance', architecture: 'ARM', ocpu: 4, memory: 24, disk: 50, paid: false },
  { id: 'arm-a2', label: 'armA2', architecture: 'ARM_PAID_A2', ocpu: 4, memory: 24, disk: 200, paid: true },
  { id: 'amd-basic', label: 'amdBasic', architecture: 'AMD', ocpu: 1, memory: 1, disk: 50, paid: false },
  { id: 'amd-e3', label: 'amdE3', architecture: 'AMD_PAID_E3', ocpu: 4, memory: 24, disk: 50, paid: true },
  { id: 'amd-e4', label: 'amdE4', architecture: 'AMD_PAID_E4', ocpu: 4, memory: 24, disk: 50, paid: true },
  { id: 'amd-e5', label: 'amdE5', architecture: 'AMD_PAID_E5', ocpu: 4, memory: 24, disk: 50, paid: true },
]
const quickTemplates = templates.filter(template => template.id === 'arm-basic' || template.id === 'amd-basic')
const intervalPresets = [10, 30, 60, 200, 500]
const maxCount = 100
const maxJavaInt = 2147483647
// listRegions uses RegionEnum's Chinese short names, including three distinct suffixes.
const regionNameOverrides: Record<string, string> = {
  'ap-singapore-2': '新加坡西', 'eu-madrid-1': '马德里-1', 'eu-madrid-3': '马德里-3',
}
const codeByRegionName = new Map<string, string>(Object.keys(REGION_COORDINATES).map(code => [regionNameOverrides[code] || regionCityName(code, 'zh'), code]))
const route = useRoute()
const router = useRouter()
const shell = useShellStore()
const { t, locale } = useI18n()
const root = ref<HTMLElement | null>(null)
const confirmActions = ref<HTMLElement | null>(null)
usePageMotion(root)
const numberFormat = computed(() => new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN'))
const number = (value: number) => numberFormat.value.format(value)
const parentId = computed(() => {
  const value = route.query.tenantId
  return isBootTenantId(value) ? value : ''
})
const preferredRegionId = computed(() => isBootTenantId(route.query.regionId) ? route.query.regionId : '')
const regions = shallowRef<BootRegion[]>([])
const regionId = ref('')
const regionsLoading = ref(false)
const regionsReady = ref(false)
const regionsError = shallowRef<unknown>(null)
const selectedRegion = computed(() => regionsReady.value ? regions.value.find(region => region.id === regionId.value) : undefined)
const mode = ref<Mode>('quick')
const quickTemplateId = ref('arm-basic')
const customTemplateId = ref('')
const templateId = computed({
  get: () => mode.value === 'quick' ? quickTemplateId.value : customTemplateId.value,
  set: (id: string) => {
    if (locked.value) return
    if (mode.value === 'quick') quickTemplateId.value = id
    else customTemplateId.value = id
  },
})
const visibleTemplates = computed(() => mode.value === 'quick' ? quickTemplates : templates)
const selectedTemplate = computed(() => visibleTemplates.value.find(template => template.id === templateId.value))
const countInput = ref('1')
const intervalInput = ref('60')
const dayGap = ref('')
const useDefaultImage = ref(false)
const images = shallowRef<BootImage[]>([])
const imagesLoading = ref(false)
const imagesError = shallowRef<unknown>(null)
const selectedOs = ref('')
const selectedImageId = ref('')
const imageContext = ref('')
const operatingSystems = computed(() => [...new Set(images.value.map(image => image.operatingSystem))])
const systemVersions = computed(() => images.value.filter(image => image.operatingSystem === selectedOs.value))
const currentImageContext = computed(() => `${regionId.value}:${selectedTemplate.value?.architecture || ''}`)
const selectedImage = computed(() => imageContext.value === currentImageContext.value
  ? systemVersions.value.find(image => image.imageId === selectedImageId.value) : undefined)
const attempted = ref(false)
const confirmOpen = ref(false)
const confirmation = shallowRef<Confirmation | null>(null)
const creating = ref(false)
const saved = ref(false)
const saveFailure = shallowRef<SaveFailure | null>(null)
const saveUncertain = ref(false)
const requestMayHaveRun = ref(false)
const submittedRegionId = ref('')
const locked = computed(() => creating.value || confirmOpen.value || saved.value || saveUncertain.value)
const countValid = computed(() => validInteger(countInput.value, maxCount))
const intervalValid = computed(() => validInteger(intervalInput.value, maxJavaInt))
const dayGapValid = computed(() => validWindow(dayGap.value.trim()))
const needsImage = computed(() => mode.value === 'custom' && !useDefaultImage.value)
const imageValid = computed(() => !needsImage.value || Boolean(selectedImage.value))
const hasErrors = computed(() => !selectedRegion.value || !selectedTemplate.value
  || (mode.value === 'custom' && (!countValid.value || !intervalValid.value || !dayGapValid.value || !imageValid.value)))
const createDisabled = computed(() => locked.value || regionsLoading.value || !selectedRegion.value || imagesLoading.value)
let pageVersion = 0
let regionVersion = 0
let imageVersion = 0
let disposed = false
let regionController: AbortController | undefined
let imageController: AbortController | undefined
let saveController: AbortController | undefined

function validInteger(value: string, maximum: number): boolean {
  return /^\d+$/.test(value.trim()) && Number.isInteger(Number(value)) && Number(value) >= 1 && Number(value) <= maximum
}
function validWindow(value: string): boolean {
  if (!value) return true
  const match = /^(\d{1,2})-(\d{1,2})$/.exec(value)
  if (!match) return false
  const start = Number(match[1])
  const end = Number(match[2])
  return start >= 0 && start <= 23 && end >= 1 && end <= 24 && start < end
}
function inputValue(event: Event): string { return (event.target as HTMLInputElement).value }
function templateSpecs(template: BootTemplate): string {
  return t('ociBoot.specs', { cpu: number(template.ocpu), memory: number(template.memory), disk: number(template.disk) })
}
function regionLabel(region: BootRegion): string {
  const code = codeByRegionName.get(region.region) || region.region
  const city = locale.value.startsWith('zh') && codeByRegionName.has(region.region)
    ? region.region : regionCityName(code, locale.value)
  return city && city !== code ? `${city} · ${code}` : code
}
function versionLabel(image: BootImage): string {
  const duplicates = systemVersions.value.filter(item => item.operatingSystemVersion === image.operatingSystemVersion)
  return duplicates.length > 1 ? `${image.operatingSystemVersion} · ${image.imageId.slice(-12)}` : image.operatingSystemVersion
}
function windowLabel(value: string): string {
  if (!value || value === '0-24') return t('ociBoot.allDay')
  const match = /^(\d{1,2})-(\d{1,2})$/.exec(value)
  return match ? `${number(Number(match[1]))}:00 – ${number(Number(match[2]))}:00` : value
}
function setMode(value: Mode) {
  if (locked.value || mode.value === value) return
  mode.value = value
  attempted.value = false
}
function resetConfiguration() {
  if (locked.value) return
  mode.value = 'quick'
  quickTemplateId.value = 'arm-basic'
  customTemplateId.value = ''
  countInput.value = '1'
  intervalInput.value = '60'
  dayGap.value = ''
  useDefaultImage.value = false
  attempted.value = false
  saveFailure.value = null
  requestMayHaveRun.value = false
}
function stopImages() {
  imageVersion += 1
  imageController?.abort()
  imageController = undefined
  images.value = []
  imagesLoading.value = false
  imagesError.value = null
  imageContext.value = ''
  selectedOs.value = ''
  selectedImageId.value = ''
}
async function loadRegions() {
  if (locked.value || !parentId.value) return
  const requestedParent = parentId.value
  const previousId = regionId.value
  const version = ++regionVersion
  regionController?.abort()
  const controller = new AbortController()
  regionController = controller
  regionsReady.value = false
  regionsLoading.value = true
  regionsError.value = null
  stopImages()
  try {
    const result = await getBootRegions(requestedParent, controller.signal)
    if (disposed || version !== regionVersion || controller.signal.aborted) return
    regions.value = result
    regionId.value = result.find(region => region.id === preferredRegionId.value)?.id
      || result.find(region => region.id === previousId)?.id
      || result.find(region => region.isHomeRegion)?.id || result[0]?.id || ''
    regionsReady.value = true
  } catch (error) {
    if (disposed || version !== regionVersion || controller.signal.aborted) return
    regions.value = []
    regionId.value = ''
    regionsError.value = error
  } finally {
    if (!disposed && version === regionVersion) regionsLoading.value = false
  }
}
async function loadImages() {
  stopImages()
  const region = selectedRegion.value
  const template = selectedTemplate.value
  if (disposed || mode.value !== 'custom' || useDefaultImage.value || !region || !template) return
  const version = imageVersion
  const context = currentImageContext.value
  const controller = new AbortController()
  imageController = controller
  imagesLoading.value = true
  try {
    const result = await getBootImages(region.id, template.architecture, controller.signal)
    if (disposed || controller.signal.aborted || version !== imageVersion || context !== currentImageContext.value) return
    // Keep the server's ordering while avoiding duplicate option keys.
    images.value = result.filter((image, index) => result.findIndex(item => item.imageId === image.imageId) === index)
    imageContext.value = context
    selectedOs.value = images.value[0]?.operatingSystem || ''
    selectedImageId.value = images.value[0]?.imageId || ''
  } catch (error) {
    if (disposed || controller.signal.aborted || version !== imageVersion) return
    imagesError.value = error
  } finally {
    if (!disposed && version === imageVersion) imagesLoading.value = false
  }
}
watch([regionId, () => selectedTemplate.value?.architecture, mode, useDefaultImage, regionsReady], () => { void loadImages() })
watch(selectedOs, os => {
  if (!systemVersions.value.some(image => image.imageId === selectedImageId.value)) {
    selectedImageId.value = images.value.find(image => image.operatingSystem === os)?.imageId || ''
  }
})
watch([() => route.query.tenantId, () => route.query.regionId], () => {
  pageVersion += 1
  regionVersion += 1
  regionController?.abort()
  saveController?.abort()
  stopImages()
  regions.value = []
  regionId.value = ''
  regionsReady.value = false
  regionsLoading.value = false
  regionsError.value = null
  confirmOpen.value = false
  confirmation.value = null
  creating.value = false
  saved.value = false
  saveUncertain.value = false
  submittedRegionId.value = ''
  resetConfiguration()
  shell.setCloud(1)
  if (parentId.value) void loadRegions()
}, { immediate: true })

async function prepareSubmission() {
  if (locked.value || regionsLoading.value || imagesLoading.value) return
  attempted.value = true
  if (hasErrors.value || !selectedRegion.value || !selectedTemplate.value) {
    await nextTick()
    root.value?.querySelector<HTMLElement>('[data-template-invalid="true"] input, input[aria-invalid="true"], [aria-invalid="true"] input')?.focus()
    return
  }
  const template = selectedTemplate.value
  const region = selectedRegion.value
  const image = needsImage.value ? selectedImage.value : undefined
  confirmation.value = {
    template: { ...template },
    region: { ...region },
    input: {
      tenantId: region.id, architecture: template.architecture,
      ocpu: template.ocpu, memory: template.memory, disk: template.disk,
      // Quick mode has its own effective defaults; a custom draft must never leak into it.
      instanceCount: mode.value === 'quick' ? 1 : Number(countInput.value),
      loopTime: mode.value === 'quick' ? 60 : Number(intervalInput.value),
      dayGap: mode.value === 'quick' ? '' : dayGap.value.trim(),
      operatingSystem: image?.operatingSystem || '',
      operatingSystemVersion: image?.operatingSystemVersion || '',
      imageId: image?.imageId || '',
    },
  }
  confirmOpen.value = true
}
function focusConfirmationCancel() { confirmActions.value?.querySelector<HTMLButtonElement>('button')?.focus() }
function clearConfirmation() { if (!confirmOpen.value) confirmation.value = null }
function captureSaveFailure(error: unknown) {
  // Do not retain an Axios config/FormData containing the generated password in UI state.
  const message = bootError(error)
  const key = ['invalidResponse', 'requestFailed', 'networkError', 'timeoutError', 'invalidTenant', 'passwordUnavailable']
    .find(value => t(`ociBoot.${value}`) === message)
  const failure = { key: key || '', message: key ? '' : message }
  saveFailure.value = failure
  return failure
}
async function submitConfirmed() {
  const pending = confirmation.value
  if (creating.value || saved.value || saveUncertain.value || !confirmOpen.value || !pending) return
  if (!regionsReady.value || !regions.value.some(region => region.id === pending.input.tenantId)) {
    confirmOpen.value = false
    saveFailure.value = { key: 'regionUnavailable', message: '' }
    return
  }
  creating.value = true
  confirmOpen.value = false
  saveFailure.value = null
  requestMayHaveRun.value = false
  const version = pageVersion
  const controller = new AbortController()
  saveController = controller
  try {
    const rootPassword = generateBootPassword()
    submittedRegionId.value = pending.input.tenantId
    requestMayHaveRun.value = true
    await saveBootTask({ ...pending.input, rootPassword }, controller.signal)
    if (disposed || version !== pageVersion || controller.signal.aborted) return
    saved.value = true
    ElMessage.success(t('ociBoot.saveSuccess'))
  } catch (error) {
    if (disposed || version !== pageVersion || controller.signal.aborted) return
    const failure = captureSaveFailure(error)
    // A lost acknowledgement cannot safely be treated as a failed, retryable write.
    saveUncertain.value = requestMayHaveRun.value && (
      (isAxiosError(error) && (!error.response || error.response.status >= 500))
      || failure.key === 'invalidResponse'
    )
  } finally {
    if (!disposed && version === pageVersion) creating.value = false
  }
  // Navigation failure must not turn a successful write into a retryable form.
  if (!disposed && version === pageVersion && saved.value) await viewTasks()
}
async function viewTasks() {
  const tenantId = submittedRegionId.value || selectedRegion.value?.id
  if (!tenantId) return
  try { await router.push({ path: '/tenants/bootList', query: { tenantId, cloudType: '1' } }) }
  catch { /* Keep the success notice and its navigation action available. */ }
}
function goBack() {
  if (creating.value || confirmOpen.value) return
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push({ path: '/tenants/list', query: { cloudType: '1' } })
}
onBeforeRouteLeave(() => !creating.value)
onBeforeRouteUpdate(() => !creating.value)
onBeforeUnmount(() => {
  disposed = true
  pageVersion += 1
  regionVersion += 1
  regionController?.abort()
  stopImages()
  saveController?.abort()
})
</script>

<template>
  <div ref="root" class="oci-boot-page">
    <form class="boot-card" data-motion-enter novalidate :aria-busy="creating || undefined" @submit.prevent="prepareSubmission">
      <div class="boot-toolbar">
        <PageBackButton :disabled="creating || confirmOpen" @click="goBack" />
        <div class="boot-region-picker">
          <label class="sr-only" for="boot-region">{{ t('ociBoot.region') }}</label>
          <el-select id="boot-region" v-model="regionId" filterable :disabled="locked || regionsLoading || !regions.length" :loading="regionsLoading" :placeholder="t('ociBoot.selectRegion')" :aria-label="t('ociBoot.region')">
            <el-option v-for="region in regions" :key="region.id" :value="region.id" :label="`${regionLabel(region)}${region.isHomeRegion ? ` · ${t('ociBoot.homeRegion')}` : ''}`" />
          </el-select>
        </div>
        <div class="boot-mode-switch" role="group" :aria-label="t('ociBoot.modeLabel')">
          <button type="button" :aria-pressed="mode === 'quick'" :disabled="locked" @click="setMode('quick')">{{ t('ociBoot.quick') }}</button>
          <button type="button" :aria-pressed="mode === 'custom'" :disabled="locked" @click="setMode('custom')">{{ t('ociBoot.custom') }}</button>
        </div>
        <div class="boot-toolbar-actions" data-page-error-anchor>
          <button type="button" class="text-button" :disabled="locked" @click="resetConfiguration">{{ t('ociBoot.reset') }}</button>
          <PrimaryBtn type="submit" :loading="creating" :disabled="createDisabled"><i v-if="!creating" class="i-mdi-play-outline" aria-hidden="true" />{{ t(`ociBoot.${creating ? 'creating' : 'create'}`) }}</PrimaryBtn>
        </div>
      </div>

      <div v-if="creating" class="boot-notice is-pending" role="status"><i class="i-mdi-loading boot-spin" aria-hidden="true" /><div>{{ t('ociBoot.savePending') }}</div></div>
      <div v-else-if="saved" class="boot-notice is-success" role="status"><i class="i-mdi-check-circle-outline" aria-hidden="true" /><div>{{ t('ociBoot.saveSuccess') }}</div><button type="button" class="text-button" @click="viewTasks">{{ t('ociBoot.viewTasks') }}</button></div>
      <div v-else-if="saveFailure && saveUncertain" class="boot-notice is-error" role="alert">
        <i class="i-mdi-alert-circle-outline" aria-hidden="true" />
        <div><strong>{{ t(saveUncertain ? 'ociBoot.saveUnconfirmed' : 'ociBoot.saveFailed') }}</strong><p>{{ saveFailure.key ? t(`ociBoot.${saveFailure.key}`) : saveFailure.message }}</p><p v-if="requestMayHaveRun">{{ t('ociBoot.saveUnknown') }}</p></div>
        <button v-if="submittedRegionId && requestMayHaveRun" type="button" class="text-button" @click="viewTasks">{{ t('ociBoot.viewTasks') }}</button>
      </div>
      <template v-else-if="saveFailure">
        <PageErrorNotice class="boot-error-notice" :title="t('ociBoot.saveFailed')">{{ saveFailure.key ? t(`ociBoot.${saveFailure.key}`) : saveFailure.message }}</PageErrorNotice>
        <div v-if="requestMayHaveRun" class="boot-notice is-error" role="alert"><div>{{ t('ociBoot.saveUnknown') }}</div><button v-if="submittedRegionId" type="button" class="text-button" @click="viewTasks">{{ t('ociBoot.viewTasks') }}</button></div>
      </template>

      <div class="boot-scroll">
        <div v-if="!parentId" class="boot-empty" role="status"><i class="i-mdi-account-alert-outline" aria-hidden="true" /><strong>{{ t('ociBoot.invalidTenant') }}</strong><p>{{ t('ociBoot.invalidTenantHint') }}</p></div>
        <div v-else-if="regionsLoading" class="boot-empty" role="status"><i class="i-mdi-loading boot-spin" aria-hidden="true" /><p>{{ t('ociBoot.regionsLoading') }}</p></div>
        <PageErrorNotice v-else-if="regionsError" class="boot-load-notice" :title="t('ociBoot.regionsFailed')"><span>{{ bootError(regionsError) }}</span><GhostBtn @click="loadRegions">{{ t('ociBoot.retry') }}</GhostBtn></PageErrorNotice>
        <div v-else-if="!regions.length" class="boot-empty" role="status"><i class="i-mdi-map-marker-outline" aria-hidden="true" /><strong>{{ t('ociBoot.noRegions') }}</strong><p>{{ t('ociBoot.noRegionsHint') }}</p><GhostBtn @click="loadRegions">{{ t('ociBoot.retry') }}</GhostBtn></div>
        <template v-else>
          <div class="boot-risk-strip"><i class="i-mdi-information-outline" aria-hidden="true" /><div><strong>{{ t('ociBoot.riskTitle') }}</strong><p>{{ t('ociBoot.riskBanner') }}</p></div></div>
          <div class="boot-columns">
            <section class="template-section" aria-labelledby="boot-template-label">
              <div class="section-heading"><h2 id="boot-template-label">{{ t('ociBoot.templates') }}</h2><p>{{ mode === 'quick' ? t('ociBoot.quickHint', { count: number(1), seconds: number(60) }) : t('ociBoot.customHint') }}</p></div>
              <div class="template-grid" :class="{ 'quick-grid': mode === 'quick' }" role="radiogroup" aria-labelledby="boot-template-label" :aria-describedby="attempted && !selectedTemplate ? 'boot-template-error' : undefined" :data-template-invalid="attempted && !selectedTemplate || undefined">
                <label v-for="template in visibleTemplates" :key="template.id" class="template-option" :class="{ 'is-selected': templateId === template.id }">
                  <input v-model="templateId" type="radio" name="boot-template" :value="template.id" :disabled="locked" />
                  <span class="template-top"><strong class="template-name">{{ t(`ociBoot.${template.label}`) }}</strong><span class="template-check" aria-hidden="true"><i v-if="templateId === template.id" class="i-mdi-check" /></span></span>
                  <span class="template-specs">{{ templateSpecs(template) }}</span>
                  <span v-if="template.paid" class="paid-badge">{{ t('ociBoot.paidTemplate') }}</span>
                </label>
              </div>
              <p v-if="attempted && !selectedTemplate" id="boot-template-error" class="field-error" role="alert">{{ t('ociBoot.templateRequired') }}</p>
              <div class="password-note"><i class="i-mdi-key-outline" aria-hidden="true" /><div><strong>{{ t('ociBoot.autoPassword') }}</strong><p>{{ t('ociBoot.passwordHint') }}</p></div></div>
            </section>

            <section class="settings-section" :aria-label="t('ociBoot.deployment')">
              <template v-if="mode === 'quick'">
                <div class="section-heading"><h2>{{ t('ociBoot.deployment') }}</h2><p v-if="selectedTemplate" class="summary-specs">{{ t(`ociBoot.${selectedTemplate.label}`) }} · {{ templateSpecs(selectedTemplate) }}</p></div>
                <dl class="config-summary">
                  <div><dt>{{ t('ociBoot.summaryRegion') }}</dt><dd>{{ selectedRegion ? regionLabel(selectedRegion) : '—' }}</dd></div>
                  <div><dt>{{ t('ociBoot.summaryImage') }}</dt><dd>{{ t('ociBoot.defaultImage') }}</dd></div>
                  <div><dt>{{ t('ociBoot.instanceCount') }}</dt><dd>{{ number(1) }}</dd></div>
                  <div><dt>{{ t('ociBoot.interval') }}</dt><dd>{{ t('ociBoot.intervalPreset', { seconds: number(60) }) }}</dd></div>
                  <div><dt>{{ t('ociBoot.summaryWindow') }}</dt><dd>{{ t('ociBoot.allDay') }}</dd></div>
                </dl>
              </template>
              <div v-else-if="!selectedTemplate" class="boot-empty"><i class="i-mdi-tune-variant" aria-hidden="true" /><p>{{ t('ociBoot.noTemplateHint') }}</p></div>
              <template v-else>
                <div class="form-section">
                  <div class="section-label"><h3>{{ t('ociBoot.imageTitle') }}</h3><label class="default-image-toggle"><input v-model="useDefaultImage" type="checkbox" :disabled="locked" />{{ t('ociBoot.useDefaultImage') }}</label></div>
                  <p class="field-hint">{{ t(useDefaultImage ? 'ociBoot.defaultImageHint' : 'ociBoot.imageHint') }}</p>
                  <div v-if="useDefaultImage" class="inline-state"><i class="i-mdi-layers-outline" aria-hidden="true" /><div>{{ t('ociBoot.defaultImage') }}</div></div>
                  <div v-else-if="imagesLoading" class="inline-state" role="status"><i class="i-mdi-loading boot-spin" aria-hidden="true" /><div>{{ t('ociBoot.imagesLoading') }}</div></div>
                  <PageErrorNotice v-else-if="imagesError" class="boot-image-error" :title="t('ociBoot.imagesFailed')"><div><p>{{ bootError(imagesError) }}</p><p>{{ t('ociBoot.noImagesHint') }}</p></div><button type="button" class="text-button" :disabled="locked" @click="loadImages">{{ t('ociBoot.retry') }}</button></PageErrorNotice>
                  <div v-else-if="!images.length" class="inline-state" role="status">
                    <i class="i-mdi-image-outline" aria-hidden="true" /><div><p>{{ t('ociBoot.noImages') }}</p><p>{{ t('ociBoot.noImagesHint') }}</p><button type="button" class="text-button" :disabled="locked" @click="loadImages">{{ t('ociBoot.retry') }}</button></div>
                  </div>
                  <div v-else class="image-fields">
                    <div class="form-field"><label for="boot-os">{{ t('ociBoot.operatingSystem') }}</label><el-select id="boot-os" v-model="selectedOs" :disabled="locked" :placeholder="t('ociBoot.selectOs')" :aria-label="t('ociBoot.operatingSystem')" :aria-invalid="attempted && !imageValid || undefined"><el-option v-for="os in operatingSystems" :key="os" :value="os" :label="os" /></el-select></div>
                    <div class="form-field"><label for="boot-version">{{ t('ociBoot.systemVersion') }}</label><el-select id="boot-version" v-model="selectedImageId" :disabled="locked" :placeholder="t('ociBoot.selectVersion')" :aria-label="t('ociBoot.systemVersion')" :aria-invalid="attempted && !imageValid || undefined"><el-option v-for="image in systemVersions" :key="image.imageId" :value="image.imageId" :label="versionLabel(image)" /></el-select></div>
                  </div>
                  <p v-if="attempted && !imageValid && !imagesLoading" class="field-error" role="alert">{{ t('ociBoot.imageRequired') }}</p>
                </div>

                <div class="form-section">
                  <div class="section-label"><h3>{{ t('ociBoot.deployment') }}</h3></div>
                  <div class="deployment-fields">
                    <div class="form-field">
                      <label for="boot-count">{{ t('ociBoot.instanceCount') }}</label><input id="boot-count" type="number" inputmode="numeric" min="1" :max="maxCount" step="1" :value="countInput" :disabled="locked" :aria-invalid="attempted && !countValid || undefined" :aria-describedby="attempted && !countValid ? 'boot-count-error' : 'boot-count-hint'" @input="countInput = inputValue($event)" />
                      <p v-if="attempted && !countValid" id="boot-count-error" class="field-error">{{ t('ociBoot.countInvalid', { max: number(maxCount) }) }}</p><p v-else id="boot-count-hint" class="field-hint">{{ t('ociBoot.countHint', { max: number(maxCount) }) }}</p>
                    </div>
                    <div class="form-field">
                      <label for="boot-day-gap">{{ t('ociBoot.dayGap') }}</label><input id="boot-day-gap" type="text" :value="dayGap" :disabled="locked" :placeholder="t('ociBoot.dayGapPlaceholder')" :aria-invalid="attempted && !dayGapValid || undefined" :aria-describedby="attempted && !dayGapValid ? 'boot-day-error' : 'boot-day-hint'" @input="dayGap = inputValue($event)" />
                      <p v-if="attempted && !dayGapValid" id="boot-day-error" class="field-error">{{ t('ociBoot.dayGapInvalid') }}</p><p v-else id="boot-day-hint" class="field-hint">{{ t('ociBoot.dayGapHint') }}</p>
                    </div>
                    <div class="form-field wide-field">
                      <label id="boot-interval-label" for="boot-interval">{{ t('ociBoot.interval') }}</label>
                      <div class="interval-options" role="group" aria-labelledby="boot-interval-label"><button v-for="seconds in intervalPresets" :key="seconds" type="button" :aria-pressed="intervalInput === String(seconds)" :disabled="locked" @click="intervalInput = String(seconds)">{{ t('ociBoot.intervalPreset', { seconds: number(seconds) }) }}</button></div>
                      <input id="boot-interval" type="number" inputmode="numeric" min="1" :max="maxJavaInt" step="1" :value="intervalInput" :disabled="locked" :aria-label="t('ociBoot.customInterval')" :aria-invalid="attempted && !intervalValid || undefined" :aria-describedby="attempted && !intervalValid ? 'boot-interval-error' : 'boot-interval-hint'" @input="intervalInput = inputValue($event)" />
                      <p v-if="attempted && !intervalValid" id="boot-interval-error" class="field-error">{{ t('ociBoot.intervalInvalid') }}</p><p id="boot-interval-hint" class="field-hint">{{ t('ociBoot.intervalHint') }}</p>
                    </div>
                  </div>
                </div>
              </template>
            </section>
          </div>
        </template>
      </div>
      <div class="boot-footer" aria-live="polite">
        <span v-if="selectedRegion">{{ t('ociBoot.tenantContext', { name: selectedRegion.tenancyName || selectedRegion.userName || regionLabel(selectedRegion) }) }}</span>
        <span v-if="attempted && hasErrors" class="field-error">{{ t('ociBoot.validationSummary') }}</span>
        <span v-else-if="selectedTemplate">{{ t(`ociBoot.${selectedTemplate.label}`) }} · {{ templateSpecs(selectedTemplate) }}</span>
      </div>
    </form>

    <el-dialog v-model="confirmOpen" :title="t('ociBoot.riskTitle')" width="min(520px, calc(100vw - 32px))" align-center append-to-body :close-on-click-modal="false" @opened="focusConfirmationCancel" @closed="clearConfirmation">
      <div v-if="confirmation" class="boot-confirm">
        <div class="confirm-risk"><i class="i-mdi-alert-outline" aria-hidden="true" /><p>{{ t('ociBoot.riskDialog') }}</p></div>
        <h3>{{ t('ociBoot.confirmSummary') }}</h3>
        <dl class="config-summary">
          <div><dt>{{ t('ociBoot.summaryRegion') }}</dt><dd>{{ regionLabel(confirmation.region) }}</dd></div>
          <div><dt>{{ t('ociBoot.summaryTemplate') }}</dt><dd>{{ t(`ociBoot.${confirmation.template.label}`) }}<span v-if="confirmation.template.paid" class="paid-badge">{{ t('ociBoot.paidTemplate') }}</span><small class="summary-specs">{{ templateSpecs(confirmation.template) }}</small></dd></div>
          <div><dt>{{ t('ociBoot.summaryImage') }}</dt><dd>{{ confirmation.input.imageId ? `${confirmation.input.operatingSystem} ${confirmation.input.operatingSystemVersion}` : t('ociBoot.defaultImage') }}</dd></div>
          <div><dt>{{ t('ociBoot.summaryWindow') }}</dt><dd>{{ windowLabel(confirmation.input.dayGap) }}</dd></div>
        </dl>
        <div class="confirm-counts"><span>{{ t('ociBoot.summaryCount', { count: number(confirmation.input.instanceCount) }) }}</span><span>{{ t('ociBoot.summaryInterval', { seconds: number(Math.max(12, confirmation.input.loopTime)) }) }}</span></div>
      </div>
      <template #footer><div ref="confirmActions" class="confirm-actions"><GhostBtn @click="confirmOpen = false">{{ t('ociBoot.cancel') }}</GhostBtn><PrimaryBtn :loading="creating" @click="submitConfirmed">{{ t('ociBoot.riskConfirm') }}</PrimaryBtn></div></template>
    </el-dialog>
  </div>
</template>

<style scoped lang="scss" src="./oci-boot.scss"></style>
