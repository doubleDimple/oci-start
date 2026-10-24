import { isAxiosError, isCancel } from 'axios'
import { tenantGet, tenantPost } from './tenant'

export interface VnicRow {
  vnicId: string
  vnicDisplayName: string
  privateIp: string
  publicIp: string
  subnetId: string
  attachmentId: string
  lifecycleState: string
  ipv6Addresses: string[]
  ipv6Ids: string[]
  isPrimary: boolean | null
  instanceId: string
  instanceName: string
}
export interface VnicData {
  rows: VnicRow[]
  /** /refresh omits this field. Keep an existing tenant context in the caller. */
  tenantId: string
  primaryVnicId: string
}
export type VnicAction = 'create' | 'delete' | 'createIpv6' | 'deleteIpv6'
  | 'deleteAllSecondary' | 'changeIp' | 'configureLoadBalancer' | 'restoreNetwork'
export interface VnicActionParams {
  create: { subnetId: string; vnicCount: number; ipv6CountPerVnic: number }
  delete: { vnicId: string }
  createIpv6: { vnicId: string; ipv6Count: number }
  deleteIpv6: { vnicId: string; ipv6Address: string }
  deleteAllSecondary: Record<string, never>
  changeIp: { vnicId: string; cidrRanges: string[] }
  configureLoadBalancer: Record<string, never>
  restoreNetwork: Record<string, never>
}
export interface VnicCreationDetail extends VnicRow {
  success: boolean
  errorMessage: string
  createdAt: string | number | null
}
export interface VnicIpv6Detail {
  ipv6Id: string
  ipv6Address: string
  vnicId: string
  success: boolean
  errorMessage: string
  createdAt: string | number | null
}
export interface VnicBatchDetails {
  kind: 'create'
  instanceId: string
  instanceDisplayName: string
  requestedVnicCount: number
  requestedIpv6CountPerVnic: number
  successfulVnicCount: number
  totalIpv6Count: number
  vnicResults: VnicCreationDetail[]
  allSuccessful: boolean
  summary: string
  createdAt: string | number | null
  totalExecutionTimeMs: number | null
}
export interface VnicNetworkDetails {
  kind: 'configureLoadBalancer'
  natGatewayId: string
  natGatewayName: string
  routeTableId: string
  routeTableName: string
  networkLoadBalancerId: string
  networkLoadBalancerName: string
  nlpIpAddress: string
}
export type VnicMutationDetails = VnicBatchDetails | VnicNetworkDetails
  | { kind: 'createIpv6'; results: VnicIpv6Detail[] }
  | { kind: 'deleteAllSecondary'; results: { vnicId: string; success: boolean }[] }
  | { kind: 'changeIp'; oldIp: string; newIp: string }
export interface VnicMutationResult {
  /** The original business flag, which does not prove every requested substep succeeded. */
  success: boolean
  message: string
  outcome: 'completed' | 'accepted' | 'partial' | 'failed'
  details: VnicMutationDetails | null
}

export type VnicErrorKey = 'invalidInput' | 'invalidResponse' | 'requestFailed'
  | 'timeout' | 'cancelled' | 'unauthorized' | 'forbidden' | 'invalidContext'
/** Retain display information, never the Axios request or its raw response. */
export class VnicApiError extends Error {
  constructor(public key: VnicErrorKey, public detail = '', public writeAttempted = false) {
    super(key)
    this.name = 'VnicApiError'
  }
}

const paths: Record<VnicAction, string> = {
  create: '/oci/vnic/create', delete: '/oci/vnic/delete',
  createIpv6: '/oci/vnic/createIpv6', deleteIpv6: '/oci/vnic/deleteIpv6',
  deleteAllSecondary: '/oci/vnic/deleteAllSecondary', changeIp: '/oci/vnic/changeSpecIp',
  configureLoadBalancer: '/oci/vnic/network/configureLoadBalancer',
  restoreNetwork: '/oci/vnic/network/restoreNetwork',
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function invalidResponse(): never { throw new VnicApiError('invalidResponse') }
function resourceId(value: unknown, resource: string): value is string {
  const prefix = `ocid1.${resource}.`
  return typeof value === 'string' && value.startsWith(prefix) && value.length > prefix.length
    && !/[\s\x00-\x1f\x7f]/.test(value)
}
/** This route and every VNIC operation require the OCI OCID, not InstanceDetails.id. */
export function isVnicInstanceId(value: unknown): value is string { return resourceId(value, 'instance') }
function localId(value: unknown): value is string {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value) && value.trim() === value
    && (value.length < 19 || value <= '9223372036854775807')
}
function text(value: unknown): string {
  if (value == null) return ''
  if (typeof value !== 'string') return invalidResponse()
  return value
}
function strings(value: unknown): string[] {
  if (value == null) return []
  if (!Array.isArray(value) || value.some(item => typeof item !== 'string')) return invalidResponse()
  return value.slice() as string[]
}
function bool(value: unknown): boolean {
  if (typeof value !== 'boolean') return invalidResponse()
  return value
}
function count(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) return invalidResponse()
  return value
}
function duration(value: unknown): number | null {
  if (value == null) return null
  if (typeof value === 'string' && /^\d+$/.test(value)) {
    const number = Number(value)
    return Number.isSafeInteger(number) && number >= 0 ? number : null
  }
  return count(value)
}
function timestamp(value: unknown): string | number | null {
  if (value == null) return null
  if (typeof value === 'string' || (typeof value === 'number' && Number.isFinite(value))) return value
  return invalidResponse()
}
// Preserve integer tokens that cannot safely pass through JavaScript's JSON numbers.
function decode(raw: unknown): unknown {
  if (typeof raw !== 'string') return raw
  try {
    return JSON.parse(raw.replace(/"(?:\\.|[^"\\])*"|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, (token: string, number?: string) => {
      return number && /^-?\d{16,}$/.test(number) ? JSON.stringify(number) : token
    }))
  } catch { return raw }
}
function decodeIpMutation(raw: unknown): unknown {
  const body = decode(raw)
  // Adapt this endpoint's status envelope before the shared interceptor runs.
  // Otherwise tenantPost turns an HTTP 200 status:error into a plain Error and
  // discards its structured details. Retain status, message and all details.
  return object(body) && body.status === 'error' ? { ...body, success: false } : body
}

function row(value: unknown): VnicRow {
  if (!object(value)) return invalidResponse()
  if (value.isPrimary != null && typeof value.isPrimary !== 'boolean') return invalidResponse()
  return {
    vnicId: text(value.vnicId), vnicDisplayName: text(value.vnicDisplayName),
    privateIp: text(value.privateIp), publicIp: text(value.publicIp), subnetId: text(value.subnetId),
    attachmentId: text(value.attachmentId), lifecycleState: text(value.lifecycleState),
    ipv6Addresses: strings(value.ipv6Addresses), ipv6Ids: strings(value.ipv6Ids),
    isPrimary: value.isPrimary == null ? null : value.isPrimary as boolean,
    instanceId: text(value.instanceId), instanceName: text(value.instanceName),
  }
}

/** Both endpoints read OCI; /refresh has no extra synchronization or task receipt. */
export async function getVnicData(
  instanceId: string, mode: 'loadData' | 'refresh' = 'loadData', signal?: AbortSignal,
): Promise<VnicData> {
  if (!isVnicInstanceId(instanceId) || !['loadData', 'refresh'].includes(mode)) throw new VnicApiError('invalidInput')
  try {
    const body = await tenantGet<unknown>(`/oci/vnic/${mode}`, { instanceId }, {
      signal, timeout: 60000, transformResponse: [decode],
    })
    if (!object(body) || body.success !== true || !object(body.data)) return invalidResponse()
    const data = body.data
    if (!Array.isArray(data.vnicList)) return invalidResponse()
    const rows = data.vnicList.map(row)
    if (rows.some(item => !resourceId(item.vnicId, 'vnic')
      || (item.instanceId !== '' && item.instanceId !== instanceId))
      || new Set(rows.map(item => item.vnicId)).size !== rows.length) return invalidResponse()
    const tenantId = text(data.tenantId)
    if ((mode === 'loadData' && !localId(tenantId)) || (tenantId !== '' && !localId(tenantId))) return invalidResponse()
    const primaryRows = rows.filter(item => item.isPrimary === true)
    if (primaryRows.length > 1) return invalidResponse()
    const primaryVnicId = primaryRows[0]?.vnicId || ''
    if (data.primaryVnic != null) {
      if (!object(data.primaryVnic) || data.primaryVnic.vnicId !== primaryVnicId) return invalidResponse()
    } else if (primaryVnicId) return invalidResponse()
    return { rows, tenantId, primaryVnicId }
  } catch (cause) { throw vnicError(cause) }
}

function integerInput(value: unknown, min: number, max: number): boolean {
  return typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max
}
function ipv4Cidr(value: string): boolean {
  if (value.trim() !== value) return false
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d{1,2})$/.exec(value)
  return !!match && match.slice(1, 5).every(octet => Number(octet) <= 255) && Number(match[5]) <= 32
}
function ipv6(value: unknown): value is string {
  if (typeof value !== 'string' || !value.includes(':') || !/^[0-9a-fA-F:.]+$/.test(value)
    || value.trim() !== value) return false
  try { return new URL(`http://[${value}]/`).hostname.length > 0 } catch { return false }
}
function mutationInput(action: VnicAction, instanceId: string, params: unknown): Record<string, unknown> {
  if (!isVnicInstanceId(instanceId) || !object(params)
    || !Object.prototype.hasOwnProperty.call(paths, action)) throw new VnicApiError('invalidInput')
  const input: Record<string, unknown> = { instanceId }
  if (action === 'create') {
    // The legacy UI permits 31 additional VNICs; actual shape quotas remain server-side.
    if (!resourceId(params.subnetId, 'subnet') || !integerInput(params.vnicCount, 1, 31)
      || !integerInput(params.ipv6CountPerVnic, 0, 32)) throw new VnicApiError('invalidInput')
    return { ...input, subnetId: params.subnetId, vnicCount: params.vnicCount, ipv6CountPerVnic: params.ipv6CountPerVnic }
  }
  if (['delete', 'createIpv6', 'deleteIpv6', 'changeIp'].includes(action)) {
    if (!resourceId(params.vnicId, 'vnic')) throw new VnicApiError('invalidInput')
    input.vnicId = params.vnicId
  }
  if (action === 'createIpv6') {
    if (!integerInput(params.ipv6Count, 1, 32)) throw new VnicApiError('invalidInput')
    input.ipv6Count = params.ipv6Count
  }
  if (action === 'deleteIpv6') {
    if (!ipv6(params.ipv6Address)) throw new VnicApiError('invalidInput')
    input.ipv6Address = params.ipv6Address
  }
  if (action === 'changeIp') {
    if (!Array.isArray(params.cidrRanges) || params.cidrRanges.some(item => typeof item !== 'string')) {
      throw new VnicApiError('invalidInput')
    }
    const cidrRanges = (params.cidrRanges as string[]).map(item => item.trim()).filter(Boolean)
    if (!cidrRanges.every(ipv4Cidr)) throw new VnicApiError('invalidInput')
    input.cidrRanges = cidrRanges
    input.preferredIp = null
  }
  return input
}

function parseDetails(action: VnicAction, value: unknown, instanceId: string): VnicMutationDetails | null {
  if (value == null) return null
  if (action === 'createIpv6') {
    if (!Array.isArray(value)) return invalidResponse()
    return { kind: action, results: value.map(item => {
      if (!object(item)) return invalidResponse()
      return {
        ipv6Id: text(item.ipv6Id), ipv6Address: text(item.ipv6Address), vnicId: text(item.vnicId),
        success: bool(item.success), errorMessage: text(item.errorMessage), createdAt: timestamp(item.createdAt),
      }
    }) }
  }
  if (!object(value)) return invalidResponse()
  if (action === 'create') {
    if (!Array.isArray(value.vnicResults)) return invalidResponse()
    const returnedInstanceId = text(value.instanceId)
    if (returnedInstanceId !== '' && returnedInstanceId !== instanceId) return invalidResponse()
    return {
      kind: action, instanceId: returnedInstanceId, instanceDisplayName: text(value.instanceDisplayName),
      requestedVnicCount: count(value.requestedVnicCount), requestedIpv6CountPerVnic: count(value.requestedIpv6CountPerVnic),
      successfulVnicCount: count(value.successfulVnicCount), totalIpv6Count: count(value.totalIpv6Count),
      vnicResults: value.vnicResults.map(item => {
        if (!object(item)) return invalidResponse()
        return { ...row(item), success: bool(item.success), errorMessage: text(item.errorMessage), createdAt: timestamp(item.createdAt) }
      }),
      allSuccessful: bool(value.allSuccessful), summary: text(value.summary),
      createdAt: timestamp(value.createdAt), totalExecutionTimeMs: duration(value.totalExecutionTimeMs),
    }
  }
  if (action === 'deleteAllSecondary') {
    return { kind: action, results: Object.entries(value).map(([vnicId, success]) => {
      if (!resourceId(vnicId, 'vnic')) return invalidResponse()
      return { vnicId, success: bool(success) }
    }) }
  }
  if (action === 'changeIp') return { kind: action, oldIp: text(value.oldIp), newIp: text(value.newIp) }
  if (action === 'configureLoadBalancer') {
    return {
      kind: action, natGatewayId: text(value.natGatewayId), natGatewayName: text(value.natGatewayName),
      routeTableId: text(value.routeTableId), routeTableName: text(value.routeTableName),
      networkLoadBalancerId: text(value.networkLoadBalancerId), networkLoadBalancerName: text(value.networkLoadBalancerName),
      nlpIpAddress: text(value.nlpIpAddress),
    }
  }
  // These legacy operations have no details schema. Do not invent a result from an unexpected payload.
  return invalidResponse()
}

function businessResponse(action: VnicAction, value: unknown): value is Record<string, unknown> {
  return object(value) && (action === 'changeIp'
    ? value.status === 'success' || value.status === 'error'
    : typeof value.success === 'boolean')
}
function mutationResult(action: VnicAction, body: unknown, input: Record<string, unknown>): VnicMutationResult {
  if (!businessResponse(action, body)) return invalidResponse()
  const success = action === 'changeIp' ? body.status === 'success' : body.success === true
  const details = parseDetails(action, body.details, input.instanceId as string)
  if (success && ['create', 'createIpv6', 'deleteAllSecondary', 'changeIp', 'configureLoadBalancer'].includes(action)
    && details === null) return invalidResponse()
  if (details?.kind === 'createIpv6'
    && details.results.some(item => item.vnicId !== '' && item.vnicId !== input.vnicId)) return invalidResponse()
  let outcome: VnicMutationResult['outcome'] = success ? 'completed' : 'failed'
  if (details?.kind === 'create') {
    const wantedVnics = input.vnicCount as number
    const wantedIpv6 = wantedVnics * (input.ipv6CountPerVnic as number)
    const successfulRows = details.vnicResults.filter(item => item.success)
    const returnedIpv6 = successfulRows.reduce((total, item) => total + item.ipv6Addresses.length, 0)
    if (success && (!details.allSuccessful || details.successfulVnicCount !== wantedVnics
      || successfulRows.length !== wantedVnics || details.totalIpv6Count !== wantedIpv6
      || returnedIpv6 !== wantedIpv6)) outcome = 'partial'
    else if (!success && (details.successfulVnicCount > 0 || successfulRows.length > 0)) outcome = 'partial'
  } else if (details?.kind === 'createIpv6') {
    const successful = details.results.filter(item => item.success).length
    if ((success && successful !== input.ipv6Count) || (!success && successful > 0)) outcome = 'partial'
  } else if (details?.kind === 'deleteAllSecondary') {
    if (!success && details.results.some(item => item.success)) outcome = 'partial'
  } else if (details?.kind === 'configureLoadBalancer' && success) {
    if (!details.natGatewayId || !details.routeTableId || !details.networkLoadBalancerId) outcome = 'partial'
  }
  return { success, message: text(body.message), outcome, details }
}

/**
 * Every current operation returns a synchronous HTTP business result; none has
 * a job receipt. Completed means the controller returned, not verified guest
 * connectivity or completion of an OCI RESET (createIpv6 triggers that RESET).
 * A business failure can follow cloud changes. Preserve its details and never
 * automatically retry or abort any write, including the long CIDR search.
 */
export async function runVnicAction<A extends VnicAction>(
  action: A, instanceId: string, params: VnicActionParams[A],
): Promise<VnicMutationResult> {
  const input = mutationInput(action, instanceId, params)
  try {
    let body: unknown
    try {
      body = await tenantPost<unknown>(paths[action], input, {
        timeout: 0, transformResponse: [action === 'changeIp' ? decodeIpMutation : decode],
      })
    } catch (cause) {
      const httpError = isAxiosError(cause)
      const payload: unknown = httpError ? cause.response?.data : cause
      const status = httpError ? cause.response?.status : undefined
      const code = object(payload) ? String(payload.code ?? '') : ''
      // request.ts rejects success:false even for HTTP 200. Recover that real
      // business receipt, including partial details returned with HTTP 400/500.
      if (status === 401 || status === 403 || code === '401' || code === '403'
        || !businessResponse(action, payload)) throw cause
      body = payload
    }
    return mutationResult(action, body, input)
  } catch (cause) {
    const error = vnicError(cause)
    throw new VnicApiError(error.key, error.detail, true)
  }
}

function originalDetail(value: unknown): string {
  if (object(value)) {
    for (const key of ['message', 'msg', 'error', 'reason']) {
      if (typeof value[key] === 'string' && value[key].trim()) return value[key]
    }
  }
  // Keep actual error text intact, but do not surface a proxy/login HTML document.
  return typeof value === 'string' && !/^\s*</.test(value) ? value : ''
}
export function vnicError(cause: unknown): VnicApiError {
  if (cause instanceof VnicApiError) return cause
  if (isCancel(cause) || (object(cause) && cause.name === 'AbortError')) return new VnicApiError('cancelled')
  const httpError = isAxiosError(cause)
  const body: unknown = httpError ? cause.response?.data : cause
  const status = httpError ? cause.response?.status : undefined
  const code = object(body) ? String(body.code ?? '') : ''
  const detail = originalDetail(body)
  if (status === 401 || code === '401') return new VnicApiError('unauthorized', detail)
  if (status === 403 || code === '403') return new VnicApiError('forbidden', detail)
  const timeout = httpError && ['ETIMEDOUT', 'ECONNABORTED'].includes(cause.code || '')
  return new VnicApiError(timeout ? 'timeout' : 'requestFailed', detail)
}
export function isVnicWriteUncertain(cause: unknown): boolean { return vnicError(cause).writeAttempted }
