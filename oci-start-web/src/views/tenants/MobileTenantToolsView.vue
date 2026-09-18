<script setup lang="ts">
import { computed, defineAsyncComponent, onBeforeUnmount, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PageBackButton from '@/components/PageBackButton.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import type { TenantRow } from '@/api/tenant'
import {
  getMobileTenantToolContext, isMobileTenantId, isMobileTenantTool, MobileTenantToolError,
  type MobileTenantTool,
} from '@/api/mobileTenantTools'
import { mobileTenantToolsMessages } from '@/i18n/mobileTenantTools'
import { isMobileRecordNavigation } from '@/composables/useMobileRecords'

const TenantIdentityDialogs = defineAsyncComponent(() => import('./components/TenantIdentityDialogs.vue'))
const TenantRegionVolumesDialog = defineAsyncComponent(() => import('./components/TenantRegionVolumesDialog.vue'))
const TenantRegionSecurityDialog = defineAsyncComponent(() => import('./components/TenantRegionSecurityDialog.vue'))
const TenantRegionMysqlDialog = defineAsyncComponent(() => import('./components/TenantRegionMysqlDialog.vue'))

const props = defineProps<{ tool?: MobileTenantTool }>()
const route = useRoute()
const router = useRouter()
const { t } = useI18n({ useScope: 'local', messages: mobileTenantToolsMessages })
const tool = computed(() => {
  const value = props.tool ?? route.meta.mobileTenantTool
  return isMobileTenantTool(value) ? value : null
})
const tenantId = computed(() => isMobileTenantId(route.query.tenantId) ? route.query.tenantId : '')
const tenant = ref<TenantRow | null>(null)
const loading = ref(false)
const error = ref('')
const open = ref(false)
const name = computed(() => tenant.value?.defName || tenant.value?.tenancyName || tenant.value?.userName || t('currentTenant'))
const title = computed(() => tool.value ? t(`tools.${tool.value}`) : t('currentTenant'))
let generation = 0
let controller: AbortController | undefined
let disposed = false

async function load() {
  const current = ++generation
  controller?.abort()
  tenant.value = null
  open.value = false
  error.value = ''
  loading.value = false
  if (!tool.value) { error.value = 'invalidTool'; return }
  if (!tenantId.value) { error.value = 'invalidTenant'; return }
  if (route.query.cloudType != null && route.query.cloudType !== '1') { error.value = 'unsupportedCloud'; return }
  const active = new AbortController()
  controller = active
  loading.value = true
  try {
    const value = await getMobileTenantToolContext(tenantId.value, active.signal)
    if (disposed || current !== generation) return
    tenant.value = value
    open.value = true
  } catch (cause) {
    if (disposed || current !== generation || active.signal.aborted) return
    error.value = cause instanceof MobileTenantToolError ? cause.key : 'requestFailed'
  } finally {
    if (!disposed && current === generation) loading.value = false
  }
}

function selectTenant() { void router.push({ path: '/tenants/list', query: { cloudType: '1' } }) }
function back() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) router.back()
  else selectTenant()
}

watch(() => [tool.value, route.query.tenantId, route.query.cloudType], load, { immediate: true })
// Let the tool finish its own confirmation and close flow before changing accounts.
onBeforeRouteLeave(() => !open.value)
onBeforeRouteUpdate((to, from) => isMobileRecordNavigation(to, from) || !open.value)
onBeforeUnmount(() => { disposed = true; generation++; controller?.abort() })
</script>

<template>
  <section class="mobile-tenant-tools" :aria-label="title" :aria-busy="loading">
    <header class="mobile-tenant-tools-toolbar">
      <PageBackButton :disabled="open" @click="back" />
      <span v-if="tenant" class="mobile-tenant-tools-name">{{ name }}<span v-if="tenant.region"> · {{ tenant.region }}</span></span>
      <PrimaryBtn v-if="tenant && !open" @click="open = true">{{ t('open', { tool: title }) }}</PrimaryBtn>
    </header>
    <div v-if="loading" class="mobile-tenant-tools-state" role="status"><i class="i-mdi-loading mobile-tenant-tools-spinner" aria-hidden="true" /><p>{{ t('loading') }}</p></div>
    <div v-else-if="error" class="mobile-tenant-tools-state" role="alert">
      <i class="i-mdi-account-alert-outline" aria-hidden="true" /><p>{{ t(`errors.${error}`) }}</p>
      <div class="mobile-tenant-tools-actions">
        <GhostBtn v-if="tenantId && tool" @click="load">{{ t('retry') }}</GhostBtn>
        <PrimaryBtn @click="selectTenant">{{ t('selectTenant') }}</PrimaryBtn>
      </div>
    </div>
    <p v-else-if="tenant" class="mobile-tenant-tools-context">{{ t('tenantId') }}: {{ tenant.id }}</p>
    <template v-if="open && tenant">
      <TenantIdentityDialogs v-if="tool === 'users'" :key="`users-${tenant.id}`" :tenant="tenant" action="users" @close="open = false" />
      <TenantRegionVolumesDialog v-else-if="tool === 'volumes'" :key="`volumes-${tenant.id}`" :tenant="tenant" @close="open = false" />
      <TenantRegionSecurityDialog v-else-if="tool === 'security'" :key="`security-${tenant.id}`" :tenant="tenant" @close="open = false" />
      <TenantRegionMysqlDialog v-else-if="tool === 'mysql'" :key="`mysql-${tenant.id}`" :tenant="tenant" @close="open = false" />
    </template>
  </section>
</template>

<style scoped>
.mobile-tenant-tools { min-width: 0; padding: 20px; border: 1px solid var(--border); border-radius: 20px; background: var(--bg-card); color: var(--text-primary); box-shadow: var(--shadow-card); }
.mobile-tenant-tools-toolbar { display: flex; align-items: center; flex-wrap: wrap; gap: 12px; }
.mobile-tenant-tools-name { flex: 1; min-width: 0; overflow-wrap: anywhere; font-size: var(--font-size-body); }
.mobile-tenant-tools-state { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; min-height: 220px; padding: 24px 0; text-align: center; }
.mobile-tenant-tools-state > i { width: 30px; height: 30px; }
.mobile-tenant-tools-state p { margin: 0; max-width: 440px; font-size: var(--font-size-body); line-height: 1.6; }
.mobile-tenant-tools-actions { display: flex; flex-wrap: wrap; justify-content: center; gap: 12px; }
.mobile-tenant-tools-context { margin: 16px 0 0; overflow-wrap: anywhere; font-size: var(--font-size-secondary); }
.mobile-tenant-tools-spinner { animation: mobile-tenant-tool-spin 1s linear infinite; }
@keyframes mobile-tenant-tool-spin { to { transform: rotate(360deg); } }
@media (max-width: 640px) { .mobile-tenant-tools { padding: 16px; } }
@media (prefers-reduced-motion: reduce) { .mobile-tenant-tools-spinner { animation: none; } }
</style>
