import { defineStore } from 'pinia'
import { fetchUserInfo, logout } from '@/api/user'

export const useUserStore = defineStore('user', {
  state: () => ({
    username: '',
  }),
  actions: {
    async load() {
      try {
        const res: any = await fetchUserInfo()
        this.username = res?.data?.username || ''
      } catch {
        this.username = ''
      }
    },
    async signOut() {
      try {
        await logout()
      } finally {
        window.location.href = '/login'
      }
    },
  },
})
