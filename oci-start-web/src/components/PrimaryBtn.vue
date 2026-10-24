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
  background: var(--brand);
  color: var(--nav-active-fg);
  font: inherit;
  font-size: var(--font-size-body);
  font-weight: 600;
  border-radius: var(--r-pill);
  padding: 10px 16px;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  justify-content: center;
  min-height: 40px;
  white-space: nowrap;
  touch-action: manipulation;
  transition: transform 180ms cubic-bezier(.22, 1, .36, 1), background-color 180ms ease, box-shadow 180ms ease;
}
.btn:not(:disabled):hover { background: var(--brand-hover); box-shadow: 0 4px 12px color-mix(in srgb, var(--brand) 18%, transparent); }
.btn:not(:disabled):active { transform: scale(.97); }
.btn:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.btn:disabled { opacity: 0.6; cursor: default; }
.spinner { width: 14px; height: 14px; flex-shrink: 0; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: button-spin 700ms linear infinite; }
@keyframes button-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .btn { transition: none; } .spinner { animation: none; } }
</style>
