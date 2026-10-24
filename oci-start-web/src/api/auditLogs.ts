import request from './request'

export interface AuditLogRow {
  id: number
  username: string
  title: string
  method: string
  requestUri: string
  actionMethod: string
  ip: string
  location: string
  params: string
  responseStatus: number
  status: number
  errorMsg: string | null
  costTime: number
  userAgent: string | null
  createTime: string
}

export interface AuditLogQueryParams {
  page?: number
  size?: number
  username?: string
  method?: string
  status?: number | ''
  keyword?: string
  startDate?: string
  endDate?: string
}

export interface AuditLogPageResult {
  content: AuditLogRow[]
  totalElements: number
  totalPages: number
  page: number
  size: number
}

export interface AuditLogApiResponse<T> {
  success: boolean
  code: number
  message?: string
  data: T
}

export function fetchAuditLogs(params: AuditLogQueryParams) {
  return request.get<unknown, AuditLogApiResponse<AuditLogPageResult>>('/api/audit-logs', { params })
}

export function deleteAuditLog(id: number) {
  return request.delete<unknown, AuditLogApiResponse<null>>(`/api/audit-logs/${id}`)
}

export function batchDeleteAuditLogs(ids: number[]) {
  return request.post<unknown, AuditLogApiResponse<null>>('/api/audit-logs/batch-delete', { ids })
}

export function clearAllAuditLogs() {
  return request.delete<unknown, AuditLogApiResponse<null>>('/api/audit-logs/clear')
}
