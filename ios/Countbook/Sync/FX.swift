import Foundation

/// Exchange rates for a receipt in another currency. The sync server answers
/// `/api/fx` from the European Central Bank's daily reference rates and keeps
/// each day's figure, so every device that asks for the same day gets the same
/// rate. The rate is written into the entry at the moment of recording; a total
/// never looks a rate up again, and never moves when the market does.
///
/// Nothing here is required: with no network the last rate used for the pair is
/// offered, and the field stays editable either way. A person who knows the
/// rate their broker applied should type that one. Mirrors web/src/sync/fx.ts.

/// The currencies the keypad offers; the ledger's own currency is listed first by the caller.
let currencies = ["CNY", "USD", "HKD", "EUR", "GBP", "JPY"]

struct Rate: Equatable, Sendable {
    enum Source: Sendable { case ecb, identity, remembered }
    let rateMicro: Int
    /// The day the rate was published for — earlier than asked on a weekend.
    let asOf: Day
    let source: Source
}

enum FX {
    private struct Cached: Codable {
        var rateMicro: Int
        var asOf: Day
    }

    private struct Wire: Decodable {
        let rateMicro: Int
        let asOf: Day
    }

    private static let cacheKey = "countbook.fx"
    private static let lastKey = "countbook.fxLast"
    private static let cacheLimit = 60

    private static func pair(_ from: String, _ to: String) -> String { "\(from)/\(to)" }

    /// The rate last written into an entry for this pair, whatever its day.
    static func rememberedRate(_ from: String, _ to: String, defaults: UserDefaults = .standard) -> Int? {
        (defaults.dictionary(forKey: lastKey) as? [String: Int])?[pair(from, to)]
    }

    static func rememberRate(_ from: String, _ to: String, _ rateMicro: Int, defaults: UserDefaults = .standard) {
        var last = (defaults.dictionary(forKey: lastKey) as? [String: Int]) ?? [:]
        last[pair(from, to)] = rateMicro
        defaults.set(last, forKey: lastKey)
    }

    private static func readCache(_ defaults: UserDefaults) -> [String: Cached] {
        guard let data = defaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: Cached].self, from: data)
        else { return [:] }
        return cache
    }

    private static func writeCache(_ cache: [String: Cached], _ defaults: UserDefaults) {
        var kept = cache
        // Keys carry the day; dropping the oldest days keeps the map small.
        let overflow = kept.count - cacheLimit
        if overflow > 0 {
            for key in kept.keys.sorted { $0.suffix(10) < $1.suffix(10) }.prefix(overflow) { kept[key] = nil }
        }
        if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: cacheKey) }
    }

    /// The day's rate, from the local cache or the server. Nil when the server
    /// cannot be reached and nothing has been remembered for the pair.
    static func fetchRate(
        _ from: String, _ to: String, day: Day,
        baseUrl: String = defaultServerURL, defaults: UserDefaults = .standard
    ) async -> Rate? {
        if from == to { return Rate(rateMicro: rateScale, asOf: day, source: .identity) }
        let key = "\(pair(from, to))@\(day)"
        var cache = readCache(defaults)
        let hit = cache[key]
        // A day's rate is final once published for that day; a stand-in from an
        // earlier day (weekend, or asked before publication) is re-asked.
        if let hit, hit.asOf == day { return Rate(rateMicro: hit.rateMicro, asOf: hit.asOf, source: .ecb) }

        var base = baseUrl
        while base.hasSuffix("/") { base.removeLast() }
        if let url = URL(string: "\(base)/api/fx?from=\(from)&to=\(to)&day=\(day)") {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "accept")
            if let (data, response) = try? await uncachedSession.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let wire = try? JSONDecoder().decode(Wire.self, from: data),
               wire.rateMicro > 0 {
                cache[key] = Cached(rateMicro: wire.rateMicro, asOf: wire.asOf)
                writeCache(cache, defaults)
                return Rate(rateMicro: wire.rateMicro, asOf: wire.asOf, source: .ecb)
            }
        }
        if let hit { return Rate(rateMicro: hit.rateMicro, asOf: hit.asOf, source: .ecb) }
        if let last = rememberedRate(from, to, defaults: defaults) {
            return Rate(rateMicro: last, asOf: day, source: .remembered)
        }
        return nil
    }
}
