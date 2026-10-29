<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import request from '@/api/request'
const compact = useCompactViewport()
const { t } = useI18n({ useScope: 'local', messages: {
  zh: { nginxStatus: { current: '当前配置版本', latest: '最新配置版本', changes: '配置状态', pending: '有待应用的更改', synced: '配置已同步' }, nginxMobile: { refresh: '刷新', name: '名称', domain: '域名', status: '状态', target: '代理目标', protocol: '协议', remark: '备注', ssl: 'SSL 状态', empty: '暂无代理记录', loading: '加载中…', failed: '代理记录加载失败，请刷新重试。', pending: '待应用', applied: '已应用', error: '错误', disabled: '已停用', unknown: '未知', configured: '已配置', notConfigured: '未配置' } },
  en: { nginxStatus: { current: 'Current configuration', latest: 'Latest configuration', changes: 'Configuration status', pending: 'Changes pending', synced: 'Configuration is up to date' }, nginxMobile: { refresh: 'Refresh', name: 'Name', domain: 'Domain', status: 'Status', target: 'Proxy target', protocol: 'Protocol', remark: 'Notes', ssl: 'SSL status', empty: 'No proxy records', loading: 'Loading…', failed: 'Unable to load proxy records. Refresh to retry.', pending: 'Pending', applied: 'Applied', error: 'Error', disabled: 'Disabled', unknown: 'Unknown', configured: 'Configured', notConfigured: 'Not configured' } },
} })
const status = ref<any>({})
const configuration = computed(() => status.value?.data ?? status.value)
const proxies = ref<any[]>([])
const loading = ref(false)
const failed = ref(false)
function recordKey(row: any) { return row.id == null ? String(row.domain || row.name || '') : String(row.id) }
function recordStatus(row: any) { return String(row.configStatus || row.status || '') }
function statusLabel(value: string) {
  const key = ({ PENDING: 'pending', APPLIED: 'applied', ERROR: 'error', DISABLED: 'disabled', CONFIGURED: 'configured', NOT_CONFIGURED: 'notConfigured' } as Record<string, string>)[value.toUpperCase()]
  return key ? t(`nginxMobile.${key}`) : value || t('nginxMobile.unknown')
}
function proxyTarget(row: any) { return row.targetHost ? `${row.targetHost}${row.targetPort == null ? '' : `:${row.targetPort}`}` : '—' }
async function load() {
  loading.value = true
  failed.value = false
  try {
    status.value = await request.get('/ssl/nginx/status')
    const list: any = await request.get('/ssl/proxy/list')
    const rows = list?.data?.content ?? list?.data ?? list?.content ?? list
    proxies.value = Array.isArray(rows) ? rows : []
  } catch {
    // The shared request handler retains its existing error notification.
    failed.value = true
  } finally { loading.value = false }
}
onMounted(load)
</script>
<template>
  <div>
    <ListCard>
      <template #toolbar><GhostBtn :loading="loading" @click="load">{{ t('nginxMobile.refresh') }}</GhostBtn></template>
      <dl class="nginx-summary" :aria-busy="loading || undefined">
        <div><dt>{{ t('nginxStatus.current') }}</dt><dd>{{ configuration.currentVersion ?? '—' }}</dd></div>
        <div><dt>{{ t('nginxStatus.latest') }}</dt><dd>{{ configuration.latestVersion ?? '—' }}</dd></div>
        <div><dt>{{ t('nginxStatus.changes') }}</dt><dd class="nginx-config-state" :class="{ 'is-pending': configuration.hasChanges === true }"><i v-if="typeof configuration.hasChanges === 'boolean'" :class="configuration.hasChanges ? 'i-mdi-clock-outline' : 'i-mdi-check-circle-outline'" aria-hidden="true" />{{ typeof configuration.hasChanges === 'boolean' ? t(configuration.hasChanges ? 'nginxStatus.pending' : 'nginxStatus.synced') : '—' }}</dd></div>
      </dl>
      <PageErrorNotice v-if="failed">{{ t('nginxMobile.failed') }}</PageErrorNotice>
      <template v-if="compact">
        <MobileRecordList drilldown list-id="nginx-proxies" :record-keys="proxies.map(recordKey)" :loading="loading" class="nginx-mobile-list">
          <MobileRecordCard v-for="row in proxies" :key="recordKey(row)" :record-key="recordKey(row)" :summary-title="row.name || row.domain || '—'" :summary-meta="proxyTarget(row)" :summary-status="statusLabel(recordStatus(row))" :summary-tone="recordStatus(row) === 'APPLIED' ? 'success' : recordStatus(row) === 'ERROR' ? 'danger' : recordStatus(row) === 'PENDING' ? 'warning' : 'neutral'">
            <template #identity><h3 class="mobile-record-title">{{ row.name || row.domain || '—' }}</h3></template>
            <dl class="mobile-record-fields">
              <div v-if="row.name" class="mobile-record-wide"><dt>{{ t('nginxMobile.name') }}</dt><dd>{{ row.name }}</dd></div>
              <div class="mobile-record-wide"><dt>{{ t('nginxMobile.domain') }}</dt><dd>{{ row.domain || '—' }}</dd></div>
              <div class="mobile-record-wide"><dt>{{ t('nginxMobile.status') }}</dt><dd>{{ statusLabel(recordStatus(row)) }}</dd></div>
              <div class="mobile-record-wide"><dt>{{ t('nginxMobile.target') }}</dt><dd>{{ proxyTarget(row) }}</dd></div>
              <div><dt>{{ t('nginxMobile.protocol') }}</dt><dd>{{ row.protocol || '—' }}</dd></div>
              <div v-if="row.sslStatus"><dt>{{ t('nginxMobile.ssl') }}</dt><dd>{{ statusLabel(String(row.sslStatus)) }}</dd></div>
              <div v-if="row.remark" class="mobile-record-wide"><dt>{{ t('nginxMobile.remark') }}</dt><dd>{{ row.remark }}</dd></div>
            </dl>
          </MobileRecordCard>
          <p v-if="loading || (!proxies.length && !failed)" class="nginx-mobile-empty" role="status">{{ t(loading ? 'nginxMobile.loading' : 'nginxMobile.empty') }}</p>
        </MobileRecordList>
      </template>
      <el-table v-else :data="proxies" style="margin-top:12px">
        <el-table-column prop="name" :label="t('nginxMobile.name')" />
        <el-table-column prop="domain" :label="t('nginxMobile.domain')" />
        <el-table-column prop="status" :label="t('nginxMobile.status')" />
      </el-table>
    </ListCard>
  </div>
</template>
<style scoped>
.nginx-summary { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); margin: 0 0 20px; padding: 4px 0 20px; border-bottom: 1px solid var(--border); }
.nginx-summary > div { min-width: 0; padding: 0 20px; border-right: 1px solid var(--border); }
.nginx-summary > div:first-child { padding-left: 0; }
.nginx-summary > div:last-child { border: 0; }
.nginx-summary dt { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.nginx-summary dd { margin: 8px 0 0; color: var(--text-heading); font-size: var(--font-size-section); font-weight: 600; overflow-wrap: anywhere; }
.nginx-summary .nginx-config-state { display: flex; align-items: center; gap: 8px; font-size: var(--font-size-body); }
.nginx-config-state > i { flex: none; color: var(--status-ok); }
.nginx-config-state.is-pending > i { color: var(--status-warn); }
@media (max-width: 760px) {
  .nginx-summary { grid-template-columns: 1fr; gap: 16px; }
  .nginx-summary > div { border: 0; padding: 0; }
  .nginx-mobile-list { padding: 0; margin-top: 12px; }
  .nginx-mobile-toolbar { display: flex; justify-content: flex-end; margin-bottom: 12px; }
  .nginx-mobile-empty { display: grid; place-items: center; min-height: 88px; margin: 0; color: var(--text-secondary); font: var(--font-size-body)/1.5 var(--sans); }
}
</style>
