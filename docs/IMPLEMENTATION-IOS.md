# 据实 · Countbook — implementation contract (iOS)

Read this before writing any Swift. `docs/DESIGN.md` is normative for anything
visual, `docs/SCREENS.md` for what is on each screen and what it says,
`docs/PRODUCT.md` for the rules and formulas, `docs/PROTOCOL.md` for the data
model and the wire format.

## Ground rules

- **SwiftUI, iOS 17+, zero third-party packages.** Foundation, SwiftUI,
  CryptoKit, CommonCrypto and Combine only. No SPM dependency, ever.
- **The web client is the reference implementation.** `web/src/core/*.ts` and
  `web/src/sync/*.ts` already exist, are tested, and define the semantics. Port
  them faithfully: same names, same rules, same edge cases. Where Swift wants a
  different idiom, keep the behaviour identical and let the shape change.
- **`design/fixtures/money.json` is a shared acceptance test.** The Swift
  implementation must produce byte-identical output for every vector in it. The
  parity test that asserts this is part of the deliverable.
- **No hard-coded colour, size, radius or duration.** `ios/Countbook/Design/Tokens.swift`
  is generated from `design/tokens.json` and gives you `Ink`, `Space`, `Radius`,
  `TypeScale`, `Motion`, `Layout`, `Elevation`, `Rules`. Never edit it by hand;
  if a token is missing, use the nearest one.
- **Chinese first.** Every user-facing string goes through `S.t(.key)` from
  `Strings.swift`, mirroring `web/src/app/i18n.ts` key for key.
- **The clerk's voice.** State the fact. No praise, no scolding, no exclamation
  marks, no emoji, no SF Symbols used decoratively.
- Comments explain why, never what.
- Money is `Fen` — an `Int` count of 分. A `Double` must never touch an amount.
- Dates in the ledger are `Day` — a `String` of `"yyyy-MM-dd"` in the user's own
  timezone. A purchase at 23:40 belongs to that local day.

## Verifying

Run `scripts/ios-check.sh` (build) or `scripts/ios-check.sh test`. It takes a
lock, regenerates the Xcode project from `ios/project.yml` and builds for the
simulator, so it is safe to run while other agents are working. It must pass
before you finish. Files are picked up automatically by the glob in
`project.yml` — never edit the `.xcodeproj`.

## Layout

```
ios/Countbook/
  App/          CountbookApp.swift, Store.swift, Strings.swift, RootView.swift
  Core/         Money, DayDate, HLC, Types, Events, Fold, Compute
  Sync/         Crypto, Vault, GitHubStore, ServerStore, SyncEngine
  Design/       Tokens.swift (generated), Theme.swift, MoneyView.swift, Primitives.swift, Charts.swift
  Features/     Today, Capture, Ledger, Report, Wants, Reckoning, SettingsScreen
  Resources/    Info.plist, Assets.xcassets
ios/CountbookTests/
```

## Store contract

`Store` is an `@Observable` (or `ObservableObject`) singleton injected through
the environment, mirroring `web/src/app/store.tsx`:

```swift
@MainActor final class Store {
    private(set) var ledger: Ledger        // the fold; the only thing views read
    private(set) var events: [Event]
    var today: Day                          // refreshed on a timer and on foreground
    var now: Date
    @discardableResult func commit(_ payload: Payload) -> String
    func absorb(_ incoming: [Event])
    func undo(eventID: String)
    func replaceAll(_ events: [Event])
    func toast(_ message: String, action: ToastAction?)
}
```

Persistence is a single JSON file in Application Support, written atomically
off the main actor. Never mutate `ledger`; always `commit` an event.

## Sync contract

Both adapters from `docs/PROTOCOL.md` must interoperate with the web client
byte for byte:

- The envelope is the layout in `web/src/sync/crypto.ts` — magic `CBK1`,
  version, KDF id, big-endian iteration count, 16-byte salt, 12-byte nonce, then
  AES-256-GCM ciphertext with the tag appended. The whole header is the AEAD's
  additional data.
- PBKDF2-HMAC-SHA256 via CommonCrypto (`CCKeyDerivationPBKDF`); CryptoKit has no
  PBKDF2. The passphrase is normalised with `precomposedStringWithCanonicalMapping`
  (NFKC) before derivation, so the same passphrase typed on either platform
  derives the same key.
- AES-GCM via CryptoKit's `AES.GCM`, with the nonce and AAD supplied explicitly.
- The GitHub adapter shards by month at `vault/s/<YYYY-MM>.cbk` and uses the blob
  SHA as a compare-and-swap token, exactly as the web client does.

A device that syncs from the phone must be readable on the web and the reverse;
if a change would break that, it is wrong.
