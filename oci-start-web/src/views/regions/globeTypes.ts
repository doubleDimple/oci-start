export interface RegionGlobePoint {
  regionCode: string
  name: string
  lat: number
  lng: number
  isOpen: boolean
  isMine: boolean
  architectureType: string
  openTime: string | null
  openCount: number
  monthlyOpenCount: number
  lastNotifyTime: string | null
}
