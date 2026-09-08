import Foundation

/// The vault is the encrypted form of the event log, shaped so that syncing is
/// incremental and a conflict is small.
///
/// The log is sharded by the calendar month an event was created in. A device
/// only fetches shards whose version token has changed, and only rewrites the
/// shards it has new events for — so a year of history costs one small write a
/// day, and two devices editing different months never contend at all.
///
///     vault/manifest.json          plaintext: KDF parameters and key fingerprint
///     vault/s/2026-09.cbk          base64 of one AES-256-GCM envelope

let manifestPath = "vault/manifest.json"

func shardPath(_ month: String) -> String { "vault/s/\(month).cbk" }

func monthFromShardPath(_ p: String) -> String? {
    guard p.hasPrefix("vault/s/"), p.hasSuffix(".cbk") else { return nil }
    let month = String(p.dropFirst("vault/s/".count).dropLast(".cbk".count))
    guard month.count == 7, month[month.index(month.startIndex, offsetBy: 4)] == "-" else { return nil }
    return month.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }) ? month : nil
}

struct Manifest: Codable, Equatable, Sendable {
    struct Kdf: Codable, Equatable, Sendable {
        var name: String
        var iterations: Int
        var salt: String
    }

    var v: Int
    var kdf: Kdf
    /// Hex of SHA-256(key)[0..8). Lets a device reject a wrong passphrase before downloading anything.
    var fingerprint: String
    var updatedAt: Int
    var app: String
}

/// The month an event belongs to, taken from its HLC's wall time.
func shardOf(_ e: Event) -> String {
    let ms = decode(e.hlc).wall
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = calendar.dateComponents(
        [.year, .month],
        from: Date(timeIntervalSince1970: Double(ms) / 1000)
    )
    return String(format: "%04d-%02d", parts.year ?? 1970, parts.month ?? 1)
}

func groupByShard(_ events: [Event]) -> [String: [Event]] {
    var out: [String: [Event]] = [:]
    for e in events { out[shardOf(e), default: []].append(e) }
    return out
}

func encodeShard(_ vk: VaultKey, _ events: [Event]) throws -> String {
    toBase64(try seal(vk, String(decoding: try JSONEncoder().encode(events), as: UTF8.self)))
}

func decodeShard(_ vk: VaultKey, _ body: String) throws -> [Event] {
    guard let envelope = fromBase64(body) else { throw CryptoError("shard is not base64", .corrupt) }
    let json = Data(try open(vk, envelope).utf8)
    guard (try? JSONSerialization.jsonObject(with: json)) is [Any] else { return [] }
    return try JSONDecoder().decode([Event].self, from: json)
}

/// What this device believes about the remote, persisted between syncs.
///
/// `shas` is the remote blob version of each shard as of the last successful
/// sync. `digests` is what *we* held in that shard at the same moment. Both are
/// needed: the sha alone says whether the remote moved, and only the digest says
/// whether we have anything new to send — without it a device cannot tell
/// "already in sync" from "my local copy was cleared".
struct Cursor: Codable, Equatable, Sendable {
    var shas: [String: String]
    var digests: [String: String]

    init(shas: [String: String] = [:], digests: [String: String] = [:]) {
        self.shas = shas
        self.digests = digests
    }
}

func emptyCursor() -> Cursor { Cursor() }

/// Order-independent summary of which events we hold for one shard.
func digestOf(_ events: [Event]) -> String {
    let ids = events.map(\.id).sorted()
    var h: Int32 = 0
    for id in ids {
        // UTF-16 units and 32-bit wraparound, so the two clients agree on a
        // digest they both write into the same cursor file.
        for unit in id.utf16 { h = h &* 31 &+ Int32(unit) }
    }
    return "\(ids.count):\(String(UInt32(bitPattern: h), radix: 36))"
}

struct SyncOutcome: Sendable {
    var merged: [Event]
    var cursor: Cursor
    var pulled: Int
    var pushed: Int
}

/// A store the sync engine can drive. Both transports implement it: a private
/// GitHub repository, and a self-hosted server. Keeping the CAS loop in one
/// place is what makes the two interchangeable — a device can move from one to
/// the other and the merge is still the same merge.
protocol VaultStore: Sendable {
    var kind: VaultStoreKind { get }
    func describe() -> String
    func readManifest() async throws -> Manifest?
    func writeManifest(_ m: Manifest) async throws
    /// Shard path -> remote version token, for everything under vault/s/.
    func listShards() async throws -> [String: String]
    func readShard(_ month: String) async throws -> String
    /// Returns the new token. Throws ConflictError if `expected` is stale.
    func writeShard(_ month: String, _ body: String, expected: String?) async throws -> String
}

enum VaultStoreKind: String, Codable, Sendable {
    case github, server
}

struct ConflictError: Error, LocalizedError {
    var errorDescription: String? { "shard changed underneath us" }
}

/// Pull what changed, merge, push what is ours.
///
/// The invariant that makes this safe: a shard is only ever written by a device
/// that holds everything already in it. Writing replaces the whole shard, so a
/// device that skipped the pull — because its cursor said it was current — and
/// then wrote from a partial local log would silently delete the other device's
/// entries. The cursor's sha can be stale (GitHub's tree endpoint is a replica
/// and lags a commit by a second or two), so being "current" is never taken on
/// trust before an overwrite: any shard about to be written is read first.
///
/// A conflicting write is not an error to report. It means another device wrote
/// first, so we take their version, union it with ours — union is idempotent, so
/// this converges — and try again.
func syncVault(
    _ store: some VaultStore,
    _ vk: VaultKey,
    _ local: [Event],
    _ cursor: Cursor,
    maxRetries: Int = 5
) async throws -> SyncOutcome {
    let remote = try await store.listShards()
    var held = Set<String>() // shards whose remote contents are merged in
    var merged = local
    var pulled = 0

    // Sorted rather than in map order: two devices that walk the same tree then
    // take the same path through it, which makes a failure reproducible.
    for path in remote.keys.sorted() {
        let sha = remote[path]!
        guard let month = monthFromShardPath(path), cursor.shas[path] != sha else { continue }
        let before = merged.count
        merged = merge(merged, try decodeShard(vk, try await store.readShard(month)))
        pulled += merged.count - before
        held.insert(path)
    }

    var next = Cursor(shas: cursor.shas.merging(remote) { _, new in new }, digests: cursor.digests)
    var pushed = 0

    for month in groupByShard(merged).keys.sorted() {
        let path = shardPath(month)
        let remoteSha = remote[path]
        let mine = groupByShard(merged)[month] ?? []

        // Neither side has moved since the last sync of this shard.
        if let remoteSha, cursor.shas[path] == remoteSha, cursor.digests[path] == digestOf(mine) {
            next.digests[path] = digestOf(mine)
            continue
        }

        if remoteSha != nil, !held.contains(path) {
            let before = merged.count
            merged = merge(merged, try decodeShard(vk, try await store.readShard(month)))
            pulled += merged.count - before
            held.insert(path)
        }

        var toWrite = groupByShard(merged)[month] ?? []
        // The extra read may have shown that they already had everything we hold.
        if let remoteSha, cursor.shas[path] == remoteSha, cursor.digests[path] == digestOf(toWrite) {
            next.digests[path] = digestOf(toWrite)
            continue
        }

        var expected = remoteSha
        var attempt = 0
        while true {
            do {
                next.shas[path] = try await store.writeShard(
                    month, try encodeShard(vk, toWrite), expected: expected
                )
                next.digests[path] = digestOf(toWrite)
                pushed += toWrite.count
                break
            } catch is ConflictError where attempt < maxRetries {
                attempt += 1
                let fresh = try await store.listShards()
                expected = fresh[path]
                if expected != nil {
                    merged = merge(merged, try decodeShard(vk, try await store.readShard(month)))
                }
                toWrite = groupByShard(merged)[month] ?? toWrite
            }
        }
    }

    return SyncOutcome(merged: merged, cursor: next, pulled: pulled, pushed: pushed)
}
