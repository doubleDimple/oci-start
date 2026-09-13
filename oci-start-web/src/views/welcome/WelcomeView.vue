<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import request from '@/api/request'

const router = useRouter()

onMounted(() => {
  request.get('/api/version/check', { params: { refresh: true }, silent: true }).catch(() => undefined)
})
</script>
<template>
  <div class="welcome">
    <div class="panel">
      <div class="kicker">OCI-START</div>
      <h1>欢迎回来</h1>
      <p>控制台已切换为 Vue 布局。业务接口与登录方式保持不变。</p>
      <button @click="router.push('/boot/dashboard')">进入控制台</button>
    </div>
  </div>
</template>
<style scoped>
.welcome {
  min-height: 100%;
  display: grid;
  place-items: center;
  background: var(--bg-page);
}
.panel {
  width: min(560px, 92vw);
  background: var(--bg-card);
  border-radius: 24px;
  box-shadow: var(--shadow-card);
  padding: 48px 40px;
}
.kicker { letter-spacing: 0.16em; font-size: 12px; font-weight: 700; color: var(--brand); }
h1 { font-size: 36px; margin: 10px 0; }
p { color: var(--text-secondary); }
button {
  margin-top: 20px; border: 0; background: var(--brand); color: #fff;
  border-radius: 999px; padding: 12px 20px; font-weight: 700; cursor: pointer;
}
</style>
