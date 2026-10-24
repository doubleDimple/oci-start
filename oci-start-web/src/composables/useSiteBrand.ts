import { ref } from 'vue'
import request from '@/api/request'

// Public presentation data stays in memory; credentials never belong here.
export const siteLogoName = ref('')
let loadGeneration = 0

export function setSiteLogoName(name: string) {
  // A confirmed save must win over any earlier layout read still in flight.
  loadGeneration += 1
  siteLogoName.value = name.trim()
}

export async function loadSiteBrand(signal?: AbortSignal): Promise<boolean> {
  if (signal?.aborted) return false
  const generation = ++loadGeneration
  try {
    const response = await request.get<never, { success: boolean; data: { logoName: string } }>('/api/system/settings/logo', {
      silent: true,
      signal,
      headers: { 'Cache-Control': 'no-cache, no-store', Pragma: 'no-cache' },
    })
    if (signal?.aborted || generation !== loadGeneration) return false
    if (response?.success !== true || typeof response.data?.logoName !== 'string') return false
    siteLogoName.value = response.data.logoName.trim()
    return true
  } catch {
    // Keep the current brand, or the layout's translated default, on read failure.
    return false
  }
}
