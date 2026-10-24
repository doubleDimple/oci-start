<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import request from '@/api/request'
const compact = useCompactViewport()
const { t } = useI18n({ useScope: 'local', messages: {
  zh: { nginxMobile: { refresh: '刷新', name: '名称', domain: '域名', status: '状态', target: '代理目标', protocol: '协议', remark: '备注', ssl: 'SSL 状态', empty: '暂无代理记录', loading: '加载中…', failed: '代理记录加载失败，请刷新重试。', pending: '待应用', applied: '已应用', error: '错误', disabled: '已停用', unknown: '未知', configured: '已配置', notConfigured: '未配置' } },
  en: { nginxMobile: { refresh: 'Refresh', name: 'Name', domain: 'Domain', status: 'Status', target: 'Proxy target', protocol: 'Protocol', remark: 'Notes', ssl: 'SSL status', empty: 'No proxy records', loading: 'Loading…', failed: 'Unable to load proxy records. Refresh to retry.', pending: 'Pending', applied: 'Applied', error: 'Error', disabled: 'Disabled', unknown: 'Unknown', configured: 'Configured', notConfigured: 'Not configured' } },
} })
const status = ref<any>({})
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
    <PageHero v-if="!compact" title="Nginx 管理" desc="状态与代理列表走原 /ssl 接口">
      <GhostBtn @click="load">刷新</GhostBtn>
    </PageHero>
    <div v-else class="nginx-mobile-toolbar"><GhostBtn :loading="loading" @click="load">{{ t('nginxMobile.refresh') }}</GhostBtn></div>
    <ListCard>
      <pre class="pre">{{ JSON.stringify(status, null, 2) }}</pre>
      <template v-if="compact">
        <PageErrorNotice v-if="failed">{{ t('nginxMobile.failed') }}</PageErrorNotice>
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
        <el-table-column prop="name" label="名称" />
        <el-table-column prop="domain" label="域名" />
        <el-table-column prop="status" label="状态" />
      </el-table>
    </ListCard>
  </div>
</template>
<style scoped>
.pre { font-size: 12px; color: var(--text-secondary); white-space: pre-wrap; }
@media (max-width: 760px) {
  .pre { font: var(--font-size-body)/1.5 var(--sans); overflow-wrap: anywhere; }
  .nginx-mobile-list { padding: 0; margin-top: 12px; }
  .nginx-mobile-toolbar { display: flex; justify-content: flex-end; margin-bottom: 12px; }
  .nginx-mobile-empty { display: grid; place-items: center; min-height: 88px; margin: 0; color: var(--text-secondary); font: var(--font-size-body)/1.5 var(--sans); }
}
</style>
