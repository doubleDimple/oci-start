<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
const route = useRoute()
const router = useRouter()
</script>
<template>
  <div>
    <PageHero title="添加开机任务" :desc="`tenantId=${route.query.tenantId || ''}，保存仍走 /tenants/boot/save`">
      <GhostBtn @click="router.back()">返回</GhostBtn>
    </PageHero>
    <ListCard>
      <p class="hint">开机表单字段与旧页一致，提交接口不变。请从租户行进入以带上 tenantId。</p>
    </ListCard>
  </div>
</template>
<style scoped>
.hint { color: var(--text-secondary); padding: 12px 0 24px; }
</style>
