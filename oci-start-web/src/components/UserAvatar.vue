<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(defineProps<{
  name?: string
  context?: 'header' | 'sidebar'
}>(), { name: '', context: 'header' })

const initial = computed(() => {
  const first = props.name.trim().match(/[\p{L}\p{N}]/u)?.[0]
  return first ? Array.from(first.toUpperCase())[0] : ''
})
</script>

<template>
  <svg class="user-avatar" :class="{ 'is-sidebar': context === 'sidebar' }" viewBox="0 0 40 40" aria-hidden="true" focusable="false">
    <circle class="user-avatar-face" cx="20" cy="20" r="19.5" />
    <text v-if="initial" x="20" y="20.5" text-anchor="middle" dominant-baseline="central">{{ initial }}</text>
    <g v-else class="user-avatar-person" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="20" cy="15.5" r="4.5" />
      <path d="M12.5 29v-1.5a7.5 7.5 0 0 1 15 0V29" />
    </g>
  </svg>
</template>

<style scoped>
.user-avatar {
  --avatar-background: var(--bg-search);
  --avatar-border: color-mix(in srgb, var(--text-primary) 14%, transparent);
  display: block;
  flex: 0 0 auto;
  width: 32px;
  height: 32px;
  overflow: hidden;
  border-radius: 50%;
  color: var(--text-primary);
  user-select: none;
}
.user-avatar.is-sidebar {
  --avatar-background: color-mix(in srgb, var(--text-on-dark) 10%, var(--bg-sidebar));
  --avatar-border: color-mix(in srgb, var(--text-on-dark) 22%, transparent);
  width: 36px;
  height: 36px;
  color: var(--text-on-dark);
}
.user-avatar-face { fill: var(--avatar-background); stroke: var(--avatar-border); stroke-width: 1; }
.user-avatar text { fill: currentColor; font-family: var(--sans); font-size: 16px; font-weight: 600; letter-spacing: -.02em; }
.user-avatar-person { opacity: .88; }
</style>
