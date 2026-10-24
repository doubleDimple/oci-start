/** Preserve server wall-clock timestamps when the API supplies no time zone. */
export function formatEmailTime(value: string, locale: string): string {
  if (!value) return '—'
  const local = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/.exec(value)
  if (local) {
    const [, year, month, day, hour, minute] = local
    const date = new Date(`${year}-${month}-${day}T${hour}:${minute}:00Z`)
    if (!Number.isNaN(date.getTime())) return new Intl.DateTimeFormat(locale === 'en' ? 'en-US' : 'zh-CN', {
      year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC',
    }).format(date)
  }
  if (!/Z$|[+-]\d{2}:?\d{2}$/.test(value)) return value
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat(locale === 'en' ? 'en-US' : 'zh-CN', {
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).format(date)
}

export function formatEmailCount(value: number | null, locale: string): string {
  if (value === null || !Number.isSafeInteger(value) || value < 0) return '—'
  return new Intl.NumberFormat(locale === 'en' ? 'en-US' : 'zh-CN').format(value)
}
