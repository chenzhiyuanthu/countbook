import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useStore } from '../app/store'
import { useSync } from '../app/sync'
import { WEEKDAYS } from '../app/i18n'
import { Button, Field, Rule, Segmented, Sheet } from '../ui/primitives'
import { Money } from '../ui/Money'
import { ChevronDown, ChevronUp, DeleteBackward } from '../ui/icons'
import { available, coolingDays, commitWarning } from '../core/compute'
import { addDays, weekdayOf } from '../core/date'
import { convert, formatRate, parse, parseRate } from '../core/money'
import { newId } from '../core/id'
import type { Entry, EntryKind, Intent } from '../core/types'
import { DEFAULT_SERVER_URL } from '../sync/config'
import { CURRENCIES, fetchRate, rememberRate, type Rate } from '../sync/fx'
import './Capture.css'

/**
 * A duration the token file does not emit, because it is not a depiction: the
 * long-press is the threshold at which a press stops being a tap.
 */
const LONG_PRESS_MS = 400

/** ¥999,999.99 — six 元 digits is the ceiling, and it is reached silently. */
const MAX_INT_DIGITS = 6

const KEYPAD = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'back'] as const

/** 整数部分 / 小数部分 / 是否已进入小数态 — PRODUCT.md §4.3. */
interface Keyed {
  int: string
  frac: string
  inFrac: boolean
}

export default function Capture({ onClose }: { onClose(): void }) {
  const { ledger, today, now, t, locale, commit, undo, toast } = useStore()
  const { config: syncConfig } = useSync()

  const [kind, setKind] = useState<EntryKind>('spend')
  /** 盈利 / 亏损 — an investment result has a sign; a purchase does not. */
  const [loss, setLoss] = useState(false)
  const [amount, setAmount] = useState<Keyed>({ int: '0', frac: '', inFrac: false })
  const [categoryId, setCategoryId] = useState<string | null>(null)
  const [intent, setIntent] = useState<Intent | null>(null)
  const [note, setNote] = useState('')
  const [merchant, setMerchant] = useState('')
  const [day, setDay] = useState(today)
  const [datesOpen, setDatesOpen] = useState(false)
  const [keepOpen, setKeepOpen] = useState(false)
  const [fieldsOpen, setFieldsOpen] = useState(false)
  const [override, setOverride] = useState(false)

  const settings = ledger.settings
  const home = settings.currency

  // ── the currency the figure is keyed in ─────────────────────────────

  const [currency, setCurrency] = useState(home)
  const [currenciesOpen, setCurrenciesOpen] = useState(false)
  const [rate, setRate] = useState<Rate | null>(null)
  const [rateText, setRateText] = useState('')
  const [rateBusy, setRateBusy] = useState(false)
  const foreign = currency !== home
  const rateMicro = foreign ? parseRate(rateText) : null

  // The day's rate is asked for when the currency or the day changes, and the
  // field is pre-filled — never locked. A broker's rate beats a reference one.
  useEffect(() => {
    if (!foreign) {
      setRate(null)
      setRateText('')
      return
    }
    let stale = false
    setRateBusy(true)
    const base = syncConfig?.kind === 'server' ? syncConfig.baseUrl : DEFAULT_SERVER_URL
    void fetchRate(currency, home, day, base).then((r) => {
      if (stale) return
      setRate(r)
      setRateText(r ? formatRate(r.rateMicro) : '')
      setRateBusy(false)
    })
    return () => {
      stale = true
    }
  }, [currency, home, day, foreign, syncConfig])

  /** What was keyed, in minor units of `currency`. */
  const keyedFen = useMemo(
    () => parse(amount.inFrac ? `${amount.int}.${amount.frac}` : amount.int) ?? 0,
    [amount],
  )
  /** The same in the ledger's currency — the figure every rule below uses. */
  const amountFen = foreign ? (rateMicro ? convert(keyedFen, rateMicro) : 0) : keyedFen

  const categories = useMemo(
    () =>
      [...ledger.categories.values()]
        .filter((c) => c.kind === kind && !c.archived)
        .sort((a, b) => a.order - b.order),
    [ledger.categories, kind],
  )

  const income = kind === 'income'
  /** What is stored: a loss is the same figure below zero. */
  const sign = income && loss ? -1 : 1
  const coolingFloor = settings.coolingFloorFen
  const perDay = useMemo(() => available(ledger, today, now).perDay, [ledger, today, now])
  const after = perDay - amountFen

  // Income carries no stamp and no cooling: there is nothing to judge about
  // money arriving, and nothing to be slowed down about.
  const overFloor = !income && amountFen >= coolingFloor
  const cooling = overFloor ? coolingDays(amountFen) : 0
  const suspendable = overFloor && (intent === 'want' || intent === 'impulse') && !override
  const warning = !income && categoryId ? commitWarning(ledger, today, categoryId, amountFen) : null
  const needsRate = foreign && !rateMicro
  const missing = keyedFen === 0 || needsRate || !categoryId || (!income && !intent)

  // ── the amount, keyed one digit at a time ───────────────────────────

  const pressDigit = useCallback((d: string) => {
    setAmount((a) => {
      if (a.inFrac) return a.frac.length >= 2 ? a : { ...a, frac: a.frac + d }
      if (a.int === '0') return { ...a, int: d }
      return a.int.length >= MAX_INT_DIGITS ? a : { ...a, int: a.int + d }
    })
  }, [])

  const pressDot = useCallback(() => setAmount((a) => (a.inFrac ? a : { ...a, inFrac: true })), [])

  const pressBack = useCallback(() => {
    setAmount((a) => {
      if (!a.inFrac) return { ...a, int: a.int.length > 1 ? a.int.slice(0, -1) : '0' }
      if (a.frac.length > 0) return { ...a, frac: a.frac.slice(0, -1) }
      return { ...a, inFrac: false }
    })
  }, [])

  const clearAmount = useCallback(() => setAmount({ int: '0', frac: '', inFrac: false }), [])

  // ── committing ──────────────────────────────────────────────────────

  const save = useCallback(
    (keep: boolean) => {
      if (missing || !categoryId || (!income && !intent)) return
      const entry: Entry = {
        id: newId(),
        kind,
        amount: sign * amountFen,
        currency: home,
        categoryId,
        intent: income ? null : intent,
        note: note.trim(),
        merchant: merchant.trim(),
        day,
        createdAt: now,
        ...(foreign && rateMicro ? { original: { currency, amount: sign * keyedFen, rateMicro } } : {}),
      }
      if (foreign && rateMicro) rememberRate(currency, home, rateMicro)
      const eventId = commit({ t: 'entry.add', entry })
      if (!keep) {
        // The sheet closes and the row prints in the ledger — that is the
        // receipt. No toast on a plain save (DESIGN.md §6.5).
        onClose()
        return
      }
      // Staying open, the receipt has to be said, and it can be taken back.
      toast(t('capture.saved'), { label: t('ledger.undo'), run: () => undo(eventId) })
      // The stamp and the category survive: the next entry is usually the same
      // kind of purchase, and re-choosing them is the tax that ends a streak.
      clearAmount()
      setNote('')
      setMerchant('')
      setOverride(false)
    },
    [
      missing, categoryId, intent, income, kind, amountFen, sign, home, foreign, currency, keyedFen, rateMicro,
      note, merchant, day, now, commit, toast, t, undo, onClose, clearAmount,
    ],
  )

  // A different kind of entry is a different set of categories and a different
  // question; what was keyed stays, because the figure is usually right.
  const switchKind = (next: EntryKind) => {
    if (next === kind) return
    setKind(next)
    setCategoryId(null)
    setIntent(null)
    setLoss(false)
    setOverride(false)
  }

  const suspend = useCallback(() => {
    if (!categoryId || !cooling) return
    const named = categories.find((c) => c.id === categoryId)
    const name =
      note.trim() ||
      merchant.trim() ||
      (named ? (locale === 'en' ? named.nameEn : named.name) : t('capture.title'))
    const eventId = commit({
      t: 'wish.add',
      wish: {
        id: newId(),
        name,
        price: amountFen,
        createdAt: now,
        unlockAt: now + cooling * 86_400_000,
      },
    })
    toast(t('capture.suspended'), { label: t('ledger.undo'), run: () => undo(eventId) })
    onClose()
  }, [
    categoryId, cooling, categories, note, merchant, locale, t, commit, amountFen, now,
    toast, undo, onClose,
  ])

  // ── hardware keyboard ───────────────────────────────────────────────

  const keys = useRef({ pressDigit, pressDot, pressBack, save, missing, suspendable })
  keys.current = { pressDigit, pressDot, pressBack, save, missing, suspendable }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return
      const el = e.target
      const typing =
        el instanceof HTMLElement &&
        (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable)
      if (typing) return
      const k = keys.current
      if (e.key >= '0' && e.key <= '9') {
        e.preventDefault()
        k.pressDigit(e.key)
      } else if (e.key === '.') {
        e.preventDefault()
        k.pressDot()
      } else if (e.key === 'Backspace') {
        e.preventDefault()
        k.pressBack()
      } else if (e.key === 'Enter') {
        // A focused control answers Enter itself; overriding it would fire two
        // actions from one keystroke.
        if (el instanceof HTMLElement && el.tagName === 'BUTTON') return
        if (k.missing || k.suspendable) return
        e.preventDefault()
        k.save(false)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // ── long presses ────────────────────────────────────────────────────

  const timerRef = useRef(0)
  const heldRef = useRef(false)

  const startLongPress = (run: () => void) => {
    heldRef.current = false
    window.clearTimeout(timerRef.current)
    timerRef.current = window.setTimeout(() => {
      heldRef.current = true
      run()
    }, LONG_PRESS_MS)
  }
  const endLongPress = () => window.clearTimeout(timerRef.current)
  useEffect(() => () => window.clearTimeout(timerRef.current), [])

  // ── printing ────────────────────────────────────────────────────────

  const weekday = WEEKDAYS[locale][weekdayOf(day)] ?? ''
  const quickDays: { key: 'common.today' | 'common.yesterday' | 'capture.dayBefore'; day: string }[] = [
    { key: 'common.today', day: today },
    { key: 'common.yesterday', day: addDays(today, -1) },
    { key: 'capture.dayBefore', day: addDays(today, -2) },
  ]

  // Closed, the row still has to report what is behind it, or a note typed
  // and then collapsed would look lost.
  const filled = [note.trim(), merchant.trim()].filter(Boolean).join(' · ')

  const hint = keyedFen === 0
    ? t('capture.needAmount')
    : needsRate
      ? t('capture.needRate')
      : !categoryId
        ? t('capture.needCategory')
        : !income && !intent
          ? t('capture.intentRequired')
          : ''

  const rateNote = !foreign
    ? ''
    : rateBusy
      ? '…'
      : !rate
        ? t('capture.rateUnavailable')
        : rate.source === 'remembered'
          ? t('capture.rateRemembered')
          : t('capture.rateAsOf', { day: rate.asOf.slice(5) })

  return (
    <Sheet onClose={onClose} ariaLabel={t('capture.title')}>
      <div className="capture">
        <div className="capture__kind">
          <Segmented
            ariaLabel={t('capture.title')}
            value={kind}
            onChange={switchKind}
            options={[
              { value: 'spend', label: t('capture.spend') },
              { value: 'income', label: t('capture.income') },
            ]}
          />
        </div>

        <div className="capture__head">
          <button
            type="button"
            className="capture__date t-mono"
            aria-expanded={datesOpen}
            aria-label={`${t('capture.date')} ${day}`}
            onClick={() => setDatesOpen((v) => !v)}
          >
            {day} · {weekday}
          </button>
          {/* 备注 and 商家 are optional, and as two open fields they pushed the
              keypad off a 402×874 screen. Closed, they cost nothing: they join
              the day and 继续记 in the one control strip above the figure. */}
          <button
            type="button"
            className={`capture__optional t-body${filled ? ' capture__optional--filled' : ''}`}
            aria-expanded={fieldsOpen}
            onClick={() => setFieldsOpen((v) => !v)}
          >
            <span className="capture__optional-label">{filled || t('capture.optional')}</span>
            {fieldsOpen ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
          </button>
          <button
            type="button"
            className="capture__keep t-label"
            aria-pressed={keepOpen}
            onClick={() => setKeepOpen((v) => !v)}
          >
            {t('capture.keepOpen')}
          </button>
        </div>

        {datesOpen ? (
          <div className="capture__dates">
            {quickDays.map((q) => (
              <button
                key={q.key}
                type="button"
                className="capture__quick t-body"
                aria-pressed={day === q.day}
                onClick={() => {
                  setDay(q.day)
                  setDatesOpen(false)
                }}
              >
                {t(q.key)}
              </button>
            ))}
            <label className="capture__pick t-body">
              <span className="sr-only">{t('capture.pickDate')}</span>
              {/* The native control is the picker, never the printed date: its
                  locale format (08/09/2026) contradicts the ISO mono the rest
                  of the app reads in. */}
              <span className="capture__picked t-mono" aria-hidden="true">{day}</span>
              <input
                type="date"
                className="capture__pick-input"
                value={day}
                max={today}
                onChange={(e) => {
                  if (e.target.value) setDay(e.target.value)
                }}
              />
            </label>
          </div>
        ) : null}

        {fieldsOpen ? (
          <div className="capture__fields">
            <Field
              label={t('capture.note')}
              value={note}
              onChange={setNote}
              maxLength={40}
              placeholder={suspendable ? t('capture.promise') : t('capture.note')}
            />
            <Field
              label={t('capture.merchant')}
              value={merchant}
              onChange={setMerchant}
              maxLength={40}
              placeholder={t('capture.merchant')}
            />
          </div>
        ) : null}

        <div
          className={`capture__amount${keyedFen === 0 ? ' capture__amount--empty' : ''}`}
          role="group"
          aria-label={t('capture.amount')}
        >
          <Money fen={sign * keyedFen} size="screen" currency={currency} />
          <span className="capture__caret" aria-hidden="true" />
          <button
            type="button"
            className="capture__currency t-label"
            aria-expanded={currenciesOpen}
            aria-label={`${t('capture.currency')} ${currency}`}
            onClick={() => setCurrenciesOpen((v) => !v)}
          >
            {currency}
          </button>
        </div>

        {currenciesOpen ? (
          <div className="capture__dates" role="radiogroup" aria-label={t('capture.currency')}>
            {[home, ...CURRENCIES.filter((c) => c !== home)].map((c) => (
              <button
                key={c}
                type="button"
                role="radio"
                aria-checked={currency === c}
                className="capture__quick t-mono"
                onClick={() => {
                  setCurrency(c)
                  setCurrenciesOpen(false)
                }}
              >
                {c}
              </button>
            ))}
          </div>
        ) : null}

        {foreign ? (
          <div className="capture__rate">
            <label className="capture__rate-field">
              <span className="t-label">{t('capture.rate')}</span>
              <input
                className="capture__rate-input t-mono"
                inputMode="decimal"
                value={rateText}
                placeholder={rateBusy ? '…' : '0.0000'}
                onChange={(e) => setRateText(e.target.value)}
                aria-describedby="capture-rate-note"
              />
            </label>
            <span className="capture__rate-converted">
              <span className="t-label">≈</span>
              <Money fen={sign * amountFen} size="body" currency={home} />
            </span>
            <span id="capture-rate-note" className="t-micro capture__rate-note">{rateNote}</span>
          </div>
        ) : null}

        {income ? (
          <p className="capture__consequence">
            <span className="t-label">{t('capture.incomeNote')}</span>
          </p>
        ) : (
          <p className="capture__consequence">
            <span className="t-label">{t('capture.consequence')}</span>
            <Money fen={after} size="body" tone={after < 0 ? 'over' : undefined} currency={home} />
          </p>
        )}

        <Rule />

        <div className="capture__grid" role="radiogroup" aria-label={t('capture.category')}>
          {categories.map((c) => (
            <button
              key={c.id}
              type="button"
              role="radio"
              aria-checked={categoryId === c.id}
              className="capture__cat t-body"
              onClick={() => setCategoryId(c.id)}
            >
              {locale === 'en' ? c.nameEn : c.name}
            </button>
          ))}
        </div>

        <Rule />

        {income ? (
          <>
            <div className="capture__stamp">
              <Segmented
                ariaLabel={t('capture.result')}
                value={loss ? 'loss' : 'gain'}
                onChange={(v) => setLoss(v === 'loss')}
                options={[
                  { value: 'gain', label: t('capture.gain') },
                  { value: 'loss', label: t('capture.loss') },
                ]}
              />
            </div>

            <Rule />
          </>
        ) : (
          <>
            <div className="capture__stamp">
              <Segmented
                ariaLabel={t('capture.intent')}
                value={intent}
                onChange={(v) => setIntent((prev) => (prev === 'want' && v === 'want' ? 'impulse' : v))}
                options={[
                  { value: 'need', label: t('capture.intent.need') },
                  { value: 'want', label: t('capture.intent.want') },
                  { value: 'impulse', label: t('capture.intent.impulse') },
                ]}
              />
              {cooling > 0 && intent !== null && intent !== 'need' ? (
                <p className="t-micro capture__tier">{t('capture.coolingTier', { days: cooling })}</p>
              ) : null}
            </div>

            <Rule />
          </>
        )}

        <div className="capture__keypad" role="group" aria-label={t('capture.keypad')}>
          {KEYPAD.map((k) =>
            k === 'back' ? (
              <button
                key={k}
                type="button"
                className="capture__key capture__key--icon"
                aria-label={t('capture.backspace')}
                onPointerDown={() => startLongPress(clearAmount)}
                onPointerUp={endLongPress}
                onPointerLeave={endLongPress}
                onPointerCancel={endLongPress}
                onClick={() => {
                  if (heldRef.current) {
                    heldRef.current = false
                    return
                  }
                  pressBack()
                }}
              >
                <DeleteBackward size={24} />
              </button>
            ) : k === '.' ? (
              <button
                key={k}
                type="button"
                className="capture__key"
                aria-label={t('capture.decimal')}
                disabled={amount.inFrac}
                onClick={pressDot}
              >
                .
              </button>
            ) : (
              <button key={k} type="button" className="capture__key" onClick={() => pressDigit(k)}>
                {k}
              </button>
            ),
          )}
        </div>

        <div className="capture__commit">
          {suspendable ? (
            <>
              <Button
                variant="quiet"
                fullWidth
                className="capture__hold"
                onClick={suspend}
              >
                {t('capture.holdPrimary', { days: cooling, date: addDays(today, cooling).slice(5) })}
              </Button>
              <button type="button" className="capture__link t-body" onClick={() => setOverride(true)}>
                {warning
                  ? t('capture.overrideWarned', { warning })
                  : t('capture.holdOverride')}
              </button>
            </>
          ) : (
            <div
              onPointerDown={() => startLongPress(() => save(true))}
              onPointerUp={endLongPress}
              onPointerLeave={endLongPress}
              onPointerCancel={endLongPress}
            >
              <Button
                variant="primary"
                fullWidth
                disabled={missing}
                onClick={() => {
                  if (heldRef.current) {
                    heldRef.current = false
                    return
                  }
                  save(keepOpen)
                }}
              >
                {warning ? t('capture.saveWarned', { warning }) : t('capture.save')}
              </Button>
            </div>
          )}
          <p className="sr-only" role="status">{hint}</p>
        </div>
      </div>
    </Sheet>
  )
}
