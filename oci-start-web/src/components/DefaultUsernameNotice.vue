<script setup lang="ts">
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { isReservedRegistrationUsername } from '@/utils/initialCredentials'
import { navigateWithFeedback } from '@/utils/navigation'

const props = defineProps<{ username: string; ready: boolean }>()
const { t } = useI18n()
const router = useRouter()
const visible = ref(false)
// The authenticated layout stays mounted while navigating between pages.
const prompted = new Set<string>()

watch([() => props.username, () => props.ready], ([username, ready]) => {
  if (!ready || !isReservedRegistrationUsername(username)) {
    visible.value = false
    return
  }
  if (prompted.has(username)) return
  prompted.add(username)
  visible.value = true
}, { immediate: true })

function openAccountSettings() {
  visible.value = false
  void navigateWithFeedback(router, '/system/settings')
}
</script>

<template>
  <el-dialog v-model="visible" :title="t('header.defaultUsername.title')"
    width="min(460px, calc(100vw - 24px))" align-center append-to-body
    :show-close="true" :close-on-click-modal="true" :close-on-press-escape="true">
    <p class="username-notice-message">{{ t('header.defaultUsername.message', { username }) }}</p>
    <p class="username-notice-optional">{{ t('header.defaultUsername.optional') }}</p>
    <template #footer>
      <el-button @click="visible = false">{{ t('header.defaultUsername.dismiss') }}</el-button>
      <el-button type="primary" @click="openAccountSettings">{{ t('header.defaultUsername.change') }}</el-button>
    </template>
  </el-dialog>
</template>

<style scoped>
.username-notice-message { margin: 0; line-height: 1.7; color: var(--text-primary); overflow-wrap: anywhere; }
.username-notice-optional { margin: 12px 0 0; line-height: 1.6; color: var(--text-muted); }
</style>
