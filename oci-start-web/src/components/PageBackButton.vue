<script setup lang="ts">
import { useI18n } from 'vue-i18n'

defineProps<{ disabled?: boolean; loading?: boolean; title?: string }>()
const emit = defineEmits<{ click: [event: MouseEvent] }>()
const { t } = useI18n()
</script>

<template>
  <button class="page-back-button" type="button" :disabled="disabled || loading" :aria-busy="loading || undefined" :title="title || t('pageBack')" @click="emit('click', $event)">
    <span v-if="loading" class="back-spinner" aria-hidden="true" />
    <i v-else class="i-mdi-arrow-left" aria-hidden="true" />
    <span>{{ t('pageBack') }}</span>
  </button>
</template>

<style scoped>
.page-back-button { display: inline-flex; flex: none; align-self: center; align-items: center; justify-content: center; gap: 6px; box-sizing: border-box; height: 36px; min-height: 36px; padding: 7px 12px; margin: 0; border: 1px solid var(--border-strong); border-radius: var(--r-pill); background: var(--bg-card); color: var(--text-primary); font: 500 var(--font-size-body)/20px var(--sans); white-space: nowrap; cursor: pointer; touch-action: manipulation; transition: background-color 180ms ease; }
.page-back-button > i { width: 18px; height: 18px; font-size: 18px; flex: none; }
.page-back-button:not(:disabled):hover { background: var(--bg-hover); }
.page-back-button:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.page-back-button:disabled { opacity: .6; cursor: default; }
.back-spinner { width: 16px; height: 16px; box-sizing: border-box; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: back-button-spin 800ms linear infinite; }
@keyframes back-button-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .page-back-button { transition: none; } .back-spinner { animation: none; } }
</style>
