<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'

const props = defineProps<{
  fieldId: string
  label: string
  hint: string
  modelValue: string
  disabled?: boolean
}>()
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()
const { t } = useI18n()
const visible = ref(false)
const copying = ref(false)
const copyState = ref<'none' | 'copied' | 'copyFailed'>('none')
const describedBy = computed(() => `${props.fieldId}-hint${copyState.value === 'copied' ? ` ${props.fieldId}-copy` : ''}`)
let disposed = false
let sequence = 0

function update(event: Event) { emit('update:modelValue', (event.target as HTMLInputElement).value) }
function toggleVisibility() { if (!props.disabled) visible.value = !visible.value }
async function copy() {
  if (props.disabled || copying.value || !props.modelValue) return
  const current = ++sequence
  copying.value = true
  copyState.value = 'none'
  try {
    await navigator.clipboard.writeText(props.modelValue)
    if (!disposed && current === sequence) copyState.value = 'copied'
  } catch {
    if (!disposed && current === sequence) copyState.value = 'copyFailed'
  } finally {
    if (!disposed && current === sequence) copying.value = false
  }
}
watch(() => props.modelValue, () => { ++sequence; copying.value = false; copyState.value = 'none' })
watch(() => props.disabled, disabled => { if (disabled) visible.value = false })
onBeforeUnmount(() => { disposed = true; ++sequence; visible.value = false })
</script>

<template>
  <div class="domain-provider-field">
    <label :for="fieldId">{{ label }}</label>
    <div class="provider-secret" :class="{ 'is-disabled': disabled }">
      <input :id="fieldId" :value="modelValue" :type="visible ? 'text' : 'password'" :disabled="disabled" :aria-describedby="describedBy" autocomplete="new-password" autocapitalize="off" :spellcheck="false" @input="update" />
      <button type="button" :disabled="disabled" :aria-label="t(visible ? 'domainProviders.hideSecret' : 'domainProviders.showSecret', { field: label })" :title="t(visible ? 'domainProviders.hideSecret' : 'domainProviders.showSecret', { field: label })" :aria-pressed="visible" @click="toggleVisibility"><i :class="visible ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" /></button>
      <button type="button" :disabled="disabled || copying || !modelValue" :aria-label="t('domainProviders.copySecret', { field: label })" :title="t('domainProviders.copySecret', { field: label })" @click="copy"><i :class="copying ? 'i-mdi-loading animate-spin' : 'i-mdi-content-copy'" aria-hidden="true" /></button>
    </div>
    <small :id="`${fieldId}-hint`">{{ hint }}</small>
    <PageErrorNotice v-if="copyState === 'copyFailed'" :label="t('domainProviders.copyFailed')">{{ t('domainProviders.copyFailed') }}</PageErrorNotice>
    <span v-else-if="copyState === 'copied'" :id="`${fieldId}-copy`" class="provider-secret-feedback" role="status">{{ t('domainProviders.copied') }}</span>
  </div>
</template>
