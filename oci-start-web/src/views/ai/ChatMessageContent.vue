<script setup lang="ts">
import { nextTick, onBeforeUnmount, onErrorCaptured, shallowRef, watch, type Component } from 'vue'

const props = defineProps<{ content: string; streaming?: boolean }>()
const emit = defineEmits<{ copy: [text: string]; rendered: [] }>()
const renderer = shallowRef<Component>()
let requested = false
let disposed = false

function loadRenderer() {
  if (requested || disposed || !props.content) return
  requested = true
  void import('./ChatMarkdown.vue').then(async (module) => {
    if (disposed) return
    renderer.value = module.default
    await nextTick()
    if (!disposed) emit('rendered')
  }).catch(() => {
    // The message remains readable if the renderer or one of its libraries fails.
  })
}

watch(() => props.content, loadRenderer, { immediate: true })
onErrorCaptured(() => {
  // A rendering failure must never replace the assistant's text with a blank area.
  renderer.value = undefined
  return false
})
onBeforeUnmount(() => { disposed = true })
</script>

<template>
  <component :is="renderer" v-if="renderer" :content="content" :streaming="streaming" @copy="emit('copy', $event)" />
  <div v-else class="chat-message-plain">{{ content }}</div>
</template>

<style scoped>
.chat-message-plain {
  min-width: 0;
  color: inherit;
  font: inherit;
  line-height: 1.7;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
</style>
