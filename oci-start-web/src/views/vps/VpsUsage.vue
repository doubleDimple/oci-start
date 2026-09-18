<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
const props = defineProps<{ value: number | null; label: string; detail?: string; detailTitle?: string }>()
const { locale } = useI18n()
const amount = computed(() => props.value != null && Number.isFinite(props.value) && props.value >= 0 && props.value <= 100 ? props.value : null)
const percentage = computed(() => amount.value == null ? '—' : new Intl.NumberFormat(locale.value, { style: 'percent', maximumFractionDigits: 1 }).format(amount.value / 100))
const level = computed(() => amount.value == null ? 'unknown' : amount.value > 90 ? 'danger' : amount.value > 70 ? 'warning' : 'normal')
</script>
<template>
  <div class="vps-usage">
    <strong>{{ percentage }}</strong>
    <span class="vps-usage-track" :role="amount == null ? undefined : 'progressbar'" :aria-label="label" :aria-valuenow="amount ?? undefined" :aria-valuemin="0" :aria-valuemax="100" :aria-valuetext="percentage"><span v-if="amount != null" :class="`is-${level}`" :style="{ width: `${amount}%` }" /></span>
    <small v-if="detail" class="vps-truncate" :title="detailTitle || detail">{{ detail }}</small>
  </div>
</template>
