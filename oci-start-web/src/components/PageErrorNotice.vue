<script setup lang="ts">
import { computed, getCurrentInstance, nextTick, onBeforeUnmount, onMounted, onUpdated, ref, shallowRef } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{ title?: string; label?: string; popperClass?: string }>()
const { t } = useI18n()
const visible = ref(false)
const source = ref<HTMLElement>()
const anchor = shallowRef<HTMLElement | null>(null)
const popupContainer = shallowRef<HTMLElement>()
const trigger = ref<HTMLButtonElement>()
const closeButton = ref<HTMLButtonElement>()
const detailId = `page-error-${getCurrentInstance()?.uid ?? 'detail'}`
const heading = computed(() => props.title || t('pageError.title'))
const label = computed(() => props.label || [props.title, t('pageError.open')].filter(Boolean).join(' · '))
async function opened() { await nextTick(); closeButton.value?.focus({ preventScroll: true }) }
async function close() { visible.value = false; await nextTick(); trigger.value?.focus({ preventScroll: true }) }
function locateAnchor() {
  const origin = source.value
  if (!origin) return
  const dialog = origin.closest<HTMLElement>('.el-dialog, .el-drawer')
  const fullscreen = document.fullscreenElement
  popupContainer.value = dialog ?? (fullscreen instanceof HTMLElement && fullscreen.contains(origin) ? fullscreen : undefined)
  if (dialog) {
    anchor.value = dialog.querySelector<HTMLElement>('.el-dialog__header, .el-drawer__header')
    return
  }
  let scope = origin.parentElement
  while (scope && scope !== document.body) {
    const candidate = scope.matches('[data-page-error-anchor]') ? scope : scope.querySelector<HTMLElement>('[data-page-error-anchor]')
    if (candidate) { anchor.value = candidate; return }
    scope = scope.parentElement
  }
  anchor.value = null
}
onMounted(() => {
  locateAnchor()
  document.addEventListener('fullscreenchange', locateAnchor)
})
onUpdated(locateAnchor)
onBeforeUnmount(() => document.removeEventListener('fullscreenchange', locateAnchor))
defineExpose({ focus: () => trigger.value?.focus({ preventScroll: true }) })
</script>

<template>
  <span ref="source" class="page-error-source">
    <Teleport :to="anchor ?? 'body'" :disabled="!anchor">
      <span class="page-error-notice" :class="{ 'is-anchored': !!anchor }">
        <el-popover v-model:visible="visible" trigger="click" placement="bottom-start" :width="380" :persistent="false"
          :append-to="popupContainer" :popper-class="['page-error-popover', popperClass].filter(Boolean).join(' ')" @show="opened">
          <template #reference>
            <button ref="trigger" type="button" class="page-error-trigger" :title="label" :aria-label="label" aria-haspopup="dialog"
              :aria-expanded="visible" :aria-controls="visible ? detailId : undefined" @click.stop @keydown.esc.stop.prevent="close">
              <i class="i-mdi-alert-circle-outline" aria-hidden="true" />
            </button>
          </template>
          <section :id="detailId" class="page-error-detail" role="dialog" :aria-label="heading" @keydown.esc.stop.prevent="close" @click.stop>
            <header><strong>{{ heading }}</strong><button ref="closeButton" type="button" :title="t('pageError.close')" :aria-label="t('pageError.close')" @click="close"><i class="i-mdi-close" aria-hidden="true" /></button></header>
            <div class="page-error-content"><slot /></div>
          </section>
        </el-popover>
        <span class="page-error-announcement" role="status">{{ label }}</span>
      </span>
    </Teleport>
  </span>
</template>

<style scoped lang="scss">
.page-error-source { display: contents; }
.page-error-notice { display: inline-flex; flex: none; align-self: flex-start; align-items: center; margin: 4px 12px; vertical-align: middle; }
.page-error-notice.is-anchored { align-self: center; order: 20; margin: 0 0 0 4px; }
.page-error-trigger { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; padding: 0; border: 0; border-radius: 50%; background: transparent; color: var(--status-danger); cursor: pointer; }
.page-error-trigger > i { width: 20px; height: 20px; }
.page-error-trigger:hover, .page-error-trigger[aria-expanded='true'] { background: var(--status-danger-bg); }
.page-error-trigger:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
.page-error-announcement { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
.page-error-detail { color: var(--text-primary); font: var(--font-size-body)/1.6 var(--sans); }
.page-error-detail > header { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 10px; }
.page-error-detail > header > strong { font-weight: 600; }
.page-error-detail > header > button { display: inline-flex; align-items: center; justify-content: center; width: 24px; height: 24px; padding: 0; border: 0; border-radius: 6px; background: transparent; color: var(--text-primary); cursor: pointer; }
.page-error-detail > header > button:hover { background: var(--bg-hover); }
.page-error-detail > header > button > i { width: 16px; height: 16px; }
.page-error-content { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; max-height: min(420px, 60vh); overflow: auto; overflow-wrap: anywhere; white-space: normal; }
.page-error-content :deep(p) { margin: 0; }
.page-error-content :deep(pre) { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; font: inherit; }
.page-error-content :deep(button) { display: inline-flex; align-items: center; justify-content: center; gap: 5px; min-height: 30px; padding: 4px 10px; border: 1px solid var(--border); border-radius: 8px; background: var(--bg-card); color: var(--text-primary); font: inherit; cursor: pointer; }
.page-error-content :deep(button:disabled) { opacity: .5; cursor: default; }
.page-error-content :deep(button:hover:not(:disabled)) { background: var(--bg-hover); }
.page-error-content :deep(button > i) { flex: none; width: 16px; height: 16px; }
</style>

<style lang="scss">
html:root .el-popover.page-error-popover { max-width: calc(100vw - 32px); box-sizing: border-box; padding: 14px 16px; border-color: var(--border); border-radius: 12px; background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); }
html:root :is(.el-dialog__header, .el-drawer__header):has(> .page-error-notice) { display: flex; align-items: center; gap: 6px; }
html:root :is(.el-dialog__header, .el-drawer__header):has(> .page-error-notice) > :is(.el-dialog__title, .el-drawer__title) { margin-right: auto; }
</style>
