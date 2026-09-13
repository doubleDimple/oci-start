<script setup lang="ts">
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
function download(url: string) {
  window.location.href = url
}
</script>
<template>
  <div>
    <PageHero title="数据迁移" desc="导出/导入仍走 /migration/export 等原接口" />
    <ListCard>
      <PrimaryBtn @click="download('/migration/export')">导出</PrimaryBtn>
      <p class="hint">加密导出：/migration/exportEncrypted。导入保持原 POST。</p>
    </ListCard>
  </div>
</template>
<style scoped>
.hint { margin-top: 12px; color: var(--text-secondary); }
</style>
