import type { RegionGlobePoint } from './globeTypes'
import { REGION_SCENE_ERROR_EVENT, type RegionScene, type RegionSceneOptions } from './sceneTypes'

// Simplified silhouettes from design/dot-world-map.html, retained as supplied.
// These are dot-pattern artwork, not political boundaries.
type Coordinate = readonly [number, number]
const LAND: readonly (readonly Coordinate[])[] = [
  [[-168,65],[-165,60],[-158,57],[-152,58],[-146,60],[-138,59],[-131,53],[-125,49],[-124,42],[-120,34],[-117,32],[-110,24],[-105,20],[-97,16],[-92,15],[-88,16],[-87,21],[-91,21],[-95,19],[-97,23],[-97,26],[-94,29],[-89,29],[-84,30],[-81,25],[-80,32],[-76,35],[-70,42],[-67,45],[-60,47],[-56,51],[-56,54],[-64,60],[-78,62],[-78,55],[-82,55],[-86,66],[-95,68],[-105,68],[-115,70],[-125,70],[-135,69],[-145,70],[-156,71],[-166,68]],
  [[-45,60],[-52,64],[-53,68],[-62,70],[-68,76],[-62,82],[-40,83],[-24,80],[-20,73],[-30,68],[-42,61]],
  [[-81,-4],[-79,0],[-77,8],[-72,12],[-62,10],[-60,8],[-52,5],[-50,0],[-44,-2],[-38,-5],[-35,-8],[-39,-13],[-39,-18],[-48,-25],[-53,-34],[-58,-38],[-62,-40],[-65,-45],[-68,-50],[-70,-54],[-75,-52],[-74,-45],[-73,-37],[-71,-30],[-70,-20],[-75,-15],[-81,-6]],
  [[-17,15],[-16,20],[-12,28],[-10,32],[-5,36],[10,37],[20,32],[28,31],[33,28],[35,23],[38,18],[43,12],[51,12],[51,5],[42,-1],[40,-10],[35,-20],[32,-26],[27,-34],[20,-35],[18,-30],[13,-20],[9,-1],[3,6],[-8,4],[-13,9]],
  [[-10,36],[-9,43],[-2,48],[3,51],[6,53],[9,54],[11,58],[16,60],[22,60],[30,60],[28,66],[21,70],[32,71],[46,68],[62,70],[76,73],[92,75],[106,77],[116,74],[132,72],[146,70],[160,70],[170,66],[179,65],[172,60],[162,58],[155,52],[142,48],[135,43],[130,35],[122,32],[120,25],[110,20],[105,10],[100,6],[97,16],[90,22],[82,17],[77,8],[72,20],[66,25],[57,25],[50,30],[45,37],[36,36],[30,41],[26,38],[22,40],[16,38],[13,45],[8,44],[3,42],[-2,37]],
  [[95,5],[105,-6],[115,-9],[125,-9],[135,-5],[141,-3],[141,-9],[131,-8],[120,-10],[110,-8],[100,0]],
  [[113,-22],[114,-35],[118,-35],[129,-32],[137,-35],[141,-38],[147,-39],[151,-37],[153,-28],[145,-15],[142,-11],[136,-12],[130,-11],[125,-14],[118,-20]],
  [[172,-41],[174,-37],[178,-38],[176,-41],[174,-46],[168,-46],[167,-44]],
  [[130,31],[134,34],[139,35],[141,39],[145,44],[142,42],[137,37],[132,34]],
  [[-5,50],[-6,55],[-3,58],[-1,56],[1,53],[1,51],[-4,50]],
  [[43,-12],[50,-15],[50,-25],[45,-25],[43,-17]],
  [[-24,65],[-22,66],[-14,66],[-14,64],[-22,63]],
  [[120,18],[124,18],[126,10],[122,6],[119,11]],
  [[-85,22],[-77,23],[-74,20],[-80,21]],
  [[8,55],[11,57],[13,55],[10,54]]
]
const LAND_BOUNDS = LAND.map(polygon => ({
  polygon,
  left: Math.min(...polygon.map(point => point[0])),
  right: Math.max(...polygon.map(point => point[0])),
  bottom: Math.min(...polygon.map(point => point[1])),
  top: Math.max(...polygon.map(point => point[1])),
}))
const LAT_TOP = 84
const LAT_BOTTOM = -58
const LAT_SPAN = LAT_TOP - LAT_BOTTOM
const DOT_STEP = 5
const DOT_RADIUS = 1.1
const TAU = Math.PI * 2
const FONT = '11px -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif'

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

function inPolygon(lng: number, lat: number, polygon: readonly Coordinate[]) {
  let inside = false
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const [xi, yi] = polygon[i]
    const [xj, yj] = polygon[j]
    if ((yi > lat) !== (yj > lat) && lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside
  }
  return inside
}
function isLand(lng: number, lat: number) {
  return LAND_BOUNDS.some(bounds => lng >= bounds.left && lng <= bounds.right && lat >= bounds.bottom && lat <= bounds.top && inPolygon(lng, lat, bounds.polygon))
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
  const colors = {
    surface: options.colors.surface || '#0a1420',
    land: options.colors.land || '#22506b',
    arm: options.colors.arm || '#e5b45c',
    mine: options.colors.mine || '#4fe3c1',
    text: options.colors.text || '#dcecf3',
    muted: options.colors.muted || '#6f93a8',
    grid: options.colors.grid || '#16293c',
  }

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
    background: colors.surface, color: colors.text, border: '1px solid ' + colors.grid,
    boxShadow: '0 2px 10px rgba(0,0,0,.25)',
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
      const offsets = [-13, 3, -29, 19, -45, 35]
      let found: LabelBox | undefined
      for (const yOffset of offsets) {
        for (const toLeft of [point.x > width - labelWidth - 18, point.x <= width - labelWidth - 18]) {
          const x = point.x + (toLeft ? -labelWidth - 8 : 8)
          const y = point.y + yOffset
          const candidate = { x, y, width: labelWidth, height: 13, point }
          if (x < 4 || y < 4 || x + labelWidth > width - 4 || y + 13 > height - 4) continue
          if (!labelBoxes.some(box => x < box.x + box.width + 4 && x + labelWidth + 4 > box.x && y < box.y + box.height + 2 && y + 15 > box.y)) {
            found = candidate
            break
          }
        }
        if (found) break
      }
      if (found) labelBoxes.push(found)
      else if (on) labelBoxes.push({ x: Math.max(4, Math.min(width - labelWidth - 4, point.x + 8)), y: Math.max(4, point.y - 13), width: labelWidth, height: 13, point })
    }
  }
  function buildBase() {
    base.width = Math.max(1, Math.round(width * pixelRatio))
    base.height = Math.max(1, Math.round(height * pixelRatio))
    baseCtx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0)
    baseCtx.clearRect(0, 0, width, height)
    baseCtx.fillStyle = colors.land
    // Pixel sampling stays at the reference's 5px / 1.1px, even after zooming.
    baseCtx.beginPath()
    for (let y = DOT_STEP / 2; y < height; y += DOT_STEP) {
      const lat = centerLat - (y - height / 2) / scale
      if (lat < LAT_BOTTOM || lat > LAT_TOP) continue
      for (let x = DOT_STEP / 2; x < width; x += DOT_STEP) {
        const lng = centerLng + (x - width / 2) / scale
        if (lng < -180 || lng > 180 || !isLand(lng, lat)) continue
        baseCtx.moveTo(x + DOT_RADIUS, y)
        baseCtx.arc(x, y, DOT_RADIUS, 0, TAU)
      }
    }
    baseCtx.fill()
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
      ctx.strokeStyle = colors.mine
      ctx.globalAlpha = .35
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(start.x, start.y)
      ctx.quadraticCurveTo(controlX, controlY, end.x, end.y)
      ctx.stroke()
      ctx.globalAlpha = 1
      if (reduced || !active || doc.hidden) continue
      // Link motion is independent of the node pulse switch.
      const progress = (now / 2600) % 1
      const remaining = 1 - progress
      const x = remaining * remaining * start.x + 2 * remaining * progress * controlX + progress * progress * end.x
      const y = remaining * remaining * start.y + 2 * remaining * progress * controlY + progress * progress * end.y
      ctx.fillStyle = colors.mine
      ctx.globalAlpha = Math.sin(Math.PI * progress)
      ctx.beginPath()
      ctx.arc(x, y, 1.8, 0, TAU)
      ctx.fill()
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
      const both = point.data.isOpen && point.data.isMine
      const color = point.data.isMine ? colors.mine : colors.arm
      if (moving) {
        const age = now - point.born
        if (age >= 0 && age < 900) drawRing(point, 4 + age / 900 * 26, color, (1 - age / 900) * .9, 2)
        const phase = ((now + point.phase) % 2200) / 2200
        drawRing(point, 3 + phase * (on ? 16 : 11), both ? colors.arm : color, (1 - phase) * (on ? .75 : .45))
      }
      const radius = on ? 13 : 9
      const glow = ctx.createRadialGradient(point.x, point.y, 0, point.x, point.y, radius)
      glow.addColorStop(0, color)
      glow.addColorStop(1, 'rgba(0,0,0,0)')
      ctx.globalAlpha = on ? .5 : .32
      ctx.fillStyle = glow
      ctx.beginPath()
      ctx.arc(point.x, point.y, radius, 0, TAU)
      ctx.fill()
      ctx.globalAlpha = 1
      if (both) drawRing(point, on ? 6.8 : 5.5, colors.arm, .95, 1.5)
      else if (on) drawRing(point, 6.6, color, .8, 1)
      ctx.fillStyle = color
      ctx.beginPath()
      ctx.arc(point.x, point.y, on ? 3.4 : 2.6, 0, TAU)
      ctx.fill()
    }
    ctx.font = FONT
    ctx.textAlign = 'left'
    ctx.textBaseline = 'middle'
    for (const box of labelBoxes) {
      ctx.fillStyle = box.point.data.regionCode === selected || box.point.data.regionCode === hovered ? colors.text : colors.muted
      ctx.fillText(box.point.label, box.x, box.y + 6.5, 140)
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
    points = next.filter(point => Number.isFinite(point.lat) && Number.isFinite(point.lng) && Math.abs(point.lat) <= 90 && Math.abs(point.lng) <= 180 && (point.isOpen || point.isMine)).map(data => {
      const old = previous.get(data.regionCode)
      const button = old?.button || doc.createElement('button')
      const point: MapPoint = { data, x: 0, y: 0, born: old?.born ?? now, phase: phaseFor(data.regionCode), label: options.label(data), button }
      button.type = 'button'
      button.className = 'region-scene-pin region-dot-pin ' + (data.isOpen && data.isMine ? 'both' : data.isMine ? 'mine' : 'arm')
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
