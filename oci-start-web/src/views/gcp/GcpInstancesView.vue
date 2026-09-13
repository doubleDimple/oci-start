<script setup lang="ts">
import { watch } from 'vue'
import { useRoute } from 'vue-router'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { usePagedQuery } from '@/composables/usePagedQuery'
const q = usePagedQuery('/other/instances/list/json')
const route = useRoute()
function load() {
  return q.load({ tenantId: route.query.tenantId || undefined })
}
watch(() => route.query.tenantId, () => {
  q.page = 1
  void load()
}, { immediate: true })
</script>
<template>
  <div>
    <PageHero title="GCP 实例" desc="GET /other/instances/list/json">
      <GhostBtn @click="load">刷新</GhostBtn>
    </PageHero>
    <ListCard>
      <el-table :data="q.rows" v-loading="q.loading" height="560">
        <el-table-column prop="displayName" label="名称" min-width="160" />
        <el-table-column prop="state" label="状态" width="120" />
        <el-table-column prop="publicIps" label="公网 IP" min-width="140" />
        <el-table-column prop="shape" label="机型" min-width="140" />
      </el-table>
      <template #footer>
        <el-pagination background layout="total, prev, pager, next" :total="q.total"
          v-model:current-page="q.page" @current-change="load" />
      </template>
    </ListCard>
  </div>
</template>
