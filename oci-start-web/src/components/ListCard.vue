<template>
  <section class="card">
    <div v-if="$slots.toolbar" class="toolbar"><slot name="toolbar" /></div>
    <div class="body"><slot /></div>
    <div v-if="$slots.footer" class="footer"><slot name="footer" /></div>
  </section>
</template>

<style scoped>
.card {
  background: var(--bg-card);
  border-radius: var(--r-card);
  border: 1px solid var(--border);
  box-shadow: var(--shadow-card);
  overflow: hidden;
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.toolbar {
  display: flex;
  gap: var(--space-s);
  align-items: center;
  flex-wrap: wrap;
  padding: var(--space-m) var(--space-l);
  border-bottom: 1px solid var(--border);
}
.body { padding: var(--space-m) var(--space-l); overflow: auto; }
.footer {
  padding: var(--space-s) var(--space-l);
  border-top: 1px solid var(--border);
  display: flex;
  justify-content: flex-end;
}
</style>
