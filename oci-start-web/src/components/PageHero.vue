<script setup lang="ts">
defineProps<{
  title: string
}>()
</script>

<template>
  <div class="hero" data-motion-enter>
    <div class="heading">
      <h1>{{ title }}</h1>
    </div>
    <div class="actions"><slot /></div>
  </div>
</template>

<style scoped>
.hero {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: var(--space-m);
  margin-bottom: 24px;
  flex-wrap: wrap;
}
.heading { min-width: 0; flex: 1 1 260px; }
h1 { margin: 0; font-size: var(--font-size-page-title); font-weight: 700; line-height: 1.25; letter-spacing: -0.01em; }
.actions { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
.actions:empty { display: none; }
@media (max-width: 760px) {
  .hero { align-items: flex-start; gap: 16px; margin-bottom: 20px; }
  .heading { flex-basis: 100%; }
  .actions { width: 100%; }
}
</style>
