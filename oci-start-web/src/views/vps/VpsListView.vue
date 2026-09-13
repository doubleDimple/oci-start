<script setup lang="ts">
import { onMounted } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { usePagedQuery } from '@/composables/usePagedQuery'
const q = usePagedQuery('/oci/list/json')
onMounted(() => q.load())
</script>
<template>
  <div>
    <PageHero title="资源列表" desc="沿用 GET /oci/list/json（与原 VPS 页同一数据源）。">
      <GhostBtn @click="q.load()">刷新</GhostBtn>
    </PageHero>
    <ListCard>
      <el-table :data="q.rows" v-loading="q.loading" height="560">
        <el-table-column prop="displayName" label="名称" min-width="160" />
        <el-table-column prop="state" label="状态" width="110" />
        <el-table-column prop="publicIps" label="公网 IP" min-width="140" />
        <el-table-column prop="privateIps" label="私网 IP" min-width="140" />
      </el-table>
      <template #footer>
        <el-pagination background layout="total, prev, pager, next" :total="q.total"
          v-model:current-page="q.page" @current-change="q.load()" />
      </template>
    </ListCard>
  </div>
</template>
