import { isAxiosError, isCancel } from 'axios'
import { readonly, shallowRef } from 'vue'
import request from './request'

export interface HeaderVersionInfo {
  currentVersion: string | null
  latestVersion: string | null
  deployType: string | null
  needUpdate: boolean
}

export type HeaderVersionErrorKey = 'invalidResponse' | 'requestFailed' | 'networkError' | 'timeoutError'
export interface HeaderVersionProblem {
  key: HeaderVersionErrorKey
  detail: string
}

export type HeaderUpdateState = 'idle' | 'starting' | 'started' | 'unknown' | 'failed'

const versionSnapshot = shallowRef<HeaderVersionInfo | null>(null)
const updateState = shallowRef<HeaderUpdateState>('idle')
const updateProblem = shallowRef<HeaderVersionProblem | null>(null)
export const headerVersionSnapshot = readonly(versionSnapshot)
export const headerVersionUpdateState = readonly(updateState)
export const headerVersionUpdateProblem = readonly(updateProblem)
let snapshotRevision = 0
let latestCacheRequest = 0
let entryRefresh: Promise<void> | undefined

class HeaderVersionResponseError extends Error {
  constructor() {
    super('invalidResponse')
    this.name = 'HeaderVersionResponseError'
  }
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function nullableText(value: unknown): value is string | null {
  return value === null || typeof value === 'string'
}

function parseVersion(body: unknown): HeaderVersionInfo {
  if (!record(body) || typeof body.needUpdate !== 'boolean'
    || !nullableText(body.currentVersion) || !nullableText(body.latestVersion)
    || !nullableText(body.deployType)) {
    throw new HeaderVersionResponseError()
  }
  return {
    currentVersion: body.currentVersion,
    latestVersion: body.latestVersion,
    deployType: body.deployType,
    needUpdate: body.needUpdate,
  }
}

/** Accept a remote check result; this function never sends a request. */
export function acceptRemoteVersionSnapshot(body: unknown): boolean {
  try {
    const result = parseVersion(body)
    ++snapshotRevision
    versionSnapshot.value = result
    return true
  } catch {
    return false
  }
}

/** Check once on console entry, without delaying navigation or retrying failures. */
export function refreshHeaderVersionOnEntry(): Promise<void> {
  if (!entryRefresh) {
    // Retain the settled promise too: remounting the layout in this document
    // must not repeat the remote check, even after an unsuccessful response.
    entryRefresh = request.get<unknown, unknown>('/api/version/check', {
      params: { refresh: true }, silent: true,
    }).then(body => {
      // Cache reads may finish while this request is pending. The remote result
      // still takes precedence and invalidates any older in-flight cache read.
      acceptRemoteVersionSnapshot(body)
    }).catch(() => undefined)
  }
  return entryRefresh
}

/** Header and About only read the stored result; console entry refreshes it remotely. */
export async function fetchHeaderVersion(signal?: AbortSignal): Promise<HeaderVersionInfo> {
  const revision = snapshotRevision
  const cacheRequest = ++latestCacheRequest
  const body = await request.get<unknown, unknown>('/api/version/check', { signal, silent: true })
  const result = parseVersion(body)
  if (revision === snapshotRevision && cacheRequest === latestCacheRequest) {
    ++snapshotRevision
    versionSnapshot.value = result
  }
  // An older cache response cannot overwrite a completed remote check.
  return versionSnapshot.value ?? result
}

/** The server can restart before replying. Never retry this request automatically. */
export async function executeHeaderUpdate(signal?: AbortSignal): Promise<void> {
  if (updateState.value === 'starting' || updateState.value === 'started' || updateState.value === 'unknown') return
  updateState.value = 'starting'
  updateProblem.value = null
  try {
    const body = await request.post<unknown, unknown>('/api/version/execute-update', undefined, {
      signal, silent: true, timeout: 30000,
    })
    if (!record(body) || body.success !== true) throw new HeaderVersionResponseError()
    updateState.value = 'started'
  } catch (error) {
    updateProblem.value = headerVersionProblem(error)
    updateState.value = headerUpdateUncertain(error) ? 'unknown' : 'failed'
    throw error
  }
}

export function headerVersionProblem(error: unknown): HeaderVersionProblem {
  if (error instanceof HeaderVersionResponseError) return { key: 'invalidResponse', detail: '' }
  if (isAxiosError(error)) {
    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') return { key: 'timeoutError', detail: '' }
    if (!error.response) return { key: 'networkError', detail: '' }
  }
  const body: unknown = isAxiosError(error) ? error.response?.data : error
  const detail = record(body) && typeof body.message === 'string' ? body.message.trim() : ''
  return { key: 'requestFailed', detail }
}

export function headerUpdateUncertain(error: unknown): boolean {
  if (error instanceof HeaderVersionResponseError || isCancel(error)) return true
  if (isAxiosError(error)) {
    const status = error.response?.status
    return !status || status === 408 || status >= 500
  }
  // An explicit business rejection is a known failure; other incomplete results are uncertain.
  return !record(error) || error.success !== false
}
