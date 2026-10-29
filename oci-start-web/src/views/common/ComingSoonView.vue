<script setup lang="ts">
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'

const route = useRoute()
const { t } = useI18n()
</script>
<template>
  <div>
    <section class="card">
      <i class="i-mdi-cloud-outline" />
      <h2>{{ route.meta.title }}</h2>
      <p>{{ t('pageLayout.comingSoon') }}</p>
    </section>
  </div>
</template>
<style scoped>
.card {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--r-card);
  box-shadow: var(--shadow-card);
  padding: 48px 24px;
  text-align: center;
  color: var(--text-secondary);
}
.card i { font-size: 42px; color: var(--brand); }
</style>
