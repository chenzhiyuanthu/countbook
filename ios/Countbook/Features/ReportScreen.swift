import SwiftUI

/// 报告 — the retrospective judgement, printed as a statement rather than shown
/// as a dashboard. Nothing here is actionable and nothing here is encouraging:
/// the page exists so the figures can be found by someone who goes looking,
/// which is why 后悔 lives on this screen and on no other. It is a port of
/// `web/src/screens/Report.tsx`; the two clients read the same page.

/// The whole page stays silent until there is a fortnight to read.
private let minRecordedDays = 14
private let minDeviationDays = 14
private let minHourSample = 40
/// Ordering after this hour is the pattern the scatter exists to expose.
private let lateHour = 22

// MARK: - The page, computed once

private struct CategoryRow: Identifiable, Equatable {
    let categoryId: String
    let count: Int
    let median: Fen
    let max: Fen
    let regret: Fen
    let judged: Int

    var id: String { categoryId }
}

/// Everything the page prints, derived in one pass. A report over a few
/// thousand entries walks the log a dozen times; doing that inside a row body —
/// or on every 30-second clock tick — would make scrolling the page cost as
/// much as opening it.
private struct ReportModel: Equatable {
    var currency = "CNY"
    var recordedDays = 0
    var regretMonth: Fen = 0
    var regretYear: Fen = 0
    var judged = 0
    var notWorth = 0
    var wishName: String?
    var wishFraction: Double = 0
    var names: [String: String] = [:]
    var categoryRows: [CategoryRow] = []
    var deviations: [Deviation] = []
    var deviationShort = 0
    var hours: [HourBucket] = []
    var hourTotal = 0
    var lateCount = 0
    var lateSum: Fen = 0
    var yearMonths: [YearLedgerRow] = []

    /// Pure in its arguments: the clock and the fold are read by the caller, so
    /// this can be reasoned about — and, if it ever needs to, moved off the main
    /// actor — without carrying a store with it.
    static func build(
        ledger L: Ledger,
        today: Day,
        nowMs: Int,
        month: Month,
        english: Bool
    ) -> ReportModel {
        var m = ReportModel()
        m.currency = L.settings.currency

        let currentMonth = monthOf(today)
        let year = String(month.prefix(4))
        // A statement is read at its own closing date, not at today's: a month
        // that has ended is reported as it stood on its last day.
        let asOf: Day = month >= currentMonth ? today : dayOfMonth(month, daysInMonth(month))

        let spends = spendsOf(L)
        let monthSpends = inMonth(spends, month)

        var days = L.noSpendDays
        for e in spends { days.insert(e.day) }
        m.recordedDays = days.count

        for (id, c) in L.categories { m.names[id] = english ? c.nameEn : c.name }

        let r = regret(L, asOf)
        m.regretMonth = r.month
        m.regretYear = r.year
        m.judged = r.judged
        m.notWorth = r.notWorth
        if let wish = regretAsWishObject(L, r.year) {
            m.wishName = wish.name
            m.wishFraction = wish.fraction
        }

        m.categoryRows = Self.categories(monthSpends)
        m.deviations = Self.deviations(L, month: month, nowMs: nowMs, ranked: m.categoryRows)

        let elapsed = month == currentMonth ? Int(today.suffix(2)) ?? 0 : daysInMonth(month)
        m.deviationShort = Swift.max(0, minDeviationDays - elapsed)

        m.hours = hourScatter(L, today)
        m.hourTotal = m.hours.reduce(0) { $0 + $1.count }
        for h in m.hours where h.hour >= lateHour {
            m.lateCount += h.count
            m.lateSum += h.sum
        }

        m.yearMonths = Self.yearLedger(L, spends: spends, year: year, currentMonth: currentMonth, nowMs: nowMs)
        return m
    }

    private static func categories(_ monthSpends: [EffectiveEntry]) -> [CategoryRow] {
        var order: [String] = []
        var amounts: [String: [Fen]] = [:]
        var regretBy: [String: Fen] = [:]
        var judgedBy: [String: Int] = [:]
        for e in monthSpends {
            if amounts[e.categoryId] == nil { order.append(e.categoryId) }
            amounts[e.categoryId, default: []].append(e.effective)
            if e.worthIt != nil { judgedBy[e.categoryId, default: 0] += 1 }
            if e.worthIt == false { regretBy[e.categoryId, default: 0] += e.effective }
        }
        return order.map { id in
            let xs = amounts[id] ?? []
            return CategoryRow(
                categoryId: id,
                count: xs.count,
                median: median(xs),
                max: xs.reduce(0) { Swift.max($0, $1) },
                regret: regretBy[id] ?? 0,
                judged: judgedBy[id] ?? 0
            )
        }
        // Amount-weighted, so the category that cost the most regret is read first.
        .sorted { a, b in a.regret != b.regret ? a.regret > b.regret : a.max > b.max }
    }

    private static func deviations(
        _ L: Ledger,
        month: Month,
        nowMs: Int,
        ranked: [CategoryRow]
    ) -> [Deviation] {
        var byId: [String: CategoryRow] = [:]
        for row in ranked { byId[row.categoryId] = row }
        // A category with no standard has nothing to deviate from; it is left to
        // the table rather than drawn against an implied zero.
        let rows = deviationByCategory(L, month, nowMs).filter { $0.standard > 0 }
        return rows.sorted { a, b in
            let ja = byId[a.categoryId]?.judged ?? 0
            let jb = byId[b.categoryId]?.judged ?? 0
            if (ja > 0) != (jb > 0) { return ja > 0 }
            if ja > 0 && jb > 0 {
                let ra = byId[a.categoryId]?.regret ?? 0
                let rb = byId[b.categoryId]?.regret ?? 0
                if ra != rb { return ra > rb }
            }
            return a.delta > b.delta
        }
    }

    private static func yearLedger(
        _ L: Ledger,
        spends: [EffectiveEntry],
        year: String,
        currentMonth: Month,
        nowMs: Int
    ) -> [YearLedgerRow] {
        var spentBy: [Month: Fen] = [:]
        for e in spends where e.day.hasPrefix(year) {
            spentBy[monthOf(e.day), default: 0] += e.effective
        }
        let last = year == String(currentMonth.prefix(4)) ? currentMonth : "\(year)-12"
        let first = spentBy.keys.min() ?? "\(year)-01"
        var rows: [YearLedgerRow] = []
        var m = first
        while m <= last && rows.count < 12 {
            // The standard as it stood when the month closed, not as it stands
            // now: a raised line must not retroactively forgive a month it was
            // not set for.
            let closed = Int(fromDay(dayOfMonth(m, daysInMonth(m))).timeIntervalSince1970 * 1000)
            rows.append(YearLedgerRow(
                month: m,
                spent: spentBy[m] ?? 0,
                standard: standardAt(L, Swift.min(nowMs, closed)).monthlyFen
            ))
            m = addMonths(m, 1)
        }
        return rows
    }
}

/// What must change before the page is worth deriving again: the month being
/// read, the day it is read on, and the size of the log behind it.
private struct ReportKey: Equatable {
    var month: Month
    var today: Day
    var events: Int
    var entries: Int
}

// MARK: - The screen

@MainActor
struct ReportScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicType

    /// Nil is "the month the reader is in", which follows the clock across
    /// midnight; once a month is chosen it stays chosen.
    @State private var picked: Month?
    @State private var model: ReportModel?

    private var month: Month { picked ?? monthOf(store.today) }
    private var currentMonth: Month { monthOf(store.today) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .contentColumn()
            Hairline(.strong)
                .contentColumn()
            ScrollView {
                if let model {
                    page(model)
                        .contentColumn()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ink.paper)
        .onChange(
            of: ReportKey(
                month: month,
                today: store.today,
                events: store.events.count,
                entries: store.ledger.entries.count
            ),
            initial: true
        ) { _, _ in
            rebuild()
        }
    }

    /// Derived outside `body` on purpose: the read of `store.now` here is not a
    /// dependency of the view, so a clock that ticks every thirty seconds does
    /// not walk the whole ledger again.
    private func rebuild() {
        model = ReportModel.build(
            ledger: store.ledger,
            today: store.today,
            nowMs: Int(store.now.timeIntervalSince1970 * 1000),
            month: month,
            english: store.locale == .en
        )
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(S.t(.reportTitle))
                .textStyle(.label)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s3)
            monthStepper
        }
        .frame(minHeight: Theme.barHeight)
    }

    private var monthStepper: some View {
        HStack(spacing: Space.s1) {
            ChevronButton(direction: .left, label: S.t(.reportPrevMonth)) {
                picked = addMonths(month, -1)
            }
            Text(S.t(.reportMonthTitle, ["year": String(month.prefix(4)), "month": String(month.suffix(2))]))
                .textStyle(.body, ink: Ink.ink900)
                // Zero-padded and tabular, so stepping through months does not
                // shift the chevrons under the reader's thumb. A minimum rather
                // than a fixed width, and never wrapped: 2026 年 09 月 is wider
                // than the minimum and was breaking across two lines.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: Space.s10 + Space.s5)
            ChevronButton(
                direction: .right,
                label: S.t(.reportNextMonth),
                disabled: month >= currentMonth
            ) {
                picked = addMonths(month, 1)
            }
        }
        // The chevrons carry their own hit area; pulling the group back keeps
        // the arrow, not its padding, on the gutter.
        .padding(.trailing, -Space.s3)
    }

    // MARK: page

    @ViewBuilder
    private func page(_ m: ReportModel) -> some View {
        if m.recordedDays < minRecordedDays {
            EmptyStateView(title: S.t(.reportEmpty))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                regretHead(m)
                deviationSection(m)
                rateSection(m)
                categorySection(m)
                hourSection(m)
                yearSection(m)
            }
            .padding(.bottom, Space.s8)
        }
    }

    /// P1 and P2. The only place in the product 后悔 is printed, and the only
    /// place `figRegret` is spent: a figure that never earns the live red is
    /// more damning than one that shouts.
    private func regretHead(_ m: ReportModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RegretFigures(month: m.regretMonth, year: m.regretYear, currency: m.currency)
            if let name = m.wishName {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text(S.t(.reportWishFraction, [
                        "name": name,
                        "percent": "\(Int((m.wishFraction * 100).rounded()))%",
                    ]))
                    .textStyle(.body, ink: Ink.figRegret)
                    .fixedSize(horizontal: false, vertical: true)
                    ProgressRule(fraction: m.wishFraction, tone: .regret)
                }
                .padding(.top, Space.s5)
            }
        }
        .padding(.vertical, Space.s6)
    }

    private func deviationSection(_ m: ReportModel) -> some View {
        ReportSection(title: S.t(.reportDeviation)) {
            if m.deviations.isEmpty {
                GateLine(text: S.t(.reportNoStandard))
            } else if m.deviationShort > 0 {
                GateLine(text: S.t(.reportDeviationGate, ["n": m.deviationShort]))
            } else {
                DeviationBarsView(rows: m.deviations, nameOf: { m.names[$0] ?? $0 })
            }
        }
    }

    /// The chart states its own shortfall — 30 verdicts before a rate means
    /// anything — so the gate lives inside the block rather than beside it.
    private func rateSection(_ m: ReportModel) -> some View {
        ReportSection(title: S.t(.reportRate)) {
            RegretBlocksView(judged: m.judged, notWorth: m.notWorth)
        }
    }

    private func categorySection(_ m: ReportModel) -> some View {
        ReportSection(title: S.t(.reportByCategory)) {
            if m.categoryRows.isEmpty {
                GateLine(text: S.t(.reportTableEmpty), ink: Ink.ink500)
            } else if dynamicType.isAccessibilitySize {
                // Five columns cannot hold their alignment at accessibility
                // sizes, so the table becomes one stacked block per category
                // rather than a ruled grid that truncates its figures.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(m.categoryRows) { row in
                        CategoryBlock(row: row, name: m.names[row.categoryId] ?? row.categoryId, currency: m.currency)
                    }
                }
            } else {
                CategoryTable(rows: m.categoryRows, names: m.names, currency: m.currency)
            }
        }
    }

    private func hourSection(_ m: ReportModel) -> some View {
        ReportSection(title: S.t(.reportHours)) {
            if m.hourTotal < minHourSample {
                GateLine(text: S.t(.reportHourGate, ["n": minHourSample - m.hourTotal]))
            } else {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HourScatterView(data: m.hours)
                    Text(S.t(.reportHourLate, [
                        "hh": "\(lateHour)",
                        "n": m.lateCount,
                        "sum": format(m.lateSum, currency: m.currency),
                    ]))
                    .textStyle(.body, ink: Ink.ink500)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func yearSection(_ m: ReportModel) -> some View {
        ReportSection(title: S.t(.reportYear)) {
            Text(String(month.prefix(4)))
                .textStyle(.label, mono: true)
        } content: {
            YearLedgerView(months: m.yearMonths)
        }
    }
}

// MARK: - P1, the regret figures

/// Two figures of equal rank, so they take the same setting and neither is
/// given an emphasis the other lacks. They wrap rather than shrink.
@MainActor
private struct RegretFigures: View {
    let month: Fen
    let year: Fen
    let currency: String

    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.s6) {
                figure(S.t(.reportRegretMonth), month)
                figure(S.t(.reportRegretYear), year)
            }
        } else {
            HStack(alignment: .top, spacing: Space.s7) {
                figure(S.t(.reportRegretMonth), month)
                figure(S.t(.reportRegretYear), year)
                Spacer(minLength: 0)
            }
        }
    }

    private func figure(_ label: String, _ fen: Fen) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).textStyle(.label)
            MoneyView(fen: fen, size: .section, tone: .regret, currency: currency)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - P5, the category table

@MainActor
private struct CategoryTable: View {
    let rows: [CategoryRow]
    let names: [String: String]
    let currency: String

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: Space.s2, verticalSpacing: 0) {
            GridRow {
                Text(S.t(.reportTableCategory))
                    .gridColumnAlignment(.leading)
                Text(S.t(.reportTableCount))
                Text(S.t(.reportTableMedian))
                Text(S.t(.reportTableMax))
                Text(S.t(.reportTableRegret))
            }
            .textStyle(.label)
            .lineLimit(1)
            .padding(.bottom, Space.s3)

            ForEach(rows) { row in
                GridRow { Hairline().gridCellColumns(5) }
                GridRow {
                    Text(names[row.categoryId] ?? row.categoryId)
                        .textStyle(.body, ink: Ink.ink700)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(row.count)")
                        .textStyle(.body, ink: Ink.ink700)
                        .accessibilityLabel(S.t(.reportTableCount) + " \(row.count)")
                    figure(S.t(.reportTableMedian), row.median)
                    figure(S.t(.reportTableMax), row.max)
                    figure(S.t(.reportTableRegret), row.regret)
                }
                .padding(.vertical, Space.s3)
            }
        }
    }

    /// A grid cell cannot be folded into a row-level accessibility element
    /// without breaking the columns, so each figure carries the column it sits
    /// under and is readable on its own.
    private func figure(_ head: String, _ fen: Fen) -> some View {
        MoneyView(fen: fen, size: .body, currency: currency)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(head + " " + format(fen, currency: currency))
    }
}

/// The same five figures at accessibility sizes, printed down the page instead
/// of across it.
@MainActor
private struct CategoryBlock: View {
    let row: CategoryRow
    let name: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Hairline()
                .padding(.bottom, Space.s3)
            Text(name)
                .textStyle(.body, ink: Ink.ink700)
                .fixedSize(horizontal: false, vertical: true)
            line(S.t(.reportTableCount)) {
                Text("\(row.count)").textStyle(.row, ink: Ink.ink900)
            }
            line(S.t(.reportTableMedian)) { MoneyView(fen: row.median, size: .body, currency: currency) }
            line(S.t(.reportTableMax)) { MoneyView(fen: row.max, size: .body, currency: currency) }
            line(S.t(.reportTableRegret)) { MoneyView(fen: row.regret, size: .body, currency: currency) }
        }
        .padding(.bottom, Space.s3)
    }

    private func line<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label).textStyle(.label)
            Spacer(minLength: Space.s3)
            value()
        }
        .frame(minHeight: Layout.hitTarget)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page furniture

/// §3.5 and the web's `.section`: the structural rule opens the section, the
/// label sits 24 below it, the content 12 below the label, and 24 of air closes
/// it. Every block on this page is set in that rhythm — including the ones that
/// have nothing to draw.
@MainActor
private struct ReportSection<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline(.strong)
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(title)
                    .textStyle(.label)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s3)
                trailing
            }
            .padding(.top, Space.s6)
            .padding(.bottom, Space.s3)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Space.s6)
        }
    }
}

private extension ReportSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// A withheld statistic is a sentence where the chart would have begun, not a
/// chart-shaped hole: it takes a row's own vertical rhythm, so a section that
/// cannot draw yet still reads as part of the statement.
@MainActor
private struct GateLine: View {
    let text: String
    var ink: Color = Ink.ink700

    var body: some View {
        Text(text)
            .textStyle(.body, ink: ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Layout.rowPadY)
            .frame(minHeight: Layout.hitTarget, alignment: .leading)
    }
}

/// §8.3 #1 and #2, drawn from the same 24-grid geometry as the web set. The
/// month stepper is the one place this screen has no room for a word.
@MainActor
private struct ChevronButton: View {
    enum Direction { case left, right }

    let direction: Direction
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Chevron(direction: direction)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .butt, lineJoin: .miter))
                .foregroundStyle(disabled ? Ink.ink300 : Ink.ink700)
                .frame(width: Space.s5, height: Space.s5)
                .frame(width: Layout.hitTarget, height: Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

private struct Chevron: Shape {
    let direction: ChevronButton.Direction

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        // The left chevron is the right one mirrored about the 24-grid's centre.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (direction == .left ? 24 - x : x) * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(9, 5))
        path.addLine(to: point(15.5, 12))
        path.addLine(to: point(9, 19))
        return path
    }
}
