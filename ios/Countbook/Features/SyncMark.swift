import SwiftUI

/// One line, top trailing, on every screen: whether what was written here has
/// reached the server. It is the only place the app answers that question
/// without being asked, because a ledger that quietly stops syncing is a ledger
/// with two truths. The green is figSpared — the one colour the token set has
/// for "kept safe" — and it is the only time it is spent on anything but money.
/// With sync off the line is absent, not "off": sync is an enhancement.
///
/// Mirrors web/src/ui/SyncMark.tsx state for state.
struct SyncMark: View {
    @Environment(SyncEngine.self) private var sync
    let open: () -> Void

    private enum Tone { case ok, held, quiet, alert }
    private struct State { let tone: Tone; let text: String; let glyph: String? }

    private var state: State? {
        guard sync.phase != .off, sync.config != nil else { return nil }
        if sync.phase == .locked || sync.authExpired {
            return State(tone: .alert, text: S.t(.syncMarkRelogin), glyph: "exclamationmark")
        }
        switch sync.phase {
        case .syncing: return State(tone: .quiet, text: S.t(.syncSyncing), glyph: nil)
        case .offline: return State(tone: .quiet, text: S.t(.syncMarkOffline), glyph: nil)
        case .error: return State(tone: .alert, text: S.t(.syncMarkError), glyph: "exclamationmark")
        default: break
        }
        if sync.pending { return State(tone: .held, text: S.t(.syncMarkPending), glyph: nil) }
        return State(tone: .ok, text: S.t(.syncSynced), glyph: "checkmark")
    }

    var body: some View {
        if let state {
            HStack {
                Spacer(minLength: 0)
                Button(action: open) {
                    HStack(spacing: Space.s1) {
                        if let glyph = state.glyph {
                            Image(systemName: glyph)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ink(state.tone))
                        }
                        Text(state.text).textStyle(.label, ink: ink(state.tone))
                    }
                    .frame(minHeight: Space.s7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(state.text) · \(S.t(.syncMarkOpen))")
            }
            .padding(.horizontal, Layout.gutter)
            .background(Ink.paper)
            .animation(.default, value: state.text)
        }
    }

    private func ink(_ tone: Tone) -> Color {
        switch tone {
        case .ok: return Ink.figSpared
        case .held: return Ink.figHeld
        case .quiet: return Ink.ink500
        case .alert: return Ink.ink900
        }
    }
}

/// Pull to sync: forget the cursor and read the whole log again. Offered only
/// where there is a remote to read from, so a ledger kept on one device is
/// never given a spinner that spins for nothing.
struct SyncRefresh: ViewModifier {
    @Environment(SyncEngine.self) private var sync

    func body(content: Content) -> some View {
        if sync.config != nil {
            content.refreshable { await sync.resync() }
        } else {
            content
        }
    }
}

extension View {
    func syncRefresh() -> some View { modifier(SyncRefresh()) }
}
