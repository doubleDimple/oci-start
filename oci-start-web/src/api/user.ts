import request from './request'

export function fetchUserInfo(options: { signal?: AbortSignal; lang?: string } = {}) {
  return request.get<never, { success: boolean; data: { username: string } }>('/api/userInfo', {
    silent: true,
    signal: options.signal,
    params: options.lang ? { lang: options.lang } : undefined,
  })
}

export function logout() {
  return request.post<never, { success: boolean }>('/perform_logout', undefined, { silent: true })
}
