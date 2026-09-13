<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const rows = ref<any[]>([])
onMounted(async () => {
  const res: any = await request.get('/oci/storage/buckets')
  rows.value = res?.data || res || []
})
</script>
<template>
  <div>
    <PageHero title="对象存储" desc="GET /oci/storage/buckets" />
    <ListCard>
      <el-table :data="Array.isArray(rows) ? rows : []" height="520">
        <el-table-column prop="name" label="Bucket" />
        <el-table-column prop="namespace" label="Namespace" />
        <el-table-column prop="region" label="区域" />
      </el-table>
    </ListCard>
  </div>
</template>
