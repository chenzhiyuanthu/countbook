import Foundation

/// Every number the app prints is computed here, from the folded ledger and
/// nothing else. Pure functions with no clock of their own: `today` and `nowMs`
/// are always passed in, so a report is reproducible and a test does not need
/// to mock time.
///
/// The web client in `web/src/core/compute.ts` is the reference; these agree
/// with it to the 分, so every division below is stated in integers and the
/// truncation direction is the one JavaScript's `Math.trunc` would take.

func clamp<T: Comparable>(_ n: T, _ lo: T, _ hi: T) -> T { min(hi, max(lo, n)) }

/// Toward negative infinity, which Swift's `/` does not do for negatives.
private func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b, r = a % b
    return (r != 0 && ((r < 0) != (b < 0))) ? q - 1 : q
}

/// Toward positive infinity, the counterpart of `Math.ceil` on a quotient.
private func ceilDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b, r = a % b
    return (r != 0 && ((r < 0) == (b < 0))) ? q + 1 : q
}

func median(_ xs: [Fen]) -> Fen {
    if xs.isEmpty { return 0 }
    let s = xs.sorted()
    let mid = s.count >> 1
    if s.count % 2 == 1 { return s[mid] }
    // Half-up, matching JS `Math.round`, and stated in 分 so no float ever
    // rounds an amount.
    return floorDiv(s[mid - 1] + s[mid] + 1, 2)
}

/// Population standard deviation. Only ever applied to day counts — never to
/// money — which is why a `Double` is allowed to appear at all.
func stddev(_ xs: [Int]) -> Double {
    if xs.count < 2 { return 0 }
    let n = Double(xs.count)
    let mean = Double(xs.reduce(0, +)) / n
    let variance = xs.reduce(0.0) { acc, x in
        let d = Double(x) - mean
        return acc + d * d
    } / n
    return variance.squareRoot()
}

/// Dictionary iteration has no defined order, so the effective entries are put
/// back into a stable one before anything groups, ranks or clusters them;
/// otherwise two runs over identical data could break ties differently.
func spendsOf(_ L: Ledger) -> [EffectiveEntry] {
    effective(L).values
        .filter { $0.kind == .spend }
        .sorted { a, b in
            if a.day != b.day { return a.day < b.day }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id < b.id
        }
}

func inMonth(_ es: [EffectiveEntry], _ m: Month) -> [EffectiveEntry] {
    es.filter { monthOf($0.day) == m }
}

func inYear(_ es: [EffectiveEntry], _ y: String) -> [EffectiveEntry] {
    es.filter { $0.day.hasPrefix(y) }
}

private func total(_ es: [EffectiveEntry]) -> Fen { es.reduce(0) { $0 + $1.effective } }

// MARK: - 今日可用 — the standing figure

struct Available: Sendable, Equatable {
    /// The hero number. The only figure in the app permitted to be negative.
    let perDay: Fen
    /// Provenance, printed underneath so the figure shows its own derivation.
    let standard: Fen
    let spent: Fen
    let fixedRemaining: Fen
    let remaining: Fen
    let daysLeft: Int
    /// Days of zero spending needed to get back to zero, or 0 if not behind.
    let recoveryDays: Int
}

func available(_ L: Ledger, _ today: Day, _ nowMs: Int) -> Available {
    let m = monthOf(today)
    let std = standardAt(L, nowMs)
    let spends = spendsOf(L)

    let spent = total(inMonth(spends, m).filter { $0.day <= today })
    let fixedRemaining = scheduledOutflowsRemaining(L, today)
    let remaining = std.monthlyFen - spent - fixedRemaining
    let daysLeft = max(1, daysRemainingInMonth(today))

    // Integer division in 分; the remainder rides on the final day rather than
    // evaporating, so the daily figures sum back to the month exactly.
    let perDay = remaining / daysLeft

    let daily = std.monthlyFen > 0 ? std.monthlyFen / daysInMonth(m) : 0
    let recoveryDays = (remaining >= 0 || daily <= 0) ? 0 : ceilDiv(-remaining, daily)

    return Available(
        perDay: perDay,
        standard: std.monthlyFen,
        spent: spent,
        fixedRemaining: fixedRemaining,
        remaining: remaining,
        daysLeft: daysLeft,
        recoveryDays: recoveryDays
    )
}

/// Committed charges still to come this month — money that is already spoken for.
func scheduledOutflowsRemaining(_ L: Ledger, _ today: Day) -> Fen {
    let m = monthOf(today)
    var sum: Fen = 0
    for s in L.subs.values {
        if s.status == .cancelled { continue }
        if monthOf(s.nextChargeAt) == m && s.nextChargeAt > today { sum += s.amount }
    }
    return sum
}

// MARK: - 小额漏水 — the sub-threshold class

struct MerchantLeak: Sendable, Equatable {
    let key: String
    var count: Int
    var sum: Fen
}

struct Leak: Sendable, Equatable {
    let count: Int
    let sum: Fen
    /// The trailing-90-day median of above-ceiling spends; the equivalence divisor.
    let divisor: Fen
    /// sum / divisor — "≈ 3.1 次大额支出". 0 when there is no basis yet.
    let equivalent: Double
    let byMerchant: [MerchantLeak]
}

func leak(_ L: Ledger, _ today: Day) -> Leak {
    let ceiling = L.settings.leakCeilingFen
    let spends = spendsOf(L)
    let month = inMonth(spends, monthOf(today))
    let small = month.filter { $0.effective > 0 && $0.effective < ceiling }

    let since = addDays(today, -90)
    let big = spends.filter { $0.day >= since && $0.day <= today && $0.effective >= ceiling }
    let divisor = median(big.map(\.effective))

    var order: [String] = []
    var groups: [String: MerchantLeak] = [:]
    for e in small {
        let trimmed = e.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.isEmpty ? (L.categories[e.categoryId]?.name ?? "其他") : trimmed
        if var g = groups[key] {
            g.count += 1
            g.sum += e.effective
            groups[key] = g
        } else {
            order.append(key)
            groups[key] = MerchantLeak(key: key, count: 1, sum: e.effective)
        }
    }

    let sum = total(small)
    return Leak(
        count: small.count,
        sum: sum,
        divisor: divisor,
        equivalent: divisor > 0 ? Double(sum) / Double(divisor) : 0,
        byMerchant: order.compactMap { groups[$0] }.sorted { a, b in
            a.sum != b.sum ? a.sum > b.sum : a.key < b.key
        }
    )
}

// MARK: - 后悔账 — the number that does not soften

struct Regret: Sendable, Equatable {
    let month: Fen
    let year: Fen
    let judged: Int
    let notWorth: Int
    /// Nil until the sample is large enough to mean anything.
    let rate: Double?
    let pending: Int
}

func regret(_ L: Ledger, _ today: Day, minSample: Int = 30) -> Regret {
    let spends = spendsOf(L)
    let judgedAll = spends.filter { $0.worthIt != nil }
    let notWorth = judgedAll.filter { $0.worthIt == false }
    let m = monthOf(today)
    let y = String(today.prefix(4))

    return Regret(
        month: total(notWorth.filter { monthOf($0.day) == m }),
        year: total(notWorth.filter { $0.day.hasPrefix(y) }),
        judged: judgedAll.count,
        notWorth: notWorth.count,
        rate: judgedAll.count >= minSample ? Double(notWorth.count) / Double(judgedAll.count) : nil,
        pending: spends.filter { $0.worthIt == nil && $0.intent != nil && $0.intent != .need }.count
    )
}

struct CategoryRegret: Sendable, Equatable {
    let categoryId: String
    var judged: Int
    var notWorth: Int
    var amount: Fen
    var rate: Double
}

/// Ranked by amount, not by rate: an amount-weighted list puts the real offender first.
func regretByCategory(_ L: Ledger, _ today: Day, months: Int = 12) -> [CategoryRegret] {
    // 30.44 is the mean month; the window is a rough year, not a calendar one.
    let since = addDays(today, -Int((Double(months) * 30.44 + 0.5).rounded(.down)))
    var order: [String] = []
    var rows: [String: CategoryRegret] = [:]
    for e in spendsOf(L) {
        if e.day < since || e.worthIt == nil { continue }
        var r: CategoryRegret
        if let existing = rows[e.categoryId] {
            r = existing
        } else {
            order.append(e.categoryId)
            r = CategoryRegret(categoryId: e.categoryId, judged: 0, notWorth: 0, amount: 0, rate: 0)
        }
        r.judged += 1
        if e.worthIt == false {
            r.notWorth += 1
            r.amount += e.effective
        }
        rows[e.categoryId] = r
    }
    for key in order {
        guard var r = rows[key] else { continue }
        r.rate = r.judged > 0 ? Double(r.notWorth) / Double(r.judged) : 0
        rows[key] = r
    }
    return order.compactMap { rows[$0] }.sorted { a, b in
        a.amount != b.amount ? a.amount > b.amount : a.categoryId < b.categoryId
    }
}

/// The label on the save button, when the category being filed under has a bad
/// record and the amount is not trivial. Spending the regret rate at the moment
/// of commitment is the only place it can still change the outcome.
func commitWarning(_ L: Ledger, _ today: Day, _ categoryId: String, _ amount: Fen) -> String? {
    let rows = regretByCategory(L, today)
    guard let r = rows.first(where: { $0.categoryId == categoryId }) else { return nil }
    if r.judged < 8 { return nil }
    if r.rate <= 0.4 { return nil }
    if amount < L.settings.leakCeilingFen * 2 { return nil }
    return "这类你 \(Int((r.rate * 100 + 0.5).rounded(.down)))% 判过不值"
}

// MARK: - 偏差条 — deviation from the standard you set

struct Deviation: Sendable, Equatable {
    let categoryId: String
    let spent: Fen
    let standard: Fen
    /// Positive is over.
    let delta: Fen
}

func deviationByCategory(_ L: Ledger, _ month: Month, _ nowMs: Int) -> [Deviation] {
    let std = standardAt(L, nowMs)
    let spends = inMonth(spendsOf(L), month)
    var order: [String] = []
    var spentBy: [String: Fen] = [:]
    for e in spends {
        if spentBy[e.categoryId] == nil { order.append(e.categoryId) }
        spentBy[e.categoryId, default: 0] += e.effective
    }
    for id in std.perCategory.keys.sorted() where spentBy[id] == nil { order.append(id) }

    return order.map { categoryId in
        let spent = spentBy[categoryId] ?? 0
        let standard = std.perCategory[categoryId] ?? 0
        return Deviation(categoryId: categoryId, spent: spent, standard: standard, delta: spent - standard)
    }.sorted { a, b in
        a.delta != b.delta ? a.delta > b.delta : a.categoryId < b.categoryId
    }
}

// MARK: - 月度日柱 — the month strip

struct DayBar: Sendable, Equatable {
    let day: Day
    let spent: Fen
    /// Explicitly marked 今天没花钱 — distinct from "nothing was logged".
    let declaredZero: Bool
    let logged: Bool
    let future: Bool
}

struct MonthStrip: Sendable, Equatable {
    let bars: [DayBar]
    /// The height of the reference hairline: the month's standard spread evenly.
    let dailyStandard: Fen
    let max: Fen
}

func monthStrip(_ L: Ledger, _ month: Month, _ today: Day, _ nowMs: Int) -> MonthStrip {
    let std = standardAt(L, nowMs)
    var byDay: [Day: Fen] = [:]
    for e in inMonth(spendsOf(L), month) { byDay[e.day, default: 0] += e.effective }

    let bars = allDaysOf(month).map { day in
        DayBar(
            day: day,
            spent: byDay[day] ?? 0,
            declaredZero: L.noSpendDays.contains(day),
            logged: byDay[day] != nil || L.noSpendDays.contains(day),
            future: day > today
        )
    }

    let dailyStandard = std.monthlyFen > 0 ? std.monthlyFen / daysInMonth(month) : 0
    return MonthStrip(
        bars: bars,
        dailyStandard: dailyStandard,
        max: max(dailyStandard, bars.map(\.spent).max() ?? dailyStandard)
    )
}

/// Consecutive days, ending yesterday, that were at or under the daily standard.
/// A day with no data at all breaks the streak rather than extending it —
/// otherwise not logging would be the winning strategy.
func streak(_ L: Ledger, _ today: Day, _ nowMs: Int) -> Int {
    let std = standardAt(L, nowMs)
    if std.monthlyFen <= 0 { return 0 }
    var byDay: [Day: Fen] = [:]
    for e in spendsOf(L) { byDay[e.day, default: 0] += e.effective }

    var n = 0
    for i in 1...400 {
        let day = addDays(today, -i)
        let daily = std.monthlyFen / daysInMonth(monthOf(day))
        let logged = byDay[day] != nil || L.noSpendDays.contains(day)
        if !logged { break }
        if (byDay[day] ?? 0) > daily { break }
        n += 1
    }
    return n
}

// MARK: - 待购 — cooling

/// Continuous, not tiered: ¥999 and ¥1,001 should not differ by a week.
func coolingDays(_ priceFen: Fen, perDay: Int = 10_000, lo: Int = 1, hi: Int = 14) -> Int {
    clamp(ceilDiv(priceFen, perDay), lo, hi)
}

struct WishStats: Sendable, Equatable {
    let abstainedYear: Fen
    let abstainedAll: Fen
    let cooling: Int
    let ready: Int
}

func wishStats(_ L: Ledger, _ today: Day, _ nowMs: Int) -> WishStats {
    let y = String(today.prefix(4))
    var abstainedYear: Fen = 0
    var abstainedAll: Fen = 0
    var cooling = 0
    var ready = 0
    for w in L.wishes.values {
        if w.outcome == .abstained {
            abstainedAll += w.price
            if let at = w.resolvedAt,
               toDay(Date(timeIntervalSince1970: Double(at) / 1000)).hasPrefix(y) {
                abstainedYear += w.price
            }
        } else if w.outcome == nil {
            if w.unlockAt <= nowMs { ready += 1 } else { cooling += 1 }
        }
    }
    return WishStats(abstainedYear: abstainedYear, abstainedAll: abstainedAll, cooling: cooling, ready: ready)
}

// MARK: - 订阅影子 — annualisation

private func chargesPerYear(_ p: SubPeriod) -> Int {
    switch p {
    case .week: return 52
    case .month: return 12
    case .quarter: return 4
    case .year: return 1
    }
}

struct SubView: Equatable {
    let sub: Sub
    let annual: Fen
    let paidSoFar: Fen
    let perUse: Fen?
}

func subViews(_ L: Ledger, _ today: Day) -> (rows: [SubView], annual: Fen, perDay: Fen) {
    var rows: [SubView] = []
    for s in L.subs.values {
        let perYear = chargesPerYear(s.period)
        let annual = s.amount * perYear
        let elapsedDays = max(0, diffDays(s.firstChargedAt, s.cancelledAt ?? today))
        // The period length is fractional (365/12 is not 30), so the count of
        // charges that have already landed is the only float in this path.
        let charges = Int((Double(elapsedDays) / (365.0 / Double(perYear))).rounded(.down)) + 1
        let paidSoFar = s.amount * charges
        let uses = s.usageDays?.count ?? 0
        rows.append(SubView(
            sub: s,
            annual: annual,
            paidSoFar: paidSoFar,
            perUse: uses > 0 ? paidSoFar / uses : nil
        ))
    }
    // Ranked by annual cost: the decision is "stop a ¥300/year", never "save ¥25".
    rows.sort { a, b in
        if a.annual != b.annual { return a.annual > b.annual }
        if a.paidSoFar != b.paidSoFar { return a.paidSoFar > b.paidSoFar }
        return a.sub.id < b.sub.id
    }
    let live = rows.filter { $0.sub.status != .cancelled }
    let annual = live.reduce(0) { $0 + $1.annual }
    return (rows: rows, annual: annual, perDay: annual / 365)
}

/// Money no longer leaving, and still counting, since a subscription was cancelled.
func savedByCancelling(_ L: Ledger, _ today: Day) -> Fen {
    var sum: Fen = 0
    for s in L.subs.values {
        guard s.status == .cancelled, let cancelledAt = s.cancelledAt else { continue }
        let days = max(0, diffDays(cancelledAt, today))
        sum += (s.amount * chargesPerYear(s.period) * days) / 365
    }
    return sum
}

// MARK: - recurring detection

struct Detected: Sendable, Equatable {
    let key: String
    let name: String
    let amount: Fen
    let period: SubPeriod
    let categoryId: String
    let firstChargedAt: Day
    let lastChargedAt: Day
    let nextChargeAt: Day
    let occurrences: Int
}

private func normaliseMerchant(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    t = t.replacingOccurrences(of: "[0-9#]+$", with: "", options: .regularExpression)
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Calendar-correct advance for each billing period.
func nextCharge(_ day: Day, _ period: SubPeriod) -> Day {
    switch period {
    case .week: return addDays(day, 7)
    case .month: return addCalendarMonths(day, 1)
    case .quarter: return addCalendarMonths(day, 3)
    case .year: return addCalendarMonths(day, 12)
    }
}

private let periodGuess: [(period: SubPeriod, days: Double, tolerance: Double)] = [
    (.week, 7, 2),
    (.month, 30.44, 5),
    (.quarter, 91.3, 10),
    (.year, 365, 20),
]

/// Find charges that keep coming back: same payee, near-identical amount, at a
/// regular interval. Purely local — nothing is sent anywhere to work this out.
/// Results start `unclaimed`, and the user has to say 保留 or 待退订 for each.
func detectRecurring(_ L: Ledger, _ today: Day, minOccurrences: Int = 3, maxJitterDays: Int = 4) -> [Detected] {
    var order: [String] = []
    var byKey: [String: [EffectiveEntry]] = [:]
    for e in spendsOf(L) {
        let key = normaliseMerchant(e.merchant)
        if key.isEmpty || e.effective <= 0 { continue }
        if byKey[key] == nil { order.append(key) }
        byKey[key, default: []].append(e)
    }

    var out: [Detected] = []
    for key in order {
        guard let all = byKey[key] else { continue }
        // Cluster on amount: a ±5% band tolerates FX drift and price rises
        // without merging a ¥25 subscription with a ¥250 one.
        let sorted = all.sorted { $0.effective < $1.effective }
        var i = 0
        while i < sorted.count {
            let base = sorted[i].effective
            var j = i
            while j < sorted.count && Double(sorted[j].effective) <= Double(base) * 1.05 { j += 1 }
            let cluster = sorted[i..<j].sorted { a, b in
                a.day != b.day ? a.day < b.day : a.id < b.id
            }
            i = j
            if cluster.count < minOccurrences { continue }

            var gaps: [Int] = []
            for k in 1..<cluster.count { gaps.append(diffDays(cluster[k - 1].day, cluster[k].day)) }
            if stddev(gaps) >= Double(maxJitterDays) { continue }

            let meanGap = Double(gaps.reduce(0, +)) / Double(gaps.count)
            guard let guess = periodGuess.first(where: { abs(meanGap - $0.days) <= $0.tolerance }) else { continue }

            let first = cluster[0]
            let last = cluster[cluster.count - 1]
            // Only what is still charging: a series that stopped two intervals
            // ago was already cancelled, and surfacing it as "unclaimed" is noise.
            if Double(diffDays(last.day, today)) > meanGap * 2 + Double(maxJitterDays) { continue }

            let trimmedName = first.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Detected(
                key: key,
                name: trimmedName.isEmpty ? key : trimmedName,
                amount: median(cluster.map(\.effective)),
                period: guess.period,
                categoryId: last.categoryId,
                firstChargedAt: first.day,
                lastChargedAt: last.day,
                nextChargeAt: nextCharge(last.day, guess.period),
                occurrences: cluster.count
            ))
        }
    }
    return out.sorted { a, b in
        let x = a.amount * chargesPerYear(a.period)
        let y = b.amount * chargesPerYear(b.period)
        return x != y ? x > y : a.key < b.key
    }
}

// MARK: - the hour scatter

struct HourBucket: Sendable, Equatable {
    let hour: Int
    var count: Int
    var sum: Fen
}

/// Logging time by hour, which is where late-night ordering becomes visible.
func hourScatter(_ L: Ledger, _ today: Day, days: Int = 90) -> [HourBucket] {
    let since = addDays(today, -days)
    var buckets = (0..<24).map { HourBucket(hour: $0, count: 0, sum: 0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    for e in spendsOf(L) {
        if e.day < since { continue }
        let h = calendar.component(.hour, from: Date(timeIntervalSince1970: Double(e.createdAt) / 1000))
        buckets[h].count += 1
        buckets[h].sum += e.effective
    }
    return buckets
}

// MARK: - 心愿物 — the exchange rate for regret

func regretAsWishObject(_ L: Ledger, _ regretYear: Fen) -> (name: String, fraction: Double)? {
    guard let w = L.settings.wishObject, w.priceFen > 0 else { return nil }
    return (name: w.name, fraction: min(1, Double(regretYear) / Double(w.priceFen)))
}

/// The proposal the app offers when asked to suggest a standard: the trailing median.
func proposeStandard(_ L: Ledger, _ today: Day) -> (monthlyFen: Fen, perCategory: [String: Fen])? {
    let spends = spendsOf(L)
    if spends.isEmpty { return nil }
    let since = addDays(today, -90)
    let window = spends.filter { $0.day >= since && $0.day <= today }
    let firstDay = window.reduce(today) { $1.day < $0 ? $1.day : $0 }
    if diffDays(firstDay, today) < 30 { return nil }

    var months: [Month: Fen] = [:]
    for e in window { months[monthOf(e.day), default: 0] += e.effective }
    let monthlyFen = median(Array(months.values))

    var perCategoryMonths: [String: [Month: Fen]] = [:]
    for e in window { perCategoryMonths[e.categoryId, default: [:]][monthOf(e.day), default: 0] += e.effective }
    var perCategory: [String: Fen] = [:]
    for (cat, m) in perCategoryMonths { perCategory[cat] = median(Array(m.values)) }

    return (monthlyFen: monthlyFen, perCategory: perCategory)
}

/// Entries owed a verdict this Sunday: unjudged 想要/冲动 from the past week, largest first.
func reckoningQueue(_ L: Ledger, _ today: Day, maxCards: Int = 12) -> [EffectiveEntry] {
    let since = addDays(today, -7)
    let due = spendsOf(L)
        .filter { $0.day >= since && $0.day <= today && $0.worthIt == nil && ($0.intent == .want || $0.intent == .impulse) }
        .sorted { a, b in
            a.effective != b.effective ? a.effective > b.effective : a.id < b.id
        }
    return Array(due.prefix(maxCards))
}
