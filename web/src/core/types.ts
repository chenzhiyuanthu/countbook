import type { Fen } from './money'
import type { Day } from './date'

/**
 * 必要 / 想要 / 冲动 — stamped at the moment of spending, never inferred and
 * never defaulted. The stamp is the whole mechanism: it is the one moment the
 * app makes you look at what you are doing, and a default would let you skip it.
 */
export type Intent = 'need' | 'want' | 'impulse'

export type EntryKind = 'spend' | 'income'

export interface Entry {
  id: string
  kind: EntryKind
  /** Always positive; `kind` carries the direction. */
  amount: Fen
  currency: string
  categoryId: string
  /** Required on spend, null on income — there is nothing to judge about a salary. */
  intent: Intent | null
  note: string
  /** Normalised payee string; the recurring detector groups on it. */
  merchant: string
  day: Day
  createdAt: number
  /** 一句话，写给三天后的自己 — optional, only offered on large 想要/冲动. */
  promise?: string
  /** Set by 周日审判. Undefined means unjudged. */
  worthIt?: boolean
  reviewedAt?: number
  /** 稍后 count; at Rules.deferralLimit the entry auto-records 不值. */
  deferrals?: number
  /** Present when the entry was created by resolving a want-list item. */
  wishId?: string
  subId?: string
}

/**
 * A sealed month is not edited, it is corrected. The original row stays printed
 * and the correction is printed beneath it, which is what makes the ledger
 * worth trusting: you can see that you changed your mind, and when.
 */
export interface Correction {
  id: string
  targetId: string
  amount: Fen
  reason: string
  at: number
}

export interface Voidance {
  id: string
  targetId: string
  reason: string
  at: number
}

export interface Category {
  id: string
  name: string
  nameEn: string
  kind: EntryKind
  order: number
  archived?: boolean
}

/** 待购 — an intended purchase held inside a cooling period. */
export interface Wish {
  id: string
  name: string
  price: Fen
  note?: string
  createdAt: number
  /** createdAt + clamp(ceil(price/¥100), 1, 14) days. */
  unlockAt: number
  outcome?: 'bought' | 'abstained'
  resolvedAt?: number
  entryId?: string
}

export type SubPeriod = 'week' | 'month' | 'quarter' | 'year'

/**
 * Detected subscriptions start `unclaimed` on purpose. A passive "we found
 * these" list gets ignored; requiring an explicit 保留 or 待退订 per row flips
 * the default from "it keeps charging" to "you decided".
 */
export type SubStatus = 'unclaimed' | 'keep' | 'pending-cancel' | 'cancelled'

export interface Sub {
  id: string
  name: string
  amount: Fen
  period: SubPeriod
  categoryId: string
  /** Day of the first observed charge — the annualisation anchor. */
  firstChargedAt: Day
  nextChargeAt: Day
  status: SubStatus
  cancelledAt?: Day
  /** Optional one-tap usage log; yields 每次使用 ¥37.5. */
  usageDays?: Day[]
  detected?: boolean
}

/** 标准线 — the line you are measured against, set by you, revised on the record. */
export interface StandardRevision {
  id: string
  at: number
  monthlyFen: Fen
  perCategory: Record<string, Fen>
  reason?: string
}

export interface Settings {
  currency: string
  locale: 'zh-CN' | 'en'
  theme: 'system' | 'light' | 'dark'
  /** Entries below this are counted as a class — the 小额漏水 strip. */
  leakCeilingFen: Fen
  /** At or above this, the capture sheet offers 挂起 instead of an immediate save. */
  coolingFloorFen: Fen
  reckoningWeekday: number
  reckoningHour: number
  /** 心愿物 — turns the abstract year-to-date regret figure into a fraction of a real object. */
  wishObject?: { name: string; priceFen: Fen }
  /** Set once the user has been shown, and dismissed, the first-run standard proposal. */
  standardAccepted?: boolean
}

/** The folded ledger: the only thing the UI ever reads. */
export interface Ledger {
  entries: Map<string, Entry>
  /** Ids removed while their month was still open. Patches on these are dropped. */
  tombstones: Set<string>
  corrections: Correction[]
  voids: Voidance[]
  categories: Map<string, Category>
  wishes: Map<string, Wish>
  subs: Map<string, Sub>
  standards: StandardRevision[]
  settings: Settings
  /** Days explicitly marked 今天没花钱, so silence is never scored as discipline. */
  noSpendDays: Set<Day>
}
