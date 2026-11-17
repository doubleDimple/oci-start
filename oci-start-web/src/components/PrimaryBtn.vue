<script setup lang="ts">
withDefaults(defineProps<{ loading?: boolean; disabled?: boolean; type?: 'button' | 'submit' | 'reset' }>(), { type: 'button' })
</script>
<template>
  <button class="btn" :type="type" :disabled="loading || disabled" :aria-busy="loading || undefined">
    <span v-if="loading" class="spinner" aria-hidden="true" />
    <slot />
  </button>
</template>
<style scoped>
.btn {
  border: 0;
  background: var(--brand-solid);
  color: var(--text-on-solid);
  font: inherit;
  font-size: var(--font-size-secondary);
  font-weight: 600;
  border-radius: var(--r-pill);
  padding: 5px 14px;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  justify-content: center;
  min-height: 32px;
  line-height: 1.4;
  white-space: nowrap;
  touch-action: manipulation;
  transition: transform 180ms cubic-bezier(.22, 1, .36, 1), background-color 180ms ease, box-shadow 180ms ease;
}
@media (max-width: 760px) {
  .btn { min-height: 40px; padding: 8px 16px; font-size: var(--font-size-body); }
}
.btn:not(:disabled):hover { background: var(--brand-solid-hover); }
.btn:not(:disabled):active { transform: scale(.97); }
.btn:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.btn:disabled { opacity: 0.6; cursor: default; }
.spinner { width: 14px; height: 14px; flex-shrink: 0; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: button-spin 700ms linear infinite; }
@keyframes button-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .btn { transition: none; } .spinner { animation: none; } }
</style>
