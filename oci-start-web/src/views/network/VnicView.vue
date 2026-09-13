<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const route = useRoute()
const data = ref<any>({})
onMounted(async () => {
  data.value = await request.get('/oci/vnic/loadData', { params: { instanceId: route.query.instanceId } })
})
</script>
<template>
  <div>
    <PageHero title="网络管理" desc="GET /oci/vnic/loadData" />
    <ListCard><pre class="pre">{{ JSON.stringify(data, null, 2) }}</pre></ListCard>
  </div>
</template>
<style scoped>
.pre { font-size: 12px; color: var(--text-secondary); white-space: pre-wrap; }
</style>
