<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import ListCard from '@/components/ListCard.vue'
import request from '@/api/request'
const data = ref<any>({})
async function load() {
  const res: any = await request.get('/api/system/apiTokenConfigs')
  data.value = res?.data || res
}
onMounted(load)
async function generate() {
  await request.post('/api/system/generateApiToken', {})
  ElMessage.success('已生成')
  load()
}
</script>
<template>
  <div>
    <PageHero title="Token 配置" desc="GET /api/system/apiTokenConfigs">
      <GhostBtn @click="load">刷新</GhostBtn>
      <PrimaryBtn @click="generate">生成 Token</PrimaryBtn>
    </PageHero>
    <ListCard>
      <pre class="pre">{{ JSON.stringify(data, null, 2) }}</pre>
    </ListCard>
  </div>
</template>
<style scoped>
.pre { font-size: 12px; color: var(--text-secondary); white-space: pre-wrap; }
</style>
