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
  box-shadow: var(--shadow-card);
  overflow: hidden;
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.toolbar {
  display: flex;
  gap: 10px;
  align-items: center;
  flex-wrap: wrap;
  padding: 16px 18px 0;
}
.body { padding: 12px 18px 8px; overflow: auto; }
.footer {
  padding: 12px 18px 16px;
  display: flex;
  justify-content: flex-end;
}
</style>
