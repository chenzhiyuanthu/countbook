import SwiftUI

/// 待购 and 订阅 — the two lists in the product that are commitments rather than
/// records, and the only screen where money that was *not* spent gets ink.
///
/// The web client (`web/src/screens/Wants.tsx`) is the reference for behaviour
/// and order; two departures from it are deliberate and marked where they sit:
/// the cooling ring draws its unfilled track, and the archive's date column is
/// measured so a date can never wrap.

// MARK: - constants the screen states rather than the token file

/// Unit conversions, not design durations.
private let msPerMinute = 60_000
private let msPerHour = 60 * msPerMinute
private let msPerDay = 24 * msPerHour

/// DESIGN §5.10 fixes the arc's repaint cadence at one minute — not one frame.
/// The token file emits animation durations only, so the cadence is named here.
private let coolingCadenceMs = msPerMinute

/// Unhandled for a week: stated at the end of the row, never as a reminder.
private let staleDays = 7

/// Below three uses a per-use figure is arithmetic noise, not information.
private let perUseMinUses = 3

/// 其他 is the fallback category and PRODUCT §6 forbids disabling it.
private let wishCategoryId = "other"

private func periodKey(_ period: SubPeriod) -> StringKey {
    switch period {
    case .week: return .subsPeriodWeek
    case .month: return .subsPeriodMonth
    case .quarter: return .subsPeriodQuarter
    case .year: return .subsPeriodYear
    }
}

/// Stable across devices, so two of them claiming the same series converge.
private func detectedID(_ d: Detected) -> String {
    "detected:\(d.key):\(d.amount):\(d.period.rawValue)"
}

private func pad2(_ n: Int) -> String { n < 10 && n >= 0 ? "0\(n)" : "\(n)" }

/// 128 bits of randomness in lowercase hex, the shape of every id in the log.
private func freshID() -> String {
    (UUID().uuidString + UUID().uuidString)
        .replacingOccurrences(of: "-", with: "")
        .lowercased()
        .prefix(32)
        .description  // 32 hex characters, as the log writes them
}

// MARK: - the model

/// Everything both lists print, derived once per body evaluation. The Compute
/// functions walk the whole ledger — `detectRecurring` reads every spend — so
/// they are called here and nowhere else, and a row body only prints strings
/// this struct already holds.
@MainActor
private struct WantsModel {
    struct Unlocked: Identifiable {
        let wish: Wish
        let stale: String?
        var id: String { wish.id }
    }

    struct Cooling: Identifiable {
        let wish: Wish
        let remaining: Double
        let countdown: String
        var id: String { wish.id }
    }

    struct Archived: Identifiable {
        let id: String
        let date: String
        let name: String
        let price: Fen
    }

    struct Unclaimed: Identifiable {
        let detected: Detected
        let detail: String
        let meta: String
        var id: String { detectedID(detected) }
    }

    struct Active: Identifiable {
        let sub: Sub
        let annual: Fen
        let terms: String
        let schedule: String
        let pending: Bool
        var id: String { sub.id }
    }

    struct Ended: Identifiable {
        let id: String
        let name: String
        let line: String
    }

    let currency: String
    let year: String
    let abstainedYear: Fen
    let unlocked: [Unlocked]
    let cooling: [Cooling]
    let archive: [Archived]

    let annual: Fen
    let perDay: Fen
    let bar: [AnnualBarRow]
    let unclaimed: [Unclaimed]
    let active: [Active]
    let ended: [Ended]
    let saved: Fen
    let hasActive: Bool

    var pending: Bool { !unlocked.isEmpty || !cooling.isEmpty }
    var noWishes: Bool { unlocked.isEmpty && cooling.isEmpty && archive.isEmpty }
    var noSubs: Bool { !hasActive && ended.isEmpty && unclaimed.isEmpty }

    init(ledger: Ledger, today: Day, nowMs: Int) {
        let currency = ledger.settings.currency
        self.currency = currency
        year = String(today.prefix(4))
        abstainedYear = wishStats(ledger, today, nowMs).abstainedYear

        let open = ledger.wishes.values.filter { $0.outcome == nil }
        unlocked = open
            .filter { $0.unlockAt <= nowMs }
            .sorted { $0.unlockAt < $1.unlockAt }
            .map { wish in
                let days = (nowMs - wish.unlockAt) / msPerDay
                return Unlocked(
                    wish: wish,
                    stale: days >= staleDays ? S.t(.wantsStale, ["n": days]) : nil
                )
            }
        cooling = open
            .filter { $0.unlockAt > nowMs }
            .sorted { $0.unlockAt < $1.unlockAt }
            .map { wish in
                // The whole cooling period, so an arc that started long ago and
                // one that started this morning deplete at the same rate.
                let total = max(1, wish.unlockAt - wish.createdAt)
                let left = max(0, wish.unlockAt - nowMs)
                let hours = (left % msPerDay) / msPerHour
                let minutes = (left % msPerHour) / msPerMinute
                let time = "\(pad2(hours)):\(pad2(minutes))"
                let days = left / msPerDay
                return Cooling(
                    wish: wish,
                    remaining: Double(left) / Double(total),
                    countdown: days > 0
                        ? S.t(.wantsCooling, ["days": days, "time": time])
                        : S.t(.wantsCoolingHours, ["time": time])
                )
            }
        let year = self.year
        archive = ledger.wishes.values
            .filter { $0.outcome == .abstained && $0.resolvedAt != nil }
            .compactMap { wish -> (Wish, Day)? in
                guard let at = wish.resolvedAt else { return nil }
                let day = toDay(Date(timeIntervalSince1970: Double(at) / 1000))
                return day.hasPrefix(year) ? (wish, day) : nil
            }
            .sorted { ($0.0.resolvedAt ?? 0) > ($1.0.resolvedAt ?? 0) }
            .map { wish, day in
                Archived(id: wish.id, date: String(day.dropFirst(5)), name: wish.name, price: wish.price)
            }

        let views = subViews(ledger, today)
        annual = views.annual
        perDay = views.perDay
        saved = savedByCancelling(ledger, today)

        let liveRows = views.rows.filter { $0.sub.status == .keep || $0.sub.status == .pendingCancel }
        hasActive = !liveRows.isEmpty
        bar = liveRows.map { AnnualBarRow(label: $0.sub.name, annual: $0.annual) }
        active = liveRows.map { row in
            let uses = row.sub.usageDays?.count ?? 0
            let terms = [
                S.t(.subsAmountPer, [
                    "period": S.t(periodKey(row.sub.period)),
                    "amount": format(row.sub.amount, currency: currency),
                ]),
                S.t(.subsPaid, [
                    "paid": format(row.paidSoFar, currency: currency),
                    "since": String(row.sub.firstChargedAt.prefix(7)),
                ]),
            ].joined(separator: " · ")
            var schedule = [S.t(.subsNext, ["day": row.sub.nextChargeAt])]
            if uses >= perUseMinUses, let perUse = row.perUse {
                schedule.append(S.t(.subsPerUse, ["amount": format(perUse, currency: currency)]))
            }
            return Active(
                sub: row.sub,
                annual: row.annual,
                terms: terms,
                schedule: schedule.joined(separator: " · "),
                pending: row.sub.status == .pendingCancel
            )
        }
        ended = views.rows
            .filter { $0.sub.status == .cancelled }
            .map { row in
                let since = row.sub.cancelledAt ?? row.sub.nextChargeAt
                // The same accrual `savedByCancelling` sums, printed per row.
                let savedHere = row.annual * max(0, diffDays(since, today)) / 365
                return Ended(
                    id: row.sub.id,
                    name: row.sub.name,
                    line: S.t(.subsEndedRow, [
                        "month": String(since.prefix(7)),
                        "amount": format(savedHere, currency: currency),
                    ])
                )
            }

        let names = ledger.categories.mapValues { S.locale == .en ? $0.nameEn : $0.name }
        unclaimed = detectRecurring(ledger, today)
            .filter { ledger.subs[detectedID($0)] == nil }
            .map { d in
                Unclaimed(
                    detected: d,
                    detail: S.t(.subsUnclaimedRow, [
                        "period": S.t(periodKey(d.period)),
                        "amount": format(d.amount, currency: currency),
                        "n": d.occurrences,
                    ]),
                    meta: "\(names[d.categoryId] ?? d.categoryId) · \(S.t(.subsNext, ["day": d.nextChargeAt]))"
                )
            }
    }
}

// MARK: - the screen

@MainActor
struct WantsScreen: View {
    /// The capture sheet belongs to the shell, so the empty state can only offer
    /// it where the shell has handed down a way to open it.
    var onCapture: (() -> Void)? = nil

    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var adding = false
    /// The one clock on this screen. Every arc and countdown reads it, so they
    /// all step together and the list is laid out once a minute, not once a
    /// minute per row.
    @State private var minute = nowMillis()

    var body: some View {
        let model = WantsModel(ledger: store.ledger, today: store.today, nowMs: minute)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                wants(model)
                subscriptions(model).padding(.top, Space.s8)
            }
            .padding(.vertical, Space.s6)
            .contentColumn()
        }
        .background(Ink.paper)
        .task(id: model.pending) { await keepTime(while: model.pending) }
        .sheet(isPresented: $adding) {
            AddWishSheet(onClose: { adding = false })
                .presentationBackground(.clear)
        }
    }

    // MARK: 待购

    @ViewBuilder
    private func wants(_ model: WantsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(S.t(.wantsTitle))
                    .textStyle(.label, ink: Ink.ink900)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Space.s5)
                Text(S.t(.wantsAbstainedYear)).textStyle(.label)
                // 绿色要挣得: until something has been given up there is nothing
                // to colour. iOS's MoneyView owns the ink of a figure and offers
                // no ink300 role, so a zero prints as the ordinary section
                // figure rather than in the web's lighter grey.
                MoneyView(
                    fen: model.abstainedYear,
                    size: .section,
                    tone: model.abstainedYear == 0 ? nil : .spared,
                    currency: model.currency
                )
                .padding(.vertical, Space.s1)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, Space.s6)

            RuleView(strong: true)

            if model.noWishes {
                EmptyStateView(title: S.t(.wantsEmpty), body: S.t(.wantsEmptyHint)) {
                    QuietButton(S.t(.wantsAdd)) { adding = true }
                        .padding(.leading, -Space.s4)
                }
            }

            if !model.unlocked.isEmpty {
                group(S.t(.wantsUnlocked)) {
                    ForEach(model.unlocked) { row in
                        unlockedRow(row, currency: model.currency)
                            .transition(rowLeaves)
                    }
                }
            }

            if !model.cooling.isEmpty {
                group(S.t(.wantsHolding)) {
                    ForEach(model.cooling) { row in
                        coolingRow(row, currency: model.currency)
                            .transition(rowLeaves)
                    }
                }
            }

            if !model.archive.isEmpty {
                group(S.t(.wantsArchive, ["year": model.year])) {
                    ForEach(model.archive) { row in
                        archiveRow(row, currency: model.currency)
                    }
                }
            }

            if !model.noWishes {
                QuietButton(S.t(.wantsAdd)) { adding = true }
                    .padding(.leading, -Space.s4)
                    .padding(.top, Space.s6)
            }
        }
    }

    private func unlockedRow(_ row: WantsModel.Unlocked, currency: String) -> some View {
        let wish = row.wish
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(wish.name)
                    .textStyle(.body, ink: Ink.ink700)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Space.s3)
                MoneyView(fen: wish.price, size: .row, tone: nil, currency: currency)
                    .frame(minWidth: Theme.amountGutter, alignment: .trailing)
            }
            .padding(.vertical, Layout.rowPadY)
            .frame(minHeight: Layout.hitTarget)
            .accessibilityElement(children: .combine)

            Hairline()

            // One question, two flat actions. No third path, no dialog.
            Text(S.t(.wantsReady))
                .textStyle(.body, ink: Ink.ink700)
                .padding(.top, Space.s3)

            if let stale = row.stale {
                Text(stale).textStyle(.micro).padding(.top, Space.s1)
            }

            flatPair(
                leading: (S.t(.wantsBuy), "\(S.t(.wantsBuy)) · \(wish.name)", { buy(wish) }),
                trailing: (S.t(.wantsAbstain), "\(S.t(.wantsAbstain)) · \(wish.name)", { abstain(wish) })
            )
            .padding(.top, Space.s3)
        }
        .padding(.bottom, Space.s4)
        .accessibilityElement(children: .contain)
    }

    private func coolingRow(_ row: WantsModel.Cooling, currency: String) -> some View {
        let wish = row.wish
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.s3) {
                // The ring draws its unfilled track as well as what is left of
                // the arc: a bare arc reads as a stray mark exactly when it is
                // nearly depleted, which is the moment it matters most. The
                // countdown beside it speaks the figure, so the ring is silent.
                DepletingRing(fraction: row.remaining, size: Space.s7, tone: .held)

                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text(wish.name)
                            .textStyle(.body, ink: Ink.ink700)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: Space.s3)
                        MoneyView(fen: wish.price, size: .row, tone: .held, currency: currency)
                            .frame(minWidth: Theme.amountGutter, alignment: .trailing)
                    }
                    Text(row.countdown)
                        .textStyle(.mono, mono: true, ink: Ink.figHeld)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)

            TextLink(
                S.t(.wantsRemove),
                accessibilityLabel: "\(S.t(.wantsRemove)) · \(wish.name)"
            ) { remove(wish) }
                .padding(.leading, Space.s7 + Space.s3)
        }
        .padding(.vertical, Layout.rowPadY)
        .background(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .contain)
    }

    private func archiveRow(_ row: WantsModel.Archived, currency: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            // The date takes its intrinsic width rather than a share of the row:
            // MM-DD is five tabular characters and must never wrap to a second
            // line, which is what the web column does at large type sizes.
            Text(row.date)
                .textStyle(.mono, mono: true)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(row.name)
                .textStyle(.body, ink: Ink.ink700)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.s3)
            MoneyView(fen: row.price, size: .row, tone: .spared, currency: currency)
                .frame(minWidth: Theme.amountGutter, alignment: .trailing)
        }
        .padding(.vertical, Layout.rowPadY)
        .frame(minHeight: Layout.hitTarget)
        .background(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    // MARK: 订阅

    @ViewBuilder
    private func subscriptions(_ model: WantsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(S.t(.subsTitle))
                    .textStyle(.label, ink: Ink.ink900)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Space.s5)
                Text(S.t(.subsAnnualLabel)).textStyle(.label)
                // The year, not the month: a subscription is evaluated monthly
                // and paid annually, and only one of those two figures is shown.
                MoneyView(fen: model.annual, size: .section, tone: nil, currency: model.currency)
                    .padding(.vertical, Space.s1)
                Text(S.t(.subsPerDay, ["amount": format(model.perDay, currency: model.currency)]))
                    .textStyle(.micro)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, Space.s6)

            if model.hasActive {
                AnnualBarView(rows: model.bar)
                    .padding(.top, Space.s5)
                    .padding(.bottom, Space.s6)
            }

            RuleView(strong: true)

            if model.noSubs {
                EmptyStateView(title: S.t(.subsEmpty)) {
                    if let onCapture = onCapture {
                        TextLink(S.t(.captureTitle), action: onCapture)
                    }
                }
            }

            if !model.unclaimed.isEmpty {
                group(S.t(.subsUnclaimedCount, ["n": model.unclaimed.count])) {
                    ForEach(model.unclaimed) { row in
                        unclaimedRow(row, currency: model.currency)
                    }
                }
            }

            if model.hasActive || !model.ended.isEmpty {
                group(S.t(.subsActive)) {
                    if !model.hasActive {
                        Text(S.t(.subsEmptyActive))
                            .textStyle(.body, ink: Ink.ink700)
                            .padding(.top, Space.s1)
                    }
                    ForEach(model.active) { row in
                        activeRow(row, currency: model.currency)
                    }
                }
            }

            if !model.ended.isEmpty {
                group(S.t(.subsCancelled), figure: {
                    // 已省 keeps accruing after the cancellation: stopping a
                    // subscription is a line that goes on producing credit.
                    MoneyView(fen: model.saved, size: .row, tone: .spared, currency: model.currency)
                        .frame(minWidth: Theme.amountGutter, alignment: .trailing)
                }) {
                    ForEach(model.ended) { row in
                        endedRow(row)
                    }
                }
            }
        }
    }

    private func unclaimedRow(_ row: WantsModel.Unclaimed, currency: String) -> some View {
        let d = row.detected
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(d.name)
                        .textStyle(.body, ink: Ink.ink700)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: Space.s3)
                    MoneyView(fen: d.amount, size: .row, tone: .held, currency: currency)
                        .frame(minWidth: Theme.amountGutter, alignment: .trailing)
                }
                .padding(.vertical, Layout.rowPadY)
                .frame(minHeight: Layout.hitTarget)

                Hairline()

                Text(row.detail).textStyle(.body).padding(.top, Space.s1)
                Text(row.meta).textStyle(.micro)
            }
            .accessibilityElement(children: .combine)

            // Nothing is claimed on the reader's behalf: a detected series is
            // signed for one way or the other, and until then it is not a
            // subscription.
            flatPair(
                leading: (S.t(.subsKeep), "\(S.t(.subsKeep)) · \(d.name)", { claim(d, as: .keep) }),
                trailing: (S.t(.subsCancel), "\(S.t(.subsCancel)) · \(d.name)", { claim(d, as: .pendingCancel) })
            )
            .padding(.top, Space.s3)
        }
        .padding(.bottom, Space.s4)
        .accessibilityElement(children: .contain)
    }

    private func activeRow(_ row: WantsModel.Active, currency: String) -> some View {
        let sub = row.sub
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(sub.name)
                        .textStyle(.body, ink: Ink.ink700)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.pending {
                        Text(S.t(.subsPending)).textStyle(.mono, mono: true, ink: Ink.figHeld)
                    }
                }
                Spacer(minLength: Space.s3)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(S.t(.subsAnnualLabel)).textStyle(.micro)
                    MoneyView(fen: row.annual, size: .row, tone: nil, currency: currency)
                }
                .frame(minWidth: Theme.amountGutter, alignment: .trailing)
            }
            .padding(.vertical, Layout.rowPadY)

            Hairline()

            Text(row.terms).textStyle(.body).padding(.top, Space.s1)
            Text(row.schedule).textStyle(.micro)

            HStack(spacing: Space.s5) {
                TextLink(
                    S.t(.subsLogUse),
                    accessibilityLabel: "\(S.t(.subsLogUse)) · \(sub.name)"
                ) { store.commit(.subUse(target: sub.id, day: store.today)) }
                TextLink(
                    S.t(.subsMarkEnded),
                    accessibilityLabel: "\(S.t(.subsMarkEnded)) · \(sub.name)"
                ) { store.commit(.subStatus(target: sub.id, status: .cancelled, day: store.today)) }
            }
            .padding(.top, Space.s1)
        }
        .padding(.bottom, Space.s4)
        .accessibilityElement(children: .contain)
    }

    private func endedRow(_ row: WantsModel.Ended) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(row.name)
                .textStyle(.body, ink: Ink.ink700)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(row.line).textStyle(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Layout.rowPadY)
        .background(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    // MARK: shared parts

    /// A section label, 12 of air, its structural rule, and the rows under it.
    @ViewBuilder
    private func group<Figure: View, Content: View>(
        _ title: String,
        @ViewBuilder figure: () -> Figure,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title) { figure() }
            content()
        }
        .padding(.top, Space.s6)
    }

    @ViewBuilder
    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        group(title, figure: { EmptyView() }, content: content)
    }

    /// §5.6 — two flat actions side by side, parted by a full-height hairline
    /// and opened by the structural rule above them. There is no third option.
    private func flatPair(
        leading: (title: String, label: String, run: () -> Void),
        trailing: (title: String, label: String, run: () -> Void)
    ) -> some View {
        VStack(spacing: 0) {
            Hairline(.strong)
            HStack(spacing: 0) {
                QuietButton(leading.title, fullWidth: true, accessibilityLabel: leading.label, action: leading.run)
                VerticalHairline()
                QuietButton(trailing.title, fullWidth: true, accessibilityLabel: trailing.label, action: trailing.run)
            }
            .frame(minHeight: Theme.barHeight)
        }
    }

    /// §5.5 verdictSwipe — a resolved row leaves to the right. No bounce, no
    /// confetti, no congratulation; it simply stops being on the list.
    private var rowLeaves: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: the clock

    /// Aligned to the wall-clock minute so the whole screen steps at once, and
    /// running only while something is actually cooling.
    private func keepTime(while active: Bool) async {
        guard active else { return }
        while !Task.isCancelled {
            let wait = coolingCadenceMs - (nowMillis() % coolingCadenceMs)
            try? await Task.sleep(for: .milliseconds(wait))
            if Task.isCancelled { return }
            minute = nowMillis()
        }
    }

    // MARK: commits

    private func buy(_ wish: Wish) {
        let entryID = freshID()
        // The stamp is 想要 because the want list is the definition of 想要; the
        // entry is an ordinary row and can be re-stamped in 账页.
        let added = store.commit(.entryAdd(entry: Entry(
            id: entryID,
            kind: .spend,
            amount: wish.price,
            currency: store.ledger.settings.currency,
            categoryId: wishCategoryId,
            intent: .want,
            note: wish.name,
            merchant: "",
            day: store.today,
            createdAt: nowMillis(),
            wishId: wish.id
        )))
        let resolved = withAnimation(motion) {
            store.commit(.wishResolve(target: wish.id, outcome: .bought, entryId: entryID))
        }
        store.toast(S.t(.wantsEntered), action: ToastAction(label: S.t(.ledgerUndo)) {
            store.undo(eventID: resolved)
            store.undo(eventID: added)
        })
    }

    private func abstain(_ wish: Wish) {
        let id = withAnimation(motion) {
            store.commit(.wishResolve(target: wish.id, outcome: .abstained, entryId: nil))
        }
        store.toast(S.t(.wantsAbstainedDone), action: ToastAction(label: S.t(.ledgerUndo)) {
            store.undo(eventID: id)
        })
    }

    /// Removing is not abstaining: nothing is added to 已放弃, because no
    /// decision was made.
    private func remove(_ wish: Wish) {
        let id = withAnimation(motion) { store.commit(.wishRemove(target: wish.id)) }
        store.toast(S.t(.wantsRemoved), action: ToastAction(label: S.t(.ledgerUndo)) {
            store.undo(eventID: id)
        })
    }

    private func claim(_ d: Detected, as status: SubStatus) {
        store.commit(.subUpsert(sub: Sub(
            id: detectedID(d),
            name: d.name,
            amount: d.amount,
            period: d.period,
            categoryId: d.categoryId,
            firstChargedAt: d.firstChargedAt,
            nextChargeAt: d.nextChargeAt,
            status: status,
            detected: true
        )))
    }

    private var motion: Animation? {
        reduceMotion ? nil : Motion.ease(Motion.verdictSwipe)
    }
}

// MARK: - 加入待购

/// The cooling period is derived from the price and shown before the item is
/// held. It is read-only: a cooling period you can choose is not one.
private struct AddWishSheet: View {
    let onClose: () -> Void

    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var price = ""

    private var parsed: Fen? {
        guard let fen = parse(price), fen > 0 else { return nil }
        return fen
    }

    private var days: Int { parsed.map { coolingDays($0) } ?? 0 }

    private var valid: Bool {
        parsed != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SheetContainer(title: S.t(.wantsAddTitle), onClose: onClose) {
            VStack(alignment: .leading, spacing: Space.s4) {
                LabelledField(
                    label: S.t(.wantsPrice),
                    text: $price,
                    mono: true,
                    keyboard: .decimalPad,
                    suffix: store.ledger.settings.currency == "CNY"
                        ? nil
                        : store.ledger.settings.currency
                )
                LabelledField(label: S.t(.wantsName), text: $name, maxLength: 24)

                RuleView()

                if days > 0 {
                    Text(S.t(.wantsCoolingCalc, [
                        "days": days,
                        "date": addDays(store.today, days),
                    ]))
                    .textStyle(.body)
                }

                HeldBar(S.t(.captureSuspend, ["days": days]), disabled: !valid, action: submit)
            }
        }
    }

    private func submit() {
        guard let fen = parsed, valid else { return }
        let at = nowMillis()
        store.commit(.wishAdd(wish: Wish(
            id: freshID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            price: fen,
            createdAt: at,
            unlockAt: at + coolingDays(fen) * msPerDay
        )))
        onClose()
    }
}

// MARK: - screen-local primitives

/// §5.6, the held bar: the surface, a `fig-held` hairline border and a
/// `fig-held` label at 600. It is the one bar in the product that is neither ink
/// nor empty, and it exists so that holding an item reads as the default action
/// rather than as a refusal to buy.
private struct HeldBar: View {
    let title: String
    var disabled: Bool
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicType

    init(_ title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: TextRole.body.size(at: dynamicType), weight: .semibold))
                .foregroundStyle(disabled ? Ink.ink300 : Ink.figHeld)
                .padding(.horizontal, Space.s4)
                .frame(maxWidth: .infinity, minHeight: Theme.barHeight)
                .background(Ink.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(disabled ? Ink.rule : Ink.figHeld,
                                      lineWidth: Layout.hairline / max(displayScale, 1))
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// §5.6, the text link: body ink, a hairline underline in the state-bearing
/// rule colour, and a 44 hit target won by padding rather than by a box.
private struct TextLink: View {
    let title: String
    var accessibilityLabel: String?
    let action: () -> Void

    init(_ title: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .underline(true, color: Ink.ink500)
                .textStyle(.body, ink: Ink.ink700)
                .frame(minHeight: Layout.hitTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// The vertical companion to `Hairline`, which is horizontal only: one device
/// pixel wide, stretched by whatever row it parts.
private struct VerticalHairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Ink.rule)
            .frame(width: Layout.hairline / max(displayScale, 1))
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
