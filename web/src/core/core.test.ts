import { describe, expect, it } from 'vitest'
import fixtures from '../../../design/fixtures/money.json'
import { format, parse, parts, divideRemainderLast, MINUS } from './money'
import { addDays, allDaysOf, daysInMonth, daysRemainingInMonth, diffDays, monthOf, toDay } from './date'
import { Clock, compare, decode, encode } from './hlc'
import { fold, effective } from './fold'
import { merge, sort, type Event, type Payload } from './events'
import { available, coolingDays, detectRecurring, leak, median, regret, stddev, streak, monthStrip } from './compute'
import type { Entry } from './types'

/* ── money ───────────────────────────────────────────────────────────── */

describe('money', () => {
  it('formats every shared fixture identically', () => {
    for (const f of fixtures.format) expect(format(f.fen)).toBe(f.out)
  })

  it('parses every shared fixture, rejecting the malformed ones', () => {
    for (const f of fixtures.parse) expect(parse(f.in)).toBe(f.fen)
  })

  it('splits into the parts the design renders separately', () => {
    expect(parts(-8420)).toEqual({ sign: MINUS, symbol: '¥', int: '84', frac: '20' })
    expect(parts(123800)).toEqual({ sign: '', symbol: '¥', int: '1,238', frac: '00' })
  })

  it('round-trips parse and format without drift', () => {
    for (let fen = -50_000; fen < 50_000; fen += 337) expect(parse(format(fen).replace(MINUS, '-'))).toBe(fen)
  })

  it('never loses a fen when dividing across days', () => {
    for (const [total, n] of [[10_000, 7], [-8_421, 12], [1, 31], [0, 5]] as const) {
      const { per, last } = divideRemainderLast(total, n)
      expect(per * (n - 1) + last).toBe(total)
    }
  })
})

/* ── dates ───────────────────────────────────────────────────────────── */

describe('dates', () => {
  it('handles month lengths including leap February', () => {
    expect(daysInMonth('2024-02')).toBe(29)
    expect(daysInMonth('2026-02')).toBe(28)
    expect(daysInMonth('2026-09')).toBe(30)
  })

  it('counts remaining days inclusive of today', () => {
    expect(daysRemainingInMonth('2026-09-30')).toBe(1)
    expect(daysRemainingInMonth('2026-09-01')).toBe(30)
    expect(daysRemainingInMonth('2026-09-20')).toBe(11)
  })

  it('crosses month and year boundaries', () => {
    expect(addDays('2026-01-31', 1)).toBe('2026-02-01')
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28')
    expect(diffDays('2026-01-01', '2026-12-31')).toBe(364)
  })

  it('enumerates whole months', () => {
    expect(allDaysOf('2026-02')).toHaveLength(28)
    expect(monthOf('2026-09-08')).toBe('2026-09')
  })

  it('survives a DST transition without a half-day', () => {
    // Northern-hemisphere spring forward; diffDays must still be a whole number.
    expect(diffDays('2026-03-07', '2026-03-09')).toBe(2)
  })
})

/* ── clock ───────────────────────────────────────────────────────────── */

describe('hybrid logical clock', () => {
  it('encodes to a lexicographically sortable string', () => {
    const a = encode({ wall: 1, counter: 0, device: 'aa' })
    const b = encode({ wall: 2, counter: 0, device: 'aa' })
    const c = encode({ wall: 2, counter: 1, device: 'aa' })
    expect(compare(a, b)).toBeLessThan(0)
    expect(compare(b, c)).toBeLessThan(0)
    expect(decode(c)).toEqual({ wall: 2, counter: 1, device: 'aa' })
  })

  it('advances monotonically even when the wall clock goes backwards', () => {
    let t = 1000
    const clock = new Clock('aa', () => t)
    const first = clock.next()
    t = 900 // NTP correction, or a user changing the date
    const second = clock.next()
    const third = clock.next()
    expect(compare(first, second)).toBeLessThan(0)
    expect(compare(second, third)).toBeLessThan(0)
  })

  it('sorts after any timestamp it has observed', () => {
    const clock = new Clock('aa', () => 1000)
    const remote = encode({ wall: 5000, counter: 9, device: 'bb' })
    clock.observe(remote)
    expect(compare(remote, clock.next())).toBeLessThan(0)
  })
})

/* ── merge ───────────────────────────────────────────────────────────── */

const ev = (id: string, hlc: string, p: Payload): Event => ({ id, hlc, dev: hlc.split('-')[2] ?? 'aa', ...p })

const entry = (over: Partial<Entry> = {}): Entry => ({
  id: 'e1',
  kind: 'spend',
  amount: 10_000,
  currency: 'CNY',
  categoryId: 'food',
  intent: 'want',
  note: '',
  merchant: '',
  day: '2026-09-08',
  createdAt: 1_760_000_000_000,
  ...over,
})

const H = (wall: number, ctr = 0, dev = 'aa') => encode({ wall, counter: ctr, device: dev })

describe('merge', () => {
  const a: Event[] = [
    ev('1', H(100), { t: 'entry.add', entry: entry() }),
    ev('2', H(200), { t: 'entry.patch', target: 'e1', patch: { note: 'from A' } }),
  ]
  const b: Event[] = [
    ev('1', H(100), { t: 'entry.add', entry: entry() }),
    ev('3', H(300), { t: 'entry.patch', target: 'e1', patch: { note: 'from B' } }),
  ]

  it('is commutative, associative and idempotent', () => {
    const ab = merge(a, b)
    const ba = merge(b, a)
    expect(ab.map((e) => e.id)).toEqual(ba.map((e) => e.id))
    expect(merge(ab, ab).map((e) => e.id)).toEqual(ab.map((e) => e.id))
    expect(merge(merge(a, b), []).map((e) => e.id)).toEqual(merge(a, merge(b, [])).map((e) => e.id))
  })

  it('resolves a concurrent edit by last writer per field', () => {
    const L = fold(merge(a, b))
    expect(L.entries.get('e1')?.note).toBe('from B')
  })

  it('lets a delete win over an edit that did not see it', () => {
    const withDelete = merge(a, [ev('9', H(250), { t: 'entry.remove', target: 'e1' })])
    const L = fold(merge(withDelete, b))
    expect(L.entries.has('e1')).toBe(false)
    expect(L.tombstones.has('e1')).toBe(true)
  })

  it('does not resurrect a deleted entry when an old add arrives late', () => {
    const deleted = [ev('9', H(250), { t: 'entry.remove', target: 'e1' })]
    const lateAdd = [ev('1', H(100), { t: 'entry.add', entry: entry() })]
    expect(fold(sort(merge(deleted, lateAdd))).entries.has('e1')).toBe(false)
  })

  it('folds a week-late device to the same state as the device that was online', () => {
    const online = merge(a, b)
    const offline = merge(b, a)
    expect(JSON.stringify([...fold(online).entries])).toBe(JSON.stringify([...fold(offline).entries]))
  })
})

/* ── corrections ─────────────────────────────────────────────────────── */

describe('corrections', () => {
  it('leaves the original printed and uses the corrected amount in totals', () => {
    const L = fold([
      ev('1', H(100), { t: 'entry.add', entry: entry({ amount: 28_800 }) }),
      ev('2', H(200), { t: 'entry.correct', target: 'e1', amount: 8_800, reason: '记错了' }),
    ])
    expect(L.entries.get('e1')?.amount).toBe(28_800)
    expect(effective(L).get('e1')?.effective).toBe(8_800)
    expect(L.corrections).toHaveLength(1)
  })

  it('zeroes a voided row without deleting it', () => {
    const L = fold([
      ev('1', H(100), { t: 'entry.add', entry: entry() }),
      ev('2', H(200), { t: 'entry.void', target: 'e1', reason: '重复' }),
    ])
    expect(L.entries.has('e1')).toBe(true)
    expect(effective(L).get('e1')?.effective).toBe(0)
  })

  it('records 不值 once the deferral limit is reached', () => {
    const L = fold([
      ev('1', H(100), { t: 'entry.add', entry: entry() }),
      ev('2', H(200), { t: 'review.defer', target: 'e1' }),
      ev('3', H(300), { t: 'review.defer', target: 'e1' }),
      ev('4', H(400), { t: 'review.defer', target: 'e1' }),
    ])
    expect(L.entries.get('e1')?.worthIt).toBe(false)
  })
})

/* ── the formulas ────────────────────────────────────────────────────── */

const ledgerWith = (entries: Entry[], monthlyFen = 800_000, perCategory: Record<string, number> = {}) =>
  fold([
    ev('s', H(1), { t: 'standard.set', monthlyFen, perCategory }),
    ...entries.map((e, i) => ev(`a${i}`, H(10 + i), { t: 'entry.add', entry: e })),
  ])

describe('今日可用', () => {
  it('divides what is left by the days that are left, inclusive of today', () => {
    const L = ledgerWith([entry({ id: 'x', amount: 200_000, day: '2026-09-01' })])
    const a = available(L, '2026-09-20', Date.parse('2026-09-20T12:00:00'))
    expect(a.standard).toBe(800_000)
    expect(a.spent).toBe(200_000)
    expect(a.daysLeft).toBe(11)
    expect(a.perDay).toBe(Math.trunc(600_000 / 11))
  })

  it('goes negative and reports how many clean days undo it', () => {
    const L = ledgerWith([entry({ id: 'x', amount: 900_000, day: '2026-09-02' })])
    const a = available(L, '2026-09-20', Date.parse('2026-09-20T12:00:00'))
    expect(a.perDay).toBeLessThan(0)
    expect(a.recoveryDays).toBeGreaterThan(0)
    expect(a.recoveryDays).toBe(Math.ceil(100_000 / Math.trunc(800_000 / 30)))
  })

  it('subtracts charges that are already committed for later this month', () => {
    const L = fold([
      ev('s', H(1), { t: 'standard.set', monthlyFen: 800_000, perCategory: {} }),
      ev('sub', H(2), {
        t: 'sub.upsert',
        sub: {
          id: 's1', name: 'iCloud', amount: 5_000, period: 'month', categoryId: 'sub',
          firstChargedAt: '2026-01-25', nextChargeAt: '2026-09-25', status: 'keep',
        },
      }),
    ])
    expect(available(L, '2026-09-20', Date.parse('2026-09-20T12:00:00')).fixedRemaining).toBe(5_000)
  })
})

describe('小额漏水', () => {
  it('counts the sub-threshold class and states it as whole large purchases', () => {
    const smalls = Array.from({ length: 10 }, (_, i) => entry({ id: `s${i}`, amount: 1_500, day: '2026-09-0' + ((i % 9) + 1) }))
    const bigs = [entry({ id: 'b1', amount: 20_000, day: '2026-08-10' }), entry({ id: 'b2', amount: 10_000, day: '2026-08-11' })]
    const L = ledgerWith([...smalls, ...bigs])
    const k = leak(L, '2026-09-20')
    expect(k.count).toBe(10)
    expect(k.sum).toBe(15_000)
    expect(k.divisor).toBe(15_000)
    expect(k.equivalent).toBeCloseTo(1, 5)
  })
})

describe('后悔账', () => {
  it('withholds the rate until the sample is large enough to mean anything', () => {
    const few = Array.from({ length: 5 }, (_, i) => entry({ id: `j${i}`, amount: 1_000, day: '2026-09-01' }))
    const L = fold([
      ...few.map((e, i) => ev(`a${i}`, H(10 + i), { t: 'entry.add', entry: e })),
      ...few.map((e, i) => ev(`r${i}`, H(100 + i), { t: 'review.judge', target: e.id, worthIt: false })),
    ])
    const r = regret(L, '2026-09-20')
    expect(r.judged).toBe(5)
    expect(r.rate).toBeUndefined()
    expect(r.year).toBe(5_000)
  })
})

describe('冷静期', () => {
  it('scales continuously with price, with no cliff to game', () => {
    for (const f of fixtures.coolingDays) expect(coolingDays(f.priceFen)).toBe(f.days)
  })
})

describe('订阅侦测', () => {
  it('finds a monthly charge and ignores an irregular one', () => {
    const monthly = ['2026-05-14', '2026-06-14', '2026-07-14', '2026-08-14', '2026-09-14'].map((day, i) =>
      entry({ id: `m${i}`, amount: 2_500, merchant: 'Netflix', day, categoryId: 'sub' }),
    )
    const noisy = ['2026-06-02', '2026-07-19', '2026-09-03'].map((day, i) =>
      entry({ id: `n${i}`, amount: 3_300, merchant: 'Random Cafe', day }),
    )
    const found = detectRecurring(ledgerWith([...monthly, ...noisy]), '2026-09-20')
    expect(found.map((f) => f.name)).toEqual(['Netflix'])
    expect(found[0]?.period).toBe('month')
    expect(found[0]?.amount).toBe(2_500)
    expect(found[0]?.nextChargeAt).toBe('2026-10-14')
  })

  it('ignores a series that stopped charging long ago', () => {
    const stale = ['2025-01-10', '2025-02-10', '2025-03-10'].map((day, i) =>
      entry({ id: `s${i}`, amount: 900, merchant: 'Old Thing', day }),
    )
    expect(detectRecurring(ledgerWith(stale), '2026-09-20')).toHaveLength(0)
  })
})

describe('streak and month strip', () => {
  it('breaks the streak on a day with no data rather than extending it', () => {
    // 2026-09-18 logged and under standard, 2026-09-19 silent.
    const L = ledgerWith([entry({ id: 'x', amount: 100, day: '2026-09-18' })])
    expect(streak(L, '2026-09-20', Date.parse('2026-09-20T12:00:00'))).toBe(0)
  })

  it('counts an explicitly declared zero-spend day', () => {
    const L = fold([
      ev('s', H(1), { t: 'standard.set', monthlyFen: 800_000, perCategory: {} }),
      ev('z', H(2), { t: 'day.nospend', day: '2026-09-19', on: true }),
    ])
    expect(streak(L, '2026-09-20', Date.parse('2026-09-20T12:00:00'))).toBe(1)
  })

  it('draws one bar per day with the standard hairline', () => {
    const s = monthStrip(ledgerWith([entry({ id: 'x', amount: 50_000, day: '2026-09-08' })]), '2026-09', '2026-09-20', Date.parse('2026-09-20T12:00:00'))
    expect(s.bars).toHaveLength(30)
    expect(s.dailyStandard).toBe(Math.trunc(800_000 / 30))
    expect(s.bars.find((b) => b.day === '2026-09-08')?.spent).toBe(50_000)
    expect(s.bars.find((b) => b.day === '2026-09-25')?.future).toBe(true)
  })
})

describe('statistics helpers', () => {
  it('takes a median of both parities', () => {
    expect(median([3, 1, 2])).toBe(2)
    expect(median([4, 1, 2, 3])).toBe(3)
    expect(median([])).toBe(0)
  })
  it('measures spread', () => {
    expect(stddev([5, 5, 5])).toBe(0)
    expect(stddev([1, 3])).toBe(1)
  })
})

describe('local dates', () => {
  it('files a late-night purchase on the day it happened locally', () => {
    const nearMidnight = new Date(2026, 8, 8, 23, 40)
    expect(toDay(nearMidnight)).toBe('2026-09-08')
  })
})
