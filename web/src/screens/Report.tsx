import { useCallback, useMemo, useState, type ReactNode } from 'react'
import { useStore } from '../app/store'
import { Money, MoneyText } from '../ui/Money'
import { Button, EmptyState, Label, ProgressRule, Rule } from '../ui/primitives'
import { DeviationBars, HourScatter, RegretBlocks, YearLedger } from '../ui/charts'
import { Glyph, type GlyphName } from '../ui/icons'
import {
  cashflowOfMonth,
  cashflowOfYear,
  deviationByCategory,
  hourScatter,
  inMonth,
  median,
  regret,
  regretAsWishObject,
  spendsOf,
  standardAt,
} from '../core/compute'
import { addMonths, dayOfMonth, daysInMonth, fromDay, monthOf } from '../core/date'
import type { Day, Month } from '../core/date'
import type { Fen } from '../core/money'
import './Report.css'

/**
 * The retrospective judgement, printed as a statement rather than shown as a
 * dashboard. Nothing here is actionable and nothing here is encouraging: the
 * page exists so the figures can be found by someone who goes looking, which is
 * why 后悔 lives on this screen and on no other.
 */

/** The whole page stays silent until there is a fortnight to read. */
const MIN_RECORDED_DAYS = 14
const MIN_DEVIATION_DAYS = 14
const MIN_HOUR_SAMPLE = 40
/** Ordering after this hour is the pattern the scatter exists to expose. */
const LATE_HOUR = 22

/** A section title with its mark before it, in the title's own grey. */
function Head({ glyph, title, trailing }: { glyph: GlyphName; title: string; trailing?: ReactNode }) {
  return (
    <div className="section__head">
      <span className="report__title-row">
        <span className="report__glyph"><Glyph name={glyph} /></span>
        <Label>{title}</Label>
      </span>
      {trailing ?? null}
    </div>
  )
}

interface CategoryRow {
  categoryId: string
  count: number
  median: Fen
  max: Fen
  regret: Fen
  judged: number
}

export default function Report() {
  const { ledger, today, now, t, locale } = useStore()
  const [month, setMonth] = useState<Month>(() => monthOf(today))

  const currency = ledger.settings.currency
  const currentMonth = monthOf(today)
  const year = month.slice(0, 4)

  // A statement is read at its own closing date, not at today's: a month that
  // has ended is reported as it stood on its last day.
  const asOf: Day = month >= currentMonth ? today : dayOfMonth(month, daysInMonth(month))

  const spends = useMemo(() => spendsOf(ledger), [ledger])
  const monthSpends = useMemo(() => inMonth(spends, month), [spends, month])

  const recordedDays = useMemo(() => {
    const days = new Set<Day>(ledger.noSpendDays)
    for (const e of spends) days.add(e.day)
    return days.size
  }, [ledger.noSpendDays, spends])

  const nameOf = useCallback(
    (id: string): string => {
      const c = ledger.categories.get(id)
      if (!c) return id
      return locale === 'en' ? c.nameEn : c.name
    },
    [ledger.categories, locale],
  )

  const r = useMemo(() => regret(ledger, asOf), [ledger, asOf])
  const flow = useMemo(() => cashflowOfMonth(ledger, month), [ledger, month])
  const yearFlow = useMemo(() => cashflowOfYear(ledger, year), [ledger, year])
  const wish = useMemo(() => regretAsWishObject(ledger, r.year), [ledger, r.year])

  const categoryRows = useMemo<CategoryRow[]>(() => {
    const by = new Map<string, { amounts: Fen[]; regret: Fen; judged: number }>()
    for (const e of monthSpends) {
      const row = by.get(e.categoryId) ?? { amounts: [], regret: 0, judged: 0 }
      row.amounts.push(e.effective)
      if (e.worthIt !== undefined) row.judged++
      if (e.worthIt === false) row.regret += e.effective
      by.set(e.categoryId, row)
    }
    return [...by.entries()]
      .map(([categoryId, v]) => ({
        categoryId,
        count: v.amounts.length,
        median: median(v.amounts),
        max: v.amounts.reduce((m, a) => Math.max(m, a), 0),
        regret: v.regret,
        judged: v.judged,
      }))
      // Amount-weighted, so the category that cost the most regret is read first.
      .sort((a, b) => b.regret - a.regret || b.max - a.max)
  }, [monthSpends])

  const regretByCategoryId = useMemo(
    () => new Map(categoryRows.map((row) => [row.categoryId, row])),
    [categoryRows],
  )

  const deviations = useMemo(() => {
    // A category with no standard has nothing to deviate from; it is left to
    // the table rather than drawn against an implied zero.
    const rows = deviationByCategory(ledger, month, now).filter((d) => d.standard > 0)
    return rows.sort((a, b) => {
      const ja = regretByCategoryId.get(a.categoryId)?.judged ?? 0
      const jb = regretByCategoryId.get(b.categoryId)?.judged ?? 0
      if ((ja > 0) !== (jb > 0)) return ja > 0 ? -1 : 1
      if (ja > 0 && jb > 0) {
        const byRegret = (regretByCategoryId.get(b.categoryId)?.regret ?? 0) - (regretByCategoryId.get(a.categoryId)?.regret ?? 0)
        if (byRegret !== 0) return byRegret
      }
      return b.delta - a.delta
    })
  }, [ledger, month, now, regretByCategoryId])

  const elapsedDays = month === currentMonth ? Number(today.slice(8)) : daysInMonth(month)
  const deviationShort = Math.max(0, MIN_DEVIATION_DAYS - elapsedDays)

  const hours = useMemo(() => hourScatter(ledger, today), [ledger, today])
  const hourTotal = hours.reduce((a, h) => a + h.count, 0)
  const late = hours
    .filter((h) => h.hour >= LATE_HOUR)
    .reduce((a, h) => ({ count: a.count + h.count, sum: a.sum + h.sum }), { count: 0, sum: 0 })

  const yearMonths = useMemo(() => {
    const spentBy = new Map<Month, Fen>()
    for (const e of spends) {
      if (!e.day.startsWith(year)) continue
      const m = monthOf(e.day)
      spentBy.set(m, (spentBy.get(m) ?? 0) + e.effective)
    }
    const last = year === currentMonth.slice(0, 4) ? currentMonth : `${year}-12`
    const recorded = [...spentBy.keys()].sort()
    const first = recorded[0] ?? `${year}-01`
    const rows: { month: Month; spent: Fen; standard: Fen }[] = []
    for (let m = first; m <= last && rows.length < 12; m = addMonths(m, 1)) {
      // The standard as it stood when the month closed, not as it stands now:
      // a raised line must not retroactively forgive a month it was not set for.
      const closedAt = Math.min(now, fromDay(dayOfMonth(m, daysInMonth(m))).getTime())
      rows.push({ month: m, spent: spentBy.get(m) ?? 0, standard: standardAt(ledger, closedAt).monthlyFen })
    }
    return rows
  }, [spends, year, currentMonth, now, ledger])

  const head = (
    <header className="report__head">
      <h1 className="t-label report__title">{t('report.title')}</h1>
      <div className="report__month">
        <Button variant="quiet" ariaLabel={t('report.prevMonth')} onClick={() => setMonth(addMonths(month, -1))}>
          ‹
        </Button>
        <span className="t-body ink-900 report__monthLabel">
          {t('report.monthTitle', { year, month: month.slice(5) })}
        </span>
        <Button
          variant="quiet"
          ariaLabel={t('report.nextMonth')}
          disabled={month >= currentMonth}
          onClick={() => setMonth(addMonths(month, 1))}
        >
          ›
        </Button>
      </div>
    </header>
  )

  // Plain arithmetic, not a judgement, so it is not held behind the fortnight
  // the rest of the page waits for: what came in, what went out, and the
  // difference, in the ledger's currency. A foreign receipt was converted when
  // it was written, so nothing here depends on today's rate.
  const cashflow = (
    <section className="section report__cashflow">
      <Head glyph="cashflow" title={t('report.cashflow')} />
      <div className="report__figures">
        <div className="report__figure">
          <Label>{t('report.income')}</Label>
          <Money fen={flow.income} size="section" role="credit" currency={currency} />
        </div>
        <div className="report__figure">
          <Label>{t('report.spend')}</Label>
          <Money fen={flow.spend} size="section" role="debit" currency={currency} />
        </div>
        <div className="report__figure">
          <Label>{t('report.net')}</Label>
          <Money fen={flow.net} size="section" role={flow.net < 0 ? 'over' : 'neutral'} currency={currency} />
        </div>
      </div>
      {flow.incomeByCategory.length ? (
        <dl className="report__sources">
          <dt className="t-label report__sourcesLabel">{t('report.incomeBy')}</dt>
          {flow.incomeByCategory.map((row) => (
            <div key={row.categoryId} className="report__source">
              <dd className="t-body ink-700">{nameOf(row.categoryId)}</dd>
              <dd className="report__num">
                <Money fen={row.amount} size="body" role="neutral" currency={currency} />
              </dd>
            </div>
          ))}
        </dl>
      ) : null}
      <dl className="report__yearFlow" aria-label={t('report.thisYear')}>
        <dt className="t-label ink-500">{t('report.thisYear')}</dt>
        {(
          [
            ['report.income', yearFlow.income, 'neutral'],
            ['report.spend', yearFlow.spend, 'neutral'],
            ['report.net', yearFlow.net, yearFlow.net < 0 ? 'over' : 'neutral'],
          ] as const
        ).map(([key, fen, role]) => (
          <div key={key} className="report__yearItem">
            <dt className="t-label ink-500">{t(key)}</dt>
            <dd><Money fen={fen} size="body" role={role} currency={currency} /></dd>
          </div>
        ))}
      </dl>
    </section>
  )

  if (recordedDays < MIN_RECORDED_DAYS) {
    return (
      <div className="column report">
        {head}
        <Rule strong />
        {cashflow}
        <Rule strong />
        <EmptyState title={t('report.empty')} />
      </div>
    )
  }

  return (
    <div className="column report">
      {head}
      <Rule strong />
      {cashflow}

      <Rule strong />
      <section className="section report__regret">
        <Head glyph="regret" title={t('report.regretTitle')} />
        <div className="report__figures">
          <div className="report__figure">
            <Label>{t('report.regretMonth')}</Label>
            <Money fen={r.month} size="section" role="regret" currency={currency} />
          </div>
          <div className="report__figure">
            <Label>{t('report.regretYear')}</Label>
            <Money fen={r.year} size="section" role="regret" currency={currency} />
          </div>
        </div>
        {wish ? (
          <div className="report__wish">
            <p className="t-body report__wishLine">
              {t('report.wishFraction', { name: wish.name, percent: `${Math.round(wish.fraction * 100)}%` })}
            </p>
            <ProgressRule fraction={wish.fraction} tone="regret" />
          </div>
        ) : null}
      </section>

      <Rule strong />
      <section className="section">
        <Head glyph="deviation" title={t('report.deviation')} />
        {deviations.length === 0 ? (
          <p className="report__gate t-body ink-700">{t('report.noStandard')}</p>
        ) : deviationShort > 0 ? (
          <p className="report__gate t-body ink-700">{t('report.deviationGate', { n: deviationShort })}</p>
        ) : (
          <DeviationBars rows={deviations} nameOf={nameOf} />
        )}
      </section>

      <Rule strong />
      <section className="section">
        <Head glyph="rate" title={t('report.rate')} />
        <RegretBlocks judged={r.judged} notWorth={r.notWorth} />
      </section>

      <Rule strong />
      <section className="section">
        <Head glyph="categories" title={t('report.byCategory')} />
        {categoryRows.length === 0 ? (
          <p className="report__gate t-body ink-500">{t('report.tableEmpty')}</p>
        ) : (
          <table className="report__table">
            <thead>
              <tr>
                <th scope="col" className="t-label">{t('report.tableCategory')}</th>
                <th scope="col" className="t-label report__num">{t('report.tableCount')}</th>
                <th scope="col" className="t-label report__num">{t('report.tableMedian')}</th>
                <th scope="col" className="t-label report__num">{t('report.tableMax')}</th>
                <th scope="col" className="t-label report__num">{t('report.tableRegret')}</th>
              </tr>
            </thead>
            <tbody>
              {categoryRows.map((row) => (
                <tr key={row.categoryId}>
                  <th scope="row" className="t-body ink-700 report__cat">{nameOf(row.categoryId)}</th>
                  <td className="t-body ink-700 report__num">{row.count}</td>
                  <td className="report__num"><Money fen={row.median} size="body" role="neutral" currency={currency} /></td>
                  <td className="report__num"><Money fen={row.max} size="body" role="neutral" currency={currency} /></td>
                  <td className="report__num"><Money fen={row.regret} size="body" role="neutral" currency={currency} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <Rule strong />
      <section className="section">
        <Head glyph="hours" title={t('report.hours')} />
        {hourTotal < MIN_HOUR_SAMPLE ? (
          <p className="report__gate t-body ink-700">
            {t('report.hourGate', { n: MIN_HOUR_SAMPLE - hourTotal })}
          </p>
        ) : (
          <>
            <HourScatter data={hours} />
            <p className="t-body ink-500 report__note">
              {t('report.hourLate', { hh: String(LATE_HOUR), n: late.count, sum: MoneyText(late.sum, currency) })}
            </p>
          </>
        )}
      </section>

      <Rule strong />
      <section className="section">
        <Head glyph="year" title={t('report.year')} trailing={<span className="t-label t-mono">{year}</span>} />
        <YearLedger months={yearMonths} />
      </section>
    </div>
  )
}
