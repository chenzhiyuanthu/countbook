import Foundation

/// A local civil date, `"yyyy-MM-dd"` — never a UTC instant. A purchase made at
/// 23:40 belongs to that day in the user's own timezone, and a ledger that
/// shifts entries across midnight when he flies is broken. Timestamps (epoch
/// milliseconds) exist separately, for ordering only.
typealias Day = String

/// `"yyyy-MM"`.
typealias Month = String

// Constructing a Calendar costs enough to show up when a list formats a few
// hundred rows, so one is kept. It snapshots its timezone, so the cache is
// rebuilt when the device moves rather than silently dating entries to the
// zone the app happened to launch in.
private final class CivilCalendar: @unchecked Sendable {
    static let shared = CivilCalendar()

    private let lock = NSLock()
    private var zone: TimeZone
    private var calendar: Calendar

    private init() {
        let tz = TimeZone.current
        zone = tz
        calendar = CivilCalendar.gregorian(in: tz)
    }

    private static func gregorian(in tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    var current: Calendar {
        let tz = TimeZone.current
        lock.lock()
        defer { lock.unlock() }
        if tz != zone {
            zone = tz
            calendar = CivilCalendar.gregorian(in: tz)
        }
        return calendar
    }
}

private var civil: Calendar { CivilCalendar.shared.current }

private func p2(_ n: Int) -> String { n < 10 && n >= 0 ? "0\(n)" : "\(n)" }

private func fields(_ day: Day) -> (y: Int, m: Int, d: Int) {
    let parts = day.split(separator: "-", omittingEmptySubsequences: false)
    return (
        y: parts.count > 0 ? Int(parts[0]) ?? 0 : 0,
        m: parts.count > 1 ? Int(parts[1]) ?? 1 : 1,
        d: parts.count > 2 ? Int(parts[2]) ?? 1 : 1
    )
}

// Anchored at noon: a DST transition that deletes local midnight would
// otherwise make the day's own start ambiguous, and a day difference measured
// from midnight can land 23 or 25 hours apart.
private func instant(_ day: Day, hour: Int = 12) -> Date {
    let f = fields(day)
    var c = DateComponents()
    c.year = f.y
    c.month = f.m
    c.day = f.d
    c.hour = hour
    return civil.date(from: c) ?? Date(timeIntervalSince1970: 0)
}

private func firstOf(_ month: Month) -> Date {
    let parts = month.split(separator: "-", omittingEmptySubsequences: false)
    var c = DateComponents()
    c.year = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
    c.month = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
    c.day = 1
    c.hour = 12
    return civil.date(from: c) ?? Date(timeIntervalSince1970: 0)
}

func toDay(_ date: Date) -> Day {
    let c = civil.dateComponents([.year, .month, .day], from: date)
    return "\(c.year ?? 0)-\(p2(c.month ?? 1))-\(p2(c.day ?? 1))"
}

/// Local midnight of that day, matching the web client's `fromDay`.
func fromDay(_ day: Day) -> Date {
    instant(day, hour: 0)
}

func monthOf(_ day: Day) -> Month { String(day.prefix(7)) }

func daysInMonth(_ month: Month) -> Int {
    civil.range(of: .day, in: .month, for: firstOf(month))?.count ?? 30
}

func dayOfMonth(_ month: Month, _ dom: Int) -> Day { "\(month)-\(p2(dom))" }

func addDays(_ day: Day, _ n: Int) -> Day {
    guard let d = civil.date(byAdding: .day, value: n, to: instant(day)) else { return day }
    return toDay(d)
}

func addMonths(_ month: Month, _ n: Int) -> Month {
    guard let d = civil.date(byAdding: .month, value: n, to: firstOf(month)) else { return month }
    let c = civil.dateComponents([.year, .month], from: d)
    return "\(c.year ?? 0)-\(p2(c.month ?? 1))"
}

/// Advance by a billing period. Subscriptions charge on a calendar anchor, not
/// every 30.44 days: a monthly charge on the 14th falls on the 14th next month,
/// and one anchored on the 31st lands on the last day of a short month rather
/// than sliding into the next one.
func addCalendarMonths(_ day: Day, _ n: Int) -> Day {
    let target = addMonths(monthOf(day), n)
    return dayOfMonth(target, min(fields(day).d, daysInMonth(target)))
}

func diffDays(_ a: Day, _ b: Day) -> Int {
    civil.dateComponents([.day], from: instant(a), to: instant(b)).day ?? 0
}

/// 0 = Sunday, matching `Rules.reckoningWeekday`.
func weekdayOf(_ day: Day) -> Int {
    civil.component(.weekday, from: instant(day)) - 1
}

func isWeekend(_ day: Day) -> Bool { weekdayOf(day) % 6 == 0 }

func allDaysOf(_ month: Month) -> [Day] {
    (1...daysInMonth(month)).map { dayOfMonth(month, $0) }
}

/// Inclusive of today: on the 20th of a 31-day month this is 12.
func daysRemainingInMonth(_ today: Day) -> Int {
    daysInMonth(monthOf(today)) - fields(today).d + 1
}

/// The `n` days ending today, oldest first.
func lastNDays(_ today: Day, _ n: Int) -> [Day] {
    guard n > 0 else { return [] }
    return stride(from: n - 1, through: 0, by: -1).map { addDays(today, -$0) }
}
