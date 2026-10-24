import { nextTick, onBeforeUnmount, onMounted, type Ref } from 'vue'
import { gsap } from 'gsap'

/** Scoped entrances that remain interruptible during rapid filtering and navigation. */
export function usePageMotion(root: Ref<HTMLElement | null>) {
  let mounted = false
  let motionAllowed = false
  let rowRequest = 0
  let media: gsap.MatchMedia | undefined
  let rowContext: gsap.Context | undefined

  function revealRows() {
    const request = ++rowRequest
    void nextTick().then(() => {
      if (!mounted || request !== rowRequest) return
      rowContext?.revert()
      rowContext = undefined
      if (!motionAllowed || !root.value) return
      const rows = Array.from(root.value.querySelectorAll<HTMLElement>('[data-motion-row]')).slice(0, 12)
      if (!rows.length) return
      rowContext = gsap.context(() => {
        gsap.fromTo(rows, { opacity: 0.35, y: 7 }, {
          opacity: 1, y: 0, duration: 0.36, stagger: 0.022, ease: 'power2.out',
          overwrite: 'auto', clearProps: 'opacity,transform',
        })
      }, root.value)
    })
  }

  onMounted(() => {
    mounted = true
    media = gsap.matchMedia(root.value || undefined)
    media.add('(prefers-reduced-motion: no-preference)', () => {
      motionAllowed = true
      if (root.value) {
        const elements = root.value.querySelectorAll<HTMLElement>('[data-motion-enter]')
        if (elements.length) {
          gsap.fromTo(elements, { opacity: 0, y: 12 }, {
            opacity: 1, y: 0, duration: 0.52, stagger: 0.065, ease: 'power3.out',
            overwrite: 'auto', clearProps: 'opacity,transform',
          })
        }
      }
      revealRows()
      return () => {
        motionAllowed = false
        rowRequest += 1
        rowContext?.revert()
        rowContext = undefined
      }
    })
  })

  onBeforeUnmount(() => {
    mounted = false
    rowRequest += 1
    media?.revert()
    rowContext?.revert()
  })

  return { revealRows }
}
