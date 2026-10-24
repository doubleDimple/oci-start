type AccountRow = Record<string, unknown> | null | undefined
type Translate = (key: string) => string
export interface TenantAccountSummary {
  label: string
  source: 'subscription' | 'stored' | 'regions' | 'unknown'
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}
function text(value: unknown): string {
  if (object(value)) value = value.value ?? value.code
  return typeof value === 'string' ? value.trim() : ''
}
function meaningful(value: unknown): string {
  const raw = text(value)
  const normalized = raw.toUpperCase().replace(/[-_\s]/g, '')
  return ['UNKNOWN', 'UNKNOWNENUMVALUE', 'UNKNOWACCOUNT', 'NULL', '未知', '未知类型', '未知账号/权限不足'].includes(normalized) ? '' : raw
}

/** Parent clones are included in children, so hasChildren alone does not prove multiple regions. */
export function hasMultipleAccountRegions(row: AccountRow): boolean {
  if (!row || !Array.isArray(row.children)) return false
  const ids = new Set<string>()
  const regions = new Set<string>()
  for (const candidate of [row, ...row.children]) {
    if (!object(candidate)) continue
    const id = text(candidate.idStr) || (typeof candidate.id === 'string' || typeof candidate.id === 'number' ? String(candidate.id) : '')
    if (id && ids.has(id)) continue
    if (id) ids.add(id)
    const region = text(candidate.regionEn) || text(candidate.region)
    if (region) regions.add(region.toLowerCase())
  }
  return regions.size > 1
}

/** Prefer subscription data, then saved classification; region facts do not imply a billing plan. */
export function describeTenantAccount(row: AccountRow, t: Translate): TenantAccountSummary {
  const labels: Record<string, string> = {
    PERSONAL: 'personal', CORPORATE: 'corporate', CORPORATESUBMITTED: 'corporateSubmitted',
    FREETIER: 'freeTier', FREE: 'freeTier', PAYG: 'payg', PAID: 'payg', PAYASYOUGO: 'payg',
  }
  const detail = object(row?.registerDetail) ? row.registerDetail : null
  const values = [detail?.accountType, detail?.planType].map(meaningful).filter(Boolean)
  if (values.length) return {
    label: values.map(value => {
      const key = labels[value.toUpperCase().replace(/[-_\s]/g, '')]
      return key ? t(`tenant.account.${key}`) : value
    }).join(' · '), source: 'subscription',
  }
  const legacy = meaningful(row?.accountTypeName)
  if (legacy) {
    if (legacy === '多区域账号' || legacy === '多区号') return { label: t('tenant.account.multiRegion'), source: 'regions' }
    const account: Record<string, string> = { '个人': 'personal', '公司': 'corporate', '正在审核中的企业': 'corporateSubmitted' }
    const plans: Record<string, string> = { '免费账号': 'freeTier', '升级账号': 'payg' }
    for (const first of ['', ...Object.keys(account)]) for (const second of ['', ...Object.keys(plans)]) {
      if (first + second === legacy) return {
        label: [first && account[first], second && plans[second]].filter(Boolean).map(key => t(`tenant.account.${key}`)).join(' · '),
        source: 'subscription',
      }
    }
    return { label: legacy, source: 'stored' }
  }
  const stored: Record<string, string> = {
    FREE_ACCOUNT: 'freeTier', TRIAL_PAID_ACCOUNT: 'trial', UPGRADE_ACCOUNT: 'payg', MANY_REGION_ACCOUNT: 'multiRegion',
  }
  const key = stored[text(row?.accountType).toUpperCase()]
  if (key) return { label: t(`tenant.account.${key}`), source: 'stored' }
  if (hasMultipleAccountRegions(row)) return { label: t('tenant.account.multiRegion'), source: 'regions' }
  return { label: t('tenant.account.unknown'), source: 'unknown' }
}

/** Missing registration age must not be displayed as a known zero-day-old account. */
export function accountActiveDays(value: unknown): number | null {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value.trim()))) return null
  const days = Number(value)
  return Number.isSafeInteger(days) && days >= 0 ? days : null
}
