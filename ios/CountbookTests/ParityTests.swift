import XCTest
@testable import Countbook

/// design/fixtures/money.json is a shared acceptance test: the web client
/// asserts against the same file, so a formatting difference between the two
/// platforms fails a build rather than shipping.
private struct Fixtures: Decodable {
    struct FormatCase: Decodable {
        let fen: Fen
        let out: String
    }

    struct ParseCase: Decodable {
        let input: String
        let fen: Fen?

        enum CodingKeys: String, CodingKey {
            case input = "in"
            case fen
        }
    }

    struct CoolingCase: Decodable {
        let priceFen: Fen
        let days: Int
    }

    let format: [FormatCase]
    let parse: [ParseCase]
    let coolingDays: [CoolingCase]
}

final class ParityTests: XCTestCase {
    private static let fixtures: Fixtures = {
        guard let url = Bundle(for: ParityTests.self).url(forResource: "money", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Fixtures.self, from: data)
        else { fatalError("design/fixtures/money.json is missing from the test bundle") }
        return decoded
    }()

    private var fixtures: Fixtures { Self.fixtures }

    // MARK: money

    func testFormatsEverySharedFixtureIdentically() {
        for f in fixtures.format {
            XCTAssertEqual(format(f.fen), f.out, "format(\(f.fen))")
        }
    }

    func testParsesEverySharedFixtureRejectingTheMalformed() {
        for f in fixtures.parse {
            XCTAssertEqual(parse(f.input), f.fen, "parse(\(f.input))")
        }
    }

    func testCoolingDaysMatchesEverySharedFixture() {
        for f in fixtures.coolingDays {
            XCTAssertEqual(coolingDays(f.priceFen), f.days, "coolingDays(\(f.priceFen))")
        }
    }

    func testSplitsIntoThePartsTheDesignRendersSeparately() {
        XCTAssertEqual(parts(-8420), MoneyParts(sign: minus, symbol: "¥", int: "84", frac: "20"))
        XCTAssertEqual(parts(123_800), MoneyParts(sign: "", symbol: "¥", int: "1,238", frac: "00"))
        XCTAssertEqual(parts(1234, currency: "HKD").symbol, "HK$")
        XCTAssertEqual(parts(1234, currency: "XYZ").symbol, "XYZ ")
    }

    func testFormatsWholeYuanForDenseLabels() {
        XCTAssertEqual(formatYuan(126_499), "¥1,264")
        XCTAssertEqual(formatYuan(-8420), "−¥84")
        XCTAssertEqual(formatYuan(0), "¥0")
    }

    func testRoundTripsParseAndFormatWithoutDrift() {
        for fen in stride(from: -50_000, to: 50_000, by: 337) {
            XCTAssertEqual(parse(format(fen).replacingOccurrences(of: minus, with: "-")), fen)
        }
    }

    func testNeverLosesAFenWhenDividingAcrossDays() {
        for (total, n) in [(10_000, 7), (-8_421, 12), (1, 31), (0, 5)] {
            let split = divideRemainderLast(total, n)
            XCTAssertEqual(split.per * (n - 1) + split.last, total, "\(total)/\(n)")
        }
        XCTAssertEqual(divideRemainderLast(500, 0).last, 500)
    }

    // MARK: dates

    func testHandlesMonthLengthsIncludingLeapFebruary() {
        XCTAssertEqual(daysInMonth("2024-02"), 29)
        XCTAssertEqual(daysInMonth("2026-02"), 28)
        XCTAssertEqual(daysInMonth("2000-02"), 29)
        XCTAssertEqual(daysInMonth("1900-02"), 28)
        XCTAssertEqual(daysInMonth("2026-09"), 30)
        XCTAssertEqual(allDaysOf("2024-02").count, 29)
        XCTAssertEqual(allDaysOf("2026-02").last, "2026-02-28")
    }

    func testCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(addDays("2026-01-31", 1), "2026-02-01")
        XCTAssertEqual(addDays("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(addDays("2026-03-01", -1), "2026-02-28")
        XCTAssertEqual(addDays("2024-03-01", -1), "2024-02-29")
        XCTAssertEqual(diffDays("2026-01-01", "2026-12-31"), 364)
        XCTAssertEqual(diffDays("2024-01-01", "2025-01-01"), 366)
        XCTAssertEqual(addMonths("2026-12", 1), "2027-01")
        XCTAssertEqual(addMonths("2026-01", -1), "2025-12")
    }

    func testClampsABillingAnchorToAShortMonth() {
        XCTAssertEqual(addCalendarMonths("2026-01-31", 1), "2026-02-28")
        XCTAssertEqual(addCalendarMonths("2024-01-31", 1), "2024-02-29")
        XCTAssertEqual(addCalendarMonths("2026-01-14", 1), "2026-02-14")
        XCTAssertEqual(addCalendarMonths("2026-08-31", 1), "2026-09-30")
        XCTAssertEqual(addCalendarMonths("2026-12-31", 1), "2027-01-31")
        XCTAssertEqual(addCalendarMonths("2026-03-31", -1), "2026-02-28")
        XCTAssertEqual(addCalendarMonths("2026-01-31", 12), "2027-01-31")
    }

    func testCountsRemainingDaysInclusiveOfToday() {
        XCTAssertEqual(daysRemainingInMonth("2026-09-30"), 1)
        XCTAssertEqual(daysRemainingInMonth("2026-09-01"), 30)
        XCTAssertEqual(daysRemainingInMonth("2026-09-20"), 11)
        XCTAssertEqual(daysRemainingInMonth("2024-02-29"), 1)
    }

    func testNamesWeekdaysWithSundayZero() {
        XCTAssertEqual(weekdayOf("2026-09-06"), 0)
        XCTAssertEqual(weekdayOf("2026-09-08"), 2)
        XCTAssertTrue(isWeekend("2026-09-05"))
        XCTAssertTrue(isWeekend("2026-09-06"))
        XCTAssertFalse(isWeekend("2026-09-07"))
        XCTAssertEqual(lastNDays("2026-09-08", 3), ["2026-09-06", "2026-09-07", "2026-09-08"])
    }

    func testDatesAnEveningPurchaseToTheLocalDay() {
        withTimeZone("Asia/Shanghai") {
            // 2026-09-08 23:40 +08:00 — a UTC reading would call this the 9th.
            XCTAssertEqual(toDay(Date(timeIntervalSince1970: 1_788_882_000)), "2026-09-08")
            XCTAssertEqual(toDay(fromDay("2026-09-08")), "2026-09-08")
        }
    }

    func testSurvivesADaylightSavingTransitionWithoutAHalfDay() {
        withTimeZone("America/Los_Angeles") {
            // Spring forward is 2026-03-08; the interval spans a 23-hour day.
            XCTAssertEqual(diffDays("2026-03-07", "2026-03-09"), 2)
            XCTAssertEqual(addDays("2026-03-07", 1), "2026-03-08")
            XCTAssertEqual(addDays("2026-03-08", 1), "2026-03-09")
            // Autumn back, a 25-hour day.
            XCTAssertEqual(diffDays("2026-10-31", "2026-11-02"), 2)
            XCTAssertEqual(addDays("2026-11-01", -1), "2026-10-31")
        }
    }

    func testSurvivesAZoneWhoseTransitionDeletesLocalMidnight() {
        // Santiago springs forward at 24:00, so one day of the month has no
        // 00:00 at all; which day depends on the tz database, so assert the
        // property over the whole month rather than a fixed date.
        withTimeZone("America/Santiago") {
            for day in allDaysOf("2026-09") {
                XCTAssertEqual(diffDays(day, addDays(day, 1)), 1, day)
                XCTAssertEqual(toDay(fromDay(day)), day, day)
            }
            XCTAssertEqual(addDays("2026-09-30", 1), "2026-10-01")
        }
    }

    // MARK: clock

    func testEncodesToALexicographicallySortableString() {
        let a = encode(Hlc(wall: 1, counter: 0, device: "aa"))
        let b = encode(Hlc(wall: 2, counter: 0, device: "aa"))
        let c = encode(Hlc(wall: 2, counter: 1, device: "aa"))
        XCTAssertEqual(a, "0000000000000001-0000-aa")
        XCTAssertLessThan(compare(a, b), 0)
        XCTAssertLessThan(compare(b, c), 0)
        XCTAssertEqual(decode(c), Hlc(wall: 2, counter: 1, device: "aa"))
        XCTAssertEqual(encode(Hlc(wall: 1_760_000_000_000, counter: 7, device: "a1b2c3d4")),
                       "00000199c82cc000-0007-a1b2c3d4")
    }

    func testAdvancesMonotonicallyWhenTheWallClockGoesBackwards() {
        var t = 1000
        let clock = Clock(device: "aa", now: { t })
        let first = clock.next()
        t = 900 // an NTP correction, or the owner changing the date
        let second = clock.next()
        let third = clock.next()
        XCTAssertLessThan(compare(first, second), 0)
        XCTAssertLessThan(compare(second, third), 0)
        XCTAssertEqual(decode(second).wall, 1000)
    }

    func testSortsAfterAnyTimestampItHasObserved() {
        let clock = Clock(device: "aa", now: { 1000 })
        let remote = encode(Hlc(wall: 5000, counter: 9, device: "bb"))
        clock.observe(remote)
        XCTAssertLessThan(compare(remote, clock.next()), 0)
    }

    // MARK: -

    private func withTimeZone(_ identifier: String, _ body: () -> Void) {
        guard let tz = TimeZone(identifier: identifier) else {
            return XCTFail("no such timezone: \(identifier)")
        }
        let original = NSTimeZone.default
        NSTimeZone.default = tz
        defer { NSTimeZone.default = original }
        body()
    }
}
