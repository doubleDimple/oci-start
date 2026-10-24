import { chromeRevision } from '@/composables/useChrome'

export interface ChartTheme {
  text: string
  secondary: string
  muted: string
  surface: string
  border: string
  brand: string
  info: string
  warning: string
  fontFamily: string
  bodySize: number
  secondarySize: number
}

const colorTokens = {
  text: '--text-primary', secondary: '--text-secondary', muted: '--text-muted',
  surface: '--bg-card', border: '--border', brand: '--brand',
  info: '--status-info', warning: '--status-warn',
} as const
type ColorKey = keyof typeof colorTokens
let cachedRevision = -1
let cachedMode = ''
let cached: Readonly<ChartTheme> | undefined

/**
 * zrender 6's parser only understands legacy rgb/rgba, hsl/hsla, hex and named
 * colors. Computed custom properties can retain color-mix()/color(srgb ...).
 * Let the browser resolve CSS, then read one sRGB pixel instead of maintaining
 * another CSS color parser. All charts share one conversion batch per revision.
 */
export function readChartTheme(): Readonly<ChartTheme> {
  const root = document.documentElement
  const mode = root.getAttribute('data-content-theme') || root.getAttribute('data-theme') || 'light'
  const revision = chromeRevision.value
  if (cached && cachedRevision === revision && cachedMode === mode) return cached

  const styles = getComputedStyle(root)
  const token = (name: string) => styles.getPropertyValue(name).trim()
  // Keep chart text/surfaces legible if native color sampling is unavailable.
  const colors: Record<ColorKey, string> = {
    ...(mode === 'dark'
      ? { text: '#f5f5f7', secondary: '#d2d2d7', muted: '#b5b5bd', surface: '#1d1d1f', border: '#424245' }
      : { text: '#000000', secondary: '#000000', muted: '#000000', surface: '#ffffff', border: '#d2d2d7' }),
    brand: '#1b8a6a', info: '#0071e3', warning: '#b45309',
  }
  const canvas = document.createElement('canvas')
  canvas.width = canvas.height = 1
  const probe = document.createElement('span')
  probe.setAttribute('aria-hidden', 'true')
  probe.style.setProperty('display', 'none', 'important')
  root.appendChild(probe)
  try {
    const context = canvas.getContext('2d', { colorSpace: 'srgb', willReadFrequently: true })
    if (context) {
      for (const key of Object.keys(colorTokens) as ColorKey[]) {
        const value = token(colorTokens[key])
        if (!value || !CSS.supports('color', value)) continue
        probe.style.setProperty('color', value, 'important')
        const resolved = getComputedStyle(probe).color
        // Invalid canvas colors silently keep the previous fillStyle. Two
        // different sentinels distinguish rejection from a valid sentinel color.
        context.fillStyle = '#010203'
        context.fillStyle = resolved
        const accepted = context.fillStyle
        context.fillStyle = '#040506'
        context.fillStyle = resolved
        if (context.fillStyle !== accepted) continue
        context.clearRect(0, 0, 1, 1)
        context.fillRect(0, 0, 1, 1)
        const [red, green, blue, alpha] = context.getImageData(0, 0, 1, 1).data
        colors[key] = alpha === 255
          ? `rgb(${red}, ${green}, ${blue})`
          : `rgba(${red}, ${green}, ${blue}, ${Number((alpha! / 255).toFixed(4))})`
      }
    }
  } catch {
    // A blocked/unavailable canvas must not leak unsupported color expressions.
  } finally {
    probe.remove()
  }
  const bodySize = Number.parseFloat(token('--font-size-body'))
  const secondarySize = Number.parseFloat(token('--font-size-secondary'))
  cached = Object.freeze({
    ...colors,
    fontFamily: token('--sans') || styles.fontFamily,
    bodySize: Number.isFinite(bodySize) && bodySize > 0 ? bodySize : 14,
    secondarySize: Number.isFinite(secondarySize) && secondarySize > 0 ? secondarySize : 13,
  })
  cachedRevision = revision
  cachedMode = mode
  return cached
}
