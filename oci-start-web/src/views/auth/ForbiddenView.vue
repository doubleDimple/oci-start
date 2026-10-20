<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
import { authCopy } from './copy'
const { locale } = useI18n()
const route = useRoute()
const copy = computed(() => authCopy[locale.value === 'en' ? 'en' : 'zh'])
const permissionProblem = computed(() => ['permissionsUnavailable', 'tenantPermission'].includes(String(route.query.reason || '')))
const permissionCopy = computed(() => {
  const unavailable = route.query.reason === 'permissionsUnavailable'
  return locale.value === 'en'
    ? { title: unavailable ? 'Could not read tenant permissions' : 'This cloud action is not authorized', hint: unavailable ? 'Check your connection and open this feature again from the tenant list.' : 'Update this tenant’s cloud permissions before using this feature.', back: 'Back to tenants' }
    : { title: unavailable ? '暂时无法读取租户权限' : '此租户未授权该功能', hint: unavailable ? '请检查连接，再从租户列表重新进入。' : '请先在租户列表中更新此租户的云端权限。', back: '返回租户列表' }
})
</script>

<template>
  <main class="forbidden-page"><section><i class="i-mdi-shield-lock-outline" aria-hidden="true"/><h1>{{ permissionProblem ? permissionCopy.title : copy.forbidden }}</h1><p>{{ permissionProblem ? permissionCopy.hint : copy.forbiddenHint }}</p><a :href="permissionProblem ? '/tenants/list' : '/login'">{{ permissionProblem ? permissionCopy.back : copy.login }}</a></section></main>
</template>

<style scoped>
.forbidden-page { min-height: 100dvh; display: grid; place-items: center; padding: 24px; box-sizing: border-box; background: var(--bg-page); color: var(--text-primary); }
section { max-width: 440px; padding: 32px; border-radius: var(--r-card); background: var(--bg-card); box-shadow: var(--shadow-card); text-align: center; }
i { display: inline-block; width: 40px; height: 40px; color: var(--brand); }
h1 { margin: 18px 0 12px; font-size: 24px; }
p { line-height: 1.7; }
a { display: inline-flex; margin-top: 12px; padding: 11px 20px; border-radius: var(--r-pill); background: var(--brand); color: #fff; text-decoration: none; }
</style>
