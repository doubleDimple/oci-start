<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import request from '@/api/request'

const cfg = ref<any>({})
onMounted(async () => {
  const res: any = await request.get('/api/system/notifyConfigs')
  cfg.value = res?.data || res
})
async function save(path: string, body: any, name: string) {
  await request.post(path, body)
  ElMessage.success('已保存 ' + name)
}
</script>
<template>
  <div>
    <PageHero title="通知管理" desc="GET /api/system/notifyConfigs" />
    <div class="grid">
      <section class="card" v-if="cfg.telegram">
        <h3>Telegram</h3>
        <el-form label-position="top">
          <el-form-item label="启用"><el-switch v-model="cfg.telegram.enabled" /></el-form-item>
          <el-form-item label="Bot Token"><el-input v-model="cfg.telegram.botToken" /></el-form-item>
          <el-form-item label="Chat Id"><el-input v-model="cfg.telegram.chatId" /></el-form-item>
          <PrimaryBtn @click="save('/api/system/updateTelegramConfig', cfg.telegram, 'Telegram')">保存</PrimaryBtn>
        </el-form>
      </section>
      <section class="card" v-if="cfg.dingTalk">
        <h3>钉钉</h3>
        <el-form label-position="top">
          <el-form-item label="启用"><el-switch v-model="cfg.dingTalk.enabled" /></el-form-item>
          <el-form-item label="Webhook"><el-input v-model="cfg.dingTalk.webhook" /></el-form-item>
          <PrimaryBtn @click="save('/api/system/updateDingTalkConfig', cfg.dingTalk, '钉钉')">保存</PrimaryBtn>
        </el-form>
      </section>
      <section class="card" v-if="cfg.bark">
        <h3>Bark</h3>
        <el-form label-position="top">
          <el-form-item label="启用"><el-switch v-model="cfg.bark.enabled" /></el-form-item>
          <el-form-item label="URL"><el-input v-model="cfg.bark.url" /></el-form-item>
          <PrimaryBtn @click="save('/api/system/updateBarkConfig', cfg.bark, 'Bark')">保存</PrimaryBtn>
        </el-form>
      </section>
      <section class="card" v-if="cfg.feishu">
        <h3>飞书</h3>
        <el-form label-position="top">
          <el-form-item label="启用"><el-switch v-model="cfg.feishu.enabled" /></el-form-item>
          <el-form-item label="Webhook"><el-input v-model="cfg.feishu.webhook" /></el-form-item>
          <PrimaryBtn @click="save('/api/system/updateFeishuConfig', cfg.feishu, '飞书')">保存</PrimaryBtn>
        </el-form>
      </section>
      <section class="card" v-if="cfg.proxy">
        <h3>代理</h3>
        <el-form label-position="top">
          <el-form-item label="启用"><el-switch v-model="cfg.proxy.enabled" /></el-form-item>
          <el-form-item label="Host"><el-input v-model="cfg.proxy.host" /></el-form-item>
          <el-form-item label="Port"><el-input v-model="cfg.proxy.port" /></el-form-item>
          <PrimaryBtn @click="save('/api/system/updateProxyConfig', cfg.proxy, '代理')">保存</PrimaryBtn>
        </el-form>
      </section>
      <section class="card" v-if="cfg.task">
        <h3>定时任务</h3>
        <el-form label-position="top">
          <el-form-item label="启用"><el-switch v-model="cfg.task.enabled" /></el-form-item>
          <PrimaryBtn @click="save('/api/system/updateTaskConfig', cfg.task, '任务')">保存</PrimaryBtn>
        </el-form>
      </section>
    </div>
  </div>
</template>
<style scoped>
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.card { background: var(--bg-card); border-radius: var(--r-card); box-shadow: var(--shadow-card); padding: 20px; }
h3 { margin: 0 0 12px; }
@media (max-width: 900px) { .grid { grid-template-columns: 1fr; } }
</style>
