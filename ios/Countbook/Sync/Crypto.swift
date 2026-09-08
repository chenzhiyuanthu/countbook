import CommonCrypto
import CryptoKit
import Foundation

/// End-to-end encryption for the sync vault.
///
/// The same ciphertext must be produced and consumed by TypeScript/WebCrypto and
/// by Swift/CommonCrypto+CryptoKit, so every parameter here is fixed by the wire
/// format rather than by a library default. The envelope carries its own header,
/// and that header is the AEAD's additional data, so a tampered iteration count
/// or salt fails the tag check instead of silently deriving a different key.
///
///     offset  size  field
///     0       4     magic 'CBK1'
///     4       1     version (1)
///     5       1     kdf id (1 = PBKDF2-HMAC-SHA256)
///     6       4     iterations, big-endian u32
///     10      16    salt
///     26      12    nonce
///     38      ..    AES-256-GCM ciphertext, 16-byte tag appended
///
/// AAD = bytes[0..38), i.e. the whole header.
let envelopeMagic: [UInt8] = [0x43, 0x42, 0x4b, 0x31] // 'CBK1'
let envelopeVersion: UInt8 = 1
let kdfPBKDF2SHA256: UInt8 = 1
/// OWASP's 2023 floor for PBKDF2-HMAC-SHA256. Roughly 0.4s in a browser, 1s on a phone.
let defaultIterations = 600_000
let envelopeSaltLength = 16
let envelopeNonceLength = 12
let envelopeHeaderLength = 4 + 1 + 1 + 4 + envelopeSaltLength + envelopeNonceLength
private let tagLength = 16

struct CryptoError: Error, Equatable, LocalizedError {
    enum Kind: String, Sendable {
        case wrongPassphrase, corrupt, unsupported
    }

    let kind: Kind
    let message: String

    var errorDescription: String? { message }

    init(_ message: String, _ kind: Kind) {
        self.message = message
        self.kind = kind
    }
}

struct VaultKey: Sendable {
    let key: SymmetricKey
    let salt: Data
    let iterations: Int
    /// SHA-256 of the raw key, first 8 bytes, as 16 hex digits — shown beside the device list.
    let fingerprint: String
    /// The derived bytes. Kept so the app can offer to remember the key rather
    /// than asking for the passphrase on every load. That is a deliberate trade:
    /// the threat this design defends against is the vault's host reading the
    /// ledger, not someone holding the user's unlocked device.
    let raw: Data
}

func randomBytes(_ n: Int) -> Data {
    var g = SystemRandomNumberGenerator()
    var out = Data(count: n)
    for i in 0..<n { out[i] = UInt8.random(in: .min ... .max, using: &g) }
    return out
}

func toBase64(_ b: Data) -> String {
    b.base64EncodedString()
}

func fromBase64(_ s: String) -> Data? {
    Data(base64Encoded: s.filter { !$0.isWhitespace })
}

private func hex(_ b: Data) -> String {
    b.map { String(format: "%02x", $0) }.joined()
}

/// `4F2A · 91C7 · 0B3E · D845` — the same key always renders the same way on every device.
func formatFingerprint(_ raw: String) -> String {
    let upper = Array(raw.prefix(16).uppercased())
    return stride(from: 0, to: upper.count, by: 4)
        .map { String(upper[$0..<min($0 + 4, upper.count)]) }
        .joined(separator: " · ")
}

/// PBKDF2 is slow on purpose, so this hops off whatever actor called it; a
/// 600,000-iteration derivation would otherwise freeze the frame it runs in.
func deriveKey(
    _ passphrase: String,
    salt: Data = randomBytes(envelopeSaltLength),
    iterations: Int = defaultIterations
) async throws -> VaultKey {
    try await Task.detached(priority: .userInitiated) {
        try deriveKeyBlocking(passphrase, salt: salt, iterations: iterations)
    }.value
}

/// The derivation itself, for callers already off the main actor.
func deriveKeyBlocking(
    _ passphrase: String,
    salt: Data,
    iterations: Int = defaultIterations
) throws -> VaultKey {
    guard salt.count == envelopeSaltLength else { throw CryptoError("salt must be 16 bytes", .corrupt) }
    guard iterations > 0 else { throw CryptoError("iteration count must be positive", .corrupt) }
    return try importKeyMaterial(pbkdf2(passphrase, salt: salt, iterations: iterations),
                                 salt: salt, iterations: iterations)
}

/// Rebuild a VaultKey from remembered bytes, skipping the deliberately slow KDF.
func importKeyMaterial(_ raw: Data, salt: Data, iterations: Int) throws -> VaultKey {
    guard raw.count == 32 else { throw CryptoError("key material must be 32 bytes", .corrupt) }
    let digest = Data(SHA256.hash(data: raw))
    return VaultKey(
        key: SymmetricKey(data: raw),
        salt: salt,
        iterations: iterations,
        fingerprint: hex(digest.prefix(8)),
        raw: raw
    )
}

// Normalised before derivation so the same passphrase typed on a Mac and on an
// iPhone keyboard derives the same key even when one composes accents differently.
private func pbkdf2(_ passphrase: String, salt: Data, iterations: Int) throws -> Data {
    let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
    var derived = Data(count: 32)
    let status = derived.withUnsafeMutableBytes { out -> Int32 in
        salt.withUnsafeBytes { saltBytes -> Int32 in
            password.withUnsafeBytes { pw -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pw.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    out.baseAddress!.assumingMemoryBound(to: UInt8.self), 32
                )
            }
        }
    }
    guard status == kCCSuccess else { throw CryptoError("key derivation failed", .corrupt) }
    return derived
}

private func header(salt: Data, iterations: Int, nonce: Data) -> Data {
    var h = Data(capacity: envelopeHeaderLength)
    h.append(contentsOf: envelopeMagic)
    h.append(envelopeVersion)
    h.append(kdfPBKDF2SHA256)
    let n = UInt32(truncatingIfNeeded: iterations)
    h.append(contentsOf: [UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)])
    h.append(salt)
    h.append(nonce)
    return h
}

func seal(_ vk: VaultKey, _ plaintext: String) throws -> Data {
    // A fresh 96-bit nonce per message. Never derived, never a counter: a repeated
    // nonce under the same key is the one failure that breaks GCM completely.
    let nonce = randomBytes(envelopeNonceLength)
    let head = header(salt: vk.salt, iterations: vk.iterations, nonce: nonce)
    do {
        let box = try AES.GCM.seal(
            Data(plaintext.utf8),
            using: vk.key,
            nonce: try AES.GCM.Nonce(data: nonce),
            authenticating: head
        )
        return head + box.ciphertext + box.tag
    } catch {
        throw CryptoError("could not seal the envelope", .corrupt)
    }
}

struct EnvelopeHeader: Equatable, Sendable {
    let version: UInt8
    let kdf: UInt8
    let iterations: Int
    let salt: Data
    let nonce: Data
}

/// Read the header without the key — the salt and iteration count live here.
func readHeader(_ envelope: Data) throws -> EnvelopeHeader {
    // Re-based so a slice handed in by a caller indexes from zero like the web's does.
    let e = Data(envelope)
    guard e.count >= envelopeHeaderLength + tagLength else { throw CryptoError("envelope too short", .corrupt) }
    guard Array(e.prefix(4)) == envelopeMagic else { throw CryptoError("not a countbook envelope", .corrupt) }
    let version = e[4]
    let kdf = e[5]
    guard version == envelopeVersion else {
        throw CryptoError("envelope version \(version) is newer than this app", .unsupported)
    }
    guard kdf == kdfPBKDF2SHA256 else { throw CryptoError("unknown kdf \(kdf)", .unsupported) }
    let iterations = Int(e[6]) << 24 | Int(e[7]) << 16 | Int(e[8]) << 8 | Int(e[9])
    return EnvelopeHeader(
        version: version,
        kdf: kdf,
        iterations: iterations,
        salt: e.subdata(in: 10..<26),
        nonce: e.subdata(in: 26..<38)
    )
}

func open(_ vk: VaultKey, _ envelope: Data) throws -> String {
    let e = Data(envelope)
    let h = try readHeader(e)
    let head = e.prefix(envelopeHeaderLength)
    let body = e.dropFirst(envelopeHeaderLength)
    do {
        let box = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: h.nonce),
            ciphertext: body.dropLast(tagLength),
            tag: body.suffix(tagLength)
        )
        // Lossy on purpose: WebCrypto's TextDecoder substitutes too, and a
        // difference here would only ever appear after the tag already passed.
        return String(decoding: try AES.GCM.open(box, using: vk.key, authenticating: head), as: UTF8.self)
    } catch {
        // GCM cannot distinguish a wrong key from a corrupted byte, and it does not
        // need to: either way the only useful thing to say is that this passphrase
        // does not open this vault.
        throw CryptoError("passphrase does not open this vault", .wrongPassphrase)
    }
}
