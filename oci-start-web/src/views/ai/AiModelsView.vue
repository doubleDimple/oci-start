<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const rows = ref<any[]>([])
onMounted(async () => {
  const res: any = await request.get('/system/aiModels')
  rows.value = res?.data || res || []
})
</script>
<template>
  <div>
    <PageHero title="OCI AI 管理" desc="GET /system/aiModels" />
    <ListCard>
      <el-table :data="Array.isArray(rows) ? rows : []" height="520">
        <el-table-column prop="name" label="模型" />
        <el-table-column prop="id" label="ID" />
      </el-table>
    </ListCard>
  </div>
</template>
