<script setup lang="ts">
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import { useRoute } from 'vue-router'
const route = useRoute()
</script>
<template>
  <div>
    <PageHero title="系统救援" :desc="`/ws/rescue · instanceId=${route.query.instanceId || ''}`" />
    <ListCard>
      <p class="hint">救援通道仍使用原 WebSocket /ws/rescue，本页为 Vue 壳。</p>
    </ListCard>
  </div>
</template>
<style scoped>
.hint { color: var(--text-secondary); padding: 8px 0 24px; }
</style>
