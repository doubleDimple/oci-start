/** Shared only by sensitive export flows. TOTP and other verification codes are separate. */
export const normalizeExportCode = (value: string): string => value.trim().toUpperCase()
export const isExportCode = (value: string): boolean => /^[A-Z0-9]{8}$/.test(normalizeExportCode(value))
export class ExportVerificationError extends Error {}

/** Display bounded error text only; never turn an HTML page or a file into an error message. */
export function safeExportMessage(value: unknown): string {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const body = value as Record<string, unknown>
    for (const key of ['message', 'msg', 'error']) {
      if (typeof body[key] === 'string') return safeExportMessage(body[key])
    }
    return ''
  }
  if (typeof value !== 'string') return ''
  const text = value.trim()
  if (!text || text.length > 2000 || /[<>\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(text)
    || /-----BEGIN|# OCI 实例导出/.test(text)) return ''
  if (text.startsWith('{') || text.startsWith('[')) {
    try { return safeExportMessage(JSON.parse(text)) } catch { return '' }
  }
  return text
}

export async function exportErrorMessage(cause: unknown): Promise<string> {
  const error = cause as { response?: { data?: unknown }; message?: unknown }
  let body = error?.response?.data ?? cause
  if (body instanceof Blob) {
    if (body.size > 8192 || !/^(text\/plain|application\/json)(;|$)/i.test(body.type)) return ''
    body = await body.text()
  }
  return safeExportMessage(body)
}

/** Error responses are small; stop reading a broken upstream instead of buffering its output. */
export async function readExportResponseError(response: Response): Promise<string> {
  const contentType = response.headers.get('Content-Type') || ''
  if (!/^(text\/plain|application\/json)(;|$)/i.test(contentType) || !response.body) return ''
  const reader = response.body.getReader(), chunks: Uint8Array[] = []
  let size = 0
  try {
    while (true) {
      const next = await reader.read()
      if (next.done) break
      size += next.value.byteLength
      if (size > 8192) { await reader.cancel(); return '' }
      chunks.push(next.value)
    }
    const bytes = new Uint8Array(size)
    let offset = 0
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
    return safeExportMessage(new TextDecoder('utf-8', { fatal: true }).decode(bytes))
  } catch { return '' }
  finally { reader.releaseLock() }
}
