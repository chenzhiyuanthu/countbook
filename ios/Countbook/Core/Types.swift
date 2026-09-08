import Foundation

/// 必要 / 想要 / 冲动 — stamped at the moment of spending, never inferred and
/// never defaulted. The stamp is the whole mechanism: it is the one moment the
/// app makes you look at what you are doing, and a default would let you skip it.
enum Intent: String, Codable, Sendable, CaseIterable {
    case need, want, impulse
}

enum EntryKind: String, Codable, Sendable, CaseIterable {
    case spend, income
}

struct Entry: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var kind: EntryKind
    /// Always positive; `kind` carries the direction.
    var amount: Fen
    var currency: String
    var categoryId: String
    /// Required on spend, null on income — there is nothing to judge about a salary.
    var intent: Intent?
    var note: String
    /// Normalised payee string; the recurring detector groups on it.
    var merchant: String
    var day: Day
    var createdAt: Int
    /// 一句话，写给三天后的自己 — optional, only offered on large 想要/冲动.
    var promise: String?
    /// Set by 周日审判. `nil` means unjudged.
    var worthIt: Bool?
    var reviewedAt: Int?
    /// 稍后 count; at `Rules.deferralLimit` the entry auto-records 不值.
    var deferrals: Int?
    /// Present when the entry was created by resolving a want-list item.
    var wishId: String?
    var subId: String?

    init(
        id: String,
        kind: EntryKind,
        amount: Fen,
        currency: String,
        categoryId: String,
        intent: Intent?,
        note: String,
        merchant: String,
        day: Day,
        createdAt: Int,
        promise: String? = nil,
        worthIt: Bool? = nil,
        reviewedAt: Int? = nil,
        deferrals: Int? = nil,
        wishId: String? = nil,
        subId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.categoryId = categoryId
        self.intent = intent
        self.note = note
        self.merchant = merchant
        self.day = day
        self.createdAt = createdAt
        self.promise = promise
        self.worthIt = worthIt
        self.reviewedAt = reviewedAt
        self.deferrals = deferrals
        self.wishId = wishId
        self.subId = subId
    }

    // `intent` is required-but-nullable in the shared schema, so it is written
    // as an explicit null; the genuinely optional fields are omitted instead.
    // Everything else is the synthesised behaviour.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(amount, forKey: .amount)
        try c.encode(currency, forKey: .currency)
        try c.encode(categoryId, forKey: .categoryId)
        if let intent { try c.encode(intent, forKey: .intent) } else { try c.encodeNil(forKey: .intent) }
        try c.encode(note, forKey: .note)
        try c.encode(merchant, forKey: .merchant)
        try c.encode(day, forKey: .day)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(promise, forKey: .promise)
        try c.encodeIfPresent(worthIt, forKey: .worthIt)
        try c.encodeIfPresent(reviewedAt, forKey: .reviewedAt)
        try c.encodeIfPresent(deferrals, forKey: .deferrals)
        try c.encodeIfPresent(wishId, forKey: .wishId)
        try c.encodeIfPresent(subId, forKey: .subId)
    }
}

/// Every field of an `Entry` except its id, each independently settable. `nil`
/// means "this event says nothing about that field", which is what gives the
/// fold per-field last-writer-wins for free.
struct EntryPatch: Codable, Equatable, Sendable {
    var kind: EntryKind?
    var amount: Fen?
    var currency: String?
    var categoryId: String?
    var intent: Intent?
    var note: String?
    var merchant: String?
    var day: Day?
    var createdAt: Int?
    var promise: String?
    var worthIt: Bool?
    var reviewedAt: Int?
    var deferrals: Int?
    var wishId: String?
    var subId: String?

    init(
        kind: EntryKind? = nil,
        amount: Fen? = nil,
        currency: String? = nil,
        categoryId: String? = nil,
        intent: Intent? = nil,
        note: String? = nil,
        merchant: String? = nil,
        day: Day? = nil,
        createdAt: Int? = nil,
        promise: String? = nil,
        worthIt: Bool? = nil,
        reviewedAt: Int? = nil,
        deferrals: Int? = nil,
        wishId: String? = nil,
        subId: String? = nil
    ) {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.categoryId = categoryId
        self.intent = intent
        self.note = note
        self.merchant = merchant
        self.day = day
        self.createdAt = createdAt
        self.promise = promise
        self.worthIt = worthIt
        self.reviewedAt = reviewedAt
        self.deferrals = deferrals
        self.wishId = wishId
        self.subId = subId
    }
}

extension Entry {
    /// The object-spread the fold performs: named fields overwrite, the rest stand.
    func applying(_ p: EntryPatch) -> Entry {
        var e = self
        if let v = p.kind { e.kind = v }
        if let v = p.amount { e.amount = v }
        if let v = p.currency { e.currency = v }
        if let v = p.categoryId { e.categoryId = v }
        if let v = p.intent { e.intent = v }
        if let v = p.note { e.note = v }
        if let v = p.merchant { e.merchant = v }
        if let v = p.day { e.day = v }
        if let v = p.createdAt { e.createdAt = v }
        if let v = p.promise { e.promise = v }
        if let v = p.worthIt { e.worthIt = v }
        if let v = p.reviewedAt { e.reviewedAt = v }
        if let v = p.deferrals { e.deferrals = v }
        if let v = p.wishId { e.wishId = v }
        if let v = p.subId { e.subId = v }
        return e
    }
}

/// A sealed month is not edited, it is corrected. The original row stays printed
/// and the correction is printed beneath it, which is what makes the ledger
/// worth trusting: you can see that you changed your mind, and when.
struct Correction: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var targetId: String
    var amount: Fen
    var reason: String
    var at: Int
}

struct Voidance: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var targetId: String
    var reason: String
    var at: Int
}

struct Category: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var nameEn: String
    var kind: EntryKind
    var order: Int
    var archived: Bool?

    init(id: String, name: String, nameEn: String, kind: EntryKind, order: Int, archived: Bool? = nil) {
        self.id = id
        self.name = name
        self.nameEn = nameEn
        self.kind = kind
        self.order = order
        self.archived = archived
    }
}

enum WishOutcome: String, Codable, Sendable, CaseIterable {
    case bought, abstained
}

/// 待购 — an intended purchase held inside a cooling period.
struct Wish: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var price: Fen
    var note: String?
    var createdAt: Int
    /// createdAt + clamp(ceil(price/¥100), 1, 14) days.
    var unlockAt: Int
    var outcome: WishOutcome?
    var resolvedAt: Int?
    var entryId: String?

    init(
        id: String,
        name: String,
        price: Fen,
        note: String? = nil,
        createdAt: Int,
        unlockAt: Int,
        outcome: WishOutcome? = nil,
        resolvedAt: Int? = nil,
        entryId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.note = note
        self.createdAt = createdAt
        self.unlockAt = unlockAt
        self.outcome = outcome
        self.resolvedAt = resolvedAt
        self.entryId = entryId
    }
}

enum SubPeriod: String, Codable, Sendable, CaseIterable {
    case week, month, quarter, year
}

/// Detected subscriptions start `unclaimed` on purpose. A passive "we found
/// these" list gets ignored; requiring an explicit 保留 or 待退订 per row flips
/// the default from "it keeps charging" to "you decided".
enum SubStatus: String, Codable, Sendable, CaseIterable {
    case unclaimed
    case keep
    case pendingCancel = "pending-cancel"
    case cancelled
}

struct Sub: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var amount: Fen
    var period: SubPeriod
    var categoryId: String
    /// Day of the first observed charge — the annualisation anchor.
    var firstChargedAt: Day
    var nextChargeAt: Day
    var status: SubStatus
    var cancelledAt: Day?
    /// Optional one-tap usage log; yields 每次使用 ¥37.5.
    var usageDays: [Day]?
    var detected: Bool?

    init(
        id: String,
        name: String,
        amount: Fen,
        period: SubPeriod,
        categoryId: String,
        firstChargedAt: Day,
        nextChargeAt: Day,
        status: SubStatus,
        cancelledAt: Day? = nil,
        usageDays: [Day]? = nil,
        detected: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.period = period
        self.categoryId = categoryId
        self.firstChargedAt = firstChargedAt
        self.nextChargeAt = nextChargeAt
        self.status = status
        self.cancelledAt = cancelledAt
        self.usageDays = usageDays
        self.detected = detected
    }

    /// An upsert carries a whole `Sub`, so only the fields it leaves unstated —
    /// a usage log, a cancellation date — can still be inherited from the row
    /// already on file.
    func merged(over old: Sub?) -> Sub {
        guard let old else { return self }
        var s = self
        if s.cancelledAt == nil { s.cancelledAt = old.cancelledAt }
        if s.usageDays == nil { s.usageDays = old.usageDays }
        if s.detected == nil { s.detected = old.detected }
        return s
    }
}

/// 标准线 — the line you are measured against, set by you, revised on the record.
struct StandardRevision: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var at: Int
    var monthlyFen: Fen
    var perCategory: [String: Fen]
    var reason: String?

    init(id: String, at: Int, monthlyFen: Fen, perCategory: [String: Fen], reason: String? = nil) {
        self.id = id
        self.at = at
        self.monthlyFen = monthlyFen
        self.perCategory = perCategory
        self.reason = reason
    }
}

struct Settings: Codable, Equatable, Sendable {
    enum Locale: String, Codable, Sendable, CaseIterable {
        case zhCN = "zh-CN"
        case en
    }

    enum Theme: String, Codable, Sendable, CaseIterable {
        case system, light, dark
    }

    /// 心愿物 — turns the abstract year-to-date regret figure into a fraction of
    /// a real object.
    struct WishObject: Codable, Equatable, Sendable {
        var name: String
        var priceFen: Fen
    }

    var currency: String
    var locale: Locale
    var theme: Theme
    /// Entries below this are counted as a class — the 小额漏水 strip.
    var leakCeilingFen: Fen
    /// At or above this, the capture sheet offers 挂起 instead of an immediate save.
    var coolingFloorFen: Fen
    var reckoningWeekday: Int
    var reckoningHour: Int
    var wishObject: WishObject?
    /// Set once the user has been shown, and dismissed, the first-run standard proposal.
    var standardAccepted: Bool?

    init(
        currency: String,
        locale: Locale,
        theme: Theme,
        leakCeilingFen: Fen,
        coolingFloorFen: Fen,
        reckoningWeekday: Int,
        reckoningHour: Int,
        wishObject: WishObject? = nil,
        standardAccepted: Bool? = nil
    ) {
        self.currency = currency
        self.locale = locale
        self.theme = theme
        self.leakCeilingFen = leakCeilingFen
        self.coolingFloorFen = coolingFloorFen
        self.reckoningWeekday = reckoningWeekday
        self.reckoningHour = reckoningHour
        self.wishObject = wishObject
        self.standardAccepted = standardAccepted
    }
}

struct SettingsPatch: Codable, Equatable, Sendable {
    var currency: String?
    var locale: Settings.Locale?
    var theme: Settings.Theme?
    var leakCeilingFen: Fen?
    var coolingFloorFen: Fen?
    var reckoningWeekday: Int?
    var reckoningHour: Int?
    var wishObject: Settings.WishObject?
    var standardAccepted: Bool?

    init(
        currency: String? = nil,
        locale: Settings.Locale? = nil,
        theme: Settings.Theme? = nil,
        leakCeilingFen: Fen? = nil,
        coolingFloorFen: Fen? = nil,
        reckoningWeekday: Int? = nil,
        reckoningHour: Int? = nil,
        wishObject: Settings.WishObject? = nil,
        standardAccepted: Bool? = nil
    ) {
        self.currency = currency
        self.locale = locale
        self.theme = theme
        self.leakCeilingFen = leakCeilingFen
        self.coolingFloorFen = coolingFloorFen
        self.reckoningWeekday = reckoningWeekday
        self.reckoningHour = reckoningHour
        self.wishObject = wishObject
        self.standardAccepted = standardAccepted
    }

    /// Later patches win field by field, which is how compaction can collapse a
    /// whole settings history into one event without changing the fold.
    func merging(_ later: SettingsPatch) -> SettingsPatch {
        var p = self
        if let v = later.currency { p.currency = v }
        if let v = later.locale { p.locale = v }
        if let v = later.theme { p.theme = v }
        if let v = later.leakCeilingFen { p.leakCeilingFen = v }
        if let v = later.coolingFloorFen { p.coolingFloorFen = v }
        if let v = later.reckoningWeekday { p.reckoningWeekday = v }
        if let v = later.reckoningHour { p.reckoningHour = v }
        if let v = later.wishObject { p.wishObject = v }
        if let v = later.standardAccepted { p.standardAccepted = v }
        return p
    }
}

extension Settings {
    func applying(_ p: SettingsPatch) -> Settings {
        var s = self
        if let v = p.currency { s.currency = v }
        if let v = p.locale { s.locale = v }
        if let v = p.theme { s.theme = v }
        if let v = p.leakCeilingFen { s.leakCeilingFen = v }
        if let v = p.coolingFloorFen { s.coolingFloorFen = v }
        if let v = p.reckoningWeekday { s.reckoningWeekday = v }
        if let v = p.reckoningHour { s.reckoningHour = v }
        if let v = p.wishObject { s.wishObject = v }
        if let v = p.standardAccepted { s.standardAccepted = v }
        return s
    }
}

/// The folded ledger: the only thing the UI ever reads.
struct Ledger: Codable, Equatable, Sendable {
    var entries: [String: Entry]
    /// Ids removed while their month was still open. Patches on these are dropped.
    var tombstones: Set<String>
    var corrections: [Correction]
    var voids: [Voidance]
    var categories: [String: Category]
    var wishes: [String: Wish]
    var subs: [String: Sub]
    var standards: [StandardRevision]
    var settings: Settings
    /// Days explicitly marked 今天没花钱, so silence is never scored as discipline.
    var noSpendDays: Set<Day>
}
