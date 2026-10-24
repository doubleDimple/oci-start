<script setup lang="ts">
import { computed, inject } from 'vue'
import { useI18n } from 'vue-i18n'
import { mobileRecordsKey } from '@/composables/useMobileRecords'

const props = withDefaults(defineProps<{
  recordKey?: string | number
  summaryTitle?: string
  summaryMeta?: string
  summaryStatus?: string
  summaryTone?: 'success' | 'danger' | 'warning' | 'neutral'
}>(), { summaryTitle: '', summaryMeta: '', summaryStatus: '', summaryTone: 'neutral' })
const { t } = useI18n()
const records = inject(mobileRecordsKey, null)
const key = computed(() => props.recordKey == null ? '' : String(props.recordKey))
const drilldown = computed(() => records?.enabled.value && !!key.value)
const summary = computed(() => drilldown.value && !records?.selected.value)
const visible = computed(() => !drilldown.value || !records?.selected.value || records.selected.value === key.value)
</script>

<template>
  <article v-if="visible" class="mobile-record-entry" :class="{ 'mobile-record-card': !summary }" data-motion-row>
    <button v-if="summary" type="button" class="mobile-record-summary" :data-record-key="key" :aria-label="t('mobileRecords.open', { name: summaryTitle })" @click="records?.open(key)">
      <span class="mobile-record-summary-text"><span class="mobile-record-summary-title">{{ summaryTitle || t('mobileRecords.unnamed') }}</span><span v-if="summaryMeta" class="mobile-record-summary-meta">{{ summaryMeta }}</span></span>
      <span v-if="summaryStatus" class="mobile-record-summary-status" :class="`is-${summaryTone}`"><span aria-hidden="true" />{{ summaryStatus }}</span>
      <i class="i-mdi-chevron-right mobile-record-summary-arrow" aria-hidden="true" />
    </button>
    <template v-else>
    <header class="mobile-record-header">
      <div class="mobile-record-identity"><slot name="identity" /></div>
      <div v-if="$slots.actions" class="mobile-record-actions"><slot name="actions" /></div>
    </header>
    <div class="mobile-record-content"><slot /></div>
    <footer v-if="$slots.footer" class="mobile-record-footer"><slot name="footer" /></footer>
    </template>
  </article>
</template>

<style scoped>
.mobile-record-entry { min-width: 0; }
.mobile-record-summary { display: flex; align-items: center; gap: 10px; width: 100%; min-height: 80px; padding: 14px; border: 0; background: transparent; text-align: left; color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); cursor: pointer; }
.mobile-record-summary:hover, .mobile-record-summary:active { background: var(--bg-hover); }
.mobile-record-summary:focus-visible { outline: 2px solid var(--brand); outline-offset: -3px; border-radius: 10px; }
.mobile-record-summary-text { display: flex; flex: 1; flex-direction: column; gap: 5px; min-width: 0; }
.mobile-record-summary-title, .mobile-record-summary-meta { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.mobile-record-summary-title { font-weight: 600; }
.mobile-record-summary-meta { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.mobile-record-summary-status { display: inline-flex; align-items: center; gap: 5px; flex: none; max-width: 36%; padding: 4px 7px; border-radius: var(--r-pill); color: var(--text-secondary); background: var(--bg-search); font-size: var(--font-size-caption); overflow-wrap: anywhere; }
.mobile-record-summary-status > span { width: 5px; height: 5px; border-radius: 50%; background: currentColor; flex: none; }
.mobile-record-summary-status.is-success { color: var(--status-ok); background: var(--status-ok-bg); }
.mobile-record-summary-status.is-danger { color: var(--status-danger); background: var(--status-danger-bg); }
.mobile-record-summary-status.is-warning { color: var(--status-warn); background: var(--status-warn-bg); }
.mobile-record-summary-arrow { flex: none; width: 20px; height: 20px; color: var(--text-secondary); }
.mobile-record-card { min-width: 0; overflow-wrap: anywhere; padding: 14px; border: 1px solid var(--border); border-radius: var(--r-card); background: var(--bg-card); color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); }
.mobile-record-header { display: flex; align-items: flex-start; gap: 10px; min-width: 0; }
.mobile-record-identity { flex: 1; min-width: 0; }
.mobile-record-actions { flex: none; display: flex; align-items: center; gap: 6px; }
.mobile-record-content { min-width: 0; margin-top: 12px; }
.mobile-record-footer { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--border); }
.mobile-record-card :deep(.mobile-record-title) { margin: 0; color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; overflow-wrap: anywhere; }
.mobile-record-card :deep(.mobile-record-subtitle) { display: block; margin-top: 4px; color: var(--text-secondary); font-size: var(--font-size-secondary); overflow-wrap: anywhere; }
.mobile-record-card :deep(.mobile-record-fields) { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px 14px; margin: 0; }
.mobile-record-card :deep(.mobile-record-fields > div) { min-width: 0; }
.mobile-record-card :deep(.mobile-record-fields dt) { margin-bottom: 3px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.mobile-record-card :deep(.mobile-record-fields dd) { min-width: 0; margin: 0; color: var(--text-primary); font-size: var(--font-size-body); overflow-wrap: anywhere; }
.mobile-record-card :deep(.mobile-record-wide) { grid-column: 1 / -1; }
.mobile-record-card :deep(.mobile-record-button) { display: inline-flex; align-items: center; justify-content: center; gap: 6px; min-height: 40px; max-width: 100%; padding: 8px 12px; border: 1px solid var(--border); border-radius: var(--r-pill); background: var(--bg-card); color: var(--text-primary); font: var(--font-size-body)/1.4 var(--sans); cursor: pointer; white-space: normal; }
.mobile-record-card :deep(.mobile-record-button:hover) { background: var(--bg-hover); }
.mobile-record-card :deep(.mobile-record-button:disabled) { opacity: .6; cursor: default; }
.mobile-record-card :deep(button:focus-visible) { outline: 2px solid var(--brand); outline-offset: 2px; }
.mobile-record-card :deep(.mobile-record-button i) { flex: none; width: 18px; height: 18px; }
</style>
