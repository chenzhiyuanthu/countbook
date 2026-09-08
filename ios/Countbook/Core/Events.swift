import Foundation

/// The ledger is an append-only log. Nothing is ever mutated in place and no
/// device ever needs to agree with another about anything except the set of
/// events it has seen — which makes the merge trivially correct: union by id,
/// order by HLC, fold.
///
/// Union is commutative, associative and idempotent because it is set union on
/// immutable, uniquely-identified records; the fold is deterministic because the
/// order is a total order that does not depend on arrival time. Two devices that
/// have seen the same events therefore always show the same ledger.

enum Payload: Equatable, Sendable {
    case entryAdd(entry: Entry)
    case entryPatch(target: String, patch: EntryPatch)
    case entryRemove(target: String)
    case entryCorrect(target: String, amount: Fen, reason: String)
    case entryVoid(target: String, reason: String)
    case reviewJudge(target: String, worthIt: Bool)
    case reviewDefer(target: String)
    case wishAdd(wish: Wish)
    case wishResolve(target: String, outcome: WishOutcome, entryId: String?)
    case wishRemove(target: String)
    case subUpsert(sub: Sub)
    case subStatus(target: String, status: SubStatus, day: Day?)
    case subUse(target: String, day: Day)
    case subRemove(target: String)
    case standardSet(monthlyFen: Fen, perCategory: [String: Fen], reason: String?)
    case categoryUpsert(category: Category)
    case categoryRemove(target: String)
    case settingsPatch(patch: SettingsPatch)
    case dayNospend(day: Day, on: Bool)

    /// The wire discriminator. Both clients read the same blobs, so these
    /// strings are part of the protocol, not an implementation detail.
    var t: String {
        switch self {
        case .entryAdd: return "entry.add"
        case .entryPatch: return "entry.patch"
        case .entryRemove: return "entry.remove"
        case .entryCorrect: return "entry.correct"
        case .entryVoid: return "entry.void"
        case .reviewJudge: return "review.judge"
        case .reviewDefer: return "review.defer"
        case .wishAdd: return "wish.add"
        case .wishResolve: return "wish.resolve"
        case .wishRemove: return "wish.remove"
        case .subUpsert: return "sub.upsert"
        case .subStatus: return "sub.status"
        case .subUse: return "sub.use"
        case .subRemove: return "sub.remove"
        case .standardSet: return "standard.set"
        case .categoryUpsert: return "category.upsert"
        case .categoryRemove: return "category.remove"
        case .settingsPatch: return "settings.patch"
        case .dayNospend: return "day.nospend"
        }
    }
}

extension Payload: Codable {
    // Swift would nest an enum's associated values under a case name; the shared
    // format is flat — a `t` discriminator with the variant's own fields beside
    // it — so the coding is written out by hand.
    enum CodingKeys: String, CodingKey {
        case t, entry, target, patch, amount, reason, worthIt, wish, outcome
        case entryId, sub, status, day, monthlyFen, perCategory, category, on
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "entry.add":
            self = .entryAdd(entry: try c.decode(Entry.self, forKey: .entry))
        case "entry.patch":
            self = .entryPatch(
                target: try c.decode(String.self, forKey: .target),
                patch: try c.decode(EntryPatch.self, forKey: .patch)
            )
        case "entry.remove":
            self = .entryRemove(target: try c.decode(String.self, forKey: .target))
        case "entry.correct":
            self = .entryCorrect(
                target: try c.decode(String.self, forKey: .target),
                amount: try c.decode(Fen.self, forKey: .amount),
                reason: try c.decode(String.self, forKey: .reason)
            )
        case "entry.void":
            self = .entryVoid(
                target: try c.decode(String.self, forKey: .target),
                reason: try c.decode(String.self, forKey: .reason)
            )
        case "review.judge":
            self = .reviewJudge(
                target: try c.decode(String.self, forKey: .target),
                worthIt: try c.decode(Bool.self, forKey: .worthIt)
            )
        case "review.defer":
            self = .reviewDefer(target: try c.decode(String.self, forKey: .target))
        case "wish.add":
            self = .wishAdd(wish: try c.decode(Wish.self, forKey: .wish))
        case "wish.resolve":
            self = .wishResolve(
                target: try c.decode(String.self, forKey: .target),
                outcome: try c.decode(WishOutcome.self, forKey: .outcome),
                entryId: try c.decodeIfPresent(String.self, forKey: .entryId)
            )
        case "wish.remove":
            self = .wishRemove(target: try c.decode(String.self, forKey: .target))
        case "sub.upsert":
            self = .subUpsert(sub: try c.decode(Sub.self, forKey: .sub))
        case "sub.status":
            self = .subStatus(
                target: try c.decode(String.self, forKey: .target),
                status: try c.decode(SubStatus.self, forKey: .status),
                day: try c.decodeIfPresent(Day.self, forKey: .day)
            )
        case "sub.use":
            self = .subUse(
                target: try c.decode(String.self, forKey: .target),
                day: try c.decode(Day.self, forKey: .day)
            )
        case "sub.remove":
            self = .subRemove(target: try c.decode(String.self, forKey: .target))
        case "standard.set":
            self = .standardSet(
                monthlyFen: try c.decode(Fen.self, forKey: .monthlyFen),
                perCategory: try c.decode([String: Fen].self, forKey: .perCategory),
                reason: try c.decodeIfPresent(String.self, forKey: .reason)
            )
        case "category.upsert":
            self = .categoryUpsert(category: try c.decode(Category.self, forKey: .category))
        case "category.remove":
            self = .categoryRemove(target: try c.decode(String.self, forKey: .target))
        case "settings.patch":
            self = .settingsPatch(patch: try c.decode(SettingsPatch.self, forKey: .patch))
        case "day.nospend":
            self = .dayNospend(
                day: try c.decode(Day.self, forKey: .day),
                on: try c.decode(Bool.self, forKey: .on)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .t, in: c, debugDescription: "unknown payload type \(t)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        switch self {
        case .entryAdd(let entry):
            try c.encode(entry, forKey: .entry)
        case .entryPatch(let target, let patch):
            try c.encode(target, forKey: .target)
            try c.encode(patch, forKey: .patch)
        case .entryCorrect(let target, let amount, let reason):
            try c.encode(target, forKey: .target)
            try c.encode(amount, forKey: .amount)
            try c.encode(reason, forKey: .reason)
        case .entryVoid(let target, let reason):
            try c.encode(target, forKey: .target)
            try c.encode(reason, forKey: .reason)
        case .reviewJudge(let target, let worthIt):
            try c.encode(target, forKey: .target)
            try c.encode(worthIt, forKey: .worthIt)
        case .entryRemove(let target), .reviewDefer(let target), .wishRemove(let target),
             .subRemove(let target), .categoryRemove(let target):
            try c.encode(target, forKey: .target)
        case .wishAdd(let wish):
            try c.encode(wish, forKey: .wish)
        case .wishResolve(let target, let outcome, let entryId):
            try c.encode(target, forKey: .target)
            try c.encode(outcome, forKey: .outcome)
            try c.encodeIfPresent(entryId, forKey: .entryId)
        case .subUpsert(let sub):
            try c.encode(sub, forKey: .sub)
        case .subStatus(let target, let status, let day):
            try c.encode(target, forKey: .target)
            try c.encode(status, forKey: .status)
            try c.encodeIfPresent(day, forKey: .day)
        case .subUse(let target, let day):
            try c.encode(target, forKey: .target)
            try c.encode(day, forKey: .day)
        case .standardSet(let monthlyFen, let perCategory, let reason):
            try c.encode(monthlyFen, forKey: .monthlyFen)
            try c.encode(perCategory, forKey: .perCategory)
            try c.encodeIfPresent(reason, forKey: .reason)
        case .categoryUpsert(let category):
            try c.encode(category, forKey: .category)
        case .settingsPatch(let patch):
            try c.encode(patch, forKey: .patch)
        case .dayNospend(let day, let on):
            try c.encode(day, forKey: .day)
            try c.encode(on, forKey: .on)
        }
    }
}

/// An envelope and its payload, flattened into one object on the wire.
struct Event: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var hlc: String
    var dev: String
    var payload: Payload

    init(id: String, hlc: String, dev: String, payload: Payload) {
        self.id = id
        self.hlc = hlc
        self.dev = dev
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case id, hlc, dev
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        hlc = try c.decode(String.self, forKey: .hlc)
        dev = try c.decode(String.self, forKey: .dev)
        payload = try Payload(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(hlc, forKey: .hlc)
        try c.encode(dev, forKey: .dev)
        try payload.encode(to: encoder)
    }
}

/// Union by event id, then total order by HLC.
func merge(_ a: [Event], _ b: [Event]) -> [Event] {
    var seen = Set<String>()
    var union: [Event] = []
    union.reserveCapacity(a.count + b.count)
    for e in a where seen.insert(e.id).inserted { union.append(e) }
    for e in b where seen.insert(e.id).inserted { union.append(e) }
    return sort(union)
}

/// Lexicographic order on the HLC encoding is the intended total order. The sort
/// is made stable by hand — `sorted(by:)` is not — so two devices that merged
/// the same events in a different order still agree on stamps that tie.
func sort(_ events: [Event]) -> [Event] {
    events.enumerated()
        .sorted { l, r in
            l.element.hlc == r.element.hlc ? l.offset < r.offset : l.element.hlc < r.element.hlc
        }
        .map(\.element)
}

/// Compaction. Events whose effect is fully superseded carry no information once
/// the whole log is folded, so a vault blob does not have to grow forever. Only
/// events strictly older than `before` are eligible, so a device that has been
/// offline since then still merges correctly.
///
/// What survives: every event about an entry that still exists, every correction
/// and voidance (they are the audit trail and are never dropped), and the latest
/// settings/standard events. What is dropped: patches on entries that were later
/// removed, and superseded settings patches.
func compact(_ events: [Event], before: String) -> [Event] {
    var removed = Set<String>()
    for e in events {
        if case .entryRemove(let target) = e.payload { removed.insert(target) }
    }

    var keptSettings: [Event] = []
    var out: [Event] = []
    for e in events {
        guard e.hlc < before else {
            out.append(e)
            continue
        }
        switch e.payload {
        case .entryAdd(let entry):
            if !removed.contains(entry.id) { out.append(e) }
        case .entryPatch(let target, _), .reviewJudge(let target, _), .reviewDefer(let target):
            if !removed.contains(target) { out.append(e) }
        case .entryRemove:
            // The tombstone must outlive the events it suppresses.
            out.append(e)
        case .settingsPatch:
            keptSettings.append(e)
        default:
            out.append(e)
        }
    }
    // Collapse the settings history into one event carrying the merged patch.
    if let last = keptSettings.last {
        var merged = SettingsPatch()
        for e in keptSettings {
            if case .settingsPatch(let patch) = e.payload { merged = merged.merging(patch) }
        }
        out.append(Event(id: last.id, hlc: last.hlc, dev: last.dev, payload: .settingsPatch(patch: merged)))
    }
    return sort(out)
}
