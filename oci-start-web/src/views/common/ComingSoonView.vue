<script setup lang="ts">
import { useRoute } from 'vue-router'
import PageHero from '@/components/PageHero.vue'

const route = useRoute()
</script>
<template>
  <div>
    <PageHero :title="String(route.meta.title || '即将推出')" desc="该云厂商服务端能力尚未开放，页面为占位，不会伪造接口。" />
    <section class="card">
      <i class="i-mdi-cloud-outline" />
      <h2>{{ route.meta.title }}</h2>
      <p>Coming soon. 不会请求不存在的 REST。</p>
    </section>
  </div>
</template>
<style scoped>
.card {
  background: var(--bg-card);
  border-radius: var(--r-card);
  box-shadow: var(--shadow-card);
  padding: 48px 24px;
  text-align: center;
  color: var(--text-secondary);
}
.card i { font-size: 42px; color: var(--brand); }
</style>
