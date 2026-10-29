<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, watch } from 'vue'
import { gsap } from 'gsap'
const props = defineProps<{ value: number | null; format?: (value: number) => string }>()
const state = reactive({ value: 0 })
const text = computed(() => props.value === null ? '—' : props.format ? props.format(state.value) : Math.round(state.value).toLocaleString())
const actual = computed(() => props.value === null ? '—' : props.format ? props.format(props.value) : Math.round(props.value).toLocaleString())
let tween: gsap.core.Tween | undefined
let media: gsap.MatchMedia | undefined
let animate = false
function update() {
  tween?.kill()
  if (props.value === null) return
  if (!animate) state.value = props.value
  else tween = gsap.to(state, { value: props.value, duration: .65, ease: 'power2.out', overwrite: true })
}
onMounted(() => {
  media = gsap.matchMedia()
  media.add('(prefers-reduced-motion: no-preference)', () => {
    animate = true
    update()
    return () => { animate = false; tween?.kill(); state.value = props.value ?? 0 }
  })
  update()
})
watch(() => props.value, update)
onBeforeUnmount(() => { tween?.kill(); media?.revert() })
</script>

<template><span :aria-label="actual"><span aria-hidden="true">{{ text }}</span></span></template>
