import XCTest
@testable import Countbook

/// design/fixtures/envelope.json is a shared acceptance test: web/src/sync/crypto.test.ts
/// opens the envelope this client sealed, and these tests open the one the web
/// client sealed. Either platform drifting from the wire format fails a build.
private struct EnvelopeFixture: Decodable {
    let passphrase: String
    let saltBase64: String
    let iterations: Int
    let plaintext: String
    let fingerprint: String
    let fromWeb: String
    let fromSwift: String
}

final class CryptoTests: XCTestCase {
    // The shipping iteration count is deliberately slow; these tests exercise the
    // format, not the KDF's cost, so they use a low count and assert the default
    // separately.
    private let fast = 1000
    private let salt = Data(repeating: 7, count: 16)

    // MARK: envelope

    func testRoundTrips() async throws {
        let k = try await deriveKey("correct horse battery staple", salt: salt, iterations: fast)
        let box = try seal(k, "{\"hello\":\"世界\"}")
        XCTAssertEqual(try open(k, box), "{\"hello\":\"世界\"}")
    }

    func testLaysTheHeaderOutExactlyAsTheWireFormatSays() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        let box = try seal(k, "x")
        XCTAssertEqual(Array(box.prefix(4)), [0x43, 0x42, 0x4b, 0x31])
        XCTAssertEqual(box[4], 1)
        XCTAssertEqual(box[5], 1)
        let h = try readHeader(box)
        XCTAssertEqual(h.iterations, fast)
        XCTAssertEqual(h.salt, salt)
        XCTAssertEqual(h.nonce.count, 12)
        // header + tag + one byte of plaintext
        XCTAssertEqual(box.count, 38 + 16 + 1)
        XCTAssertEqual(envelopeHeaderLength, 38)
    }

    func testRejectsAWrongPassphraseCleanly() async throws {
        let good = try await deriveKey("right", salt: salt, iterations: fast)
        let bad = try await deriveKey("wrong", salt: salt, iterations: fast)
        let box = try seal(good, "secret")
        assertCryptoError(.wrongPassphrase) { _ = try open(bad, box) }
    }

    func testDetectsATamperedHeaderRatherThanDerivingADifferentKey() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        var box = try seal(k, "secret")
        box[9] ^= 0xff // flip a byte of the iteration count
        XCTAssertNotEqual(try readHeader(box).iterations, fast)
        assertCryptoError(.wrongPassphrase) { _ = try open(k, box) }
    }

    func testDetectsATamperedCiphertext() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        var box = try seal(k, "secret secret secret")
        box[45] ^= 0x01
        assertCryptoError(.wrongPassphrase) { _ = try open(k, box) }
    }

    func testDetectsATamperedTag() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        var box = try seal(k, "secret")
        box[box.count - 1] ^= 0x01
        assertCryptoError(.wrongPassphrase) { _ = try open(k, box) }
    }

    func testRefusesAnEnvelopeItCannotUnderstand() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        let box = try seal(k, "x")

        var future = box
        future[4] = 2
        assertCryptoError(.unsupported) { _ = try readHeader(future) }

        var otherKdf = box
        otherKdf[5] = 9
        assertCryptoError(.unsupported) { _ = try readHeader(otherKdf) }

        var alien = box
        alien[0] = 0x44
        assertCryptoError(.corrupt) { _ = try readHeader(alien) }

        assertCryptoError(.corrupt) { _ = try readHeader(box.prefix(50)) }
    }

    func testUsesAFreshNonceEveryTime() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        var nonces = Set<Data>()
        for _ in 0..<50 { nonces.insert(try seal(k, "same plaintext").subdata(in: 26..<38)) }
        XCTAssertEqual(nonces.count, 50)
    }

    // MARK: keys

    func testDerivesTheSameKeyFromTheSamePassphraseAndSalt() async throws {
        let a = try await deriveKey("同一个密码", salt: salt, iterations: fast)
        let b = try await deriveKey("同一个密码", salt: salt, iterations: fast)
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(try open(b, try seal(a, "shared")), "shared")
    }

    func testNormalisesThePassphraseSoTwoKeyboardsAgree() async throws {
        // U+00E9 vs U+0065 U+0301 — the same character, composed differently.
        let a = try await deriveKey("caf\u{00e9}", salt: salt, iterations: fast)
        let b = try await deriveKey("cafe\u{0301}", salt: salt, iterations: fast)
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(try open(b, try seal(a, "shared")), "shared")
    }

    func testARememberedKeySkipsTheDerivation() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        let remembered = try importKeyMaterial(k.raw, salt: k.salt, iterations: k.iterations)
        XCTAssertEqual(remembered.fingerprint, k.fingerprint)
        XCTAssertEqual(try open(remembered, try seal(k, "remembered")), "remembered")
        assertCryptoError(.corrupt) { _ = try importKeyMaterial(Data(repeating: 0, count: 16),
                                                                salt: self.salt, iterations: self.fast) }
    }

    func testRejectsASaltThatIsNotSixteenBytes() async {
        do {
            _ = try await deriveKey("pw", salt: Data(repeating: 1, count: 8), iterations: fast)
            XCTFail("expected a corrupt-salt error")
        } catch let error as CryptoError {
            XCTAssertEqual(error.kind, .corrupt)
        } catch {
            XCTFail("expected CryptoError, got \(error)")
        }
    }

    func testRendersAFingerprintPeopleCanCompareAcrossDevices() async throws {
        let k = try await deriveKey("pw", salt: salt, iterations: fast)
        XCTAssertEqual(k.fingerprint.count, 16)
        let shown = formatFingerprint(k.fingerprint)
        XCTAssertNotNil(shown.range(of: "^[0-9A-F]{4}( · [0-9A-F]{4}){3}$", options: .regularExpression),
                        shown)
        XCTAssertEqual(formatFingerprint("4f2a91c70b3ed845"), "4F2A · 91C7 · 0B3E · D845")
    }

    func testShipsARealIterationCount() {
        XCTAssertGreaterThanOrEqual(defaultIterations, 600_000)
    }

    func testBase64SurvivesALargeBlob() throws {
        let big = Data((0..<300_000).map { UInt8($0 & 0xff) })
        let round = try XCTUnwrap(fromBase64(toBase64(big)))
        XCTAssertEqual(round, big)
        XCTAssertEqual(try XCTUnwrap(fromBase64("  Q0JL\nMQ== ")), Data([0x43, 0x42, 0x4b, 0x31]))
    }

    // MARK: cross-platform

    func testOpensAnEnvelopeSealedByTheWebClient() async throws {
        let fx = try Self.fixture()
        let k = try await deriveKey(fx.passphrase,
                                    salt: try XCTUnwrap(fromBase64(fx.saltBase64)),
                                    iterations: fx.iterations)
        XCTAssertEqual(k.fingerprint, fx.fingerprint)
        XCTAssertEqual(try open(k, try XCTUnwrap(fromBase64(fx.fromWeb))), fx.plaintext)
    }

    func testStillSealsTheEnvelopeTheWebTestsOpen() async throws {
        let fx = try Self.fixture()
        let k = try await deriveKey(fx.passphrase,
                                    salt: try XCTUnwrap(fromBase64(fx.saltBase64)),
                                    iterations: fx.iterations)
        let published = try XCTUnwrap(fromBase64(fx.fromSwift))
        XCTAssertEqual(try open(k, published), fx.plaintext)
        // The nonce differs every time, so parity is asserted on the header and
        // the length rather than on the whole envelope.
        let fresh = try seal(k, fx.plaintext)
        XCTAssertEqual(fresh.count, published.count)
        XCTAssertEqual(fresh.prefix(26), published.prefix(26))
    }

    // MARK: -

    private static func fixture() throws -> EnvelopeFixture {
        // Preferred from the test bundle; the source tree is the fallback for a
        // runner whose resources were not copied.
        let bundled = Bundle(for: CryptoTests.self).url(forResource: "envelope", withExtension: "json")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("design/fixtures/envelope.json")
        let url = bundled ?? source
        return try JSONDecoder().decode(EnvelopeFixture.self, from: try Data(contentsOf: url))
    }

    private func assertCryptoError(
        _ kind: CryptoError.Kind,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard let error = error as? CryptoError else {
                return XCTFail("expected CryptoError, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(error.kind, kind, file: file, line: line)
        }
    }
}
