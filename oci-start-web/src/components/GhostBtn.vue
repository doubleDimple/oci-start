<script setup lang="ts">
defineProps<{ danger?: boolean; loading?: boolean; disabled?: boolean }>()
</script>
<template>
  <button class="btn" type="button" :class="{ danger }" :disabled="loading || disabled" :aria-busy="loading || undefined"><span v-if="loading" class="spinner" aria-hidden="true" /><slot /></button>
</template>
<style scoped>
.btn {
  border: 1px solid var(--border-strong);
  background: var(--bg-card);
  color: var(--text-primary);
  font: inherit;
  font-size: var(--font-size-body);
  font-weight: 600;
  border-radius: var(--r-pill);
  padding: 10px 14px;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-height: 40px;
  white-space: nowrap;
  touch-action: manipulation;
  transition: transform 180ms cubic-bezier(.22, 1, .36, 1), background-color 180ms ease, border-color 180ms ease;
}
.btn:not(:disabled):hover { background: var(--bg-hover); }
.btn:not(:disabled):active { transform: scale(.97); }
.btn:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.btn:disabled { opacity: .6; cursor: default; }
.danger { color: var(--status-danger); border-color: color-mix(in srgb, var(--status-danger) 35%, var(--border)); }
.spinner { width: 14px; height: 14px; flex-shrink: 0; border: 1.5px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: button-spin 700ms linear infinite; }
@keyframes button-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .btn { transition: none; } .spinner { animation: none; } }
</style>
