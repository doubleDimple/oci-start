import type { RegionGlobePoint } from './globeTypes'

export interface RegionSceneColors {
  surface: string
  land: string
  grid: string
  arm: string
  mine: string
  text: string
  muted: string
}

export interface RegionSceneOptions {
  points: RegionGlobePoint[]
  selectedRegion: string | null
  reducedMotion: boolean
  labels?: boolean
  pulse?: boolean
  links?: boolean
  onSelect: (code: string) => void
  onInteract: () => void
  label: (point: RegionGlobePoint) => string
  ariaLabel: (point: RegionGlobePoint) => string
  colors: RegionSceneColors
}

export interface RegionScene {
  setPoints(points: RegionGlobePoint[]): void
  setSelected(code: string | null): void
  setReducedMotion(value: boolean): void
  setActive(value: boolean): void
  setLabels(value: boolean): void
  setPulse(value: boolean): void
  setLinks(value: boolean): void
  resize(): void
  zoom(direction: number): void
  reset(): void
  dispose(): void
}

// The renderer dispatches this event on its host after a rendering/context failure.
// The wrapper can dispose the instance and show its localized retry action.
export const REGION_SCENE_ERROR_EVENT = 'region-scene-error'
