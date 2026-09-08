import type { Fen } from './money'
import type { Day } from './date'
import type { Category, Correction, Entry, Settings, Sub, SubStatus, Voidance, Wish } from './types'
import { compare as compareHlc } from './hlc'

/**
 * The ledger is an append-only log. Nothing is ever mutated in place and no
 * device ever needs to agree with another about anything except the set of
 * events it has seen — which makes the merge trivially correct: union by id,
 * order by HLC, fold.
 *
 * Union is commutative, associative and idempotent because it is set union on
 * immutable, uniquely-identified records; the fold is deterministic because the
 * order is a total order that does not depend on arrival time. Two devices that
 * have seen the same events therefore always show the same ledger.
 */

export interface Envelope {
  id: string
  hlc: string
  dev: string
}

export type Payload =
  | { t: 'entry.add'; entry: Entry }
  | { t: 'entry.patch'; target: string; patch: Partial<Omit<Entry, 'id'>> }
  | { t: 'entry.remove'; target: string }
  | { t: 'entry.correct'; target: string; amount: Fen; reason: string }
  | { t: 'entry.void'; target: string; reason: string }
  | { t: 'review.judge'; target: string; worthIt: boolean }
  | { t: 'review.defer'; target: string }
  | { t: 'wish.add'; wish: Wish }
  | { t: 'wish.resolve'; target: string; outcome: 'bought' | 'abstained'; entryId?: string }
  | { t: 'wish.remove'; target: string }
  | { t: 'sub.upsert'; sub: Sub }
  | { t: 'sub.status'; target: string; status: SubStatus; day?: Day }
  | { t: 'sub.use'; target: string; day: Day }
  | { t: 'sub.remove'; target: string }
  | { t: 'standard.set'; monthlyFen: Fen; perCategory: Record<string, Fen>; reason?: string }
  | { t: 'category.upsert'; category: Category }
  | { t: 'category.remove'; target: string }
  | { t: 'settings.patch'; patch: Partial<Settings> }
  | { t: 'day.nospend'; day: Day; on: boolean }

export type Event = Envelope & Payload

/** Union by event id, then total order by HLC. */
export function merge(a: readonly Event[], b: readonly Event[]): Event[] {
  const byId = new Map<string, Event>()
  for (const e of a) byId.set(e.id, e)
  for (const e of b) if (!byId.has(e.id)) byId.set(e.id, e)
  return sort([...byId.values()])
}

export const sort = (events: Event[]): Event[] => events.sort((x, y) => compareHlc(x.hlc, y.hlc))

/**
 * Compaction. Events whose effect is fully superseded carry no information once
 * the whole log is folded, so a vault blob does not have to grow forever. Only
 * events strictly older than `before` are eligible, so a device that has been
 * offline since then still merges correctly.
 *
 * What survives: every event about an entry that still exists, every correction
 * and voidance (they are the audit trail and are never dropped), and the latest
 * settings/standard events. What is dropped: patches on entries that were later
 * removed, and superseded settings patches.
 */
export function compact(events: readonly Event[], before: string): Event[] {
  const removed = new Set<string>()
  for (const e of events) if (e.t === 'entry.remove') removed.add(e.target)

  const keptSettings: Event[] = []
  const out: Event[] = []
  for (const e of events) {
    const old = compareHlc(e.hlc, before) < 0
    if (!old) {
      out.push(e)
      continue
    }
    switch (e.t) {
      case 'entry.add':
      case 'entry.patch':
      case 'review.judge':
      case 'review.defer':
        if (!removed.has(e.t === 'entry.add' ? e.entry.id : e.target)) out.push(e)
        break
      case 'entry.remove':
        // The tombstone must outlive the events it suppresses.
        out.push(e)
        break
      case 'settings.patch':
        keptSettings.push(e)
        break
      default:
        out.push(e)
    }
  }
  // Collapse the settings history into one event carrying the merged patch.
  if (keptSettings.length) {
    const merged = keptSettings.reduce<Partial<Settings>>(
      (acc, e) => (e.t === 'settings.patch' ? { ...acc, ...e.patch } : acc),
      {},
    )
    const last = keptSettings[keptSettings.length - 1]!
    out.push({ id: last.id, hlc: last.hlc, dev: last.dev, t: 'settings.patch', patch: merged })
  }
  return sort(out)
}

export type { Correction, Voidance }
