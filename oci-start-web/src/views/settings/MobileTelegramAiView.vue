<script setup lang="ts">
import { ref } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from '@/components/PageBackButton.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import TelegramAiDialog from './notifications/TelegramAiDialog.vue'

const { t } = useI18n()
const router = useRouter()
const open = ref(true)
const busy = ref(false)

function notifications() {
  if (!open.value && !busy.value) void router.push('/system/notifySettings')
}
// The dialog owns confirmation and uncertain-result recovery. Let it close first.
onBeforeRouteLeave(() => !open.value && !busy.value)
</script>

<template>
  <section class="mobile-telegram-ai" :aria-label="t('notificationSettings.ai.title')">
    <header class="mobile-telegram-ai-toolbar">
      <PageBackButton :disabled="open || busy" @click="notifications" />
      <GhostBtn :disabled="open || busy" @click="notifications"><i class="i-mdi-bell-outline" aria-hidden="true" />{{ t('notificationSettings.title') }}</GhostBtn>
      <PrimaryBtn :disabled="open || busy" @click="open = true"><i class="i-mdi-robot-outline" aria-hidden="true" />{{ t('notificationSettings.aiConfig') }}</PrimaryBtn>
    </header>
    <p>{{ t('notificationSettings.ai.intro') }}</p>
    <TelegramAiDialog v-model="open" @busy="busy = $event" />
  </section>
</template>

<style scoped>
.mobile-telegram-ai { min-width: 0; padding: 20px; border: 1px solid var(--border); border-radius: var(--r-card); background: var(--bg-card); color: var(--text-primary); box-shadow: var(--shadow-card); }
.mobile-telegram-ai-toolbar { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
.mobile-telegram-ai-toolbar > :last-child { margin-left: auto; }
.mobile-telegram-ai p { margin: 18px 0 0; font-size: var(--font-size-body); line-height: 1.6; }
@media (max-width: 760px) { .mobile-telegram-ai { padding: 16px; } .mobile-telegram-ai-toolbar > :last-child { margin-left: 0; } }
</style>
