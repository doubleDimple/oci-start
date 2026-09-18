import type { ComputedRef, InjectionKey } from 'vue'
import type { LocationQuery, LocationQueryRaw, RouteLocationNormalized } from 'vue-router'

export interface MobileRecordsContext {
  enabled: ComputedRef<boolean>
  selected: ComputedRef<string>
  open: (key: string) => void
}

export const mobileRecordsKey: InjectionKey<MobileRecordsContext> = Symbol('mobile-records')

export function mobileRecordParents(query: LocationQuery): string[] {
  const values = query.mobileRecordParents
  return (Array.isArray(values) ? values : [values]).filter((value): value is string => typeof value === 'string' && !!value)
}

export function mobileRecordSelection(query: LocationQuery, listId: string): string {
  const prefix = `${listId}:`
  const values = [...mobileRecordParents(query), query.mobileRecord]
  const value = values.reverse().find(value => typeof value === 'string' && value.startsWith(prefix))
  return typeof value === 'string' ? value.slice(prefix.length) : ''
}

/** Root lists are siblings; only a dialog/drawer adds a record above its page. */
export function mobileRecordOpenQuery(query: LocationQuery, listId: string, key: string, overlayListIds?: string[]): LocationQueryRaw {
  const peers = new Set([listId, ...(overlayListIds || [])])
  const belongsToScope = (record: string) => [...peers].some(id => record.startsWith(`${id}:`))
  const parents = overlayListIds ? mobileRecordParents(query).filter(record => !belongsToScope(record)) : []
  const current = query.mobileRecord
  if (overlayListIds && typeof current === 'string' && current && !belongsToScope(current)) parents.push(current)
  return { ...query, mobileRecord: `${listId}:${key}`, mobileRecordParents: parents.length ? [...new Set(parents)] : undefined }
}

/** Return from this list, removing any descendants as well as its own record. */
export function mobileRecordBackQuery(query: LocationQuery, listId: string): LocationQueryRaw | null {
  const chain = [...mobileRecordParents(query)]
  if (typeof query.mobileRecord === 'string' && query.mobileRecord) chain.push(query.mobileRecord)
  const prefix = `${listId}:`
  let selectedIndex = -1
  chain.forEach((record, index) => { if (record.startsWith(prefix)) selectedIndex = index })
  if (selectedIndex < 0) return null
  const parents = chain.slice(0, selectedIndex)
  const current = parents.pop()
  return { ...query, mobileRecord: current, mobileRecordParents: parents.length ? parents : undefined }
}

/** A disappearing sibling/ancestor must not remove another list's selection. */
export function mobileRecordCloseQuery(query: LocationQuery, listId: string): LocationQueryRaw | null {
  return typeof query.mobileRecord === 'string' && query.mobileRecord.startsWith(`${listId}:`)
    ? mobileRecordBackQuery(query, listId) : null
}

export function mobileRecordBackMethod(current: string, target: string, previous: unknown): 'back' | 'replace' | 'none' {
  if (target === current) return 'none'
  return previous === target ? 'back' : 'replace'
}

/** A record drilldown keeps the business page and its account/filter context. */
export function isMobileRecordNavigation(to: Pick<RouteLocationNormalized, 'path' | 'hash' | 'query'>, from: Pick<RouteLocationNormalized, 'path' | 'hash' | 'query'>) {
  if (to.path !== from.path || to.hash !== from.hash) return false
  const keys = new Set([...Object.keys(to.query), ...Object.keys(from.query)])
  keys.delete('mobileRecord')
  keys.delete('mobileRecordParents')
  return [...keys].every(key => JSON.stringify(to.query[key]) === JSON.stringify(from.query[key]))
}
