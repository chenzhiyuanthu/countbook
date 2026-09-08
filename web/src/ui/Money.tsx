import { useRef } from 'react'
import type { ClipboardEvent } from 'react'
import { format, parts } from '../core/money'
import type { Fen } from '../core/money'
import './Money.css'

export type MoneySize = 'hero' | 'screen' | 'section' | 'row' | 'body'
export type MoneyTone = 'over' | 'held' | 'spared' | 'regret'

/** The role names DESIGN.md §3.6.4 and SCREENS.md use; the neutral ones carry no tone. */
export type MoneyRole = MoneyTone | 'neutral' | 'debit' | 'credit' | 'allowance'

export interface MoneyProps {
  fen: Fen
  size: MoneySize
  tone?: MoneyTone
  role?: MoneyRole
  currency?: string
}

/** The full string, for aria-labels, exports and anything that is not typeset. */
export function MoneyText(fen: Fen, currency = 'CNY'): string {
  return format(fen, currency)
}

const TYPE_CLASS: Record<MoneySize, string> = {
  hero: 't-hero',
  screen: 't-screen',
  section: 't-section',
  row: 't-row',
  body: 't-body',
}

const ROLE_TONE: Record<MoneyRole, MoneyTone | undefined> = {
  over: 'over',
  held: 'held',
  spared: 'spared',
  regret: 'regret',
  allowance: 'over',
  neutral: undefined,
  debit: undefined,
  credit: undefined,
}

interface Glyph {
  ch: string
  /** Distance from the least significant digit; drives the right-to-left stagger. */
  i: number
  /** Bumped each time this position takes a different character. */
  gen: number
}

/**
 * The three-part ¥ / 元 / 分 composition, and the only place in the product it
 * exists. Splitting an amount into spans is what lets the 分 set smaller and
 * lighter than the 元 — and it is also what would silently break selection,
 * copying and VoiceOver, so those are closed here rather than at each call site.
 */
export function Money({ fen, size, tone, role, currency = 'CNY' }: MoneyProps) {
  const p = parts(fen, currency)
  const settled = useSettle(p.int, p.frac)
  const applied = tone ?? (role ? ROLE_TONE[role] : undefined)

  const className = ['money', `money--${size}`, TYPE_CLASS[size], applied ? `money--${applied}` : '']
    .filter(Boolean)
    .join(' ')

  // Copying the split DOM yields fragments in the wrong order; a figure copies
  // as a machine-readable number so it can be pasted into a sheet.
  const onCopy = (e: ClipboardEvent<HTMLSpanElement>) => {
    e.clipboardData.setData('text/plain', `${p.sign ? '-' : ''}${p.int.replace(/,/g, '')}.${p.frac}`)
    e.preventDefault()
  }

  return (
    <span className={className} role="text" aria-label={MoneyText(fen, currency)} onCopy={onCopy}>
      <span className="money__mark" aria-hidden="true">
        {p.sign ? <span className="money__sign">{p.sign}</span> : null}
        {p.symbol}
      </span>
      <span className="money__int" aria-hidden="true">
        {settled.int.map(renderGlyph)}
      </span>
      <span className="money__frac" aria-hidden="true">
        {settled.frac.map(renderGlyph)}
      </span>
    </span>
  )
}

function renderGlyph(g: Glyph) {
  // The key carries the generation, so a changed position mounts a fresh node
  // and its animation runs once; an unchanged position keeps its node and does
  // not re-animate on an unrelated render.
  return (
    <span
      key={`${g.i}:${g.gen}`}
      className={g.gen > 0 ? 'money__d money__d--settle' : 'money__d'}
      style={g.gen > 0 ? { animationDelay: `calc(var(--d-figure-stagger) * ${g.i})` } : undefined}
    >
      {g.ch}
    </span>
  )
}

/**
 * figureSettle (DESIGN.md §6.3): only the characters that actually changed
 * move. Positions are counted from the least significant digit so that a figure
 * gaining a digit does not re-animate the ones that merely shifted left.
 */
function useSettle(int: string, frac: string): { int: Glyph[]; frac: Glyph[] } {
  const seen = useRef<Map<number, Glyph> | null>(null)
  const first = seen.current === null
  const state = seen.current ?? new Map<number, Glyph>()
  seen.current = state

  const fracChars = ['.', ...frac]
  const intChars = [...int]
  const total = intChars.length + fracChars.length

  const glyph = (ch: string, i: number): Glyph => {
    const was = state.get(i)
    // A position that is new on a later render is a digit the figure just grew.
    const gen = was === undefined ? (first ? 0 : 1) : was.ch === ch ? was.gen : was.gen + 1
    const next: Glyph = { ch, i, gen }
    state.set(i, next)
    return next
  }

  const out = {
    int: intChars.map((ch, j) => glyph(ch, total - 1 - j)),
    frac: fracChars.map((ch, j) => glyph(ch, fracChars.length - 1 - j)),
  }
  for (const i of state.keys()) if (i >= total) state.delete(i)
  return out
}
