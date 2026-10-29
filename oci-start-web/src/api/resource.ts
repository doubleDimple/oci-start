import request from './request'
import type { AxiosRequestConfig } from 'axios'

export function fetchMyRegions(config: AxiosRequestConfig = {}) {
  return request.get('/resource/my-regions', { silent: true, ...config })
}
