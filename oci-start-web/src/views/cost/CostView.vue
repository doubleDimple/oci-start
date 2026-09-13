<script setup lang="ts">
import { ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import request from '@/api/request'
const data = ref<any>({})
async function query() {
  data.value = await request.post('/cost/query', {})
}
</script>
<template>
  <div>
    <PageHero title="费用" desc="POST /cost/query">
      <PrimaryBtn @click="query">查询</PrimaryBtn>
    </PageHero>
    <ListCard><pre class="pre">{{ JSON.stringify(data, null, 2) }}</pre></ListCard>
  </div>
</template>
<style scoped>
.pre { font-size: 12px; color: var(--text-secondary); white-space: pre-wrap; }
</style>
