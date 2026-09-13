import axios, { type AxiosRequestConfig, type InternalAxiosRequestConfig } from 'axios'
import { ElMessage } from 'element-plus'
import { startProgress, doneProgress } from '@/utils/progress'

declare module 'axios' {
  export interface AxiosRequestConfig {
    silent?: boolean
  }
  export interface InternalAxiosRequestConfig {
    silent?: boolean
  }
}

const REQUEST_TIMEOUT = 10000

function isSuccessCode(code: unknown): boolean {
  if (code === undefined || code === null || code === '') return true
  const value = String(code).trim().toLowerCase()
  return value === '0' || value === '200' || value === 'success' || value === 'ok'
}

function isFailureSuccessValue(success: unknown): boolean {
  if (success === true || success === 1) return false
  if (success === false || success === 0) return true
  const value = String(success).trim().toLowerCase()
  return value !== 'true' && value !== '1' && value !== 'success' && value !== 'ok'
}

function pickMessage(payload: unknown, fallback: string): string {
  if (!payload) return fallback
  if (typeof payload === 'string') return payload || fallback
  const obj = payload as Record<string, unknown>
  return String(obj.message || obj.msg || obj.error || obj.reason || fallback)
}

function payloadFailed(payload: unknown): string | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null
  const obj = payload as Record<string, unknown>
  if (Object.prototype.hasOwnProperty.call(obj, 'success') && isFailureSuccessValue(obj.success)) {
    return pickMessage(obj, '操作未完成，请稍后重试')
  }
  if (Object.prototype.hasOwnProperty.call(obj, 'code') && !isSuccessCode(obj.code)) {
    return pickMessage(obj, '操作未完成，请稍后重试')
  }
  return null
}

const request = axios.create({
  baseURL: '/',
  timeout: REQUEST_TIMEOUT,
  withCredentials: true,
})

function shouldSuppress(cfg?: InternalAxiosRequestConfig | AxiosRequestConfig): boolean {
  return !!cfg && cfg.silent === true
}

request.interceptors.request.use((cfg) => {
  if (!shouldSuppress(cfg)) startProgress()
  cfg.headers.set('X-Requested-With', 'XMLHttpRequest')
  cfg.headers.set('Accept', 'application/json')
  return cfg
})

request.interceptors.response.use(
  (resp) => {
    if (!shouldSuppress(resp.config)) doneProgress()
    const body = resp.data
    if (body && typeof body === 'object' && String((body as { code?: unknown }).code) === '401') {
      window.location.href = '/login'
      return Promise.reject(body)
    }
    const problem = payloadFailed(body)
    if (problem) {
      if (!shouldSuppress(resp.config)) ElMessage.error(problem)
      return Promise.reject(body)
    }
    return body
  },
  (err) => {
    if (!shouldSuppress(err?.config)) doneProgress()
    const status = err?.response?.status
    if (status === 401) {
      window.location.href = '/login'
    } else if (!shouldSuppress(err?.config)) {
      const data = err?.response?.data
      ElMessage.error(pickMessage(data, err.message || '网络异常'))
    }
    return Promise.reject(err)
  },
)

export default request
