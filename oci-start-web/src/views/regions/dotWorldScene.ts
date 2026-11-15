import type { RegionGlobePoint } from './globeTypes'
import { LAND_MASK_BASE64, LAND_MASK_COLS, LAND_MASK_RES, LAND_MASK_ROWS, LAND_MASK_TOP } from './landMask'
import { REGION_SCENE_ERROR_EVENT, type RegionScene, type RegionSceneColors, type RegionSceneOptions } from './sceneTypes'

const LAT_TOP = LAND_MASK_TOP
const LAT_BOTTOM = LAND_MASK_TOP - LAND_MASK_ROWS * LAND_MASK_RES
const LAT_SPAN = LAT_TOP - LAT_BOTTOM
// Target on-screen spacing of the dot matrix; dots stay anchored to geography while zooming.
const DOT_SPACING = 5.5
const GLOW_RADIUS = 60
const TAU = Math.PI * 2
const FONT = '600 12px -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif'

interface MapPoint {
  data: RegionGlobePoint
  x: number
  y: number
  born: number
  phase: number
  label: string
  button: HTMLButtonElement
}
interface LabelBox { x: number; y: number; width: number; height: number; point: MapPoint }

let landMask: Uint8Array | null = null
function isLand(lng: number, lat: number) {
  if (!landMask) landMask = Uint8Array.from(atob(LAND_MASK_BASE64), char => char.charCodeAt(0))
  const row = Math.floor((LAND_MASK_TOP - lat) / LAND_MASK_RES)
  const col = Math.floor((lng + 180) / LAND_MASK_RES)
  if (row < 0 || row >= LAND_MASK_ROWS || col < 0 || col >= LAND_MASK_COLS) return false
  const index = row * LAND_MASK_COLS + col
  return (landMask[index >> 3] & (1 << (index & 7))) !== 0
}
function phaseFor(code: string) {
  let hash = 0
  for (let i = 0; i < code.length; i++) hash = (hash * 31 + code.charCodeAt(i)) | 0
  return Math.abs(hash) % 2200
}

/** Canvas 2D implementation of the supplied dot-world-map reference. */
export function createDotWorldScene(host: HTMLElement, labelHost: HTMLElement, options: RegionSceneOptions): RegionScene {
  const doc = host.ownerDocument
  const view = doc.defaultView || window
  const canvas = doc.createElement('canvas')
  const base = doc.createElement('canvas')
  const context = canvas.getContext('2d')
  const baseContext = base.getContext('2d')
  if (!context || !baseContext) throw new Error('Canvas 2D is unavailable')
  const ctx: CanvasRenderingContext2D = context
  const baseCtx: CanvasRenderingContext2D = baseContext
  const colors: RegionSceneColors = { ...options.colors }

  const originalPosition = host.style.position
  const changedPosition = view.getComputedStyle(host).position === 'static'
  if (changedPosition) host.style.position = 'relative'
  canvas.className = 'region-dot-canvas'
  canvas.setAttribute('aria-hidden', 'true')
  Object.assign(canvas.style, { position: 'absolute', inset: '0', display: 'block', width: '100%', height: '100%', touchAction: 'pan-y' })
  host.appendChild(canvas)

  const overlays = doc.createElement('div')
  overlays.className = 'region-dot-overlays'
  Object.assign(overlays.style, { position: 'absolute', inset: '0', pointerEvents: 'none', overflow: 'hidden' })
  labelHost.appendChild(overlays)
  const tooltip = doc.createElement('div')
  tooltip.className = 'region-dot-tooltip'
  tooltip.setAttribute('aria-hidden', 'true')
  Object.assign(tooltip.style, {
    position: 'absolute', display: 'none', pointerEvents: 'none', zIndex: '3',
    maxWidth: '260px', padding: '6px 9px', borderRadius: '6px',
    font: '12px -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif',
    lineHeight: '1.45', whiteSpace: 'normal', overflowWrap: 'anywhere',
    background: colors.panel, color: colors.text, border: '1px solid ' + colors.coast,
    boxShadow: '0 4px 16px rgba(0,0,0,.12)',
  })
  const tooltipName = doc.createElement('strong')
  tooltipName.style.fontWeight = '500'
  const tooltipCoordinates = doc.createElement('div')
  Object.assign(tooltipCoordinates.style, { color: colors.muted, font: '10.5px ui-monospace, "SF Mono", monospace', marginTop: '2px' })
  tooltip.append(tooltipName, tooltipCoordinates)
  overlays.appendChild(tooltip)

  let width = 0
  let height = 0
  let pixelRatio = 1
  let scale = 1
  let magnification = 1
  let centerLng = 0
  let centerLat = (LAT_TOP + LAT_BOTTOM) / 2
  let selected = options.selectedRegion
  let hovered: string | null = null
  let labels = options.labels !== false
  let pulse = options.pulse !== false
  let links = options.links !== false
  let reduced = options.reducedMotion
  let active = true
  let disposed = false
  let failed = false
  let frame = 0
  let points: MapPoint[] = []
  let linkPairs: [MapPoint, MapPoint][] = []
  let labelBoxes: LabelBox[] = []
  let resizeObserver: ResizeObserver | null = null
  let hoverPoint: MapPoint | null = null

  function isVisible(point: MapPoint, padding = 0) {
    return point.x >= -padding && point.y >= -padding && point.x <= width + padding && point.y <= height + padding
  }
  function project(point: MapPoint) {
    point.x = width / 2 + (point.data.lng - centerLng) * scale
    point.y = height / 2 + (centerLat - point.data.lat) * scale
    point.button.style.left = point.x - 14 + 'px'
    point.button.style.top = point.y - 14 + 'px'
    point.button.hidden = !isVisible(point)
    point.button.setAttribute('aria-pressed', String(point.data.regionCode === selected))
    point.button.classList.toggle('selected', point.data.regionCode === selected)
  }
  function layoutLabels() {
    labelBoxes = []
    if (!labels || !width || !height) return
    ctx.font = FONT
    const ordered = [...points].sort((a, b) => Number(b.data.regionCode === selected) - Number(a.data.regionCode === selected))
    for (const point of ordered) {
      if (!point.label || !isVisible(point)) continue
      const labelWidth = Math.min(140, ctx.measureText(point.label).width)
      const on = point.data.regionCode === selected || point.data.regionCode === hovered
      const offsets = [-8, -26, 10, -44, 28, 46]
      let found: LabelBox | undefined
      for (const yOffset of offsets) {
        for (const toLeft of [point.x > width - labelWidth - 26, point.x <= width - labelWidth - 26]) {
          const x = point.x + (toLeft ? -labelWidth - 16 : 16)
          const y = point.y + yOffset
          const candidate = { x, y, width: labelWidth, height: 16, point }
          if (x < 10 || y < 8 || x + labelWidth > width - 10 || y + 16 > height - 8) continue
          const overlapsMarker = points.some(other => other !== point && other.x > x - 14 && other.x < x + labelWidth + 14 && other.y > y - 10 && other.y < y + 26)
          if (!overlapsMarker && !labelBoxes.some(box => x < box.x + box.width + 18 && x + labelWidth + 18 > box.x && y < box.y + box.height + 8 && y + 24 > box.y)) {
            found = candidate
            break
          }
        }
        if (found) break
      }
      if (found) labelBoxes.push(found)
      else if (on) labelBoxes.push({ x: Math.max(10, Math.min(width - labelWidth - 10, point.x + 16)), y: Math.max(8, Math.min(height - 24, point.y - 8)), width: labelWidth, height: 16, point })
    }
  }
  function buildBase() {
    base.width = Math.max(1, Math.round(width * pixelRatio))
    base.height = Math.max(1, Math.round(height * pixelRatio))
    baseCtx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0)
    baseCtx.clearRect(0, 0, width, height)
    if (!width || !height) return
    // The dot matrix is cached and rebuilt only when the viewport, palette or points change.
    const step = LAND_MASK_RES * Math.max(1, Math.round(DOT_SPACING / (LAND_MASK_RES * scale)))
    const radius = Math.max(.8, Math.min(2.2, step * scale * .3))
    const lngFrom = Math.max(-180, centerLng - width / 2 / scale)
    const lngTo = Math.min(180, centerLng + width / 2 / scale)
    const latFrom = Math.min(LAT_TOP, centerLat + height / 2 / scale)
    const latTo = Math.max(LAT_BOTTOM, centerLat - height / 2 / scale)
    const anchors = points.map(point => [width / 2 + (point.data.lng - centerLng) * scale, height / 2 + (centerLat - point.data.lat) * scale])
    const glowing: [number, number, number][] = []
    baseCtx.fillStyle = colors.land
    baseCtx.beginPath()
    for (let row = Math.floor((LAT_TOP - latFrom) / step); LAT_TOP - row * step > latTo; row++) {
      const lat = LAT_TOP - (row + .5) * step
      const y = height / 2 + (centerLat - lat) * scale
      for (let col = Math.floor((lngFrom + 180) / step); -180 + col * step < lngTo; col++) {
        const lng = -180 + (col + .5) * step
        if (!isLand(lng, lat)) continue
        const x = width / 2 + (lng - centerLng) * scale
        baseCtx.moveTo(x + radius, y)
        baseCtx.arc(x, y, radius, 0, TAU)
        let nearest = GLOW_RADIUS
        for (const [ax, ay] of anchors) nearest = Math.min(nearest, Math.hypot(ax - x, ay - y))
        if (nearest < GLOW_RADIUS) glowing.push([x, y, 1 - nearest / GLOW_RADIUS])
      }
    }
    baseCtx.fill()
    // Land around each region picks up the marker colour, fading with distance.
    baseCtx.fillStyle = colors.marker
    for (const [x, y, strength] of glowing) {
      baseCtx.globalAlpha = strength * strength * .7
      baseCtx.beginPath()
      baseCtx.arc(x, y, radius, 0, TAU)
      baseCtx.fill()
    }
    baseCtx.globalAlpha = 1
  }
  function updateView() {
    scale = Math.max(.001, Math.min(Math.max(1, width - 24) / 360, Math.max(1, height - 24) / LAT_SPAN)) * magnification
    buildBase()
    points.forEach(project)
    layoutLabels()
    updateTooltip(hoverPoint)
    redraw()
  }
  function setHover(point: MapPoint | null) {
    if (hovered === (point?.data.regionCode ?? null)) return
    hovered = point?.data.regionCode ?? null
    hoverPoint = point
    canvas.style.cursor = point ? 'pointer' : 'default'
    updateTooltip(point)
    layoutLabels()
    redraw()
  }
  function updateTooltip(point: MapPoint | null) {
    if (!point || !isVisible(point) || !active || doc.hidden) { tooltip.style.display = 'none'; return }
    tooltipName.textContent = options.ariaLabel(point.data)
    tooltipCoordinates.textContent = point.data.lat.toFixed(4) + ', ' + point.data.lng.toFixed(4)
    tooltip.style.maxWidth = Math.max(80, Math.min(260, width - 16)) + 'px'
    tooltip.style.display = 'block'
    const tipWidth = tooltip.offsetWidth
    const tipHeight = tooltip.offsetHeight
    tooltip.style.left = Math.max(8, Math.min(width - tipWidth - 8, point.x - tipWidth / 2)) + 'px'
    tooltip.style.top = Math.max(8, point.y - tipHeight - 12 < 8 ? point.y + 14 : point.y - tipHeight - 12) + 'px'
  }
  function drawRing(point: MapPoint, radius: number, color: string, alpha: number, lineWidth = 1.2) {
    ctx.strokeStyle = color
    ctx.globalAlpha = alpha
    ctx.lineWidth = lineWidth
    ctx.beginPath()
    ctx.arc(point.x, point.y, radius, 0, TAU)
    ctx.stroke()
    ctx.globalAlpha = 1
  }
  function drawLinks(now: number) {
    if (!links) return
    for (const [start, end] of linkPairs) {
      // The supplied reference offsets a quadratic control point by 22% of its chord.
      const dx = end.x - start.x
      const dy = end.y - start.y
      const controlX = (start.x + end.x) / 2 - dy * .22
      const controlY = (start.y + end.y) / 2 + dx * .22
      if (Math.max(start.x, end.x, controlX) < 0 || Math.min(start.x, end.x, controlX) > width || Math.max(start.y, end.y, controlY) < 0 || Math.min(start.y, end.y, controlY) > height) continue
      ctx.strokeStyle = colors.marker
      ctx.globalAlpha = .45
      ctx.lineWidth = 1.2
      ctx.lineCap = 'round'
      ctx.beginPath()
      ctx.moveTo(start.x, start.y)
      ctx.quadraticCurveTo(controlX, controlY, end.x, end.y)
      ctx.stroke()
      ctx.globalAlpha = 1
      if (reduced || !active || doc.hidden) continue
      // Link motion is independent of the node pulse switch: a short comet travels the arc.
      const head = (now / 2600) % 1
      ctx.fillStyle = colors.marker
      for (let i = 0; i < 8; i++) {
        const progress = head - i * .012
        if (progress <= 0) break
        const remaining = 1 - progress
        const x = remaining * remaining * start.x + 2 * remaining * progress * controlX + progress * progress * end.x
        const y = remaining * remaining * start.y + 2 * remaining * progress * controlY + progress * progress * end.y
        ctx.globalAlpha = Math.sin(Math.PI * progress) * (1 - i / 8)
        ctx.beginPath()
        ctx.arc(x, y, 2 - i * .15, 0, TAU)
        ctx.fill()
      }
      ctx.globalAlpha = 1
    }
  }
  function draw(now: number) {
    if (!width || !height) return
    ctx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0)
    ctx.clearRect(0, 0, width, height)
    ctx.fillStyle = colors.surface
    ctx.fillRect(0, 0, width, height)
    ctx.drawImage(base, 0, 0, width, height)
    drawLinks(now)
    const moving = pulse && !reduced && active && !doc.hidden
    for (const point of points) {
      if (!isVisible(point, 32)) continue
      const on = point.data.regionCode === selected || point.data.regionCode === hovered
      const color = colors.marker
      if (moving) {
        const age = now - point.born
        if (age >= 0 && age < 900) drawRing(point, 4 + age / 900 * 26, color, (1 - age / 900) * .9, 2)
        const phase = ((now + point.phase) % 2200) / 2200
        drawRing(point, 3 + phase * (on ? 16 : 11), color, (1 - phase) * (on ? .75 : .45))
      }
      const radius = on ? 18 : 13
      const glow = ctx.createRadialGradient(point.x, point.y, 0, point.x, point.y, radius)
      glow.addColorStop(0, color)
      glow.addColorStop(1, 'rgba(0,0,0,0)')
      ctx.globalAlpha = on ? .45 : .28
      ctx.fillStyle = glow
      ctx.beginPath()
      ctx.arc(point.x, point.y, radius, 0, TAU)
      ctx.fill()
      ctx.globalAlpha = 1
      // A lifted panel-coloured ring keeps markers clear on land and crossing links.
      ctx.shadowColor = 'rgba(0,0,0,.22)'
      ctx.shadowBlur = 4
      ctx.shadowOffsetY = 1
      ctx.fillStyle = colors.panel
      ctx.beginPath()
      ctx.arc(point.x, point.y, on ? 7 : 5.5, 0, TAU)
      ctx.fill()
      ctx.shadowColor = 'transparent'
      ctx.shadowBlur = 0
      ctx.shadowOffsetY = 0
      if (on) drawRing(point, 9.5, color, .55, 1.5)
      ctx.fillStyle = color
      ctx.beginPath()
      ctx.arc(point.x, point.y, on ? 4.5 : 3.6, 0, TAU)
      ctx.fill()
    }
    ctx.font = FONT
    ctx.textAlign = 'left'
    ctx.textBaseline = 'middle'
    for (const box of labelBoxes) {
      const on = box.point.data.regionCode === selected || box.point.data.regionCode === hovered
      ctx.shadowColor = 'rgba(0,0,0,.12)'
      ctx.shadowBlur = on ? 10 : 6
      ctx.shadowOffsetY = 1
      ctx.fillStyle = colors.panel
      ctx.globalAlpha = on ? 1 : .92
      ctx.beginPath()
      ctx.roundRect(box.x - 7, box.y - 3, box.width + 14, box.height + 6, 11)
      ctx.fill()
      ctx.shadowColor = 'transparent'
      ctx.shadowBlur = 0
      ctx.shadowOffsetY = 0
      ctx.globalAlpha = 1
      ctx.fillStyle = on ? colors.marker : colors.text
      ctx.fillText(box.point.label, box.x, box.y + 8, 140)
    }
  }
  function canAnimate() { return !disposed && !failed && active && !doc.hidden && !reduced && ((pulse && points.length > 0) || (links && linkPairs.length > 0)) && width > 0 && height > 0 }
  function stopFrame() {
    if (frame) view.cancelAnimationFrame(frame)
    frame = 0
  }
  function fail() {
    if (disposed || failed) return
    failed = true
    stopFrame()
    tooltip.style.display = 'none'
    host.dispatchEvent(new CustomEvent(REGION_SCENE_ERROR_EVENT))
  }
  function schedule() {
    if (!canAnimate()) { stopFrame(); return }
    if (!frame) frame = view.requestAnimationFrame(tick)
  }
  function tick(now: number) {
    frame = 0
    if (!canAnimate()) return
    try { draw(now) } catch { fail(); return }
    schedule()
  }
  function redraw() {
    if (disposed || failed) return
    if (active && !doc.hidden) {
      try { draw(view.performance.now()) } catch { fail(); return }
    }
    schedule()
  }
  function selectPoint(point: MapPoint) {
    if (disposed || !active) return
    options.onInteract()
    selected = point.data.regionCode
    points.forEach(project)
    layoutLabels()
    redraw()
    options.onSelect(point.data.regionCode)
  }
  function hitCandidates(event: MouseEvent | PointerEvent) {
    const rect = canvas.getBoundingClientRect()
    if (!rect.width || !rect.height) return []
    const x = (event.clientX - rect.left) * width / rect.width
    const y = (event.clientY - rect.top) * height / rect.height
    return points.map(point => ({ point, distance: (point.x - x) ** 2 + (point.y - y) ** 2 }))
      .filter(hit => hit.distance <= 14 ** 2 && isVisible(hit.point))
      .sort((a, b) => a.distance - b.distance)
  }
  function onMove(event: PointerEvent) {
    if (!active || disposed) return
    const hits = hitCandidates(event)
    const first = hits[0]?.point
    const current = hits.find(hit => hit.point.data.regionCode === selected && first && Math.hypot(hit.point.x - first.x, hit.point.y - first.y) < 2)?.point
    setHover(current || first || null)
  }
  function onLeave() { setHover(null) }
  function onClick(event: MouseEvent) {
    if (!active || disposed) return
    const first = hitCandidates(event)[0]?.point
    if (!first) return
    // Identical coordinates remain individually selectable on successive clicks.
    const coincident = points.filter(point => Math.hypot(point.x - first.x, point.y - first.y) < 2)
    const current = coincident.findIndex(point => point.data.regionCode === selected)
    const point = coincident[(current + 1) % coincident.length] || first
    selectPoint(point)
    setHover(point)
  }
  function setPoints(next: RegionGlobePoint[]) {
    if (disposed) return
    const previous = new Map(points.map(point => [point.data.regionCode, point]))
    const now = view.performance.now()
    points = next.filter(point => Number.isFinite(point.lat) && Number.isFinite(point.lng) && Math.abs(point.lat) <= 90 && Math.abs(point.lng) <= 180).map(data => {
      const old = previous.get(data.regionCode)
      const button = old?.button || doc.createElement('button')
      const point: MapPoint = { data, x: 0, y: 0, born: old?.born ?? now, phase: phaseFor(data.regionCode), label: options.label(data), button }
      button.type = 'button'
      button.className = 'region-scene-pin region-dot-pin'
      button.setAttribute('aria-label', options.ariaLabel(data))
      // Canvas owns the reference's appearance; transparent buttons add keyboard access.
      Object.assign(button.style, {
        position: 'absolute', width: '28px', height: '28px', minWidth: '0', minHeight: '0', padding: '0',
        margin: '0', border: '0', borderRadius: '50%', background: 'transparent',
        boxShadow: 'none', transform: 'none', pointerEvents: 'none', appearance: 'none', fontSize: '0',
      })
      button.onclick = () => selectPoint(point)
      button.onfocus = () => { button.style.outline = '2px solid ' + colors.text; setHover(point) }
      button.onblur = () => { button.style.outline = 'none'; setHover(null) }
      const name = doc.createElement('strong')
      name.className = 'region-scene-name'
      name.textContent = point.label
      name.hidden = true
      name.style.display = 'none'
      const coordinates = doc.createElement('span')
      coordinates.className = 'region-scene-coordinates'
      coordinates.textContent = data.lat.toFixed(4) + ', ' + data.lng.toFixed(4)
      coordinates.hidden = true
      coordinates.style.display = 'none'
      button.replaceChildren(name, coordinates)
      project(point)
      return point
    })
    const nextCodes = new Set(points.map(point => point.data.regionCode))
    for (const [code, point] of previous) if (!nextCodes.has(code)) point.button.remove()
    // Retain existing DOM nodes in place so refreshes and locale changes preserve focus.
    for (const point of points) if (point.button.parentNode !== overlays) overlays.insertBefore(point.button, tooltip)
    // Decorative links use only current real points, in stable region-code order.
    const ordered = [...points].sort((a, b) => a.data.regionCode < b.data.regionCode ? -1 : a.data.regionCode > b.data.regionCode ? 1 : 0)
    linkPairs = []
    for (let i = 1; i < ordered.length; i++) {
      const start = ordered[i - 1]
      const end = ordered[i]
      if (start.data.lat !== end.data.lat || start.data.lng !== end.data.lng) linkPairs.push([start, end])
    }
    if (selected && !nextCodes.has(selected)) selected = null
    hoverPoint = points.find(point => point.data.regionCode === hovered) || null
    hovered = hoverPoint?.data.regionCode ?? null
    updateTooltip(hoverPoint)
    buildBase()
    layoutLabels()
    redraw()
  }
  function resize() {
    if (disposed || failed) return
    const rect = host.getBoundingClientRect()
    const nextWidth = Math.max(0, host.clientWidth || rect.width)
    const nextHeight = Math.max(0, host.clientHeight || rect.height)
    const nextRatio = Math.min(view.devicePixelRatio || 1, 2)
    if (nextWidth === width && nextHeight === height && nextRatio === pixelRatio) { redraw(); return }
    width = nextWidth
    height = nextHeight
    pixelRatio = nextRatio
    canvas.width = Math.max(1, Math.round(width * pixelRatio))
    canvas.height = Math.max(1, Math.round(height * pixelRatio))
    try { updateView() } catch { fail() }
  }
  function onVisibility() {
    if (doc.hidden) { stopFrame(); tooltip.style.display = 'none' }
    else { updateTooltip(hoverPoint); redraw() }
  }
  function onContextLost(event: Event) { event.preventDefault(); fail() }
  canvas.addEventListener('pointermove', onMove)
  canvas.addEventListener('pointerleave', onLeave)
  canvas.addEventListener('click', onClick)
  canvas.addEventListener('contextlost', onContextLost)
  doc.addEventListener('visibilitychange', onVisibility)
  if (typeof ResizeObserver !== 'undefined') {
    resizeObserver = new ResizeObserver(resize)
    resizeObserver.observe(host)
  } else view.addEventListener('resize', resize)

  const api: RegionScene = {
    setColors(next) {
      if (disposed || failed) return
      Object.assign(colors, next)
      Object.assign(tooltip.style, { background: colors.panel, color: colors.text, borderColor: colors.coast })
      tooltipCoordinates.style.color = colors.muted
      for (const point of points) if (doc.activeElement === point.button) point.button.style.outlineColor = colors.text
      buildBase()
      redraw()
    },
    setPoints,
    setSelected(code) {
      if (disposed) return
      selected = code
      const point = points.find(item => item.data.regionCode === code)
      if (point && magnification > 1) {
        centerLng = point.data.lng
        centerLat = Math.max(LAT_BOTTOM, Math.min(LAT_TOP, point.data.lat))
        updateView()
      } else {
        points.forEach(project)
        layoutLabels()
        redraw()
      }
    },
    setReducedMotion(value) { if (!disposed) { reduced = value; redraw() } },
    setActive(value) {
      if (disposed) return
      active = value
      overlays.style.visibility = value ? 'visible' : 'hidden'
      if (!value) { stopFrame(); tooltip.style.display = 'none' }
      else { resize(); updateTooltip(hoverPoint); redraw() }
    },
    setLabels(value) { if (!disposed) { labels = value; layoutLabels(); redraw() } },
    setPulse(value) { if (!disposed) { pulse = value; redraw() } },
    setLinks(value) { if (!disposed) { links = value; redraw() } },
    resize,
    zoom(direction) {
      if (disposed || !direction) return
      options.onInteract()
      magnification = Math.max(1, Math.min(4, magnification * (direction > 0 ? 1.25 : .8)))
      const point = points.find(item => item.data.regionCode === selected)
      centerLng = magnification > 1 && point ? point.data.lng : 0
      centerLat = magnification > 1 && point ? Math.max(LAT_BOTTOM, Math.min(LAT_TOP, point.data.lat)) : (LAT_TOP + LAT_BOTTOM) / 2
      updateView()
    },
    reset() {
      if (disposed) return
      options.onInteract()
      magnification = 1
      centerLng = 0
      centerLat = (LAT_TOP + LAT_BOTTOM) / 2
      updateView()
    },
    dispose() {
      if (disposed) return
      disposed = true
      stopFrame()
      resizeObserver?.disconnect()
      view.removeEventListener('resize', resize)
      doc.removeEventListener('visibilitychange', onVisibility)
      canvas.removeEventListener('pointermove', onMove)
      canvas.removeEventListener('pointerleave', onLeave)
      canvas.removeEventListener('click', onClick)
      canvas.removeEventListener('contextlost', onContextLost)
      for (const point of points) { point.button.onclick = null; point.button.onfocus = null; point.button.onblur = null }
      points = []
      linkPairs = []
      labelBoxes = []
      hoverPoint = null
      canvas.remove()
      overlays.remove()
      canvas.width = base.width = 1
      canvas.height = base.height = 1
      if (changedPosition && host.style.position === 'relative') host.style.position = originalPosition
    },
  }
  setPoints(options.points)
  resize()
  return api
}
