import SwiftUI

/*
 * 今日 — one question, answered above the fold: how much is left today, and am
 * I already past it. Everything under the hero exists to show where that figure
 * came from, because a record that cannot prove its own arithmetic is only an
 * opinion.
 *
 * A counterpart of `web/src/screens/Today.tsx`, in the same order and with the
 * same words: the two clients are one product, and a person moving between them
 * should not have to relearn anything.
 */

/// 今天没花钱 is offered late in the day only: claimed at noon it is a guess,
/// claimed at eight it is a statement (SCREENS.md §3.4 T11).
private let noSpendHour = 20

/// Below three logged days the strip would draw a shape out of two dots, which
/// is a claim the data has not earned yet.
private let stripMinDays = 3

/// §8.2 — the icon stroke. The one number in the icon spec that is not a
/// spacing step, so it is written as a multiple of the rule weight instead.
private let iconStroke = Layout.hairline * 1.5

@MainActor
struct TodayScreen: View {
    @Environment(Store.self) private var store

    @State private var derivation = false
    @State private var scrubbed: Day?
    @State private var capturing = false
    @State private var reckoning = false
    @State private var memo = TodayMemo()

    var body: some View {
        // The fold is read once per change of ledger, day or minute — never on a
        // scrub, which arrives sixty times a second over a list that can hold
        // thousands of rows.
        let model = memo.model(for: TodayInputs(store: store)) { $0.build(store.ledger) }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(model)
                RuleView(broken: model.over)
                if model.hasStandard {
                    provenance(model)
                    if derivation { derivationList(model) }
                    if model.over, model.figure.recoveryDays > 0 {
                        Text(S.t(.todayRecovery, ["days": model.figure.recoveryDays]))
                            .textStyle(.body, ink: Ink.ink500)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Space.s3)
                    }
                } else {
                    firstRun
                }
                stripSection(model)
                if model.drip.count > 0 {
                    RuleView()
                    leakLine(model)
                }
                if model.offerNoSpend {
                    RuleView()
                    noSpendAction
                }
                if model.marked {
                    RuleView()
                    Text(S.t(.todayNospendDone))
                        .textStyle(.body, ink: Ink.ink500)
                        .frame(maxWidth: .infinity, minHeight: Layout.hitTarget, alignment: .leading)
                        .padding(.vertical, Space.s3)
                }
                if model.offerReckoning {
                    RuleView()
                    reckoningEntry(model)
                }
                if model.streak > 0 {
                    RuleView()
                    Text(S.t(.todayStreak, ["n": model.streak]))
                        .textStyle(.label)
                        .frame(maxWidth: .infinity, minHeight: Layout.hitTarget, alignment: .leading)
                        .padding(.vertical, Space.s3)
                }
                listSection(model)
            }
            .contentColumn()
            .padding(.top, Space.s7)
            .padding(.bottom, Space.s6)
        }
        .background(Ink.paper)
        .sheet(isPresented: $capturing) {
            CaptureScreen(onClose: { capturing = false })
        }
        .fullScreenCover(isPresented: $reckoning) {
            ReckoningScreen(onClose: { reckoning = false })
        }
    }

    // MARK: 主数字

    /// T1–T3. The hero is not a button and a tap does nothing: it is a statement,
    /// and the rule beneath it is the product's one composition event — when the
    /// allowance is negative the rule runs past both edges of the measure, as a
    /// layout state on first paint, never animated.
    private func hero(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(S.t(.todayAvailable)).textStyle(.label)
            if model.hasStandard {
                MoneyView(fen: model.figure.perDay, size: .hero, tone: model.over ? .over : nil)
            } else {
                // Nothing is known yet, so nothing is asserted.
                Text(verbatim: "——").textStyle(.hero, ink: Ink.ink300)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(S.t(.todayAvailable))
        .accessibilityValue(model.hasStandard
                            ? format(model.figure.perDay, currency: model.currency)
                            : S.t(.todayNoStandard))
    }

    // MARK: 推导行

    /// T4. The ledger has to be able to show its own working, so the one-line
    /// provenance opens into the four figures it was made of.
    private func provenance(_ model: TodayModel) -> some View {
        Button {
            withAnimation(Motion.ease(Motion.rowFade)) { derivation.toggle() }
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                Text(S.t(.todayProvenance, [
                    "standard": format(model.figure.standard, currency: model.currency),
                    "spent": format(model.figure.spent, currency: model.currency),
                    "fixed": format(model.figure.fixedRemaining, currency: model.currency),
                    "days": model.figure.daysLeft,
                ]))
                .textStyle(.label)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                ChevronMark(direction: derivation ? .up : .down)
            }
            .padding(.vertical, Space.s3)
            .frame(minHeight: Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(LinePressStyle())
        .accessibilityAddTraits(derivation ? [.isButton, .isSelected] : .isButton)
    }

    private func derivationList(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detail(S.t(.todayDetailStandard)) {
                MoneyView(fen: model.figure.standard, currency: model.currency)
            }
            detail(S.t(.todayDetailSpent)) {
                MoneyView(fen: model.figure.spent, currency: model.currency)
            }
            detail(S.t(.todayDetailFixed)) {
                MoneyView(fen: model.figure.fixedRemaining, currency: model.currency)
            }
            detail(S.t(.todayDetailDays)) {
                Text(S.t(.todayDaysValue, ["n": model.figure.daysLeft]))
                    .textStyle(.row)
            }
        }
        .padding(.bottom, Space.s3)
        .transition(.opacity)
    }

    private func detail<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label).textStyle(.label)
            Spacer(minLength: Space.s3)
            value().frame(minWidth: Theme.amountGutter, alignment: .trailing)
        }
        .padding(.vertical, Space.s2)
        .accessibilityElement(children: .combine)
    }

    /// §3.5, first run. With no standard set a zero would be a number the ledger
    /// has not earned, so the page asks for the line instead of drawing one.
    private var firstRun: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(S.t(.todayNoStandard))
                .textStyle(.body, ink: Ink.ink700)
                .fixedSize(horizontal: false, vertical: true)
            Text(S.t(.todayNoStandardHint))
                .textStyle(.body, ink: Ink.ink500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s3)
        .accessibilityElement(children: .combine)
    }

    // MARK: 月度日柱

    /// T6–T7. The readout follows the cursor while a finger is down and states
    /// the daily standard when it is not.
    private func stripSection(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(S.t(.todayStripTitle, ["month": model.monthName])).textStyle(.label)
                Spacer(minLength: Space.s3)
                Text(readout(model)).textStyle(.label).multilineTextAlignment(.trailing)
            }
            .padding(.bottom, Space.s3)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if model.stripReady {
                MonthStripView(data: model.strip) { scrubbed = $0 }
                    // §4.6 — at most one breakout per screen, and the hero
                    // outranks the strip, so the baseline stays in the measure
                    // on a day the allowance is already negative.
                    .clipShape(MeasureClip(active: model.over))
            } else {
                // The withheld chart keeps the height it would have taken, so the
                // page does not jump on the day the third one arrives.
                Text(S.t(.todayStripGate, ["n": stripMinDays - model.loggedDays]))
                    .textStyle(.body, ink: Ink.ink500)
                    .frame(maxWidth: .infinity, minHeight: ChartGeom.stripHeight, alignment: .leading)
            }
        }
        .padding(.vertical, Space.s6)
    }

    private func readout(_ model: TodayModel) -> String {
        if let scrubbed, let bar = model.strip.bars.first(where: { $0.day == scrubbed }) {
            return S.t(.chartStripDay, [
                "date": String(bar.day.dropFirst(5)),
                "amount": formatYuan(bar.spent, currency: model.currency),
            ])
        }
        guard model.strip.dailyStandard > 0 else { return "" }
        return S.t(.chartStandardPerDay, [
            "amount": formatYuan(model.strip.dailyStandard, currency: model.currency),
        ])
    }

    // MARK: 条目行与其余各行

    /// T8. The same invisible money counted two ways — as a count of small
    /// charges and as a number of large purchases — because one conversion is
    /// easy to shrug off and two are not.
    private func leakLine(_ model: TodayModel) -> some View {
        Text(model.drip.equivalent > 0
             ? S.t(.todayLeak, [
                "count": model.drip.count,
                "sum": format(model.drip.sum, currency: model.currency),
                "times": String(format: "%.1f", model.drip.equivalent),
             ])
             : S.t(.todayLeakBare, [
                "count": model.drip.count,
                "sum": format(model.drip.sum, currency: model.currency),
             ]))
            .textStyle(.body, ink: Ink.ink700)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.s4)
    }

    /// T11. Without this line "not logging" would be the winning strategy: a
    /// silent day has to be claimed before it counts as a clean one.
    private var noSpendAction: some View {
        Button {
            store.commit(.dayNospend(day: store.today, on: true))
        } label: {
            Text(S.t(.todayNospend))
                .textStyle(.body, ink: Ink.ink700)
                .frame(maxWidth: .infinity, minHeight: Layout.hitTarget, alignment: .leading)
                .padding(.vertical, Space.s3)
                .contentShape(Rectangle())
        }
        .buttonStyle(LinePressStyle())
    }

    /// T12. Present only after the reckoning hour and only while something is
    /// unjudged; when the deck is done the line simply goes, with no "完成".
    private func reckoningEntry(_ model: TodayModel) -> some View {
        Button { reckoning = true } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                Text(S.t(.todayVerdict, ["n": model.queue]))
                    .textStyle(.body, ink: Ink.ink700)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ChevronMark(direction: .right)
            }
            .padding(.vertical, Space.s3)
            .frame(minHeight: Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(LinePressStyle())
    }

    // MARK: 今天

    private func listSection(_ model: TodayModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(S.t(.commonToday)) {
                MoneyView(fen: model.dayTotal, currency: model.currency)
            }
            if model.rows.isEmpty {
                EmptyStateView(title: model.monthEmpty
                               ? S.t(.todayEmptyMonth)
                               : S.t(.todayEmptyToday)) {
                    if model.monthEmpty {
                        Button { capturing = true } label: {
                            Text(S.t(.captureTitle))
                                .textStyle(.body, ink: Ink.ink900)
                                .underline()
                                .frame(minHeight: Layout.hitTarget, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(LinePressStyle())
                    }
                }
            } else {
                ForEach(model.rows) { row in
                    LedgerRow(
                        time: row.time,
                        category: row.category,
                        payee: row.payee,
                        intent: row.intent,
                        spoken: row.spoken
                    ) {
                        MoneyView(fen: row.amount, currency: model.currency)
                    }
                }
            }
        }
        .padding(.vertical, Space.s6)
    }
}

// MARK: - The fold, read once

/// Everything the screen prints, derived in one pass. Rows arrive as finished
/// strings so that no row body formats a date or reads a dictionary while it
/// scrolls.
@MainActor
private struct TodayModel {
    var figure = Available(perDay: 0, standard: 0, spent: 0, fixedRemaining: 0,
                           remaining: 0, daysLeft: 1, recoveryDays: 0)
    var strip = MonthStrip(bars: [], dailyStandard: 0, max: 0)
    var drip = Leak(count: 0, sum: 0, divisor: 0, equivalent: 0, byMerchant: [])
    var streak = 0
    var queue = 0
    var rows: [TodayRow] = []
    var dayTotal: Fen = 0
    var monthEmpty = true
    var loggedDays = 0
    var monthName = ""
    var currency = "CNY"
    var marked = false
    var offerNoSpend = false
    var offerReckoning = false

    var hasStandard: Bool { figure.standard > 0 }
    /// 破版 and the one red figure on the screen: the allowance itself is past
    /// zero. A negative *amount* is not this state and never takes the colour.
    var over: Bool { hasStandard && figure.perDay < 0 }
    var stripReady: Bool { loggedDays >= stripMinDays }
}

private struct TodayRow: Identifiable {
    let id: String
    let time: String
    let category: String
    let payee: String
    let intent: Intent?
    let amount: Fen
    let spoken: String
}

/// The three things the derived figures actually depend on. An event count is
/// the cheap, honest signal for "the ledger changed": every commit, absorb and
/// undo moves it, and comparing two `Int`s costs nothing on a drag.
private struct TodayInputs: Equatable {
    let events: Int
    let today: Day
    /// Whole minutes. The hour gates 今天没花钱 and the reckoning entry; nothing
    /// on this screen is a second finer than that.
    let minute: Int
    let locale: Settings.Locale

    @MainActor init(store: Store) {
        events = store.events.count
        today = store.today
        minute = Int(store.now.timeIntervalSince1970) / 60
        locale = store.locale
    }

    var nowMs: Int { minute * 60_000 }

    @MainActor func build(_ ledger: Ledger) -> TodayModel {
        var model = TodayModel()
        model.currency = ledger.settings.currency
        model.figure = available(ledger, today, nowMs)
        model.strip = monthStrip(ledger, monthOf(today), today, nowMs)
        model.drip = leak(ledger, today)
        model.streak = streak(ledger, today, nowMs)
        model.queue = reckoningQueue(ledger, today).count
        model.marked = ledger.noSpendDays.contains(today)
        model.monthEmpty = model.strip.bars.allSatisfy { $0.spent == 0 }
        model.loggedDays = model.strip.bars.reduce(0) { $0 + (!$1.future && $1.logged ? 1 : 0) }
        model.monthName = TodayInputs.monthName(today, locale)

        let english = locale == .en
        var total: Fen = 0
        var rows: [TodayRow] = []
        for e in effective(ledger).values.sorted(by: { $0.createdAt < $1.createdAt })
        where e.day == today && e.kind == .spend {
            total += e.effective
            let category = english
                ? (ledger.categories[e.categoryId]?.nameEn ?? "")
                : (ledger.categories[e.categoryId]?.name ?? "")
            let payee = e.note.isEmpty ? e.merchant : e.note
            let time = TodayInputs.clock(e.createdAt)
            let stamp = e.intent.map { S.t($0.stampKey) } ?? ""
            rows.append(TodayRow(
                id: e.id,
                time: time,
                category: category,
                payee: payee,
                intent: e.intent,
                amount: e.effective,
                // One element per record: a row is a sentence, not five stops.
                spoken: [time, category, payee, stamp,
                         format(e.effective, currency: ledger.settings.currency)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            ))
        }
        model.rows = rows
        model.dayTotal = total

        let calendar = Calendar.current
        let at = Date(timeIntervalSince1970: Double(nowMs) / 1000)
        let hour = calendar.component(.hour, from: at)
        let weekday = calendar.component(.weekday, from: at) - 1
        model.offerNoSpend = rows.isEmpty && !model.marked && hour >= noSpendHour
        model.offerReckoning = weekday == ledger.settings.reckoningWeekday
            && hour >= ledger.settings.reckoningHour
            && model.queue > 0
        return model
    }

    private static func clock(_ ms: Int) -> String {
        let at = Date(timeIntervalSince1970: Double(ms) / 1000)
        let c = Calendar.current.dateComponents([.hour, .minute], from: at)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `MMMM` against the locale's own month symbols, which gives 三月 and March
    /// where a localised template would give 3月.
    private static func monthName(_ day: Day, _ locale: Settings.Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale.rawValue)
        formatter.dateFormat = "MMMM"
        return formatter.string(from: fromDay(day))
    }
}

/// `useMemo`, which SwiftUI does not have. Held in `@State` as a reference so
/// that filling it is not a change to any observed value: a scrub, or opening
/// the derivation, re-runs the body but never the fold.
@MainActor
private final class TodayMemo {
    private var key: TodayInputs?
    private var value = TodayModel()

    func model(for key: TodayInputs, _ build: (TodayInputs) -> TodayModel) -> TodayModel {
        if self.key != key {
            self.key = key
            value = build(key)
        }
        return value
    }
}

// MARK: - Parts this screen owns

/// A tappable line: no ground, no border, and a press is a change of ground
/// only — no scale, no ripple, no haptic.
private struct LinePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Ink.surfaceSunken : Color.clear)
            .animation(.linear(duration: Motion.rowFade), value: configuration.isPressed)
    }
}

/// §8.3 icons 1, 3 and 4, drawn from the same 24-grid geometry as the web set.
/// SF Symbols are forbidden precisely because they have no CSS twin, so the
/// chevron is authored here until `Design/Icons.swift` exists to hold it.
private struct ChevronShape: Shape {
    enum Direction { case right, up, down }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        switch direction {
        case .right:
            path.move(to: point(9, 5))
            path.addLine(to: point(15.5, 12))
            path.addLine(to: point(9, 19))
        case .up:
            path.move(to: point(5, 15))
            path.addLine(to: point(12, 8.5))
            path.addLine(to: point(19, 15))
        case .down:
            path.move(to: point(5, 9))
            path.addLine(to: point(12, 15.5))
            path.addLine(to: point(19, 9))
        }
        return path
    }
}

/// The disclosure mark carries no meaning of its own, so it carries no name
/// either: the row it sits in is the accessible element.
private struct ChevronMark: View {
    let direction: ChevronShape.Direction

    var body: some View {
        ChevronShape(direction: direction)
            .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
            .foregroundStyle(Ink.ink300)
            .frame(width: Space.s5, height: Space.s5)
            .accessibilityHidden(true)
    }
}

/// Clips the measure horizontally and leaves the vertical alone, so a chart can
/// be stopped from breaking the column without its labels being cropped.
private struct MeasureClip: Shape {
    let active: Bool

    func path(in rect: CGRect) -> Path {
        Path(active ? rect.insetBy(dx: 0, dy: -Space.s10) : rect.insetBy(dx: -Space.s10, dy: -Space.s10))
    }
}
