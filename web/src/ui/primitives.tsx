import {
  useCallback, useEffect, useId, useLayoutEffect, useRef, useState, useSyncExternalStore,
  type CSSProperties, type KeyboardEvent as ReactKeyboardEvent, type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { useStore } from '../app/store'
import './primitives.css'

type Tone = 'neutral' | 'over' | 'held' | 'spared' | 'regret'

const clamp01 = (n: number): number => (Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : 0)

const MOTION_QUERY = '(prefers-reduced-motion: reduce)'
let motionQuery: MediaQueryList | null = null

function motionMedia(): MediaQueryList | null {
  if (motionQuery) return motionQuery
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return null
  motionQuery = window.matchMedia(MOTION_QUERY)
  return motionQuery
}

function subscribeMotion(onChange: () => void): () => void {
  const m = motionMedia()
  if (!m) return () => undefined
  m.addEventListener('change', onChange)
  return () => m.removeEventListener('change', onChange)
}

/** Reduced motion removes depictions, never mechanics: a hold still takes as
    long, a cooling arc still updates. Only the tween goes. */
function useReducedMotion(): boolean {
  return useSyncExternalStore(
    subscribeMotion,
    () => motionMedia()?.matches ?? false,
    () => false,
  )
}

/** Durations live in tokens.css, including the ones JS has to wait out. */
function durationOf(name: string, fallback: number): number {
  if (typeof window === 'undefined') return fallback
  const raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim()
  const n = Number.parseFloat(raw)
  if (!Number.isFinite(n)) return fallback
  return raw.endsWith('ms') ? n : raw.endsWith('s') ? n * 1000 : fallback
}

const cx = (...parts: (string | false | undefined)[]): string => parts.filter(Boolean).join(' ')

// ── Card ──────────────────────────────────────────────────────────────

export function Card({
  children, compact, sunken, className,
}: {
  children: ReactNode
  compact?: boolean
  sunken?: boolean
  className?: string
}) {
  return (
    <div className={cx('card', 'pr-card', compact && 'pr-card--compact', sunken && 'pr-card--sunken', className)}>
      {children}
    </div>
  )
}

// ── Row ───────────────────────────────────────────────────────────────

export function Row({
  left, right, sub, onClick, className,
}: {
  left: ReactNode
  right?: ReactNode
  sub?: ReactNode
  onClick?: () => void
  className?: string
}) {
  const body = (
    <>
      <span className="pr-row__left">
        <span>{left}</span>
        {sub !== undefined && sub !== null ? <span className="pr-row__sub t-body">{sub}</span> : null}
      </span>
      {right !== undefined && right !== null ? <span className="pr-row__right">{right}</span> : null}
    </>
  )
  if (!onClick) return <div className={cx('row', 'pr-row', className)}>{body}</div>
  return (
    <button type="button" className={cx('row', 'pr-row', 'pr-row--tap', className)} onClick={onClick}>
      {body}
    </button>
  )
}

// ── Rule ──────────────────────────────────────────────────────────────

/** `broken` is 破版: an overspend lets the rule run past the content column,
    clipped only by the viewport. It is a layout state and is never animated. */
export function Rule({ strong, broken }: { strong?: boolean; broken?: boolean }) {
  return <hr className={cx('rule', strong && 'rule--strong', broken && 'rule--broken')} />
}

// ── Label ─────────────────────────────────────────────────────────────

export function Label({ children }: { children: ReactNode }) {
  return <span className="t-label pr-label">{children}</span>
}

// ── Button ────────────────────────────────────────────────────────────

const RING_R = 11.5
const RING_C = 2 * Math.PI * RING_R

export function Button({
  children, onClick, variant = 'quiet', fullWidth, disabled, holdMs, ariaLabel, className,
}: {
  children: ReactNode
  onClick: () => void
  variant?: 'primary' | 'quiet' | 'danger'
  fullWidth?: boolean
  disabled?: boolean
  holdMs?: number
  ariaLabel?: string
  className?: string
}) {
  const reduced = useReducedMotion()
  const [holding, setHolding] = useState(false)
  const arcRef = useRef<SVGCircleElement | null>(null)
  const countRef = useRef<HTMLSpanElement | null>(null)
  const frameRef = useRef(0)
  const firedRef = useRef(false)
  const onClickRef = useRef(onClick)
  onClickRef.current = onClick

  const paint = useCallback((progress: number) => {
    const arc = arcRef.current
    if (arc) arc.style.strokeDashoffset = String(RING_C * (1 - progress))
    const count = countRef.current
    if (count && holdMs) {
      const left = Math.max(1, Math.ceil((holdMs * (1 - progress)) / 1000))
      const text = String(left)
      if (count.textContent !== text) count.textContent = text
    }
  }, [holdMs])

  const cancel = useCallback(() => {
    if (frameRef.current) cancelAnimationFrame(frameRef.current)
    frameRef.current = 0
    setHolding(false)
    paint(0)
  }, [paint])

  const start = useCallback(() => {
    if (disabled || !holdMs || frameRef.current) return
    firedRef.current = false
    setHolding(true)
    const began = performance.now()
    const step = () => {
      const progress = clamp01((performance.now() - began) / holdMs)
      paint(progress)
      if (progress < 1) {
        frameRef.current = requestAnimationFrame(step)
        return
      }
      frameRef.current = 0
      setHolding(false)
      if (!firedRef.current) {
        firedRef.current = true
        onClickRef.current()
      }
    }
    frameRef.current = requestAnimationFrame(step)
  }, [disabled, holdMs, paint])

  // A pointer released or a key pressed outside the button must still abort:
  // a hold that survives the release would commit money on its own.
  useEffect(() => {
    if (!holding) return
    const stop = () => cancel()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') cancel() }
    window.addEventListener('pointerup', stop)
    window.addEventListener('pointercancel', stop)
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('pointerup', stop)
      window.removeEventListener('pointercancel', stop)
      window.removeEventListener('keydown', onKey)
    }
  }, [holding, cancel])

  useEffect(() => () => { if (frameRef.current) cancelAnimationFrame(frameRef.current) }, [])

  const held = holdMs !== undefined && holdMs > 0
  return (
    <button
      type="button"
      className={cx(
        'pr-btn', `pr-btn--${variant}`, fullWidth && 'pr-btn--full', held && 'pr-btn--hold', className,
      )}
      disabled={disabled}
      aria-label={ariaLabel}
      onClick={held ? undefined : onClick}
      onPointerDown={held ? (e) => { if (e.button === 0) start() } : undefined}
      onPointerUp={held ? cancel : undefined}
      onPointerLeave={held ? cancel : undefined}
      onBlur={held ? cancel : undefined}
      onKeyDown={held ? (e) => {
        if (e.key === 'Escape') { cancel(); return }
        if (e.key !== ' ' && e.key !== 'Enter') return
        e.preventDefault()
        if (!e.repeat) start()
      } : undefined}
      onKeyUp={held ? (e) => { if (e.key === ' ' || e.key === 'Enter') cancel() } : undefined}
    >
      <span>{children}</span>
      {held && holding && reduced ? (
        <span className="pr-btn__count" ref={countRef} aria-hidden="true" />
      ) : null}
      {held && !reduced ? (
        <svg className="pr-btn__ring" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
          <circle className="pr-btn__ring-track" cx="12" cy="12" r={RING_R} />
          <circle
            className="pr-btn__ring-arc"
            cx="12"
            cy="12"
            r={RING_R}
            ref={arcRef}
            strokeDasharray={RING_C}
            strokeDashoffset={RING_C}
          />
        </svg>
      ) : null}
    </button>
  )
}

// ── Segmented ─────────────────────────────────────────────────────────

/** Selection is a 2px rule sliding under the chosen word — no fill, no colour
    (§2.1 R5). `onChange` fires on a repeat choice too, so a screen can treat a
    second tap as an escalation. */
export function Segmented<V extends string>({
  options, value, onChange, ariaLabel,
}: {
  options: readonly { value: V; label: ReactNode }[]
  value: V | null
  onChange: (value: V) => void
  ariaLabel?: string
}) {
  const listRef = useRef<HTMLDivElement | null>(null)
  const inkRef = useRef<HTMLSpanElement | null>(null)

  const place = useCallback(() => {
    const list = listRef.current
    const ink = inkRef.current
    if (!list || !ink) return
    const label = list.querySelector<HTMLElement>('[aria-checked="true"] .pr-seg__label')
    if (!label) { ink.hidden = true; return }
    ink.hidden = false
    ink.style.setProperty('--pr-seg-x', `${label.offsetLeft}px`)
    ink.style.setProperty('--pr-seg-w', `${label.offsetWidth}px`)
  }, [])

  // Measured rather than computed: the rule is exactly as wide as its label,
  // which depends on the rendered glyphs.
  useLayoutEffect(place)

  useEffect(() => {
    const list = listRef.current
    if (!list || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(place)
    ro.observe(list)
    return () => ro.disconnect()
  }, [place])

  const selected = options.findIndex((o) => o.value === value)
  const roving = selected >= 0 ? selected : 0

  const move = (from: number, key: string) => {
    const n = options.length
    let next = -1
    if (key === 'ArrowRight' || key === 'ArrowDown') next = (from + 1) % n
    else if (key === 'ArrowLeft' || key === 'ArrowUp') next = (from - 1 + n) % n
    else if (key === 'Home') next = 0
    else if (key === 'End') next = n - 1
    if (next < 0) return false
    const option = options[next]
    if (!option) return false
    onChange(option.value)
    listRef.current?.querySelectorAll<HTMLButtonElement>('.pr-seg__opt')[next]?.focus()
    return true
  }

  return (
    <div className="pr-seg" role="radiogroup" aria-label={ariaLabel} ref={listRef}>
      {options.map((option, i) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          className="pr-seg__opt"
          aria-checked={option.value === value}
          tabIndex={i === roving ? 0 : -1}
          onClick={() => onChange(option.value)}
          onKeyDown={(e) => { if (move(i, e.key)) e.preventDefault() }}
        >
          <span className="pr-seg__label">{option.label}</span>
        </button>
      ))}
      <span className="pr-seg__ink" ref={inkRef} hidden aria-hidden="true" />
    </div>
  )
}

// ── Sheet ─────────────────────────────────────────────────────────────

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'

export function Sheet({
  children, onClose, title, ariaLabel,
}: {
  children: ReactNode
  onClose: () => void
  title?: string
  ariaLabel?: string
}) {
  const { t } = useStore()
  const reduced = useReducedMotion()
  const sheetRef = useRef<HTMLDivElement | null>(null)
  const timerRef = useRef(0)
  const [leaving, setLeaving] = useState(false)
  const titleId = useId()

  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose

  const requestClose = useCallback(() => {
    if (timerRef.current) return
    if (reduced) { onCloseRef.current(); return }
    setLeaving(true)
    timerRef.current = window.setTimeout(() => {
      timerRef.current = 0
      onCloseRef.current()
    }, durationOf('--d-sheet-dismiss', 200))
  }, [reduced])

  useEffect(() => {
    const restore = document.activeElement
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const first = sheetRef.current?.querySelector<HTMLElement>(FOCUSABLE) ?? sheetRef.current
    first?.focus()
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      document.body.style.overflow = previousOverflow
      if (restore instanceof HTMLElement) restore.focus()
    }
  }, [])

  const onKeyDown = (e: ReactKeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Escape') { e.stopPropagation(); requestClose(); return }
    if (e.key !== 'Tab') return
    const items = Array.from(sheetRef.current?.querySelectorAll<HTMLElement>(FOCUSABLE) ?? [])
    const first = items[0]
    const last = items[items.length - 1]
    if (!first || !last) { e.preventDefault(); return }
    const active = document.activeElement
    if (e.shiftKey && (active === first || active === sheetRef.current)) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && active === last) {
      e.preventDefault()
      first.focus()
    }
  }

  return createPortal(
    <div
      className={cx('pr-scrim', leaving && 'pr-scrim--leaving')}
      onClick={(e) => { if (e.target === e.currentTarget) requestClose() }}
    >
      <div
        className="pr-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby={title ? titleId : undefined}
        aria-label={title ? undefined : ariaLabel}
        tabIndex={-1}
        ref={sheetRef}
        onKeyDown={onKeyDown}
      >
        {title ? (
          <div className="pr-sheet__head">
            <h2 className="t-label" id={titleId}>{title}</h2>
            <button
              type="button"
              className="pr-sheet__close"
              aria-label={t('common.close')}
              onClick={requestClose}
            >
              <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
                <path
                  d="M6 6 L18 18 M18 6 L6 18"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.5"
                  strokeLinecap="butt"
                />
              </svg>
            </button>
          </div>
        ) : null}
        {children}
      </div>
    </div>,
    document.body,
  )
}

// ── Field ─────────────────────────────────────────────────────────────

export function Field({
  label, value, onChange, placeholder, type = 'text', suffix, mono,
  inputMode, disabled, maxLength, autoFocus, name,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string
  type?: 'text' | 'number' | 'password' | 'search'
  suffix?: ReactNode
  mono?: boolean
  inputMode?: 'text' | 'decimal' | 'numeric' | 'search' | 'tel'
  disabled?: boolean
  maxLength?: number
  autoFocus?: boolean
  name?: string
}) {
  const id = useId()
  const suffixId = `${id}-suffix`
  // A native number input brings steppers and a locale-dependent value; money
  // is parsed from the string by core/money, so the well stays a text field.
  const numeric = type === 'number'
  return (
    <div className={cx('pr-field', mono && 'pr-field--mono')}>
      <label className="t-label pr-field__label" htmlFor={id}>{label}</label>
      <div className="pr-field__well">
        <input
          id={id}
          name={name}
          className="pr-field__input t-body"
          type={numeric ? 'text' : type}
          inputMode={inputMode ?? (numeric ? 'decimal' : undefined)}
          value={value}
          placeholder={placeholder}
          disabled={disabled}
          maxLength={maxLength}
          autoFocus={autoFocus}
          aria-describedby={suffix ? suffixId : undefined}
          onChange={(e) => onChange(e.target.value)}
        />
        {suffix ? <span className="pr-field__suffix t-body" id={suffixId}>{suffix}</span> : null}
      </div>
    </div>
  )
}

// ── Stepper ───────────────────────────────────────────────────────────

export function Stepper({
  label, value, onChange, step = 1, min, max, format,
}: {
  label: string
  value: number
  onChange: (value: number) => void
  step?: number
  min?: number
  max?: number
  format?: (value: number) => string
}) {
  const { t } = useStore()
  const lo = min ?? Number.NEGATIVE_INFINITY
  const hi = max ?? Number.POSITIVE_INFINITY
  const shown = format ? format(value) : String(value)
  const set = (next: number) => {
    const bounded = Math.min(hi, Math.max(lo, next))
    if (bounded !== value) onChange(bounded)
  }

  return (
    <div className="pr-stepper" role="group" aria-label={label}>
      <button
        type="button"
        className="pr-stepper__btn"
        aria-label={t('common.decrease')}
        disabled={value <= lo}
        onClick={() => set(value - step)}
      >
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
          <path d="M5 12 L19 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="butt" />
        </svg>
      </button>
      <span
        className="pr-stepper__value t-row"
        role="spinbutton"
        tabIndex={0}
        aria-label={label}
        aria-valuenow={value}
        aria-valuemin={min}
        aria-valuemax={max}
        aria-valuetext={shown}
        onKeyDown={(e) => {
          if (e.key === 'ArrowUp' || e.key === 'ArrowRight') { e.preventDefault(); set(value + step) }
          else if (e.key === 'ArrowDown' || e.key === 'ArrowLeft') { e.preventDefault(); set(value - step) }
          else if (e.key === 'Home' && min !== undefined) { e.preventDefault(); set(min) }
          else if (e.key === 'End' && max !== undefined) { e.preventDefault(); set(max) }
        }}
      >
        {shown}
      </span>
      <button
        type="button"
        className="pr-stepper__btn"
        aria-label={t('common.increase')}
        disabled={value >= hi}
        onClick={() => set(value + step)}
      >
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
          <path
            d="M12 5 L12 19 M5 12 L19 12"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="butt"
          />
        </svg>
      </button>
    </div>
  )
}

// ── EmptyState ────────────────────────────────────────────────────────

export function EmptyState({
  title, body, action,
}: {
  title: string
  body?: ReactNode
  action?: ReactNode
}) {
  return (
    <div className="pr-empty">
      <p className="t-body pr-empty__title">{title}</p>
      {body !== undefined && body !== null ? <p className="t-body pr-empty__body">{body}</p> : null}
      {action ? <div className="pr-empty__action">{action}</div> : null}
    </div>
  )
}

// ── ProgressRule ──────────────────────────────────────────────────────

/** A 1px rule with its achieved portion overdrawn. No cap, no track fill, no
    percentage badge — the percentage belongs to the sentence above it. */
export function ProgressRule({
  fraction, tone = 'neutral', label,
}: {
  fraction: number
  tone?: Tone
  label?: string
}) {
  const done = clamp01(fraction)
  return (
    <div
      className={cx('pr-progress', tone !== 'neutral' && `pr-progress--${tone}`)}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <div className="pr-progress__fill" style={{ width: `${done * 100}%` }} />
    </div>
  )
}

// ── Ring ──────────────────────────────────────────────────────────────

/** The depleting cooling arc. `fraction` is what remains. It carries no timer:
    the caller repaints it once a minute, which is the whole cadence (§5.10). */
export function Ring({
  fraction, size = 18, tone = 'held', label,
}: {
  fraction: number
  size?: number
  tone?: Tone
  label?: string
}) {
  const remaining = clamp01(fraction)
  const r = (size - 1) / 2
  const circumference = 2 * Math.PI * r
  const box: CSSProperties = { width: size, height: size }
  return (
    <svg
      className={cx('pr-ring', tone !== 'held' && `pr-ring--${tone}`)}
      viewBox={`0 0 ${size} ${size}`}
      style={box}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      focusable="false"
      shapeRendering="geometricPrecision"
    >
      <circle
        className="pr-ring__arc"
        cx={size / 2}
        cy={size / 2}
        r={r}
        strokeDasharray={`${circumference * remaining} ${circumference}`}
      />
    </svg>
  )
}
