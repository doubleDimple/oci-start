import { ref } from 'vue'

export const progressVisible = ref(false)
export const progressWidth = ref(0)

let active = 0
let raf: number | null = null
let showTimer: number | null = null
let hideTimer: number | null = null

const SHOW_DELAY = 80
const TARGET = 90

function clearShowTimer() { if (showTimer) { clearTimeout(showTimer); showTimer = null } }
function clearHideTimer() { if (hideTimer) { clearTimeout(hideTimer); hideTimer = null } }
function clearRaf() { if (raf) { cancelAnimationFrame(raf); raf = null } }

function tick() {
  if (raf) return
  const step = () => {
    if (active === 0 || !progressVisible.value) { raf = null; return }
    const remaining = TARGET - progressWidth.value
    if (remaining > 0.5) {
      progressWidth.value += Math.min(remaining * 0.05 + 0.3, remaining)
    }
    raf = requestAnimationFrame(step)
  }
  raf = requestAnimationFrame(step)
}

function showAndAnimate() {
  progressVisible.value = true
  if (progressWidth.value < 8) progressWidth.value = 8
  tick()
}

export function startProgress() {
  clearHideTimer()
  active++
  if (active !== 1) return
  if (progressVisible.value) {
    showAndAnimate()
    return
  }
  progressWidth.value = 0
  clearShowTimer()
  showTimer = window.setTimeout(() => {
    showTimer = null
    if (active > 0) showAndAnimate()
  }, SHOW_DELAY)
}

export function doneProgress() {
  if (active === 0) return
  active--
  if (active !== 0) return
  clearShowTimer()
  if (!progressVisible.value) {
    progressWidth.value = 0
    return
  }
  progressWidth.value = 100
  clearHideTimer()
  hideTimer = window.setTimeout(() => {
    hideTimer = null
    progressVisible.value = false
    progressWidth.value = 0
    clearRaf()
  }, 320)
}

export function finishProgress() {
  if (active === 0) return
  active = 1
  doneProgress()
}
