import Security
import SwiftUI
import UIKit

/// 记一笔 — the path the whole product stands on. Six seconds, six taps, and
/// exactly one moment of self-classification.
///
/// The rule that outranks every other decision in this file: on the shortest
/// supported iPhone the amount, the category grid, the 必要/想要/冲动 stamp and
/// the keypad are all on screen at once, and nothing scrolls. So everything
/// optional — the note, the payee, the date shortcuts — is folded behind a
/// control that costs no vertical space until it is asked for, and the two
/// blocks that can give height back (the grid and the keypad) are measured
/// against the room that is actually there rather than assumed. The web client
/// gave the note and payee full-height rows and pushed the keypad off a
/// 402 × 874 screen; that is the mistake this layout exists to not repeat.

// MARK: - Constants this screen owns

/// Neither of these is a depiction, which is why the token file does not emit
/// them: the long press is the threshold at which a press stops being a tap
/// (PRODUCT.md §4.8), and the caret's period is a legibility figure from
/// DESIGN.md §5.5 (1.06s, `steps(2)` — so half of it per state).
private let longPressSeconds: Double = 0.4
private let caretHalfPeriod: Double = 0.53

/// §4.3 — six 元 digits is the ceiling, and it is reached silently.
private let maxIntDigits = 6

/// §5.8 — the keypad digit sets at 0.61× the amount figure (44 → 27). It is a
/// ratio between two type roles rather than a size, so it lives beside them.
private let keyDigitRatio: CGFloat = 0.61

/// The keypad has four rows and the category grid wants three, so when the two
/// compete for the same leftover height they split it four to seven.
private let keypadShare: CGFloat = 4.0 / 7.0

/// Milliseconds in a day. Arithmetic, not a design value.
private let msPerDay = 86_400_000

// MARK: - The screen

@MainActor
struct CaptureScreen: View {
    let onClose: () -> Void

    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.displayScale) private var displayScale

    // 整数部分 / 小数部分 / 是否已进入小数态 — PRODUCT.md §4.3.
    @State private var intPart = "0"
    @State private var fracPart = ""
    @State private var inFrac = false

    @State private var categoryID: String?
    @State private var intent: Intent?
    @State private var note = ""
    @State private var merchant = ""
    @State private var day: Day = ""

    @State private var datesOpen = false
    @State private var fieldsOpen = false
    @State private var keepOpen = false
    /// 仍要立即记入 — the escape from the cooling path, taken once per entry.
    @State private var overrideHold = false

    /// A long press fires while the finger is still down and the tap fires when
    /// it lifts; without this both would run and the entry would be saved twice.
    @State private var longPressed = false

    /// Derived from the whole ledger, so they are computed on a change rather
    /// than in the body: a ledger of a few thousand entries must not be walked
    /// on every keystroke's re-render.
    @State private var perDay: Fen = 0
    @State private var warning: String?
    @State private var categories: [Category] = []

    /// The sheet is anchored to the bottom, so this rectangle's bottom edge and
    /// width are stable no matter how tall the content turns out — which is what
    /// makes it safe to size the grid and the keypad from it.
    @State private var box: CGRect = .zero

    @FocusState private var noteFocused: Bool

    var body: some View {
        SheetContainer(accessibilityLabel: S.t(.captureTitle), onClose: onClose) {
            content
                .background {
                    // The sheet is anchored to the bottom, so this rectangle's
                    // bottom edge and width do not move when the content above
                    // grows — which is what makes it safe to size the grid and
                    // the keypad from it without the layout chasing itself.
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { box = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, next in
                                box = next
                            }
                    }
                }
        }
        // SheetContainer draws the scrim, the one shadow and the sheet radius
        // itself; the system sheet must not paint a second ground behind it.
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .onAppear(perform: prime)
        .onChange(of: store.events.count) { _, _ in recompute() }
    }

    // MARK: - Composition

    private var content: some View {
        let m = metrics
        return VStack(alignment: .leading, spacing: 0) {
            head
                .frame(height: Layout.hitTarget)

            if fieldsOpen {
                optionalFields
            }

            amountRow

            consequenceRow

            RuleView().padding(.vertical, Space.s1)

            categoryGrid(m)

            RuleView().padding(.vertical, Space.s1)

            stampRow

            RuleView().padding(.vertical, Space.s1)

            if !fieldsOpen {
                keypad(m)
            }

            commit
        }
    }

    // MARK: - Head: the date, the optional fields, 继续记

    @ViewBuilder
    private var head: some View {
        if datesOpen {
            dateShortcuts
        } else {
            HStack(spacing: Space.s3) {
                Button { datesOpen = true } label: {
                    Text("\(day) · \(S.weekday(weekdayOf(day)))")
                        .textStyle(.mono, mono: true)
                        .frame(minHeight: Layout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(S.t(.captureDate)) \(day)")

                Spacer(minLength: 0)

                disclosure

                Button { keepOpen.toggle() } label: {
                    Text(S.t(.captureKeepOpen))
                        .textStyle(.label, ink: keepOpen ? Ink.ink900 : Ink.ink500)
                        .overlay(alignment: .bottom) {
                            if keepOpen {
                                Ink.ink500.frame(height: Layout.hairline / max(displayScale, 1))
                                    .offset(y: Space.s1 / 2)
                            }
                        }
                        .frame(minHeight: Layout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(keepOpen ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// Closed the row still has to report what is behind it, or a note typed and
    /// then folded away would look lost.
    private var disclosure: some View {
        let filled = [note, merchant]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        // On the cooling path the note is a promise to your future self, so the
        // closed row says so rather than opening itself and taking the keypad's
        // place, which is what the web client does.
        let closedLabel = suspendable ? S.t(.capturePromise) : S.t(.captureOptional)
        return Button {
            fieldsOpen.toggle()
            noteFocused = fieldsOpen
        } label: {
            HStack(spacing: Space.s1) {
                Text(filled.isEmpty ? closedLabel : filled)
                    .textStyle(.body, ink: filled.isEmpty ? Ink.ink500 : Ink.ink700)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Chevron(up: fieldsOpen)
                    .stroke(style: StrokeStyle(lineWidth: Layout.hairline * 1.5,
                                               lineCap: .butt, lineJoin: .miter))
                    .foregroundStyle(Ink.ink500)
                    .frame(width: Space.s4, height: Space.s4)
            }
            .frame(minHeight: Layout.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(closedLabel)
        .accessibilityValue(filled)
        .accessibilityAddTraits(fieldsOpen ? [.isButton, .isSelected] : .isButton)
    }

    /// 今天 · 昨天 · 前天 · 选择日期 — the four of them take the head's own row, so
    /// opening the date costs nothing below it. Every one of them closes the row
    /// again, which is also the way back out.
    private var dateShortcuts: some View {
        HStack(spacing: 0) {
            shortcut(S.t(.commonToday), store.today)
            shortcut(S.t(.commonYesterday), addDays(store.today, -1))
            shortcut(S.t(.captureDayBefore), addDays(store.today, -2))
            picker
        }
        .frame(maxWidth: .infinity)
    }

    private func shortcut(_ label: String, _ target: Day) -> some View {
        Button {
            day = target
            datesOpen = false
        } label: {
            Text(label)
                .textStyle(.body, ink: day == target ? Ink.ink900 : Ink.ink700)
                .overlay(alignment: .bottom) {
                    if day == target {
                        Ink.ink500.frame(height: Layout.hairline / max(displayScale, 1))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(day == target ? [.isButton, .isSelected] : .isButton)
    }

    /// The system control is the picker, never the printed date: its locale
    /// format (08/09/2026) contradicts the ISO mono the rest of the app reads in.
    /// So the word is ours and the near-invisible native control sits on top of
    /// it — invisible rather than hidden, because a hidden view takes no taps.
    private var picker: some View {
        let bound = Binding<Date>(
            get: { fromDay(day) },
            set: { day = toDay($0); datesOpen = false }
        )
        return Text(S.t(.capturePickDate))
            .textStyle(.body, ink: Ink.ink700)
            .frame(maxWidth: .infinity, minHeight: Layout.hitTarget)
            .accessibilityHidden(true)
            .overlay {
                DatePicker("", selection: bound,
                           in: ...fromDay(store.today),
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .opacity(0.02)
                    .accessibilityLabel(S.t(.capturePickDate))
            }
    }

    // MARK: - Optional fields

    /// They sit at the top of the sheet, not above the commit bar, because the
    /// system keyboard they raise covers the bottom of it. While they are open
    /// the keypad stands down — you are typing prose, not digits — so the sheet
    /// gets shorter rather than taller and nothing below is pushed anywhere.
    private var optionalFields: some View {
        VStack(spacing: Space.s4) {
            LabelledField(
                label: S.t(.captureNote),
                text: $note,
                placeholder: suspendable ? S.t(.capturePromise) : S.t(.captureNote),
                maxLength: 40
            )
            .focused($noteFocused)

            LabelledField(
                label: S.t(.captureMerchant),
                text: $merchant,
                placeholder: S.t(.captureMerchant),
                maxLength: 40
            )
        }
        .padding(.vertical, Space.s2)
    }

    // MARK: - Amount and its consequence

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
            Spacer(minLength: 0)
            MoneyView(fen: amountFen, size: .screen, currency: currency)
            caret
        }
        .padding(.bottom, Space.s2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(S.t(.captureAmount))
    }

    @ViewBuilder
    private var caret: some View {
        let mark = Rectangle()
            .fill(Ink.ink500)
            .frame(width: Layout.hairline, height: Space.s6)
            .accessibilityHidden(true)
        // Reduced motion: solid, no blink. The caret is a position, and a
        // position does not need to move to be read.
        if reduceMotion {
            mark
        } else {
            TimelineView(.periodic(from: .now, by: caretHalfPeriod)) { tick in
                mark.opacity(
                    Int(tick.date.timeIntervalSinceReferenceDate / caretHalfPeriod) % 2 == 0 ? 1 : 0
                )
            }
        }
    }

    /// The one line that moves the consequence to before the press instead of
    /// after it, and it costs nothing.
    private var consequenceRow: some View {
        let after = perDay - amountFen
        return HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(S.t(.captureConsequence)).textStyle(.label)
            MoneyView(fen: after, size: .body, tone: after < 0 ? .over : nil, currency: currency)
            Spacer(minLength: 0)
        }
        .padding(.bottom, Space.s2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Categories

    /// Text labels only — no icon, no colour, no emoji (DESIGN.md R6). The shape
    /// of the grid is decided by the room left over: fewer rows and more columns
    /// on a short phone, the design's 4 × 4 on a tall one, and all of it visible
    /// either way rather than a scroll in the middle of a six-second flow.
    private func categoryGrid(_ m: Metrics) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: m.columns)
        return ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(categories) { category in
                    cell(category, height: m.categoryRow)
                }
            }
        }
        .frame(height: m.gridHeight)
        .scrollDisabled(m.categoryRows * m.categoryRow <= m.gridHeight)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(S.t(.captureCategory))
    }

    private func cell(_ category: Category, height: CGFloat) -> some View {
        let chosen = category.id == categoryID
        return Button {
            // A second tap on the same cell does not clear it: a mis-tap must
            // not be able to leave the entry with no category at all.
            categoryID = category.id
            recomputeWarning()
        } label: {
            Text(S.locale == .en ? category.nameEn : category.name)
                .textStyle(.body, ink: chosen ? Ink.ink900 : Ink.ink700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Space.s1)
                .frame(maxWidth: .infinity, minHeight: Layout.hitTarget)
                .frame(height: height)
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                            .strokeBorder(Ink.ink900,
                                          lineWidth: Layout.hairline / max(displayScale, 1))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - The stamp

    private var stampRow: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            SegmentedStamp(
                options: [
                    .init(value: Intent.need, label: S.t(.captureIntentNeed)),
                    .init(value: Intent.want, label: S.t(.captureIntentWant)),
                    .init(value: Intent.impulse, label: S.t(.captureIntentImpulse)),
                ],
                selection: intent,
                accessibilityLabel: S.t(.captureIntent)
            ) { choice in
                // A second tap on 想要 escalates to 冲动. You cannot pay ¥68 for
                // the week's fourth coffee and call it 必要 without noticing that
                // you are lying — that is the whole mechanism.
                intent = (intent == .want && choice == .want) ? .impulse : choice
            }

            if showsTier {
                Text(S.t(.captureCoolingTier, ["days": cooling]))
                    .textStyle(.micro)
            }
        }
    }

    // MARK: - The keypad

    /// Never the system keyboard: it covers half the sheet, it has no ⌫ of the
    /// right shape, and it cannot be laid out against the room that is left.
    private func keypad(_ m: Metrics) -> some View {
        let hair = Layout.hairline / max(displayScale, 1)
        return VStack(spacing: hair) {
            ForEach(keypadRows, id: \.first) { row in
                HStack(spacing: hair) {
                    ForEach(row, id: \.self) { key in
                        keyView(key, height: m.keyHeight, figure: m.keyFigure)
                    }
                }
            }
        }
        .background(Ink.rule)
        // §5.8 — the keypad is full bleed to the sheet's edges; the sheet's own
        // clip shape is what ends it.
        .padding(.horizontal, -Layout.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(S.t(.captureKeypad))
    }

    private var keypadRows: [[Key]] {
        [[.digit("1"), .digit("2"), .digit("3")],
         [.digit("4"), .digit("5"), .digit("6")],
         [.digit("7"), .digit("8"), .digit("9")],
         [.dot, .digit("0"), .back]]
    }

    @ViewBuilder
    private func keyView(_ key: Key, height: CGFloat, figure: CGFloat) -> some View {
        switch key {
        case .digit(let d):
            keyButton(height: height, label: S.t(.captureAmount) + " " + d) {
                press { pressDigit(d) }
            } content: {
                Text(d)
                    .font(.system(size: figure, weight: .regular).monospacedDigit())
                    .foregroundStyle(Ink.ink900)
            }
        case .dot:
            keyButton(height: height, label: S.t(.captureDecimal), disabled: inFrac) {
                press { inFrac = true }
            } content: {
                Text(verbatim: ".")
                    .font(.system(size: figure, weight: .regular).monospacedDigit())
                    .foregroundStyle(inFrac ? Ink.ink300 : Ink.ink900)
            }
        case .back:
            keyButton(height: height, label: S.t(.captureBackspace)) {
                // The long press has already cleared the amount; the lift that
                // follows it is not a second, separate deletion.
                if longPressed { longPressed = false; return }
                press { pressBack() }
            } content: {
                BackspaceIcon()
                    .stroke(style: StrokeStyle(lineWidth: Layout.hairline * 1.5,
                                               lineCap: .butt, lineJoin: .miter))
                    .foregroundStyle(Ink.ink900)
                    .frame(width: Space.s5, height: Space.s5)
            }
            // §5.8 — 400ms clears the whole amount, once, with no repeat.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: longPressSeconds).onEnded { _ in
                    longPressed = true
                    press { clearAmount() }
                }
            )
        }
    }

    private func keyButton<Content: View>(
        height: CGFloat,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyStyle())
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: - The commit bar

    @ViewBuilder
    private var commit: some View {
        VStack(spacing: 0) {
            if suspendable {
                heldBar
                overrideLink
            } else {
                primaryBar
            }
        }
        .padding(.top, Space.s3)
    }

    /// §5.6, the held bar: the cooling path is the default, not an option nobody
    /// takes, so the primary action itself becomes it. Tapping writes a 待购
    /// item — not an entry.
    private var heldBar: some View {
        Button(action: suspend) {
            Text(S.t(.captureHoldPrimary, [
                "days": cooling,
                "date": String(addDays(store.today, cooling).dropFirst(5)),
            ]))
            .font(.system(size: TextRole.body.size(at: dynamicType), weight: .semibold))
            .foregroundStyle(Ink.figHeld)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Space.s4)
        }
        .buttonStyle(HeldBarStyle())
        .accessibilityLabel(S.t(.captureSuspendHint, ["days": cooling]))
    }

    /// The escape hatch must exist and must be second class.
    private var overrideLink: some View {
        Button { overrideHold = true } label: {
            Text(warning.map { S.t(.captureOverrideWarned, ["warning": $0]) }
                 ?? S.t(.captureHoldOverride))
                .textStyle(.body, ink: Ink.ink700)
                .underline(true, color: Ink.ink500)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var primaryBar: some View {
        PrimaryButton(
            warning.map { S.t(.captureSaveWarned, ["warning": $0]) } ?? S.t(.captureSave),
            holdMs: needsHold ? Rules.holdToSaveMs : nil,
            disabled: missing,
            accessibilityLabel: needsHold ? S.t(.captureHoldHint) : nil
        ) {
            if longPressed { longPressed = false; return }
            save(keep: keepOpen)
        }
        .accessibilityHint(hint)
        // AC-1.6 — a long press saves and keeps the sheet open. It is offered
        // only when the 3-second ring is not: above the cooling floor the press
        // and hold already means something else, and one gesture may not mean
        // two things.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: longPressSeconds).onEnded { _ in
                guard !needsHold, !missing else { return }
                longPressed = true
                save(keep: true)
            },
            including: needsHold ? .subviews : .all
        )
    }

    // MARK: - Derived values

    private var currency: String { store.ledger.settings.currency }

    /// §4.3 — 整数分 end to end. `intPart` is capped at six digits, so the
    /// product cannot overflow.
    private var amountFen: Fen {
        let whole = Int(intPart) ?? 0
        let frac = Int((fracPart + "00").prefix(2)) ?? 0
        return whole * 100 + frac
    }

    private var overFloor: Bool { amountFen >= store.ledger.settings.coolingFloorFen }
    private var cooling: Int { overFloor ? coolingDays(amountFen) : 0 }
    private var suspendable: Bool {
        overFloor && (intent == .want || intent == .impulse) && !overrideHold
    }
    private var showsTier: Bool { cooling > 0 && intent != nil && intent != .need }
    /// SCREENS.md C9b — the hold is asked for by the amount, or by an allowance
    /// that is already spent, whichever is true first.
    private var needsHold: Bool { overFloor || perDay < 0 }
    private var missing: Bool { amountFen == 0 || categoryID == nil || intent == nil }

    private var hint: String {
        if amountFen == 0 { return S.t(.captureNeedAmount) }
        if categoryID == nil { return S.t(.captureNeedCategory) }
        if intent == nil { return S.t(.captureIntentRequired) }
        return ""
    }

    // MARK: - Layout arithmetic

    /// What the room actually is, and what the two elastic blocks get out of it.
    private struct Metrics {
        var gridHeight: CGFloat
        var categoryRow: CGFloat
        var categoryRows: CGFloat
        var columns: Int
        var keyHeight: CGFloat
        var keyFigure: CGFloat
    }

    private var metrics: Metrics {
        let hair = Layout.hairline / max(displayScale, 1)
        let width = box.width > 0 ? box.width : SheetWidth.fallback
        // The sheet is bottom-anchored, so its bottom edge does not move when
        // the content above it grows; the ceiling is the room the status bar and
        // the presenting sheet's own inset leave at the top.
        let ceiling = Space.s10 + Space.s5
        let bottom = box.maxY > 0 ? box.maxY : SheetWidth.fallbackHeight
        let available = max(bottom - ceiling, Layout.hitTarget)

        let screenFig = TextRole.screen.size(at: dynamicType)
        let labelFig = TextRole.label.size(at: dynamicType)
        let microFig = TextRole.micro.size(at: dynamicType)
        let bodyFig = TextRole.body.size(at: dynamicType)

        var chrome = Layout.hitTarget                       // the head row
        chrome += screenFig * 1.25 + Space.s2               // the amount
        chrome += labelFig * 1.5 + Space.s2                 // the consequence
        chrome += 3 * (Space.s1 * 2 + hair)                 // three rules
        chrome += Layout.hitTarget                          // the stamp
        if showsTier { chrome += microFig * 1.4 + Space.s1 }
        chrome += Space.s3 + Theme.barHeight                // the commit bar
        if suspendable { chrome += Layout.hitTarget }       // 仍要立即记入
        if fieldsOpen {
            chrome += 2 * (labelFig * 1.5 + Space.s2 + Layout.hitTarget)
                + Space.s4 + Space.s2 * 2
        }

        let free = max(available - chrome, Layout.hitTarget)

        // The keypad key is 56 at default type (§5.8) and grows with the digit
        // it carries, but it never takes the grid below one visible row.
        let keyFigure = screenFig * keyDigitRatio
        let idealKey = max(Space.s9 + Space.s2, keyFigure * 1.5)
        let keypadHeight = fieldsOpen
            ? 0
            : min(4 * idealKey + 3 * hair,
                  max(4 * Layout.hitTarget + 3 * hair, free * keypadShare))
        let keyHeight = fieldsOpen ? 0 : (keypadHeight - 3 * hair) / 4

        let gridHeight = max(free - keypadHeight, Layout.hitTarget)
        // Three rows is the design's shape and four is its ceiling; below that
        // the grid widens instead of scrolling, because a scroll in the middle
        // of a six-second flow costs more than a narrow cell.
        let rowsThatFit = min(4, max(1, Int(gridHeight / Layout.hitTarget)))
        let widestGrid = max(3, Int(width / Layout.hitTarget))
        let count = max(categories.count, 1)
        let columns = min(widestGrid, max(3, (count + rowsThatFit - 1) / rowsThatFit))
        let rows = CGFloat((count + columns - 1) / columns)
        let rowHeight = min(max(Layout.hitTarget, gridHeight / rows), Space.s9 + Space.s2)

        return Metrics(
            gridHeight: gridHeight,
            categoryRow: rowHeight,
            categoryRows: rows,
            columns: columns,
            keyHeight: keyHeight,
            keyFigure: max(keyFigure, bodyFig)
        )
    }

    // MARK: - Keying the amount

    private func press(_ change: () -> Void) {
        // The one haptic in the product (§5.8).
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        change()
    }

    private func pressDigit(_ d: String) {
        if inFrac {
            guard fracPart.count < 2 else { return }
            fracPart += d
        } else if intPart == "0" {
            intPart = d
        } else {
            guard intPart.count < maxIntDigits else { return }
            intPart += d
        }
        recomputeWarning()
    }

    private func pressBack() {
        if inFrac {
            if !fracPart.isEmpty { fracPart.removeLast() } else { inFrac = false }
        } else {
            intPart = intPart.count > 1 ? String(intPart.dropLast()) : "0"
        }
        recomputeWarning()
    }

    private func clearAmount() {
        intPart = "0"
        fracPart = ""
        inFrac = false
        recomputeWarning()
    }

    // MARK: - Committing

    private func save(keep: Bool) {
        guard !missing, let categoryID, let intent else { return }
        let entry = Entry(
            id: captureID(),
            kind: .spend,
            amount: amountFen,
            currency: currency,
            categoryId: categoryID,
            intent: intent,
            note: note.trimmingCharacters(in: .whitespaces),
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            day: day,
            createdAt: nowMs
        )
        let eventID = store.commit(.entryAdd(entry: entry))
        store.toast(S.t(.captureSaved),
                    ToastAction(label: S.t(.ledgerUndo)) { store.undo(eventID: eventID) })
        guard keep else {
            onClose()
            return
        }
        // The stamp and the category survive: the next entry is usually the same
        // kind of purchase, and re-choosing them is the tax that ends a streak.
        clearAmount()
        note = ""
        merchant = ""
        overrideHold = false
        recompute()
    }

    private func suspend() {
        guard let categoryID, cooling > 0 else { return }
        let named = categories.first { $0.id == categoryID }
        let fallback = named.map { S.locale == .en ? $0.nameEn : $0.name } ?? S.t(.captureTitle)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespaces)
        let name = !trimmedNote.isEmpty ? trimmedNote
            : (!trimmedMerchant.isEmpty ? trimmedMerchant : fallback)
        let at = nowMs
        let eventID = store.commit(.wishAdd(wish: Wish(
            id: captureID(),
            name: name,
            price: amountFen,
            createdAt: at,
            unlockAt: at + cooling * msPerDay
        )))
        store.toast(S.t(.captureSuspended),
                    ToastAction(label: S.t(.ledgerUndo)) { store.undo(eventID: eventID) })
        onClose()
    }

    // MARK: - Ledger-wide values, computed off the render path

    private var nowMs: Int { Int(store.now.timeIntervalSince1970 * 1000) }

    private func prime() {
        if day.isEmpty { day = store.today }
        categories = store.ledger.categories.values
            .filter { $0.kind == .spend && $0.archived != true }
            .sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
        recompute()
    }

    private func recompute() {
        perDay = available(store.ledger, store.today, nowMs).perDay
        recomputeWarning()
    }

    /// §4.8's third bar: the product's best figure, placed in the second that
    /// matters. It walks the ledger, so it runs on a choice, never in a body.
    private func recomputeWarning() {
        guard let categoryID else { warning = nil; return }
        warning = commitWarning(store.ledger, store.today, categoryID, amountFen)
    }
}

// MARK: - Parts

private enum Key: Hashable {
    case digit(String)
    case dot
    case back
}

/// The sheet has not been measured on the first paint; these are only what the
/// first frame is drawn against, and they are replaced a frame later.
private enum SheetWidth {
    static let fallback: CGFloat = Layout.contentMax / 3 * 2 - Layout.gutter * 2
    static let fallbackHeight: CGFloat = Layout.contentMax
}

/// §5.8 — a key answers a press with a change of ground and nothing else: no
/// scale, no ripple, no lift. The keypad's own `Ink.rule` ground shows through
/// the gaps between the keys and is what draws the hairline grid.
private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Ink.surface : Ink.surfaceSunken)
            .animation(.linear(duration: Motion.rowFade), value: configuration.isPressed)
    }
}

/// §5.6, the held bar: `--surface` under a 1pt `--fig-held` border and a label
/// of the same brass, pressing to the sunken ground. It is the only bar in the
/// product that is neither filled ink nor bare.
private struct HeldBarStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: Theme.barHeight)
            .background(configuration.isPressed ? Ink.surfaceSunken : Ink.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Ink.figHeld, lineWidth: Layout.hairline)
            }
            .animation(.linear(duration: Motion.rowFade), value: configuration.isPressed)
    }
}

/// §8.2 — icons are drawn on a 24 grid with a 20 live area, stroke 1.5, butt
/// caps, mitre joins. SF Symbols are forbidden because they have no CSS twin,
/// so the two clients would drift apart the moment one of them changed.
private struct Chevron: Shape {
    var up: Bool

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var p = Path()
        p.move(to: at(5, up ? 15 : 9))
        p.addLine(to: at(12, up ? 8 : 16))
        p.addLine(to: at(19, up ? 15 : 9))
        return p
    }
}

/// `delete.backward`: the tag, and the ✕ inside it.
private struct BackspaceIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var p = Path()
        p.move(to: at(9, 4))
        p.addLine(to: at(22, 4))
        p.addLine(to: at(22, 20))
        p.addLine(to: at(9, 20))
        p.addLine(to: at(2, 12))
        p.closeSubpath()
        p.move(to: at(12, 9))
        p.addLine(to: at(18, 15))
        p.move(to: at(18, 9))
        p.addLine(to: at(12, 15))
        return p
    }
}

/// 128 bits of CSPRNG output in lowercase hex, matching the ids the web client
/// mints. The store keeps its own for events; an entry and a wish are minted
/// here because they are part of the payload, not of the envelope.
private func captureID() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
}
