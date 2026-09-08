import { useEffect, useId, useMemo, useState } from 'react'
import { useStore } from '../app/store'
import { Money, MoneyText } from '../ui/Money'
import { Button, EmptyState, Field, Label, Rule, Ring, Sheet } from '../ui/primitives'
import { AnnualBar } from '../ui/charts'
import { Plus } from '../ui/icons'
import { coolingDays, detectRecurring, savedByCancelling, subViews, wishStats } from '../core/compute'
import type { Detected } from '../core/compute'
import { diffDays, toDay } from '../core/date'
import { parse } from '../core/money'
import { newId } from '../core/id'
import type { Sub, SubPeriod, Wish } from '../core/types'
import './Wants.css'

const DAY_MS = 86_400_000

/** Unhandled for a week: stated at the end of the row, never as a reminder. */
const STALE_DAYS = 7

/** Below three uses a per-use figure is arithmetic noise, not information. */
const PER_USE_MIN_USES = 3

const p2 = (n: number): string => String(n).padStart(2, '0')

/** 其他 is the fallback category and PRODUCT §6 forbids disabling it. */
const WISH_CATEGORY = 'other'

const PERIOD_KEY = {
  week: 'subs.period.week',
  month: 'subs.period.month',
  quarter: 'subs.period.quarter',
  year: 'subs.period.year',
} as const satisfies Record<SubPeriod, string>

/**
 * One timer for every arc and countdown on the screen, stepped on the wall
 * clock so they all change together (DESIGN.md §5.10). Per-row timers would
 * repaint the list once per row per minute and drift apart while doing it.
 */
function useMinute(active: boolean): number {
  const [tick, setTick] = useState(() => Date.now())
  useEffect(() => {
    if (!active) return
    let interval = 0
    const timeout = window.setTimeout(() => {
      setTick(Date.now())
      interval = window.setInterval(() => setTick(Date.now()), 60_000)
    }, 60_000 - (Date.now() % 60_000))
    return () => {
      window.clearTimeout(timeout)
      window.clearInterval(interval)
    }
  }, [active])
  return tick
}

function remainingOf(ms: number): { days: number; time: string } {
  const rest = Math.max(0, ms)
  const hours = Math.floor((rest % DAY_MS) / 3_600_000)
  const minutes = Math.floor((rest % 3_600_000) / 60_000)
  return { days: Math.floor(rest / DAY_MS), time: `${p2(hours)}:${p2(minutes)}` }
}

/** Stable across devices, so two of them claiming the same series converge. */
const detectedId = (d: Detected): string => `detected:${d.key}:${d.amount}:${d.period}`

export default function Wants({ onCapture }: { onCapture(): void }) {
  const { ledger, today, now, t, locale, commit, undo, toast } = useStore()
  const currency = ledger.settings.currency
  const headingId = useId()
  const subsHeadingId = useId()

  const [adding, setAdding] = useState(false)

  const wishes = useMemo(() => [...ledger.wishes.values()], [ledger.wishes])
  const pending = useMemo(() => wishes.filter((w) => !w.outcome), [wishes])
  const minute = useMinute(pending.length > 0)
  const nowMs = Math.max(now, minute)

  const stats = useMemo(() => wishStats(ledger, today, nowMs), [ledger, today, nowMs])

  const unlocked = useMemo(
    () => pending.filter((w) => w.unlockAt <= nowMs).sort((a, b) => a.unlockAt - b.unlockAt),
    [pending, nowMs],
  )
  const cooling = useMemo(
    () => pending.filter((w) => w.unlockAt > nowMs).sort((a, b) => a.unlockAt - b.unlockAt),
    [pending, nowMs],
  )
  const year = today.slice(0, 4)
  const archive = useMemo(
    () =>
      wishes
        .filter((w) => w.outcome === 'abstained' && w.resolvedAt !== undefined)
        .filter((w) => toDay(new Date(w.resolvedAt!)).startsWith(year))
        .sort((a, b) => (b.resolvedAt ?? 0) - (a.resolvedAt ?? 0)),
    [wishes, year],
  )


  const buy = (w: Wish) => {
    const at = Date.now()
    const entryId = newId()
    // The stamp is 想要 because the want list is the definition of 想要; the
    // entry is still an ordinary row and can be re-stamped in 账页.
    const added = commit({
      t: 'entry.add',
      entry: {
        id: entryId,
        kind: 'spend',
        amount: w.price,
        currency,
        categoryId: WISH_CATEGORY,
        intent: 'want',
        note: w.name,
        merchant: '',
        day: today,
        createdAt: at,
        wishId: w.id,
      },
    })
    const resolved = commit({ t: 'wish.resolve', target: w.id, outcome: 'bought', entryId })
    toast(t('wants.entered'), {
      label: t('ledger.undo'),
      run: () => {
        undo(resolved)
        undo(added)
      },
    })
  }

  const abstain = (w: Wish) => {
    const id = commit({ t: 'wish.resolve', target: w.id, outcome: 'abstained' })
    toast(t('wants.abstainedDone'), { label: t('ledger.undo'), run: () => undo(id) })
  }

  const remove = (w: Wish) => {
    const id = commit({ t: 'wish.remove', target: w.id })
    toast(t('wants.removed'), { label: t('ledger.undo'), run: () => undo(id) })
  }

  const views = useMemo(() => subViews(ledger, today), [ledger, today])
  const saved = useMemo(() => savedByCancelling(ledger, today), [ledger, today])
  const detected = useMemo(() => detectRecurring(ledger, today), [ledger, today])

  const active = views.rows.filter((r) => r.sub.status === 'keep' || r.sub.status === 'pending-cancel')
  const ended = views.rows.filter((r) => r.sub.status === 'cancelled')
  const unclaimed = detected.filter((d) => !ledger.subs.has(detectedId(d)))

  const nameOf = useMemo(() => {
    const map = new Map<string, string>()
    for (const c of ledger.categories.values()) map.set(c.id, locale === 'en' ? c.nameEn : c.name)
    return (id: string): string => map.get(id) ?? id
  }, [ledger.categories, locale])

  const claim = (d: Detected, status: 'keep' | 'pending-cancel') => {
    const sub: Sub = {
      id: detectedId(d),
      name: d.name,
      amount: d.amount,
      period: d.period,
      categoryId: d.categoryId,
      firstChargedAt: d.firstChargedAt,
      nextChargeAt: d.nextChargeAt,
      status,
      detected: true,
    }
    commit({ t: 'sub.upsert', sub })
  }

  const noWishes = unlocked.length === 0 && cooling.length === 0 && archive.length === 0
  const noSubs = views.rows.length === 0 && unclaimed.length === 0

  return (
    <div className="wants">
      <section className="column wants__section" aria-labelledby={headingId}>
        <header className="wants__head">
          <h1 className="t-label t-label--cjk wants__title" id={headingId}>{t('wants.title')}</h1>
          <p className="t-label t-label--cjk ink-500">{t('wants.abstainedYear')}</p>
          <div className={stats.abstainedYear === 0 ? 'wants__figure wants__figure--zero' : 'wants__figure'}>
            <Money fen={stats.abstainedYear} size="section" role="spared" currency={currency} />
          </div>
          <p className="t-micro ink-500 wants__notice">{t('wants.notifyWeb')}</p>
        </header>

        <Rule strong />

        {noWishes ? (
          <EmptyState
            title={t('wants.empty')}
            body={t('wants.emptyHint')}
            action={
              <Button onClick={() => setAdding(true)}>
                <Plus size={20} />
                {t('wants.add')}
              </Button>
            }
          />
        ) : null}

        {unlocked.length > 0 ? (
          <div className="wants__group">
            <Label>{t('wants.unlocked')}</Label>
            <ul>
              {unlocked.map((w) => {
                const stale = Math.floor((nowMs - w.unlockAt) / DAY_MS)
                return (
                  <li key={w.id} className="wants__unlocked">
                    <div className="row wants__row">
                      <span className="row__grow row__truncate t-body ink-700">{w.name}</span>
                      <span className="wants__amount">
                        <Money fen={w.price} size="row" role="neutral" currency={currency} />
                      </span>
                    </div>
                    <p className="t-body ink-700 wants__question">{t('wants.ready')}</p>
                    {stale >= STALE_DAYS ? (
                      <p className="t-micro ink-500 wants__stale">{t('wants.stale', { n: stale })}</p>
                    ) : null}
                    <div className="wants__flat">
                      <button
                        type="button"
                        className="t-body wants__flat-action"
                        onClick={() => buy(w)}
                        aria-label={`${t('wants.buy')} · ${w.name}`}
                      >
                        {t('wants.buy')}
                      </button>
                      <button
                        type="button"
                        className="t-body wants__flat-action"
                        onClick={() => abstain(w)}
                        aria-label={`${t('wants.abstain')} · ${w.name}`}
                      >
                        {t('wants.abstain')}
                      </button>
                    </div>
                  </li>
                )
              })}
            </ul>
          </div>
        ) : null}

        {cooling.length > 0 ? (
          <div className="wants__group">
            <Label>{t('wants.holding')}</Label>
            <ul>
              {cooling.map((w) => {
                const total = Math.max(1, w.unlockAt - w.createdAt)
                const left = remainingOf(w.unlockAt - nowMs)
                const countdown =
                  left.days > 0
                    ? t('wants.cooling', { days: left.days, time: left.time })
                    : t('wants.coolingHours', { time: left.time })
                return (
                  <li key={w.id} className="row wants__row wants__cooling">
                    <span className="wants__arc" aria-hidden="true">
                      <Ring fraction={(w.unlockAt - nowMs) / total} size={32} tone="held" />
                    </span>
                    <span className="row__grow wants__cooling-body">
                      <span className="row__truncate t-body ink-700 wants__name">{w.name}</span>
                      <span className="t-mono fig-held wants__countdown">{countdown}</span>
                      <button
                        type="button"
                        className="t-body wants__link"
                        onClick={() => remove(w)}
                        aria-label={`${t('wants.remove')} · ${w.name}`}
                      >
                        {t('wants.remove')}
                      </button>
                    </span>
                    <span className="wants__amount">
                      <Money fen={w.price} size="row" tone="held" currency={currency} />
                    </span>
                  </li>
                )
              })}
            </ul>
          </div>
        ) : null}

        {archive.length > 0 ? (
          <div className="wants__group">
            <Label>{t('wants.archive', { year })}</Label>
            <ul>
              {archive.map((w) => (
                <li key={w.id} className="row wants__row">
                  <span className="t-mono ink-500 wants__date">
                    {toDay(new Date(w.resolvedAt ?? 0)).slice(5)}
                  </span>
                  <span className="row__grow row__truncate t-body ink-700">{w.name}</span>
                  <span className="wants__amount">
                    <Money fen={w.price} size="row" role="spared" currency={currency} />
                  </span>
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {noWishes ? null : (
          <div className="wants__add">
            <Button onClick={() => setAdding(true)}>
              <Plus size={20} />
              {t('wants.add')}
            </Button>
          </div>
        )}
      </section>

      <section className="column wants__section" aria-labelledby={subsHeadingId}>
        <header className="wants__head">
          <h2 className="t-label t-label--cjk wants__title" id={subsHeadingId}>{t('subs.title')}</h2>
          <p className="t-label t-label--cjk ink-500">{t('subs.annualLabel')}</p>
          <div className="wants__figure">
            <Money fen={views.annual} size="section" role="neutral" currency={currency} />
          </div>
          <p className="t-micro ink-500">
            {t('subs.perDay', { amount: MoneyText(views.perDay, currency) })}
          </p>
        </header>

        {active.length > 0 ? (
          <div className="wants__bar">
            <AnnualBar rows={active.map((r) => ({ label: r.sub.name, annual: r.annual }))} />
          </div>
        ) : null}

        <Rule strong />

        {noSubs ? (
          <EmptyState
            title={t('subs.empty')}
            action={
              <button type="button" className="t-body wants__link" onClick={onCapture}>
                {t('capture.title')}
              </button>
            }
          />
        ) : null}

        {unclaimed.length > 0 ? (
          <div className="wants__group">
            <Label>{t('subs.unclaimedCount', { n: unclaimed.length })}</Label>
            <ul>
              {unclaimed.map((d) => (
                <li key={detectedId(d)} className="wants__unlocked">
                  <div className="row wants__row">
                    <span className="row__grow row__truncate t-body ink-700">{d.name}</span>
                    <span className="wants__amount">
                      <Money fen={d.amount} size="row" tone="held" currency={currency} />
                    </span>
                  </div>
                  <p className="t-body ink-500 wants__detail">
                    {t('subs.unclaimedRow', {
                      period: t(PERIOD_KEY[d.period]),
                      amount: MoneyText(d.amount, currency),
                      n: d.occurrences,
                    })}
                  </p>
                  <p className="t-micro ink-500">
                    {`${nameOf(d.categoryId)} · ${t('subs.next', { day: d.nextChargeAt })}`}
                  </p>
                  <div className="wants__flat">
                    <button
                      type="button"
                      className="t-body wants__flat-action"
                      onClick={() => claim(d, 'keep')}
                      aria-label={`${t('subs.keep')} · ${d.name}`}
                    >
                      {t('subs.keep')}
                    </button>
                    <button
                      type="button"
                      className="t-body wants__flat-action"
                      onClick={() => claim(d, 'pending-cancel')}
                      aria-label={`${t('subs.cancel')} · ${d.name}`}
                    >
                      {t('subs.cancel')}
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {views.rows.length > 0 ? (
          <div className="wants__group">
            <Label>{t('subs.active')}</Label>
            {active.length === 0 ? (
              <p className="t-body ink-700 wants__detail">{t('subs.emptyActive')}</p>
            ) : null}
            <ul>
              {active.map((r) => {
                const uses = r.sub.usageDays?.length ?? 0
                const second = [
                  t('subs.amountPer', {
                    period: t(PERIOD_KEY[r.sub.period]),
                    amount: MoneyText(r.sub.amount, currency),
                  }),
                  t('subs.paid', {
                    paid: MoneyText(r.paidSoFar, currency),
                    since: r.sub.firstChargedAt.slice(0, 7),
                  }),
                ].join(' · ')
                const third = [
                  t('subs.next', { day: r.sub.nextChargeAt }),
                  uses >= PER_USE_MIN_USES && r.perUse !== undefined
                    ? t('subs.perUse', { amount: MoneyText(r.perUse, currency) })
                    : '',
                ]
                  .filter(Boolean)
                  .join(' · ')
                return (
                  <li key={r.sub.id} className="wants__sub">
                    <div className="row wants__row">
                      <span className="row__grow row__truncate t-body ink-700">
                        {r.sub.name}
                        {r.sub.status === 'pending-cancel' ? (
                          <span className="t-mono fig-held wants__flag">{t('subs.pending')}</span>
                        ) : null}
                      </span>
                      <span className="wants__amount">
                        <span className="t-micro ink-500 wants__annual-label">{t('subs.annualLabel')}</span>
                        <Money fen={r.annual} size="row" role="neutral" currency={currency} />
                      </span>
                    </div>
                    <p className="t-body ink-500 wants__detail">{second}</p>
                    <p className="t-micro ink-500">{third}</p>
                    <div className="wants__row-actions">
                      <button
                        type="button"
                        className="t-body wants__link"
                        onClick={() => commit({ t: 'sub.use', target: r.sub.id, day: today })}
                        aria-label={`${t('subs.logUse')} · ${r.sub.name}`}
                      >
                        {t('subs.logUse')}
                      </button>
                      <button
                        type="button"
                        className="t-body wants__link"
                        onClick={() =>
                          commit({ t: 'sub.status', target: r.sub.id, status: 'cancelled', day: today })
                        }
                        aria-label={`${t('subs.markEnded')} · ${r.sub.name}`}
                      >
                        {t('subs.markEnded')}
                      </button>
                    </div>
                  </li>
                )
              })}
            </ul>
          </div>
        ) : null}

        {ended.length > 0 ? (
          <div className="wants__group">
            <div className="section__head">
              <Label>{t('subs.cancelled')}</Label>
              <span className="wants__amount">
                <Money fen={saved} size="row" role="spared" currency={currency} />
              </span>
            </div>
            <ul>
              {ended.map((r) => {
                const since = r.sub.cancelledAt ?? r.sub.nextChargeAt
                // The same accrual `savedByCancelling` sums, printed per row.
                const savedHere = Math.trunc((r.annual * Math.max(0, diffDays(since, today))) / 365)
                return (
                  <li key={r.sub.id} className="row wants__row">
                    <span className="row__grow wants__cooling-body">
                      <span className="row__truncate t-body ink-700">{r.sub.name}</span>
                      <span className="t-body ink-500">
                        {t('subs.endedRow', {
                          month: since.slice(0, 7),
                          amount: MoneyText(savedHere, currency),
                        })}
                      </span>
                    </span>
                  </li>
                )
              })}
            </ul>
          </div>
        ) : null}
      </section>

      {adding ? <AddWish onClose={() => setAdding(false)} /> : null}
    </div>
  )
}

function AddWish({ onClose }: { onClose: () => void }) {
  const { t, commit, ledger } = useStore()
  const [name, setName] = useState('')
  const [price, setPrice] = useState('')

  const parsed = parse(price)
  const valid = parsed !== null && parsed > 0 && name.trim() !== ''
  const days = parsed !== null && parsed > 0 ? coolingDays(parsed) : 0
  const until = toDay(new Date(Date.now() + days * DAY_MS))

  const submit = () => {
    if (!valid || parsed === null) return
    const at = Date.now()
    commit({
      t: 'wish.add',
      wish: {
        id: newId(),
        name: name.trim(),
        price: parsed,
        createdAt: at,
        unlockAt: at + coolingDays(parsed) * DAY_MS,
      },
    })
    onClose()
  }

  return (
    <Sheet onClose={onClose} title={t('wants.addTitle')}>
      <div className="wants__sheet">
        <Field
          label={t('wants.price')}
          value={price}
          onChange={setPrice}
          type="number"
          mono
          suffix={ledger.settings.currency === 'CNY' ? undefined : ledger.settings.currency}
          autoFocus
        />
        <Field label={t('wants.name')} value={name} onChange={setName} maxLength={24} />
        <Rule />
        {days > 0 ? (
          <p className="t-body ink-500">{t('wants.coolingCalc', { days, date: until })}</p>
        ) : null}
        <button type="button" className="t-body wants__held" onClick={submit} disabled={!valid}>
          {t('capture.suspend', { days })}
        </button>
      </div>
    </Sheet>
  )
}
