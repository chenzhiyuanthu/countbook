import XCTest
@testable import Countbook

private func H(_ wall: Int, _ ctr: Int = 0, _ dev: String = "aa") -> String {
    encode(Hlc(wall: wall, counter: ctr, device: dev))
}

private func ev(_ id: String, _ hlc: String, _ p: Payload) -> Event {
    Event(id: id, hlc: hlc, dev: decode(hlc).device, payload: p)
}

private func entry(
    id: String = "e1",
    amount: Fen = 10_000,
    note: String = "",
    day: Day = "2026-09-08"
) -> Entry {
    Entry(
        id: id,
        kind: .spend,
        amount: amount,
        currency: "CNY",
        categoryId: "food",
        intent: .want,
        note: note,
        merchant: "",
        day: day,
        createdAt: 1_760_000_000_000
    )
}

final class MergeTests: XCTestCase {
    private let a: [Event] = [
        ev("1", H(100), .entryAdd(entry: entry())),
        ev("2", H(200), .entryPatch(target: "e1", patch: EntryPatch(note: "from A"))),
    ]
    private let b: [Event] = [
        ev("1", H(100), .entryAdd(entry: entry())),
        ev("3", H(300), .entryPatch(target: "e1", patch: EntryPatch(note: "from B"))),
    ]

    func testIsCommutativeAssociativeAndIdempotent() {
        let ab = merge(a, b)
        let ba = merge(b, a)
        XCTAssertEqual(ab.map(\.id), ba.map(\.id))
        XCTAssertEqual(merge(ab, ab).map(\.id), ab.map(\.id))
        XCTAssertEqual(merge(merge(a, b), []).map(\.id), merge(a, merge(b, [])).map(\.id))
    }

    func testResolvesAConcurrentEditByLastWriterPerField() {
        let L = fold(merge(a, b))
        XCTAssertEqual(L.entries["e1"]?.note, "from B")
    }

    func testLetsADeleteWinOverAnEditThatDidNotSeeIt() {
        let withDelete = merge(a, [ev("9", H(250), .entryRemove(target: "e1"))])
        let L = fold(merge(withDelete, b))
        XCTAssertNil(L.entries["e1"])
        XCTAssertTrue(L.tombstones.contains("e1"))
    }

    func testDoesNotResurrectADeletedEntryWhenAnOldAddArrivesLate() {
        let deleted = [ev("9", H(250), .entryRemove(target: "e1"))]
        let lateAdd = [ev("1", H(100), .entryAdd(entry: entry()))]
        XCTAssertNil(fold(sort(merge(deleted, lateAdd))).entries["e1"])
    }

    func testFoldsAWeekLateDeviceToTheSameStateAsTheDeviceThatWasOnline() {
        XCTAssertEqual(fold(merge(a, b)).entries, fold(merge(b, a)).entries)
    }
}

final class CorrectionTests: XCTestCase {
    func testLeavesTheOriginalPrintedAndUsesTheCorrectedAmountInTotals() {
        let L = fold([
            ev("1", H(100), .entryAdd(entry: entry(amount: 28_800))),
            ev("2", H(200), .entryCorrect(target: "e1", amount: 8_800, reason: "记错了")),
        ])
        XCTAssertEqual(L.entries["e1"]?.amount, 28_800)
        XCTAssertEqual(effective(L)["e1"]?.effective, 8_800)
        XCTAssertEqual(L.corrections.count, 1)
    }

    func testZeroesAVoidedRowWithoutDeletingIt() {
        let L = fold([
            ev("1", H(100), .entryAdd(entry: entry())),
            ev("2", H(200), .entryVoid(target: "e1", reason: "重复")),
        ])
        XCTAssertNotNil(L.entries["e1"])
        XCTAssertEqual(effective(L)["e1"]?.effective, 0)
    }

    func testRecordsNotWorthItOnceTheDeferralLimitIsReached() {
        let L = fold([
            ev("1", H(100), .entryAdd(entry: entry())),
            ev("2", H(200), .reviewDefer(target: "e1")),
            ev("3", H(300), .reviewDefer(target: "e1")),
            ev("4", H(400), .reviewDefer(target: "e1")),
        ])
        XCTAssertEqual(L.entries["e1"]?.worthIt, false)
    }
}

final class EventWireFormatTests: XCTestCase {
    /// Copied from what the TypeScript client writes: the envelope and the
    /// payload share one flat object, discriminated by `t`.
    private let samples = [
        """
        {"id":"1","hlc":"0000000000000064-0000-aa","dev":"aa","t":"entry.add",\
        "entry":{"id":"e1","kind":"spend","amount":10000,"currency":"CNY","categoryId":"food",\
        "intent":"want","note":"","merchant":"","day":"2026-09-08","createdAt":1760000000000}}
        """,
        """
        {"id":"2","hlc":"00000000000000c8-0000-aa","dev":"aa","t":"entry.patch",\
        "target":"e1","patch":{"note":"from B"}}
        """,
        """
        {"id":"3","hlc":"000000000000012c-0000-aa","dev":"aa","t":"entry.correct",\
        "target":"e1","amount":8800,"reason":"记错了"}
        """,
        """
        {"id":"4","hlc":"0000000000000190-0000-aa","dev":"aa","t":"review.judge",\
        "target":"e1","worthIt":false}
        """,
        """
        {"id":"5","hlc":"00000000000001f4-0000-aa","dev":"aa","t":"sub.status",\
        "target":"s1","status":"pending-cancel","day":"2026-09-20"}
        """,
        """
        {"id":"6","hlc":"0000000000000258-0000-aa","dev":"aa","t":"standard.set",\
        "monthlyFen":800000,"perCategory":{"food":200000}}
        """,
        """
        {"id":"7","hlc":"00000000000002bc-0000-aa","dev":"aa","t":"day.nospend",\
        "day":"2026-09-19","on":true}
        """,
    ]

    func testRoundTripsTheTypeScriptWireShape() throws {
        for json in samples {
            let data = Data(json.utf8)
            let event = try JSONDecoder().decode(Event.self, from: data)
            let reencoded = try JSONEncoder().encode(event)
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary,
                try JSONSerialization.jsonObject(with: data) as? NSDictionary,
                json
            )
        }
    }

    func testDiscriminatesTheDecodedVariant() throws {
        let event = try JSONDecoder().decode(Event.self, from: Data(samples[0].utf8))
        guard case .entryAdd(let e) = event.payload else { return XCTFail("expected entry.add") }
        XCTAssertEqual(e.amount, 10_000)
        XCTAssertEqual(e.intent, .want)
        XCTAssertEqual(event.hlc, H(100))
    }

    func testRejectsAnUnknownVariant() {
        let json = #"{"id":"x","hlc":"0000000000000001-0000-aa","dev":"aa","t":"txn.create"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Event.self, from: Data(json.utf8)))
    }

    func testCompactionKeepsTheTombstoneAndDropsSupersededPatches() {
        let events = [
            ev("1", H(100), .entryAdd(entry: entry())),
            ev("2", H(200), .entryPatch(target: "e1", patch: EntryPatch(note: "gone"))),
            ev("3", H(300), .entryRemove(target: "e1")),
            ev("4", H(400), .settingsPatch(patch: SettingsPatch(leakCeilingFen: 2_000))),
            ev("5", H(500), .settingsPatch(patch: SettingsPatch(reckoningHour: 21))),
        ]
        let out = compact(events, before: H(900))
        XCTAssertEqual(out.map(\.id), ["3", "5"])
        XCTAssertEqual(fold(out).settings.leakCeilingFen, 2_000)
        XCTAssertEqual(fold(out).settings.reckoningHour, 21)
    }
}
