<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useCompactViewport } from '@/composables/useCompactViewport'

const props = withDefaults(defineProps<{
  currentPage?: number
  pageSize?: number
  total?: number
  pageCount?: number
  pageSizes?: number[]
  disabled?: boolean
  embedded?: boolean
  cursor?: boolean
  hasNext?: boolean
  hasPrevious?: boolean
}>(), { currentPage: 1, pageSizes: () => [], disabled: false, embedded: false, cursor: false, hasNext: false, hasPrevious: undefined })
const emit = defineEmits<{
  'update:currentPage': [page: number]
  'update:pageSize': [size: number]
  'current-change': [page: number]
  'size-change': [size: number]
}>()
const { t, locale } = useI18n()
const compact = useCompactViewport()
const layout = computed(() => `${props.pageSizes.length ? 'sizes, ' : ''}prev, ${compact.value ? 'slot' : 'pager'}, next`)
const previousAvailable = computed(() => props.hasPrevious ?? props.currentPage > 1)
const pageLabel = computed(() => new Intl.NumberFormat(locale.value).format(props.currentPage))
// Let Element Plus keep its normal page clamping when totals change; disabled
// prevents user gestures without suppressing those controlled-state updates.
function updatePage(value: number) { emit('update:currentPage', value) }
function changePage(value: number) { emit('current-change', value) }
function updateSize(value: number) { emit('update:pageSize', value) }
function changeSize(value: number) { emit('size-change', value) }
function chooseCursorSize(value: unknown) {
  if (props.disabled || typeof value !== 'number' || !props.pageSizes.includes(value)) return
  updateSize(value)
  changeSize(value)
}
function move(direction: -1 | 1) {
  if (props.disabled || (direction === -1 ? !previousAvailable.value : !props.hasNext)) return
  const value = props.currentPage + direction
  updatePage(value)
  changePage(value)
}
</script>

<template>
  <div class="page-pagination" :class="{ 'is-embedded': embedded }">
    <div v-if="$slots.default" class="page-pagination-summary"><slot /></div>
    <nav v-if="cursor" class="page-pagination-cursor" :aria-label="t('pagePagination.label')">
      <el-select v-if="pageSizes.length" class="page-pagination-size" :model-value="pageSize" :disabled="disabled" :aria-label="t('pagePagination.pageSize')" @change="chooseCursorSize">
        <el-option v-for="value in pageSizes" :key="value" :value="value" :label="t('pagePagination.perPage', { count: value })" />
      </el-select>
      <button type="button" :disabled="disabled || !previousAvailable" :aria-label="t('pagePagination.previous')" @click="move(-1)"><i class="i-mdi-chevron-left" aria-hidden="true" /></button>
      <span aria-current="page">{{ pageLabel }}</span>
      <button type="button" :disabled="disabled || !hasNext" :aria-label="t('pagePagination.next')" @click="move(1)"><i class="i-mdi-chevron-right" aria-hidden="true" /></button>
    </nav>
    <el-pagination v-else background :current-page="currentPage" :page-size="pageSize" :total="total" :page-count="pageCount"
      :page-sizes="pageSizes" :pager-count="5" :layout="layout" :disabled="disabled" :aria-label="t('pagePagination.label')"
      @update:current-page="updatePage" @update:page-size="updateSize" @current-change="changePage" @size-change="changeSize">
      <span v-if="compact" class="page-pagination-current" aria-current="page">{{ pageLabel }}</span>
    </el-pagination>
  </div>
</template>

<style scoped lang="scss">
.page-pagination {
  display: flex; flex: none; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px;
  width: 100%; min-width: 0; box-sizing: border-box; padding: 12px 18px;
  border-top: 1px solid color-mix(in srgb, var(--border) 40%, transparent);
  color: var(--text-secondary); font: var(--font-size-secondary)/1.5 var(--sans);
}
.page-pagination.is-embedded { padding: 0; border: 0; }
.page-pagination-summary { display: flex; align-items: center; flex-wrap: wrap; gap: 5px 14px; min-width: 0; overflow-wrap: anywhere; }
.page-pagination-summary :deep(p) { margin: 0; }
.page-pagination :deep(.el-pagination) {
  flex: none; flex-wrap: wrap; justify-content: flex-end; row-gap: 6px; max-width: 100%; margin-left: auto;
  font-family: var(--sans); --el-pagination-font-size: var(--font-size-body); --el-pagination-font-size-small: var(--font-size-body);
}
.page-pagination :deep(.el-pager li), .page-pagination :deep(.el-select__wrapper), .page-pagination :deep(.el-input__inner) { font-size: var(--font-size-body); }
.page-pagination :deep(.btn-prev), .page-pagination :deep(.btn-next), .page-pagination :deep(.el-pager li) { border-radius: 8px; }
.page-pagination :deep(.el-pagination__sizes) { margin-left: 0; }
.page-pagination-cursor { display: flex; flex: none; flex-wrap: wrap; align-items: center; gap: 8px; max-width: 100%; margin-left: auto; font-size: var(--font-size-body); font-variant-numeric: tabular-nums; }
.page-pagination-size { width: 128px; margin-right: 8px; }
.page-pagination-current { display: inline-grid; place-items: center; min-width: 32px; height: 32px; padding: 0 6px; border-radius: 8px; background: var(--brand); color: var(--nav-active-fg); font-weight: 600; }
.page-pagination-cursor > button, .page-pagination-cursor > span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; box-sizing: border-box; padding: 0 6px; border: 0; border-radius: 8px; background: var(--el-fill-color-light); color: var(--text-primary); font: inherit; }
.page-pagination-cursor > button { cursor: pointer; }
.page-pagination-cursor > button > i { width: 16px; height: 16px; }
.page-pagination-cursor > button:hover:not(:disabled) { color: var(--brand); }
.page-pagination-cursor > button:disabled { color: var(--el-disabled-text-color); cursor: not-allowed; }
.page-pagination-cursor > span { background: var(--brand); color: var(--nav-active-fg); font-weight: 600; }
@media (max-width: 680px) {
  .page-pagination { align-items: flex-start; flex-direction: column; padding: 12px; }
  .page-pagination :deep(.el-pagination) { justify-content: flex-start; gap: 6px; margin-left: 0; }
  .page-pagination :deep(.el-pagination.is-background .btn-prev), .page-pagination :deep(.el-pagination.is-background .btn-next) { margin: 0; }
  .page-pagination-cursor { margin-left: 0; }
  .page-pagination :deep(.el-pagination__sizes) { margin-right: 4px; }
  .page-pagination :deep(.el-pagination__sizes .el-select), .page-pagination-size { width: 112px; }
}
</style>
