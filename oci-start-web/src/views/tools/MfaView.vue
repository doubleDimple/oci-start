<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const keys = ref<any[]>([])
onMounted(async () => {
  const res: any = await request.get('/api/mfa/keys')
  keys.value = res?.data || res || []
})
</script>
<template>
  <div>
    <PageHero title="MFA 备份" desc="GET /api/mfa/keys" />
    <ListCard>
      <el-table :data="Array.isArray(keys) ? keys : []">
        <el-table-column prop="name" label="名称" />
        <el-table-column prop="secret" label="密钥" />
        <el-table-column prop="createTime" label="时间" />
      </el-table>
    </ListCard>
  </div>
</template>
