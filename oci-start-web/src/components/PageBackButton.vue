<script setup lang="ts">
import { computed, inject } from 'vue'
import { useI18n } from 'vue-i18n'
import { LAYOUT_HEADER_BACK_KEY } from '@/utils/headerBack'

const props = defineProps<{ disabled?: boolean; loading?: boolean; title?: string; local?: boolean }>()
const emit = defineEmits<{ click: [event: MouseEvent] }>()
const { t } = useI18n()
const headerBackSlot = inject(LAYOUT_HEADER_BACK_KEY, null)
const teleportTarget = computed(() => (props.local ? null : headerBackSlot?.value ?? null))
</script>

<template>
  <Teleport :to="teleportTarget ?? 'body'" :disabled="!teleportTarget">
    <button class="page-back-button" :class="{ 'in-header': Boolean(teleportTarget) }" type="button" :disabled="disabled || loading" :aria-busy="loading || undefined" :title="title || t('pageBack')" @click="emit('click', $event)">
      <span v-if="loading" class="back-spinner" aria-hidden="true" />
      <i v-else class="i-mdi-arrow-left" aria-hidden="true" />
      <span>{{ t('pageBack') }}</span>
    </button>
  </Teleport>
</template>

<style scoped>
.page-back-button { display: inline-flex; flex: none; align-self: center; align-items: center; justify-content: center; gap: 5px; box-sizing: border-box; height: 32px; min-height: 32px; padding: 5px 11px; margin: 0; border: 1px solid var(--border-strong); border-radius: var(--r-pill); background: var(--bg-card); color: var(--text-primary); font: 500 var(--font-size-secondary)/18px var(--sans); white-space: nowrap; cursor: pointer; touch-action: manipulation; transition: background-color 180ms ease; }
.page-back-button > i { width: 16px; height: 16px; font-size: 16px; flex: none; }
@media (max-width: 760px) {
  .page-back-button { height: 36px; min-height: 36px; padding: 7px 12px; font-size: var(--font-size-body); line-height: 20px; }
  .page-back-button > i { width: 18px; height: 18px; font-size: 18px; }
}
.page-back-button:not(:disabled):hover { background: var(--bg-hover); }
.page-back-button:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.page-back-button:disabled { opacity: .6; cursor: default; }
.back-spinner { width: 16px; height: 16px; box-sizing: border-box; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: back-button-spin 800ms linear infinite; }
@keyframes back-button-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .page-back-button { transition: none; } .back-spinner { animation: none; } }
</style>
