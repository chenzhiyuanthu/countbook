import SwiftUI

/// 账页 — the permanent record: searchable, dense, and visibly not tampered
/// with. The screen's whole argument is the audit trail, so an open month edits
/// freely and a sealed one may only be *appended to*: a 更正 line prints under
/// the original with 原 → 新 and its reason, a 冲销 line strikes the amount
/// through, and the original row stays on the page forever. Totals read the
/// effective values; the page reads both.
///
/// Mirrors `web/src/screens/Ledger.tsx` field for field, including the entry
/// detail sheet, which lives here for the same reason it lives there: the two
/// halves share the audit rules and must not drift apart.

// MARK: - The rules the screen is built on

/// A month is sealed the moment the calendar rolls past it. There is no seal
/// event to read: the period *is* the calendar month, so the comparison is the
/// rule (PRODUCT §5.10).
private func isSealed(_ month: Month, _ today: Day) -> Bool { month < monthOf(today) }

/// SCREENS §5.4 L5. Long enough that a scan is not run per keystroke, short
/// enough that the list never feels like it stopped listening.
private let searchDebounce = Duration.milliseconds(120)

/// SCREENS §6.3 D10 — a correction without a stated reason is not a correction.
private let reasonMinimum = 2
private let reasonMaximum = 40

private func pad2(_ n: Int) -> String { n < 10 && n >= 0 ? "0\(n)" : "\(n)" }

/// A wall-clock time of day. The calendar is passed in because building one
/// costs enough to matter when a month of rows is formatted at once.
private func hhmm(_ millis: Int, _ calendar: Calendar) -> String {
    // Milliseconds to seconds is a clock conversion, not a money path.
    let date = Date(timeIntervalSince1970: Double(millis) / 1000)
    let c = calendar.dateComponents([.hour, .minute], from: date)
    return "\(pad2(c.hour ?? 0)):\(pad2(c.minute ?? 0))"
}

/// The plain form a text field holds. Grouping and the small 分 belong to
/// `MoneyView`; a field the user is typing into must round-trip through `parse`.
private func decimalString(_ fen: Fen) -> String {
    let magnitude = fen.magnitude
    let frac = magnitude % 100
    return "\(fen < 0 ? "-" : "")\(magnitude / 100).\(frac < 10 ? "0" : "")\(frac)"
}

/// `>100` `<30` `=68` are read as 元, because that is the unit people type.
private func amountQuery(_ raw: String) -> ((Fen) -> Bool)? {
    let text = raw.trimmingCharacters(in: .whitespaces)
    guard let op = text.first, op == ">" || op == "<" || op == "=" else { return nil }
    let rest = text.dropFirst().trimmingCharacters(in: .whitespaces)
    guard !rest.isEmpty,
          rest.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
          let cut = parse(rest)
    else { return nil }
    switch op {
    case ">": return { $0 > cut }
    case "<": return { $0 < cut }
    default: return { $0 == cut }
    }
}

private enum VerdictFilter: Hashable, Sendable { case unreviewed, notWorth }

private struct LedgerFilters: Equatable {
    var categories: Set<String> = []
    var intents: Set<Intent> = []
    var leak = false
    var corrected = false
    var verdict: VerdictFilter?

    var isActive: Bool {
        !categories.isEmpty || !intents.isEmpty || leak || corrected || verdict != nil
    }
}

// MARK: - Derived state, computed once and not in a row body

/// Everything that depends on the ledger alone. Rebuilt when the ledger
/// changes, never while a list is scrolling: a month can hold thousands of rows
/// and each of them would otherwise re-resolve its category name, its
/// corrections and its spoken label on every frame.
private struct LedgerDigest {
    var rows: [String: EffectiveEntry] = [:]
    var corrections: [String: [Correction]] = [:]
    var names: [String: String] = [:]
    var categories: [Category] = []
    var noSpendDays: Set<Day> = []
    var currency = "CNY"
    var leakCeiling: Fen = 0
    var minMonth: Month = ""
    var maxMonth: Month = ""
}

/// The month header's figures, and the day standard the day rules are measured
/// against. Separate from the sections so a keystroke in the search field does
/// not recompute the standard's revision history.
private struct MonthSummary {
    /// The month's rows, kept so that a keystroke in the search field scans one
    /// month rather than the whole ledger.
    var rows: [EffectiveEntry] = []
    var total: Fen = 0
    var standard: Fen = 0
    var dayStandard: Fen = 0
    var sealed = false
    var categories: [Category] = []
}

/// One row, fully printed. Nothing here is computed later.
private struct LedgerRowModel: Identifiable {
    let id: String
    let time: String
    let category: String
    let payee: String
    let intent: Intent?
    let amount: Fen
    let currency: String
    let struck: Bool
    let subLines: [String]
    let spoken: String
    let sealed: Bool
}

private struct LedgerDaySection: Identifiable {
    let day: Day
    let header: String
    let total: Fen
    let over: Bool
    let currency: String
    let rows: [LedgerRowModel]

    var id: Day { day }
}

/// The audit trail as it is printed: each correction states the amount it
/// replaced, so the chain reads back to the amount first entered.
@MainActor
private func correctionLines(
    _ entry: EffectiveEntry, _ corrections: [Correction], _ currency: String
) -> [String] {
    var previous = entry.amount
    return corrections.map { c in
        let line = S.t(.ledgerCorrection, [
            "from": format(previous, currency: currency),
            "to": format(c.amount, currency: currency),
            "reason": c.reason,
        ])
        previous = c.amount
        return line
    }
}

@MainActor
private func voidLine(_ entry: EffectiveEntry) -> String? {
    guard let voidance = entry.voidance else { return nil }
    return S.t(.ledgerVoided, ["reason": voidance.reason])
}

private func intentKey(_ intent: Intent) -> StringKey {
    switch intent {
    case .need: return .captureIntentNeed
    case .want: return .captureIntentWant
    case .impulse: return .captureIntentImpulse
    }
}

// MARK: - The screen

@MainActor
struct LedgerScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var month: Month = ""
    /// What the field holds, and what the list has been told about — the two are
    /// separate so a scan is not run per keystroke.
    @State private var rawQuery = ""
    @State private var query = ""
    @State private var filters = LedgerFilters()
    @State private var hintShown = true
    @State private var opened: OpenEntry?

    @State private var digest = LedgerDigest()
    @State private var summary = MonthSummary()
    @State private var sections: [LedgerDaySection] = []

    /// `.sheet(item:)` wants an identity rather than a whole entry, so the sheet
    /// always reads the row as the ledger currently holds it.
    private struct OpenEntry: Identifiable { let id: String }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header
                controls
                if sections.isEmpty {
                    emptyState
                } else {
                    ForEach(sections) { section in
                        Section {
                            dayRows(section)
                        } header: {
                            DayRule(section: section)
                        }
                    }
                }
                // Clear of the tab bar and the 记 button on scroll-to-end.
                Color.clear.frame(height: Space.s10)
            }
            .contentColumn()
        }
        .background(Ink.paper)
        .scrollDismissesKeyboard(.interactively)
        // The ledger is read once per change here, and never inside a row.
        .onChange(of: store.ledger) { rebuildDigest(); rebuildMonth() }
        .onChange(of: store.today) { rebuildMonth() }
        .onChange(of: month) { hintShown = true; rebuildMonth() }
        .onChange(of: query) { rebuildSections() }
        .onChange(of: filters) { rebuildSections() }
        .task(id: rawQuery) {
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled else { return }
            query = rawQuery
        }
        .onAppear {
            if month.isEmpty { month = monthOf(store.today) }
            rebuildDigest()
            rebuildMonth()
        }
        .sheet(item: $opened) { open in
            if let entry = digest.rows[open.id] {
                EntryDetailSheet(
                    entry: entry,
                    corrections: digest.corrections[open.id] ?? [],
                    categoryName: digest.names[entry.categoryId] ?? entry.categoryId,
                    categories: digest.categories,
                    sealed: isSealed(monthOf(entry.day), store.today),
                    onClose: { opened = nil }
                )
                .presentationBackground(.clear)
            } else {
                // A sync race removed it while the sheet was opening.
                Color.clear.onAppear { opened = nil }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 0) {
                Text(S.t(.ledgerTitle)).textStyle(.label)
                Spacer(minLength: Space.s3)
                monthStep(-1, glyph: .chevronLeft, label: S.t(.ledgerPrevMonth),
                          enabled: month > digest.minMonth)
                Text(monthTitle)
                    .textStyle(.label, ink: Ink.ink900)
                    .frame(minWidth: Theme.amountGutter)
                    .accessibilityAddTraits(.isHeader)
                monthStep(1, glyph: .chevronRight, label: S.t(.ledgerNextMonth),
                          enabled: month < digest.maxMonth)
            }

            MoneyView(fen: summary.total, size: .section, currency: digest.currency)

            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(S.t(.ledgerStandard, ["amount": format(summary.standard, currency: digest.currency)]))
                    .textStyle(.micro)
                Spacer(minLength: Space.s3)
                sealMark
            }

            if summary.sealed && hintShown {
                Text(S.t(.ledgerSealedNote))
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RuleView(strong: true)
        }
        .padding(.top, Space.s6)
        .padding(.bottom, Space.s4)
    }

    private var monthTitle: String {
        let parts = month.split(separator: "-")
        let year = parts.first.map(String.init) ?? ""
        let number = parts.count > 1 ? String(Int(parts[1]) ?? 0) : ""
        return S.t(.ledgerMonthTitle, ["year": year, "month": number])
    }

    private func monthStep(_ step: Int, glyph: LedgerIcon.Glyph, label: String, enabled: Bool) -> some View {
        Button {
            month = addMonths(month, step)
        } label: {
            LedgerIcon(glyph)
                .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
                .foregroundStyle(enabled ? Ink.ink700 : Ink.ink300)
                .frame(width: Space.s5, height: Space.s5)
                .frame(width: Layout.hitTarget, height: Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// §5.3 — a sealed month wears a letterpressed 结 block; an open one says so
    /// in a word. Tapping the seal shows the sentence that explains it.
    @ViewBuilder
    private var sealMark: some View {
        if summary.sealed {
            Button { hintShown.toggle() } label: {
                Text(S.t(.ledgerSealed))
                    .textStyle(.mono, ink: Ink.ink500)
                    .frame(width: Space.s5, height: Space.s5)
                    .background(Ink.surfaceSunken)
                    .overlay(alignment: .top) { Ink.ruleStrong.frame(height: Layout.hairline) }
                    .overlay(alignment: .leading) { Ink.ruleStrong.frame(width: Layout.hairline) }
                    .frame(width: Layout.hitTarget, height: Layout.hitTarget, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(S.t(.ledgerSealedNote))
        } else {
            Text(S.t(.ledgerOpen)).textStyle(.label)
        }
    }

    // MARK: Search and filters

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            searchField
            if rawQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(S.t(.ledgerSearchSyntax)).textStyle(.micro)
            }
            filterWords
            RuleView(strong: true)
        }
        .padding(.bottom, Space.s2)
    }

    private var searchField: some View {
        HStack(spacing: Space.s3) {
            LedgerIcon(.magnifyingglass)
                .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
                .foregroundStyle(Ink.ink500)
                .frame(width: Space.s5, height: Space.s5)
                .accessibilityHidden(true)

            TextField("", text: $rawQuery)
                .textStyle(.body, ink: Ink.ink900)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel(S.t(.ledgerSearch))
                // R8: a placeholder is small text and takes ink500, never ink300.
                .overlay(alignment: .leading) {
                    if rawQuery.isEmpty {
                        Text(S.t(.ledgerSearch))
                            .textStyle(.body, ink: Ink.ink500)
                            .allowsHitTesting(false)
                    }
                }

            if !rawQuery.isEmpty {
                Button {
                    rawQuery = ""
                    query = ""
                } label: {
                    LedgerIcon(.xmark)
                        .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
                        .foregroundStyle(Ink.ink700)
                        .frame(width: Space.s5, height: Space.s5)
                        .frame(width: Layout.hitTarget, height: Layout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(S.t(.ledgerSearchClear))
            }
        }
        .frame(minHeight: Layout.hitTarget)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// §5.7 — words with a rule under the active ones. No pills: there are no
    /// pills anywhere in this product.
    private var filterWords: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s4) {
                FilterWord(title: S.t(.ledgerFilterAll), active: !filters.isActive && query.isEmpty) {
                    filters = LedgerFilters()
                    rawQuery = ""
                    query = ""
                }
                ForEach(summary.categories) { category in
                    FilterWord(title: digest.names[category.id] ?? category.id,
                               active: filters.categories.contains(category.id)) {
                        toggle(&filters.categories, category.id)
                    }
                }
                ForEach(Intent.allCases, id: \.self) { intent in
                    FilterWord(title: S.t(intentKey(intent)),
                               active: filters.intents.contains(intent)) {
                        toggle(&filters.intents, intent)
                    }
                }
                FilterWord(title: S.t(.ledgerFilterLeak), active: filters.leak) {
                    filters.leak.toggle()
                }
                FilterWord(title: S.t(.ledgerFilterCorrected), active: filters.corrected) {
                    filters.corrected.toggle()
                }
                FilterWord(title: S.t(.ledgerFilterUnreviewed),
                           active: filters.verdict == .unreviewed) {
                    setVerdict(.unreviewed)
                }
                FilterWord(title: S.t(.ledgerFilterNotWorth),
                           active: filters.verdict == .notWorth) {
                    setVerdict(.notWorth)
                }
            }
            .padding(.trailing, Layout.gutter)
        }
        // The row overflows sideways rather than folding into a "more" menu.
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(S.t(.ledgerFilters))
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.remove(value) == nil { set.insert(value) }
    }

    /// The two verdict words are one control: holding both at once would ask the
    /// ledger for entries that are unjudged and judged, which is always nothing.
    private func setVerdict(_ verdict: VerdictFilter) {
        filters.verdict = filters.verdict == verdict ? nil : verdict
    }

    // MARK: The list

    @ViewBuilder
    private func dayRows(_ section: LedgerDaySection) -> some View {
        if section.rows.isEmpty {
            // A claimed no-spend day is a record too, and says so.
            Text(S.t(.todayNospendDone))
                .textStyle(.body, ink: Ink.ink500)
                .padding(.vertical, Layout.rowPadY)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(section.rows) { row in
                EntryRow(model: row, reduceMotion: reduceMotion) {
                    opened = OpenEntry(id: row.id)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if month < digest.minMonth {
            EmptyStateView(title: S.t(.ledgerEmptyBefore, ["date": digest.minMonth]))
        } else if filters.isActive || !query.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyStateView(title: S.t(.ledgerEmptySearch)) {
                QuietButton(S.t(.ledgerEmptySearchClear)) {
                    filters = LedgerFilters()
                    rawQuery = ""
                    query = ""
                }
            }
        } else {
            EmptyStateView(title: S.t(.ledgerEmpty), body: S.t(.ledgerEmptyHint))
        }
    }

    // MARK: Derivation

    private func rebuildDigest() {
        let ledger = store.ledger
        var next = LedgerDigest()
        next.rows = effective(ledger)
        next.noSpendDays = ledger.noSpendDays
        next.currency = ledger.settings.currency
        next.leakCeiling = ledger.settings.leakCeilingFen

        // The fold keeps corrections in event order, so a target's chain reads
        // oldest first and the last one is the amount in force.
        var chains: [String: [Correction]] = [:]
        for correction in ledger.corrections {
            chains[correction.targetId, default: []].append(correction)
        }
        next.corrections = chains

        let english = S.locale == .en
        var names: [String: String] = [:]
        names.reserveCapacity(ledger.categories.count)
        for category in ledger.categories.values {
            names[category.id] = english ? category.nameEn : category.name
        }
        next.names = names
        next.categories = ledger.categories.values.sorted { $0.order < $1.order }

        var minMonth = monthOf(store.today)
        var maxMonth = minMonth
        for entry in ledger.entries.values {
            let m = monthOf(entry.day)
            if m < minMonth { minMonth = m }
            if m > maxMonth { maxMonth = m }
        }
        next.minMonth = minMonth
        next.maxMonth = maxMonth

        digest = next
    }

    private func rebuildMonth() {
        if month.isEmpty { month = monthOf(store.today) }
        let ledger = store.ledger
        let rows = digest.rows.values.filter { monthOf($0.day) == month }

        var next = MonthSummary()
        next.rows = rows
        next.total = rows.reduce(0) { $0 + ($1.kind == .spend ? $1.effective : 0) }
        next.sealed = isSealed(month, store.today)

        // A closed month is measured against the line that was standing when it
        // closed, not against a line revised since.
        let lastDay = dayOfMonth(month, daysInMonth(month))
        let monthEnd = Int(fromDay(lastDay).timeIntervalSince1970 * 1000) + 86_400_000 - 1
        let now = Int(store.now.timeIntervalSince1970 * 1000)
        next.standard = standardAt(ledger, min(now, monthEnd)).monthlyFen
        next.dayStandard = next.standard / daysInMonth(month)

        var present = Set<String>()
        for row in rows { present.insert(row.categoryId) }
        next.categories = digest.categories.filter { present.contains($0.id) }

        summary = next
        rebuildSections(next)
    }

    /// The month is passed in rather than read back off `summary`, so that a
    /// rebuild triggered by the month itself cannot group last month's rows
    /// against this month's standard.
    private func rebuildSections(_ snapshot: MonthSummary? = nil) {
        let summary = snapshot ?? self.summary
        let needle = query.trimmingCharacters(in: .whitespaces)
        let byAmount = amountQuery(needle)
        let text = byAmount == nil ? needle.lowercased() : ""
        let ceiling = digest.leakCeiling
        let currency = digest.currency

        let visible = summary.rows.filter { entry in
            if !filters.categories.isEmpty && !filters.categories.contains(entry.categoryId) { return false }
            if !filters.intents.isEmpty {
                guard let intent = entry.intent, filters.intents.contains(intent) else { return false }
            }
            if filters.leak && !(entry.effective > 0 && entry.effective < ceiling) { return false }
            if filters.corrected && entry.correction == nil && entry.voidance == nil { return false }
            if filters.verdict == .unreviewed && entry.worthIt != nil { return false }
            if filters.verdict == .notWorth && entry.worthIt != false { return false }
            if let byAmount { return byAmount(entry.effective) }
            if text.isEmpty { return true }
            let hay = "\(entry.note) \(entry.merchant) \(digest.names[entry.categoryId] ?? "") "
                + format(entry.effective, currency: currency)
            return hay.lowercased().contains(text)
        }

        var byDay: [Day: [EffectiveEntry]] = [:]
        for entry in visible { byDay[entry.day, default: []].append(entry) }
        if !filters.isActive && needle.isEmpty {
            for day in digest.noSpendDays where monthOf(day) == month && byDay[day] == nil {
                byDay[day] = []
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let sealed = summary.sealed
        let dayStandard = summary.dayStandard

        sections = byDay.keys.sorted(by: >).map { day in
            let entries = (byDay[day] ?? []).sorted { a, b in
                a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id > b.id
            }
            let total = entries.reduce(0) { $0 + ($1.kind == .spend ? $1.effective : 0) }
            return LedgerDaySection(
                day: day,
                header: S.t(.ledgerDayHeader, [
                    "date": String(day.dropFirst(5)),
                    "weekday": S.weekday(weekdayOf(day)),
                ]),
                total: total,
                over: dayStandard > 0 && total > dayStandard,
                currency: currency,
                rows: entries.map { row($0, calendar: calendar, sealed: sealed, currency: currency) }
            )
        }
    }

    private func row(
        _ entry: EffectiveEntry, calendar: Calendar, sealed: Bool, currency: String
    ) -> LedgerRowModel {
        let name = digest.names[entry.categoryId] ?? entry.categoryId
        let payee = entry.note.isEmpty ? entry.merchant : entry.note
        let voided = entry.voidance != nil
        let lines = correctionLines(entry, digest.corrections[entry.id] ?? [], currency)
        let reversal = voidLine(entry)
        let shown = voided ? entry.amount : entry.effective
        let time = hhmm(entry.createdAt, calendar)

        // One accessibility element per record: the corrections belong to the
        // row that they correct, not to a second thing to arrow past.
        let spoken = [
            time,
            name,
            payee,
            entry.intent.map { S.t(intentKey($0)) } ?? "",
            format(shown, currency: currency),
            lines.last ?? "",
            reversal ?? "",
        ].filter { !$0.isEmpty }.joined(separator: " ")

        return LedgerRowModel(
            id: entry.id,
            time: time,
            category: name,
            payee: payee,
            intent: entry.intent,
            amount: shown,
            currency: currency,
            struck: voided,
            subLines: lines + (reversal.map { [$0] } ?? []),
            spoken: spoken,
            sealed: sealed
        )
    }
}

// MARK: - Row

private struct EntryRow: View {
    let model: LedgerRowModel
    let reduceMotion: Bool
    let onOpen: () -> Void

    var body: some View {
        LedgerRow(
            time: model.time,
            category: model.category,
            payee: model.payee,
            intent: model.intent,
            struck: model.struck,
            subLines: model.subLines,
            spoken: model.spoken,
            onTap: onOpen
        ) {
            MoneyView(fen: model.amount, currency: model.currency)
        }
        // rowPrint: a correction printed under the row it corrects arrives with
        // the hairline, not on top of it.
        .animation(reduceMotion ? nil : Motion.ease(Motion.rowPrint), value: model.subLines.count)
        // §9.6 — the row's two actions are reachable without a swipe.
        .accessibilityAction(named: S.t(model.sealed ? .ledgerCorrect : .ledgerEdit), onOpen)
    }
}

/// §5.3, the day rule: the date and weekday on the left, the day's total in the
/// amount gutter, a structural hairline beneath, and — when the day ran past its
/// share of the standard — a 45° hatch mark, which is not red and does not need
/// to be (§4.7).
private struct DayRule: View {
    let section: LedgerDaySection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(section.header).textStyle(.mono)
            Spacer(minLength: Space.s3)
            if section.over { OverMark() }
            MoneyView(fen: section.total, currency: section.currency)
                .frame(minWidth: Theme.amountGutter, alignment: .trailing)
        }
        .padding(.vertical, Space.s2)
        .frame(minHeight: Space.s6 + Space.s1, alignment: .bottom)
        .background(Ink.paper)
        .overlay(alignment: .bottom) { Hairline(.strong) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The over-channel that survives greyscale, print and a red-blind reader.
private struct OverMark: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.clip(to: Path(rect))
            context.stroke(hatch(in: rect), with: .color(Ink.ink700), lineWidth: Layout.hairline)
        }
        .frame(width: Space.s2, height: Space.s2)
        .accessibilityLabel(S.t(.ledgerDayOver))
    }

    /// Lines run at 45° (x − y = c); a family of them whose intercepts differ by
    /// Δc stands Δc/√2 apart, so Δc is the period times √2.
    private func hatch(in rect: CGRect) -> Path {
        var path = Path()
        let step = ChartGeom.hatchPeriod * CGFloat(2.0.squareRoot())
        var c = rect.minX - rect.maxY
        while c <= rect.maxX - rect.minY {
            path.move(to: CGPoint(x: c + rect.minY, y: rect.minY))
            path.addLine(to: CGPoint(x: c + rect.maxY, y: rect.maxY))
            c += step
        }
        return path
    }
}

/// §5.7 — a filter is a word with a rule under it when it is on. Not a chip, not
/// a pill, not a fill.
private struct FilterWord: View {
    let title: String
    let active: Bool
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(.body, ink: active ? Ink.ink900 : Ink.ink500)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, Space.s2)
                .overlay(alignment: .bottom) {
                    if active {
                        Rectangle()
                            .fill(Ink.ink500)
                            .frame(height: Layout.hairline / max(displayScale, 1))
                    }
                }
                .frame(minHeight: Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Entry detail

/// SCREENS §6. An open month edits and deletes; a sealed month may only append.
/// The two are the same sheet because they are the same record — what changes is
/// what the ledger will accept, and the sheet says so rather than hiding it.
@MainActor
private struct EntryDetailSheet: View {
    let entry: EffectiveEntry
    let corrections: [Correction]
    let categoryName: String
    let categories: [Category]
    let sealed: Bool
    let onClose: () -> Void
    /// Formatted once: a calendar is expensive enough that building one inside a
    /// body is a habit worth not starting.
    private let stamped: String

    @Environment(Store.self) private var store

    @State private var amount: String
    @State private var note: String
    @State private var day: Day
    @State private var intent: Intent?
    @State private var categoryId: String

    @State private var correctTo: String
    @State private var reason = ""
    @State private var voiding = false
    @State private var voidReason = ""

    init(
        entry: EffectiveEntry,
        corrections: [Correction],
        categoryName: String,
        categories: [Category],
        sealed: Bool,
        onClose: @escaping () -> Void
    ) {
        self.entry = entry
        self.corrections = corrections
        self.categoryName = categoryName
        self.categories = categories.filter { $0.kind == entry.kind && $0.archived != true }
        self.sealed = sealed
        self.onClose = onClose
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        stamped = "\(entry.day) \(hhmm(entry.createdAt, calendar))"
        _amount = State(initialValue: decimalString(entry.amount))
        _note = State(initialValue: entry.note)
        _day = State(initialValue: entry.day)
        _intent = State(initialValue: entry.intent)
        _categoryId = State(initialValue: entry.categoryId)
        _correctTo = State(initialValue: decimalString(entry.effective))
    }

    private var currency: String { entry.currency }
    private var parsedAmount: Fen? { parse(amount) }
    private var parsedCorrection: Fen? { parse(correctTo) }
    /// A typed date is only a date once it round-trips: `2026-02-31` is not one.
    private var parsedDay: Day? { toDay(fromDay(day)) == day ? day : nil }
    private var dayIntoSealed: Bool {
        guard let parsedDay else { return false }
        return isSealed(monthOf(parsedDay), store.today)
    }
    private var reasonReady: Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= reasonMinimum
    }
    private var voidReasonReady: Bool {
        voidReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= reasonMinimum
    }
    private var saveReady: Bool {
        guard let parsedAmount, parsedAmount > 0, parsedDay != nil, !dayIntoSealed else { return false }
        return true
    }

    var body: some View {
        SheetContainer(title: S.t(.entryTitle), onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    figure
                    RuleView(strong: true)
                    if sealed { correctionForm } else { editForm }
                    promise
                    verdict
                    history
                }
                .padding(.bottom, Space.s6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Head

    private var figure: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            MoneyView(
                fen: sealed ? entry.effective : (parsedAmount ?? entry.amount),
                size: .screen,
                currency: currency
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(entry.note.isEmpty ? categoryName : "\(categoryName) · \(entry.note)")
                .textStyle(.body, ink: Ink.ink700)
                .fixedSize(horizontal: false, vertical: true)

            Text(stamped).textStyle(.mono)

            if sealed {
                Text(S.t(.ledgerSealedNote))
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Open month — edit and delete

    private var editForm: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            LabelledField(
                label: S.t(.entryAmountLabel), text: $amount,
                mono: true, keyboard: .decimalPad
            )

            VStack(alignment: .leading, spacing: Space.s2) {
                Text(S.t(.captureCategory)).textStyle(.label)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s4) {
                        ForEach(categories) { category in
                            FilterWord(
                                title: S.locale == .en ? category.nameEn : category.name,
                                active: category.id == categoryId
                            ) { categoryId = category.id }
                        }
                    }
                }
                .scrollClipDisabled()
            }

            LabelledField(label: S.t(.captureNote), text: $note)
            LabelledField(label: S.t(.captureDate), text: $day, mono: true,
                          keyboard: .numbersAndPunctuation)

            if dayIntoSealed {
                Text(S.t(.entryClosedDate))
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if entry.kind == .spend {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(S.t(.entryStamp)).textStyle(.label)
                    SegmentedStamp(
                        options: Intent.allCases.map {
                            SegmentedStamp.Option(value: $0, label: S.t(intentKey($0)))
                        },
                        selection: intent,
                        accessibilityLabel: S.t(.entryStamp)
                    ) { intent = $0 }
                }
            }

            PrimaryButton(S.t(.entrySave), disabled: !saveReady, action: save)
            QuietButton(S.t(.entryDelete), fullWidth: true, action: remove)
        }
    }

    private func save() {
        guard let parsedAmount, let parsedDay, saveReady else { return }
        store.commit(.entryPatch(
            target: entry.id,
            patch: EntryPatch(
                amount: parsedAmount,
                categoryId: categoryId,
                intent: intent,
                note: note,
                day: parsedDay
            )
        ))
        onClose()
    }

    private func remove() {
        let eventID = store.commit(.entryRemove(target: entry.id))
        onClose()
        // Undo drops the event outright: it was committed seconds ago on this
        // device, so no other device can have seen it.
        store.toast(S.t(.ledgerDeleted), action: ToastAction(label: S.t(.ledgerUndo)) {
            store.undo(eventID: eventID)
        })
    }

    // MARK: Sealed month — append only

    private var correctionForm: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            LabelledField(
                label: S.t(.entryCorrectAmount), text: $correctTo,
                mono: true, keyboard: .decimalPad
            )
            LabelledField(
                label: S.t(.entryReasonLabel), text: $reason,
                placeholder: S.t(.ledgerReasonRequired),
                suffix: "\(reason.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(reasonMaximum)",
                maxLength: reasonMaximum
            )
            // A reason shorter than two characters keeps the button disabled and
            // says so with the counter. No red, no error line (SCREENS §6.4).
            PrimaryButton(
                S.t(.entryCorrectSubmit),
                disabled: parsedCorrection == nil || !reasonReady,
                action: correct
            )

            if voiding {
                LabelledField(
                    label: S.t(.entryVoidReason), text: $voidReason,
                    placeholder: S.t(.ledgerReasonRequired),
                    suffix: "\(voidReason.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(reasonMaximum)",
                    maxLength: reasonMaximum
                )
                DangerButton(S.t(.ledgerVoid), disabled: !voidReasonReady, action: reverse)
            } else {
                QuietButton(S.t(.entryVoid), fullWidth: true) { voiding = true }
            }
        }
    }

    private func correct() {
        guard let parsedCorrection, reasonReady else { return }
        store.commit(.entryCorrect(
            target: entry.id,
            amount: parsedCorrection,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        onClose()
    }

    private func reverse() {
        guard voidReasonReady else { return }
        store.commit(.entryVoid(
            target: entry.id,
            reason: voidReason.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        onClose()
    }

    // MARK: The record

    /// Written down is written down: the promise is evidence and is never
    /// editable. With none, the block does not render at all.
    @ViewBuilder
    private var promise: some View {
        if let promise = entry.promise, !promise.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                RuleView()
                Text(S.t(.entryPromiseTitle)).textStyle(.label)
                Text("「\(promise)」")
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Space.s3)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Ink.rule).frame(width: Layout.hairline * 2)
                    }
            }
        }
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            RuleView()
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(S.t(.entryVerdict)).textStyle(.label)
                Spacer(minLength: Space.s3)
                Text(verdictWord.text).textStyle(.body, ink: verdictWord.ink)
            }
            .frame(minHeight: Layout.hitTarget)
            .accessibilityElement(children: .combine)
        }
    }

    private var verdictWord: (text: String, ink: Color) {
        guard let worthIt = entry.worthIt else { return (S.t(.entryPending), Ink.ink500) }
        return worthIt ? (S.t(.entryWorth), Ink.ink700) : (S.t(.entryNotWorth), Ink.figRegret)
    }

    /// Permanently expanded, never collapsible, never removable: the history is
    /// the reason the ledger is worth anything.
    @ViewBuilder
    private var history: some View {
        let lines = correctionLines(entry, corrections, currency) + (voidLine(entry).map { [$0] } ?? [])
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                RuleView()
                Text(S.t(.entryHistory)).textStyle(.label)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .textStyle(.mono)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Icons

/// §8.2 and §8.3. The stroke is the one number in the icon spec that is not a
/// spacing step, and the geometry is the same 24-grid `d` data the web set draws
/// from — SF Symbols are forbidden because they have no CSS equivalent (§8.1).
private let iconStroke: CGFloat = 1.5

private struct LedgerIcon: Shape {
    enum Glyph { case chevronLeft, chevronRight, magnifyingglass, xmark }

    let glyph: Glyph

    init(_ glyph: Glyph) { self.glyph = glyph }

    func path(in rect: CGRect) -> Path {
        let unit = Swift.min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        switch glyph {
        case .chevronRight:
            path.move(to: point(9, 5))
            path.addLine(to: point(15.5, 12))
            path.addLine(to: point(9, 19))
        case .chevronLeft:
            path.move(to: point(15, 5))
            path.addLine(to: point(8.5, 12))
            path.addLine(to: point(15, 19))
        case .magnifyingglass:
            path.addEllipse(in: CGRect(
                x: point(4, 4).x, y: point(4, 4).y,
                width: 13 * unit, height: 13 * unit
            ))
            path.move(to: point(15.2, 15.2))
            path.addLine(to: point(20, 20))
        case .xmark:
            path.move(to: point(6, 6))
            path.addLine(to: point(18, 18))
            path.move(to: point(18, 6))
            path.addLine(to: point(6, 18))
        }
        return path
    }
}
