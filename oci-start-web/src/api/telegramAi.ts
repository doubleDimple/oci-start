import {
  addAiModelConfig, aiModelsError, deleteAiModelConfig, listAiModelConfigs, listAiModelTenants,
  listAvailableAiModels, setAiModelConfigEnabled,
  type AiModelConfig, type AiModelConfigInput, type AiModelTenant, type AiModelsErrorKey, type AvailableAiModel,
} from './aiModels'

export type TelegramAiTenant = AiModelTenant
export type TelegramAiModel = AvailableAiModel
export type TelegramAiConfig = AiModelConfig
export type TelegramAiConfigInput = AiModelConfigInput
export type TelegramAiErrorKey = AiModelsErrorKey | 'saveMismatch'

/** This notification flow keeps neither raw errors nor private AI configuration DTOs. */
export class TelegramAiApiError extends Error {
  constructor(public key: TelegramAiErrorKey, public writeAttempted = false) {
    super(key)
    this.name = 'TelegramAiApiError'
  }
}
export function telegramAiError(cause: unknown): TelegramAiApiError {
  if (cause instanceof TelegramAiApiError) return new TelegramAiApiError(cause.key, cause.writeAttempted)
  const error = aiModelsError(cause)
  return new TelegramAiApiError(error.key, error.writeAttempted)
}
async function sanitized<T>(operation: () => Promise<T>): Promise<T> {
  try { return await operation() } catch (cause) { throw telegramAiError(cause) }
}

export function listTelegramAiTenants(signal?: AbortSignal): Promise<TelegramAiTenant[]> {
  return sanitized(() => listAiModelTenants(signal))
}
export function listTelegramAiModels(tenantId: string, signal?: AbortSignal): Promise<TelegramAiModel[]> {
  return sanitized(() => listAvailableAiModels(tenantId, signal))
}
export function listTelegramAiConfigs(signal?: AbortSignal): Promise<TelegramAiConfig[]> {
  return sanitized(() => listAiModelConfigs(signal))
}
export function addTelegramAiConfig(input: TelegramAiConfigInput): Promise<TelegramAiConfig> {
  return sanitized(() => addAiModelConfig(input))
}
export function setTelegramAiEnabled(id: string, enabled: boolean): Promise<TelegramAiConfig> {
  // Reuse the existing private snapshot preservation for advanced fields. Sending
  // only { id, enabled } to the legacy save endpoint would clear those fields.
  return sanitized(() => setAiModelConfigEnabled(id, enabled))
}
export function deleteTelegramAiConfig(id: string): Promise<void> {
  return sanitized(() => deleteAiModelConfig(id))
}
