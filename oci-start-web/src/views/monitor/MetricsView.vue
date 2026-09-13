<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const data = ref<any>({})
onMounted(async () => { data.value = await request.get('/api/metrics/status') })
</script>
<template>
  <div>
    <PageHero title="监控" desc="GET /api/metrics/status" />
    <ListCard><pre class="pre">{{ JSON.stringify(data, null, 2) }}</pre></ListCard>
  </div>
</template>
<style scoped>
.pre { font-size: 12px; color: var(--text-secondary); white-space: pre-wrap; }
</style>
