<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import HeaderVersion from '@/components/header/HeaderVersion.vue'
import { headerVersionSnapshot } from '@/api/headerVersion'
const { t } = useI18n()
const details = ref<InstanceType<typeof HeaderVersion>>()
onMounted(() => details.value?.open())
</script>

<template>
  <section class="about-page">
    <p>{{ t('headerVersion.author') }}</p>
    <dl><dt>{{ t('headerVersion.currentVersion') }}</dt><dd>{{ headerVersionSnapshot?.currentVersion || t('headerVersion.unavailable') }}</dd></dl>
    <button type="button" class="about-open" @click="details?.open()">{{ t('headerVersion.about') }}</button>
    <HeaderVersion ref="details"/>
  </section>
</template>

<style scoped>
.about-page { padding: 24px; border-radius: var(--r-card); background: var(--bg-card); color: var(--text-primary); box-shadow: var(--shadow-card); }
dl { display: flex; gap: 12px; margin: 16px 0; }
dd { margin: 0; font-weight: 600; }
.about-open { border: 1px solid var(--border); border-radius: var(--r-pill); padding: 10px 16px; background: var(--bg-card); color: var(--text-primary); font: inherit; cursor: pointer; }
</style>
