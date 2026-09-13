<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const rows = ref<any[]>([])
onMounted(async () => {
  const res: any = await request.get('/dns/edgeone/api/zones')
  rows.value = res?.data || res || []
})
</script>
<template>
  <div>
    <PageHero title="EdgeOne" desc="GET /dns/edgeone/api/zones" />
    <ListCard>
      <el-table :data="Array.isArray(rows) ? rows : []" height="520">
        <el-table-column prop="name" label="Zone" />
        <el-table-column prop="id" label="ID" />
      </el-table>
    </ListCard>
  </div>
</template>
