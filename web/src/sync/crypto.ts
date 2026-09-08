/**
 * End-to-end encryption for the sync vault.
 *
 * The same ciphertext must be produced and consumed by TypeScript/WebCrypto and
 * by Swift/CommonCrypto+CryptoKit, so every parameter here is fixed by the wire
 * format rather than by a library default. The envelope carries its own header,
 * and that header is the AEAD's additional data, so a tampered iteration count
 * or salt fails the tag check instead of silently deriving a different key.
 *
 *   offset  size  field
 *   0       4     magic 'CBK1'
 *   4       1     version (1)
 *   5       1     kdf id (1 = PBKDF2-HMAC-SHA256)
 *   6       4     iterations, big-endian u32
 *   10      16    salt
 *   26      12    nonce
 *   38      ..    AES-256-GCM ciphertext, 16-byte tag appended
 *
 * AAD = bytes[0..38), i.e. the whole header.
 */

export const MAGIC = new Uint8Array([0x43, 0x42, 0x4b, 0x31]) // 'CBK1'
export const VERSION = 1
export const KDF_PBKDF2_SHA256 = 1
/** OWASP's 2023 floor for PBKDF2-HMAC-SHA256. Roughly 0.4s in a browser, 1s on a phone. */
export const DEFAULT_ITERATIONS = 600_000
const SALT_LEN = 16
const NONCE_LEN = 12
const HEADER_LEN = 4 + 1 + 1 + 4 + SALT_LEN + NONCE_LEN

export class CryptoError extends Error {
  constructor(
    message: string,
    readonly kind: 'wrong-passphrase' | 'corrupt' | 'unsupported',
  ) {
    super(message)
    this.name = 'CryptoError'
  }
}

export interface VaultKey {
  readonly key: CryptoKey
  readonly salt: Uint8Array
  readonly iterations: number
  /** SHA-256 of the raw key, first 8 bytes, as 4 hex quads — shown beside the device list. */
  readonly fingerprint: string
  /**
   * The derived bytes. Kept so the app can offer to remember the key rather
   * than asking for the passphrase on every load. That is a deliberate trade:
   * the threat this design defends against is the vault's host reading the
   * ledger, not someone holding the user's unlocked device.
   */
  readonly raw: Uint8Array
}

const enc = new TextEncoder()
const dec = new TextDecoder()

export function randomBytes(n: number): Uint8Array {
  const b = new Uint8Array(n)
  crypto.getRandomValues(b)
  return b
}

export const toBase64 = (b: Uint8Array): string => {
  let s = ''
  // Chunked to stay well under the argument-count limit on multi-megabyte blobs.
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000))
  return btoa(s)
}

export const fromBase64 = (s: string): Uint8Array => {
  const bin = atob(s.replace(/\s+/g, ''))
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('')

/** '4F2A · 91C7 · 0B3E · D845' — the same key always renders the same way on every device. */
export function formatFingerprint(raw: string): string {
  return (raw.slice(0, 16).toUpperCase().match(/.{1,4}/g) ?? []).join(' · ')
}

export async function deriveKey(
  passphrase: string,
  salt: Uint8Array = randomBytes(SALT_LEN),
  iterations: number = DEFAULT_ITERATIONS,
): Promise<VaultKey> {
  if (salt.length !== SALT_LEN) throw new CryptoError('salt must be 16 bytes', 'corrupt')

  const material = await crypto.subtle.importKey(
    'raw',
    // NFKC so the same passphrase typed on a Mac and on an iPhone keyboard
    // derives the same key even when one composes accents differently.
    enc.encode(passphrase.normalize('NFKC')),
    'PBKDF2',
    false,
    ['deriveBits'],
  )
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: salt as BufferSource, iterations },
    material,
    256,
  )
  return importKeyMaterial(new Uint8Array(bits), salt, iterations)
}

/** Rebuild a VaultKey from remembered bytes, skipping the deliberately slow KDF. */
export async function importKeyMaterial(
  raw: Uint8Array,
  salt: Uint8Array,
  iterations: number,
): Promise<VaultKey> {
  if (raw.length !== 32) throw new CryptoError('key material must be 32 bytes', 'corrupt')
  const key = await crypto.subtle.importKey('raw', raw as BufferSource, 'AES-GCM', false, ['encrypt', 'decrypt'])
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', raw as BufferSource))
  return { key, salt, iterations, fingerprint: hex(digest.subarray(0, 8)), raw }
}

function header(salt: Uint8Array, iterations: number, nonce: Uint8Array): Uint8Array {
  const h = new Uint8Array(HEADER_LEN)
  h.set(MAGIC, 0)
  h[4] = VERSION
  h[5] = KDF_PBKDF2_SHA256
  new DataView(h.buffer).setUint32(6, iterations, false)
  h.set(salt, 10)
  h.set(nonce, 26)
  return h
}

export async function seal(vk: VaultKey, plaintext: string): Promise<Uint8Array> {
  // A fresh 96-bit nonce per message. Never derived, never a counter: a repeated
  // nonce under the same key is the one failure that breaks GCM completely.
  const nonce = randomBytes(NONCE_LEN)
  const head = header(vk.salt, vk.iterations, nonce)
  const body = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonce as BufferSource, additionalData: head as BufferSource, tagLength: 128 },
      vk.key,
      enc.encode(plaintext) as BufferSource,
    ),
  )
  const out = new Uint8Array(head.length + body.length)
  out.set(head, 0)
  out.set(body, head.length)
  return out
}

export interface EnvelopeHeader {
  version: number
  kdf: number
  iterations: number
  salt: Uint8Array
  nonce: Uint8Array
}

/** Read the header without the key — the salt and iteration count live here. */
export function readHeader(envelope: Uint8Array): EnvelopeHeader {
  if (envelope.length < HEADER_LEN + 16) throw new CryptoError('envelope too short', 'corrupt')
  for (let i = 0; i < MAGIC.length; i++) {
    if (envelope[i] !== MAGIC[i]) throw new CryptoError('not a countbook envelope', 'corrupt')
  }
  const version = envelope[4]!
  const kdf = envelope[5]!
  if (version !== VERSION) throw new CryptoError(`envelope version ${version} is newer than this app`, 'unsupported')
  if (kdf !== KDF_PBKDF2_SHA256) throw new CryptoError(`unknown kdf ${kdf}`, 'unsupported')
  return {
    version,
    kdf,
    iterations: new DataView(envelope.buffer, envelope.byteOffset).getUint32(6, false),
    salt: envelope.slice(10, 26),
    nonce: envelope.slice(26, 38),
  }
}

export async function open(vk: VaultKey, envelope: Uint8Array): Promise<string> {
  const h = readHeader(envelope)
  const head = envelope.subarray(0, HEADER_LEN)
  try {
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: h.nonce as BufferSource, additionalData: head as BufferSource, tagLength: 128 },
      vk.key,
      envelope.subarray(HEADER_LEN) as BufferSource,
    )
    return dec.decode(plain)
  } catch {
    // GCM cannot distinguish a wrong key from a corrupted byte, and it does not
    // need to: either way the only useful thing to say is that this passphrase
    // does not open this vault.
    throw new CryptoError('passphrase does not open this vault', 'wrong-passphrase')
  }
}
