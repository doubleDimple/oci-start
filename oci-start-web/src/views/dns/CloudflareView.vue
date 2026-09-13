<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const zones = ref<any[]>([])
onMounted(async () => {
  const res: any = await request.get('/dns/cloudflare/api/zones')
  zones.value = res?.data || res || []
})
</script>
<template>
  <div>
    <PageHero title="Cloudflare" desc="GET /dns/cloudflare/api/zones" />
    <ListCard>
      <el-table :data="Array.isArray(zones) ? zones : []" height="520">
        <el-table-column prop="name" label="Zone" />
        <el-table-column prop="status" label="状态" />
        <el-table-column prop="id" label="ID" />
      </el-table>
    </ListCard>
  </div>
</template>
