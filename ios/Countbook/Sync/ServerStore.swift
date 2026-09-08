import Foundation

/// Sync must always see the server's present state, never a cached copy of it;
/// see the note in GitHubStore.
let uncachedSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    return URLSession(configuration: config)
}()

/// Adapter B — a self-hosted sync server.
///
/// Unlike the GitHub vault this needs no compare-and-swap: the server is an
/// append-only relay keyed by the client-generated event id, so two devices
/// writing at once simply both succeed and a retry after a dropped response
/// inserts nothing twice. Each event body is sealed individually, so the server
/// stores ciphertext and operating it grants no ability to read the ledger.

struct ServerConfig: Codable, Equatable, Sendable {
    var baseUrl: String
    var token: String
}

struct ServerCursor: Codable, Equatable, Sendable {
    var cursor: Int

    init(cursor: Int = 0) { self.cursor = cursor }
}

struct ServerError: Error, LocalizedError {
    enum Kind: String, Sendable {
        case auth, network, other
    }

    let message: String
    let status: Int
    let kind: Kind

    var errorDescription: String? { message }

    init(_ message: String, _ status: Int, _ kind: Kind) {
        self.message = message
        self.status = status
        self.kind = kind
    }
}

struct ServerSession: Decodable, Sendable {
    let token: String
    let expiresAt: Int
    let userId: String
}

struct DeviceRow: Decodable, Identifiable, Sendable {
    let ref: String
    let device: String
    let label: String
    let createdAt: Int
    let seenAt: Int
    let current: Bool

    var id: String { ref }
}

private struct ServerFailure: Decodable {
    let error: String?
}

enum ServerStore {
    private static let pageSize = 500

    /// The server stores the manifest as a normal event so the KDF parameters
    /// travel with the log. It is the one event whose body is plaintext — it has
    /// to be readable before a key exists.
    private static let manifestEventID = "manifest"

    private static func trim(_ u: String) -> String {
        var s = u
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private static func call<T: Decodable>(
        _ cfg: ServerConfig,
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        session: URLSession = .shared
    ) async throws -> T {
        guard let url = URL(string: trim(cfg.baseUrl) + path) else {
            throw ServerError("地址不对", 0, .other)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "accept")
        // A bearer token, never a cookie: the app is not a browser and must not
        // carry ambient credentials that a cross-site request could ride on.
        if !cfg.token.isEmpty {
            req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "authorization")
        }
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "content-type") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ServerError(error.localizedDescription, 0, .network)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ServerError("连接失败", 0, .network)
        }
        if http.statusCode == 401 { throw ServerError("登录已过期，请重新登录", 401, .auth) }
        if !(200..<300).contains(http.statusCode) {
            let detail = (try? JSONDecoder().decode(ServerFailure.self, from: data))?.error
            throw ServerError(detail ?? "服务器返回 \(http.statusCode)", http.statusCode, .other)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    static func login(
        baseUrl: String, email: String, password: String, device: String, label: String
    ) async throws -> ServerSession {
        try await call(
            ServerConfig(baseUrl: baseUrl, token: ""),
            "/api/login",
            method: "POST",
            body: try json(["email": email, "password": password, "device": device, "label": label])
        )
    }

    static func signup(
        baseUrl: String, email: String, password: String, code: String, device: String, label: String
    ) async throws -> ServerSession {
        try await call(
            ServerConfig(baseUrl: baseUrl, token: ""),
            "/api/signup",
            method: "POST",
            body: try json([
                "email": email, "password": password, "code": code, "device": device, "label": label,
            ])
        )
    }

    static func listDevices(_ cfg: ServerConfig) async throws -> [DeviceRow] {
        struct Page: Decodable { let devices: [DeviceRow] }
        let page: Page = try await call(cfg, "/api/devices")
        return page.devices
    }

    static func revokeDevice(_ cfg: ServerConfig, ref: String) async throws {
        struct Ack: Decodable { let ok: Bool? }
        let _: Ack = try await call(
            cfg, "/api/devices/revoke", method: "POST", body: try json(["ref": ref])
        )
    }

    private struct PullPage: Decodable {
        struct Row: Decodable {
            let id: String
            let hlc: String?
            let body: String
        }

        let events: [Row]
        let cursor: Int
        let hasMore: Bool?
    }

    static func syncServer(
        _ cfg: ServerConfig,
        _ vk: VaultKey,
        _ local: [Event],
        _ cursor: ServerCursor
    ) async throws -> (merged: [Event], cursor: ServerCursor, pulled: Int, pushed: Int) {
        var at = cursor.cursor
        var merged = local
        var pulled = 0

        while true {
            let page: PullPage = try await call(cfg, "/api/pull?since=\(at)&limit=\(pageSize)")
            var decoded: [Event] = []
            for row in page.events where row.id != manifestEventID {
                guard let envelope = fromBase64(row.body),
                      let plain = try? open(vk, envelope),
                      let event = try? JSONDecoder().decode(Event.self, from: Data(plain.utf8))
                else {
                    // One unreadable row must not stop the sync: it is far more likely to be
                    // an event written under a different passphrase than a real corruption,
                    // and the rest of the log is still perfectly usable.
                    continue
                }
                decoded.append(event)
            }
            pulled += decoded.count
            merged = merge(merged, decoded)
            at = page.cursor
            if page.hasMore != true { break }
        }

        // Push everything we hold; the server discards ids it already has, so there
        // is no need to track which of ours it has seen.
        let encoder = JSONEncoder()
        let payload: [[String: Any]] = try merged.map { e in
            [
                "id": e.id,
                "hlc": e.hlc,
                "body": toBase64(try seal(vk, String(decoding: try encoder.encode(e), as: UTF8.self))),
            ]
        }

        struct Ack: Decodable { let accepted: Int; let cursor: Int }
        var pushed = 0
        for start in stride(from: 0, to: payload.count, by: pageSize) {
            let slice = Array(payload[start..<min(start + pageSize, payload.count)])
            let ack: Ack = try await call(
                cfg, "/api/push", method: "POST", body: try json(["events": slice])
            )
            pushed += ack.accepted
            at = max(at, ack.cursor)
        }

        return (merged, ServerCursor(cursor: at), pulled, pushed)
    }

    static func readManifest(_ cfg: ServerConfig) async throws -> Manifest? {
        let page: PullPage = try await call(cfg, "/api/pull?since=0&limit=1")
        guard let row = page.events.first(where: { $0.id == manifestEventID }),
              let plain = Data(base64Encoded: row.body)
        else { return nil }
        return try JSONDecoder().decode(Manifest.self, from: plain)
    }

    static func writeManifest(_ cfg: ServerConfig, _ m: Manifest) async throws {
        struct Ack: Decodable { let accepted: Int? }
        let body = try JSONEncoder().encode(m).base64EncodedString()
        let _: Ack = try await call(
            cfg, "/api/push", method: "POST",
            body: try json([
                "events": [[
                    "id": manifestEventID,
                    "hlc": String(repeating: "0", count: 16) + "-0000-manifest",
                    "body": body,
                ]],
            ])
        )
    }
}
