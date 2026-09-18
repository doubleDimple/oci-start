<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { authCopy } from './copy'
const { locale } = useI18n()
const copy = computed(() => authCopy[locale.value === 'en' ? 'en' : 'zh'])
</script>

<template>
  <main class="forbidden-page"><section><i class="i-mdi-shield-lock-outline" aria-hidden="true"/><h1>{{ copy.forbidden }}</h1><p>{{ copy.forbiddenHint }}</p><a href="/login">{{ copy.login }}</a></section></main>
</template>

<style scoped>
.forbidden-page { min-height: 100dvh; display: grid; place-items: center; padding: 24px; box-sizing: border-box; background: var(--bg-page); color: var(--text-primary); }
section { max-width: 440px; padding: 32px; border-radius: var(--r-card); background: var(--bg-card); box-shadow: var(--shadow-card); text-align: center; }
i { display: inline-block; width: 40px; height: 40px; color: var(--brand); }
h1 { margin: 18px 0 12px; font-size: 24px; }
p { line-height: 1.7; }
a { display: inline-flex; margin-top: 12px; padding: 11px 20px; border-radius: var(--r-pill); background: var(--brand); color: #fff; text-decoration: none; }
</style>
