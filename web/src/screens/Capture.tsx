import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useStore } from '../app/store'
import { WEEKDAYS } from '../app/i18n'
import { Button, Field, Rule, Segmented, Sheet } from '../ui/primitives'
import { Money } from '../ui/Money'
import { DeleteBackward } from '../ui/icons'
import { available, coolingDays, commitWarning } from '../core/compute'
import { addDays, weekdayOf } from '../core/date'
import { parse } from '../core/money'
import { newId } from '../core/id'
import type { Entry, Intent } from '../core/types'
import './Capture.css'

/**
 * Two durations the token file does not emit, because neither is a depiction:
 * the three-second commit is the friction itself (DESIGN.md §5.6) and the
 * long-press is the threshold at which a press stops being a tap.
 */
const HOLD_MS = 3000
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

  const [amount, setAmount] = useState<Keyed>({ int: '0', frac: '', inFrac: false })
  const [categoryId, setCategoryId] = useState<string | null>(null)
  const [intent, setIntent] = useState<Intent | null>(null)
  const [note, setNote] = useState('')
  const [merchant, setMerchant] = useState('')
  const [day, setDay] = useState(today)
  const [datesOpen, setDatesOpen] = useState(false)
  const [keepOpen, setKeepOpen] = useState(false)
  const [override, setOverride] = useState(false)

  const amountFen = useMemo(
    () => parse(amount.inFrac ? `${amount.int}.${amount.frac}` : amount.int) ?? 0,
    [amount],
  )

  const categories = useMemo(
    () =>
      [...ledger.categories.values()]
        .filter((c) => c.kind === 'spend' && !c.archived)
        .sort((a, b) => a.order - b.order),
    [ledger.categories],
  )

  const settings = ledger.settings
  const coolingFloor = settings.coolingFloorFen
  const perDay = useMemo(() => available(ledger, today, now).perDay, [ledger, today, now])
  const after = perDay - amountFen

  const overFloor = amountFen >= coolingFloor
  const cooling = overFloor ? coolingDays(amountFen) : 0
  const suspendable = overFloor && (intent === 'want' || intent === 'impulse') && !override
  const warning = categoryId ? commitWarning(ledger, today, categoryId, amountFen) : null
  // The hold is required by the amount or by an allowance that is already
  // spent, whichever is true first (SCREENS.md C9b).
  const needsHold = overFloor || perDay < 0
  const missing = amountFen === 0 || !categoryId || !intent

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
      if (missing || !categoryId || !intent) return
      const entry: Entry = {
        id: newId(),
        kind: 'spend',
        amount: amountFen,
        currency: settings.currency,
        categoryId,
        intent,
        note: note.trim(),
        merchant: merchant.trim(),
        day,
        createdAt: now,
      }
      const eventId = commit({ t: 'entry.add', entry })
      toast(t('capture.saved'), { label: t('ledger.undo'), run: () => undo(eventId) })
      if (!keep) {
        onClose()
        return
      }
      // The stamp and the category survive: the next entry is usually the same
      // kind of purchase, and re-choosing them is the tax that ends a streak.
      clearAmount()
      setNote('')
      setMerchant('')
      setOverride(false)
    },
    [
      missing, categoryId, intent, amountFen, settings.currency, note, merchant, day, now,
      commit, toast, t, undo, onClose, clearAmount,
    ],
  )

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

  const hint = amountFen === 0
    ? t('capture.needAmount')
    : !categoryId
      ? t('capture.needCategory')
      : !intent
        ? t('capture.intentRequired')
        : ''

  return (
    <Sheet onClose={onClose} ariaLabel={t('capture.title')}>
      <div className="capture">
        <div className="capture__head">
          <button
            type="button"
            className="capture__date t-mono"
            aria-expanded={datesOpen}
            aria-label={`${t('capture.date')} ${day}`}
            onClick={() => setDatesOpen((v) => !v)}
          >
            {day.slice(5)} · {weekday}
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
              <input
                type="date"
                className="t-mono"
                value={day}
                max={today}
                onChange={(e) => {
                  if (e.target.value) setDay(e.target.value)
                }}
              />
            </label>
          </div>
        ) : null}

        <div
          className={`capture__amount${amountFen === 0 ? ' capture__amount--empty' : ''}`}
          role="group"
          aria-label={t('capture.amount')}
        >
          <Money fen={amountFen} size="screen" currency={settings.currency} />
          <span className="capture__caret" aria-hidden="true" />
        </div>

        <p className="capture__consequence">
          <span className="t-label">{t('capture.consequence')}</span>
          <Money fen={after} size="body" tone={after < 0 ? 'over' : undefined} currency={settings.currency} />
        </p>

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
              onPointerDown={needsHold ? undefined : () => startLongPress(() => save(true))}
              onPointerUp={needsHold ? undefined : endLongPress}
              onPointerLeave={needsHold ? undefined : endLongPress}
              onPointerCancel={needsHold ? undefined : endLongPress}
            >
              <Button
                variant="primary"
                fullWidth
                disabled={missing}
                holdMs={needsHold ? HOLD_MS : undefined}
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
