<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import request from '@/api/request'

const cfg = ref<any>({})
const pwd = ref({ oldPassword: '', newPassword: '', confirmPassword: '' })

onMounted(async () => {
  const res: any = await request.get('/api/system/securitySettingsConfigs')
  cfg.value = res?.data || res
})

async function saveGithub() {
  await request.post('/api/system/updateGithubConfig', cfg.value.github)
  ElMessage.success('已保存 GitHub')
}
async function saveGoogle() {
  await request.post('/api/system/updateGoogleConfig', cfg.value.google)
  ElMessage.success('已保存 Google')
}
async function saveMfa() {
  await request.post('/api/system/updateMfaConfig', cfg.value.mfa)
  ElMessage.success('已保存 MFA')
}
async function saveTurnstile() {
  await request.post('/api/system/updateTurnstileConfig', cfg.value.turnstile)
  ElMessage.success('已保存 Turnstile')
}
async function savePassword() {
  await request.post('/api/system/updatePassword', pwd.value)
  ElMessage.success('密码已更新')
}
</script>
<template>
  <div>
    <PageHero title="安全管理" desc="GET /api/system/securitySettingsConfigs，保存走原 POST。" />
    <div class="grid">
      <section class="card">
        <h3>登录密码</h3>
        <el-form label-position="top">
          <el-form-item label="原密码"><el-input v-model="pwd.oldPassword" type="password" show-password /></el-form-item>
          <el-form-item label="新密码"><el-input v-model="pwd.newPassword" type="password" show-password /></el-form-item>
          <el-form-item label="确认"><el-input v-model="pwd.confirmPassword" type="password" show-password /></el-form-item>
          <PrimaryBtn @click="savePassword">保存密码</PrimaryBtn>
        </el-form>
      </section>
      <section class="card">
        <h3>GitHub 登录</h3>
        <el-form label-position="top" v-if="cfg.github">
          <el-form-item label="启用"><el-switch v-model="cfg.github.enabled" /></el-form-item>
          <el-form-item label="Client ID"><el-input v-model="cfg.github.clientId" /></el-form-item>
          <el-form-item label="Secret"><el-input v-model="cfg.github.clientSecret" type="password" /></el-form-item>
          <PrimaryBtn @click="saveGithub">保存 GitHub</PrimaryBtn>
        </el-form>
      </section>
      <section class="card">
        <h3>Google 登录</h3>
        <el-form label-position="top" v-if="cfg.google">
          <el-form-item label="启用"><el-switch v-model="cfg.google.enabled" /></el-form-item>
          <el-form-item label="Client ID"><el-input v-model="cfg.google.clientId" /></el-form-item>
          <el-form-item label="Secret"><el-input v-model="cfg.google.clientSecret" type="password" /></el-form-item>
          <PrimaryBtn @click="saveGoogle">保存 Google</PrimaryBtn>
        </el-form>
      </section>
      <section class="card">
        <h3>MFA / Turnstile</h3>
        <el-form label-position="top">
          <el-form-item v-if="cfg.mfa" label="启用 MFA"><el-switch v-model="cfg.mfa.enabled" /></el-form-item>
          <PrimaryBtn @click="saveMfa">保存 MFA</PrimaryBtn>
          <el-form-item v-if="cfg.turnstile" label="启用 Turnstile" style="margin-top:16px"><el-switch v-model="cfg.turnstile.enabled" /></el-form-item>
          <el-form-item v-if="cfg.turnstile" label="Site Key"><el-input v-model="cfg.turnstile.siteKey" /></el-form-item>
          <PrimaryBtn @click="saveTurnstile">保存 Turnstile</PrimaryBtn>
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
