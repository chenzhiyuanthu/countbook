import { useMemo, useState } from 'react'
import { useStore } from '../app/store'
import type { StringKey } from '../app/i18n'
import { available, effective, leak, monthStrip, reckoningQueue, streak } from '../core/compute'
import type { EffectiveEntry } from '../core/compute'
import { fromDay, monthOf } from '../core/date'
import type { Day } from '../core/date'
import { formatYuan } from '../core/money'
import type { Fen } from '../core/money'
import type { Intent, Ledger } from '../core/types'
import { MonthStrip } from '../ui/charts'
import { ChevronDown, ChevronRight, ChevronUp } from '../ui/icons'
import { Money, MoneyText } from '../ui/Money'
import { Rule } from '../ui/primitives'
import './Today.css'

/** 今天没花钱 is offered late in the day only: claimed at noon it is a guess,
    claimed at eight it is a statement (SCREENS.md §3.4 T11). */
const NOSPEND_HOUR = 20

/** Below three logged days the strip would draw a shape out of two dots. */
const STRIP_MIN_DAYS = 3

const STAMP: Record<Intent, StringKey> = {
  need: 'today.stampNeed',
  want: 'today.stampWant',
  impulse: 'today.stampImpulse',
}

function spendsOn(L: Ledger, day: Day): EffectiveEntry[] {
  return [...effective(L).values()]
    .filter((e) => e.day === day && e.kind === 'spend')
    .sort((a, b) => a.createdAt - b.createdAt)
}

function clock(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

/**
 * One question, answered above the fold: how much is left today, and am I
 * already past it. Everything below the hero exists to show where that figure
 * came from — the ledger has to be able to prove its own arithmetic.
 */
export default function Today({ onCapture, onReckon }: { onCapture(): void; onReckon(): void }) {
  const { ledger, today, now, t, locale, commit } = useStore()
  const [derivation, setDerivation] = useState(false)
  const [scrubbed, setScrubbed] = useState<Day | null>(null)

  const month = monthOf(today)
  const figure = useMemo(() => available(ledger, today, now), [ledger, today, now])
  const strip = useMemo(() => monthStrip(ledger, month, today, now), [ledger, month, today, now])
  const drip = useMemo(() => leak(ledger, today), [ledger, today])
  const held = useMemo(() => streak(ledger, today, now), [ledger, today, now])
  const queue = useMemo(() => reckoningQueue(ledger, today), [ledger, today])
  const rows = useMemo(() => spendsOn(ledger, today), [ledger, today])

  const hasStandard = figure.standard > 0
  const over = hasStandard && figure.perDay < 0
  const dayTotal: Fen = rows.reduce((sum, e) => sum + e.effective, 0)
  const monthEmpty = strip.bars.every((b) => b.spent === 0)

  const loggedDays = strip.bars.filter((b) => !b.future && b.logged).length
  const stripReady = loggedDays >= STRIP_MIN_DAYS

  const marked = ledger.noSpendDays.has(today)
  const clockHour = new Date(now).getHours()
  const offerNoSpend = rows.length === 0 && !marked && clockHour >= NOSPEND_HOUR

  const settings = ledger.settings
  const at = new Date(now)
  const reckoningDue =
    at.getDay() === settings.reckoningWeekday && at.getHours() >= settings.reckoningHour
  const offerReckoning = reckoningDue && queue.length > 0

  const monthName = useMemo(
    () => new Intl.DateTimeFormat(locale, { month: 'long' }).format(fromDay(today)),
    [locale, today],
  )

  const cursor = scrubbed === null ? undefined : strip.bars.find((b) => b.day === scrubbed)
  const stripReadout = cursor
    ? t('chart.stripDay', { date: cursor.day.slice(5), amount: formatYuan(cursor.spent) })
    : strip.dailyStandard > 0
      ? t('chart.standardPerDay', { amount: formatYuan(strip.dailyStandard) })
      : ''

  return (
    <div className={over ? 'today column today--over' : 'today column'}>
      <section className="today__hero" aria-live="polite">
        <span className="t-label today__heroLabel">{t('today.available')}</span>
        {hasStandard ? (
          <Money fen={figure.perDay} size="hero" role={over ? 'allowance' : 'neutral'} />
        ) : (
          <span className="t-hero today__blank" aria-hidden="true">
            ——
          </span>
        )}
      </section>

      <Rule broken={over} />

      {hasStandard ? (
        <>
          <button
            type="button"
            className="today__provenance"
            aria-expanded={derivation}
            aria-controls="today-derivation"
            onClick={() => setDerivation((was) => !was)}
          >
            <span className="t-label today__provenanceText">
              {t('today.provenance', {
                standard: MoneyText(figure.standard),
                spent: MoneyText(figure.spent),
                fixed: MoneyText(figure.fixedRemaining),
                days: figure.daysLeft,
              })}
            </span>
            <span className="today__chevron ink-300">
              {derivation ? <ChevronUp /> : <ChevronDown />}
            </span>
          </button>

          {derivation && (
            <dl className="today__derivation" id="today-derivation">
              <div className="today__derivationRow">
                <dt className="t-label">{t('today.detailStandard')}</dt>
                <dd className="today__derivationValue">
                  <Money fen={figure.standard} size="row" />
                </dd>
              </div>
              <div className="today__derivationRow">
                <dt className="t-label">{t('today.detailSpent')}</dt>
                <dd className="today__derivationValue">
                  <Money fen={figure.spent} size="row" />
                </dd>
              </div>
              <div className="today__derivationRow">
                <dt className="t-label">{t('today.detailFixed')}</dt>
                <dd className="today__derivationValue">
                  <Money fen={figure.fixedRemaining} size="row" />
                </dd>
              </div>
              <div className="today__derivationRow">
                <dt className="t-label">{t('today.detailDays')}</dt>
                <dd className="today__derivationValue t-row">
                  {t('today.daysValue', { n: figure.daysLeft })}
                </dd>
              </div>
            </dl>
          )}

          {over && figure.recoveryDays > 0 && (
            <p className="t-body today__trajectory">
              {t('today.recovery', { days: figure.recoveryDays })}
            </p>
          )}
        </>
      ) : (
        <div className="today__firstRun">
          <p className="t-body today__firstRunLine">{t('today.noStandard')}</p>
          <p className="t-body today__firstRunHint">{t('today.noStandardHint')}</p>
        </div>
      )}

      <section className="section today__strip">
        <div className="section__head">
          <span className="t-label">{t('today.stripTitle', { month: monthName })}</span>
          <span className="t-label today__stripReadout">{stripReadout}</span>
        </div>
        {stripReady ? (
          <MonthStrip data={strip} onScrub={setScrubbed} />
        ) : (
          <p className="t-body today__gate">
            {t('today.stripGate', { n: STRIP_MIN_DAYS - loggedDays })}
          </p>
        )}
      </section>

      {drip.count > 0 && (
        <>
          <Rule />
          <p className="t-body today__leak">
            {drip.equivalent > 0
              ? t('today.leak', {
                  count: drip.count,
                  sum: MoneyText(drip.sum),
                  times: drip.equivalent.toFixed(1),
                })
              : t('today.leakBare', { count: drip.count, sum: MoneyText(drip.sum) })}
          </p>
        </>
      )}

      {offerNoSpend && (
        <>
          <Rule />
          <button
            type="button"
            className="today__line today__lineTap"
            onClick={() => commit({ t: 'day.nospend', day: today, on: true })}
          >
            <span className="t-body ink-700">{t('today.nospend')}</span>
          </button>
        </>
      )}

      {marked && (
        <>
          <Rule />
          <p className="today__line t-body ink-500">{t('today.nospendDone')}</p>
        </>
      )}

      {offerReckoning && (
        <>
          <Rule />
          <button type="button" className="today__line today__lineTap" onClick={onReckon}>
            <span className="t-body ink-700">{t('today.verdict', { n: queue.length })}</span>
            <span className="today__chevron ink-300">
              <ChevronRight />
            </span>
          </button>
        </>
      )}

      {held > 0 && (
        <>
          <Rule />
          <p className="today__line t-label">{t('today.streak', { n: held })}</p>
        </>
      )}

      <section className="section today__list">
        <div className="section__head">
          <span className="t-label">{t('common.today')}</span>
          <Money fen={dayTotal} size="row" />
        </div>
        <Rule strong />
        {rows.length > 0 ? (
          <ul>
            {rows.map((e) => (
              <li key={e.id} className="row today__entry">
                <span className="today__time">{clock(e.createdAt)}</span>
                <span className="today__category">
                  {locale === 'en'
                    ? (ledger.categories.get(e.categoryId)?.nameEn ?? '')
                    : (ledger.categories.get(e.categoryId)?.name ?? '')}
                </span>
                <span className="today__note row__grow row__truncate">
                  {e.note || e.merchant}
                </span>
                <span className={e.intent ? `today__stamp today__stamp--${e.intent}` : 'today__stamp'}>
                  {e.intent ? t(STAMP[e.intent]) : ''}
                </span>
                <span className="today__amount">
                  <Money fen={e.effective} size="row" />
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <div className="today__empty">
            <p className="t-body ink-700">
              {monthEmpty ? t('today.emptyMonth') : t('today.emptyToday')}
            </p>
            {monthEmpty && (
              <button type="button" className="today__emptyAction t-body" onClick={onCapture}>
                {t('capture.title')}
              </button>
            )}
          </div>
        )}
      </section>
    </div>
  )
}
