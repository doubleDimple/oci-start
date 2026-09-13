<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import request from '@/api/request'
const status = ref<any>({})
const proxies = ref<any[]>([])
async function load() {
  status.value = await request.get('/ssl/nginx/status')
  const list: any = await request.get('/ssl/proxy/list')
  proxies.value = list?.data || list?.content || (Array.isArray(list) ? list : [])
}
onMounted(load)
</script>
<template>
  <div>
    <PageHero title="Nginx 管理" desc="状态与代理列表走原 /ssl 接口">
      <GhostBtn @click="load">刷新</GhostBtn>
    </PageHero>
    <ListCard>
      <pre class="pre">{{ JSON.stringify(status, null, 2) }}</pre>
      <el-table :data="proxies" style="margin-top:12px">
        <el-table-column prop="name" label="名称" />
        <el-table-column prop="domain" label="域名" />
        <el-table-column prop="status" label="状态" />
      </el-table>
    </ListCard>
  </div>
</template>
<style scoped>
.pre { font-size: 12px; color: var(--text-secondary); white-space: pre-wrap; }
</style>
