import { isAxiosError } from 'axios'
import { i18n } from '@/i18n'
import { tenantGet, tenantPost } from './tenant'

export type BootArchitecture = 'ARM' | 'AMD' | 'ARM_PAID_A2' | 'AMD_PAID_E3' | 'AMD_PAID_E4' | 'AMD_PAID_E5'

export interface BootRegion {
  id: string
  region: string
  userName: string
  tenancyName: string
  isHomeRegion: boolean
}

export interface BootImage {
  imageId: string
  operatingSystem: string
  operatingSystemVersion: string
}

export interface BootTaskInput {
  tenantId: string
  ocpu: number
  memory: number
  disk: number
  architecture: BootArchitecture
  rootPassword: string
  loopTime: number
  instanceCount: number
  operatingSystem: string
  operatingSystemVersion: string
  imageId: string
  dayGap: string
}

type ErrorKey =
  | 'ociBoot.invalidResponse'
  | 'ociBoot.requestFailed'
  | 'ociBoot.invalidTenant'
  | 'ociBoot.passwordUnavailable'

class BootValidationError extends Error {
  constructor(readonly translationKey: ErrorKey) {
    // Keep local errors independent of the current locale and credential values.
    super(translationKey)
    this.name = 'BootValidationError'
  }
}

const MAX_TENANT_ID = '9223372036854775807'
const MAX_JAVA_INT = 2147483647
const ARCHITECTURES: readonly BootArchitecture[] = ['ARM', 'AMD', 'ARM_PAID_A2', 'AMD_PAID_E3', 'AMD_PAID_E4', 'AMD_PAID_E5']

export function isBootTenantId(value: unknown): value is string {
  // Never convert a Snowflake/Long identifier to a JavaScript number.
  return typeof value === 'string'
    && /^[1-9][0-9]{0,18}$/.test(value)
    && (value.length < MAX_TENANT_ID.length || value <= MAX_TENANT_ID)
}

function requireTenantId(value: unknown): asserts value is string {
  if (!isBootTenantId(value)) throw new BootValidationError('ociBoot.invalidTenant')
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function isArchitecture(value: unknown): value is BootArchitecture {
  return typeof value === 'string' && ARCHITECTURES.includes(value as BootArchitecture)
}

function nullableName(value: unknown): string {
  if (value === null || value === undefined) return ''
  if (typeof value !== 'string') throw new BootValidationError('ociBoot.invalidResponse')
  return value
}

function successfulBody(value: unknown): Record<string, unknown> {
  if (!isObject(value) || value.success !== true) {
    // The shared interceptor rejects success:false as the original backend payload.
    if (isObject(value) && nonEmpty(value.error)) throw new Error(value.error)
    throw new BootValidationError('ociBoot.invalidResponse')
  }
  return value
}

export async function getBootRegions(parentId: string, signal?: AbortSignal): Promise<BootRegion[]> {
  requireTenantId(parentId)
  const body = await tenantGet<unknown>('/tenants/listRegions', { parentId }, { signal })
  if (!Array.isArray(body)) throw new BootValidationError('ociBoot.invalidResponse')
  const result: BootRegion[] = []
  const seen = new Set<string>()
  for (const value of body) {
    if (
      !isObject(value)
      || !isBootTenantId(value.id)
      || !nonEmpty(value.region)
      || (value.isHomeRegion !== null && value.isHomeRegion !== undefined && typeof value.isHomeRegion !== 'boolean')
    ) {
      throw new BootValidationError('ociBoot.invalidResponse')
    }
    const region: BootRegion = {
      id: value.id,
      region: value.region,
      userName: nullableName(value.userName),
      tenancyName: nullableName(value.tenancyName),
      isHomeRegion: value.isHomeRegion === true,
    }
    // Validate every record before deduplicating; keep the first occurrence and its order.
    if (!seen.has(region.id)) {
      seen.add(region.id)
      result.push(region)
    }
  }
  return result
}

export async function getBootImages(
  tenantId: string,
  shapeType: BootArchitecture,
  signal?: AbortSignal,
): Promise<BootImage[]> {
  requireTenantId(tenantId)
  if (!isArchitecture(shapeType)) throw new BootValidationError('ociBoot.requestFailed')
  const body = successfulBody(await tenantPost<unknown>('/tenants/querySystemImages', { tenantId, shapeType }, { signal }))
  if (!Array.isArray(body.data)) throw new BootValidationError('ociBoot.invalidResponse')
  return body.data.map(value => {
    if (!isObject(value) || !nonEmpty(value.imageId) || !nonEmpty(value.operatingSystem) || !nonEmpty(value.operatingSystemVersion)) {
      throw new BootValidationError('ociBoot.invalidResponse')
    }
    return {
      imageId: value.imageId,
      operatingSystem: value.operatingSystem,
      operatingSystemVersion: value.operatingSystemVersion,
    }
  })
}

function positiveJavaInt(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0 && value <= MAX_JAVA_INT
}

function validDayGap(value: unknown): value is string {
  if (typeof value !== 'string') return false
  if (value === '') return true
  const match = /^(\d{1,2})-(\d{1,2})$/.exec(value)
  if (!match) return false
  const start = Number(match[1])
  const end = Number(match[2])
  return start >= 0 && start <= 23 && end >= 1 && end <= 24 && start < end
}

export async function saveBootTask(input: BootTaskInput, signal?: AbortSignal): Promise<void> {
  requireTenantId(input.tenantId)
  if (
    ![input.ocpu, input.memory, input.disk, input.loopTime].every(positiveJavaInt)
    || !positiveJavaInt(input.instanceCount)
    || input.instanceCount > 100
    || !isArchitecture(input.architecture)
    || !nonEmpty(input.rootPassword)
    || typeof input.operatingSystem !== 'string'
    || typeof input.operatingSystemVersion !== 'string'
    || typeof input.imageId !== 'string'
    || !validDayGap(input.dayGap)
  ) {
    throw new BootValidationError('ociBoot.requestFailed')
  }

  const data = new FormData()
  data.append('tenantId', input.tenantId)
  data.append('ocpu', String(input.ocpu))
  data.append('memory', String(input.memory))
  data.append('disk', String(input.disk))
  data.append('architecture', input.architecture)
  data.append('rootPassword', input.rootPassword)
  data.append('loopTime', String(input.loopTime))
  data.append('instanceCount', String(input.instanceCount))
  data.append('operatingSystem', input.operatingSystem)
  data.append('operatingSystemVersion', input.operatingSystemVersion)
  data.append('imageId', input.imageId)
  data.append('dayGap', input.dayGap)
  successfulBody(await tenantPost<unknown>('/tenants/boot/save', data, {
    signal,
    // Cloud network preparation is synchronous. Keep 10s unchanged; the server applies its 12s minimum.
    // Aborting the client request does not cancel server-side preparation or undo an accepted task.
    timeout: 0,
  }))
}

export function generateBootPassword(): string {
  try {
    const secureCrypto = globalThis.crypto
    if (!secureCrypto || typeof secureCrypto.getRandomValues !== 'function') {
      throw new BootValidationError('ociBoot.passwordUnavailable')
    }
    const sample = new Uint32Array(1)
    function randomIndex(length: number): number {
      const limit = Math.floor(0x100000000 / length) * length
      // Rejection sampling avoids the bias from reducing an arbitrary byte modulo 62.
      do { secureCrypto.getRandomValues(sample) } while (sample[0]! >= limit)
      return sample[0]! % length
    }

    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    const lower = 'abcdefghijklmnopqrstuvwxyz'
    const digits = '0123456789'
    const alphabet = upper + lower + digits
    const characters = [upper.charAt(randomIndex(upper.length)), lower.charAt(randomIndex(lower.length)), digits.charAt(randomIndex(digits.length))]
    while (characters.length < 16) characters.push(alphabet.charAt(randomIndex(alphabet.length)))
    for (let index = characters.length - 1; index > 0; index--) {
      const other = randomIndex(index + 1)
      const character = characters[index]!
      characters[index] = characters[other]!
      characters[other] = character
    }
    return characters.join('')
  } catch {
    throw new BootValidationError('ociBoot.passwordUnavailable')
  }
}

function backendMessage(body: unknown): string {
  if (typeof body === 'string') return nonEmpty(body) && !body.trimStart().startsWith('<') ? body : ''
  if (!isObject(body)) return ''
  for (const key of ['error', 'message', 'msg']) {
    const value = body[key]
    if (nonEmpty(value)) return value
  }
  return ''
}

export function bootError(error: unknown): string {
  if (error instanceof BootValidationError) return i18n.global.t(error.translationKey)
  if (isAxiosError(error)) {
    const message = backendMessage(error.response?.data)
    if (message) return message
    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') return i18n.global.t('ociBoot.timeoutError')
    if (error.code === 'ERR_CANCELED') return i18n.global.t('ociBoot.requestFailed')
    if (error.code === 'ERR_NETWORK' || (!error.response && error.request)) return i18n.global.t('ociBoot.networkError')
    return i18n.global.t('ociBoot.requestFailed')
  }
  return backendMessage(error) || i18n.global.t('ociBoot.requestFailed')
}
