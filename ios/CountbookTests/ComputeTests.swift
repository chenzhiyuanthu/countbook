import XCTest
@testable import Countbook

private func H(_ wall: Int, _ counter: Int = 0, _ device: String = "aa") -> String {
    encode(Hlc(wall: wall, counter: counter, device: device))
}

private func ev(_ id: String, _ hlc: String, _ payload: Payload) -> Event {
    Event(id: id, hlc: hlc, dev: decode(hlc).device, payload: payload)
}

private func entry(
    id: String = "e1",
    amount: Fen = 10_000,
    categoryId: String = "food",
    intent: Intent? = .want,
    merchant: String = "",
    day: Day = "2026-09-08"
) -> Entry {
    Entry(
        id: id, kind: .spend, amount: amount, currency: "CNY", categoryId: categoryId,
        intent: intent, note: "", merchant: merchant, day: day, createdAt: 1_760_000_000_000
    )
}

private func ledgerWith(
    _ entries: [Entry],
    monthlyFen: Fen = 800_000,
    perCategory: [String: Fen] = [:]
) -> Ledger {
    fold(
        [ev("s", H(1), .standardSet(monthlyFen: monthlyFen, perCategory: perCategory, reason: nil))]
            + entries.enumerated().map { i, e in ev("a\(i)", H(10 + i), .entryAdd(entry: e)) }
    )
}

/// Midday of a civil day in epoch milliseconds, the unit `standardAt` reads.
private func noonMs(_ day: Day) -> Int {
    Int(fromDay(day).addingTimeInterval(12 * 3600).timeIntervalSince1970 * 1000)
}

final class AvailableTests: XCTestCase {
    func testDividesWhatIsLeftByTheDaysThatAreLeftInclusiveOfToday() {
        let L = ledgerWith([entry(id: "x", amount: 200_000, day: "2026-09-01")])
        let a = available(L, "2026-09-20", noonMs("2026-09-20"))
        XCTAssertEqual(a.standard, 800_000)
        XCTAssertEqual(a.spent, 200_000)
        XCTAssertEqual(a.daysLeft, 11)
        XCTAssertEqual(a.perDay, 600_000 / 11)
    }

    func testGoesNegativeAndReportsHowManyCleanDaysUndoIt() {
        let L = ledgerWith([entry(id: "x", amount: 900_000, day: "2026-09-02")])
        let a = available(L, "2026-09-20", noonMs("2026-09-20"))
        XCTAssertLessThan(a.perDay, 0)
        XCTAssertGreaterThan(a.recoveryDays, 0)
        let daily = 800_000 / 30
        XCTAssertEqual(a.recoveryDays, (100_000 + daily - 1) / daily)
    }

    func testSubtractsChargesAlreadyCommittedForLaterThisMonth() {
        let L = fold([
            ev("s", H(1), .standardSet(monthlyFen: 800_000, perCategory: [:], reason: nil)),
            ev("sub", H(2), .subUpsert(sub: Sub(
                id: "s1", name: "iCloud", amount: 5_000, period: .month, categoryId: "sub",
                firstChargedAt: "2026-01-25", nextChargeAt: "2026-09-25", status: .keep
            ))),
        ])
        XCTAssertEqual(available(L, "2026-09-20", noonMs("2026-09-20")).fixedRemaining, 5_000)
    }
}

final class LeakTests: XCTestCase {
    func testStatesTheSubThresholdClassAsWholeLargePurchases() {
        let smalls = (0..<10).map { i in
            entry(id: "s\(i)", amount: 1_500, day: "2026-09-0\((i % 9) + 1)")
        }
        let bigs = [
            entry(id: "b1", amount: 20_000, day: "2026-08-10"),
            entry(id: "b2", amount: 10_000, day: "2026-08-11"),
        ]
        let k = leak(ledgerWith(smalls + bigs), "2026-09-20")
        XCTAssertEqual(k.count, 10)
        XCTAssertEqual(k.sum, 15_000)
        XCTAssertEqual(k.divisor, 15_000)
        XCTAssertEqual(k.equivalent, 1.0, accuracy: 1e-5)
    }
}

final class RegretTests: XCTestCase {
    func testWithholdsTheRateUntilTheSampleIsLargeEnoughToMeanAnything() {
        let few = (0..<5).map { i in entry(id: "j\(i)", amount: 1_000, day: "2026-09-01") }
        let L = fold(
            few.enumerated().map { i, e in ev("a\(i)", H(10 + i), .entryAdd(entry: e)) }
                + few.enumerated().map { i, e in
                    ev("r\(i)", H(100 + i), .reviewJudge(target: e.id, worthIt: false))
                }
        )
        let r = regret(L, "2026-09-20")
        XCTAssertEqual(r.judged, 5)
        XCTAssertNil(r.rate)
        XCTAssertEqual(r.year, 5_000)
    }
}

final class CoolingTests: XCTestCase {
    // The shared vectors in design/fixtures/money.json are asserted by
    // ParityTests; what is left to prove is the shape between them — one step
    // per ¥100 with no cliff at any price a person might arrange themselves
    // around, and no way out of the 1–14 day range.
    func testScalesContinuouslyWithPriceWithNoCliffToGame() {
        XCTAssertEqual(coolingDays(10_000), 1)
        XCTAssertEqual(coolingDays(10_001), 2)
        // ¥999 and ¥1,001 differ by a day at most, never by a week.
        XCTAssertLessThanOrEqual(coolingDays(100_100) - coolingDays(99_900), 1)

        var previous = 0
        for priceFen in stride(from: 0, through: 400_000, by: 137) {
            let days = coolingDays(priceFen)
            XCTAssertGreaterThanOrEqual(days, previous)
            XCTAssertLessThanOrEqual(days - previous, 1)
            XCTAssertGreaterThanOrEqual(days, 1)
            XCTAssertLessThanOrEqual(days, 14)
            previous = days
        }
    }
}

final class DetectRecurringTests: XCTestCase {
    func testFindsAMonthlyChargeAndIgnoresAnIrregularOne() {
        let monthly = ["2026-05-14", "2026-06-14", "2026-07-14", "2026-08-14", "2026-09-14"]
            .enumerated()
            .map { i, day in
                entry(id: "m\(i)", amount: 2_500, categoryId: "sub", merchant: "Netflix", day: day)
            }
        let noisy = ["2026-06-02", "2026-07-19", "2026-09-03"]
            .enumerated()
            .map { i, day in entry(id: "n\(i)", amount: 3_300, merchant: "Random Cafe", day: day) }

        let found = detectRecurring(ledgerWith(monthly + noisy), "2026-09-20")
        XCTAssertEqual(found.map(\.name), ["Netflix"])
        XCTAssertEqual(found.first?.period, .month)
        XCTAssertEqual(found.first?.amount, 2_500)
        XCTAssertEqual(found.first?.occurrences, 5)
        XCTAssertEqual(found.first?.nextChargeAt, "2026-10-14")
    }

    func testIgnoresASeriesThatStoppedChargingLongAgo() {
        let stale = ["2025-01-10", "2025-02-10", "2025-03-10"]
            .enumerated()
            .map { i, day in entry(id: "s\(i)", amount: 900, merchant: "Old Thing", day: day) }
        XCTAssertTrue(detectRecurring(ledgerWith(stale), "2026-09-20").isEmpty)
    }
}

final class StreakAndMonthStripTests: XCTestCase {
    func testBreaksTheStreakOnADayWithNoDataRatherThanExtendingIt() {
        // 2026-09-18 is logged and under standard; 2026-09-19 is silent.
        let L = ledgerWith([entry(id: "x", amount: 100, day: "2026-09-18")])
        XCTAssertEqual(streak(L, "2026-09-20", noonMs("2026-09-20")), 0)
    }

    func testCountsAnExplicitlyDeclaredZeroSpendDay() {
        let L = fold([
            ev("s", H(1), .standardSet(monthlyFen: 800_000, perCategory: [:], reason: nil)),
            ev("z", H(2), .dayNospend(day: "2026-09-19", on: true)),
        ])
        XCTAssertEqual(streak(L, "2026-09-20", noonMs("2026-09-20")), 1)
    }

    func testDrawsOneBarPerDayWithTheStandardHairline() {
        let s = monthStrip(
            ledgerWith([entry(id: "x", amount: 50_000, day: "2026-09-08")]),
            "2026-09",
            "2026-09-20",
            noonMs("2026-09-20")
        )
        XCTAssertEqual(s.bars.count, 30)
        XCTAssertEqual(s.dailyStandard, 800_000 / 30)
        XCTAssertEqual(s.bars.first { $0.day == "2026-09-08" }?.spent, 50_000)
        XCTAssertEqual(s.bars.first { $0.day == "2026-09-25" }?.future, true)
    }
}

final class StatisticsHelperTests: XCTestCase {
    func testTakesAMedianOfBothParities() {
        XCTAssertEqual(median([3, 1, 2]), 2)
        XCTAssertEqual(median([4, 1, 2, 3]), 3)
        XCTAssertEqual(median([]), 0)
    }

    func testMeasuresSpread() {
        XCTAssertEqual(stddev([5, 5, 5]), 0, accuracy: 1e-12)
        XCTAssertEqual(stddev([1, 3]), 1, accuracy: 1e-12)
    }
}
