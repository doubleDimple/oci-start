<script setup lang="ts">
defineProps<{
  kicker?: string
  title: string
  desc?: string
}>()
</script>

<template>
  <div class="hero" data-motion-enter>
    <div class="heading">
      <div v-if="kicker" class="kicker">{{ kicker }}</div>
      <h1>{{ title }}</h1>
      <p v-if="desc">{{ desc }}</p>
    </div>
    <div class="actions"><slot /></div>
  </div>
</template>

<style scoped>
.hero {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 16px;
  margin-bottom: 18px;
  flex-wrap: wrap;
}
.heading { min-width: 0; flex: 1 1 260px; }
.kicker {
  font-size: var(--font-size-caption);
  letter-spacing: 0.14em;
  font-weight: 600;
  color: var(--text-muted);
}
h1 { margin: 6px 0 4px; font-size: clamp(25px, 2.8vw, 32px); font-weight: 600; letter-spacing: -0.03em; }
p { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; overflow-wrap: anywhere; }
.actions { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
@media (max-width: 760px) {
  .hero { align-items: flex-start; gap: 16px; margin-bottom: 20px; }
  .heading { flex-basis: 100%; }
  .actions { width: 100%; }
}
</style>
