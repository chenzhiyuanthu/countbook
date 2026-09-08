import SwiftUI

@main
struct CountbookApp: App {
    @State private var store = Store()
    @State private var sync = SyncEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
                // The theme is a ledger setting, not a system preference, so it
                // is applied above every screen and every sheet.
                .preferredColorScheme(scheme(store.ledger.settings.theme))
                .tint(Ink.accentInk)
        }
    }

    private func scheme(_ theme: Settings.Theme) -> ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
