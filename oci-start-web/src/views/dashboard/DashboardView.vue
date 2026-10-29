<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import BusinessOverview from './BusinessOverview.vue'
import HostMonitor from './HostMonitor.vue'
const { t } = useI18n()
const activeView = ref<'business' | 'host'>('business')
</script>

<template>
  <div class="dashboard-workspace">
    <div class="dashboard-views" role="group" :aria-label="t('dashboardBusiness.views')">
      <button v-for="view in (['business', 'host'] as const)" :key="view" type="button" :data-dashboard-view="view" :aria-pressed="activeView === view" @click="activeView = view"><i :class="view === 'business' ? 'i-mdi-chart-box-outline' : 'i-mdi-server-outline'" aria-hidden="true" />{{ t(`dashboardBusiness.${view}`) }}</button>
    </div>
    <BusinessOverview v-if="activeView === 'business'" />
    <HostMonitor v-else />
  </div>
</template>

<style scoped>
.dashboard-workspace { min-width: 0; }
.dashboard-views { display: flex; gap: 4px; margin: 0 0 20px; padding-bottom: 12px; border-bottom: 1px solid var(--border); }
.dashboard-views button { display: inline-flex; align-items: center; gap: 8px; padding: 9px 14px; border: 0; border-radius: 8px; background: transparent; color: var(--text-secondary); font: 600 13px/1.4 var(--sans); cursor: pointer; transition: background .18s, color .18s; }
.dashboard-views button[aria-pressed='true'] { background: var(--brand-subtle); color: var(--brand); }
.dashboard-views button:hover { background: var(--bg-hover); }
.dashboard-views button[aria-pressed='true']:hover { background: var(--brand-subtle); }
.dashboard-views i { font-size: 18px; }
@media (prefers-reduced-motion: reduce) { .dashboard-views button { transition: none; } }
</style>
