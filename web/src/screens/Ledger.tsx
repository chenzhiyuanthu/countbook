import { useEffect, useId, useMemo, useState } from 'react'
import { useStore } from '../app/store'
import { WEEKDAYS } from '../app/i18n'
import type { T } from '../app/i18n'
import { Money, MoneyText } from '../ui/Money'
import { Button, EmptyState, Field, Rule, Segmented, Sheet } from '../ui/primitives'
import { ChevronLeft, ChevronRight, MagnifyingGlass, XMark } from '../ui/icons'
import { effective, standardAt } from '../core/compute'
import type { EffectiveEntry } from '../core/compute'
import { dayOfMonth, daysInMonth, fromDay, monthOf, weekdayOf } from '../core/date'
import type { Day, Month } from '../core/date'
import { format, parse } from '../core/money'
import type { Fen } from '../core/money'
import type { Correction, Intent } from '../core/types'
import './Ledger.css'

/**
 * A month is sealed the moment the calendar rolls past it. There is no seal
 * event to read: the period is the calendar month, so the comparison is the
 * rule (PRODUCT §5.10).
 */
const isSealed = (month: Month, today: Day): boolean => month < monthOf(today)

const p2 = (n: number): string => String(n).padStart(2, '0')

const timeOf = (ms: number): string => {
  const d = new Date(ms)
  return `${p2(d.getHours())}:${p2(d.getMinutes())}`
}

/** SCREENS §5.4 L5. Long enough that a scan is not run per keystroke, short
    enough that the list never feels like it stopped listening. */
const SEARCH_DEBOUNCE_MS = 120

const INTENTS: Intent[] = ['need', 'want', 'impulse']

const INTENT_KEY = {
  need: 'capture.intent.need',
  want: 'capture.intent.want',
  impulse: 'capture.intent.impulse',
} as const

const GLYPH_KEY = {
  need: 'ledger.glyph.need',
  want: 'ledger.glyph.want',
  impulse: 'ledger.glyph.impulse',
} as const

type Verdict = 'unreviewed' | 'notWorth'

interface Filters {
  categories: Set<string>
  intents: Set<Intent>
  leak: boolean
  corrected: boolean
  verdict: Verdict | null
}

const EMPTY_FILTERS: Filters = {
  categories: new Set(),
  intents: new Set(),
  leak: false,
  corrected: false,
  verdict: null,
}

const isFiltered = (f: Filters): boolean =>
  f.categories.size > 0 || f.intents.size > 0 || f.leak || f.corrected || f.verdict !== null

/** `>100` `<30` `=68` are read as 元, because that is the unit people type. */
function amountQuery(raw: string): ((fen: Fen) => boolean) | null {
  const m = /^([<>=])\s*(\d+(?:\.\d{1,2})?)$/.exec(raw.trim())
  if (!m) return null
  const cut = parse(m[2] ?? '')
  if (cut === null) return null
  const op = m[1]
  return (fen) => (op === '>' ? fen > cut : op === '<' ? fen < cut : fen === cut)
}

/**
 * The audit trail as it is printed: each correction states the amount it
 * replaced, so the chain reads back to the amount first entered.
 */
function correctionLines(
  t: T,
  entry: EffectiveEntry,
  corrections: readonly Correction[],
): { id: string; line: string }[] {
  let previous = entry.amount
  return corrections.map((c) => {
    const line = t('ledger.correction', {
      from: MoneyText(previous, entry.currency),
      to: MoneyText(c.amount, entry.currency),
      reason: c.reason,
    })
    previous = c.amount
    return { id: c.id, line }
  })
}

export default function Ledger() {
  const { ledger, today, now, t, locale } = useStore()

  const [month, setMonth] = useState<Month>(() => monthOf(today))
  const [rawQuery, setRawQuery] = useState('')
  const [query, setQuery] = useState('')
  const [filters, setFilters] = useState<Filters>(EMPTY_FILTERS)
  const [hintOpen, setHintOpen] = useState(true)
  const [openId, setOpenId] = useState<string | null>(null)
  const [printedId, setPrintedId] = useState<string | null>(null)

  // useId's output carries punctuation that url(#…) cannot address.
  const hatchId = `hatch${useId().replace(/[^a-zA-Z0-9]/g, '')}`
  const searchId = `ledger${useId().replace(/[^a-zA-Z0-9]/g, '')}`

  useEffect(() => {
    const id = window.setTimeout(() => setQuery(rawQuery), SEARCH_DEBOUNCE_MS)
    return () => window.clearTimeout(id)
  }, [rawQuery])

  const eff = useMemo(() => effective(ledger), [ledger])
  const sealed = isSealed(month, today)

  const nameOf = useMemo(() => {
    const map = new Map<string, string>()
    for (const c of ledger.categories.values()) map.set(c.id, locale === 'en' ? c.nameEn : c.name)
    return (id: string): string => map.get(id) ?? id
  }, [ledger.categories, locale])

  const correctionsOf = useMemo(() => {
    const map = new Map<string, Correction[]>()
    for (const c of ledger.corrections) {
      const list = map.get(c.targetId)
      if (list) list.push(c)
      else map.set(c.targetId, [c])
    }
    return map
  }, [ledger.corrections])

  const bounds = useMemo(() => {
    let min = monthOf(today)
    let max = monthOf(today)
    for (const e of ledger.entries.values()) {
      const m = monthOf(e.day)
      if (m < min) min = m
      if (m > max) max = m
    }
    return { min, max }
  }, [ledger.entries, today])

  const monthRows = useMemo(
    () => [...eff.values()].filter((e) => monthOf(e.day) === month),
    [eff, month],
  )

  const monthTotal = useMemo(
    () => monthRows.reduce((a, e) => (e.kind === 'spend' ? a + e.effective : a), 0),
    [monthRows],
  )

  // A closed month is measured against the line that was standing when it
  // closed, not against a line revised since.
  const monthEndMs = fromDay(dayOfMonth(month, daysInMonth(month))).getTime() + 86_400_000 - 1
  const standard = standardAt(ledger, Math.min(now, monthEndMs)).monthlyFen
  const dayStandard = Math.floor(standard / daysInMonth(month))

  const categoriesPresent = useMemo(() => {
    const ids = new Set<string>()
    for (const e of monthRows) ids.add(e.categoryId)
    return [...ledger.categories.values()]
      .filter((c) => ids.has(c.id))
      .sort((a, b) => a.order - b.order)
  }, [monthRows, ledger.categories])

  const visible = useMemo(() => {
    const byAmount = amountQuery(query)
    const needle = byAmount ? '' : query.trim().toLowerCase()
    const ceiling = ledger.settings.leakCeilingFen
    return monthRows.filter((e) => {
      if (filters.categories.size && !filters.categories.has(e.categoryId)) return false
      if (filters.intents.size && (e.intent === null || !filters.intents.has(e.intent))) return false
      if (filters.leak && !(e.effective > 0 && e.effective < ceiling)) return false
      if (filters.corrected && !e.correction && !e.voidance) return false
      if (filters.verdict === 'unreviewed' && e.worthIt !== undefined) return false
      if (filters.verdict === 'notWorth' && e.worthIt !== false) return false
      if (byAmount) return byAmount(e.effective)
      if (!needle) return true
      const hay = `${e.note} ${e.merchant} ${nameOf(e.categoryId)} ${format(e.effective, e.currency)}`
      return hay.toLowerCase().includes(needle)
    })
  }, [monthRows, filters, query, nameOf, ledger.settings.leakCeilingFen])

  const days = useMemo(() => {
    const byDay = new Map<Day, EffectiveEntry[]>()
    for (const e of visible) {
      const list = byDay.get(e.day)
      if (list) list.push(e)
      else byDay.set(e.day, [e])
    }
    // A claimed no-spend day is a record too, so it gets its own section.
    if (!isFiltered(filters) && !query.trim()) {
      for (const d of ledger.noSpendDays) if (monthOf(d) === month && !byDay.has(d)) byDay.set(d, [])
    }
    return [...byDay.entries()]
      .sort((a, b) => (a[0] < b[0] ? 1 : -1))
      .map(([day, rows]) => ({
        day,
        rows: rows.sort((a, b) => b.createdAt - a.createdAt),
        total: rows.reduce((a, e) => (e.kind === 'spend' ? a + e.effective : a), 0),
      }))
  }, [visible, filters, query, ledger.noSpendDays, month])

  const goMonth = (step: number) => {
    const [y = 0, m = 1] = month.split('-').map(Number)
    const d = new Date(y, m - 1 + step, 1)
    setMonth(`${d.getFullYear()}-${p2(d.getMonth() + 1)}`)
    setHintOpen(true)
  }

  const clearAll = () => {
    setFilters(EMPTY_FILTERS)
    setRawQuery('')
    setQuery('')
  }

  const toggleCategory = (id: string) =>
    setFilters((f) => {
      const next = new Set(f.categories)
      if (!next.delete(id)) next.add(id)
      return { ...f, categories: next }
    })

  const toggleIntent = (i: Intent) =>
    setFilters((f) => {
      const next = new Set(f.intents)
      if (!next.delete(i)) next.add(i)
      return { ...f, intents: next }
    })

  // The two verdict words are one control: holding both at once would ask the
  // ledger for entries that are unjudged and judged, which is always nothing.
  const setVerdict = (v: Verdict) =>
    setFilters((f) => ({ ...f, verdict: f.verdict === v ? null : v }))

  const [year = '', mon = ''] = month.split('-')
  const open = openId === null ? undefined : eff.get(openId)

  return (
    <section className="ledger" aria-labelledby={`${searchId}-title`}>
      <div className="column">
        <header className="ledger__head">
          <h1 className="t-label ledger__title" id={`${searchId}-title`}>{t('ledger.title')}</h1>
          <div className="ledger__nav">
            <button
              type="button"
              className="ledger__step"
              onClick={() => goMonth(-1)}
              disabled={month <= bounds.min}
              aria-label={t('ledger.prevMonth')}
            >
              <ChevronLeft size={20} />
            </button>
            <span className="t-label t-label--cjk ledger__month">
              {t('ledger.monthTitle', { year, month: String(Number(mon)) })}
            </span>
            <button
              type="button"
              className="ledger__step"
              onClick={() => goMonth(1)}
              disabled={month >= bounds.max}
              aria-label={t('ledger.nextMonth')}
            >
              <ChevronRight size={20} />
            </button>
          </div>

          <div className="ledger__figure">
            <Money fen={monthTotal} size="section" role="neutral" currency={ledger.settings.currency} />
            <div className="ledger__state">
              <span className="t-micro ink-500 ledger__standard">
                {t('ledger.standard', { amount: MoneyText(standard, ledger.settings.currency) })}
              </span>
              {sealed ? (
                <button
                  type="button"
                  className="ledger__seal"
                  onClick={() => setHintOpen((v) => !v)}
                  aria-expanded={hintOpen}
                >
                  <span aria-hidden="true">{t('ledger.sealed')}</span>
                  <span className="sr-only">{t('ledger.sealedNote')}</span>
                </button>
              ) : (
                <span className="t-label t-label--cjk ink-500">{t('ledger.open')}</span>
              )}
            </div>
          </div>
        </header>

        {sealed && hintOpen ? (
          <p className="t-body ink-700 ledger__hint">{t('ledger.sealedNote')}</p>
        ) : null}

        <Rule strong />

        <div className="ledger__search">
          <span className="ledger__search-mark ink-500" aria-hidden="true">
            <MagnifyingGlass size={20} />
          </span>
          <input
            id={searchId}
            className="t-body ledger__search-input"
            type="search"
            value={rawQuery}
            onChange={(e) => setRawQuery(e.target.value)}
            placeholder={t('ledger.search')}
            aria-label={t('ledger.search')}
            autoComplete="off"
          />
          {rawQuery ? (
            <button
              type="button"
              className="ledger__search-clear"
              onClick={() => { setRawQuery(''); setQuery('') }}
              aria-label={t('ledger.searchClear')}
            >
              <XMark size={20} />
            </button>
          ) : null}
        </div>
        {rawQuery.trim() === '' ? (
          <p className="t-micro ink-500 ledger__syntax">{t('ledger.searchSyntax')}</p>
        ) : null}

        <div className="ledger__filters" role="group" aria-label={t('ledger.filters')}>
          <button
            type="button"
            className="ledger__word"
            aria-pressed={!isFiltered(filters)}
            onClick={clearAll}
          >
            {t('ledger.filterAll')}
          </button>
          {categoriesPresent.map((c) => (
            <button
              key={c.id}
              type="button"
              className="ledger__word"
              aria-pressed={filters.categories.has(c.id)}
              onClick={() => toggleCategory(c.id)}
            >
              {locale === 'en' ? c.nameEn : c.name}
            </button>
          ))}
          {INTENTS.map((i) => (
            <button
              key={i}
              type="button"
              className="ledger__word"
              aria-pressed={filters.intents.has(i)}
              onClick={() => toggleIntent(i)}
            >
              {t(INTENT_KEY[i])}
            </button>
          ))}
          <button
            type="button"
            className="ledger__word"
            aria-pressed={filters.leak}
            onClick={() => setFilters((f) => ({ ...f, leak: !f.leak }))}
          >
            {t('ledger.filterLeak')}
          </button>
          <button
            type="button"
            className="ledger__word"
            aria-pressed={filters.corrected}
            onClick={() => setFilters((f) => ({ ...f, corrected: !f.corrected }))}
          >
            {t('ledger.filterCorrected')}
          </button>
          <button
            type="button"
            className="ledger__word"
            aria-pressed={filters.verdict === 'unreviewed'}
            onClick={() => setVerdict('unreviewed')}
          >
            {t('ledger.filterUnreviewed')}
          </button>
          <button
            type="button"
            className="ledger__word"
            aria-pressed={filters.verdict === 'notWorth'}
            onClick={() => setVerdict('notWorth')}
          >
            {t('ledger.filterNotWorth')}
          </button>
        </div>

        <svg className="ledger__defs" aria-hidden="true" focusable="false">
          <defs>
            <pattern id={hatchId} width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
              <line x1="0" y1="0" x2="0" y2="4" stroke="var(--c-ink700)" strokeWidth="1" />
            </pattern>
          </defs>
        </svg>

        {days.length === 0 ? (
          month < bounds.min ? (
            <EmptyState title={t('ledger.emptyBefore', { date: bounds.min })} />
          ) : isFiltered(filters) || query.trim() ? (
            <EmptyState
              title={t('ledger.emptySearch')}
              action={
                <button type="button" className="ledger__link" onClick={clearAll}>
                  {t('ledger.emptySearchClear')}
                </button>
              }
            />
          ) : (
            <EmptyState title={t('ledger.empty')} body={t('ledger.emptyHint')} />
          )
        ) : (
          days.map((d) => (
            <section key={d.day} className="ledger__day">
              <h2 className="ledger__dayhead">
                <span className="t-mono ink-500 ledger__daydate">
                  {t('ledger.dayHeader', {
                    date: d.day.slice(5),
                    weekday: WEEKDAYS[locale][weekdayOf(d.day)] ?? '',
                  })}
                </span>
                <span className="ledger__daytotal">
                  {dayStandard > 0 && d.total > dayStandard ? (
                    <svg
                      className="ledger__over"
                      viewBox="0 0 8 8"
                      width="8"
                      height="8"
                      role="img"
                      aria-label={t('ledger.dayOver')}
                    >
                      <rect x="0" y="0" width="8" height="8" fill={`url(#${hatchId})`} />
                    </svg>
                  ) : null}
                  <Money fen={d.total} size="row" role="neutral" currency={ledger.settings.currency} />
                </span>
              </h2>

              {d.rows.length === 0 ? (
                <p className="t-body ink-500 ledger__nospend">{t('today.nospendDone')}</p>
              ) : (
                d.rows.map((e) => (
                  <LedgerRow
                    key={e.id}
                    entry={e}
                    corrections={correctionsOf.get(e.id) ?? []}
                    categoryName={nameOf(e.categoryId)}
                    printed={printedId === e.id}
                    onOpen={() => setOpenId(e.id)}
                  />
                ))
              )}
            </section>
          ))
        )}
      </div>

      {open ? (
        <EntryDetail
          entry={open}
          sealed={isSealed(monthOf(open.day), today)}
          categoryName={nameOf(open.categoryId)}
          corrections={correctionsOf.get(open.id) ?? []}
          onClose={() => setOpenId(null)}
          onPrinted={() => setPrintedId(open.id)}
        />
      ) : null}
    </section>
  )
}

function LedgerRow({
  entry, corrections, categoryName, printed, onOpen,
}: {
  entry: EffectiveEntry
  corrections: Correction[]
  categoryName: string
  printed: boolean
  onOpen: () => void
}) {
  const { t } = useStore()
  const voided = entry.voidance !== undefined
  const intent = entry.intent
  const lines = correctionLines(t, entry, corrections)

  // One accessibility element per record: the corrections belong to the row
  // that they correct, not to a second thing to arrow past.
  const spoken = [
    timeOf(entry.createdAt),
    categoryName,
    entry.note || entry.merchant,
    intent ? t(INTENT_KEY[intent]) : '',
    MoneyText(voided ? entry.amount : entry.effective, entry.currency),
    lines[lines.length - 1]?.line ?? '',
    entry.voidance ? t('ledger.voided', { reason: entry.voidance.reason }) : '',
  ]
    .filter(Boolean)
    .join(' ')

  return (
    <div className={`ledger__entry${printed ? ' ledger__entry--printed' : ''}`}>
      <button type="button" className="ledger__row" onClick={onOpen} aria-label={spoken}>
        <span className="t-mono ink-500 ledger__time" aria-hidden="true">{timeOf(entry.createdAt)}</span>
        <span className="t-body ink-700 ledger__category" aria-hidden="true">{categoryName}</span>
        <span className="t-body ink-500 ledger__note" aria-hidden="true">{entry.note || entry.merchant}</span>
        <span
          className={intent ? `ledger__stamp ledger__stamp--${intent}` : 'ledger__stamp'}
          aria-hidden="true"
        >
          {intent ? t(GLYPH_KEY[intent]) : ''}
        </span>
        <span className={voided ? 'ledger__amount ledger__amount--voided' : 'ledger__amount'} aria-hidden="true">
          <Money
            fen={voided ? entry.amount : entry.effective}
            size="row"
            role={entry.kind === 'income' ? 'credit' : 'debit'}
            currency={entry.currency}
          />
        </span>
      </button>
      {lines.map((l) => (
        <p key={l.id} className="t-mono ink-500 ledger__sub" aria-hidden="true">{l.line}</p>
      ))}
      {entry.voidance ? (
        <p className="t-mono ink-500 ledger__sub" aria-hidden="true">
          {t('ledger.voided', { reason: entry.voidance.reason })}
        </p>
      ) : null}
      <hr className="rule ledger__rule" />
    </div>
  )
}

function EntryDetail({
  entry, sealed, categoryName, corrections, onClose, onPrinted,
}: {
  entry: EffectiveEntry
  sealed: boolean
  categoryName: string
  corrections: Correction[]
  onClose: () => void
  onPrinted: () => void
}) {
  const { t, ledger, today, commit, undo, toast, locale } = useStore()

  const [amount, setAmount] = useState(() => (entry.amount / 100).toFixed(2))
  const [note, setNote] = useState(entry.note)
  const [day, setDay] = useState<Day>(entry.day)
  const [intent, setIntent] = useState<Intent | null>(entry.intent)
  const [categoryId, setCategoryId] = useState(entry.categoryId)

  const [correctTo, setCorrectTo] = useState(() => (entry.effective / 100).toFixed(2))
  const [reason, setReason] = useState('')
  const [voiding, setVoiding] = useState(false)
  const [voidReason, setVoidReason] = useState('')

  const currency = entry.currency
  const parsedAmount = parse(amount)
  const parsedCorrection = parse(correctTo)
  const dayIntoSealed = isSealed(monthOf(day), today)

  const categories = useMemo(
    () => [...ledger.categories.values()]
      .filter((c) => c.kind === entry.kind && !c.archived)
      .sort((a, b) => a.order - b.order),
    [ledger.categories, entry.kind],
  )

  const save = () => {
    if (parsedAmount === null || parsedAmount <= 0 || dayIntoSealed) return
    commit({
      t: 'entry.patch',
      target: entry.id,
      patch: { amount: parsedAmount, note, day, intent, categoryId },
    })
    onClose()
  }

  const remove = () => {
    const eventId = commit({ t: 'entry.remove', target: entry.id })
    onClose()
    toast(t('ledger.deleted'), { label: t('ledger.undo'), run: () => undo(eventId) })
  }

  const correct = () => {
    if (parsedCorrection === null || reason.trim().length < 2) return
    commit({ t: 'entry.correct', target: entry.id, amount: parsedCorrection, reason: reason.trim() })
    onPrinted()
    onClose()
  }

  const voidIt = () => {
    if (voidReason.trim().length < 2) return
    commit({ t: 'entry.void', target: entry.id, reason: voidReason.trim() })
    onPrinted()
    onClose()
  }

  const history = correctionLines(t, entry, corrections)

  const verdict =
    entry.worthIt === undefined
      ? { label: t('entry.pending'), className: 'ink-500' }
      : entry.worthIt
        ? { label: t('entry.worth'), className: 'ink-700' }
        : { label: t('entry.notWorth'), className: 'fig-regret' }

  return (
    <Sheet onClose={onClose} title={t('entry.title')}>
      <div className="ledger__detail">
        <div className="ledger__detail-figure">
          <Money
            fen={sealed ? entry.effective : (parsedAmount ?? entry.amount)}
            size="screen"
            role={entry.kind === 'income' ? 'credit' : 'debit'}
            currency={currency}
          />
        </div>
        <p className="t-body ink-700 ledger__detail-line">
          {categoryName}
          {entry.note ? ` · ${entry.note}` : ''}
        </p>
        <p className="t-mono ink-500 ledger__detail-meta">
          {`${entry.day} ${timeOf(entry.createdAt)}`}
        </p>

        {sealed ? (
          <p className="t-body ink-700 ledger__hint">{t('ledger.sealedNote')}</p>
        ) : null}

        <Rule strong />

        {sealed ? (
          <>
            <Field
              label={t('entry.correctAmount')}
              value={correctTo}
              onChange={setCorrectTo}
              mono
              inputMode="decimal"
            />
            <Field
              label={t('entry.reasonLabel')}
              value={reason}
              onChange={setReason}
              maxLength={40}
              placeholder={t('ledger.reasonRequired')}
              suffix={<span className="t-mono ink-500">{`${reason.trim().length}/40`}</span>}
            />
            <div className="ledger__actions">
              <Button
                onClick={correct}
                fullWidth
                disabled={parsedCorrection === null || reason.trim().length < 2}
              >
                {t('entry.correctSubmit')}
              </Button>
              {voiding ? (
                <>
                  <Field
                    label={t('entry.voidReason')}
                    value={voidReason}
                    onChange={setVoidReason}
                    maxLength={40}
                    placeholder={t('ledger.reasonRequired')}
                    suffix={<span className="t-mono ink-500">{`${voidReason.trim().length}/40`}</span>}
                  />
                  <Button
                    onClick={voidIt}
                    variant="danger"
                    fullWidth
                    disabled={voidReason.trim().length < 2}
                  >
                    {t('ledger.void')}
                  </Button>
                </>
              ) : (
                <button type="button" className="ledger__link" onClick={() => setVoiding(true)}>
                  {t('entry.void')}
                </button>
              )}
            </div>
          </>
        ) : (
          <>
            <Field
              label={t('entry.amountLabel')}
              value={amount}
              onChange={setAmount}
              mono
              inputMode="decimal"
            />
            <div className="ledger__pick">
              <span className="t-label t-label--cjk ledger__pick-label">{t('capture.category')}</span>
              <div className="ledger__pick-words">
                {categories.map((c) => (
                  <button
                    key={c.id}
                    type="button"
                    className="ledger__word"
                    aria-pressed={c.id === categoryId}
                    onClick={() => setCategoryId(c.id)}
                  >
                    {locale === 'en' ? c.nameEn : c.name}
                  </button>
                ))}
              </div>
            </div>
            <Field label={t('capture.note')} value={note} onChange={setNote} />
            <label className="ledger__date">
              <span className="t-label t-label--cjk">{t('capture.date')}</span>
              <input
                className="t-mono ledger__date-input"
                type="date"
                value={day}
                onChange={(e) => setDay(e.target.value)}
              />
            </label>
            {dayIntoSealed ? (
              <p className="t-body ink-700 ledger__error">{t('entry.closedDate')}</p>
            ) : null}
            {entry.kind === 'spend' ? (
              <div className="ledger__pick">
                <span className="t-label t-label--cjk ledger__pick-label">{t('entry.stamp')}</span>
                <Segmented
                  options={INTENTS.map((i) => ({ value: i, label: t(INTENT_KEY[i]) }))}
                  value={intent}
                  onChange={setIntent}
                  ariaLabel={t('entry.stamp')}
                />
              </div>
            ) : null}
            <div className="ledger__actions">
              <Button
                onClick={save}
                fullWidth
                disabled={parsedAmount === null || parsedAmount <= 0 || dayIntoSealed}
              >
                {t('entry.save')}
              </Button>
              <button type="button" className="ledger__link" onClick={remove}>
                {t('entry.delete')}
              </button>
            </div>
          </>
        )}

        {entry.promise ? (
          <>
            <Rule />
            <p className="t-label t-label--cjk ink-500">{t('entry.promiseTitle')}</p>
            <blockquote className="t-body ink-700 ledger__quote">{`「${entry.promise}」`}</blockquote>
          </>
        ) : null}

        <Rule />
        <p className="ledger__meta-row">
          <span className="t-label t-label--cjk ink-500">{t('entry.verdict')}</span>
          <span className={`t-body ${verdict.className}`}>{verdict.label}</span>
        </p>

        {history.length || entry.voidance ? (
          <>
            <Rule />
            <p className="t-label t-label--cjk ink-500">{t('entry.history')}</p>
            {history.map((h) => (
              <p key={h.id} className="t-mono ink-500 ledger__sub">{h.line}</p>
            ))}
            {entry.voidance ? (
              <p className="t-mono ink-500 ledger__sub">
                {t('ledger.voided', { reason: entry.voidance.reason })}
              </p>
            ) : null}
          </>
        ) : null}
      </div>
    </Sheet>
  )
}
