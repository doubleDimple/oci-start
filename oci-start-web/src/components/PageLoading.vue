<script setup lang="ts">
import { useI18n } from 'vue-i18n'

withDefaults(defineProps<{ visible: boolean; fullscreen?: boolean; label?: string }>(), { fullscreen: false })
const { t } = useI18n()
</script>

<template>
  <Transition name="page-loading-fade" appear>
    <div v-if="visible" class="page-loading" :class="{ 'is-fullscreen': fullscreen }" role="status" aria-live="polite" aria-atomic="true">
      <span class="page-loading-spinner" aria-hidden="true" />
      <span class="page-loading-label">{{ label || t('pageLoading.loading') }}</span>
    </div>
  </Transition>
</template>

<style scoped>
.page-loading {
  position: absolute;
  inset: 0;
  z-index: 10;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 24px;
  box-sizing: border-box;
  background: var(--bg-page);
  background: color-mix(in srgb, var(--bg-page) 78%, transparent);
  color: var(--text-primary);
  font: var(--font-size-body)/1.5 var(--sans);
  text-align: center;
  pointer-events: none;
}
.page-loading.is-fullscreen { position: fixed; z-index: 2000; }
.page-loading-spinner {
  flex: none;
  width: 28px;
  height: 28px;
  box-sizing: border-box;
  border: 2px solid color-mix(in srgb, var(--brand) 18%, transparent);
  border-top-color: var(--brand);
  border-radius: 50%;
  animation: page-loading-spin .8s linear infinite;
}
.page-loading-label { overflow-wrap: anywhere; }
.page-loading-fade-enter-active, .page-loading-fade-leave-active { transition: opacity 120ms ease; }
.page-loading-fade-enter-from, .page-loading-fade-leave-to { opacity: 0; }
@keyframes page-loading-spin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) {
  .page-loading-spinner { animation: none; }
  .page-loading-fade-enter-active, .page-loading-fade-leave-active { transition: none; }
}
</style>
