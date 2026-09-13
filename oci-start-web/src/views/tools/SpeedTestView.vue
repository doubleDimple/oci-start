<script setup lang="ts">
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
</script>
<template>
  <div>
    <PageHero title="延迟测试" desc="测试仍在浏览器侧执行，不改服务端。" />
    <ListCard>
      <p class="hint">打开后可在此页接入原 delayTest 测速逻辑。当前先提供与设计一致的页面壳，避免再走 FTL。</p>
    </ListCard>
  </div>
</template>
<style scoped>
.hint { color: var(--text-secondary); padding: 8px 0 20px; }
</style>
