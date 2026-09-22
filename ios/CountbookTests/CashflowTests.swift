import XCTest
@testable import Countbook

private func H(_ wall: Int, _ counter: Int = 0, _ device: String = "aa") -> String {
    encode(Hlc(wall: wall, counter: counter, device: device))
}

private func ev(_ id: String, _ hlc: String, _ payload: Payload) -> Event {
    Event(id: id, hlc: hlc, dev: decode(hlc).device, payload: payload)
}

/// design/fixtures/fx.json is a shared acceptance test: the web client asserts
/// against the same vectors, so a rounding difference between the two
/// platforms fails a build rather than shipping as a 分 that only one side sees.
private struct FxFixtures: Decodable {
    struct ConvertCase: Decodable {
        let amount: Fen
        let rateMicro: Int
        let out: Fen
    }

    struct RateCase: Decodable {
        let rateMicro: Int
        let out: String
    }

    let convert: [ConvertCase]
    let formatRate: [RateCase]
}

private func income(
    id: String, amount: Fen, categoryId: String, day: Day, original: ForeignAmount? = nil
) -> Entry {
    Entry(
        id: id, kind: .income, amount: amount, currency: "CNY", categoryId: categoryId,
        intent: nil, note: "", merchant: "", day: day, createdAt: 1_760_000_000_000, original: original
    )
}

private func spend(id: String, amount: Fen, day: Day) -> Entry {
    Entry(
        id: id, kind: .spend, amount: amount, currency: "CNY", categoryId: "food",
        intent: .want, note: "", merchant: "", day: day, createdAt: 1_760_000_000_000
    )
}

final class CashflowTests: XCTestCase {
    private static let fx: FxFixtures = {
        guard let url = Bundle(for: CashflowTests.self).url(forResource: "fx", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FxFixtures.self, from: data)
        else { fatalError("design/fixtures/fx.json is missing from the test bundle") }
        return decoded
    }()

    private let receipt = ForeignAmount(currency: "USD", amount: 120_000, rateMicro: 7_123_400)

    private var ledger: Ledger {
        fold([
            ev("s", H(1), .standardSet(monthlyFen: 800_000, perCategory: [:], reason: nil)),
            ev("a", H(10), .entryAdd(entry: spend(id: "a", amount: 30_000, day: "2026-09-03"))),
            ev("b", H(11), .entryAdd(entry: spend(id: "b", amount: 20_000, day: "2026-09-15"))),
            ev("c", H(12), .entryAdd(entry: spend(id: "c", amount: 50_000, day: "2026-08-15"))),
            ev("i1", H(13), .entryAdd(entry: income(id: "i1", amount: 854_808, categoryId: "stock", day: "2026-09-10", original: receipt))),
            ev("i2", H(14), .entryAdd(entry: income(id: "i2", amount: 1_000_000, categoryId: "salary", day: "2026-09-01"))),
            ev("i3", H(15), .entryAdd(entry: income(id: "i3", amount: 10_000, categoryId: "stock", day: "2026-08-02"))),
        ])
    }

    func testConvertsForeignMinorUnitsIdenticallyToTheWebClient() {
        for f in Self.fx.convert {
            XCTAssertEqual(convert(f.amount, rateMicro: f.rateMicro), f.out, "convert(\(f.amount), \(f.rateMicro))")
        }
        for f in Self.fx.formatRate {
            XCTAssertEqual(formatRate(f.rateMicro), f.out, "formatRate(\(f.rateMicro))")
        }
    }

    func testParsesATypedRateAndRejectsWhatIsNotOne() {
        XCTAssertEqual(parseRate("7.1234"), 7_123_400)
        XCTAssertEqual(parseRate("0.0431"), 43_100)
        XCTAssertEqual(parseRate("7"), 7_000_000)
        XCTAssertNil(parseRate("0"))
        XCTAssertNil(parseRate(""))
        XCTAssertNil(parseRate("7,1"))
        XCTAssertNil(parseRate("-1"))
    }

    func testTotalsIncomeSpendingAndTheDifferenceInTheHomeCurrency() {
        let m = cashflowOfMonth(ledger, "2026-09")
        XCTAssertEqual(m.income, 1_854_808)
        XCTAssertEqual(m.spend, 50_000)
        XCTAssertEqual(m.net, 1_804_808)
        XCTAssertEqual(m.incomeByCategory, [
            IncomeRow(categoryId: "salary", amount: 1_000_000, count: 1),
            IncomeRow(categoryId: "stock", amount: 854_808, count: 1),
        ])
    }

    func testCountsALossAsANegativeResultNeverAsSpending() {
        let L = fold([
            ev("s", H(1), .standardSet(monthlyFen: 800_000, perCategory: [:], reason: nil)),
            ev("g", H(2), .entryAdd(entry: income(id: "g", amount: 50_000, categoryId: "stock", day: "2026-09-02"))),
            ev("l", H(3), .entryAdd(entry: income(id: "l", amount: -80_000, categoryId: "fund", day: "2026-09-03"))),
            ev("x", H(4), .entryAdd(entry: spend(id: "x", amount: 10_000, day: "2026-09-04"))),
        ])
        let m = cashflowOfMonth(L, "2026-09")
        XCTAssertEqual(m.income, -30_000)
        XCTAssertEqual(m.spend, 10_000)
        XCTAssertEqual(m.net, -40_000)
        XCTAssertEqual(m.incomeByCategory.map { [$0.categoryId, String($0.amount)] }, [["stock", "50000"], ["fund", "-80000"]])
        let noon = Int(fromDay("2026-09-20").addingTimeInterval(12 * 3600).timeIntervalSince1970 * 1000)
        XCTAssertEqual(available(L, "2026-09-20", noon).spent, 10_000)
        XCTAssertEqual(format(-80_000), "−¥800.00")
    }

    func testSumsTheYearAndKeepsIncomeOutOfAvailable() {
        let y = cashflowOfYear(ledger, "2026")
        XCTAssertEqual(y.income, 1_864_808)
        XCTAssertEqual(y.spend, 100_000)
        XCTAssertEqual(y.net, 1_764_808)
        let noon = Int(fromDay("2026-09-20").addingTimeInterval(12 * 3600).timeIntervalSince1970 * 1000)
        XCTAssertEqual(available(ledger, "2026-09-20", noon).spent, 50_000)
    }

    func testCarriesTheReceiptThroughTheFoldAndTheWire() throws {
        XCTAssertEqual(ledger.entries["i1"]?.original, receipt)
        // The wire shape the web client writes and reads: `original` beside `amount`.
        let entry = income(id: "w", amount: 854_808, categoryId: "stock", day: "2026-09-10", original: receipt)
        let data = try JSONEncoder().encode(entry)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let original = try XCTUnwrap(json["original"] as? [String: Any])
        XCTAssertEqual(original["currency"] as? String, "USD")
        XCTAssertEqual(original["amount"] as? Int, 120_000)
        XCTAssertEqual(original["rateMicro"] as? Int, 7_123_400)
        XCTAssertEqual(try JSONDecoder().decode(Entry.self, from: data), entry)
        // An entry without one stays exactly as it was on the wire before.
        let plain = try JSONEncoder().encode(spend(id: "p", amount: 1, day: "2026-09-01"))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("original"))
    }
}

final class ReceiptCorrectionTests: XCTestCase {
    func testACorrectionRestatesTheReceiptAndTheFigureFollowsIt() throws {
        let first = ForeignAmount(currency: "USD", amount: 120_000, rateMicro: 7_123_400)
        let second = ForeignAmount(currency: "USD", amount: 125_000, rateMicro: 7_123_400)
        let x = Entry(
            id: "x", kind: .income, amount: 854_808, currency: "CNY", categoryId: "stock",
            intent: nil, note: "", merchant: "", day: "2026-08-10", createdAt: 1_760_000_000_000, original: first
        )
        let L = fold([
            ev("s", H(1), .standardSet(monthlyFen: 800_000, perCategory: [:], reason: nil)),
            ev("a", H(2), .entryAdd(entry: x)),
            ev("c", H(3), .entryCorrect(target: "x", amount: 890_425, reason: "券商汇率", original: second)),
        ])
        let e = try XCTUnwrap(effective(L)["x"])
        XCTAssertEqual(e.effective, 890_425)
        XCTAssertEqual(e.original, second)
        XCTAssertEqual(L.entries["x"]?.original, first) // the row as first printed
        XCTAssertEqual(cashflowOfMonth(L, "2026-08").income, 890_425)

        // The wire shape the web client writes: `original` beside `amount` on entry.correct.
        let event = ev("c", H(3), .entryCorrect(target: "x", amount: 890_425, reason: "r", original: second))
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["original"] as? [String: Any])?["amount"] as? Int, 125_000)
        XCTAssertEqual(try JSONDecoder().decode(Event.self, from: data), event)

        // A patch can restate the receipt too, and one without leaves it alone.
        let patched = fold([
            ev("a", H(2), .entryAdd(entry: x)),
            ev("p", H(3), .entryPatch(target: "x", patch: EntryPatch(amount: 890_425, original: second))),
            ev("q", H(4), .entryPatch(target: "x", patch: EntryPatch(note: "n"))),
        ])
        XCTAssertEqual(patched.entries["x"]?.original, second)
        XCTAssertEqual(patched.entries["x"]?.amount, 890_425)
    }
}
