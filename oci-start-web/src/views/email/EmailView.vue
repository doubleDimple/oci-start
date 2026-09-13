<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const rows = ref<any[]>([])
onMounted(async () => {
  const res: any = await request.post('/email/receive/list', {})
  rows.value = res?.data?.content || res?.data || []
})
</script>
<template>
  <div>
    <PageHero title="邮箱服务" desc="POST /email/receive/list" />
    <ListCard>
      <el-table :data="rows" height="520">
        <el-table-column prop="subject" label="主题" />
        <el-table-column prop="from" label="发件人" />
        <el-table-column prop="createTime" label="时间" />
      </el-table>
    </ListCard>
  </div>
</template>
