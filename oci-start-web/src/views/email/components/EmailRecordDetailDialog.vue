<script setup lang="ts">
import { computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import GhostBtn from '@/components/GhostBtn.vue'
import MobileRecordList from '@/components/MobileRecordList.vue'
import MobileRecordCard from '@/components/MobileRecordCard.vue'
import { useCompactViewport } from '@/composables/useCompactViewport'
import PagePagination from '@/components/PagePagination.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { listEmailSendRecords, type EmailBody } from '@/api/email'
import { useEmailPage } from '../useEmailPage'
import { formatEmailTime } from '../presentation'

const props = defineProps<{ record: EmailBody | null }>()
const emit = defineEmits<{ close: [] }>()
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const compact = useCompactViewport()
const details = useEmailPage(10, (pageNum, pageSize, signal) => listEmailSendRecords({
  pageNum, pageSize, sort: 'createTime', order: 'desc', emailBodyId: props.record?.emailBodyId || '',
}, signal))
const problem = computed(() => details.problem ? details.problem.detail || t(`emailManagement.errors.${details.problem.key}`) : '')
const count = (value: number) => new Intl.NumberFormat(locale.value).format(value)
watch(() => props.record?.emailBodyId, () => {
  details.reset()
  const page = Number(route.query.mobileEmailRecipientPage)
  if (props.record) void details.load(String(props.record.id) === route.query.mobileEmailBody && Number.isSafeInteger(page) && page > 0 ? page : 1)
}, { immediate: true })
watch([() => details.page, () => details.loading], () => {
  if (!compact.value || !props.record || details.loading || !details.loaded || !route.query.mobileEmailBody || route.query.mobileEmailRecipientPage === String(details.page)) return
  void router.replace({ query: { ...route.query, mobileEmailRecipientPage: String(details.page) } })
})
</script>

<template>
  <el-dialog :model-value="!!record" :title="t('emailManagement.details')" width="920px" class="email-detail-dialog" append-to-body @update:model-value="emit('close')">
    <template v-if="record">
      <dl class="email-detail-meta">
        <div><dt>{{ t('emailManagement.subject') }}</dt><dd>{{ record.title || t('emailManagement.unnamed') }}</dd></div>
        <div><dt>{{ t('emailManagement.sendTime') }}</dt><dd :title="t('emailManagement.timeHint')">{{ formatEmailTime(record.createTime, locale) }}</dd></div>
        <div><dt>{{ t('emailManagement.sender') }}</dt><dd>{{ record.senderEmail || '—' }}</dd></div>
        <div><dt>{{ t('emailManagement.tenant') }}</dt><dd>{{ record.tenantName || '—' }}</dd></div>
      </dl>
      <h3>{{ t('emailManagement.content') }}</h3>
      <div class="email-plain-content">{{ record.content || t('emailManagement.emptyContent') }}</div>
      <div class="email-detail-toolbar"><h3>{{ t('emailManagement.recipients') }}</h3><GhostBtn :loading="details.loading" @click="details.load()">{{ t('emailManagement.refresh') }}</GhostBtn></div>
      <p class="email-detail-note">{{ t('emailManagement.statusHint') }}</p>
      <PageErrorNotice v-if="problem" class="email-detail-read-notice"><span>{{ problem }} <span v-if="details.loaded">{{ t('emailManagement.keepPage') }}</span></span><GhostBtn :loading="details.loading" @click="details.retry()">{{ t('emailManagement.retry') }}</GhostBtn></PageErrorNotice>
      <MobileRecordList v-if="compact" drilldown :list-id="`email-recipients-${record.emailBodyId}`" :record-keys="details.rows.map(row => row.id)" :loading="details.loading">
        <MobileRecordCard v-for="row in details.rows" :key="row.id" :record-key="row.id" :summary-title="row.receiveEmailAddress" :summary-meta="formatEmailTime(row.createTime, locale)" :summary-status="t(row.sendState === 1 ? 'emailManagement.success' : row.sendState === 0 ? 'emailManagement.unsuccessful' : 'emailManagement.unknown')" :summary-tone="row.sendState === 1 ? 'success' : row.sendState === 0 ? 'warning' : 'neutral'">
          <template #identity><div class="mobile-record-title">{{ row.receiveEmailAddress }}</div></template>
          <dl class="mobile-record-fields"><div class="mobile-record-wide"><dt>{{ t('emailManagement.sendTime') }}</dt><dd>{{ formatEmailTime(row.createTime, locale) }}</dd></div><div class="mobile-record-wide"><dt>{{ t('emailManagement.sendState') }}</dt><dd><span class="email-status" :class="{ success: row.sendState === 1, warning: row.sendState === 0 }">{{ t(row.sendState === 1 ? 'emailManagement.success' : row.sendState === 0 ? 'emailManagement.unsuccessful' : 'emailManagement.unknown') }}</span></dd></div></dl>
        </MobileRecordCard>
        <p v-if="!details.rows.length" class="email-detail-note" role="status">{{ t(details.loading ? 'emailManagement.loading' : problem ? 'emailManagement.loadFailed' : 'emailManagement.detailsEmpty') }}</p>
      </MobileRecordList>
      <el-table v-else :data="details.rows" v-loading="details.loading" :element-loading-text="t('emailManagement.loading')" max-height="310" row-key="id" :empty-text="t(details.loading ? 'emailManagement.loading' : problem ? 'emailManagement.loadFailed' : 'emailManagement.detailsEmpty')">
        <el-table-column prop="receiveEmailAddress" :label="t('emailManagement.recipientAddress')" min-width="270" show-overflow-tooltip />
        <el-table-column :label="t('emailManagement.sendTime')" width="190" show-overflow-tooltip><template #default="{ row }">{{ formatEmailTime(row.createTime, locale) }}</template></el-table-column>
        <el-table-column :label="t('emailManagement.sendState')" width="160"><template #default="{ row }"><span class="email-status" :class="{ success: row.sendState === 1, warning: row.sendState === 0 }">{{ t(row.sendState === 1 ? 'emailManagement.success' : row.sendState === 0 ? 'emailManagement.unsuccessful' : 'emailManagement.unknown') }}</span></template></el-table-column>
      </el-table>
      <PagePagination embedded class="email-detail-pagination" :current-page="details.page" :page-size="details.size" :total="details.total" :disabled="details.loading" @current-change="details.load"><span>{{ details.loaded ? t('emailManagement.count', { count: count(details.total) }) : t('emailManagement.countUnknown') }}</span></PagePagination>
    </template>
    <template #footer><GhostBtn @click="emit('close')">{{ t('emailManagement.close') }}</GhostBtn></template>
  </el-dialog>
</template>

<style lang="scss">
.email-detail-dialog { max-width: calc(100vw - 28px); font: var(--font-size-body)/1.5 var(--sans); color: var(--text-primary); }
.email-detail-dialog {
  .el-dialog__body { max-height: min(72vh, 820px); overflow: auto; }
  h3 { margin: 18px 0 10px; font-size: var(--font-size-section); font-weight: 600; }
  .email-detail-meta { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px 24px; margin: 0; }
  .email-detail-meta > div { min-width: 0; }
  dt { margin-bottom: 4px; color: var(--text-secondary); font-size: var(--font-size-body); }
  dd { margin: 0; overflow-wrap: anywhere; }
  .email-plain-content { max-height: 250px; overflow: auto; padding: 14px; border: 1px solid var(--border); border-radius: var(--r-sm); background: var(--bg-search); white-space: pre-wrap; overflow-wrap: anywhere; font: var(--font-size-body)/1.6 var(--sans); }
  .email-detail-toolbar { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 18px; }
  .email-detail-toolbar h3 { margin: 0; }
  .email-detail-toolbar .btn { min-height: 36px; padding: 7px 12px; }
  .email-detail-note { margin: 10px 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
  .email-detail-pagination { margin-top: 12px; }
  .email-status { color: var(--text-primary); }
  .email-status.success { color: var(--status-ok); }
  .email-status.warning { color: var(--status-warn); }
  .email-detail-read-notice { margin-bottom: 12px; }
  .el-dialog__footer { border-top: 1px solid var(--border); }
}
@media (max-width: 760px) {
  .email-detail-dialog .email-detail-meta { grid-template-columns: minmax(0, 1fr); }
  .email-detail-dialog .email-detail-toolbar .btn { min-height: 44px; }
}
</style>
