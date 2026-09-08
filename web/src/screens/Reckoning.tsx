import {
  useCallback, useEffect, useId, useRef, useState,
  type KeyboardEvent as ReactKeyboardEvent,
} from 'react'
import { createPortal } from 'react-dom'
import { useStore } from '../app/store'
import { reckoningQueue, type EffectiveEntry } from '../core/compute'
import { diffDays } from '../core/date'
import { Money, MoneyText } from '../ui/Money'
import { Button, EmptyState, Rule } from '../ui/primitives'
import { XMark } from '../ui/icons'
import './Reckoning.css'

/** The same bound the fold applies (core/fold.ts): the third 稍后 is the verdict. */
const DEFERRAL_LIMIT = 3

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])'

function swipeMs(): number {
  if (typeof window === 'undefined') return 0
  // Reduced motion removes the depiction; here there is no mechanic left under
  // it, so the card is simply replaced.
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return 0
  const raw = getComputedStyle(document.documentElement).getPropertyValue('--d-verdict-swipe').trim()
  const n = Number.parseFloat(raw)
  if (!Number.isFinite(n)) return 260
  return raw.endsWith('ms') ? n : n * 1000
}

/**
 * 周日审判. Last week's 想要 and 冲动 come back one at a time and the owner
 * signs the verdict himself — which is the only reason the 后悔 figure on the
 * report is believable. The deck is capped, the deferrals are bounded, and the
 * whole thing can be walked out of without a word about it.
 */
export default function Reckoning({ onClose }: { onClose(): void }) {
  const { ledger, today, locale, t, commit } = useStore()
  const titleId = useId()
  const rootRef = useRef<HTMLDivElement | null>(null)
  const nextRef = useRef<HTMLButtonElement | null>(null)
  const timerRef = useRef(0)

  // The queue is read once: judging an entry removes it from the live queue,
  // and a deck that renumbered itself under the hand would lose its place.
  const [deck] = useState<EffectiveEntry[]>(() => reckoningQueue(ledger, today))
  const [index, setIndex] = useState(0)
  const [leaving, setLeaving] = useState<'worth' | 'notworth' | null>(null)
  const [stated, setStated] = useState(false)
  const [failed, setFailed] = useState(false)
  const [notWorth, setNotWorth] = useState(0)
  const [regret, setRegret] = useState(0)

  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose

  useEffect(() => {
    const restore = document.activeElement
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    rootRef.current?.focus()
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      document.body.style.overflow = previousOverflow
      if (restore instanceof HTMLElement) restore.focus()
    }
  }, [])

  const entry = deck[index]

  // The verdict buttons leave the tree when the deck ends or an automatic
  // verdict is stated; focus follows what replaced them rather than falling to
  // the body, where Escape would no longer reach the deck.
  useEffect(() => {
    if (!entry) rootRef.current?.focus()
  }, [entry])

  useEffect(() => {
    if (stated) nextRef.current?.focus()
  }, [stated])

  const busy = leaving !== null || stated
  const deferrals = entry ? (ledger.entries.get(entry.id)?.deferrals ?? entry.deferrals ?? 0) : 0
  const lastDeferral = deferrals + 1 >= DEFERRAL_LIMIT

  const advance = useCallback(() => {
    timerRef.current = 0
    setLeaving(null)
    setStated(false)
    setIndex((i) => i + 1)
  }, [])

  const judge = useCallback(
    (worth: boolean) => {
      if (!entry || busy) return
      try {
        commit({ t: 'review.judge', target: entry.id, worthIt: worth })
      } catch {
        setFailed(true)
        return
      }
      setFailed(false)
      if (!worth) {
        setNotWorth((n) => n + 1)
        setRegret((s) => s + entry.effective)
      }
      setLeaving(worth ? 'worth' : 'notworth')
      timerRef.current = window.setTimeout(advance, swipeMs())
    },
    [advance, busy, commit, entry],
  )

  const defer = useCallback(() => {
    if (!entry || busy) return
    try {
      commit({ t: 'review.defer', target: entry.id })
    } catch {
      setFailed(true)
      return
    }
    setFailed(false)
    if (lastDeferral) {
      // The fold has just written 不值 on this entry; the card says so before
      // it goes, so the number is never changed behind the owner's back.
      setNotWorth((n) => n + 1)
      setRegret((s) => s + entry.effective)
      setStated(true)
      return
    }
    advance()
  }, [advance, busy, commit, entry, lastDeferral])

  const onKeyDown = (e: ReactKeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Escape') {
      e.stopPropagation()
      onCloseRef.current()
      return
    }
    if (entry && !busy && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
      e.preventDefault()
      judge(e.key === 'ArrowLeft')
      return
    }
    if (e.key !== 'Tab') return
    const items = Array.from(rootRef.current?.querySelectorAll<HTMLElement>(FOCUSABLE) ?? [])
    const first = items[0]
    const last = items[items.length - 1]
    if (!first || !last) {
      e.preventDefault()
      return
    }
    const active = document.activeElement
    if (e.shiftKey && (active === first || active === rootRef.current)) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && active === last) {
      e.preventDefault()
      first.focus()
    }
  }

  const category = entry ? ledger.categories.get(entry.categoryId) : undefined
  const categoryName = category ? (locale === 'en' ? category.nameEn : category.name) : ''
  const elapsed = entry ? diffDays(entry.day, today) : 0
  const carried = index === 0 ? deck.filter((e) => (e.deferrals ?? 0) > 0).length : 0

  const separator = locale === 'en' ? ', ' : '，'
  const spoken = entry
    ? [
        t('reckoning.cardOf', { i: index + 1, n: deck.length }),
        MoneyText(entry.effective, entry.currency),
        categoryName,
        entry.note,
        entry.day,
        t('reckoning.daysAgo', { n: elapsed }),
        entry.promise ? `${t('reckoning.quote')}「${entry.promise}」` : '',
      ]
        .filter(Boolean)
        .join(separator)
    : ''

  const head = (
    <div className="reckoning__head column">
      <button
        type="button"
        className="reckoning__close"
        aria-label={t('common.close')}
        onClick={() => onCloseRef.current()}
      >
        <XMark />
      </button>
      {entry ? (
        <span className="t-micro t-mono reckoning__progress">
          {t('reckoning.progress', { done: index + 1, total: deck.length })}
        </span>
      ) : null}
    </div>
  )

  let content

  if (deck.length === 0) {
    content = (
      <div className="reckoning__body column">
        <EmptyState
          title={t('reckoning.empty')}
          action={<Button variant="primary" fullWidth onClick={() => onCloseRef.current()}>{t('common.done')}</Button>}
        />
      </div>
    )
  } else if (!entry) {
    content = (
      <div className="reckoning__body column">
        <div className="reckoning__summary">
          <p className="t-body ink-700">{t('reckoning.doneSummary', { n: deck.length })}</p>
          <p className="reckoning__result">
            <span className="t-body ink-700">{t('reckoning.doneNotWorth', { n: notWorth })}</span>
            <Money fen={regret} size="section" tone="regret" />
          </p>
          {notWorth > 0 ? <p className="t-body ink-500">{t('reckoning.doneNote')}</p> : null}
        </div>
        <Rule />
        <div className="reckoning__finish">
          <Button variant="primary" fullWidth onClick={() => onCloseRef.current()}>
            {t('common.done')}
          </Button>
        </div>
      </div>
    )
  } else {
    content = (
      <>
        <div className="reckoning__body column" aria-live="polite">
          <p className="sr-only">{spoken}</p>
          {carried > 0 ? (
            <p className="t-micro t-mono reckoning__carryover">{t('reckoning.carryover', { n: carried })}</p>
          ) : null}
          <div
            key={entry.id}
            className={`reckoning__card${leaving ? ` reckoning__card--${leaving}` : ''}`}
            aria-hidden="true"
          >
            <p className="reckoning__amount">
              <Money fen={entry.effective} size="screen" currency={entry.currency} />
            </p>
            <p className="t-body reckoning__category">{categoryName}</p>
            {entry.note ? <p className="t-body reckoning__note">{entry.note}</p> : null}
            <p className="t-micro t-mono reckoning__date">
              {entry.day.slice(5)} · {t('reckoning.daysAgo', { n: elapsed })}
            </p>
            {entry.promise ? (
              <>
                <p className="t-body reckoning__quoteLabel">{t('reckoning.quote')}</p>
                <p className="t-body reckoning__quote">「{entry.promise}」</p>
              </>
            ) : null}
          </div>
          {/* The ink a 不值 leaves behind, kept until the deck ends. */}
          {notWorth > 0 ? <hr className="reckoning__scar" /> : null}
          {stated ? <p className="t-body reckoning__statement">{t('reckoning.autoStatement')}</p> : null}
        </div>

        <div className="reckoning__foot column">
          {failed ? (
            <p className="t-body reckoning__error" role="status">{t('reckoning.error')}</p>
          ) : null}
          {stated ? (
            <div className="reckoning__actions">
              <button type="button" className="reckoning__verdict" ref={nextRef} onClick={advance}>
                {t('reckoning.next')}
              </button>
            </div>
          ) : (
            <>
              <div className="reckoning__actions">
                <button
                  type="button"
                  className="reckoning__verdict"
                  onClick={() => judge(true)}
                >
                  {t('reckoning.worth')}
                </button>
                <button
                  type="button"
                  className="reckoning__verdict"
                  onClick={() => judge(false)}
                >
                  {t('reckoning.notWorth')}
                </button>
              </div>
              {lastDeferral ? (
                <p className="t-body reckoning__warning">{t('reckoning.lastChance', { n: deferrals })}</p>
              ) : null}
              <div className="reckoning__links">
                <button type="button" className="reckoning__link" onClick={defer}>
                  {t('reckoning.laterCount', { n: Math.min(deferrals + 1, DEFERRAL_LIMIT) })}
                </button>
                <button type="button" className="reckoning__link" onClick={() => onCloseRef.current()}>
                  {t('reckoning.skip')}
                </button>
              </div>
            </>
          )}
        </div>
      </>
    )
  }

  return createPortal(
    <div
      className="reckoning"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      tabIndex={-1}
      ref={rootRef}
      onKeyDown={onKeyDown}
    >
      <h2 className="sr-only" id={titleId}>{t('reckoning.title')}</h2>
      {head}
      {content}
    </div>,
    document.body,
  )
}
