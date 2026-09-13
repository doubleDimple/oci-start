<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const rows = ref<any[]>([])
onMounted(async () => {
  const res: any = await request.post('/monitor/api/instances/traffic', {})
  rows.value = res?.data || []
})
</script>
<template>
  <div>
    <PageHero title="流量监控" desc="POST /monitor/api/instances/traffic" />
    <ListCard>
      <el-table :data="rows" height="520">
        <el-table-column prop="displayName" label="实例" />
        <el-table-column prop="inBytes" label="入" />
        <el-table-column prop="outBytes" label="出" />
      </el-table>
    </ListCard>
  </div>
</template>
