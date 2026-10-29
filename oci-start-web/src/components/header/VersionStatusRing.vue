<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, useId, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { HeaderUpdateState, HeaderVersionInfo } from '@/api/headerVersion'

const props = defineProps<{
  active: boolean
  info: HeaderVersionInfo | null
  state: HeaderUpdateState
  startedAt: number | null
  loading: boolean
}>()
const { t } = useI18n()
const gradientId = `version-ring-${useId()}`
const estimateSeconds = 90
const now = ref(Date.now())
const documentVisible = ref(true)
let timer: number | undefined
const counting = computed(() => props.startedAt !== null && ['starting', 'started', 'unknown'].includes(props.state))
const seconds = computed(() => counting.value
  ? Math.max(0, Math.min(estimateSeconds, Math.ceil(estimateSeconds - (now.value - props.startedAt!) / 1000))) : estimateSeconds)
const clock = computed(() => `${String(Math.floor(seconds.value / 60)).padStart(2, '0')}:${String(seconds.value % 60).padStart(2, '0')}`)
const phase = computed(() => counting.value ? seconds.value === 0 ? 'waiting' : props.state
  : props.state === 'failed' ? 'failed' : !props.info ? props.loading ? 'loading' : 'unavailable' : props.info.needUpdate ? 'ready' : 'current')
const caption = computed(() => t(`headerVersion.${phase.value === 'waiting' ? 'waitingRecovery'
  : phase.value === 'starting' ? 'startingTitle' : phase.value === 'started' ? 'waitingRecovery'
    : phase.value === 'unknown' ? 'awaitingConfirmation' : phase.value === 'failed' ? 'failedTitle'
      : phase.value === 'loading' ? 'loading' : phase.value === 'unavailable' ? 'unavailable'
        : phase.value === 'ready' ? 'updateAvailable' : 'noUpdate'}`))
const icon = computed(() => phase.value === 'current' ? 'i-mdi-check'
  : ['failed', 'unknown', 'unavailable'].includes(phase.value) ? 'i-mdi-information-outline' : 'i-mdi-tray-arrow-up')

function stopClock() { window.clearInterval(timer); timer = undefined }
function syncClock() {
  stopClock()
  now.value = Date.now()
  if (props.active && documentVisible.value && counting.value && seconds.value > 0) {
    timer = window.setInterval(() => {
      now.value = Date.now()
      if (seconds.value === 0) stopClock()
    }, 1000)
  }
}
function onVisibilityChange() { documentVisible.value = !document.hidden; syncClock() }
watch(() => [props.active, props.startedAt, props.state], syncClock)
onMounted(() => { onVisibilityChange(); document.addEventListener('visibilitychange', onVisibilityChange) })
onBeforeUnmount(() => { stopClock(); document.removeEventListener('visibilitychange', onVisibilityChange) })
</script>

<template>
  <div class="version-ring-widget">
   <div class="version-status-ring" :data-phase="phase" :data-active="active && documentVisible" :aria-busy="phase === 'loading' || state === 'starting'">
    <svg class="version-ring-art" viewBox="0 0 300 300" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient :id="gradientId" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" class="ring-gradient-start" />
          <stop offset="100%" class="ring-gradient-end" />
        </linearGradient>
      </defs>
      <g class="ring-ticks">
        <line v-for="tick in 60" :key="tick" x1="150" :y1="tick % 5 === 0 ? 7 : 10" x2="150" y2="15" :transform="`rotate(${(tick - 1) * 6} 150 150)`" :class="{ 'is-major': tick % 5 === 0 }" />
      </g>
      <circle class="ring-inner" cx="150" cy="150" r="99" />
      <circle class="ring-track" cx="150" cy="150" r="119" />
      <g transform="rotate(-90 150 150)">
        <circle class="ring-halo" cx="150" cy="150" r="119" />
        <circle class="ring-value" cx="150" cy="150" r="119" pathLength="100" :stroke="`url(#${gradientId})`" :style="{ strokeDashoffset: counting ? 100 - seconds / estimateSeconds * 100 : 0 }" />
      </g>
      <g class="ring-orbit">
        <circle cx="150" cy="150" r="131" pathLength="100" />
        <circle class="orbit-point" cx="150" cy="19" r="3" />
      </g>
    </svg>
    <div class="version-ring-center">
      <template v-if="counting">
        <span class="ring-overline">{{ t('headerVersion.estimatedRemaining') }}</span>
        <span class="ring-clock" role="timer" aria-live="off" :aria-label="t('headerVersion.secondsRemaining', { seconds })">{{ clock }}</span>
      </template>
      <template v-else>
        <i class="ring-icon" :class="icon" aria-hidden="true" />
        <span class="ring-overline">{{ t('headerVersion.latestVersion') }}</span>
        <strong class="ring-version">{{ info?.latestVersion || t('headerVersion.unavailable') }}</strong>
      </template>
      <span class="ring-caption">{{ caption }}</span>
    </div>
   </div>
   <p v-if="counting" class="ring-estimate-note" role="status">{{ t(seconds === 0 ? 'headerVersion.estimateElapsed' : 'headerVersion.estimateOnly') }}</p>
  </div>
</template>

<style scoped>
.version-ring-widget { width: min(100%, 290px); justify-self: center; align-self: center; }
.version-status-ring { position: relative; width: 100%; aspect-ratio: 1; color: var(--brand); isolation: isolate; }
.version-status-ring::before { content: ''; position: absolute; inset: 15%; border-radius: 50%; background: radial-gradient(circle at 38% 30%, color-mix(in srgb, var(--brand-solid) 13%, transparent), color-mix(in srgb, var(--brand-solid) 3%, transparent) 70%); z-index: -1; }
.version-ring-art { display: block; width: 100%; overflow: visible; fill: none; }
.ring-gradient-start { stop-color: color-mix(in srgb, var(--brand-solid) 70%, var(--bg-card)); }
.ring-gradient-end { stop-color: color-mix(in srgb, var(--brand-solid) 84%, var(--brand)); }
.ring-ticks { stroke: color-mix(in srgb, var(--text-secondary) 25%, transparent); stroke-width: 1; }
.ring-ticks .is-major { stroke: color-mix(in srgb, var(--brand) 48%, var(--border)); stroke-width: 1.5; }
.ring-inner { stroke: color-mix(in srgb, var(--brand) 12%, var(--border)); stroke-dasharray: 1 7; }
.ring-track { stroke: color-mix(in srgb, var(--brand) 10%, var(--border)); stroke-width: 6; }
.ring-halo { stroke: var(--brand-solid); stroke-width: 18; opacity: .09; }
.ring-value { stroke-width: 5; stroke-linecap: round; stroke-dasharray: 100; transition: stroke-dashoffset 1s linear; }
.ring-orbit { transform-origin: 150px 150px; animation: version-orbit 12s linear infinite; }
.ring-orbit > circle:first-child { stroke: var(--brand); stroke-width: 1.2; stroke-dasharray: 7 43; opacity: .6; }
.orbit-point { fill: var(--brand-solid); stroke: var(--bg-card); stroke-width: 2; }
.version-ring-center { position: absolute; inset: 22% 17%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 7px; text-align: center; }
.ring-icon { display: block; font-size: 25px; margin-bottom: 1px; }
.ring-overline { color: var(--text-secondary); font-size: 12px; line-height: 1.4; }
.ring-version { max-width: 100%; color: var(--text-primary); font-size: 30px; letter-spacing: -.8px; line-height: 1.1; font-weight: 650; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
.ring-clock { color: var(--text-primary); font-size: 49px; font-weight: 550; line-height: 1.1; font-variant-numeric: tabular-nums; letter-spacing: -2px; }
.ring-caption { max-width: 100%; font-size: 12px; line-height: 1.5; color: var(--brand); }
.ring-estimate-note { margin: 2px -8px 0; color: var(--text-secondary); font-size: 12px; line-height: 1.6; text-align: center; }
[data-phase='ready'] .ring-orbit { animation-duration: 5s; animation-iteration-count: 1; }
[data-phase='current'] .ring-orbit, [data-phase='failed'] .ring-orbit, [data-phase='unavailable'] .ring-orbit { animation: none; }
[data-phase='failed'] .ring-value, [data-phase='unavailable'] .ring-value { opacity: .25; }
[data-phase='loading'] .ring-value { stroke-dasharray: 20 80; }
[data-phase='unknown'] .ring-value { opacity: .6; }
[data-phase='waiting'] .ring-orbit { animation-duration: 16s; }
[data-active='false'] .ring-orbit { animation-play-state: paused; }
@keyframes version-orbit { to { transform: rotate(360deg); } }
@media (max-width: 600px) { .version-ring-widget { width: min(100%, 230px); } .ring-clock { font-size: 43px; } .ring-version { font-size: 27px; } .ring-estimate-note { margin-inline: -20px; } }
@media (prefers-reduced-motion: reduce) { .ring-orbit { animation: none !important; } .ring-value { transition: none; } }
</style>
