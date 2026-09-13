import { AxiosHeaders, type AxiosRequestConfig } from 'axios'
import request from './request'
import { i18n } from '@/i18n'

export interface TenantRow extends Record<string, any> {
  id: string
  tenancyName?: string
  defName?: string
  cloudType?: number
  active?: boolean
  isActive?: boolean
}

export function tenantCsrfToken(): string {
  return (
    document.querySelector<HTMLInputElement>('input[name="_csrf"]')?.value ||
    document.querySelector<HTMLMetaElement>('meta[name="_csrf"]')?.content ||
    ''
  )
}

async function tenantRequest<T>(config: AxiosRequestConfig): Promise<T> {
  const headers = AxiosHeaders.from(
    config.headers as Parameters<typeof AxiosHeaders.from>[0],
  )
  const token = tenantCsrfToken()
  const csrfHeader =
    document.querySelector<HTMLMetaElement>('meta[name="_csrf_header"]')
      ?.content || 'X-CSRF-TOKEN'
  if (token) headers.set(csrfHeader, token)
  // request's interceptor returns the payload rather than the Axios response.
  const response: unknown = await request.request({
    silent: true,
    timeout: 30000,
    ...config,
    headers,
  })
  const body = response as T
  if (body && typeof body === 'object' && 'status' in body) {
    const value = body as Record<string, unknown>
    if (
      ['error', 'failed', 'failure'].includes(
        String(value.status).toLowerCase(),
      )
    ) {
      throw new Error(
        String(value.message || value.msg || i18n.global.t('tenant.common.requestFailed')),
      )
    }
  }
  return body
}

export function tenantGet<T = any>(
  url: string,
  params?: Record<string, unknown>,
  config: AxiosRequestConfig = {},
) {
  return tenantRequest<T>({ ...config, method: 'GET', url, params })
}

export function tenantPost<T = any>(
  url: string,
  data?: unknown,
  config: AxiosRequestConfig = {},
) {
  return tenantRequest<T>({ ...config, method: 'POST', url, data })
}

export function tenantPut<T = any>(
  url: string,
  data?: unknown,
  config: AxiosRequestConfig = {},
) {
  return tenantRequest<T>({ ...config, method: 'PUT', url, data })
}

export function tenantError(error: unknown): string {
  const value = error as {
    message?: string
    msg?: string
    response?: { data?: { message?: string } }
  }
  return (
    value?.response?.data?.message ||
    value?.message ||
    value?.msg ||
    i18n.global.t('tenant.common.requestFailed')
  )
}
