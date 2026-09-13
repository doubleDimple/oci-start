import { defineStore } from 'pinia'
import { PROVIDERS } from '@/nav/menu'

const PROVIDER_KEY = 'selectedCloudProvider'
const SIDE_KEY = 'sidebar_collapsed'

function readProvider(): { type: number; name: string } {
  try {
    const raw = localStorage.getItem(PROVIDER_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      // The header now exposes OCI only; discard a previously selected hidden provider.
      if (Number(parsed?.type) === 1) return { type: 1, name: 'Oracle Cloud' }
    }
  } catch { /* ignore */ }
  return { type: 1, name: 'Oracle Cloud' }
}

function readCollapsed() {
  try { return localStorage.getItem(SIDE_KEY) === '1' } catch { return false }
}

export const useShellStore = defineStore('shell', {
  state: () => ({
    path: '/boot/dashboard',
    active: 'api-dashboard',
    cloudType: readProvider().type,
    cloudName: readProvider().name,
    collapsed: readCollapsed(),
    menuQuery: '',
  }),
  actions: {
    hydrateFromUrl() {
      const q = new URLSearchParams(window.location.search)
      this.path = q.get('path') || '/boot/dashboard'
      this.active = q.get('active') || (this.path === '/boot/dashboard' ? 'api-dashboard' : '')
      const cloud = q.get('cloudType')
      if (cloud) this.setCloud(Number(cloud))
    },
    open(path: string, active: string, newTab = false) {
      if (newTab) {
        const url = `/main?path=${encodeURIComponent(path)}&active=${encodeURIComponent(active)}`
        window.open(url, '_blank', 'noopener')
        return
      }
      this.path = path
      this.active = active
      const url = new URL(window.location.href)
      url.pathname = '/main'
      url.searchParams.set('path', path)
      url.searchParams.set('active', active)
      window.history.replaceState({}, '', url.toString())
    },
    setCloud(type: number) {
      const found = PROVIDERS.find((p) => p.type === type) || PROVIDERS[0]
      this.cloudType = found.type
      this.cloudName = found.name
      try { localStorage.setItem(PROVIDER_KEY, JSON.stringify({ type: found.type, name: found.name })) } catch { /* session only */ }
    },
    toggleCollapsed() {
      this.collapsed = !this.collapsed
      try { localStorage.setItem(SIDE_KEY, this.collapsed ? '1' : '0') } catch { /* session only */ }
    },
  },
})
