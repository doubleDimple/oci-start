import { isAxiosError } from 'axios'
import { tenantGet } from './tenant'

export interface AiChatModel {
  id: string
  displayName: string
  version: string
  vendor: string
  lifecycleState: string
}
export interface AiChatTenant { id: string; name: string; region: string }
export interface AiChatEvent {
  type: string
  status?: string
  role?: string
  message?: string
  isChunk?: boolean
}
export type AiChatRequest =
  | { type: 'init'; tenant: { tenantId: string; modelId: string } }
  | { type: 'chat'; message: string; tenantId: string; modelId: string; useHistory: boolean }
  | { type: 'clear' | 'ping' }
  | { type: 'close_session'; reason: 'user_requested' }

export class AiChatResponseError extends Error {}
function object(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value)
}
function text(value: unknown): string { return typeof value === 'string' ? value : '' }
export function isAiChatTenantId(value: string): boolean {
  return /^[1-9]\d*$/.test(value) && (value.length < 19 || (value.length === 19 && value <= '9223372036854775807'))
}

export async function getAiChatModels(tenantId: string, signal: AbortSignal): Promise<AiChatModel[]> {
  const body = await tenantGet<unknown>('/ai/models', { tenantId }, { signal })
  if (!object(body) || body.success !== true || !Array.isArray(body.models)) throw new AiChatResponseError()
  return body.models.map((value) => {
    if (!object(value) || !text(value.id)) throw new AiChatResponseError()
    return {
      id: text(value.id), displayName: text(value.displayName), version: text(value.version),
      vendor: text(value.vendor), lifecycleState: text(value.lifecycleState),
    }
  })
}

/** Read only the selected account's label; its ID determines the AI region. */
export async function getAiChatTenant(tenantId: string, signal: AbortSignal): Promise<AiChatTenant | null> {
  const body = await tenantGet<unknown>('/tenants/regionList/json', { tenantId }, { signal })
  if (!Array.isArray(body)) throw new AiChatResponseError()
  const row = body.find((value) => object(value) && (value.idStr === tenantId || value.id === tenantId ||
    (typeof value.id === 'number' && Number.isSafeInteger(value.id) && String(value.id) === tenantId)))
  if (!object(row)) return null
  return { id: tenantId, name: text(row.defName) || text(row.tenancyName) || text(row.userName), region: text(row.region) || text(row.regionEn) }
}

export function aiChatServerError(cause: unknown): string {
  if (cause instanceof AiChatResponseError) return ''
  const body = isAxiosError(cause) ? cause.response?.data : cause
  if (object(body)) {
    for (const key of ['message', 'msg', 'error']) if (typeof body[key] === 'string' && body[key]) return body[key]
  }
  return ''
}

export function openAiChatSocket(): WebSocket {
  const url = new URL('/ws/aiChat', window.location.href)
  url.protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return new WebSocket(url)
}

export function sendAiChatRequest(socket: WebSocket, payload: AiChatRequest): void {
  if (socket.readyState !== WebSocket.OPEN) throw new Error('socket_not_open')
  socket.send(JSON.stringify(payload))
}

export function parseAiChatEvent(value: unknown): AiChatEvent {
  if (typeof value !== 'string') throw new AiChatResponseError()
  let body: unknown
  try { body = JSON.parse(value) } catch { throw new AiChatResponseError() }
  if (!object(body) || typeof body.type !== 'string') throw new AiChatResponseError()
  return {
    type: body.type, status: text(body.status), role: text(body.role),
    message: typeof body.message === 'string' ? body.message : undefined,
    isChunk: body.isChunk === true,
  }
}

export function disposeAiChatSocket(socket: WebSocket | undefined): void {
  if (!socket) return
  socket.onopen = null
  socket.onmessage = null
  socket.onerror = null
  socket.onclose = null
  if (socket.readyState === WebSocket.CONNECTING || socket.readyState === WebSocket.OPEN) socket.close(1000, 'Client disconnected')
}
