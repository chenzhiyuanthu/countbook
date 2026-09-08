import { useCallback, useId, useMemo, useRef, useState } from 'react'
import type { CSSProperties, PointerEvent as ReactPointerEvent, KeyboardEvent as ReactKeyboardEvent } from 'react'
import { useStore } from '../app/store'
import type { Deviation, MonthStrip as MonthStripData } from '../core/compute'
import type { Day, Month } from '../core/date'
import { isWeekend, monthOf } from '../core/date'
import type { Fen } from '../core/money'
import { MINUS, format, formatYuan } from '../core/money'
import './charts.css'

/*
 * Every form here is drawn by hand. The geometry constants below mirror
 * design/tokens geometry §7 and the layout functions are pure so the SwiftUI
 * side can be written against the same numbers and proven equal by fixtures.
 *
 * Amounts are printed with the shared formatter rather than composed through
 * <Money>: a deviation figure must carry an explicit U+002B, which the money
 * parts deliberately never emit, and a chart label is a single string rather
 * than the three-part ledger treatment.
 */

/** The phone content column, 360 − 2 × 20 gutter. Charts are laid out at this
 *  width and stretched horizontally to whatever column they land in, so the
 *  vertical metrics below are exact pixels at every viewport. */
const PLOT_W = 320

const STRIP = { height: 96, barRatio: 0.6, tick: 3, tickGap: 3, headroom: 1.6 } as const
const DEVIATION = { barHeight: 6, rowHeight: 34, minBar: 2 } as const
const YEAR_ROW_H = 28
const REGRET = { unit: 8, gap: 3, minCols: 12, minSample: 30 } as const
const ANNUAL = { height: 14, minSegment: 3 } as const
const HOURS = { dot: 3, gap: 2, maxRows: 10, height: 96 } as const
const HATCH = { period: 4, stroke: 1 } as const

/* ── shared geometry: pure, normalised to [0,1], no DOM, no clock ───────── */

/** Round half away from zero, to 4 places. JS rounds −0.5 to −0, Swift to −1;
 *  pinning it here is what lets the two platforms agree. */
function q4(x: number): number {
  const v = x * 10000
  return (v < 0 ? -Math.round(-v) : Math.round(v)) / 10000
}

function ratio(n: number, d: number): number {
  return d === 0 ? 0 : n / d
}

interface Span {
  i: number
  x0: number
  x1: number
  over: boolean
}

/** Symmetric about 0.5, scaled so the largest absolute deviation touches an edge. */
function deviationLayout(deltas: readonly number[]): Span[] {
  const maxAbs = deltas.reduce((m, d) => Math.max(m, Math.abs(d)), 0)
  const floorLen = DEVIATION.minBar / PLOT_W
  return deltas.map((d, i) => {
    const over = d > 0
    let len = Math.abs(ratio(d, maxAbs)) / 2
    if (d !== 0 && len < floorLen) len = floorLen
    return { i, x0: q4(over ? 0.5 : 0.5 - len), x1: q4(over ? 0.5 + len : 0.5), over }
  })
}

interface StripBar {
  x: number
  w: number
  underY: number
  underH: number
  overY: number
  overH: number
}

function monthStripLayout(daily: readonly number[], standard: number): { bars: StripBar[]; standardY: number } {
  const n = daily.length
  const peak = daily.reduce((m, v) => Math.max(m, v), 0)
  // Headroom keeps the standard line off the top edge, so a day that clears it
  // has somewhere to go.
  const top = Math.max(peak, standard * STRIP.headroom, 1)
  const pitch = n === 0 ? 0 : 1 / n
  const w = pitch * STRIP.barRatio
  const bars = daily.map<StripBar>((v, i) => {
    const whole = ratio(v, top)
    // A day equal to the standard is under it: the comparison is strict.
    const under = ratio(Math.min(v, standard), top)
    return {
      x: q4(i * pitch + (pitch - w) / 2),
      w: q4(w),
      underY: q4(1 - under),
      underH: q4(under),
      overY: q4(1 - whole),
      overH: q4(whole - under),
    }
  })
  return { bars, standardY: q4(1 - ratio(standard, top)) }
}

function regretBlockLayout(count: number, marked: ReadonlySet<number>, cols: number): { col: number; row: number; bad: boolean }[] {
  const out: { col: number; row: number; bad: boolean }[] = []
  for (let i = 0; i < count; i++) out.push({ col: i % cols, row: Math.floor(i / cols), bad: marked.has(i) })
  return out
}

/** Counts alone carry no chronology, so the 不值 squares are spread evenly
 *  rather than clustered: a run would assert a pattern the data does not hold. */
function spreadMarks(total: number, marked: number): Set<number> {
  const out = new Set<number>()
  if (total <= 0 || marked <= 0) return out
  for (let k = 0; k < marked; k++) out.add(Math.min(total - 1, Math.floor(((k + 0.5) * total) / marked)))
  return out
}

function annualBarSegments(values: readonly number[]): { x0: number; x1: number }[] {
  const total = values.reduce((a, v) => a + Math.max(0, v), 0)
  let acc = 0
  return values.map((v) => {
    const x0 = ratio(acc, total)
    acc += Math.max(0, v)
    return { x0: q4(x0), x1: q4(ratio(acc, total)) }
  })
}

function hourScatterLayout(counts: readonly number[], maxRows: number): { col: number; row: number }[] {
  const out: { col: number; row: number }[] = []
  counts.forEach((c, col) => {
    for (let row = 0; row < Math.min(c, maxRows); row++) out.push({ col, row })
  })
  return out
}

/* ── shared marks ───────────────────────────────────────────────────────── */

const vars = (o: Record<string, string>): CSSProperties => o as CSSProperties

/** The over-channel that survives greyscale, print and a red-blind reader. The
 *  hatch cuts the solid mark instead of adding to it — red lines on a red
 *  ground would carry nothing. */
function Hatch({ id }: { id: string }) {
  return (
    <pattern id={id} width={HATCH.period} height={HATCH.period} patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <line x1="0" y1="0" x2="0" y2={HATCH.period} stroke="var(--c-paper)" strokeWidth={HATCH.stroke} />
    </pattern>
  )
}

/** '+¥688.00' / '−¥210.00' / '¥0.00'. The sign is typography, never colour. */
function signed(fen: Fen): string {
  return fen > 0 ? `+${format(fen)}` : format(fen)
}

/* ── 月度日柱 ───────────────────────────────────────────────────────────── */

export function MonthStrip({ data, onScrub }: { data: MonthStripData; onScrub?: (day: Day | null) => void }) {
  const { t } = useStore()
  const id = useId()
  const plot = useRef<HTMLDivElement>(null)
  const [active, setActive] = useState<number | null>(null)

  const bars = data.bars
  const n = bars.length
  const { bars: geo, standardY } = useMemo(
    () => monthStripLayout(bars.map((b) => b.spent), data.dailyStandard),
    [bars, data.dailyStandard],
  )

  let todayIndex = n - 1
  for (let i = 0; i < n; i++) if (!bars[i]!.future) todayIndex = i
  const elapsed = todayIndex + 1
  const spentToDate = bars.reduce((a, b) => (b.future ? a : a + b.spent), 0)
  // 破版: the month is already past its pro-rated standard, so the baseline
  // leaves the measure. A layout state, not an animation.
  const broken = data.dailyStandard > 0 && spentToDate > data.dailyStandard * elapsed

  const report = useCallback(
    (i: number | null) => {
      setActive(i)
      onScrub?.(i === null ? null : bars[i]!.day)
    },
    [bars, onScrub],
  )

  const pickAt = useCallback(
    (clientX: number) => {
      const box = plot.current?.getBoundingClientRect()
      if (!box || box.width === 0 || n === 0) return
      const i = Math.floor(((clientX - box.left) / box.width) * n)
      report(Math.min(n - 1, Math.max(0, i)))
    },
    [n, report],
  )

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId)
    pickAt(e.clientX)
  }
  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => pickAt(e.clientX)
  const onPointerEnd = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId)
    report(null)
  }

  const onKeyDown = (e: ReactKeyboardEvent<HTMLDivElement>) => {
    const at = active ?? todayIndex
    const step = e.key === 'ArrowLeft' ? -1 : e.key === 'ArrowRight' ? 1 : 0
    if (step !== 0) {
      e.preventDefault()
      report(Math.min(n - 1, Math.max(0, at + step)))
    } else if (e.key === 'Home') {
      e.preventDefault()
      report(0)
    } else if (e.key === 'End') {
      e.preventDefault()
      report(n - 1)
    } else if (e.key === 'Escape') {
      report(null)
    }
  }

  const dayText = (i: number): string => {
    const b = bars[i]!
    return t('chart.stripDay', { date: b.day.slice(5), amount: formatYuan(b.spent) })
  }

  const month: Month = n > 0 ? monthOf(bars[0]!.day) : ''
  const headline = t('chart.strip', {
    month,
    standard: formatYuan(data.dailyStandard),
    max: formatYuan(data.max),
  })

  return (
    <figure className="chart chart-strip" style={vars({ '--strip-h': `${STRIP.height}px`, '--tick-h': `${STRIP.tick + STRIP.tickGap}px` })}>
      <div className="chart-strip__plot" ref={plot}>
        <svg
          className="chart-strip__svg"
          viewBox={`0 0 ${PLOT_W} ${STRIP.height}`}
          preserveAspectRatio="none"
          shapeRendering="crispEdges"
          role="img"
          aria-label={headline}
          aria-describedby={`${id}-table`}
        >
          <defs>
            <Hatch id={`${id}-hatch`} />
          </defs>
          {n > 0 && (
            <line
              className="chart__hairline chart__hairline--today"
              x1={(geo[todayIndex]!.x + geo[todayIndex]!.w / 2) * PLOT_W}
              y1={0}
              x2={(geo[todayIndex]!.x + geo[todayIndex]!.w / 2) * PLOT_W}
              y2={STRIP.height}
              vectorEffect="non-scaling-stroke"
            />
          )}
          <g className="chart__mark">
            {geo.map((g, i) =>
              g.underH > 0 ? (
                <rect key={`u${i}`} x={g.x * PLOT_W} y={g.underY * STRIP.height} width={g.w * PLOT_W} height={g.underH * STRIP.height} />
              ) : null,
            )}
          </g>
          <g className="chart__mark chart__mark--over">
            {geo.map((g, i) =>
              g.overH > 0 ? (
                <rect key={`o${i}`} x={g.x * PLOT_W} y={g.overY * STRIP.height} width={g.w * PLOT_W} height={g.overH * STRIP.height} />
              ) : null,
            )}
          </g>
          <g fill={`url(#${id}-hatch)`}>
            {geo.map((g, i) =>
              g.overH > 0 ? (
                <rect key={`h${i}`} x={g.x * PLOT_W} y={g.overY * STRIP.height} width={g.w * PLOT_W} height={g.overH * STRIP.height} />
              ) : null,
            )}
          </g>
          {data.dailyStandard > 0 && (
            <line
              className="chart__reference"
              x1={0}
              y1={standardY * STRIP.height}
              x2={PLOT_W}
              y2={standardY * STRIP.height}
              vectorEffect="non-scaling-stroke"
            />
          )}
          {active !== null && (
            <line
              className="chart__hairline"
              x1={(geo[active]!.x + geo[active]!.w / 2) * PLOT_W}
              y1={0}
              x2={(geo[active]!.x + geo[active]!.w / 2) * PLOT_W}
              y2={STRIP.height}
              vectorEffect="non-scaling-stroke"
            />
          )}
        </svg>
        {data.dailyStandard > 0 && (
          <span className="chart-strip__standard t-micro" style={vars({ '--std-y': `${standardY * 100}%` })} aria-hidden="true">
            {t('chart.standardPerDay', { amount: formatYuan(data.dailyStandard) })}
          </span>
        )}
        <div
          className="chart-strip__scrub"
          role="slider"
          tabIndex={0}
          aria-label={t('chart.stripScrub')}
          aria-valuemin={0}
          aria-valuemax={Math.max(0, n - 1)}
          aria-valuenow={active ?? todayIndex}
          aria-valuetext={n > 0 ? dayText(active ?? todayIndex) : undefined}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerEnd}
          onPointerCancel={onPointerEnd}
          onPointerLeave={() => report(null)}
          onKeyDown={onKeyDown}
          onBlur={() => report(null)}
        />
      </div>
      <hr className={broken ? 'rule rule--strong rule--broken' : 'rule rule--strong'} />
      <svg className="chart-strip__ticks" viewBox={`0 0 ${PLOT_W} ${STRIP.tick + STRIP.tickGap}`} preserveAspectRatio="none" aria-hidden="true">
        {geo.map((g, i) =>
          isWeekend(bars[i]!.day) ? (
            <line
              key={i}
              className="chart-strip__weekend"
              x1={(g.x + g.w / 2) * PLOT_W}
              y1={STRIP.tickGap}
              x2={(g.x + g.w / 2) * PLOT_W}
              y2={STRIP.tickGap + STRIP.tick}
              vectorEffect="non-scaling-stroke"
            />
          ) : null,
        )}
      </svg>
      <table id={`${id}-table`} className="sr-only">
        <thead>
          <tr>
            <th scope="col">{t('chart.colDay')}</th>
            <th scope="col">{t('chart.colAmount')}</th>
          </tr>
        </thead>
        <tbody>
          {bars.map((b) =>
            b.future ? null : (
              <tr key={b.day}>
                <th scope="row">{b.day}</th>
                <td>{format(b.spent)}</td>
              </tr>
            ),
          )}
        </tbody>
      </table>
    </figure>
  )
}

/* ── 偏差条 ─────────────────────────────────────────────────────────────── */

const DEVIATION_VARS = {
  '--row-h': `${DEVIATION.rowHeight}px`,
  '--bar-h': `${DEVIATION.barHeight}px`,
  '--name-w': 'calc(var(--s-10) + var(--s-4))',
  '--fig-w': 'calc(var(--s-10) + var(--s-7))',
}

/** One row's bar. The mark restates a figure that is already printed beside it,
 *  so it is hidden from the reading order rather than labelled twice. */
function Bar({ span, hatchId }: { span: Span; hatchId: string }) {
  const x = span.x0 * PLOT_W
  const w = (span.x1 - span.x0) * PLOT_W
  return (
    <svg
      className="chart-deviation__bar"
      viewBox={`0 0 ${PLOT_W} ${DEVIATION.barHeight}`}
      preserveAspectRatio="none"
      shapeRendering="crispEdges"
      aria-hidden="true"
    >
      <rect className={span.over ? 'chart__mark chart__mark--over' : 'chart__mark'} x={x} y={0} width={w} height={DEVIATION.barHeight} />
      {span.over && <rect x={x} y={0} width={w} height={DEVIATION.barHeight} fill={`url(#${hatchId})`} />}
    </svg>
  )
}

export function DeviationBars({ rows, nameOf }: { rows: readonly Deviation[]; nameOf: (id: string) => string }) {
  const { t } = useStore()
  const id = useId()
  const spans = useMemo(() => deviationLayout(rows.map((r) => r.delta)), [rows])
  const maxAbs = rows.reduce((m, r) => Math.max(m, Math.abs(r.delta)), 0)
  const broken = rows.reduce((a, r) => a + r.delta, 0) > 0

  if (rows.length === 0) return <p className="chart__gate t-body ink-700">{t('chart.empty')}</p>

  return (
    <figure className="chart chart-deviation" style={vars(DEVIATION_VARS)}>
      <figcaption className="sr-only">{t('chart.deviation', { n: rows.length, max: formatYuan(maxAbs) })}</figcaption>
      <svg className="chart__defs" aria-hidden="true" focusable="false">
        <defs>
          <Hatch id={`${id}-hatch`} />
        </defs>
      </svg>
      <div className={broken ? 'chart-deviation__rows chart-deviation__rows--broken' : 'chart-deviation__rows'}>
        <span className="chart-deviation__zero" aria-hidden="true" />
        {rows.map((r, i) => (
          <div className="chart-deviation__row" key={r.categoryId}>
            <span className="chart-deviation__name t-body ink-700">{nameOf(r.categoryId)}</span>
            <Bar span={spans[i]!} hatchId={`${id}-hatch`} />
            <span className={r.delta > 0 ? 'chart__fig fig-over' : 'chart__fig ink-900'}>{signed(r.delta)}</span>
          </div>
        ))}
      </div>
      <div className="chart-deviation__ticks" aria-hidden="true">
        <span className="t-micro">{MINUS + formatYuan(maxAbs)}</span>
        <span className="t-micro">{`+${formatYuan(maxAbs)}`}</span>
      </div>
    </figure>
  )
}

/* ── 年账页 ─────────────────────────────────────────────────────────────── */

export function YearLedger({ months }: { months: readonly { month: Month; spent: Fen; standard: Fen }[] }) {
  const { t } = useStore()
  const id = useId()
  const spans = useMemo(() => deviationLayout(months.map((m) => m.spent - m.standard)), [months])
  const maxAbs = months.reduce((m, r) => Math.max(m, Math.abs(r.spent - r.standard)), 0)

  if (months.length === 0) return <p className="chart__gate t-body ink-700">{t('chart.empty')}</p>

  return (
    <figure className="chart chart-deviation chart-year" style={vars({ ...DEVIATION_VARS, '--row-h': `${YEAR_ROW_H}px` })}>
      <figcaption className="sr-only">{t('chart.year', { n: months.length, max: formatYuan(maxAbs) })}</figcaption>
      <svg className="chart__defs" aria-hidden="true" focusable="false">
        <defs>
          <Hatch id={`${id}-hatch`} />
        </defs>
      </svg>
      <div className="chart-deviation__rows">
        <span className="chart-deviation__zero" aria-hidden="true" />
        {months.map((m, i) => {
          const delta = m.spent - m.standard
          return (
            <div className="chart-deviation__row" key={m.month}>
              <span className="chart-year__label t-mono ink-500">{m.month.slice(5)}</span>
              <Bar span={spans[i]!} hatchId={`${id}-hatch`} />
              <span className={delta > 0 ? 'chart__fig fig-over' : 'chart__fig ink-900'}>{signed(delta)}</span>
            </div>
          )
        })}
      </div>
    </figure>
  )
}

/* ── 后悔率 ─────────────────────────────────────────────────────────────── */

export function RegretBlocks({ judged, notWorth }: { judged: number; notWorth: number }) {
  const { t } = useStore()
  const id = useId()
  const cols = Math.max(REGRET.minCols, Math.floor((PLOT_W + REGRET.gap) / (REGRET.unit + REGRET.gap)))

  if (judged < REGRET.minSample) {
    // The rate is withheld, and what is withholding it is stated instead.
    return (
      <p className="chart__gate t-body ink-700" style={vars({ '--gate-h': `${Math.ceil(REGRET.minSample / cols) * (REGRET.unit + REGRET.gap)}px` })}>
        {t('chart.regretGate', { n: REGRET.minSample - judged })}
      </p>
    )
  }

  const marked = spreadMarks(judged, notWorth)
  const cells = regretBlockLayout(judged, marked, cols)
  const rows = Math.ceil(judged / cols)
  const w = cols * (REGRET.unit + REGRET.gap) - REGRET.gap
  const h = rows * (REGRET.unit + REGRET.gap) - REGRET.gap
  const caption = t('chart.regretBlock', {
    judged,
    notWorth,
    rate: `${((notWorth / judged) * 100).toFixed(1)}%`,
  })

  return (
    <figure className="chart chart-regret">
      <svg className="chart-regret__svg" viewBox={`0 0 ${w} ${h}`} shapeRendering="crispEdges" role="img" aria-label={caption}>
        <defs>
          <Hatch id={`${id}-hatch`} />
        </defs>
        {cells.map((c, i) => {
          const x = c.col * (REGRET.unit + REGRET.gap)
          const y = c.row * (REGRET.unit + REGRET.gap)
          return (
            <g key={i}>
              <rect className={c.bad ? 'chart__mark chart__mark--over' : 'chart-regret__kept'} x={x} y={y} width={REGRET.unit} height={REGRET.unit} />
              {c.bad && <rect x={x} y={y} width={REGRET.unit} height={REGRET.unit} fill={`url(#${id}-hatch)`} />}
            </g>
          )
        })}
      </svg>
      <figcaption className="chart-regret__caption t-body ink-700">{caption}</figcaption>
    </figure>
  )
}

/* ── 订阅年化条 ─────────────────────────────────────────────────────────── */

export function AnnualBar({ rows }: { rows: readonly { label: string; annual: Fen }[] }) {
  const { t } = useStore()

  const merged = useMemo(() => {
    const ranked = [...rows].sort((a, b) => b.annual - a.annual)
    const total = ranked.reduce((a, r) => a + Math.max(0, r.annual), 0)
    // A segment thinner than 3px is a smudge, not a reading. They are summed
    // into one 其他 rather than drawn as noise.
    const floor = total * (ANNUAL.minSegment / PLOT_W)
    const kept = ranked.filter((r) => r.annual >= floor)
    const rest = ranked.filter((r) => r.annual < floor).reduce((a, r) => a + r.annual, 0)
    return rest > 0 ? [...kept, { label: t('chart.annualOther'), annual: rest }] : kept
  }, [rows, t])

  if (merged.length === 0) return <p className="chart__gate t-body ink-700">{t('chart.empty')}</p>

  const segments = annualBarSegments(merged.map((r) => r.annual))
  const total = merged.reduce((a, r) => a + r.annual, 0)

  return (
    <figure className="chart chart-annual" style={vars({ '--annual-h': `${ANNUAL.height}px` })}>
      <svg
        className="chart-annual__svg"
        viewBox={`0 0 ${PLOT_W} ${ANNUAL.height}`}
        preserveAspectRatio="none"
        shapeRendering="crispEdges"
        role="img"
        aria-label={t('chart.annual', { amount: formatYuan(total) })}
      >
        {segments.map((s, i) => (
          <rect
            key={i}
            className={i % 2 === 0 ? 'chart__mark' : 'chart__mark chart__mark--second'}
            x={s.x0 * PLOT_W}
            y={0}
            width={(s.x1 - s.x0) * PLOT_W}
            height={ANNUAL.height}
          />
        ))}
        {segments.slice(1).map((s, i) => (
          <line
            key={`g${i}`}
            className="chart-annual__gap"
            x1={s.x0 * PLOT_W}
            y1={0}
            x2={s.x0 * PLOT_W}
            y2={ANNUAL.height}
            vectorEffect="non-scaling-stroke"
          />
        ))}
      </svg>
      <ol className="chart-annual__list">
        {merged.map((r) => (
          <li className="t-micro ink-500" key={r.label}>
            {t('chart.annualRow', { name: r.label, amount: formatYuan(r.annual) })}
          </li>
        ))}
      </ol>
    </figure>
  )
}

/* ── 时段散点 ───────────────────────────────────────────────────────────── */

export function HourScatter({ data }: { data: readonly { hour: number; count: number; sum: Fen }[] }) {
  const { t } = useStore()
  const id = useId()
  const dots = useMemo(() => hourScatterLayout(data.map((d) => d.count), HOURS.maxRows), [data])
  const cols = data.length
  const pitch = cols === 0 ? 0 : PLOT_W / cols
  const total = data.reduce((a, d) => a + d.count, 0)
  const peak = data.reduce((m, d) => (d.count > m.count ? d : m), { hour: 0, count: 0, sum: 0 })

  if (cols === 0) return <p className="chart__gate t-body ink-700">{t('chart.empty')}</p>

  const hh = (h: number): string => String(h).padStart(2, '0')

  return (
    <figure className="chart chart-hours" style={vars({ '--hours-h': `${HOURS.height}px` })}>
      <div className="chart-hours__plot">
        <svg
          className="chart-hours__svg"
          viewBox={`0 0 ${PLOT_W} ${HOURS.height}`}
          preserveAspectRatio="none"
          shapeRendering="crispEdges"
          role="img"
          aria-label={t('chart.hour', { n: total })}
          aria-describedby={`${id}-table`}
        >
          <g className="chart__mark">
            {dots.map((d, i) => (
              <rect
                key={i}
                x={d.col * pitch + (pitch - HOURS.dot) / 2}
                y={HOURS.height - (d.row + 1) * (HOURS.dot + HOURS.gap) + HOURS.gap}
                width={HOURS.dot}
                height={HOURS.dot}
              />
            ))}
          </g>
        </svg>
        {data.map((d) =>
          d.count > HOURS.maxRows ? (
            <span
              className="chart-hours__more t-micro ink-500"
              key={d.hour}
              style={vars({
                '--col-x': `${((d.hour * pitch + pitch / 2) / PLOT_W) * 100}%`,
                '--col-y': `${((HOURS.maxRows * (HOURS.dot + HOURS.gap)) / HOURS.height) * 100}%`,
              })}
              aria-hidden="true"
            >
              {t('chart.hourMore', { n: d.count - HOURS.maxRows })}
            </span>
          ) : null,
        )}
      </div>
      <hr className="rule rule--strong" />
      <div className="chart-hours__foot">
        <span className="t-micro" aria-hidden="true">{hh(data[0]!.hour)}</span>
        <span className="t-micro ink-500">{t('chart.hourPeak', { hour: hh(peak.hour), n: peak.count })}</span>
        <span className="t-micro" aria-hidden="true">{hh(data[cols - 1]!.hour)}</span>
      </div>
      <table id={`${id}-table`} className="sr-only">
        <thead>
          <tr>
            <th scope="col">{t('chart.colHour')}</th>
            <th scope="col">{t('chart.colCount')}</th>
            <th scope="col">{t('chart.colAmount')}</th>
          </tr>
        </thead>
        <tbody>
          {data.map((d) => (
            <tr key={d.hour}>
              <th scope="row">{`${hh(d.hour)}:00`}</th>
              <td>{d.count}</td>
              <td>{format(d.sum)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </figure>
  )
}
