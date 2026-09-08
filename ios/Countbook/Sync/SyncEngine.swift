import Foundation
import Network
import Observation
import UIKit

/// The sync state machine. Sync is always an enhancement: the app is fully
/// usable with it off, every write lands locally first, and a failure is a line
/// of status text rather than a blocked screen.

enum SyncPhase: String, Sendable {
    case off, locked, idle, syncing, offline, error
}

enum SyncConfig: Codable, Equatable, Sendable {
    case github(GitHubConfig)
    case server(ServerConfig, email: String)

    var kind: VaultStoreKind {
        switch self {
        case .github: return .github
        case .server: return .server
        }
    }

    var describe: String {
        switch self {
        case .github(let cfg): return "\(cfg.owner)/\(cfg.repo)"
        case .server(let cfg, let email): return "\(email) · \(cfg.baseUrl)"
        }
    }

    // Flat on the wire, with a `kind` discriminator, so a config written by
    // either client reads on the other.
    private enum CodingKeys: String, CodingKey {
        case kind, owner, repo, branch, token, baseUrl, email
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(VaultStoreKind.self, forKey: .kind) {
        case .github:
            self = .github(GitHubConfig(
                owner: try c.decode(String.self, forKey: .owner),
                repo: try c.decode(String.self, forKey: .repo),
                branch: try c.decode(String.self, forKey: .branch),
                token: try c.decode(String.self, forKey: .token)
            ))
        case .server:
            self = .server(
                ServerConfig(
                    baseUrl: try c.decode(String.self, forKey: .baseUrl),
                    token: try c.decode(String.self, forKey: .token)
                ),
                email: try c.decode(String.self, forKey: .email)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .github(let cfg):
            try c.encode(cfg.owner, forKey: .owner)
            try c.encode(cfg.repo, forKey: .repo)
            try c.encode(cfg.branch, forKey: .branch)
            try c.encode(cfg.token, forKey: .token)
        case .server(let cfg, let email):
            try c.encode(cfg.baseUrl, forKey: .baseUrl)
            try c.encode(cfg.token, forKey: .token)
            try c.encode(email, forKey: .email)
        }
    }
}

/// The remembered key, so a relaunch does not ask for the passphrase again.
private struct RememberedKey: Codable {
    var raw: String
    var salt: String
    var iterations: Int
    var fingerprint: String
}

@MainActor
@Observable
final class SyncEngine {
    private(set) var phase: SyncPhase = .off
    private(set) var config: SyncConfig?
    private(set) var message = ""
    private(set) var lastSyncedAt: Int?

    var fingerprint: String? { key.map { formatFingerprint($0.fingerprint) } }
    var describe: String? { config?.describe }

    @ObservationIgnored private var key: VaultKey?
    @ObservationIgnored private var readEvents: () -> [Event] = { [] }
    @ObservationIgnored private var absorb: ([Event]) -> Void = { _ in }
    @ObservationIgnored private var running = false
    @ObservationIgnored private var queued = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var online = true
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let defaults: UserDefaults

    private let configKey = "countbook.sync"
    private let cursorKey = "countbook.cursor"
    private let lastKey = "countbook.lastSync"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        config = decode(SyncConfig.self, defaults.data(forKey: configKey))
        lastSyncedAt = defaults.object(forKey: lastKey) as? Int
    }

    /// The event log is owned by the store; sync reads it through a closure so a
    /// re-render never restarts an in-flight sync.
    func bind(events: @escaping () -> [Event], absorb: @escaping ([Event]) -> Void) {
        readEvents = events
        self.absorb = absorb
    }

    // MARK: - triggers

    func start() {
        guard !started else { return }
        started = true
        restoreKey()
        watchForeground()
        watchNetwork()
        watchClock()
        trigger()
    }

    /// Called after a local write. Debounced, so a burst of edits produces one
    /// sync rather than one per keystroke.
    func noteLocalWrite() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.trigger()
        }
    }

    func syncNow() async {
        guard let config, let key else { return }
        await run(config, key)
    }

    private func trigger() {
        Task { await syncNow() }
    }

    private func watchForeground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trigger() }
        }
    }

    /// A phone loses and regains the network constantly; a sync that failed
    /// while the tunnel was down should recover on its own the moment it is back.
    private func watchNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let returned = up && !self.online
                self.online = up
                if returned { self.trigger() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "countbook.sync.path"))
        self.monitor = monitor
    }

    private func watchClock() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                self?.trigger()
            }
        }
    }

    // MARK: - the sync run

    private func run(_ cfg: SyncConfig, _ vk: VaultKey) async {
        if running {
            queued = true
            return
        }
        running = true
        repeat {
            queued = false
            await once(cfg, vk)
        } while queued
        running = false
    }

    private func once(_ cfg: SyncConfig, _ vk: VaultKey) async {
        phase = .syncing
        do {
            let merged: [Event]
            switch cfg {
            case .github(let github):
                let out = try await syncVault(
                    GitHubStore(github), vk, readEvents(),
                    decode(Cursor.self, defaults.data(forKey: cursorKey)) ?? emptyCursor()
                )
                store(out.cursor, at: cursorKey)
                merged = out.merged
            case .server(let server, _):
                let out = try await ServerStore.syncServer(
                    server, vk, readEvents(),
                    decode(ServerCursor.self, defaults.data(forKey: cursorKey)) ?? ServerCursor()
                )
                store(out.cursor, at: cursorKey)
                merged = out.merged
            }
            absorb(merged)
            let at = nowMillis()
            lastSyncedAt = at
            defaults.set(at, forKey: lastKey)
            message = ""
            phase = .idle
        } catch {
            message = error.localizedDescription
            // A dead network is a normal state on a phone, not a failure worth
            // colouring red.
            phase = isOffline(error) ? .offline : .error
        }
    }

    private func isOffline(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let e = error as? ServerError { return e.kind == .network }
        return !online
    }

    // MARK: - connecting

    /// Establish the key against the vault's manifest. A vault that already exists
    /// dictates the salt and iteration count, so a second device deriving from the
    /// same passphrase lands on the same key; a fingerprint mismatch means the
    /// passphrase is wrong and is reported as such before anything is written.
    private func establish(
        _ passphrase: String,
        read: () async throws -> Manifest?,
        write: (Manifest) async throws -> Void
    ) async throws -> VaultKey {
        if let existing = try await read() {
            guard let salt = fromBase64(existing.kdf.salt) else {
                throw CryptoError("manifest salt is not base64", .corrupt)
            }
            let vk = try await deriveKey(passphrase, salt: salt, iterations: existing.kdf.iterations)
            guard vk.fingerprint == existing.fingerprint else {
                throw CryptoError("口令打不开这个仓库 · That passphrase does not open this vault", .wrongPassphrase)
            }
            return vk
        }
        let vk = try await deriveKey(passphrase)
        try await write(Manifest(
            v: 1,
            kdf: Manifest.Kdf(name: "PBKDF2-SHA256", iterations: vk.iterations, salt: toBase64(vk.salt)),
            fingerprint: vk.fingerprint,
            updatedAt: nowMillis(),
            app: "countbook/1.0"
        ))
        return vk
    }

    func connectGitHub(_ cfg: GitHubConfig, passphrase: String, remember keep: Bool) async throws {
        phase = .syncing
        message = ""
        do {
            let store = GitHubStore(cfg)
            if case .bad(let error) = await store.verify() {
                throw GitHubError(error, 0, .auth)
            }
            _ = try await store.listShards() // primes the SHA table the manifest write needs
            let vk = try await establish(
                passphrase,
                read: { try await store.readManifest() },
                write: { try await store.writeManifest($0) }
            )
            adopt(.github(cfg), vk, remember: keep)
            await syncNow()
        } catch {
            message = error.localizedDescription
            phase = .error
            throw error
        }
    }

    func connectServer(
        _ cfg: ServerConfig, email: String, passphrase: String, remember keep: Bool
    ) async throws {
        phase = .syncing
        message = ""
        do {
            let vk = try await establish(
                passphrase,
                read: { try await ServerStore.readManifest(cfg) },
                write: { try await ServerStore.writeManifest(cfg, $0) }
            )
            adopt(.server(cfg, email: email), vk, remember: keep)
            await syncNow()
        } catch {
            message = error.localizedDescription
            phase = .error
            throw error
        }
    }

    func unlock(passphrase: String) async throws {
        guard let config else { return }
        let manifest: Manifest?
        switch config {
        case .github(let cfg): manifest = try await GitHubStore(cfg).readManifest()
        case .server(let cfg, _): manifest = try await ServerStore.readManifest(cfg)
        }
        guard let manifest else { throw CryptoError("这个仓库还没有初始化", .corrupt) }
        guard let salt = fromBase64(manifest.kdf.salt) else {
            throw CryptoError("manifest salt is not base64", .corrupt)
        }
        let vk = try await deriveKey(passphrase, salt: salt, iterations: manifest.kdf.iterations)
        guard vk.fingerprint == manifest.fingerprint else {
            throw CryptoError("口令打不开这个仓库", .wrongPassphrase)
        }
        remember(vk)
        key = vk
        phase = .idle
        await run(config, vk)
    }

    func disconnect() {
        defaults.removeObject(forKey: configKey)
        defaults.removeObject(forKey: cursorKey)
        defaults.removeObject(forKey: lastKey)
        KeyStash.clear()
        config = nil
        key = nil
        lastSyncedAt = nil
        phase = .off
        message = ""
    }

    private func adopt(_ next: SyncConfig, _ vk: VaultKey, remember keep: Bool) {
        store(next, at: configKey)
        defaults.removeObject(forKey: cursorKey)
        if keep { remember(vk) }
        config = next
        key = vk
    }

    // MARK: - key material

    /// The key lives in the Keychain, never in UserDefaults: it is the one
    /// secret whose loss reads the whole ledger, and only the Keychain keeps it
    /// out of a device backup and behind the device passcode.
    private func remember(_ vk: VaultKey) {
        let remembered = RememberedKey(
            raw: toBase64(vk.raw),
            salt: toBase64(vk.salt),
            iterations: vk.iterations,
            fingerprint: vk.fingerprint
        )
        if let data = try? JSONEncoder().encode(remembered) { KeyStash.save(data) }
    }

    private func restoreKey() {
        guard config != nil else {
            phase = .off
            return
        }
        guard let data = KeyStash.load(),
              let remembered = try? JSONDecoder().decode(RememberedKey.self, from: data),
              let raw = fromBase64(remembered.raw),
              let salt = fromBase64(remembered.salt),
              let vk = try? importKeyMaterial(raw, salt: salt, iterations: remembered.iterations)
        else {
            phase = .locked
            return
        }
        key = vk
        phase = .idle
    }

    // MARK: - small storage helpers

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func store(_ value: some Encodable, at key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    static var deviceLabel: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}

private enum KeyStash {
    private static let service = "com.czy.countbook.vault"
    private static let account = "countbook.key"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ data: Data) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        // Available to a background sync after the first unlock, but never in an
        // iCloud backup and never on another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> Data? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
