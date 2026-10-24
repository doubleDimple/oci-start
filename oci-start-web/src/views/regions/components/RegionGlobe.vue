<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, useId, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { RegionGlobePoint } from '../globeTypes'
import type { RegionScene, RegionSceneColors, RegionSceneOptions } from '../sceneTypes'
import { REGION_SCENE_ERROR_EVENT } from '../sceneTypes'
import { regionCityName } from '../regionCoords'

const props = defineProps<{ points: RegionGlobePoint[]; active: boolean; selectedRegion: string | null }>()
const emit = defineEmits<{ select: [code: string | null] }>()
const { t, locale } = useI18n()
const root = ref<HTMLElement | null>(null)
const sceneHost = ref<HTMLElement | null>(null)
const labelHost = ref<HTMLElement | null>(null)
const mapTheme = ref<'dark' | 'light'>('dark')
const pickerOpen = ref(false)
const linksEnabled = ref(true)
const labelsEnabled = ref(true)
const pulseEnabled = ref(true)
const reducedMotion = ref(false)
const loading = ref(false)
const ready = ref(false)
const failed = ref(false)
const inViewport = ref(false)
const documentVisible = ref(true)
const id = useId()
const selectId = `${id}-region`
const helpId = `${id}-help`
const canRender = computed(() => props.active && inViewport.value && documentVisible.value && !failed.value)
const pointList = computed(() => props.points.filter(point =>
  (point.isOpen || point.isMine) && Number.isFinite(point.lat) && Number.isFinite(point.lng)
  && Math.abs(point.lat) <= 90 && Math.abs(point.lng) <= 180,
))
const selected = computed(() => pointList.value.find(point => point.regionCode === props.selectedRegion) || null)
const panelOnLeft = computed(() => (selected.value?.lng ?? 0) > 0)
const panelOnTop = computed(() => (selected.value?.lat ?? 0) < 0)
const dateFormatter = computed(() => new Intl.DateTimeFormat(locale.value.startsWith('zh') ? 'zh-CN' : 'en-US', { dateStyle: 'medium', timeStyle: 'medium' }))
const legend = computed(() => [
  { key: 'arm', label: t('regionGlobe.armRecorded') },
  { key: 'mine', label: t('regionGlobe.mine') },
  { key: 'both', label: t('regionGlobe.both') },
])
const mapStyle = computed<Record<string, string>>(() => ({
  '--map-surface': `var(--region-map-${mapTheme.value}-surface)`,
  '--map-land': `var(--region-map-${mapTheme.value}-land)`,
  '--map-text': `var(--region-map-${mapTheme.value}-text)`,
  '--map-muted': `var(--region-map-${mapTheme.value}-muted)`,
  '--map-arm': mapTheme.value === 'dark' ? 'var(--region-map-arm)' : 'var(--status-warn)',
  '--map-mine': mapTheme.value === 'dark' ? 'var(--region-map-mine)' : 'var(--brand)',
}))
let scene: RegionScene | null = null
let generation = 0
let disposed = false
let resizeFrame = 0
let resizeObserver: ResizeObserver | null = null
let intersectionObserver: IntersectionObserver | null = null
let themeObserver: MutationObserver | null = null
let motionQuery: MediaQueryList | null = null

function cityName(point: RegionGlobePoint) { return regionCityName(point.regionCode, locale.value) }
function regionOptionLabel(point: RegionGlobePoint) { return `${cityName(point)} · ${point.regionCode}` }
function categoryText(point: RegionGlobePoint) {
  return [point.isOpen && t('regionGlobe.armRecorded'), point.isMine && t('regionGlobe.mine')].filter(Boolean).join(' · ')
}
function markerAriaLabel(point: RegionGlobePoint) { return `${point.name}, ${point.regionCode}, ${categoryText(point)}` }
function formatCount(value: number) {
  return Number.isFinite(value) ? new Intl.NumberFormat(locale.value).format(value) : t('regionGlobe.unavailable')
}
function formatDateTime(value: string | null) {
  if (!value) return t('regionGlobe.unavailable')
  const date = new Date(value.replace(/^(\d{4}-\d{2}-\d{2}) /, '$1T'))
  return Number.isNaN(date.getTime()) ? value : dateFormatter.value.format(date)
}
function readColors(): RegionSceneColors {
  const style = getComputedStyle(root.value!)
  const token = (name: string) => style.getPropertyValue(name).trim()
  const prefix = `--region-map-${mapTheme.value}`
  return {
    surface: token(`${prefix}-surface`), land: token(`${prefix}-land`),
    text: token(`${prefix}-text`), muted: token(`${prefix}-muted`),
    grid: token('--region-map-grid'),
    arm: token(mapTheme.value === 'dark' ? '--region-map-arm' : '--status-warn'),
    mine: token(mapTheme.value === 'dark' ? '--region-map-mine' : '--brand'),
  }
}
function releaseScene() {
  const previous = scene
  scene = null
  ready.value = false
  if (resizeFrame) cancelAnimationFrame(resizeFrame)
  resizeFrame = 0
  try { previous?.dispose() }
  catch { /* A rendering failure may already have released engine resources. */ }
  sceneHost.value?.replaceChildren()
  labelHost.value?.replaceChildren()
}
function onSceneError() {
  if (disposed) return
  generation += 1
  loading.value = false
  failed.value = true
  releaseScene()
}
function withScene(action: (instance: RegionScene) => void) {
  if (!scene || disposed) return
  try { action(scene) }
  catch { onSceneError() }
}
function chooseRegion(code: string) {
  if (!pointList.value.some(point => point.regionCode === code)) return
  emit('select', code)
  if (props.selectedRegion === code) withScene(instance => instance.setSelected(code))
}
function selectFromList(value: unknown) {
  if (typeof value === 'string' && value) chooseRegion(value)
  else clearSelection()
}
function onPickerVisibilityChange(visible: boolean) { pickerOpen.value = visible }
function clearSelection() { emit('select', null) }
function toggleTheme() { mapTheme.value = mapTheme.value === 'dark' ? 'light' : 'dark' }
function toggleLinks() { linksEnabled.value = !linksEnabled.value }
function toggleLabels() { labelsEnabled.value = !labelsEnabled.value }
function togglePulse() { if (!reducedMotion.value) pulseEnabled.value = !pulseEnabled.value }
function zoomIn() { withScene(instance => instance.zoom(1)) }
function zoomOut() { withScene(instance => instance.zoom(-1)) }
function resetView() {
  emit('select', null)
  withScene(instance => { instance.setSelected(null); instance.reset() })
}
function resizeScene() {
  resizeFrame = 0
  if (canRender.value) withScene(instance => instance.resize())
}
function scheduleResize() {
  if (!resizeFrame && !disposed && canRender.value) resizeFrame = requestAnimationFrame(resizeScene)
}
function syncActivity() {
  if (!scene) { if (canRender.value) void initialize(); return }
  withScene(instance => instance.setActive(canRender.value))
  if (canRender.value) scheduleResize()
  else if (resizeFrame) { cancelAnimationFrame(resizeFrame); resizeFrame = 0 }
}
async function initialize() {
  if (disposed || scene || loading.value || !canRender.value || !sceneHost.value || !labelHost.value) return
  const current = ++generation
  loading.value = true
  failed.value = false
  try {
    const { createDotWorldScene } = await import('../dotWorldScene')
    if (disposed || current !== generation || !canRender.value || !sceneHost.value || !labelHost.value) return
    const options: RegionSceneOptions = {
      points: pointList.value,
      selectedRegion: selected.value?.regionCode ?? null,
      reducedMotion: reducedMotion.value, labels: labelsEnabled.value,
      pulse: pulseEnabled.value && !reducedMotion.value, links: linksEnabled.value,
      onSelect: code => { if (!disposed && current === generation && !pickerOpen.value) chooseRegion(code) },
      onInteract: () => {},
      label: cityName, ariaLabel: markerAriaLabel, colors: readColors(),
    }
    const instance = createDotWorldScene(sceneHost.value, labelHost.value, options)
    if (disposed || current !== generation) { instance.dispose(); return }
    scene = instance
    ready.value = true
    syncActivity()
    instance.resize()
  } catch {
    if (disposed || current !== generation) return
    onSceneError()
  } finally {
    if (!disposed && current === generation) loading.value = false
  }
}
function restartScene() {
  if (disposed) return
  generation += 1
  loading.value = false
  releaseScene()
  failed.value = false
  void initialize()
}
function retry() { if (!loading.value) restartScene() }
function onVisibilityChange() { documentVisible.value = document.visibilityState !== 'hidden' }
function onMotionChange() {
  reducedMotion.value = Boolean(motionQuery?.matches)
  withScene(instance => {
    instance.setReducedMotion(reducedMotion.value)
    instance.setPulse(pulseEnabled.value && !reducedMotion.value)
  })
}
watch(canRender, syncActivity)
watch(mapTheme, restartScene, { flush: 'post' })
watch(pointList, () => withScene(instance => {
  instance.setPoints(pointList.value)
  instance.setSelected(selected.value?.regionCode ?? null)
}))
watch(() => selected.value?.regionCode, code => withScene(instance => instance.setSelected(code ?? null)))
watch(locale, () => withScene(instance => instance.setPoints(pointList.value)))
watch(linksEnabled, value => withScene(instance => instance.setLinks(value)))
watch(labelsEnabled, value => withScene(instance => instance.setLabels(value)))
watch(pulseEnabled, value => withScene(instance => instance.setPulse(value && !reducedMotion.value)))
onMounted(() => {
  motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
  reducedMotion.value = motionQuery.matches
  motionQuery.addEventListener('change', onMotionChange)
  onVisibilityChange()
  document.addEventListener('visibilitychange', onVisibilityChange)
  sceneHost.value?.addEventListener(REGION_SCENE_ERROR_EVENT, onSceneError)
  if (sceneHost.value && 'ResizeObserver' in window) {
    resizeObserver = new ResizeObserver(scheduleResize)
    resizeObserver.observe(sceneHost.value)
  } else window.addEventListener('resize', scheduleResize)
  if (root.value && 'IntersectionObserver' in window) {
    intersectionObserver = new IntersectionObserver(entries => { inViewport.value = entries.some(entry => entry.isIntersecting) }, { threshold: 0.01 })
    intersectionObserver.observe(root.value)
  } else inViewport.value = true
  themeObserver = new MutationObserver(() => { if (scene) restartScene() })
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'style', 'class'] })
})
onBeforeUnmount(() => {
  disposed = true
  generation += 1
  resizeObserver?.disconnect()
  intersectionObserver?.disconnect()
  themeObserver?.disconnect()
  motionQuery?.removeEventListener('change', onMotionChange)
  document.removeEventListener('visibilitychange', onVisibilityChange)
  window.removeEventListener('resize', scheduleResize)
  sceneHost.value?.removeEventListener(REGION_SCENE_ERROR_EVENT, onSceneError)
  releaseScene()
})
</script>

<template>
  <section ref="root" class="region-globe" :style="mapStyle" :aria-label="t('regionGlobe.title')">
    <div class="scene-toolbar">
      <div class="region-picker">
        <label :for="selectId" class="sr-only">{{ t('regionGlobe.chooseRegion') }}</label>
        <el-select
          :id="selectId"
          :model-value="selected?.regionCode || ''"
          filterable
          clearable
          default-first-option
          value-on-clear=""
          :teleported="true"
          :fit-input-width="true"
          :show-arrow="false"
          :effect="mapTheme"
          :popper-class="`region-map-select-popper region-map-select-${mapTheme}`"
          :popper-style="mapStyle"
          :placeholder="t('regionGlobe.searchRegion')"
          :aria-label="t('regionGlobe.searchRegion')"
          :no-match-text="t('regionGlobe.noMatchingRegion')"
          :no-data-text="t('regionGlobe.noSelectableRegions')"
          @change="selectFromList"
          @visible-change="onPickerVisibilityChange"
        >
          <template #prefix><span class="i-mdi-magnify picker-search-icon" aria-hidden="true" /></template>
          <el-option v-for="point in pointList" :key="point.regionCode" :value="point.regionCode" :label="regionOptionLabel(point)">
            <span class="region-map-option-copy"><span class="region-map-option-name">{{ cityName(point) }}</span><span class="region-map-option-code">{{ point.regionCode }}</span></span>
            <span class="i-mdi-check region-map-option-check" :class="{ 'is-selected': selected?.regionCode === point.regionCode }" aria-hidden="true" />
          </el-option>
        </el-select>
      </div>
      <div class="scene-controls">
        <button type="button" :aria-pressed="linksEnabled" :title="t('regionGlobe.linksAria')" :aria-label="t('regionGlobe.linksAria')" @click="toggleLinks"><span class="i-mdi-vector-curve" aria-hidden="true" /><span class="control-text">{{ t('regionGlobe.links') }}</span></button>
        <button type="button" :aria-pressed="labelsEnabled" :title="t('regionGlobe.labels')" :aria-label="t('regionGlobe.labels')" @click="toggleLabels"><span class="i-mdi-label-outline" aria-hidden="true" /><span class="control-text">{{ t('regionGlobe.labels') }}</span></button>
        <button type="button" :disabled="reducedMotion" :aria-pressed="pulseEnabled && !reducedMotion" :title="t(reducedMotion ? 'regionGlobe.motionDisabled' : 'regionGlobe.pulse')" :aria-label="t('regionGlobe.pulse')" @click="togglePulse"><span class="i-mdi-radio-tower" aria-hidden="true" /><span class="control-text">{{ t('regionGlobe.pulse') }}</span></button>
        <button type="button" :title="t(mapTheme === 'dark' ? 'regionGlobe.lightTheme' : 'regionGlobe.darkTheme')" :aria-label="t(mapTheme === 'dark' ? 'regionGlobe.lightTheme' : 'regionGlobe.darkTheme')" @click="toggleTheme"><span :class="mapTheme === 'dark' ? 'i-mdi-white-balance-sunny' : 'i-mdi-weather-night'" aria-hidden="true" /></button>
        <span class="control-divider" aria-hidden="true" />
        <button type="button" :disabled="!ready" :title="t('regionGlobe.zoomIn')" :aria-label="t('regionGlobe.zoomIn')" @click="zoomIn"><span class="i-mdi-plus" aria-hidden="true" /></button>
        <button type="button" :disabled="!ready" :title="t('regionGlobe.zoomOut')" :aria-label="t('regionGlobe.zoomOut')" @click="zoomOut"><span class="i-mdi-minus" aria-hidden="true" /></button>
        <button type="button" :disabled="!ready" :title="t('regionGlobe.reset')" :aria-label="t('regionGlobe.reset')" @click="resetView"><span class="i-mdi-backup-restore" aria-hidden="true" /></button>
      </div>
    </div>

    <div class="scene-area" :inert="pickerOpen">
      <div ref="sceneHost" class="scene-host" role="group" :tabindex="ready ? 0 : -1" :aria-label="t('regionGlobe.interactiveMap')" :aria-describedby="helpId" />
      <div ref="labelHost" class="scene-labels" />
      <div v-if="loading" class="scene-message" role="status"><span class="loading-dot" aria-hidden="true" />{{ t('regionGlobe.loading') }}</div>
      <div v-else-if="failed" class="scene-message scene-fallback" role="status">
        <span class="i-mdi-earth" aria-hidden="true" />
        <strong>{{ t('regionGlobe.fallbackTitle') }}</strong>
        <p>{{ t('regionGlobe.fallbackDescription') }}</p>
        <div class="fallback-actions"><button type="button" @click="retry">{{ t('regionGlobe.retry') }}</button></div>
      </div>
      <p v-else-if="ready && !pointList.length" class="empty-notice">{{ t('regionGlobe.noPoints') }}</p>
      <aside v-if="selected" class="region-details" :class="{ 'details-left': panelOnLeft, 'details-top': panelOnTop }" :aria-label="t('regionGlobe.details')" @keydown.esc="clearSelection">
        <div class="detail-heading">
          <div><strong>{{ selected.name }}</strong><span>{{ selected.regionCode }}</span></div>
          <button type="button" :title="t('regionGlobe.closeDetails')" :aria-label="t('regionGlobe.closeDetails')" @click="clearSelection"><span class="i-mdi-close" aria-hidden="true" /></button>
        </div>
        <dl class="detail-data">
          <div><dt>{{ t('regionGlobe.armStatus') }}</dt><dd>{{ t(selected.isOpen ? 'regionGlobe.armRecorded' : 'regionGlobe.noRecord') }}</dd></div>
          <div><dt>{{ t('regionGlobe.ownership') }}</dt><dd>{{ t(selected.isMine ? 'regionGlobe.mine' : 'regionGlobe.notOwned') }}</dd></div>
          <div><dt>{{ t('regionGlobe.totalOpen') }}</dt><dd>{{ formatCount(selected.openCount) }}</dd></div>
          <div><dt>{{ t('regionGlobe.monthlyOpen') }}</dt><dd>{{ formatCount(selected.monthlyOpenCount) }}</dd></div>
          <div class="wide"><dt>{{ t('regionGlobe.architecture') }}</dt><dd>{{ selected.architectureType || t('regionGlobe.unavailable') }}</dd></div>
          <div class="wide"><dt>{{ t('regionGlobe.latestOpen') }}</dt><dd>{{ formatDateTime(selected.openTime) }}</dd></div>
          <div class="wide"><dt>{{ t('regionGlobe.lastNotification') }}</dt><dd>{{ formatDateTime(selected.lastNotifyTime) }}</dd></div>
        </dl>
      </aside>
    </div>

    <div class="scene-footer">
      <div class="scene-legend"><span v-for="item in legend" :key="item.key"><i :class="`legend-${item.key}`" aria-hidden="true" />{{ item.label }}</span></div>
      <p>{{ t('regionGlobe.mapHint') }}</p>
    </div>
    <p :id="helpId" class="sr-only">{{ t('regionGlobe.mapKeyboardHint') }} {{ t('regionGlobe.overlappingHint') }}</p>
    <p class="sr-only" role="status" aria-live="polite">{{ selected ? t('regionGlobe.selected', { name: selected.name }) : t('regionGlobe.cleared') }}</p>
  </section>
</template>

<style scoped>
.region-globe { display: flex; flex-direction: column; position: relative; width: 100%; min-height: 340px; isolation: isolate; overflow: hidden; border-radius: var(--r-card); background: var(--map-surface); color: var(--map-text); font-family: var(--sans); font-size: var(--font-size-body); container-type: inline-size; }
.scene-toolbar { position: relative; z-index: 3; display: flex; align-items: center; flex-wrap: wrap; gap: 8px; padding: 12px 14px 8px; }
.scene-controls button, .fallback-actions button { display: inline-flex; align-items: center; justify-content: center; gap: 5px; min-width: 30px; min-height: 30px; padding: 5px 9px; border: 1px solid transparent; border-radius: 6px; background: transparent; color: var(--map-muted); font: var(--font-size-body) var(--sans); line-height: 1.3; cursor: pointer; transition: background-color 140ms ease, color 140ms ease; }
.scene-controls button:hover:not(:disabled) { color: var(--map-text); background: color-mix(in srgb, var(--map-land) 24%, transparent); }
.region-picker { position: relative; flex: 1 1 160px; min-width: 0; max-width: 250px; }
.region-picker :deep(.el-select) { width: 100%; --el-color-primary: var(--map-mine); --el-select-input-color: var(--map-muted); --el-select-close-hover-color: var(--map-text); }
.region-picker :deep(.el-select__wrapper) { min-height: 36px; padding: 7px 10px; border-radius: 8px; background: var(--map-surface); color: var(--map-text); box-shadow: 0 0 0 1px color-mix(in srgb, var(--map-land) 65%, transparent) inset; font: var(--font-size-body) var(--sans); }
.region-picker :deep(.el-select__wrapper.is-hovering) { box-shadow: 0 0 0 1px var(--map-muted) inset; }
.region-picker :deep(.el-select__wrapper.is-focused) { box-shadow: 0 0 0 1px var(--map-mine) inset, 0 0 0 3px color-mix(in srgb, var(--map-mine) 12%, transparent); }
.region-picker :deep(.el-select__selected-item), .region-picker :deep(.el-select__placeholder), .region-picker :deep(.el-select__input) { color: var(--map-text); font: var(--font-size-body) var(--sans); }
.region-picker :deep(.el-select__placeholder.is-transparent), .region-picker :deep(.el-select__input::placeholder), .region-picker :deep(.el-select__caret) { color: var(--map-muted); }
.region-picker :deep(.el-select__input) { caret-color: var(--map-mine); }
.region-picker :deep(.el-select__clear:hover) { color: var(--map-text); }
.picker-search-icon { width: 15px; height: 15px; color: var(--map-muted); }
.scene-controls { display: flex; align-items: center; flex-wrap: wrap; gap: 2px; margin-left: auto; }
.scene-controls button { padding: 5px 6px; }
.scene-controls button > span:not(.control-text) { width: 16px; height: 16px; flex-shrink: 0; }
.scene-controls button[aria-pressed="true"] { color: var(--map-mine); }
.scene-controls button:disabled { opacity: .38; cursor: default; }
.control-divider { height: 16px; width: 1px; margin: 0 4px; background: color-mix(in srgb, var(--map-land) 65%, transparent); }
/* Size the world from its available width; leave a little vertical room for markers. */
.scene-area { position: relative; flex: 1 0 auto; width: 100%; aspect-ratio: 360 / 150; min-height: 180px; overflow: hidden; }
.scene-host, .scene-labels { position: absolute; inset: 0; }
.scene-host { outline-offset: -3px; }
.scene-host:focus-visible { outline: 2px solid var(--map-mine); }
.scene-host :deep(canvas) { display: block; outline: none; }
.scene-labels { pointer-events: none; }
.scene-message { position: absolute; z-index: 2; inset: 16px 24px; display: flex; align-items: center; justify-content: center; gap: 10px; text-align: center; color: var(--map-muted); font-size: var(--font-size-secondary); pointer-events: none; }
.scene-fallback { flex-direction: column; }
.scene-fallback > span { width: 30px; height: 30px; color: var(--map-mine); }
.scene-fallback strong { color: var(--map-text); font-size: var(--font-size-section); font-weight: 500; }
.scene-fallback p { max-width: 330px; margin: 0; line-height: 1.6; }
.fallback-actions { display: flex; flex-wrap: wrap; justify-content: center; gap: 8px; }
.fallback-actions button { margin-top: 4px; border-color: var(--map-land); color: var(--map-text); pointer-events: auto; }
.loading-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--map-mine); }
.empty-notice { position: absolute; top: 8px; inset-inline: 16px; margin: 0; text-align: center; color: var(--map-muted); font-size: var(--font-size-secondary); pointer-events: none; }
.scene-footer { position: relative; z-index: 3; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 7px 16px; padding: 9px 16px 13px; }
.scene-legend { display: flex; flex-wrap: wrap; gap: 7px 14px; color: var(--map-text); font-size: var(--font-size-secondary); }
.scene-legend > span { display: inline-flex; align-items: center; gap: 6px; }
.scene-legend i { display: inline-block; flex-shrink: 0; width: 8px; height: 8px; border-radius: 50%; }
.legend-mine { background: var(--map-mine); }
.legend-arm { background: var(--map-arm); }
.legend-both { background: linear-gradient(135deg, var(--map-mine) 50%, var(--map-arm) 50%); }
.scene-footer > p { margin: 0; color: var(--map-muted); font-size: var(--font-size-secondary); }
.region-details { position: absolute; z-index: 4; right: 14px; bottom: 12px; width: 270px; max-width: calc(100% - 28px); max-height: calc(100% - 24px); box-sizing: border-box; overflow: auto; padding: 14px; border: 1px solid color-mix(in srgb, var(--map-land) 80%, transparent); border-radius: 10px; background: color-mix(in srgb, var(--map-surface) 97%, transparent); color: var(--map-text); box-shadow: var(--shadow-card); overscroll-behavior: contain; }
.region-details.details-left { right: auto; left: 14px; }
.detail-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
.detail-heading > div { min-width: 0; }
.detail-heading strong { display: block; font-size: var(--font-size-section); font-weight: 600; overflow-wrap: anywhere; }
.detail-heading div > span { display: block; margin-top: 4px; font-family: var(--mono); font-size: var(--font-size-secondary); color: var(--map-muted); overflow-wrap: anywhere; }
.detail-heading button { display: inline-flex; flex-shrink: 0; align-items: center; justify-content: center; width: 26px; height: 26px; margin: -4px -4px 0 0; padding: 0; border: 0; border-radius: 6px; background: transparent; color: var(--map-muted); cursor: pointer; }
.detail-heading button > span { width: 17px; height: 17px; }
.detail-heading button:hover { color: var(--map-text); background: color-mix(in srgb, var(--map-land) 24%, transparent); }
.detail-data { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px 12px; margin: 13px 0 0; font-size: var(--font-size-body); line-height: 1.5; }
.detail-data > div { min-width: 0; }
.detail-data dt { color: var(--map-muted); }
.detail-data dd { margin: 3px 0 0; color: var(--map-text); font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
.detail-data .wide { grid-column: 1 / -1; display: flex; flex-wrap: wrap; justify-content: space-between; gap: 4px 10px; }
.detail-data .wide dd { margin: 0; }
.sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
.region-globe :deep(.region-scene-pin:focus-visible) { outline: 2px solid var(--map-mine); outline-offset: 4px; }
.region-globe button:focus-visible { outline: 2px solid var(--map-mine); outline-offset: 2px; }
@container (max-width: 680px) {
  .scene-toolbar { padding: 10px 10px 6px; gap: 6px; }
  .region-picker { max-width: none; }
  .scene-controls { gap: 2px; }
  .scene-controls .control-text { display: none; }
  .region-details, .region-details.details-left { right: 10px; left: 10px; bottom: 8px; width: auto; max-width: none; padding: 11px; max-height: 36%; }
  .region-details.details-top { top: 8px; bottom: auto; }
  .detail-data { gap: 8px 10px; margin-top: 10px; }
  .scene-footer { padding: 8px 12px 11px; }
  .scene-legend { gap: 6px 10px; }
  .scene-footer > p { display: none; }
}
@media (prefers-reduced-motion: reduce) {
  .scene-controls button, .fallback-actions button { transition: none; }
}
</style>

<style>
/* Teleported options keep the map's local palette, independent of the app theme. */
body .el-popper.region-map-select-popper {
  --el-bg-color-overlay: var(--map-surface);
  --el-fill-color-light: color-mix(in srgb, var(--map-land) 24%, transparent);
  --el-text-color-primary: var(--map-text);
  --el-text-color-regular: var(--map-text);
  --el-text-color-secondary: var(--map-muted);
  --el-text-color-placeholder: var(--map-muted);
  --el-color-primary: var(--map-mine);
  --el-border-color-light: color-mix(in srgb, var(--map-land) 75%, transparent);
  --el-scrollbar-bg-color: var(--map-muted);
  --el-scrollbar-hover-bg-color: var(--map-text);
  max-width: calc(100vw - 24px);
  padding: 0;
  border: 1px solid var(--el-border-color-light);
  border-radius: 10px;
  background: var(--map-surface);
  color: var(--map-text);
  box-shadow: 0 10px 32px color-mix(in srgb, var(--region-map-dark-surface) 26%, transparent);
  font-family: var(--sans);
  font-size: var(--font-size-body);
}
.region-map-select-popper.region-map-select-dark { color-scheme: dark; }
.region-map-select-popper.region-map-select-light { color-scheme: light; }
.region-map-select-popper .el-select-dropdown__list { padding: 5px 0; }
.region-map-select-popper .el-select-dropdown__item { display: flex; align-items: center; gap: 10px; min-height: 48px; height: auto; margin: 2px 6px; padding: 8px 10px; border-radius: 6px; color: var(--map-text); font-size: var(--font-size-body); line-height: 1.3; }
.region-map-select-popper .el-select-dropdown__item.is-hovering { background: color-mix(in srgb, var(--map-land) 24%, transparent); }
.region-map-select-popper .el-select-dropdown__item.is-selected { color: var(--map-mine); background: color-mix(in srgb, var(--map-mine) 10%, transparent); font-weight: 500; }
.region-map-select-popper .el-select-dropdown__item.is-selected.is-hovering { background: color-mix(in srgb, var(--map-mine) 17%, transparent); }
.region-map-select-popper .region-map-option-copy { display: grid; flex: 1; min-width: 0; gap: 4px; }
.region-map-select-popper .region-map-option-name { overflow: hidden; text-overflow: ellipsis; font-size: var(--font-size-body); font-weight: 500; }
.region-map-select-popper .region-map-option-code { overflow: hidden; text-overflow: ellipsis; color: var(--map-muted); font: var(--font-size-secondary) var(--mono); }
.region-map-select-popper .region-map-option-check { width: 16px; height: 16px; flex-shrink: 0; color: var(--map-mine); visibility: hidden; }
.region-map-select-popper .region-map-option-check.is-selected { visibility: visible; }
.region-map-select-popper .el-select-dropdown__empty { padding: 22px 14px; color: var(--map-muted); font: var(--font-size-secondary) var(--sans); line-height: 1.5; }
</style>
