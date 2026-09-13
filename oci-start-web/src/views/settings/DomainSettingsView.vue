<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import request from '@/api/request'
const cfg = ref<any>({})
onMounted(async () => {
  const res: any = await request.get('/api/system/domainProviderConfigs')
  cfg.value = res?.data || res
})
</script>
<template>
  <div>
    <PageHero title="密钥配置" desc="GET /api/system/domainProviderConfigs" />
    <div class="grid">
      <section class="card">
        <h3>Cloudflare</h3>
        <el-form label-position="top" v-if="cfg.cloudflare">
          <el-form-item label="启用"><el-switch v-model="cfg.cloudflare.enabled" /></el-form-item>
          <el-form-item label="Email"><el-input v-model="cfg.cloudflare.email" /></el-form-item>
          <el-form-item label="API Key"><el-input v-model="cfg.cloudflare.apiKey" type="password" /></el-form-item>
          <PrimaryBtn @click="request.post('/api/system/updateCloudflareConfig', cfg.cloudflare).then(() => ElMessage.success('已保存'))">保存</PrimaryBtn>
        </el-form>
      </section>
      <section class="card">
        <h3>EdgeOne</h3>
        <el-form label-position="top" v-if="cfg.edgeOne">
          <el-form-item label="启用"><el-switch v-model="cfg.edgeOne.enabled" /></el-form-item>
          <el-form-item label="SecretId"><el-input v-model="cfg.edgeOne.secretId" /></el-form-item>
          <el-form-item label="SecretKey"><el-input v-model="cfg.edgeOne.secretKey" type="password" /></el-form-item>
          <PrimaryBtn @click="request.post('/api/system/updateEdgeOneConfig', cfg.edgeOne).then(() => ElMessage.success('已保存'))">保存</PrimaryBtn>
        </el-form>
      </section>
    </div>
  </div>
</template>
<style scoped>
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.card { background: var(--bg-card); border-radius: var(--r-card); box-shadow: var(--shadow-card); padding: 20px; }
@media (max-width: 900px) { .grid { grid-template-columns: 1fr; } }
</style>
