import Foundation

/// Adapter A — a private GitHub repository as the vault.
///
/// This is the transport that works without any server at all, which is why it
/// is the default: nothing has to be hosted, and the phone talks to the REST
/// API directly with the token the user pasted.
///
/// Blob SHAs are the version tokens, and the Contents API's `sha` parameter is a
/// compare-and-swap: a stale SHA is rejected with 409, which is exactly the
/// conflict signal the sync engine retries on.
///
/// Reads go through the Git Data API rather than the Contents API because the
/// latter refuses to return a file over 1 MB as JSON, and a few years of ledger
/// will cross that.

private let gitHubAPI = "https://api.github.com"

struct GitHubConfig: Codable, Equatable, Sendable {
    var owner: String
    var repo: String
    var branch: String
    var token: String
}

struct GitHubError: Error, LocalizedError {
    enum Kind: String, Sendable {
        case auth, notFound, rateLimit, conflict, other
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

enum GitHubCheck: Sendable {
    case ok(detail: String)
    case bad(error: String)
}

actor GitHubStore: VaultStore {
    nonisolated let kind = VaultStoreKind.github
    private let cfg: GitHubConfig
    private let session: URLSession
    /// Blob SHAs from the last tree read, so a write knows what it is replacing.
    private var shas: [String: String] = [:]

    init(_ cfg: GitHubConfig, session: URLSession? = nil) {
        self.cfg = cfg
        self.session = session ?? Self.uncachedSession()
    }

    /// GitHub answers with `Cache-Control: private, max-age=60`, and
    /// `URLSession.shared` honours it — so a compare-and-swap retry would keep
    /// being handed the same stale blob sha out of the local cache for a minute
    /// and could never converge. Sync must always see the server's present
    /// state, so this transport keeps no cache at all.
    private static func uncachedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    nonisolated func describe() -> String { "\(cfg.owner)/\(cfg.repo)" }

    private var repoRoot: String { "/repos/\(cfg.owner)/\(cfg.repo)" }

    private func call(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        accept: String = "application/vnd.github+json"
    ) async throws -> Data {
        guard let url = URL(string: gitHubAPI + path) else {
            throw GitHubError("bad request path: \(path)", 0, .other)
        }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.httpMethod = method
        req.httpBody = body
        req.setValue(accept, forHTTPHeaderField: "accept")
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "authorization")
        req.setValue("2022-11-28", forHTTPHeaderField: "x-github-api-version")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "content-type") }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError("no response from GitHub", 0, .other)
        }
        if (200..<300).contains(http.statusCode) { return data }

        if http.statusCode == 401 || http.statusCode == 403 {
            if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                let reset = Double(http.value(forHTTPHeaderField: "x-ratelimit-reset") ?? "0") ?? 0
                let at = Date(timeIntervalSince1970: reset)
                    .formatted(date: .omitted, time: .shortened)
                throw GitHubError("GitHub rate limit reached; resets \(at)", http.statusCode, .rateLimit)
            }
            throw GitHubError(
                "token rejected — check it has Contents write access to this repository",
                http.statusCode, .auth
            )
        }
        if http.statusCode == 404 { throw GitHubError("not found: \(path)", 404, .notFound) }
        if http.statusCode == 409 || http.statusCode == 422 {
            throw ConflictError(detail: "\(http.statusCode) \(path): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        let text = String(decoding: data.prefix(200), as: UTF8.self)
        throw GitHubError("GitHub \(http.statusCode): \(text)", http.statusCode, .other)
    }

    /// Cheap credential check that also tells the user what the token can see.
    func verify() async -> GitHubCheck {
        struct Repo: Decodable {
            struct Permissions: Decodable { let push: Bool? }
            let fullName: String
            let isPrivate: Bool
            let permissions: Permissions?

            enum CodingKeys: String, CodingKey {
                case fullName = "full_name"
                case isPrivate = "private"
                case permissions
            }
        }
        do {
            let repo = try JSONDecoder().decode(Repo.self, from: try await call(repoRoot))
            guard repo.permissions?.push == true else {
                return .bad(error: "这个令牌只能读，不能写。需要 Contents: Read and write。")
            }
            let visibility = repo.isPrivate ? " · 私有" : " · 公开（建议改成私有）"
            return .ok(detail: repo.fullName + visibility)
        } catch {
            return .bad(error: error.localizedDescription)
        }
    }

    func readManifest() async throws -> Manifest? {
        do {
            let data = try await call(
                "\(repoRoot)/contents/\(manifestPath)?ref=\(escaped(cfg.branch))",
                accept: "application/vnd.github.raw"
            )
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch let e as GitHubError where e.kind == .notFound {
            return nil
        }
    }

    func writeManifest(_ m: Manifest) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        _ = try await put(
            manifestPath,
            content: try encoder.encode(m).base64EncodedString(),
            expected: shas[manifestPath],
            message: "vault: manifest"
        )
    }

    func listShards() async throws -> [String: String] {
        struct Entry: Decodable { let path: String; let sha: String; let type: String }

        var out: [String: String] = [:]
        // The Contents directory listing rather than the git tree: the tree
        // endpoint sets `truncated` and silently drops entries once a
        // repository is large enough, and a shard missing from the listing
        // reads as "no remote copy", which is the one mistake this whole file
        // exists to avoid.
        //
        // A directory listing carries no file contents, so the Contents API's
        // 1 MB ceiling does not apply, and its own cap is 1,000 entries — one
        // shard per month, so eighty years.
        for dir in ["vault", "vault/s"] {
            do {
                let data = try await call("\(repoRoot)/contents/\(dir)?ref=\(escaped(cfg.branch))")
                for e in try JSONDecoder().decode([Entry].self, from: data) where e.type == "file" {
                    shas[e.path] = e.sha
                    if e.path.hasPrefix("vault/s/") { out[e.path] = e.sha }
                }
            } catch let e as GitHubError where e.kind == .notFound {
                // Neither directory exists in a fresh vault; that is a valid start.
                continue
            }
        }
        return out
    }

    func readShard(_ month: String) async throws -> String {
        let path = shardPath(month)
        guard let sha = shas[path] else {
            throw GitHubError("no such shard: \(path)", 404, .notFound)
        }
        // The blobs endpoint has no 1 MB ceiling, unlike the contents endpoint.
        let data = try await call("\(repoRoot)/git/blobs/\(sha)", accept: "application/vnd.github.raw")
        return String(decoding: data, as: UTF8.self)
    }

    func writeShard(_ month: String, _ body: String, expected: String?) async throws -> String {
        let path = shardPath(month)
        // The file's bytes are the base64 of the envelope; the Contents API then
        // base64s that again for transport. Double encoding is 33% waste on a small
        // file and buys a plain-text blob that `git diff` will not try to merge.
        let sha = try await put(
            path,
            content: Data(body.utf8).base64EncodedString(),
            expected: expected,
            message: "vault: \(month)"
        )
        shas[path] = sha
        return sha
    }

    private func put(_ path: String, content: String, expected: String?, message: String) async throws -> String {
        struct Body: Encodable {
            let message: String
            let content: String
            let branch: String
            let sha: String?
        }
        struct Written: Decodable {
            struct Content: Decodable { let sha: String? }
            let content: Content?
        }
        let data = try await call(
            "\(repoRoot)/contents/\(path)",
            method: "PUT",
            body: try JSONEncoder().encode(
                Body(message: message, content: content, branch: cfg.branch, sha: expected)
            )
        )
        guard let sha = try JSONDecoder().decode(Written.self, from: data).content?.sha else {
            throw GitHubError("write succeeded but returned no sha", 500, .other)
        }
        return sha
    }

    private nonisolated func escaped(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}

/// A one-click link that pre-fills the scopes the vault needs.
let gitHubTokenURL =
    "https://github.com/settings/tokens/new?scopes=repo&description=Countbook%20%E8%8A%B1%E5%BE%97%E5%80%BC"
