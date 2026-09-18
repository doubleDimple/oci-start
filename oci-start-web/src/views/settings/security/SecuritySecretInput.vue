<script setup lang="ts">
import { computed, onBeforeUnmount, onDeactivated, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'

const props = withDefaults(defineProps<{
  id: string
  label: string
  modelValue: string
  disabled?: boolean
  readonly?: boolean
  placeholder?: string
  autocomplete?: 'current-password' | 'new-password' | 'one-time-code' | 'off'
  copyable?: boolean
  revealDuration?: number
}>(), {
  disabled: false,
  readonly: false,
  autocomplete: 'new-password',
  copyable: false,
  revealDuration: 0,
})
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()
const { t } = useI18n()
const visible = ref(false)
const copying = ref(false)
const copyState = ref<'none' | 'copied' | 'copyFailed'>('none')
const visibilityLabel = computed(() => t(visible.value ? 'securitySettings.hideSecret' : 'securitySettings.showSecret', { field: props.label }))
const copyLabel = computed(() => t('securitySettings.copySecret', { field: props.label }))
let disposed = false
let copyGeneration = 0
let revealTimer: number | undefined

function resetPresentation() {
  window.clearTimeout(revealTimer)
  revealTimer = undefined
  copyGeneration += 1
  visible.value = false
  copying.value = false
  copyState.value = 'none'
}

function update(event: Event) {
  if (!props.disabled && !props.readonly) emit('update:modelValue', (event.target as HTMLInputElement).value)
}

function toggleVisibility() {
  if (props.disabled) return
  const next = !visible.value
  resetPresentation()
  visible.value = next
  if (next && Number.isFinite(props.revealDuration) && props.revealDuration > 0) {
    revealTimer = window.setTimeout(resetPresentation, props.revealDuration)
  }
}

async function copy() {
  if (props.disabled || !props.copyable || copying.value || !props.modelValue) return
  const generation = ++copyGeneration
  copying.value = true
  copyState.value = 'none'
  try {
    await navigator.clipboard.writeText(props.modelValue)
    if (!disposed && generation === copyGeneration) copyState.value = 'copied'
  } catch {
    if (!disposed && generation === copyGeneration) copyState.value = 'copyFailed'
  } finally {
    if (!disposed && generation === copyGeneration) copying.value = false
  }
}

function hideWhenInactive() {
  if (document.hidden) resetPresentation()
}

watch(() => [props.modelValue, props.disabled, props.readonly, props.copyable, props.revealDuration], resetPresentation, { flush: 'sync' })
onMounted(() => document.addEventListener('visibilitychange', hideWhenInactive))
onDeactivated(resetPresentation)
onBeforeUnmount(() => {
  disposed = true
  resetPresentation()
  document.removeEventListener('visibilitychange', hideWhenInactive)
})
</script>

<template>
  <div class="security-secret-field">
    <label :for="id">{{ label }}</label>
    <div class="security-secret-control" :class="{ 'is-disabled': disabled }">
      <input
        :id="id"
        :value="modelValue"
        :type="visible ? 'text' : 'password'"
        :disabled="disabled"
        :readonly="readonly"
        :placeholder="placeholder"
        :autocomplete="autocomplete"
        :aria-describedby="copyState === 'copied' ? `${id}-feedback` : undefined"
        autocapitalize="off"
        :spellcheck="false"
        @input="update"
      />
      <button type="button" :disabled="disabled" :aria-label="visibilityLabel" :title="visibilityLabel" :aria-pressed="visible" @click="toggleVisibility">
        <i :class="visible ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />
      </button>
      <button v-if="copyable" type="button" :disabled="disabled || copying || !modelValue" :aria-label="copyLabel" :title="copyLabel" :aria-busy="copying" @click="copy">
        <i class="i-mdi-content-copy" aria-hidden="true" />
      </button>
    </div>
    <PageErrorNotice v-if="copyState === 'copyFailed'" :label="t('securitySettings.copyFailed')">{{ t('securitySettings.copyFailed') }}</PageErrorNotice>
    <small v-else-if="copyState === 'copied'" :id="`${id}-feedback`" class="security-secret-feedback" role="status" aria-live="polite">{{ t('securitySettings.copied') }}</small>
  </div>
</template>

<style scoped>
.security-secret-field {
  display: grid;
  min-width: 0;
  gap: 7px;
  color: var(--text-primary);
  font-family: var(--sans);
  font-size: var(--font-size-body);
}
.security-secret-field > label {
  min-width: 0;
  font-size: var(--font-size-body);
  font-weight: 500;
  line-height: 1.5;
  overflow-wrap: anywhere;
}
.security-secret-control {
  display: flex;
  min-width: 0;
  height: 36px;
  box-sizing: border-box;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}
.security-secret-control:focus-within { border-color: var(--brand); }
.security-secret-control.is-disabled { background: var(--bg-search); }
.security-secret-control input {
  flex: 1 1 0;
  width: 0;
  min-width: 0;
  padding: 0 10px;
  border: 0;
  border-radius: inherit;
  outline: none;
  background: transparent;
  color: var(--text-primary);
  font: inherit;
  line-height: 1.5;
}
.security-secret-control input::placeholder { color: var(--text-muted); opacity: 1; }
.security-secret-control button {
  display: inline-flex;
  flex: 0 0 34px;
  align-items: center;
  justify-content: center;
  width: 34px;
  min-width: 0;
  padding: 0;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--text-primary);
  font: inherit;
  cursor: pointer;
}
.security-secret-control button i { width: 18px; height: 18px; }
.security-secret-control button:hover:not(:disabled) { background: var(--bg-hover); }
.security-secret-control button:focus-visible { outline: 2px solid var(--brand); outline-offset: -3px; }
.security-secret-control :disabled { cursor: not-allowed; }
.security-secret-control button:disabled { opacity: .5; }
.security-secret-feedback {
  min-width: 0;
  color: var(--text-secondary);
  font-size: var(--font-size-secondary);
  line-height: 1.5;
  overflow-wrap: anywhere;
}
.security-secret-feedback.is-error { color: var(--status-danger); }
</style>
