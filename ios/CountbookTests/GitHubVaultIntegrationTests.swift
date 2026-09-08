import XCTest
@testable import Countbook

/// Drives the real GitHub API against a real private repository, from Swift.
///
/// The unit tests prove the envelope and the merge in isolation; only this
/// proves the thing the product actually promises — that a ledger written by
/// the phone is readable by the web client and the reverse — because both
/// clients here are talking to the same repository with the same key.
///
/// Skipped unless credentials are present, so the normal test run stays offline
/// and fast. Supply them by writing `.integration.json` at the repository root
/// (it is gitignored):
///
///   { "token": "…", "repo": "owner/repo" }
///
/// A file rather than the environment because `xcodebuild`'s `TEST_RUNNER_`
/// passthrough does not reach a bundle hosted inside the app, and a token on
/// the command line ends up in the shell history.
final class GitHubVaultIntegrationTests: XCTestCase {
    private var cfg: GitHubConfig?

    private struct Credentials: Decodable {
        let token: String
        let repo: String
    }

    override func setUp() {
        super.setUp()
        // #filePath is this file inside the checkout, so the repository root is
        // two directories up — the test bundle itself has no idea where it came
        // from.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent(".integration.json")),
              let creds = try? JSONDecoder().decode(Credentials.self, from: data),
              creds.repo.contains("/")
        else { return }
        let parts = creds.repo.split(separator: "/", maxSplits: 1)
        cfg = GitHubConfig(owner: String(parts[0]), repo: String(parts[1]), branch: "main", token: creds.token)
    }

    private func requireConfig() throws -> GitHubConfig {
        try XCTSkipIf(cfg == nil, "write .integration.json at the repository root to run")
        return cfg!
    }

    /// The same passphrase and salt the web integration test uses, so both
    /// clients derive the same key and read each other's shards.
    private func vaultKey() throws -> VaultKey {
        try deriveKeyBlocking(
            "integration-test-passphrase",
            salt: Data(repeating: 3, count: 16),
            iterations: 1000
        )
    }

    private func event(_ id: String, wall: Int, device: String, note: String) -> Event {
        let hlc = String(format: "%016lx-0000-%@", wall, device)
        return Event(
            id: id,
            hlc: hlc,
            dev: device,
            payload: .entryAdd(entry: Entry(
                id: "entry-\(id)",
                kind: .spend,
                amount: 12_640,
                currency: "CNY",
                categoryId: "food",
                intent: .want,
                note: note,
                merchant: "测试",
                day: "2026-09-08",
                createdAt: wall
            ))
        )
    }

    func testReportsWhatTheTokenCanDo() async throws {
        let store = GitHubStore(try requireConfig())
        let check = await store.verify()
        guard case .ok = check else { return XCTFail("token cannot write: \(check)") }
    }

    func testRoundTripsAShardTheWebClientCanAlsoRead() async throws {
        let cfg = try requireConfig()
        let key = try vaultKey()
        let wall = Int(Date().timeIntervalSince1970 * 1000)
        let mine = event("swift-\(wall)", wall: wall, device: "swift001", note: "from Swift")

        let out = try await syncVault(GitHubStore(cfg), key, [mine], emptyCursor())
        XCTAssertGreaterThanOrEqual(out.pushed, 1)

        // A fresh store with an empty cursor is exactly a second device seeing
        // this vault for the first time.
        let second = try await syncVault(GitHubStore(cfg), key, [], emptyCursor())
        XCTAssertTrue(second.merged.contains { $0.id == mine.id }, "the shard did not come back")
    }

    func testConvergesWhenTwoDevicesWriteTheSameMonthAtOnce() async throws {
        let cfg = try requireConfig()
        let key = try vaultKey()
        let wall = Int(Date().timeIntervalSince1970 * 1000)

        // Both read the same starting state, then both write. The second write's
        // compare-and-swap must fail and be retried against the winner.
        let cursorA = Cursor(shas: try await GitHubStore(cfg).listShards(), digests: [:])
        let cursorB = Cursor(shas: try await GitHubStore(cfg).listShards(), digests: [:])

        _ = try await syncVault(GitHubStore(cfg), key, [event("sa-\(wall)", wall: wall, device: "swifta01", note: "A")], cursorA)
        let outB = try await syncVault(GitHubStore(cfg), key, [event("sb-\(wall)", wall: wall + 1, device: "swiftb01", note: "B")], cursorB)

        let ids = Set(outB.merged.map(\.id))
        XCTAssertTrue(ids.contains("sa-\(wall)"), "A's event was lost")
        XCTAssertTrue(ids.contains("sb-\(wall)"), "B's event was lost")
    }

    /// The point of the whole exercise: an event the web client wrote decrypts
    /// here, in Swift, out of the same repository.
    func testReadsAnEventWrittenByTheWebClient() async throws {
        let cfg = try requireConfig()
        let key = try vaultKey()
        let out = try await syncVault(GitHubStore(cfg), key, [], emptyCursor())

        let fromWeb = out.merged.filter { $0.dev == "aaaa" || $0.dev == "bbbb" }
        try XCTSkipIf(fromWeb.isEmpty, "run the web integration test first to seed a web-written event")

        // Decrypting is not enough: the payload must decode into the same
        // domain object, or the two clients agree on bytes and disagree on
        // meaning, which is worse than failing outright.
        guard case .entryAdd(let entry) = fromWeb[0].payload else {
            return XCTFail("web event did not decode as entry.add: \(fromWeb[0].payload)")
        }
        XCTAssertEqual(entry.amount, 12_640)
        XCTAssertEqual(entry.categoryId, "food")
        XCTAssertEqual(entry.intent, .want)
        XCTAssertEqual(entry.currency, "CNY")
    }
}
