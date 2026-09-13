<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
// @ts-expect-error Element Plus locale has no types
import zhCn from 'element-plus/dist/locale/zh-cn.mjs'
// @ts-expect-error same
import en from 'element-plus/dist/locale/en.mjs'
import AppProgress from '@/components/AppProgress.vue'

const { locale } = useI18n()
const elLocale = computed(() => (locale.value === 'en' ? en : zhCn))
</script>

<template>
  <ElConfigProvider :locale="elLocale">
    <AppProgress />
    <RouterView />
  </ElConfigProvider>
</template>
