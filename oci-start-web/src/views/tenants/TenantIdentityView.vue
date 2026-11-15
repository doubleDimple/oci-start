<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { isAxiosError, isCancel } from 'axios'
import type { TenantRow } from '@/api/tenant'
import { loadTenantPermissionContext } from '@/utils/tenantPermissions'
import { useShellStore } from '@/stores/shell'
import PageBackButton from '@/components/PageBackButton.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import TenantIdentityUsersWorkspace from './components/TenantIdentityUsersWorkspace.vue'
import './tenants.scss'

const route = useRoute()
const router = useRouter()
const shell = useShellStore()
const { t } = useI18n()

const tenantId = computed(() => {
  const value = String(route.query.tenantId || '')
  return /^[1-9]\d*$/.test(value) ? value : ''
})
const validCloud = computed(() => route.query.cloudType == null || route.query.cloudType === '1')
const validContext = computed(() => !!tenantId.value && validCloud.value)

const tenant = ref<TenantRow | null>(null)
const loadingTenant = ref(false)
const tenantError = ref('')
let requestId = 0
let controller: AbortController | undefined
let disposed = false

function extractError(cause: unknown): string {
  if (isAxiosError(cause)) return cause.response?.data?.message || t('tenant.list.loadFailed')
  const value = cause as { message?: string; msg?: string }
  return value?.message || value?.msg || t('tenant.list.loadFailed')
}

async function loadTenantContext() {
  const current = ++requestId
  controller?.abort()
  tenant.value = null
  tenantError.value = ''
  if (!validContext.value) {
    loadingTenant.value = false
    return
  }
  const active = new AbortController()
  controller = active
  loadingTenant.value = true
  try {
    const context = await loadTenantPermissionContext(tenantId.value, active.signal)
    if (disposed || current !== requestId) return
    tenant.value = context
  } catch (cause) {
    if (disposed || current !== requestId || isCancel(cause)) return
    tenantError.value = extractError(cause)
  } finally {
    if (!disposed && current === requestId) loadingTenant.value = false
  }
}

function goBack() {
  const previous = window.history.state?.back
  if (typeof previous === 'string' && previous.startsWith('/') && !previous.startsWith('//') && previous !== route.fullPath) {
    router.back()
    return
  }
  void router.push({ path: '/tenants/list', query: { cloudType: String(route.query.cloudType || shell.cloudType) } })
}

watch(() => [tenantId.value, route.query.cloudType], () => {
  void loadTenantContext()
}, { immediate: true })

onBeforeUnmount(() => {
  disposed = true
  requestId++
  controller?.abort()
})
</script>

<template>
  <div class="tenants-page tenant-identity-page">
    <PageBackButton @click="goBack" />

    <section v-if="!validContext" class="tenant-card">
      <div class="tenant-invalid-notice">
        <PageErrorNotice>
          <div>
            <strong>{{ t('tenantIdentity.titles.users') }}</strong>
            <p>{{ t('tenantAudit.invalidTenant') }}</p>
          </div>
          <GhostBtn @click="goBack">{{ t('tenantAudit.back') }}</GhostBtn>
        </PageErrorNotice>
      </div>
    </section>

    <TenantIdentityUsersWorkspace
      v-else
      :tenant="tenant"
      :loading-tenant="loadingTenant"
      :tenant-error="tenantError"
      @retry-tenant="loadTenantContext"
    />
  </div>
</template>

<style scoped>
.tenant-invalid-notice {
  padding: 20px;
}
</style>
