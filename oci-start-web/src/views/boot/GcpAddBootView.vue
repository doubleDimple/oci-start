<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import ListCard from '@/components/ListCard.vue'
import PageBackButton from '@/components/PageBackButton.vue'
const { t } = useI18n()
const router = useRouter()
const route = useRoute()
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//')) router.back()
  else void router.push({ path: '/tenants/list', query: typeof route.query.cloudType === 'string' ? { cloudType: route.query.cloudType } : {} })
}
</script>
<template>
  <div class="gcp-boot-page">
    <ListCard :aria-label="t('tenant.actions.boot')">
      <template #toolbar><PageBackButton @click="back" /></template>
      <p class="hint">{{ t('comingSoon') }}</p>
    </ListCard>
  </div>
</template>
<style scoped>
.gcp-boot-page { color: var(--text-primary); font: var(--font-size-body)/1.47 var(--sans); }
.hint { color: var(--text-secondary); padding: 12px 0 24px; font-size: var(--font-size-secondary); line-height: 1.6; }
</style>
