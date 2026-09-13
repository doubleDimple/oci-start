import { defineStore } from 'pinia'
import { fetchUserInfo, logout } from '@/api/user'

let loadGeneration = 0

export const useUserStore = defineStore('user', {
  state: () => ({
    username: '',
    loading: false,
    loadFailed: false,
    signingOut: false,
  }),
  actions: {
    async load(signal?: AbortSignal) {
      const generation = ++loadGeneration
      this.loading = true
      this.loadFailed = false
      try {
        const res = await fetchUserInfo({ signal })
        if (signal?.aborted || generation !== loadGeneration) return
        if (!res?.success || typeof res.data?.username !== 'string' || !res.data.username) throw new Error('Invalid user response')
        this.username = res.data.username
      } catch {
        if (!signal?.aborted && generation === loadGeneration) this.loadFailed = true
      } finally {
        if (generation === loadGeneration) this.loading = false
      }
    },
    async signOut() {
      if (this.signingOut) return false
      this.signingOut = true
      try {
        const res = await logout()
        if (res?.success !== true) throw new Error('Logout not acknowledged')
        this.username = ''
        window.location.assign('/login')
        return true
      } catch {
        this.signingOut = false
        return false
      }
    },
  },
})
