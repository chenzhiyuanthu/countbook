import SwiftUI

// MARK: - Metrics the token file does not emit

/// §8.2 — icons are drawn on a 24 grid with a 20 live area. The stroke is the
/// one number in the icon spec that is not a spacing step.
private let iconStroke: CGFloat = 1.5

/// §6.3 gives `verdictSwipe` a travel of ±120. It is a property of the motion
/// rather than of the layout, so it is composed from spacing steps here rather
/// than typed as a size.
private let swipeTravel: CGFloat = Space.s9 * 2 + Space.s6

/// §11.5 — the deck is dragged 1:1 and decided past 88 of travel, the same
/// threshold the capture sheet uses to know a dismiss from a wobble.
private let swipeThreshold: CGFloat = Space.s10 + Space.s6

/// 周日审判. Last week's 想要 and 冲动 come back one at a time, largest first,
/// and the owner signs each verdict himself — which is the only reason the 后悔
/// figure on the report is believable. The deck is capped at
/// `Rules.reckoningMaxCards`, the deferrals are bounded at `Rules.deferralLimit`,
/// and the whole thing can be walked out of without a word said about it.
struct ReckoningScreen: View {
    let onClose: () -> Void

    private enum Verdict { case worth, notWorth }

    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// The queue is read once and then held: judging an entry removes it from
    /// the live queue, and a deck that renumbered itself under the hand would
    /// lose its place. `nil` is "not read yet", which is not the same statement
    /// as an empty deck and must not print one.
    @State private var deck: [EffectiveEntry]?
    @State private var index = 0
    @State private var leaving: Verdict?
    @State private var stated = false
    @State private var notWorth = 0
    @State private var regret: Fen = 0
    @State private var drag: CGFloat = 0
    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                head
                content
            }
            .contentColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if deck == nil { deck = reckoningQueue(store.ledger, store.today) }
        }
        .onDisappear { advanceTask?.cancel() }
    }

    // MARK: - Head

    private var head: some View {
        HStack(spacing: Space.s3) {
            Button(action: onClose) {
                CloseGlyph()
                    .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
                    .foregroundStyle(Ink.ink700)
                    .frame(width: Space.s5, height: Space.s5)
                    .frame(width: Layout.hitTarget, height: Layout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(S.t(.commonClose))
            // The gutter belongs to the text column; the glyph aligns to it.
            .padding(.leading, -Space.s3)

            Spacer(minLength: 0)

            if let deck, index < deck.count {
                Text(S.t(.reckoningProgress, ["done": index + 1, "total": deck.count]))
                    .textStyle(.micro, mono: true)
            }
        }
        .padding(.top, Space.s2)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let deck {
            if deck.isEmpty {
                empty
            } else if index < deck.count {
                judging(deck[index], deck: deck)
            } else {
                summary(deck)
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            EmptyStateView(title: S.t(.reckoningEmpty)) {
                PrimaryButton(S.t(.commonDone), action: onClose)
            }
            Spacer(minLength: Space.s7)
        }
        .padding(.bottom, Space.s5)
    }

    private func judging(_ entry: EffectiveEntry, deck: [EffectiveEntry]) -> some View {
        let elapsed = diffDays(entry.day, store.today)
        // Only the first card says what came over from last week; after that the
        // count is stale, because the deck is being spent.
        let carried = index == 0 ? deck.filter { ($0.deferrals ?? 0) > 0 }.count : 0

        return VStack(spacing: 0) {
            Spacer(minLength: Space.s7)
            VStack(alignment: .leading, spacing: Space.s3) {
                if carried > 0 {
                    Text(S.t(.reckoningCarryover, ["n": carried]))
                        .textStyle(.micro, mono: true)
                }
                card(entry, deck: deck, elapsed: elapsed)
                // The ink a 不值 leaves in the position the card occupied; it
                // stays until the deck ends. §2.5's one use of the over tone on
                // something that is not a figure.
                if notWorth > 0 {
                    Rectangle()
                        .fill(Ink.figOver)
                        .frame(height: Layout.hairline / max(displayScale, 1))
                        .accessibilityHidden(true)
                }
                if stated {
                    Text(S.t(.reckoningAutoStatement)).textStyle(.body, ink: Ink.ink700)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: Space.s7)
            foot(entry)
        }
    }

    private func card(_ entry: EffectiveEntry, deck: [EffectiveEntry], elapsed: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MoneyView(fen: entry.effective, size: .screen, currency: entry.currency)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(categoryName(entry))
                .textStyle(.body, ink: Ink.ink700)
                .padding(.top, Space.s3)

            let payee = payee(entry)
            if !payee.isEmpty {
                Text(payee).textStyle(.body, ink: Ink.ink500)
            }

            // The interval is the point: a week on, the wanting has worn off,
            // which is what makes the verdict worth anything. ink300 below 19pt
            // is allowed here by R8's second clause — the card is one
            // accessibility element and its label carries the date in full.
            Text("\(entry.day.dropFirst(5)) · \(S.t(.reckoningDaysAgo, ["n": elapsed]))")
                .textStyle(.mono, mono: true, ink: Ink.ink300)

            if let promise = entry.promise, !promise.isEmpty {
                Text(S.t(.reckoningQuote))
                    .textStyle(.body, ink: Ink.ink500)
                    .padding(.top, Space.s5)
                // Quoted verbatim and never truncated: the sentence he wrote to
                // himself is the evidence, and an edited quote is not evidence.
                Text("「\(promise)」")
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Space.s3)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Ink.rule)
                            .frame(width: Layout.hairline * 2)
                    }
                    .padding(.top, Space.s1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .offset(x: offsetX)
        .opacity(leaving == nil ? 1 : 0)
        // A card deck is dragged, not only tapped: 1:1 under the finger, and
        // past the threshold the drag is the verdict.
        .gesture(
            DragGesture(minimumDistance: Space.s2)
                .onChanged { value in
                    guard !busy else { return }
                    drag = value.translation.width
                }
                .onEnded { value in
                    guard !busy else { return }
                    if abs(value.translation.width) >= swipeThreshold {
                        judge(worth: value.translation.width < 0, entry: entry)
                    } else {
                        withAnimation(swipeAnimation) { drag = 0 }
                    }
                }
        )
        // One record, one element: the parts of a card are a layout, not seven
        // things to arrow past.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(entry, deck: deck, elapsed: elapsed))
        .id(entry.id)
    }

    private func foot(_ entry: EffectiveEntry) -> some View {
        VStack(spacing: 0) {
            if stated {
                actions {
                    QuietButton(S.t(.reckoningNext), fullWidth: true) { next() }
                }
            } else {
                actions {
                    QuietButton(S.t(.reckoningWorth), fullWidth: true) {
                        judge(worth: true, entry: entry)
                    }
                    Rectangle()
                        .fill(Ink.rule)
                        .frame(width: Layout.hairline / max(displayScale, 1))
                        .frame(maxHeight: .infinity)
                    QuietButton(S.t(.reckoningNotWorth), fullWidth: true) {
                        judge(worth: false, entry: entry)
                    }
                }

                // Said before the deferral, not after it: the number is never
                // changed behind the owner's back.
                if lastDeferral(entry) {
                    Text(S.t(.reckoningLastChance, ["n": deferrals(entry)]))
                        .textStyle(.body, ink: Ink.ink700)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s3)
                }

                VStack(spacing: 0) {
                    link(S.t(.reckoningLaterCount,
                             ["n": min(deferrals(entry) + 1, Rules.deferralLimit)])) {
                        postpone(entry)
                    }
                    // Skipping is a way out, not a failure, and nothing is said
                    // about it here or anywhere else.
                    link(S.t(.reckoningSkip), action: onClose)
                }
                .padding(.top, Space.s2)
            }
        }
        .padding(.bottom, Space.s5)
    }

    private func summary(_ deck: [EffectiveEntry]) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.s7)
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(S.t(.reckoningDoneSummary, ["n": deck.count]))
                    .textStyle(.body, ink: Ink.ink700)
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    Text(S.t(.reckoningDoneNotWorth, ["n": notWorth]))
                        .textStyle(.body, ink: Ink.ink700)
                    Spacer(minLength: Space.s4)
                    MoneyView(fen: regret, size: .section, tone: .regret)
                }
                .accessibilityElement(children: .combine)
                if notWorth > 0 {
                    Text(S.t(.reckoningDoneNote)).textStyle(.body, ink: Ink.ink500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: Space.s7)
            RuleView()
            PrimaryButton(S.t(.commonDone), action: onClose)
                .padding(.top, Space.s6)
        }
        .padding(.bottom, Space.s5)
    }

    // MARK: - Parts

    /// §5.14 — two flat actions of equal width, a hairline between them and a
    /// structural rule above and below. No fill, no colour: 不值 is not red, and
    /// only the mark it leaves behind is.
    private func actions<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .frame(minHeight: Theme.barHeight)
            .overlay(alignment: .top) { Hairline(.strong) }
            .overlay(alignment: .bottom) { Hairline(.strong) }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .underline(true, color: Ink.ink500)
                .textStyle(.body, ink: Ink.ink700)
                .padding(.horizontal, Space.s4)
                .frame(minHeight: Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derivations

    private var busy: Bool { leaving != nil || stated }

    private var swipeAnimation: Animation? {
        // Reduced motion removes the depiction; there is no mechanic under this
        // one, so the card is simply replaced.
        reduceMotion ? nil : Motion.ease(Motion.verdictSwipe)
    }

    private var offsetX: CGFloat {
        switch leaving {
        case .worth: return -swipeTravel
        case .notWorth: return swipeTravel
        case nil: return drag
        }
    }

    /// Read from the live ledger rather than from the held deck: the fold owns
    /// the count, and the card must agree with what the fold will do next.
    private func deferrals(_ entry: EffectiveEntry) -> Int {
        store.ledger.entries[entry.id]?.deferrals ?? entry.deferrals ?? 0
    }

    private func lastDeferral(_ entry: EffectiveEntry) -> Bool {
        deferrals(entry) + 1 >= Rules.deferralLimit
    }

    private func categoryName(_ entry: EffectiveEntry) -> String {
        guard let category = store.ledger.categories[entry.categoryId] else { return "" }
        return S.locale == .en ? category.nameEn : category.name
    }

    /// The same fallback the ledger row prints, so a card and its row name the
    /// same purchase.
    private func payee(_ entry: EffectiveEntry) -> String {
        entry.note.isEmpty ? entry.merchant : entry.note
    }

    private func spoken(_ entry: EffectiveEntry, deck: [EffectiveEntry], elapsed: Int) -> String {
        let separator = S.locale == .en ? ", " : "，"
        let quote = (entry.promise?.isEmpty == false)
            ? "\(S.t(.reckoningQuote))「\(entry.promise ?? "")」" : ""
        return [
            S.t(.reckoningCardOf, ["i": index + 1, "n": deck.count]),
            format(entry.effective, currency: entry.currency),
            categoryName(entry),
            payee(entry),
            entry.day,
            S.t(.reckoningDaysAgo, ["n": elapsed]),
            quote,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: separator)
    }

    // MARK: - Verdicts

    private func judge(worth: Bool, entry: EffectiveEntry) {
        guard !busy else { return }
        store.commit(.reviewJudge(target: entry.id, worthIt: worth))
        if !worth {
            notWorth += 1
            regret += entry.effective
        }
        withAnimation(swipeAnimation) {
            leaving = worth ? .worth : .notWorth
            drag = 0
        }
        schedule(after: reduceMotion ? 0 : Motion.verdictSwipe)
    }

    private func postpone(_ entry: EffectiveEntry) {
        guard !busy else { return }
        let last = lastDeferral(entry)
        store.commit(.reviewDefer(target: entry.id))
        if last {
            // The fold has just written 不值 on this entry. The card says so and
            // waits, so a verdict is never recorded out of sight.
            notWorth += 1
            regret += entry.effective
            stated = true
            return
        }
        next()
    }

    private func schedule(after seconds: Double) {
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled else { return }
            next()
        }
    }

    private func next() {
        advanceTask?.cancel()
        advanceTask = nil
        leaving = nil
        stated = false
        drag = 0
        index += 1
    }
}

// MARK: - Icons

/// §8.3 icon 5, `xmark`: two lines on the 24 grid, drawn from the same geometry
/// as the web set. SF Symbols have no CSS equivalent and are forbidden (§8.1).
private struct CloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(6, 6)); path.addLine(to: point(18, 18))
        path.move(to: point(18, 6)); path.addLine(to: point(6, 18))
        return path
    }
}
