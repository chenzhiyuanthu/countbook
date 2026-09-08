import type { Event } from './events'
import type { Correction, Entry, Ledger, Voidance } from './types'
import { DEFAULT_CATEGORIES, DEFAULT_SETTINGS } from './categories'
import { decode } from './hlc'
import type { Fen } from './money'

export function emptyLedger(): Ledger {
  return {
    entries: new Map(),
    tombstones: new Set(),
    corrections: [],
    voids: [],
    categories: new Map(DEFAULT_CATEGORIES.map((c) => [c.id, c])),
    wishes: new Map(),
    subs: new Map(),
    standards: [],
    settings: { ...DEFAULT_SETTINGS },
    noSpendDays: new Set(),
  }
}

/**
 * Fold the log into the ledger. Events arrive already sorted by HLC, so
 * "later event wins" is simply "applied second", and a patch that names only
 * some fields yields per-field last-writer-wins for free.
 *
 * Delete wins over a concurrent edit: an entry removed on one device stays
 * removed even if another device patched it afterwards without having seen the
 * removal. Resurrecting a row the user deliberately deleted is the worse
 * failure — they would have to notice it came back to delete it again.
 */
export function fold(events: readonly Event[]): Ledger {
  const L = emptyLedger()

  for (const e of events) {
    switch (e.t) {
      case 'entry.add':
        if (!L.tombstones.has(e.entry.id)) L.entries.set(e.entry.id, { ...e.entry })
        break

      case 'entry.patch': {
        const cur = L.entries.get(e.target)
        if (cur) L.entries.set(e.target, { ...cur, ...e.patch })
        break
      }

      case 'entry.remove':
        L.entries.delete(e.target)
        L.tombstones.add(e.target)
        break

      case 'entry.correct':
        L.corrections.push({ id: e.id, targetId: e.target, amount: e.amount, reason: e.reason, at: decode(e.hlc).wall })
        break

      case 'entry.void':
        L.voids.push({ id: e.id, targetId: e.target, reason: e.reason, at: decode(e.hlc).wall })
        break

      case 'review.judge': {
        const cur = L.entries.get(e.target)
        if (cur) L.entries.set(e.target, { ...cur, worthIt: e.worthIt, reviewedAt: decode(e.hlc).wall })
        break
      }

      case 'review.defer': {
        const cur = L.entries.get(e.target)
        if (!cur) break
        const n = (cur.deferrals ?? 0) + 1
        // A bounded deferral, not an escape hatch: once the limit is reached the
        // entry records itself as 不值, because refusing to look at it for three
        // weeks running is itself the answer.
        L.entries.set(
          e.target,
          n >= 3 ? { ...cur, deferrals: n, worthIt: false, reviewedAt: decode(e.hlc).wall } : { ...cur, deferrals: n },
        )
        break
      }

      case 'wish.add':
        L.wishes.set(e.wish.id, { ...e.wish })
        break

      case 'wish.resolve': {
        const w = L.wishes.get(e.target)
        if (w) L.wishes.set(e.target, { ...w, outcome: e.outcome, resolvedAt: decode(e.hlc).wall, entryId: e.entryId })
        break
      }

      case 'wish.remove':
        L.wishes.delete(e.target)
        break

      case 'sub.upsert':
        L.subs.set(e.sub.id, { ...L.subs.get(e.sub.id), ...e.sub })
        break

      case 'sub.status': {
        const s = L.subs.get(e.target)
        if (s) L.subs.set(e.target, { ...s, status: e.status, ...(e.day ? { cancelledAt: e.day } : {}) })
        break
      }

      case 'sub.use': {
        const s = L.subs.get(e.target)
        if (s) L.subs.set(e.target, { ...s, usageDays: [...(s.usageDays ?? []), e.day] })
        break
      }

      case 'sub.remove':
        L.subs.delete(e.target)
        break

      case 'standard.set':
        L.standards.push({
          id: e.id,
          at: decode(e.hlc).wall,
          monthlyFen: e.monthlyFen,
          perCategory: { ...e.perCategory },
          ...(e.reason ? { reason: e.reason } : {}),
        })
        break

      case 'category.upsert':
        L.categories.set(e.category.id, { ...e.category })
        break

      case 'category.remove': {
        // Archived, never deleted: entries filed under it must keep their label.
        const c = L.categories.get(e.target)
        if (c) L.categories.set(e.target, { ...c, archived: true })
        break
      }

      case 'settings.patch':
        L.settings = { ...L.settings, ...e.patch }
        break

      case 'day.nospend':
        if (e.on) L.noSpendDays.add(e.day)
        else L.noSpendDays.delete(e.day)
        break
    }
  }

  L.corrections.sort((a, b) => a.at - b.at)
  L.standards.sort((a, b) => a.at - b.at)
  return L
}

/* ── derived views over the audit trail ──────────────────────────────── */

export interface EffectiveEntry extends Entry {
  /** The amount aggregates must use: corrected, or 0 if the row was voided. */
  effective: Fen
  correction?: Correction
  voidance?: Voidance
}

/**
 * Resolve corrections and voidances onto the entries. The originals are never
 * changed — the ledger prints both — but every total in the app is computed
 * from `effective`.
 */
export function effective(L: Ledger): Map<string, EffectiveEntry> {
  const latestCorrection = new Map<string, Correction>()
  for (const c of L.corrections) latestCorrection.set(c.targetId, c) // sorted, so last wins
  const voided = new Map<string, Voidance>()
  for (const v of L.voids) voided.set(v.targetId, v)

  const out = new Map<string, EffectiveEntry>()
  for (const [id, e] of L.entries) {
    const c = latestCorrection.get(id)
    const v = voided.get(id)
    out.set(id, {
      ...e,
      effective: v ? 0 : (c?.amount ?? e.amount),
      ...(c ? { correction: c } : {}),
      ...(v ? { voidance: v } : {}),
    })
  }
  return out
}

/** The standard in force for a given month, i.e. the latest revision made before it ended. */
export function standardAt(L: Ledger, atMs: number): { monthlyFen: Fen; perCategory: Record<string, Fen> } {
  let found: { monthlyFen: Fen; perCategory: Record<string, Fen> } = { monthlyFen: 0, perCategory: {} }
  for (const s of L.standards) {
    if (s.at <= atMs) found = { monthlyFen: s.monthlyFen, perCategory: s.perCategory }
  }
  return found
}
