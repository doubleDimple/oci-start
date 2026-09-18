<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
// @ts-expect-error Element Plus locale has no types
import zhCn from 'element-plus/dist/locale/zh-cn.mjs'
// @ts-expect-error same
import en from 'element-plus/dist/locale/en.mjs'
import AppProgress from '@/components/AppProgress.vue'
import PageLoading from '@/components/PageLoading.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { navigationErrorDetail, navigationLoadingVisible, navigationProblem } from '@/utils/navigation'
import { sessionExpired } from '@/utils/session'
import { useSessionGuard } from '@/composables/useSessionGuard'

useSessionGuard()
const { locale, t } = useI18n()
const elLocale = computed(() => (locale.value === 'en' ? en : zhCn))
function reloadPage() { window.location.reload() }
</script>

<template>
  <ElConfigProvider :locale="elLocale">
    <AppProgress />
    <PageLoading v-if="sessionExpired" visible fullscreen />
    <RouterView v-else v-slot="{ Component }">
      <component :is="Component" v-if="Component" />
      <div v-else-if="navigationProblem" class="startup-error"><PageErrorNotice :title="t('pageLoading.failed')"><p>{{ navigationErrorDetail || t('pageLoading.failed') }}</p><button type="button" @click="reloadPage">{{ t('pageLoading.retry') }}</button></PageErrorNotice></div>
      <PageLoading v-else :visible="navigationLoadingVisible" fullscreen />
    </RouterView>
  </ElConfigProvider>
</template>

<style scoped>
.startup-error { display: grid; min-height: 100dvh; place-items: center; background: var(--bg-page); }
</style>
