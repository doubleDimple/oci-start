<script setup lang="ts">
import { onMounted } from 'vue'
import { useRoute } from 'vue-router'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { usePagedQuery } from '@/composables/usePagedQuery'

const route = useRoute()
const q = usePagedQuery('/boot/fullBootList/json')
onMounted(() => q.load({ tenantId: route.query.tenantId }))
</script>
<template>
  <div>
    <PageHero title="开机任务" desc="GET /boot/fullBootList/json">
      <GhostBtn @click="q.load({ tenantId: route.query.tenantId })">刷新</GhostBtn>
    </PageHero>
    <ListCard>
      <el-table :data="q.rows" v-loading="q.loading" height="560">
        <el-table-column prop="id" label="ID" width="90" />
        <el-table-column prop="instanceName" label="名称" min-width="140" />
        <el-table-column prop="region" label="区域" min-width="140" />
        <el-table-column prop="status" label="状态" width="110" />
        <el-table-column prop="shape" label="Shape" min-width="140" />
        <el-table-column prop="createTime" label="创建时间" width="170" />
      </el-table>
      <template #footer>
        <el-pagination background layout="total, prev, pager, next" :total="q.total"
          v-model:current-page="q.page" @current-change="q.load({ tenantId: route.query.tenantId })" />
      </template>
    </ListCard>
  </div>
</template>
