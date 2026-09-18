<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'

interface TurnstileApi {
  render(container: HTMLElement, options: Record<string, unknown>): string
  remove(widget: string): void
  reset(widget: string): void
}
const props = defineProps<{ siteKey: string; locale: string; theme: 'light' | 'dark'; retryLabel: string; failureLabel: string }>()
const emit = defineEmits<{ token: [value: string] }>()
const container = ref<HTMLElement>()
const failed = ref(false)
let widget: string | undefined
let disposed = false
let generation = 0
let script: HTMLScriptElement | undefined
let cancelLoad: (() => void) | undefined
const api = () => (window as unknown as { turnstile?: TurnstileApi }).turnstile

async function mount() {
  const current = ++generation
  failed.value = false
  emit('token', '')
  if (widget !== undefined) { api()?.remove(widget); widget = undefined }
  try {
    if (!api()) {
      cancelLoad?.()
      await new Promise<void>((resolve, reject) => {
        const node = document.createElement('script')
        script = node
        node.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
        node.async = true
        const finish = (error = false) => {
          clearTimeout(timeout)
          node.onload = node.onerror = null
          cancelLoad = undefined
          if (error) { node.remove(); reject(new Error('turnstile')) } else resolve()
        }
        const timeout = setTimeout(() => finish(true), 15000)
        cancelLoad = () => finish(true)
        node.onload = () => finish(!api())
        node.onerror = () => finish(true)
        document.head.append(node)
      })
    }
    if (disposed || current !== generation || !container.value || !api()) return
    widget = api()!.render(container.value, {
      sitekey: props.siteKey, theme: props.theme, language: props.locale === 'zh' ? 'zh-cn' : 'en', size: 'flexible',
      callback: (token: string) => { if (!disposed && current === generation) { failed.value = false; emit('token', token) } },
      'expired-callback': () => { if (!disposed && current === generation) emit('token', '') },
      'error-callback': () => { if (!disposed && current === generation) { failed.value = true; emit('token', '') } },
    })
  } catch { if (!disposed && current === generation) failed.value = true }
}
function reset() {
  emit('token', '')
  if (widget !== undefined && api()) { failed.value = false; api()!.reset(widget) }
  else void mount()
}
defineExpose({ reset })
onMounted(() => { void mount() })
watch(() => [props.siteKey, props.locale, props.theme], () => { void mount() })
onBeforeUnmount(() => {
  disposed = true
  generation++
  cancelLoad?.()
  if (widget !== undefined) api()?.remove(widget)
  script?.remove()
})
</script>

<template>
  <div class="auth-challenge">
    <div ref="container" class="cf-turnstile" />
    <div v-if="failed" class="message error-message" role="alert">{{ failureLabel }}</div>
    <button v-if="failed" type="button" class="btn" @click="reset">{{ retryLabel }}</button>
  </div>
</template>
