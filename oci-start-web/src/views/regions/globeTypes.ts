export interface RegionGlobePoint {
  regionCode: string
  name: string
  lat: number
  lng: number
  /** Linked to one of the user's accounts; other Oracle regions render as quiet markers. */
  isMine: boolean
}
