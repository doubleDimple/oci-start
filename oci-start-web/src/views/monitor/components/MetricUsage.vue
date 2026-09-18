<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{ value: number | null; capacity: string; label: string }>()
const { locale } = useI18n()
const amount = computed(() => props.value != null && Number.isFinite(props.value) && props.value >= 0 && props.value <= 100 ? props.value : null)
const percentage = computed(() => amount.value == null ? '—' : new Intl.NumberFormat(locale.value, {
  style: 'percent', maximumFractionDigits: 1,
}).format(amount.value / 100))
const level = computed(() => amount.value == null ? 'unknown' : amount.value > 80 ? 'danger' : amount.value > 60 ? 'warning' : 'normal')
</script>

<template>
  <span class="metrics-usage">
    <span class="metrics-usage-values"><strong>{{ percentage }}</strong><span :title="capacity">{{ capacity }}</span></span>
    <span class="metrics-usage-track" :role="amount == null ? undefined : 'progressbar'" :aria-label="label" :aria-valuenow="amount ?? undefined" :aria-valuemin="0" :aria-valuemax="100" :aria-valuetext="percentage"><span v-if="amount != null" class="metrics-usage-fill" :class="`is-${level}`" :style="{ width: `${amount}%` }" /></span>
  </span>
</template>
