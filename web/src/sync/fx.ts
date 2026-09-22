import { KEYS, lsGet, lsSet } from '../app/db'
import type { Day } from '../core/date'
import { DEFAULT_SERVER_URL } from './config'

/**
 * Exchange rates for a receipt in another currency. The sync server answers
 * `/api/fx` from the European Central Bank's daily reference rates and keeps
 * each day's figure, so every device that asks for the same day gets the same
 * rate. The rate is written into the entry at the moment of recording; a total
 * never looks a rate up again, and never moves when the market does.
 *
 * Nothing here is required: with no network the last rate used for the pair is
 * offered, and the field stays editable either way. A person who knows the
 * rate their broker applied should type that one.
 */

/** The currencies the keypad offers; the ledger's own currency is listed first by the caller. */
export const CURRENCIES = ['CNY', 'USD', 'HKD', 'EUR', 'GBP', 'JPY'] as const

export interface Rate {
  rateMicro: number
  /** The day the rate was published for — earlier than asked on a weekend. */
  asOf: Day
  source: 'ecb' | 'identity' | 'remembered'
}

interface Cached {
  rateMicro: number
  asOf: Day
}

const CACHE_LIMIT = 60
const pairKey = (from: string, to: string) => `${from}/${to}`

function readCache(): Record<string, Cached> {
  return lsGet<Record<string, Cached>>(KEYS.fx, {})
}

function writeCache(cache: Record<string, Cached>): void {
  const keys = Object.keys(cache)
  // Oldest-first insertion order; drop from the front so the map stays small.
  for (const k of keys.slice(0, Math.max(0, keys.length - CACHE_LIMIT))) delete cache[k]
  lsSet(KEYS.fx, cache)
}

/** The rate last written into an entry for this pair, whatever its day. */
export function rememberedRate(from: string, to: string): number | null {
  return lsGet<Record<string, number>>(KEYS.fxLast, {})[pairKey(from, to)] ?? null
}

export function rememberRate(from: string, to: string, rateMicro: number): void {
  const last = lsGet<Record<string, number>>(KEYS.fxLast, {})
  last[pairKey(from, to)] = rateMicro
  lsSet(KEYS.fxLast, last)
}

/**
 * The day's rate, from the local cache or the server. Returns null when the
 * server cannot be reached and nothing has been remembered for the pair.
 */
export async function fetchRate(from: string, to: string, day: Day, baseUrl = DEFAULT_SERVER_URL): Promise<Rate | null> {
  if (from === to) return { rateMicro: 1_000_000, asOf: day, source: 'identity' }
  const key = `${pairKey(from, to)}@${day}`
  const cache = readCache()
  const hit = cache[key]
  // A day's rate is final once published for that day; a stand-in from an
  // earlier day (weekend, or asked before publication) is re-asked.
  if (hit && hit.asOf === day) return { ...hit, source: 'ecb' }

  try {
    const url = `${baseUrl.replace(/\/+$/, '')}/api/fx?from=${from}&to=${to}&day=${day}`
    const res = await fetch(url, { headers: { accept: 'application/json' } })
    if (!res.ok) throw new Error(String(res.status))
    const body = (await res.json()) as { rateMicro: number; asOf: Day }
    if (!Number.isInteger(body.rateMicro) || body.rateMicro <= 0) throw new Error('malformed')
    cache[key] = { rateMicro: body.rateMicro, asOf: body.asOf }
    writeCache(cache)
    return { rateMicro: body.rateMicro, asOf: body.asOf, source: 'ecb' }
  } catch {
    if (hit) return { ...hit, source: 'ecb' }
    const last = rememberedRate(from, to)
    return last === null ? null : { rateMicro: last, asOf: day, source: 'remembered' }
  }
}
