import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 设置 — one page that states every rule the app applies to its owner, with
/// nothing folded away: the standard line and every revision it has ever had,
/// the thresholds, the wish object, the sync surface, the categories, the two
/// display switches, and the door the whole event log leaves by.
///
/// It mirrors `web/src/screens/Settings.tsx` section for section. The one place
/// it deliberately reads better than the web page is the per-category standard:
/// every editable value on this screen wears the same well, so a figure that can
/// be typed over never looks like a figure that was merely printed.

/// The vault is only as strong as its passphrase, and this is the floor.
private let minPassphrase = 8
/// `proposeStandard` needs a 30-day span inside its 90-day window.
private let proposalDays = 30
private let defaultBranch = "main"

/// The sync server this build points at by default, so signing in is just an
/// email and a password. sslip.io resolves the dotted-IP name to the box, so a
/// real certificate is issued with no DNS record to create. Mirrors
/// web/src/sync/config.ts.
private let defaultServerURL = "https://43-162-121-196.sslip.io"
/// SCREENS.md B8: the save receipt is a line that stands for three seconds.
private let savedNote = Duration.seconds(3)

/// §8.2 — icons are drawn on a 24 grid at stroke 1.5, the one number in the icon
/// spec that is not a spacing step.
private let iconStroke: CGFloat = 1.5

/// A one-click link that pre-fills the scopes the vault needs, identical to the
/// web client's `TOKEN_URL`.
private let githubTokenURL = URL(
    string: "https://github.com/settings/tokens/new?scopes=repo&description=Countbook%20%E8%8A%B1%E5%BE%97%E5%80%BC"
)

/// The editable form of an amount: plain digits and a point, never grouped, so
/// that what a person typed and what the field shows are the same string.
private func yuanText(_ fen: Fen) -> String {
    let magnitude = fen.magnitude
    let frac = magnitude % 100
    return "\(fen < 0 ? minus : "")\(magnitude / 100).\(frac < 10 ? "0" : "")\(frac)"
}

private func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

/// `MM-DD HH:mm` — a sync time is a fact about this device's own clock, so it is
/// printed in the device's calendar rather than in the ledger's day strings.
private func stamp(_ milliseconds: Int) -> String {
    let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
    return "\(pad2(c.month ?? 0))-\(pad2(c.day ?? 0)) \(pad2(c.hour ?? 0)):\(pad2(c.minute ?? 0))"
}

/// 128 bits of CSPRNG output in lowercase hex — the id shape the store mints for
/// an event, reused here for the one record this screen creates itself.
private func newLocalID() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
}

/// The server names a device with the same installation id the ledger's HLC
/// uses, so a row in the device list and a row in the log mean the same phone.
private func thisDeviceID() -> String {
    UserDefaults.standard.string(forKey: "countbook.device")
        ?? UIDevice.current.identifierForVendor?.uuidString
        ?? "ios"
}

// MARK: - the screen

struct SettingsScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s7) {
                Text(S.t(.settingsTitle))
                    .textStyle(.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                StandardSection()
                WishSection()
                SyncSection()
                CategoriesSection()
                DisplaySection()
                DataSection()
                AboutLine()
            }
            .contentColumn()
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s9)
        }
        // The amount fields put a decimal pad on screen, which has no return
        // key; a drag has to be able to put it away again.
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.paper)
    }
}

// MARK: - shared parts of this screen

/// A section label, its one optional text action, the structural rule, and the
/// section's rows. Parts are separated by air rather than by nested cards (§5.2).
private struct SettingsSection<Trailing: View, Content: View>: View {
    let title: String
    var trailing: Trailing
    var content: Content

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
        VStack(alignment: .leading, spacing: Space.s4) {
            SectionHeader(title) { trailing }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// A block inside a section: its own rows, with a little more air above it than
/// between them, so a section does not read as one undifferentiated list.
private struct SettingsBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            content
        }
        .padding(.top, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// §5.6's text link. It sits beside the figure it would overwrite, so it takes
/// ink500 — the underline, not the ink, is what says the word is pressable — and
/// it keeps a full hit target while its padding is pulled back out so the words
/// stay on the grid.
private struct TextLink: View {
    let title: String
    var accessibilityLabel: String?
    var disabled = false
    let action: () -> Void

    init(
        _ title: String,
        accessibilityLabel: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .underline(!disabled, color: Ink.ink500)
                .textStyle(.body, ink: disabled ? Ink.ink300 : Ink.ink500)
                .padding(.horizontal, Space.s2)
                .frame(minHeight: Layout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.horizontal, -Space.s2)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// The well of `LabelledField`, without a label above it: a sunken ground, the
/// field radius, and a bottom rule that turns state-bearing while the cursor is
/// in it (§2.3). Nothing else moves — no fill, no lift, no ring.
private struct FieldWell<Content: View>: View {
    var focused: Bool
    var minWidth: CGFloat?
    var alignment: Alignment = .leading
    @ViewBuilder var content: Content

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .padding(.horizontal, Space.s3)
            .frame(minWidth: minWidth, minHeight: Layout.hitTarget, alignment: alignment)
            .background(Ink.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? Ink.ink500 : Ink.rule)
                    .frame(height: Layout.hairline / max(displayScale, 1))
            }
    }
}

/// A money cell in a table: the same ground, radius and state rule as the 月度
/// 标准 field, at the width of the amount column rather than of the row. The
/// affordance is the well, not the alignment — a bare right-aligned number reads
/// as a printed figure and nobody tries to type over it.
private struct AmountCell: View {
    let label: String
    @Binding var text: String
    var placeholder: String

    @FocusState private var focused: Bool

    var body: some View {
        FieldWell(focused: focused, minWidth: Theme.amountGutter, alignment: .trailing) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Ink.ink500))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .focused($focused)
                .textStyle(.row, mono: true, ink: Ink.ink900)
        }
        .accessibilityLabel(label)
    }
}

/// §8.3 #14 — the only error affordance in the product. It renders in ink900,
/// never in fig-over: red is rationed to three uses and an error is not one of
/// them. Drawn from the same 24-grid geometry as the web icon.
private struct ExclamationMark: View {
    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 24
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Ink.ink900)
                    .frame(width: iconStroke, height: 9.5 * unit)
                    .offset(x: 12 * unit - iconStroke / 2, y: 5 * unit)
                Rectangle()
                    .fill(Ink.ink900)
                    .frame(width: 2 * unit, height: 2 * unit)
                    .offset(x: 11 * unit, y: 17.5 * unit)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(width: Space.s5, height: Space.s5)
        .accessibilityHidden(true)
    }
}

/// A failure, stated: the mark, a 2pt ink900 rule down the left edge, and the
/// sentence itself. No colour, no dialog, no retry that hides what happened.
private struct ErrorNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            ExclamationMark()
            Text(message)
                .textStyle(.body, ink: Ink.ink900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(Ink.ink900).frame(width: Layout.hairline * 2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 标准线

/// Everything the standard editor derives from the log, computed once per commit
/// rather than inside a row body: the ledger can hold thousands of entries and
/// `proposeStandard` walks ninety days of them.
private struct StandardDerived {
    var monthlyFen: Fen = 0
    var perCategory: [String: Fen] = [:]
    var proposalMonthly: Fen = 0
    var proposalPerCategory: [String: Fen] = [:]
    var hasProposal = false
    var gateDays = proposalDays
    var categories: [Category] = []
    var revisions: [StandardRevision] = []
}

@MainActor
private struct StandardSection: View {
    @Environment(Store.self) private var store

    @State private var derived = StandardDerived()
    @State private var monthly = ""
    @State private var per: [String: String] = [:]
    @State private var leak = ""
    @State private var cooling = ""
    @State private var weekday = Rules.reckoningWeekday
    @State private var hour = Rules.reckoningHour
    @State private var seeded = false
    @State private var logged = false

    var body: some View {
        SettingsSection(title: S.t(.standardTitle)) {
            if derived.monthlyFen == 0 {
                Text(S.t(.standardEmpty))
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabelledField(
                label: S.t(.standardMonthly),
                text: $monthly,
                mono: true,
                keyboard: .decimalPad,
                suffix: S.t(.settingsYuan)
            )
            proposal

            SettingsBlock { categoryTable }
            SettingsBlock { thresholds }
            SettingsBlock { revisions }

            PrimaryButton(S.t(.standardSave), disabled: !canSave) { save() }
            if logged {
                Text(S.t(.standardSaved)).textStyle(.label)
            }
        }
        .task(id: store.events.count) { refresh() }
        .task(id: logged) {
            guard logged else { return }
            try? await Task.sleep(for: savedNote)
            guard !Task.isCancelled else { return }
            logged = false
        }
    }

    // MARK: figures

    private var monthlyFen: Fen? { parse(monthly) }
    private var leakFen: Fen? { parse(leak) }
    private var coolingFen: Fen? { parse(cooling) }

    /// One pass over at most twenty rows: the parsed per-category standards and
    /// whether every one of them was a number.
    private var perParsed: (values: [String: Fen], valid: Bool) {
        var values: [String: Fen] = [:]
        var valid = true
        for c in derived.categories {
            let raw = (per[c.id] ?? "").trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { continue }
            guard let value = parse(raw) else {
                valid = false
                continue
            }
            if value > 0 { values[c.id] = value }
        }
        return (values, valid)
    }

    private var standardChanged: Bool {
        guard let monthlyFen else { return false }
        return monthlyFen != derived.monthlyFen || perParsed.values != derived.perCategory
    }

    private var thresholdsChanged: Bool {
        let settings = store.ledger.settings
        if let leakFen, leakFen != settings.leakCeilingFen { return true }
        if let coolingFen, coolingFen != settings.coolingFloorFen { return true }
        return weekday != settings.reckoningWeekday || hour != settings.reckoningHour
    }

    private var canSave: Bool {
        guard let monthlyFen, monthlyFen > 0, leakFen != nil, coolingFen != nil else { return false }
        return perParsed.valid && (standardChanged || thresholdsChanged)
    }

    // MARK: parts

    @ViewBuilder
    private var proposal: some View {
        if derived.hasProposal {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(S.t(.standardPropose, ["amount": format(derived.proposalMonthly)]))
                    .textStyle(.label)
                Spacer(minLength: Space.s3)
                // A proposal is never written by the app; it is offered, and
                // adopting it is a thing the owner does (SCREENS.md B2).
                TextLink(S.t(.standardAccept)) { monthly = yuanText(derived.proposalMonthly) }
            }
        } else {
            Text(S.t(.standardProposeGate, ["n": derived.gateDays])).textStyle(.label)
        }
    }

    private var categoryTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(S.t(.standardPerCategory)).textStyle(.label)
                Spacer(minLength: Space.s3)
                Text(S.t(.settingsYuan)).textStyle(.label)
            }
            .padding(.bottom, Space.s2)
            .accessibilityElement(children: .combine)
            RuleView(strong: true)

            ForEach(derived.categories) { category in
                categoryRow(category)
            }

            allocation.padding(.top, Space.s3)
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        let name = S.locale == .en ? category.nameEn : category.name
        let suggested = derived.proposalPerCategory[category.id] ?? 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text(name).textStyle(.body).lineLimit(1)
                Spacer(minLength: Space.s3)
                AmountCell(
                    label: name,
                    text: binding(category.id),
                    placeholder: S.t(.standardUnset)
                )
            }
            if suggested > 0 {
                HStack(spacing: Space.s2) {
                    Spacer(minLength: 0)
                    Text(S.t(.standardSuggest, ["amount": format(suggested)])).textStyle(.label)
                    TextLink(
                        S.t(.standardAccept),
                        accessibilityLabel: "\(name) · "
                            + S.t(.standardSuggest, ["amount": format(suggested)])
                            + " · " + S.t(.standardAccept)
                    ) {
                        per[category.id] = yuanText(suggested)
                    }
                }
            }
            RuleView()
        }
        .padding(.vertical, Space.s1)
    }

    private var allocation: some View {
        let allocated = perParsed.values.values.reduce(0, +)
        let unallocated = (monthlyFen ?? 0) - allocated
        // Over-allocation does not block a save: it is your standard, and you
        // are the one answerable for it (SCREENS.md B4).
        return Text(
            unallocated < 0
                ? S.t(.standardAllocOver, ["a": format(allocated), "b": format(-unallocated)])
                : S.t(.standardAlloc, ["a": format(allocated), "b": format(monthlyFen ?? 0)])
        )
        .textStyle(.label, ink: unallocated < 0 ? Ink.figOver : Ink.ink500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var thresholds: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(S.t(.settingsThresholds)).textStyle(.label)
            LabelledField(
                label: S.t(.settingsLeakCeiling),
                text: $leak,
                mono: true,
                keyboard: .decimalPad,
                suffix: S.t(.settingsYuan)
            )
            Text(S.t(.settingsLeakCeilingHint))
                .textStyle(.label)
                .fixedSize(horizontal: false, vertical: true)
            LabelledField(
                label: S.t(.settingsCoolingFloor),
                text: $cooling,
                mono: true,
                keyboard: .decimalPad,
                suffix: S.t(.settingsYuan)
            )
            Text(S.t(.settingsCoolingFloorHint))
                .textStyle(.label)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s3) {
                Text(S.t(.settingsReckoningDay)).textStyle(.body)
                Spacer(minLength: Space.s3)
                StepperField(
                    label: S.t(.settingsReckoningDay),
                    value: $weekday,
                    min: 0,
                    max: 6,
                    format: { S.weekday($0) }
                )
                .frame(maxWidth: Theme.amountGutter + Layout.hitTarget * 2)
            }
            HStack(spacing: Space.s3) {
                Text(S.t(.settingsReckoningHour)).textStyle(.body)
                Spacer(minLength: Space.s3)
                StepperField(
                    label: S.t(.settingsReckoningHour),
                    value: $hour,
                    min: 0,
                    max: 23,
                    format: { "\(pad2($0)):00" }
                )
                .frame(maxWidth: Theme.amountGutter + Layout.hitTarget * 2)
            }
        }
    }

    private var revisions: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(S.t(.standardRevisions)).textStyle(.label)
            if derived.revisions.isEmpty {
                Text(S.t(.standardRevisionsEmpty)).textStyle(.body, ink: Ink.ink500)
            } else {
                // A revision is never deleted and never edited: the record of
                // when you moved the line is the point of having a line.
                ForEach(derived.revisions) { revision in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(toDay(Date(timeIntervalSince1970: Double(revision.at) / 1000)))
                                .textStyle(.mono, mono: true)
                            Spacer(minLength: Space.s3)
                            MoneyView(fen: revision.monthlyFen, size: .row)
                        }
                        if let reason = revision.reason, !reason.isEmpty {
                            Text(reason).textStyle(.label)
                        }
                        RuleView()
                    }
                    .padding(.vertical, Space.s1)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: state

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { per[id] ?? "" }, set: { per[id] = $0 })
    }

    private func refresh() {
        let ledger = store.ledger
        var next = StandardDerived()
        let current = standardAt(ledger, nowMillis())
        next.monthlyFen = current.monthlyFen
        next.perCategory = current.perCategory
        if let proposed = proposeStandard(ledger, store.today) {
            next.hasProposal = true
            next.proposalMonthly = proposed.monthlyFen
            next.proposalPerCategory = proposed.perCategory
        } else {
            next.gateDays = gateDays(ledger)
        }
        next.categories = ledger.categories.values
            .filter { $0.kind == .spend && $0.archived != true }
            .sorted { $0.order < $1.order }
        next.revisions = ledger.standards.reversed()
        derived = next
        if !seeded {
            seed()
            seeded = true
        }
    }

    /// How many more days of records a proposal needs (SCREENS.md B2's gate).
    private func gateDays(_ ledger: Ledger) -> Int {
        let since = addDays(store.today, -90)
        var first: Day?
        for e in ledger.entries.values
        where e.kind == .spend && e.day >= since && e.day <= store.today {
            if first == nil || e.day < first! { first = e.day }
        }
        guard let first else { return proposalDays }
        return max(1, proposalDays - diffDays(first, store.today))
    }

    private func seed() {
        monthly = derived.monthlyFen > 0 ? yuanText(derived.monthlyFen) : ""
        var seeded: [String: String] = [:]
        for (id, fen) in derived.perCategory where fen > 0 { seeded[id] = yuanText(fen) }
        per = seeded
        let settings = store.ledger.settings
        leak = yuanText(settings.leakCeilingFen)
        cooling = yuanText(settings.coolingFloorFen)
        weekday = settings.reckoningWeekday
        hour = settings.reckoningHour
    }

    private func save() {
        guard let monthlyFen, let leakFen, let coolingFen else { return }
        if thresholdsChanged {
            store.commit(.settingsPatch(patch: SettingsPatch(
                leakCeilingFen: leakFen,
                coolingFloorFen: coolingFen,
                reckoningWeekday: weekday,
                reckoningHour: hour
            )))
        }
        // A threshold is part of the line you are measured against, so changing
        // one is dated in the same log a standard change is (PRODUCT.md AC-15.3).
        store.commit(.standardSet(
            monthlyFen: monthlyFen,
            perCategory: perParsed.values,
            reason: standardChanged ? nil : S.t(.settingsThresholds)
        ))
        logged = true
    }
}

// MARK: - 心愿物

@MainActor
private struct WishSection: View {
    @Environment(Store.self) private var store

    @State private var name = ""
    @State private var price = ""
    @State private var seeded = false

    var body: some View {
        SettingsSection(title: S.t(.settingsWishObject)) {
            Text(S.t(.settingsWishObjectHint))
                .textStyle(.body, ink: Ink.ink500)
                .fixedSize(horizontal: false, vertical: true)
            LabelledField(label: S.t(.settingsWishName), text: $name, maxLength: 12)
            LabelledField(
                label: S.t(.settingsWishPrice),
                text: $price,
                mono: true,
                keyboard: .decimalPad,
                suffix: S.t(.settingsYuan)
            )
            HStack(spacing: Space.s3) {
                QuietButton(S.t(.commonSave), disabled: !canSave) { save() }
                if let wish = store.ledger.settings.wishObject, wish.priceFen > 0 {
                    DangerButton(S.t(.commonDelete), fullWidth: false) { clear() }
                }
            }
        }
        .task(id: store.events.count) { seed() }
    }

    private var priceFen: Fen? { parse(price) }
    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private var canSave: Bool {
        let wish = store.ledger.settings.wishObject
        let changed = trimmed != (wish?.name ?? "") || priceFen != wish?.priceFen
        return !trimmed.isEmpty && (priceFen ?? 0) > 0 && changed
    }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        guard let wish = store.ledger.settings.wishObject else { return }
        name = wish.name
        price = wish.priceFen > 0 ? yuanText(wish.priceFen) : ""
    }

    private func save() {
        guard let priceFen else { return }
        store.commit(.settingsPatch(patch: SettingsPatch(
            wishObject: Settings.WishObject(name: trimmed, priceFen: priceFen)
        )))
    }

    private func clear() {
        // Cleared by writing an empty object rather than dropping the key: an
        // absent field does not survive JSON on its way to another device, and a
        // clear that only works locally is a lie.
        store.commit(.settingsPatch(patch: SettingsPatch(
            wishObject: Settings.WishObject(name: "", priceFen: 0)
        )))
        name = ""
        price = ""
    }
}

// MARK: - 设备与同步

@MainActor
private struct SyncSection: View {
    @Environment(Store.self) private var store
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        if sync.phase == .off || sync.config == nil {
            SettingsSection(title: S.t(.syncTitle)) {
                Text(S.t(.syncOffNote))
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                ConnectForms()
            }
        } else if sync.phase == .locked {
            SettingsSection(title: S.t(.syncTitle)) {
                Text(S.t(.syncLocked))
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                UnlockForm()
                DangerButton(S.t(.syncDisconnect)) { sync.disconnect() }
            }
        } else {
            connected
        }
    }

    /// Always one word and never a spinner (SCREENS.md Y8): the timestamp is its
    /// own line beneath, and a failure states itself in a row of its own.
    private var stateWord: String {
        switch sync.phase {
        case .syncing: return S.t(.syncSyncing)
        case .offline: return S.t(.syncStateOffline)
        case .error: return S.t(.syncStateError)
        default: return S.t(.syncSynced)
        }
    }

    /// R2 — at most one chromatic figure per screen, and this screen already
    /// spends its one on an over-allocated standard. 待同步 is the state that
    /// earns fig-held (§2.5); 同步中 and 已同步 are ink, and an error is ink900
    /// beside its mark rather than a colour.
    private var stateInk: Color {
        switch sync.phase {
        case .offline: return Ink.ink500
        case .error: return Ink.ink900
        default: return Ink.ink700
        }
    }

    @ViewBuilder
    private var connected: some View {
        SettingsSection(
            title: S.t(.syncTitle),
            trailing: { Text(stateWord).textStyle(.mono, mono: true, ink: stateInk) }
        ) {
            if let config = sync.config {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(config.kind == .github ? S.t(.syncGithub) : S.t(.syncServer))
                        .textStyle(.body)
                    Spacer(minLength: Space.s3)
                    Text(config.describe)
                        .textStyle(.mono, mono: true)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
            }
            if let at = sync.lastSyncedAt {
                Text(S.t(.syncLastSeen, ["time": stamp(at)])).textStyle(.mono, mono: true)
            }
            if sync.phase == .error, !sync.message.isEmpty {
                ErrorNote(message: S.t(.syncError, ["message": sync.message]))
            }

            QuietButton(S.t(.syncNow), disabled: sync.phase == .syncing) {
                Task { await sync.syncNow() }
            }

            if let fingerprint = sync.fingerprint {
                SettingsBlock { FingerprintBlock(value: fingerprint) }
            }
            if case .server(let config, _)? = sync.config {
                SettingsBlock { DeviceList(config: config) }
            }

            SettingsBlock {
                Text(S.t(.syncDisconnectHint))
                    .textStyle(.body, ink: Ink.ink500)
                    .fixedSize(horizontal: false, vertical: true)
                DangerButton(S.t(.syncDisconnect)) { sync.disconnect() }
            }
        }
    }
}

/// Four mono hex quads, and a sentence saying what to do with them. Encryption is
/// presented as an interface fact, not as a marketing badge (SCREENS.md Y9).
@MainActor
private struct FingerprintBlock: View {
    @Environment(Store.self) private var store
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(S.t(.syncFingerprint)).textStyle(.label)
            Button {
                UIPasteboard.general.string = value
                store.toast(S.t(.syncCopied))
            } label: {
                Text(value)
                    .textStyle(.mono, mono: true, ink: Ink.ink700)
                    .frame(maxWidth: .infinity, minHeight: Layout.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(S.t(.syncFingerprint)) \(value)")
            Text(S.t(.syncFingerprintHint))
                .textStyle(.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The devices holding a key to this ledger, and the way to take one back.
@MainActor
private struct DeviceList: View {
    let config: ServerConfig

    @State private var rows: [DeviceRow] = []
    @State private var pending: String?
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if !rows.isEmpty {
                Text(S.t(.syncDevices)).textStyle(.label)
                ForEach(rows) { row in
                    deviceRow(row)
                }
            }
            if !error.isEmpty {
                ErrorNote(message: error)
            }
        }
        .task { await load() }
    }

    private func deviceRow(_ row: DeviceRow) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text(row.label.isEmpty ? row.device : row.label)
                    .textStyle(.body)
                    .lineLimit(1)
                Spacer(minLength: Space.s3)
                Text(row.current ? S.t(.syncThisDevice) : stamp(row.seenAt))
                    .textStyle(.mono, mono: true)
            }
            .accessibilityElement(children: .combine)

            if !row.current {
                if pending == row.ref {
                    // The confirmation is a sentence and two words, not a dialog:
                    // revoking a device is reversible by logging in again.
                    Text(S.t(.syncRevokeConfirm))
                        .textStyle(.label)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s3) {
                        TextLink(S.t(.commonConfirm)) { Task { await revoke(row.ref) } }
                        TextLink(S.t(.commonCancel)) { pending = nil }
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: Space.s3) {
                        TextLink(
                            S.t(.syncRevoke),
                            accessibilityLabel: "\(row.label.isEmpty ? row.device : row.label) · \(S.t(.syncRevoke))"
                        ) {
                            pending = row.ref
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            RuleView()
        }
    }

    private func load() async {
        do {
            rows = try await ServerStore.listDevices(config)
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func revoke(_ ref: String) async {
        pending = nil
        do {
            try await ServerStore.revokeDevice(config, ref: ref)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The locked phase: the vault is configured, the key is not on this device.
@MainActor
private struct UnlockForm: View {
    @Environment(SyncEngine.self) private var sync

    @State private var passphrase = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            LabelledField(label: S.t(.syncPassphrase), text: $passphrase, secure: true)
            if !error.isEmpty { ErrorNote(message: error) }
            PrimaryButton(
                busy ? S.t(.syncConnecting) : S.t(.syncUnlock),
                disabled: busy || passphrase.count < minPassphrase
            ) {
                unlock()
            }
        }
    }

    private func unlock() {
        busy = true
        error = ""
        Task {
            do {
                try await sync.unlock(passphrase: passphrase)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

/// The passphrase pair, shared by both adapters: typed twice, never sent.
private struct PassphrasePair: View {
    @Binding var passphrase: String
    @Binding var again: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            LabelledField(label: S.t(.syncPassphrase), text: $passphrase, secure: true)
            LabelledField(label: S.t(.syncPassphraseAgain), text: $again, secure: true)
            // Stated plainly and without colour: this is a fact about how the
            // vault works, not an error and not a warning (SCREENS.md Y6).
            Text(S.t(.syncPassphraseHint))
                .textStyle(.body, ink: Ink.ink500)
                .fixedSize(horizontal: false, vertical: true)
            if !problem.isEmpty {
                Text(problem)
                    .textStyle(.body, ink: Ink.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var problem: String {
        if !passphrase.isEmpty, passphrase.count < minPassphrase { return S.t(.syncPassphraseShort) }
        if !again.isEmpty, passphrase != again { return S.t(.syncPassphraseMismatch) }
        return ""
    }
}

private struct ConnectForms: View {
    @State private var kind = VaultStoreKind.server

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(S.t(.syncChoose)).textStyle(.label)
            SegmentedStamp(
                options: [
                    .init(value: VaultStoreKind.server, label: S.t(.syncServer)),
                    .init(value: VaultStoreKind.github, label: S.t(.syncGithub)),
                ],
                selection: kind,
                accessibilityLabel: S.t(.syncChoose)
            ) { kind = $0 }

            if kind == .github {
                GitHubForm()
            } else {
                ServerForm()
            }
        }
    }
}

@MainActor
private struct GitHubForm: View {
    @Environment(SyncEngine.self) private var sync

    @State private var owner = ""
    @State private var repo = ""
    @State private var branch = defaultBranch
    @State private var token = ""
    @State private var passphrase = ""
    @State private var again = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(S.t(.syncGithubHint))
                .textStyle(.body, ink: Ink.ink500)
                .fixedSize(horizontal: false, vertical: true)
            LabelledField(label: S.t(.syncOwner), text: $owner, mono: true)
            LabelledField(label: S.t(.syncRepo), text: $repo, mono: true)
            LabelledField(label: S.t(.syncBranch), text: $branch, mono: true)
            LabelledField(label: S.t(.syncToken), text: $token, mono: true, secure: true)
            if let url = githubTokenURL {
                Link(destination: url) {
                    Text(S.t(.syncTokenHelp))
                        .underline(true, color: Ink.ink900)
                        .textStyle(.body, ink: Ink.ink900)
                        .frame(minHeight: Layout.hitTarget)
                }
            }
            PassphrasePair(passphrase: $passphrase, again: $again)
            if !error.isEmpty { ErrorNote(message: error) }
            PrimaryButton(
                busy ? S.t(.syncConnecting) : S.t(.syncConnect),
                disabled: busy || !ready
            ) {
                connect()
            }
        }
    }

    private var ready: Bool {
        !owner.trimmingCharacters(in: .whitespaces).isEmpty
            && !repo.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
            && passphrase.count >= minPassphrase
            && passphrase == again
    }

    private func connect() {
        busy = true
        error = ""
        let config = GitHubConfig(
            owner: owner.trimmingCharacters(in: .whitespaces),
            repo: repo.trimmingCharacters(in: .whitespaces),
            branch: branch.trimmingCharacters(in: .whitespaces).isEmpty
                ? defaultBranch
                : branch.trimmingCharacters(in: .whitespaces),
            token: token.trimmingCharacters(in: .whitespaces)
        )
        Task {
            do {
                try await sync.connectGitHub(config, passphrase: passphrase, remember: true)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

@MainActor
private struct ServerForm: View {
    private enum Mode: String, Hashable { case login, signup }

    @Environment(SyncEngine.self) private var sync

    @State private var mode = Mode.login
    @State private var url = defaultServerURL
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(S.t(.syncServerHint))
                .textStyle(.body, ink: Ink.ink500)
                .fixedSize(horizontal: false, vertical: true)
            SegmentedStamp(
                options: [
                    .init(value: Mode.login, label: S.t(.syncLogin)),
                    .init(value: Mode.signup, label: S.t(.syncSignup)),
                ],
                selection: mode,
                accessibilityLabel: S.t(.syncServer)
            ) { mode = $0 }

            LabelledField(
                label: S.t(.syncServerUrl),
                text: $url,
                placeholder: "https://",
                mono: true,
                keyboard: .URL
            )
            LabelledField(label: S.t(.syncEmail), text: $email, mono: true, keyboard: .emailAddress)
            LabelledField(label: S.t(.syncPassword), text: $password, secure: true)
            if mode == .signup {
                LabelledField(label: S.t(.syncCode), text: $code, mono: true)
            }
            Text(S.t(.syncServerKeyHint))
                .textStyle(.body, ink: Ink.ink500)
                .fixedSize(horizontal: false, vertical: true)
            if !error.isEmpty { ErrorNote(message: error) }
            PrimaryButton(
                busy ? S.t(.syncConnecting) : (mode == .signup ? S.t(.syncSignup) : S.t(.syncLogin)),
                disabled: busy || !ready
            ) {
                submit()
            }
        }
    }

    // One secret: the account password authenticates and also derives the vault
    // key. See the note in the web ServerForm — a stolen database is ciphertext
    // plus a scrypt hash, and on a personal server the operator is you.
    private var ready: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && (mode == .signup ? password.count >= minPassphrase : !password.isEmpty)
    }

    private func submit() {
        busy = true
        error = ""
        var base = url.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        let account = email.trimmingCharacters(in: .whitespaces)
        let device = thisDeviceID()
        let label = SyncEngine.deviceLabel
        let mode = mode
        let password = password
        let code = code.trimmingCharacters(in: .whitespaces)
        let passphrase = password
        Task {
            do {
                // Logging in and unlocking the vault are two steps of one act,
                // so they happen on one press and on one page (SCREENS.md 13.7).
                let session = mode == .signup
                    ? try await ServerStore.signup(
                        baseUrl: base, email: account, password: password,
                        code: code, device: device, label: label
                    )
                    : try await ServerStore.login(
                        baseUrl: base, email: account, password: password,
                        device: device, label: label
                    )
                try await sync.connectServer(
                    ServerConfig(baseUrl: base, token: session.token),
                    email: account,
                    passphrase: passphrase,
                    remember: true
                )
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - 分类

@MainActor
private struct CategoriesSection: View {
    @Environment(Store.self) private var store

    @State private var kind = EntryKind.spend
    @State private var added = ""
    @State private var rows: [Category] = []
    @State private var used: Set<String> = []

    var body: some View {
        SettingsSection(title: S.t(.settingsCategories)) {
            SegmentedStamp(
                options: [
                    .init(value: EntryKind.spend, label: S.t(.captureSpend)),
                    .init(value: EntryKind.income, label: S.t(.captureIncome)),
                ],
                selection: kind,
                accessibilityLabel: S.t(.settingsCategories)
            ) { kind = $0 }

            ForEach(rows.filter { $0.kind == kind }) { category in
                CategoryRow(
                    category: category,
                    name: S.locale == .en ? category.nameEn : category.name,
                    deletable: !used.contains(category.id),
                    rename: { rename(category, to: $0) },
                    archive: {
                        var next = category
                        next.archived = !(category.archived ?? false)
                        store.commit(.categoryUpsert(category: next))
                    },
                    remove: { store.commit(.categoryRemove(target: category.id)) }
                )
            }

            SettingsBlock {
                LabelledField(label: S.t(.settingsCategoryAdd), text: $added, maxLength: 8)
                QuietButton(
                    S.t(.settingsCategoryAdd),
                    disabled: added.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    add()
                }
            }
        }
        .task(id: store.events.count) { refresh() }
    }

    private func refresh() {
        let ledger = store.ledger
        rows = ledger.categories.values.sorted { $0.order < $1.order }
        // A category that has never been used can be deleted outright; one that
        // has is archived instead, so an old row keeps the name it was filed
        // under.
        var seen = Set<String>()
        for e in ledger.entries.values { seen.insert(e.categoryId) }
        for s in ledger.subs.values { seen.insert(s.categoryId) }
        used = seen
    }

    private func rename(_ category: Category, to next: String) {
        let trimmed = next.trimmingCharacters(in: .whitespaces)
        let current = S.locale == .en ? category.nameEn : category.name
        guard !trimmed.isEmpty, trimmed != current else { return }
        var updated = category
        if S.locale == .en { updated.nameEn = trimmed } else { updated.name = trimmed }
        store.commit(.categoryUpsert(category: updated))
    }

    private func add() {
        let name = added.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let order = rows.filter { $0.kind == kind }.reduce(-1) { max($0, $1.order) } + 1
        store.commit(.categoryUpsert(category: Category(
            id: newLocalID(), name: name, nameEn: name, kind: kind, order: order
        )))
        added = ""
    }
}

/// One category: its name in a well, because a name that can be typed over must
/// look like it, and the two words that archive or delete it.
private struct CategoryRow: View {
    let category: Category
    let name: String
    let deletable: Bool
    let rename: (String) -> Void
    let archive: () -> Void
    let remove: () -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(
        category: Category,
        name: String,
        deletable: Bool,
        rename: @escaping (String) -> Void,
        archive: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        self.category = category
        self.name = name
        self.deletable = deletable
        self.rename = rename
        self.archive = archive
        self.remove = remove
        _draft = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            FieldWell(focused: focused) {
                TextField("", text: $draft)
                    .focused($focused)
                    .textStyle(.body, ink: Ink.ink900)
                    .submitLabel(.done)
            }
            .accessibilityLabel(S.t(.settingsCategoryName))

            HStack(spacing: Space.s3) {
                TextLink(
                    category.archived == true
                        ? S.t(.settingsCategoryRestore)
                        : S.t(.settingsCategoryArchive),
                    accessibilityLabel: "\(name) · " + (category.archived == true
                        ? S.t(.settingsCategoryRestore)
                        : S.t(.settingsCategoryArchive)),
                    action: archive
                )
                if deletable {
                    TextLink(
                        S.t(.commonDelete),
                        accessibilityLabel: "\(name) · \(S.t(.commonDelete))",
                        action: remove
                    )
                }
                Spacer(minLength: 0)
            }
            RuleView()
        }
        .onSubmit { rename(draft) }
        // A rename lands when the cursor leaves, not on every keystroke: one
        // event per decision, not one per letter.
        .onChange(of: focused) { _, now in
            if !now { rename(draft) }
        }
        .onChange(of: name) { _, next in
            if !focused { draft = next }
        }
    }
}

// MARK: - 显示

@MainActor
private struct DisplaySection: View {
    @Environment(Store.self) private var store

    var body: some View {
        let settings = store.ledger.settings
        SettingsSection(title: S.t(.settingsAppearance)) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(S.t(.settingsAppearance)).textStyle(.label)
                SegmentedStamp(
                    options: [
                        .init(value: Settings.Theme.system, label: S.t(.settingsThemeSystem)),
                        .init(value: Settings.Theme.light, label: S.t(.settingsThemeLight)),
                        .init(value: Settings.Theme.dark, label: S.t(.settingsThemeDark)),
                    ],
                    selection: settings.theme,
                    accessibilityLabel: S.t(.settingsAppearance)
                ) { theme in
                    store.commit(.settingsPatch(patch: SettingsPatch(theme: theme)))
                }
            }
            SettingsBlock {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(S.t(.settingsLanguage)).textStyle(.label)
                    SegmentedStamp(
                        options: [
                            .init(value: Settings.Locale.zhCN, label: "简体中文"),
                            .init(value: Settings.Locale.en, label: "English"),
                        ],
                        selection: settings.locale,
                        accessibilityLabel: S.t(.settingsLanguage)
                    ) { locale in
                        store.commit(.settingsPatch(patch: SettingsPatch(locale: locale)))
                    }
                }
            }
        }
    }
}

// MARK: - 数据

/// What travels is the event log, not a snapshot: corrections, voidances and
/// verdicts are events, so a log restores the ledger down to the day a figure
/// was changed, which a snapshot cannot.
private struct ExportBundle: Codable, Sendable {
    var app: String
    var schemaVersion: Int
    var exportedAt: String
    var currency: String
    var settings: Settings
    var events: [Event]
}

/// The system share sheet. Export hands the file to whatever the owner already
/// trusts with their files; the app keeps no copy and uploads nothing.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

@MainActor
private struct DataSection: View {
    @Environment(Store.self) private var store

    @State private var exported: ExportFile?
    @State private var importing = false
    @State private var error = ""

    var body: some View {
        SettingsSection(title: S.t(.settingsData)) {
            HStack(spacing: Space.s3) {
                QuietButton(S.t(.settingsExport)) { export() }
                QuietButton(S.t(.settingsImport)) { importing = true }
            }
            Text(S.t(.settingsExportHint, ["n": store.events.count]))
                .textStyle(.label)
                .fixedSize(horizontal: false, vertical: true)
            if !error.isEmpty { ErrorNote(message: error) }
        }
        .sheet(item: $exported) { file in
            ShareSheet(url: file.url)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func export() {
        error = ""
        let bundle = ExportBundle(
            app: "countbook",
            schemaVersion: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            currency: store.ledger.settings.currency,
            settings: store.ledger.settings,
            events: store.events
        )
        let name = "countbook-\(store.today).json"
        Task {
            // A few years of ledger is a megabyte of JSON; encoding it is not
            // allowed to drop a frame on the way to the share sheet.
            let written = await Task.detached(priority: .userInitiated) { () -> URL? in
                guard let data = try? JSONEncoder().encode(bundle) else { return nil }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
                return url
            }.value
            guard let written else {
                error = S.t(.settingsExportFailed)
                return
            }
            exported = ExportFile(url: written)
        }
    }

    private func load(_ url: URL) {
        error = ""
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(ExportBundle.self, from: data),
              bundle.app == "countbook"
        else {
            error = S.t(.settingsImportInvalid)
            return
        }
        // Merge, never replace: a backup restored onto a device that has kept
        // recording must not delete what was recorded since the backup.
        let before = store.events.count
        let merged = merge(store.events, bundle.events)
        store.replaceAll(merged)
        let gained = merged.count - before
        store.toast(S.t(.settingsImportSummary, [
            "n": gained,
            "skip": bundle.events.count - gained,
        ]))
    }
}

// MARK: - 版本

@MainActor
private struct AboutLine: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        Text(S.t(.settingsVersion, ["version": version ?? "1.0.0"]))
            .textStyle(.micro)
            .padding(.top, Space.s7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
