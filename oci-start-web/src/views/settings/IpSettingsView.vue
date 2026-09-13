<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import request from '@/api/request'
const cfg = ref<any>({})
onMounted(async () => {
  const res: any = await request.get('/api/system/ipSettingsConfigs')
  cfg.value = res?.data || res
})
async function save() {
  await request.post('/api/system/updateIpCheckConfig', cfg.value.ipCheck || cfg.value)
  ElMessage.success('已保存')
}
</script>
<template>
  <div>
    <PageHero title="质量管理" desc="GET /api/system/ipSettingsConfigs" />
    <section class="card">
      <el-form label-position="top" v-if="cfg">
        <el-form-item label="启用检测"><el-switch v-model="(cfg.ipCheck || cfg).enabled" /></el-form-item>
        <PrimaryBtn @click="save">保存</PrimaryBtn>
      </el-form>
    </section>
  </div>
</template>
<style scoped>
.card { background: var(--bg-card); border-radius: var(--r-card); box-shadow: var(--shadow-card); padding: 20px; max-width: 640px; }
</style>
