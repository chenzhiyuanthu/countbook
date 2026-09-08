import type { Fen } from './money'
import type { Day, Month } from './date'
import { addCalendarMonths, addDays, allDaysOf, daysInMonth, daysRemainingInMonth, diffDays, monthOf, toDay } from './date'
import type { Ledger, Sub, SubPeriod } from './types'
import { effective, standardAt, type EffectiveEntry } from './fold'

/**
 * Every number the app prints is computed here, from the folded ledger and
 * nothing else. Pure functions with no clock of their own: `today` is always
 * passed in, so a report is reproducible and a test does not need to mock time.
 */

export const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n))

export function median(xs: readonly number[]): number {
  if (!xs.length) return 0
  const s = [...xs].sort((a, b) => a - b)
  const mid = s.length >> 1
  return s.length % 2 ? s[mid]! : Math.round((s[mid - 1]! + s[mid]!) / 2)
}

export function stddev(xs: readonly number[]): number {
  if (xs.length < 2) return 0
  const mean = xs.reduce((a, b) => a + b, 0) / xs.length
  return Math.sqrt(xs.reduce((a, b) => a + (b - mean) ** 2, 0) / xs.length)
}

export const spendsOf = (L: Ledger): EffectiveEntry[] =>
  [...effective(L).values()].filter((e) => e.kind === 'spend')

export const inMonth = (es: readonly EffectiveEntry[], m: Month) => es.filter((e) => monthOf(e.day) === m)
export const inYear = (es: readonly EffectiveEntry[], y: string) => es.filter((e) => e.day.startsWith(y))
const total = (es: readonly EffectiveEntry[]) => es.reduce((a, e) => a + e.effective, 0)

/* ── 今日可用 — the standing figure ──────────────────────────────────── */

export interface Available {
  /** The hero number. The only figure in the app permitted to be negative. */
  perDay: Fen
  /** Provenance, printed underneath so the figure shows its own derivation. */
  standard: Fen
  spent: Fen
  fixedRemaining: Fen
  remaining: Fen
  daysLeft: number
  /** Days of zero spending needed to get back to zero, or 0 if not behind. */
  recoveryDays: number
}

export function available(L: Ledger, today: Day, nowMs: number): Available {
  const m = monthOf(today)
  const std = standardAt(L, nowMs)
  const spends = spendsOf(L)

  const spent = total(inMonth(spends, m).filter((e) => e.day <= today))
  const fixedRemaining = scheduledOutflowsRemaining(L, today)
  const remaining = std.monthlyFen - spent - fixedRemaining
  const daysLeft = Math.max(1, daysRemainingInMonth(today))

  // Integer division in 分; the remainder rides on the final day rather than
  // evaporating, so the daily figures sum back to the month exactly.
  const perDay = Math.trunc(remaining / daysLeft)

  const daily = std.monthlyFen > 0 ? Math.trunc(std.monthlyFen / daysInMonth(m)) : 0
  const recoveryDays = remaining >= 0 || daily <= 0 ? 0 : Math.ceil(-remaining / daily)

  return { perDay, standard: std.monthlyFen, spent, fixedRemaining, remaining, daysLeft, recoveryDays }
}

/** Committed charges still to come this month — money that is already spoken for. */
export function scheduledOutflowsRemaining(L: Ledger, today: Day): Fen {
  const m = monthOf(today)
  let sum = 0
  for (const s of L.subs.values()) {
    if (s.status === 'cancelled') continue
    if (monthOf(s.nextChargeAt) === m && s.nextChargeAt > today) sum += s.amount
  }
  return sum
}

/* ── 小额漏水 — the sub-threshold class ──────────────────────────────── */

export interface Leak {
  count: number
  sum: Fen
  /** The trailing-90-day median of above-ceiling spends; the equivalence divisor. */
  divisor: Fen
  /** sum / divisor — "≈ 3.1 次大额支出". 0 when there is no basis yet. */
  equivalent: number
  byMerchant: { key: string; count: number; sum: Fen }[]
}

export function leak(L: Ledger, today: Day): Leak {
  const ceiling = L.settings.leakCeilingFen
  const spends = spendsOf(L)
  const month = inMonth(spends, monthOf(today))
  const small = month.filter((e) => e.effective > 0 && e.effective < ceiling)

  const since = addDays(today, -90)
  const big = spends.filter((e) => e.day >= since && e.day <= today && e.effective >= ceiling)
  const divisor = median(big.map((e) => e.effective))

  const groups = new Map<string, { key: string; count: number; sum: Fen }>()
  for (const e of small) {
    const key = e.merchant.trim() || (L.categories.get(e.categoryId)?.name ?? '其他')
    const g = groups.get(key) ?? { key, count: 0, sum: 0 }
    g.count++
    g.sum += e.effective
    groups.set(key, g)
  }

  return {
    count: small.length,
    sum: total(small),
    divisor,
    equivalent: divisor > 0 ? total(small) / divisor : 0,
    byMerchant: [...groups.values()].sort((a, b) => b.sum - a.sum),
  }
}

/* ── 后悔账 — the number that does not soften ────────────────────────── */

export interface Regret {
  month: Fen
  year: Fen
  judged: number
  notWorth: number
  /** Undefined until the sample is large enough to mean anything. */
  rate?: number
  pending: number
}

export function regret(L: Ledger, today: Day, minSample = 30): Regret {
  const spends = spendsOf(L)
  const judgedAll = spends.filter((e) => e.worthIt !== undefined)
  const notWorth = judgedAll.filter((e) => e.worthIt === false)
  const m = monthOf(today)
  const y = today.slice(0, 4)

  return {
    month: total(notWorth.filter((e) => monthOf(e.day) === m)),
    year: total(notWorth.filter((e) => e.day.startsWith(y))),
    judged: judgedAll.length,
    notWorth: notWorth.length,
    ...(judgedAll.length >= minSample ? { rate: notWorth.length / judgedAll.length } : {}),
    pending: spends.filter((e) => e.worthIt === undefined && e.intent !== 'need' && e.intent !== null).length,
  }
}

export interface CategoryRegret {
  categoryId: string
  judged: number
  notWorth: number
  amount: Fen
  rate: number
}

/** Ranked by amount, not by rate: an amount-weighted list puts the real offender first. */
export function regretByCategory(L: Ledger, today: Day, months = 12): CategoryRegret[] {
  const since = addDays(today, -Math.round(months * 30.44))
  const rows = new Map<string, CategoryRegret>()
  for (const e of spendsOf(L)) {
    if (e.day < since || e.worthIt === undefined) continue
    const r = rows.get(e.categoryId) ?? { categoryId: e.categoryId, judged: 0, notWorth: 0, amount: 0, rate: 0 }
    r.judged++
    if (e.worthIt === false) {
      r.notWorth++
      r.amount += e.effective
    }
    rows.set(e.categoryId, r)
  }
  for (const r of rows.values()) r.rate = r.judged ? r.notWorth / r.judged : 0
  return [...rows.values()].sort((a, b) => b.amount - a.amount)
}

/**
 * The label on the save button, when the category being filed under has a bad
 * record and the amount is not trivial. Spending the regret rate at the moment
 * of commitment is the only place it can still change the outcome.
 */
export function commitWarning(L: Ledger, today: Day, categoryId: string, amount: Fen): string | null {
  const rows = regretByCategory(L, today)
  const r = rows.find((x) => x.categoryId === categoryId)
  if (!r || r.judged < 8) return null
  if (r.rate <= 0.4) return null
  if (amount < L.settings.leakCeilingFen * 2) return null
  return `这类你 ${Math.round(r.rate * 100)}% 判过不值`
}

/* ── 偏差条 — deviation from the standard you set ────────────────────── */

export interface Deviation {
  categoryId: string
  spent: Fen
  standard: Fen
  /** Positive is over. */
  delta: Fen
}

export function deviationByCategory(L: Ledger, month: Month, nowMs: number): Deviation[] {
  const std = standardAt(L, nowMs)
  const spends = inMonth(spendsOf(L), month)
  const spentBy = new Map<string, Fen>()
  for (const e of spends) spentBy.set(e.categoryId, (spentBy.get(e.categoryId) ?? 0) + e.effective)

  const ids = new Set([...spentBy.keys(), ...Object.keys(std.perCategory)])
  return [...ids]
    .map((categoryId) => {
      const spent = spentBy.get(categoryId) ?? 0
      const standard = std.perCategory[categoryId] ?? 0
      return { categoryId, spent, standard, delta: spent - standard }
    })
    .sort((a, b) => b.delta - a.delta)
}

/* ── 月度日柱 — the month strip ──────────────────────────────────────── */

export interface DayBar {
  day: Day
  spent: Fen
  /** Explicitly marked 今天没花钱 — distinct from "nothing was logged". */
  declaredZero: boolean
  logged: boolean
  future: boolean
}

export interface MonthStrip {
  bars: DayBar[]
  /** The height of the reference hairline: the month's standard spread evenly. */
  dailyStandard: Fen
  max: Fen
}

export function monthStrip(L: Ledger, month: Month, today: Day, nowMs: number): MonthStrip {
  const std = standardAt(L, nowMs)
  const byDay = new Map<Day, Fen>()
  for (const e of inMonth(spendsOf(L), month)) byDay.set(e.day, (byDay.get(e.day) ?? 0) + e.effective)

  const bars = allDaysOf(month).map<DayBar>((day) => ({
    day,
    spent: byDay.get(day) ?? 0,
    declaredZero: L.noSpendDays.has(day),
    logged: byDay.has(day) || L.noSpendDays.has(day),
    future: day > today,
  }))

  const dailyStandard = std.monthlyFen > 0 ? Math.trunc(std.monthlyFen / daysInMonth(month)) : 0
  return { bars, dailyStandard, max: Math.max(dailyStandard, ...bars.map((b) => b.spent)) }
}

/**
 * Consecutive days, ending yesterday, that were at or under the daily standard.
 * A day with no data at all breaks the streak rather than extending it —
 * otherwise not logging would be the winning strategy.
 */
export function streak(L: Ledger, today: Day, nowMs: number): number {
  const std = standardAt(L, nowMs)
  if (std.monthlyFen <= 0) return 0
  const byDay = new Map<Day, Fen>()
  for (const e of spendsOf(L)) byDay.set(e.day, (byDay.get(e.day) ?? 0) + e.effective)

  let n = 0
  for (let i = 1; i <= 400; i++) {
    const day = addDays(today, -i)
    const daily = Math.trunc(std.monthlyFen / daysInMonth(monthOf(day)))
    const logged = byDay.has(day) || L.noSpendDays.has(day)
    if (!logged) break
    if ((byDay.get(day) ?? 0) > daily) break
    n++
  }
  return n
}

/* ── 待购 — cooling ──────────────────────────────────────────────────── */

/** Continuous, not tiered: ¥999 and ¥1,001 should not differ by a week. */
export function coolingDays(priceFen: Fen, perDay = 10_000, lo = 1, hi = 14): number {
  return clamp(Math.ceil(priceFen / perDay), lo, hi)
}

export interface WishStats {
  abstainedYear: Fen
  abstainedAll: Fen
  cooling: number
  ready: number
}

export function wishStats(L: Ledger, today: Day, nowMs: number): WishStats {
  const y = today.slice(0, 4)
  let abstainedYear = 0
  let abstainedAll = 0
  let cooling = 0
  let ready = 0
  for (const w of L.wishes.values()) {
    if (w.outcome === 'abstained') {
      abstainedAll += w.price
      if (w.resolvedAt && toDay(new Date(w.resolvedAt)).startsWith(y)) abstainedYear += w.price
    } else if (!w.outcome) {
      if (w.unlockAt <= nowMs) ready++
      else cooling++
    }
  }
  return { abstainedYear, abstainedAll, cooling, ready }
}

/* ── 订阅影子 — annualisation ────────────────────────────────────────── */

const PER_YEAR: Record<SubPeriod, number> = { week: 52, month: 12, quarter: 4, year: 1 }

export interface SubView {
  sub: Sub
  annual: Fen
  paidSoFar: Fen
  perUse?: Fen
}

export function subViews(L: Ledger, today: Day): { rows: SubView[]; annual: Fen; perDay: Fen } {
  const rows: SubView[] = []
  for (const s of L.subs.values()) {
    const annual = s.amount * PER_YEAR[s.period]
    const elapsedDays = Math.max(0, diffDays(s.firstChargedAt, s.cancelledAt ?? today))
    const charges = Math.floor(elapsedDays / (365 / PER_YEAR[s.period])) + 1
    const paidSoFar = s.amount * charges
    const uses = s.usageDays?.length ?? 0
    rows.push({ sub: s, annual, paidSoFar, ...(uses > 0 ? { perUse: Math.trunc(paidSoFar / uses) } : {}) })
  }
  // Ranked by annual cost: the decision is "stop a ¥300/year", never "save ¥25".
  rows.sort((a, b) => b.annual - a.annual)
  const live = rows.filter((r) => r.sub.status !== 'cancelled')
  const annual = live.reduce((a, r) => a + r.annual, 0)
  return { rows, annual, perDay: Math.trunc(annual / 365) }
}

/** Money no longer leaving, and still counting, since a subscription was cancelled. */
export function savedByCancelling(L: Ledger, today: Day): Fen {
  let sum = 0
  for (const s of L.subs.values()) {
    if (s.status !== 'cancelled' || !s.cancelledAt) continue
    const days = Math.max(0, diffDays(s.cancelledAt, today))
    sum += Math.trunc((s.amount * PER_YEAR[s.period] * days) / 365)
  }
  return sum
}

/* ── recurring detection ─────────────────────────────────────────────── */

export interface Detected {
  key: string
  name: string
  amount: Fen
  period: SubPeriod
  categoryId: string
  firstChargedAt: Day
  lastChargedAt: Day
  nextChargeAt: Day
  occurrences: number
}

const normaliseMerchant = (s: string) => s.trim().toLowerCase().replace(/\s+/g, ' ').replace(/[0-9#]+$/, '').trim()

/** Calendar-correct advance for each billing period. */
export function nextCharge(day: Day, period: SubPeriod): Day {
  switch (period) {
    case 'week': return addDays(day, 7)
    case 'month': return addCalendarMonths(day, 1)
    case 'quarter': return addCalendarMonths(day, 3)
    case 'year': return addCalendarMonths(day, 12)
  }
}

const PERIOD_GUESS: [SubPeriod, number, number][] = [
  ['week', 7, 2],
  ['month', 30.44, 5],
  ['quarter', 91.3, 10],
  ['year', 365, 20],
]

/**
 * Find charges that keep coming back: same payee, near-identical amount, at a
 * regular interval. Purely local — nothing is sent anywhere to work this out.
 * Results start `unclaimed`, and the user has to say 保留 or 待退订 for each.
 */
export function detectRecurring(L: Ledger, today: Day, minOccurrences = 3, maxJitterDays = 4): Detected[] {
  const byKey = new Map<string, EffectiveEntry[]>()
  for (const e of spendsOf(L)) {
    const key = normaliseMerchant(e.merchant)
    if (!key || e.effective <= 0) continue
    byKey.set(key, [...(byKey.get(key) ?? []), e])
  }

  const out: Detected[] = []
  for (const [key, all] of byKey) {
    // Only what is still charging: a series that stopped two intervals ago was
    // already cancelled, and surfacing it as "unclaimed" is noise.
    // Cluster on amount: a ±5% band tolerates FX drift and price rises without
    // merging a ¥25 subscription with a ¥250 one.
    const sorted = [...all].sort((a, b) => a.effective - b.effective)
    let i = 0
    while (i < sorted.length) {
      const base = sorted[i]!.effective
      let j = i
      while (j < sorted.length && sorted[j]!.effective <= base * 1.05) j++
      const cluster = sorted.slice(i, j).sort((a, b) => (a.day < b.day ? -1 : 1))
      i = j
      if (cluster.length < minOccurrences) continue

      const gaps: number[] = []
      for (let k = 1; k < cluster.length; k++) gaps.push(diffDays(cluster[k - 1]!.day, cluster[k]!.day))
      if (stddev(gaps) >= maxJitterDays) continue

      const meanGap = gaps.reduce((a, b) => a + b, 0) / gaps.length
      const guess = PERIOD_GUESS.find(([, days, tol]) => Math.abs(meanGap - days) <= tol)
      if (!guess) continue

      const first = cluster[0]!
      const last = cluster[cluster.length - 1]!
      if (diffDays(last.day, today) > meanGap * 2 + maxJitterDays) continue

      out.push({
        key,
        name: first.merchant.trim() || key,
        amount: median(cluster.map((c) => c.effective)),
        period: guess[0],
        categoryId: last.categoryId,
        firstChargedAt: first.day,
        lastChargedAt: last.day,
        nextChargeAt: nextCharge(last.day, guess[0]),
        occurrences: cluster.length,
      })
    }
  }
  return out.sort((a, b) => b.amount * PER_YEAR[b.period] - a.amount * PER_YEAR[a.period])
}

/* ── the hour scatter ────────────────────────────────────────────────── */

/** Logging time by hour, which is where late-night ordering becomes visible. */
export function hourScatter(L: Ledger, today: Day, days = 90): { hour: number; count: number; sum: Fen }[] {
  const since = addDays(today, -days)
  const buckets = Array.from({ length: 24 }, (_, hour) => ({ hour, count: 0, sum: 0 }))
  for (const e of spendsOf(L)) {
    if (e.day < since) continue
    const h = new Date(e.createdAt).getHours()
    const b = buckets[h]!
    b.count++
    b.sum += e.effective
  }
  return buckets
}

/* ── 心愿物 — the exchange rate for regret ───────────────────────────── */

export function regretAsWishObject(L: Ledger, regretYear: Fen): { name: string; fraction: number } | null {
  const w = L.settings.wishObject
  if (!w || w.priceFen <= 0) return null
  return { name: w.name, fraction: Math.min(1, regretYear / w.priceFen) }
}

/** The proposal the app offers when asked to suggest a standard: the trailing median. */
export function proposeStandard(L: Ledger, today: Day): { monthlyFen: Fen; perCategory: Record<string, Fen> } | null {
  const spends = spendsOf(L)
  if (!spends.length) return null
  const since = addDays(today, -90)
  const window = spends.filter((e) => e.day >= since && e.day <= today)
  const firstDay = window.reduce<Day>((a, e) => (e.day < a ? e.day : a), today)
  if (diffDays(firstDay, today) < 30) return null

  const months = new Map<Month, Fen>()
  for (const e of window) months.set(monthOf(e.day), (months.get(monthOf(e.day)) ?? 0) + e.effective)
  const monthlyFen = median([...months.values()])

  const perCategoryMonths = new Map<string, Map<Month, Fen>>()
  for (const e of window) {
    const m = perCategoryMonths.get(e.categoryId) ?? new Map()
    m.set(monthOf(e.day), (m.get(monthOf(e.day)) ?? 0) + e.effective)
    perCategoryMonths.set(e.categoryId, m)
  }
  const perCategory: Record<string, Fen> = {}
  for (const [cat, m] of perCategoryMonths) perCategory[cat] = median([...m.values()])

  return { monthlyFen, perCategory }
}

/** Entries owed a verdict this Sunday: unjudged 想要/冲动 from the past week, largest first. */
export function reckoningQueue(L: Ledger, today: Day, maxCards = 12): EffectiveEntry[] {
  const since = addDays(today, -7)
  return spendsOf(L)
    .filter((e) => e.day >= since && e.day <= today && e.worthIt === undefined && (e.intent === 'want' || e.intent === 'impulse'))
    .sort((a, b) => b.effective - a.effective)
    .slice(0, maxCards)
}

export { effective, standardAt }
export type { EffectiveEntry }
