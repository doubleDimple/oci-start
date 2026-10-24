import request from './request'
import type { AxiosRequestConfig } from 'axios'

export function fetchArmData(config: AxiosRequestConfig = {}) {
  return request.get('/resource/arm-data', { silent: true, ...config })
}

export function fetchMyRegions(config: AxiosRequestConfig = {}) {
  return request.get('/resource/my-regions', { silent: true, ...config })
}
