import { ElMessageBox } from 'element-plus'
import { i18n } from '@/i18n'
import { tenantPost } from '@/api/tenant'
import { ExportVerificationError, exportErrorMessage, isExportCode, normalizeExportCode } from '@/api/exportVerification'

/** Sending is explicit; the returned code is checked only by the subsequent real export request. */
export async function requestExportVerification(signal?: AbortSignal): Promise<string | null> {
  const t = i18n.global.t
  if (signal?.aborted) return null
  try { await tenantPost('/tenants/verify/sendExportCode', undefined, { silent: true, signal }) }
  catch (cause) {
    if (signal?.aborted) return null
    throw new ExportVerificationError(await exportErrorMessage(cause) || t('tenantOperations.errors.sendCode'))
  }
  if (signal?.aborted) return null
  const abort = () => ElMessageBox.close()
  signal?.addEventListener('abort', abort, { once: true })
  try {
    const result = await ElMessageBox.prompt(
      `${t('tenantOperations.export.codeHint')} ${t('tenantOperations.export.codeLimit')}`,
      t('tenantOperations.export.codeLabel'), {
        inputType: 'text', inputPlaceholder: t('tenantOperations.export.codePlaceholder'),
        inputValidator: value => isExportCode(value || '') || t('tenantOperations.export.codePlaceholder'),
        confirmButtonText: t('tenantOperations.actions.verifyDownload'), cancelButtonText: t('tenantOperations.actions.cancel'),
        closeOnClickModal: false, distinguishCancelAndClose: true,
      },
    )
    return signal?.aborted ? null : normalizeExportCode(result.value)
  } catch (cause) {
    if (cause === 'cancel' || cause === 'close' || signal?.aborted) return null
    throw cause
  } finally { signal?.removeEventListener('abort', abort) }
}
