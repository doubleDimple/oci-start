import request from './request'

export function fetchDashboardStats() {
  return request.get('/boot/dashboard-stats', { silent: true, timeout: 5000 })
}

export function fetchMonitorStats() {
  return request.get('/monitor/stats', { silent: true, timeout: 5000 })
}
