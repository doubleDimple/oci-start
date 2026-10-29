<script setup lang="ts">
import ListCard from '@/components/ListCard.vue'
import { useI18n } from 'vue-i18n'
const { t } = useI18n()
</script>
<template>
  <div>
    <ListCard>
      <p class="hint">{{ t('pageLayout.rescueUnavailable') }}</p>
    </ListCard>
  </div>
</template>
<style scoped>
.hint { color: var(--text-secondary); padding: 8px 0 24px; }
</style>
