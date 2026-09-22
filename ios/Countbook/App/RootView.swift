import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case today, ledger, report, wants, settings

    var id: String { rawValue }

    var label: StringKey {
        switch self {
        case .today: return .tabToday
        case .ledger: return .tabLedger
        case .report: return .tabReport
        case .wants: return .tabWants
        case .settings: return .tabSettings
        }
    }

    var glyph: GlyphName {
        switch self {
        case .today: return .today
        case .ledger: return .ledger
        case .report: return .report
        case .wants: return .wants
        case .settings: return .settings
        }
    }
}

extension Tab {
    /// Lets a screenshot run open straight onto a tab:
    ///   xcrun simctl launch <udid> com.czy.countbook -startTab report
    /// Debug only — the shipping app always opens on 今日.
    static var launchDefault: Tab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "startTab"),
           let tab = Tab(rawValue: raw) {
            return tab
        }
        #endif
        return .today
    }

    /// Likewise `-openCapture 1` raises the capture sheet once the shell is up,
    /// so the sheet can be looked at without a tap the screenshot run cannot make.
    static var launchCapturing: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "openCapture")
        #else
        return false
        #endif
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(SyncEngine.self) private var sync

    @State private var tab: Tab = Tab.launchDefault
    @State private var capturing = false
    @State private var reckoning = false
    /// The reckoning is offered once per day per launch; a modal that came back
    /// on every foreground would make people stop opening the app on Sundays.
    @State private var reckonedOn: Day?

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            if store.ready {
                shell
            } else {
                Text(S.t(.commonLoading))
                    .font(TypeScale.labelCJK.font)
                    .kerning(TypeScale.labelCJK.kerning)
                    .foregroundStyle(Ink.ink500)
            }
        }
        .task { await boot() }
        .onChange(of: store.now) { offerReckoning() }
    }

    private var shell: some View {
        screen
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .top, spacing: 0) { SyncMark { tab = .settings } }
            .safeAreaInset(edge: .bottom, spacing: 0) { captureClearance }
            .overlay(alignment: .bottomTrailing) { captureButton }
            // Same slot as the 记 button, so the two are measured from the same
            // edge: 16 above the tab bar (DESIGN.md §5.12), or above the button
            // where there is one.
            .overlay(alignment: .bottom) { toast }
            .safeAreaInset(edge: .bottom, spacing: 0) { TabBar(tab: $tab) }
            .sheet(isPresented: $capturing) {
                CaptureScreen(onClose: { capturing = false })
            }
            .fullScreenCover(isPresented: $reckoning) {
                ReckoningScreen(onClose: {
                    reckonedOn = store.today
                    reckoning = false
                })
            }
    }

    @ViewBuilder
    private var screen: some View {
        switch tab {
        case .today: TodayScreen()
        case .ledger: LedgerScreen()
        case .report: ReportScreen()
        case .wants: WantsScreen()
        case .settings: SettingsScreen()
        }
    }

    /// Logging a purchase is a plausible next action from today and from the
    /// ledger, and from nowhere else — on 报告, 待购 or 设置 the button is only
    /// ink sitting over a figure.
    private var showsCapture: Bool { tab == .today || tab == .ledger }

    /// The button is drawn over the content, so the content is given back the
    /// height it covers. Without this the last row of a list can never be
    /// scrolled clear of it, and in a ledger an obscured figure is a fault
    /// rather than a cosmetic detail.
    @ViewBuilder
    private var captureClearance: some View {
        if showsCapture {
            Color.clear.frame(height: Space.s9 + Space.s2 + Space.s4 * 2)
        }
    }

    @ViewBuilder
    private var captureButton: some View {
        if showsCapture {
            Button { capturing = true } label: {
                Text(S.t(.captureMark))
                    .font(TypeScale.row.font)
                    .foregroundStyle(Ink.accentOn)
                    .frame(width: Space.s9 + Space.s2, height: Space.s9 + Space.s2)
                    .background(Ink.accentInk, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(S.t(.captureTitle))
            .padding(.trailing, Layout.gutter)
            .padding(.bottom, Space.s4)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let state = store.toastState {
            ToastBar(state: state)
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, Space.s4 + (showsCapture ? Space.s9 + Space.s2 + Space.s2 : 0))
                .transition(.opacity)
                .id(state.id)
        }
    }

    private func boot() async {
        await store.start()
        sync.bind(events: { store.events }, absorb: { store.absorb($0) })
        store.onLocalWrite = { sync.noteLocalWrite() }
        sync.start()
        offerReckoning()
        // A sheet presents on a change of state, not on a state it was born
        // with, so the screenshot flag is applied a frame after the shell exists.
        if Tab.launchCapturing {
            try? await Task.sleep(for: .milliseconds(500))
            capturing = true
        }
        #if DEBUG
        // `-showToast 1`: a save receipt with 撤销, to look at where it lands.
        if UserDefaults.standard.bool(forKey: "showToast") {
            store.toast(S.t(.captureSaved), action: ToastAction(label: S.t(.ledgerUndo)) {})
        }
        #endif
    }

    /// Offered, never forced: it appears on its day and can be dismissed.
    private func offerReckoning() {
        guard store.ready, !reckoning, reckonedOn != store.today else { return }
        let settings = store.ledger.settings
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: store.now) - 1
        let hour = calendar.component(.hour, from: store.now)
        guard weekday == settings.reckoningWeekday, hour >= settings.reckoningHour else { return }
        guard !reckoningQueue(store.ledger, store.today).isEmpty else { return }
        reckoning = true
    }
}

/// Five words, no icons — the design forbids both SF Symbols and `TabView`'s
/// system material here, so the bar is built by hand.
private struct TabBar: View {
    @Environment(Store.self) private var store
    @Binding var tab: Tab
    @Namespace private var rule

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { item in
                cell(item)
            }
        }
        .background(alignment: .top) {
            Ink.ruleStrong.frame(height: Layout.hairlineWidth)
        }
        .background(Ink.surface)
    }

    private func cell(_ item: Tab) -> some View {
        let active = tab == item
        return Button {
            withAnimation(Motion.ease(Motion.stampSlide)) { tab = item }
        } label: {
            // The mark above the word takes the word's ink, a step lighter when
            // the word is at rest, so it says nothing the word does not.
            VStack(spacing: Space.s1) {
                Glyph(name: item.glyph, size: 20)
                    .foregroundStyle(active ? Ink.indigo : alerting(item) ? Ink.ink900 : Ink.ink300)
                Text(S.t(item.label))
                    .font(.system(size: TypeScale.labelCJK.size, weight: active || alerting(item) ? .semibold : .medium))
                    .kerning(TypeScale.labelCJK.kerning)
                    .foregroundStyle(active ? Ink.indigo : alerting(item) ? Ink.ink900 : Ink.ink500)
            }
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s3)
                .overlay(alignment: .top) {
                    if active {
                        Ink.indigo
                            .frame(height: Layout.hairline * 2)
                            .matchedGeometryEffect(id: "tab.rule", in: rule)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Space.s9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    /// The only notification affordance in the product: a pending 周日审判 gives
    /// the 报告 word full ink while it is still unselected. No badge, no dot.
    private func alerting(_ item: Tab) -> Bool {
        item == .report && !reckoningQueue(store.ledger, store.today).isEmpty
    }
}

private struct ToastBar: View {
    @Environment(Store.self) private var store
    let state: ToastState

    /// Long enough to read one line and reach for 撤销, short enough to leave.
    private let dwell = Duration.seconds(4)

    var body: some View {
        HStack(spacing: Space.s4) {
            Text(state.message)
                .font(TypeScale.body.font)
                .foregroundStyle(Ink.paper)
            Spacer(minLength: 0)
            if let action = state.action {
                Button {
                    action.run()
                    store.dismissToast()
                } label: {
                    Text(action.label)
                        .font(.system(size: TypeScale.body.size, weight: .semibold))
                        .foregroundStyle(Ink.paper)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Layout.hitTarget)
        .background(Ink.ink900, in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityAddTraits(.updatesFrequently)
        .onTapGesture { store.dismissToast() }
        .gesture(
            DragGesture(minimumDistance: Space.s6)
                .onEnded { if $0.translation.height > 0 { store.dismissToast() } }
        )
        // Four seconds whether or not it carries 撤销 (DESIGN.md §5.12): what it
        // offers is always still reachable from the ledger's own history.
        .task(id: state.id) {
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.ease(Motion.rowFade)) { store.dismissToast() }
        }
    }
}
