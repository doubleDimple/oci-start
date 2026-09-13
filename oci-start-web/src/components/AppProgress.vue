<script setup lang="ts">
import { progressVisible as visible, progressWidth as width } from '@/utils/progress'
</script>

<template>
  <Transition name="prog">
    <div v-if="visible" class="app-progress" aria-hidden="true">
      <div class="bar" :style="{ width: width + '%' }" />
    </div>
  </Transition>
</template>

<style scoped>
.app-progress {
  position: fixed;
  top: 0; left: 0; right: 0;
  height: 3px;
  z-index: 99999;
  pointer-events: none;
}
.bar {
  height: 100%;
  background: var(--brand);
  border-radius: 0 2px 2px 0;
  transition: width .25s cubic-bezier(.45, .05, .55, .95);
}
.prog-leave-active { transition: opacity .35s ease; }
.prog-leave-to { opacity: 0; }
</style>
