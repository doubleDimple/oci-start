import request from './request'

export interface DashboardStats {
  totalApiCalls?: number
  totalBootInstances?: number
  totalAttempts?: number
  successfulAttempts?: number
  failCounts?: number
}

export interface SystemMetrics {
  cpuUsage?: number | null
  cpuTemperature?: number | null
  cpuPhysicalCount?: number | null
  cpuLogicalCount?: number | null
  cpuModel?: string
  cpuFrequency?: number | null
  memoryUsage?: number | null
  totalMemory?: number | null
  availableMemory?: number | null
  usedMemory?: number | null
  swapUsage?: number | null
  swapTotal?: number | null
  swapUsed?: number | null
  diskUsage?: number | null
  diskTotal?: number | null
  diskUsed?: number | null
  diskFree?: number | null
  uploadSpeed?: number | null
  downloadSpeed?: number | null
  totalUploadBytes?: number | null
  totalDownloadBytes?: number | null
  totalProcesses?: number | null
  threadCount?: number | null
  systemUptime?: number | null
  osName?: string
  osArch?: string
  hostname?: string
  timestamp?: string
}

interface DashboardResponse<T> { success: boolean; data: T | null }

export interface BusinessBucket { key: string; label: string; count: number }
export interface BusinessDay { date: string; success: number; failed: number; unknown: number }
export interface BusinessActivity {
  total: number
  success: number
  failed: number
  unknown: number
  daily: BusinessDay[]
}
export interface BusinessOverview {
  days: 7 | 30
  startDate: string
  endDate: string
  timeZone: string
  generatedAt: number
  accounts: number
  instances: number
  regions: number
  ocpus: number
  memoryGiB: number
  bootVolumeGiB: number
  knownCpuInstances: number
  knownMemoryInstances: number
  knownVolumeInstances: number
  accountStates: BusinessBucket[]
  instanceStates: BusinessBucket[]
  architectures: BusinessBucket[]
  monitoring: BusinessBucket[]
  regionRanking: BusinessBucket[]
  tenantRanking: BusinessBucket[]
  operations: BusinessActivity
  email: BusinessActivity
  launch: DashboardStats
}

export function fetchBusinessOverview(days: 7 | 30, signal?: AbortSignal) {
  return request.get<unknown, DashboardResponse<BusinessOverview>>('/api/dashboard/business', { params: { days }, silent: true, timeout: 10000, signal })
}

export function fetchDashboardStats(signal?: AbortSignal) {
  return request.get<unknown, DashboardResponse<DashboardStats>>('/boot/dashboard-stats', { silent: true, timeout: 5000, signal })
}

export function fetchMonitorStats(signal?: AbortSignal) {
  return request.get<unknown, DashboardResponse<SystemMetrics>>('/monitor/stats', { silent: true, timeout: 5000, signal })
}
