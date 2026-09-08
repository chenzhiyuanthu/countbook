/**
 * Every date in the ledger is a local civil date — 'YYYY-MM-DD' — never a UTC
 * instant. A purchase made at 23:40 belongs to that day in the user's own
 * timezone, and a ledger that shifts entries across midnight when you fly is
 * broken. Timestamps (epoch ms) exist separately, for ordering only.
 */

export type Day = string // 'YYYY-MM-DD'
export type Month = string // 'YYYY-MM'

const p2 = (n: number) => String(n).padStart(2, '0')

export function toDay(d: Date): Day {
  return `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`
}

export function fromDay(day: Day): Date {
  const [y = 0, m = 1, d = 1] = day.split('-').map(Number)
  return new Date(y, m - 1, d)
}

export const monthOf = (day: Day): Month => day.slice(0, 7)

export function daysInMonth(month: Month): number {
  const [y = 0, m = 1] = month.split('-').map(Number)
  return new Date(y, m, 0).getDate()
}

export function dayOfMonth(month: Month, dom: number): Day {
  return `${month}-${p2(dom)}`
}

export function addDays(day: Day, n: number): Day {
  const d = fromDay(day)
  d.setDate(d.getDate() + n)
  return toDay(d)
}

export function diffDays(a: Day, b: Day): number {
  // Compare at noon so a DST transition inside the interval cannot round the
  // difference to 0.5 of a day and truncate wrong.
  const x = fromDay(a); x.setHours(12)
  const y = fromDay(b); y.setHours(12)
  return Math.round((y.getTime() - x.getTime()) / 86_400_000)
}

/** 0 = Sunday, matching Rules.reckoningWeekday. */
export const weekdayOf = (day: Day): number => fromDay(day).getDay()

export const isWeekend = (day: Day): boolean => weekdayOf(day) % 6 === 0

export function allDaysOf(month: Month): Day[] {
  const n = daysInMonth(month)
  const out: Day[] = []
  for (let i = 1; i <= n; i++) out.push(dayOfMonth(month, i))
  return out
}

export function addMonths(month: Month, n: number): Month {
  const [y = 0, m = 1] = month.split('-').map(Number)
  const d = new Date(y, m - 1 + n, 1)
  return `${d.getFullYear()}-${p2(d.getMonth() + 1)}`
}

/** Inclusive of today: on the 20th of a 31-day month this is 12. */
export function daysRemainingInMonth(today: Day): number {
  return daysInMonth(monthOf(today)) - Number(today.slice(8, 10)) + 1
}

/** The 7 days ending today, oldest first. */
export function lastNDays(today: Day, n: number): Day[] {
  const out: Day[] = []
  for (let i = n - 1; i >= 0; i--) out.push(addDays(today, -i))
  return out
}
