import SwiftUI

/*
 * Every form here is drawn by hand. The layout functions below are a
 * line-by-line port of `web/src/ui/charts.tsx`: pure, normalised to [0, 1], no
 * clock and no view. `ChartGeometryTests` asserts they return the coordinates
 * the TypeScript returns, which is the only thing keeping six hand-drawn
 * charts comparable across two languages.
 *
 * Amounts are printed with the shared formatter rather than composed through
 * the money parts: a deviation figure must carry an explicit U+002B, which the
 * parts deliberately never emit, and a chart label is a single string rather
 * than the three-part ledger treatment.
 */

// MARK: - geometry constants (design/DESIGN.md §7, mirrored from charts.tsx)

enum ChartGeom {
    /// The phone content column, 360 − 2 × 20 gutter. Charts are laid out at
    /// this width and stretched horizontally into whatever column they land in,
    /// so the vertical metrics below are exact points at every size class.
    static let plotW: CGFloat = 320

    static let stripHeight: CGFloat = 96
    static let stripBarRatio: Double = 0.6
    static let stripTick: CGFloat = 3
    static let stripTickGap: CGFloat = 3
    static let stripHeadroom: Double = 1.6

    static let deviationBarHeight: CGFloat = 6
    static let deviationRowHeight: CGFloat = 34
    static let deviationMinBar: CGFloat = 2
    static let yearRowHeight: CGFloat = 28
    /// `--name-w` / `--fig-w` from charts.css, in the tokens they are built from.
    static let nameWidth: CGFloat = Space.s10 + Space.s4
    static let figureWidth: CGFloat = Space.s10 + Space.s7

    static let regretUnit: CGFloat = 8
    static let regretGap: CGFloat = 3
    static let regretMinCols = 12
    /// The gate is the product rule, not a drawing constant.
    static var regretMinSample: Int { Rules.minJudgedForRegretRate }

    static let annualHeight: CGFloat = 14
    static let annualMinSegment: CGFloat = 3

    static let hourDot: CGFloat = 3
    static let hourGap: CGFloat = 2
    static let hourMaxRows = 10
    static let hourHeight: CGFloat = 96

    static let hatchPeriod: CGFloat = 4
}

// MARK: - shared geometry: pure, normalised to [0,1], no view, no clock

/// Round half away from zero, to 4 places. JS rounds −0.5 to −0 and Swift to
/// −1; pinning it here, in the same shape the TypeScript uses, is what lets the
/// two platforms agree.
func q4(_ x: Double) -> Double {
    let v = x * 10_000
    return (v < 0 ? -((-v).rounded(.toNearestOrAwayFromZero)) : v.rounded(.toNearestOrAwayFromZero)) / 10_000
}

private func ratio(_ n: Double, _ d: Double) -> Double {
    d == 0 ? 0 : n / d
}

struct ChartSpan: Equatable, Sendable {
    let i: Int
    let x0: Double
    let x1: Double
    let over: Bool
}

/// Symmetric about 0.5, scaled so the largest absolute deviation touches an edge.
func deviationLayout(_ deltas: [Fen]) -> [ChartSpan] {
    let maxAbs = deltas.reduce(0.0) { max($0, Double($1).magnitude) }
    let floorLen = Double(ChartGeom.deviationMinBar / ChartGeom.plotW)
    return deltas.enumerated().map { i, d in
        let over = d > 0
        var len = ratio(Double(d), maxAbs).magnitude / 2
        if d != 0 && len < floorLen { len = floorLen }
        return ChartSpan(
            i: i,
            x0: q4(over ? 0.5 : 0.5 - len),
            x1: q4(over ? 0.5 + len : 0.5),
            over: over
        )
    }
}

struct StripBar: Equatable, Sendable {
    let x: Double
    let w: Double
    let underY: Double
    let underH: Double
    let overY: Double
    let overH: Double
}

func monthStripLayout(_ daily: [Fen], _ standard: Fen) -> (bars: [StripBar], standardY: Double) {
    let n = daily.count
    let peak = daily.reduce(0) { max($0, $1) }
    // Headroom keeps the standard line off the top edge, so a day that clears
    // it has somewhere to go.
    let top = max(Double(peak), Double(standard) * ChartGeom.stripHeadroom, 1)
    let pitch = n == 0 ? 0 : 1 / Double(n)
    let w = pitch * ChartGeom.stripBarRatio
    let bars = daily.enumerated().map { i, v -> StripBar in
        let whole = ratio(Double(v), top)
        // A day equal to the standard is under it: the comparison is strict.
        let under = ratio(Double(min(v, standard)), top)
        return StripBar(
            x: q4(Double(i) * pitch + (pitch - w) / 2),
            w: q4(w),
            underY: q4(1 - under),
            underH: q4(under),
            overY: q4(1 - whole),
            overH: q4(whole - under)
        )
    }
    return (bars, q4(1 - ratio(Double(standard), top)))
}

struct RegretCell: Equatable, Sendable {
    let col: Int
    let row: Int
    let bad: Bool
}

func regretBlockLayout(_ count: Int, _ marked: Set<Int>, _ cols: Int) -> [RegretCell] {
    guard cols > 0 else { return [] }
    var out: [RegretCell] = []
    out.reserveCapacity(max(0, count))
    for i in 0..<max(0, count) {
        out.append(RegretCell(col: i % cols, row: i / cols, bad: marked.contains(i)))
    }
    return out
}

/// Counts alone carry no chronology, so the 不值 squares are spread evenly
/// rather than clustered: a run would assert a pattern the data does not hold.
func spreadMarks(_ total: Int, _ marked: Int) -> Set<Int> {
    var out = Set<Int>()
    if total <= 0 || marked <= 0 { return out }
    for k in 0..<marked {
        let at = ((Double(k) + 0.5) * Double(total) / Double(marked)).rounded(.down)
        out.insert(min(total - 1, Int(at)))
    }
    return out
}

struct AnnualSegment: Equatable, Sendable {
    let x0: Double
    let x1: Double
}

func annualBarSegments(_ values: [Fen]) -> [AnnualSegment] {
    let total = values.reduce(0) { $0 + max(0, $1) }
    var acc = 0
    return values.map { v in
        let x0 = ratio(Double(acc), Double(total))
        acc += max(0, v)
        return AnnualSegment(x0: q4(x0), x1: q4(ratio(Double(acc), Double(total))))
    }
}

struct ScatterDot: Equatable, Sendable {
    let col: Int
    let row: Int
}

func hourScatterLayout(_ counts: [Int], _ maxRows: Int) -> [ScatterDot] {
    var out: [ScatterDot] = []
    for (col, c) in counts.enumerated() {
        let rows = min(c, maxRows)
        if rows <= 0 { continue }
        for row in 0..<rows { out.append(ScatterDot(col: col, row: row)) }
    }
    return out
}

// MARK: - shared marks

/// The over-channel that survives greyscale, print and a red-blind reader. The
/// hatch cuts the solid mark instead of adding to it — red lines on a red
/// ground would carry nothing.
private func hatchPath(in rect: CGRect, period: CGFloat = ChartGeom.hatchPeriod) -> Path {
    var path = Path()
    guard rect.width > 0, rect.height > 0, period > 0 else { return path }
    // Lines run at 45° (x − y = c); the perpendicular spacing of a family of
    // 45° lines whose intercepts differ by Δc is Δc/√2, so Δc = period·√2.
    let step = period * CGFloat(2.0.squareRoot())
    var c = rect.minX - rect.maxY
    let last = rect.maxX - rect.minY
    while c <= last {
        path.move(to: CGPoint(x: c + rect.minY, y: rect.minY))
        path.addLine(to: CGPoint(x: c + rect.maxY, y: rect.maxY))
        c += step
    }
    return path
}

private func fillOver(_ ctx: inout GraphicsContext, _ rect: CGRect) {
    ctx.fill(Path(rect), with: .color(Ink.figOver))
    ctx.drawLayer { layer in
        layer.clip(to: Path(rect))
        layer.stroke(hatchPath(in: rect), with: .color(Ink.paper), lineWidth: Layout.hairline)
    }
}

/// §4.4: marks land on whole device pixels, using the same round-half-away-from-zero
/// rule the geometry module uses, applied at the render layer rather than in it.
private func snap(_ v: CGFloat, _ scale: CGFloat) -> CGFloat {
    guard scale > 0 else { return v }
    return (v * scale).rounded(.toNearestOrAwayFromZero) / scale
}

/// `+¥688` / `−¥210` / `¥0`. The sign is typography, never colour.
private func signedYuan(_ fen: Fen) -> String {
    fen > 0 ? "+" + format(fen) : format(fen)
}

private func hh(_ hour: Int) -> String {
    hour < 10 && hour >= 0 ? "0\(hour)" : "\(hour)"
}

/// JS `toFixed(1)` rounds half away from zero on the decimal value; `%.1f`
/// rounds half to even on the binary one, so the rounding is done first.
private func fixed1(_ x: Double) -> String {
    String(format: "%.1f", (x * 10).rounded(.toNearestOrAwayFromZero) / 10)
}

/// The only entry animation a chart gets: opacity, nothing grows from a baseline.
private struct ChartReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else {
                    withAnimation(Motion.ease(Motion.rowFade)) { shown = true }
                }
            }
    }
}

private extension View {
    func chartReveal() -> some View { modifier(ChartReveal()) }
}

/// A withheld statistic keeps the height its chart would have taken, so the
/// page does not jump on the day the sample arrives.
private struct ChartGate: View {
    let text: String
    var minHeight: CGFloat = Space.s10

    var body: some View {
        Text(text)
            .font(TypeScale.body.font)
            .lineSpacing(TypeScale.body.lineSpacing)
            .foregroundStyle(Ink.ink700)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(.vertical, Space.s3)
    }
}

// MARK: - 月度日柱

@MainActor
struct MonthStripView: View {
    let data: MonthStrip
    var onScrub: ((Day?) -> Void)?

    @Environment(\.displayScale) private var displayScale
    @State private var active: Int?

    private let geo: [StripBar]
    private let standardY: Double
    private let todayIndex: Int
    /// 破版: the month is already past its pro-rated standard, so the baseline
    /// leaves the measure. A layout state, not an animation.
    private let broken: Bool

    init(data: MonthStrip, onScrub: ((Day?) -> Void)? = nil) {
        self.data = data
        self.onScrub = onScrub
        let layout = monthStripLayout(data.bars.map(\.spent), data.dailyStandard)
        geo = layout.bars
        standardY = layout.standardY

        var last = data.bars.count - 1
        for (i, b) in data.bars.enumerated() where !b.future { last = i }
        todayIndex = last

        let spentToDate = data.bars.reduce(0) { $0 + ($1.future ? 0 : $1.spent) }
        broken = data.dailyStandard > 0 && spentToDate > data.dailyStandard * (last + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            plot
            baseline
            ticks
        }
        .chartReveal()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline)
        .accessibilityValue(geo.isEmpty ? "" : dayText(active ?? todayIndex))
        .accessibilityHint(S.t(.chartStripScrub))
        .accessibilityAdjustableAction { direction in
            guard !geo.isEmpty else { return }
            let step = direction == .increment ? 1 : -1
            report(min(geo.count - 1, max(0, (active ?? todayIndex) + step)))
        }
    }

    private var plot: some View {
        Canvas(opaque: false) { ctx, size in
            let scale = displayScale
            if !geo.isEmpty {
                let g = geo[todayIndex]
                let x = snap((g.x + g.w / 2) * size.width, scale)
                ctx.stroke(vertical(x, size.height), with: .color(Ink.ruleStrong), lineWidth: Layout.hairline)
            }
            for g in geo where g.underH > 0 {
                ctx.fill(Path(rect(g.x, g.w, g.underY, g.underH, size, scale)), with: .color(Ink.ink700))
            }
            for g in geo where g.overH > 0 {
                fillOver(&ctx, rect(g.x, g.w, g.overY, g.overH, size, scale))
            }
            if data.dailyStandard > 0 {
                let y = snap(standardY * size.height, scale)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(Ink.ruleStrong), lineWidth: Layout.hairline)
            }
            if let active, active < geo.count {
                let g = geo[active]
                let x = snap((g.x + g.w / 2) * size.width, scale)
                ctx.stroke(vertical(x, size.height), with: .color(Ink.ink500), lineWidth: Layout.hairline)
            }
        }
        .frame(height: ChartGeom.stripHeight)
        // The daily standard, printed at the line it draws.
        .overlay(alignment: .topTrailing) {
            if data.dailyStandard > 0 {
                Text(S.t(.chartStandardPerDay, ["amount": formatYuan(data.dailyStandard)]))
                    .font(TypeScale.micro.font)
                    .kerning(TypeScale.micro.kerning)
                    .foregroundStyle(Ink.ink500)
                    .padding(.horizontal, Space.s1)
                    .background(Ink.paper)
                    .alignmentGuide(.top) { $0[.bottom] - standardY * ChartGeom.stripHeight }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { pick($0.location.x, proxy.size.width) }
                            .onEnded { _ in report(nil) }
                    )
            }
            .frame(minHeight: Layout.hitTarget)
        }
        .accessibilityHidden(true)
    }

    private var baseline: some View {
        Rectangle()
            .fill(broken ? Ink.figOver : Ink.ruleStrong)
            .frame(height: Layout.hairline)
            .padding(.horizontal, broken ? -Space.s5 : 0)
    }

    private var ticks: some View {
        Canvas(opaque: false) { ctx, size in
            let scale = displayScale
            for (i, g) in geo.enumerated() where isWeekend(data.bars[i].day) {
                let x = snap((g.x + g.w / 2) * size.width, scale)
                var line = Path()
                line.move(to: CGPoint(x: x, y: ChartGeom.stripTickGap))
                line.addLine(to: CGPoint(x: x, y: ChartGeom.stripTickGap + ChartGeom.stripTick))
                ctx.stroke(line, with: .color(Ink.ink300), lineWidth: Layout.hairline)
            }
        }
        .frame(height: ChartGeom.stripTick + ChartGeom.stripTickGap)
        .accessibilityHidden(true)
    }

    private var headline: String {
        let month: Month = data.bars.isEmpty ? "" : monthOf(data.bars[0].day)
        return S.t(.chartStrip, [
            "month": month,
            "standard": formatYuan(data.dailyStandard),
            "max": formatYuan(data.max),
        ])
    }

    private func dayText(_ i: Int) -> String {
        let b = data.bars[i]
        return S.t(.chartStripDay, ["date": String(b.day.suffix(5)), "amount": formatYuan(b.spent)])
    }

    private func rect(_ x: Double, _ w: Double, _ y: Double, _ h: Double, _ size: CGSize, _ scale: CGFloat) -> CGRect {
        let x0 = snap(CGFloat(x) * size.width, scale)
        let x1 = snap(CGFloat(x + w) * size.width, scale)
        let y0 = snap(CGFloat(y) * size.height, scale)
        let y1 = snap(CGFloat(y + h) * size.height, scale)
        let unit = scale > 0 ? 1 / scale : 1
        return CGRect(x: x0, y: y0, width: max(unit, x1 - x0), height: max(unit, y1 - y0))
    }

    private func vertical(_ x: CGFloat, _ height: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: 0))
        p.addLine(to: CGPoint(x: x, y: height))
        return p
    }

    private func pick(_ x: CGFloat, _ width: CGFloat) {
        let n = geo.count
        guard width > 0, n > 0 else { return }
        let i = Int((x / width * CGFloat(n)).rounded(.down))
        report(min(n - 1, max(0, i)))
    }

    private func report(_ i: Int?) {
        guard active != i else { return }
        active = i
        onScrub?(i == nil ? nil : data.bars[i!].day)
    }
}

// MARK: - 偏差条

/// One row's bar. The mark restates a figure that is already printed beside it,
/// so it is hidden from the reading order rather than labelled twice.
private struct DeviationBar: View {
    let span: ChartSpan

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas(opaque: false) { ctx, size in
            let scale = displayScale
            let x0 = snap(CGFloat(span.x0) * size.width, scale)
            let x1 = snap(CGFloat(span.x1) * size.width, scale)
            let unit = scale > 0 ? 1 / scale : 1
            guard x1 - x0 > 0 else { return }
            let r = CGRect(x: x0, y: 0, width: max(unit, x1 - x0), height: size.height)
            if span.over {
                fillOver(&ctx, r)
            } else {
                ctx.fill(Path(r), with: .color(Ink.ink700))
            }
        }
        .frame(height: ChartGeom.deviationBarHeight)
        .accessibilityHidden(true)
    }
}

/// The vertical rule at zero, sitting behind the rows and centred on the bar
/// column. 破版: over standard, it is the one thing that leaves the block.
private struct ZeroRule: View {
    let broken: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            Color.clear.frame(width: ChartGeom.nameWidth)
            Rectangle()
                .fill(broken ? Ink.figOver : Ink.ruleStrong)
                .frame(width: Layout.hairline)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: ChartGeom.figureWidth)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, broken ? -Space.s5 : 0)
        .accessibilityHidden(true)
    }
}

@MainActor
struct DeviationBarsView: View {
    let rows: [Deviation]
    let nameOf: (String) -> String

    private let spans: [ChartSpan]
    private let maxAbs: Fen
    private let broken: Bool

    init(rows: [Deviation], nameOf: @escaping (String) -> String) {
        self.rows = rows
        self.nameOf = nameOf
        spans = deviationLayout(rows.map(\.delta))
        maxAbs = rows.reduce(0) { max($0, abs($1.delta)) }
        broken = rows.reduce(0) { $0 + $1.delta } > 0
    }

    var body: some View {
        if rows.isEmpty {
            ChartGate(text: S.t(.chartEmpty))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.categoryId) { i, row in
                        line(row, spans[i])
                    }
                }
                .background(alignment: .top) { ZeroRule(broken: broken) }
                ticks
            }
            .chartReveal()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(S.t(.chartDeviation, ["n": rows.count, "max": formatYuan(maxAbs)]))
        }
    }

    private func line(_ row: Deviation, _ span: ChartSpan) -> some View {
        HStack(spacing: Space.s2) {
            Text(nameOf(row.categoryId))
                .font(TypeScale.body.font)
                .foregroundStyle(Ink.ink700)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: ChartGeom.nameWidth, alignment: .leading)
            DeviationBar(span: span)
                .frame(maxWidth: .infinity)
            Text(signedYuan(row.delta))
                .font(TypeScale.row.font)
                .monospacedDigit()
                .foregroundStyle(row.delta > 0 ? Ink.figOver : Ink.ink900)
                .lineLimit(1)
                .frame(width: ChartGeom.figureWidth, alignment: .trailing)
        }
        .frame(minHeight: ChartGeom.deviationRowHeight)
        .accessibilityElement(children: .combine)
    }

    private var ticks: some View {
        HStack(spacing: Space.s2) {
            Color.clear.frame(width: ChartGeom.nameWidth, height: 0)
            Text(minus + formatYuan(maxAbs))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("+" + formatYuan(maxAbs))
                .frame(width: ChartGeom.figureWidth, alignment: .trailing)
        }
        .font(TypeScale.micro.font)
        .kerning(TypeScale.micro.kerning)
        .foregroundStyle(Ink.ink500)
        .padding(.top, Space.s2)
        .accessibilityHidden(true)
    }
}

// MARK: - 年账页

struct YearLedgerRow: Equatable, Sendable {
    let month: Month
    let spent: Fen
    let standard: Fen

    var delta: Fen { spent - standard }
}

@MainActor
struct YearLedgerView: View {
    let months: [YearLedgerRow]

    private let spans: [ChartSpan]
    private let maxAbs: Fen

    init(months: [YearLedgerRow]) {
        self.months = months
        spans = deviationLayout(months.map(\.delta))
        maxAbs = months.reduce(0) { max($0, abs($1.delta)) }
    }

    var body: some View {
        if months.isEmpty {
            ChartGate(text: S.t(.chartEmpty))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.element.month) { i, row in
                    line(row, spans[i])
                }
            }
            .background(alignment: .top) { ZeroRule(broken: false) }
            .chartReveal()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(S.t(.chartYear, ["n": months.count, "max": formatYuan(maxAbs)]))
        }
    }

    private func line(_ row: YearLedgerRow, _ span: ChartSpan) -> some View {
        HStack(spacing: Space.s2) {
            Text(String(row.month.suffix(2)))
                .font(.system(size: TypeScale.label.size, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.ink500)
                .frame(width: ChartGeom.nameWidth, alignment: .leading)
            DeviationBar(span: span)
                .frame(maxWidth: .infinity)
            Text(signedYuan(row.delta))
                .font(TypeScale.row.font)
                .monospacedDigit()
                .foregroundStyle(row.delta > 0 ? Ink.figOver : Ink.ink900)
                .lineLimit(1)
                .frame(width: ChartGeom.figureWidth, alignment: .trailing)
        }
        .frame(minHeight: ChartGeom.yearRowHeight)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 后悔率

@MainActor
struct RegretBlocksView: View {
    let judged: Int
    let notWorth: Int

    @Environment(\.displayScale) private var displayScale

    private static let cols = max(
        ChartGeom.regretMinCols,
        Int(((ChartGeom.plotW + ChartGeom.regretGap) / (ChartGeom.regretUnit + ChartGeom.regretGap)).rounded(.down))
    )

    /// One square per judged entry, so the block is laid out once at
    /// construction: a `body` that rebuilt it would walk the whole judged
    /// history on every scroll tick.
    private let cells: [RegretCell]
    private let plotW: CGFloat
    private let plotH: CGFloat
    private let caption: String

    init(judged: Int, notWorth: Int) {
        self.judged = judged
        self.notWorth = notWorth
        let cols = Self.cols
        let gated = judged < ChartGeom.regretMinSample
        cells = gated ? [] : regretBlockLayout(judged, spreadMarks(judged, notWorth), cols)
        let rows = gated ? 0 : Int((Double(judged) / Double(cols)).rounded(.up))
        plotW = CGFloat(cols) * (ChartGeom.regretUnit + ChartGeom.regretGap) - ChartGeom.regretGap
        plotH = CGFloat(rows) * (ChartGeom.regretUnit + ChartGeom.regretGap) - ChartGeom.regretGap
        caption = gated ? "" : S.t(.chartRegretBlock, [
            "judged": judged,
            "notWorth": notWorth,
            "rate": fixed1(Double(notWorth) / Double(judged) * 100) + "%",
        ])
    }

    var body: some View {
        if judged < ChartGeom.regretMinSample {
            // The rate is withheld, and what is withholding it is stated instead.
            let rows = (Double(ChartGeom.regretMinSample) / Double(Self.cols)).rounded(.up)
            ChartGate(
                text: S.t(.chartRegretGate, ["n": ChartGeom.regretMinSample - judged]),
                minHeight: CGFloat(rows) * (ChartGeom.regretUnit + ChartGeom.regretGap)
            )
        } else {
            block
        }
    }

    // 9 red squares in 40 need no legend, so the caption is the whole label and
    // the squares carry nothing on their own.
    private var block: some View {
        VStack(alignment: .leading, spacing: 0) {
            Canvas(opaque: false) { ctx, size in
                let scale = displayScale
                // Unit squares must stay square, so this one form scales uniformly.
                let k = size.width / plotW
                for c in cells {
                    let r = CGRect(
                        x: snap(CGFloat(c.col) * (ChartGeom.regretUnit + ChartGeom.regretGap) * k, scale),
                        y: snap(CGFloat(c.row) * (ChartGeom.regretUnit + ChartGeom.regretGap) * k, scale),
                        width: snap(ChartGeom.regretUnit * k, scale),
                        height: snap(ChartGeom.regretUnit * k, scale)
                    )
                    if c.bad {
                        fillOver(&ctx, r)
                    } else {
                        ctx.fill(Path(r), with: .color(Ink.ink900))
                    }
                }
            }
            .aspectRatio(plotW / max(plotH, 1), contentMode: .fit)
            Text(caption)
                .font(TypeScale.body.font)
                .foregroundStyle(Ink.ink700)
                .padding(.top, Space.s3)
        }
        .chartReveal()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }
}

// MARK: - 订阅年化条

struct AnnualBarRow: Equatable, Sendable {
    let label: String
    let annual: Fen
}

@MainActor
struct AnnualBarView: View {
    let rows: [AnnualBarRow]

    @Environment(\.displayScale) private var displayScale

    private let merged: [AnnualBarRow]
    private let segments: [AnnualSegment]
    private let total: Fen

    init(rows: [AnnualBarRow]) {
        self.rows = rows
        merged = Self.merge(rows)
        segments = annualBarSegments(merged.map(\.annual))
        total = merged.reduce(0) { $0 + $1.annual }
    }

    var body: some View {
        if merged.isEmpty {
            ChartGate(text: S.t(.chartEmpty))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Canvas(opaque: false) { ctx, size in
                    let scale = displayScale
                    for (i, s) in segments.enumerated() {
                        let x0 = snap(CGFloat(s.x0) * size.width, scale)
                        let x1 = snap(CGFloat(s.x1) * size.width, scale)
                        guard x1 > x0 else { continue }
                        ctx.fill(
                            Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)),
                            with: .color(i % 2 == 0 ? Ink.ink700 : Ink.ink500)
                        )
                    }
                    // Segments are parted by ground, not by a fourth colour.
                    for s in segments.dropFirst() {
                        let x = snap(CGFloat(s.x0) * size.width, scale)
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(line, with: .color(Ink.paper), lineWidth: Layout.hairline)
                    }
                }
                .frame(height: ChartGeom.annualHeight)
                // A Canvas carries no accessibility content of its own, so the
                // bar is made one element and given the total it draws.
                .accessibilityElement()
                .accessibilityLabel(S.t(.chartAnnual, ["amount": formatYuan(total)]))

                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(merged, id: \.label) { row in
                        Text(S.t(.chartAnnualRow, ["name": row.label, "amount": formatYuan(row.annual)]))
                            .font(TypeScale.micro.font)
                            .kerning(TypeScale.micro.kerning)
                            .foregroundStyle(Ink.ink500)
                    }
                }
                .padding(.top, Space.s3)
            }
            .chartReveal()
        }
    }

    /// A segment thinner than 3pt is a smudge, not a reading. They are summed
    /// into one 其他 rather than drawn as noise.
    private static func merge(_ rows: [AnnualBarRow]) -> [AnnualBarRow] {
        // Ranked by annual cost descending; ties keep their given order, as the
        // stable sort on the web does.
        let ranked = rows.enumerated()
            .sorted { a, b in
                a.element.annual != b.element.annual
                    ? a.element.annual > b.element.annual
                    : a.offset < b.offset
            }
            .map(\.element)
        let total = ranked.reduce(0) { $0 + max(0, $1.annual) }
        let floor = Double(total) * Double(ChartGeom.annualMinSegment / ChartGeom.plotW)
        let kept = ranked.filter { Double($0.annual) >= floor }
        let rest = ranked.filter { Double($0.annual) < floor }.reduce(0) { $0 + $1.annual }
        return rest > 0 ? kept + [AnnualBarRow(label: S.t(.chartAnnualOther), annual: rest)] : kept
    }
}

// MARK: - 时段散点

@MainActor
struct HourScatterView: View {
    let data: [HourBucket]

    @Environment(\.displayScale) private var displayScale
    /// VoiceOver's stand-in for the web's screen-reader table: adjusting the
    /// chart reads one hour's own numbers without changing what is drawn.
    @State private var reading = 0

    private let dots: [ScatterDot]
    private let total: Int
    private let peak: HourBucket

    init(data: [HourBucket]) {
        self.data = data
        dots = hourScatterLayout(data.map(\.count), ChartGeom.hourMaxRows)
        total = data.reduce(0) { $0 + $1.count }
        peak = data.reduce(HourBucket(hour: 0, count: 0, sum: 0)) { $1.count > $0.count ? $1 : $0 }
    }

    var body: some View {
        if data.isEmpty {
            ChartGate(text: S.t(.chartEmpty), minHeight: ChartGeom.hourHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                plot
                Rectangle().fill(Ink.ruleStrong).frame(height: Layout.hairline)
                foot
            }
            .chartReveal()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(S.t(.chartHour, ["n": total]))
            .accessibilityValue(hourText(reading))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : -1
                reading = min(data.count - 1, max(0, reading + step))
            }
        }
    }

    private var plot: some View {
        Canvas(opaque: false) { ctx, size in
            let scale = displayScale
            let cols = CGFloat(max(1, data.count))
            let pitch = size.width / cols
            // The web plot stretches with preserveAspectRatio="none", so the dot
            // widens with the column and the two clients stay the same picture.
            let dot = ChartGeom.hourDot * (size.width / ChartGeom.plotW)
            for d in dots {
                let r = CGRect(
                    x: snap(CGFloat(d.col) * pitch + (pitch - dot) / 2, scale),
                    y: snap(ChartGeom.hourHeight - CGFloat(d.row + 1) * (ChartGeom.hourDot + ChartGeom.hourGap) + ChartGeom.hourGap, scale),
                    width: max(scale > 0 ? 1 / scale : 1, snap(dot, scale)),
                    height: ChartGeom.hourDot
                )
                ctx.fill(Path(r), with: .color(Ink.ink700))
            }
        }
        .frame(height: ChartGeom.hourHeight)
        .overlay {
            GeometryReader { proxy in
                let pitch = proxy.size.width / CGFloat(max(1, data.count))
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    ForEach(data.filter { $0.count > ChartGeom.hourMaxRows }, id: \.hour) { d in
                        Text(S.t(.chartHourMore, ["n": d.count - ChartGeom.hourMaxRows]))
                            .font(TypeScale.micro.font)
                            .kerning(TypeScale.micro.kerning)
                            .foregroundStyle(Ink.ink500)
                            .fixedSize()
                            .alignmentGuide(.leading) { $0.width / 2 }
                            .offset(
                                x: (CGFloat(index(of: d.hour)) + 0.5) * pitch,
                                y: -CGFloat(ChartGeom.hourMaxRows) * (ChartGeom.hourDot + ChartGeom.hourGap)
                            )
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var foot: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(hh(data[0].hour))
            Text(S.t(.chartHourPeak, ["hour": hh(peak.hour), "n": peak.count]))
                .frame(maxWidth: .infinity)
            Text(hh(data[data.count - 1].hour))
        }
        .font(TypeScale.micro.font)
        .kerning(TypeScale.micro.kerning)
        .foregroundStyle(Ink.ink500)
        .padding(.top, Space.s2)
        .accessibilityHidden(true)
    }

    private func index(of hour: Int) -> Int {
        data.firstIndex { $0.hour == hour } ?? 0
    }

    private func hourText(_ i: Int) -> String {
        guard i >= 0, i < data.count else { return "" }
        let d = data[i]
        return "\(hh(d.hour)):00 · " + S.t(.chartColCount) + " \(d.count) · " + format(d.sum)
    }
}
