import { describe, expect, it } from 'vitest'
import { webcrypto } from 'node:crypto'
import {
  CryptoError, DEFAULT_ITERATIONS, deriveKey, formatFingerprint, fromBase64, open, readHeader, seal, toBase64,
} from './crypto'

// Node exposes WebCrypto under a different global than the browser does.
if (!globalThis.crypto) Object.defineProperty(globalThis, 'crypto', { value: webcrypto })

// The real iteration count is deliberately slow; the tests exercise the format,
// not the KDF's cost, so they use a low count and assert the count separately.
const FAST = 1000
const salt = new Uint8Array(16).fill(7)

describe('vault envelope', () => {
  it('round-trips', async () => {
    const k = await deriveKey('correct horse battery staple', salt, FAST)
    const box = await seal(k, '{"hello":"世界"}')
    expect(await open(k, box)).toBe('{"hello":"世界"}')
  })

  it('lays the header out exactly as the wire format says', async () => {
    const k = await deriveKey('pw', salt, FAST)
    const box = await seal(k, 'x')
    expect(Array.from(box.subarray(0, 4))).toEqual([0x43, 0x42, 0x4b, 0x31])
    expect(box[4]).toBe(1)
    expect(box[5]).toBe(1)
    const h = readHeader(box)
    expect(h.iterations).toBe(FAST)
    expect(Array.from(h.salt)).toEqual(Array.from(salt))
    expect(h.nonce).toHaveLength(12)
    // header + tag + one byte of plaintext
    expect(box.length).toBe(38 + 16 + 1)
  })

  it('rejects a wrong passphrase cleanly', async () => {
    const good = await deriveKey('right', salt, FAST)
    const bad = await deriveKey('wrong', salt, FAST)
    const box = await seal(good, 'secret')
    await expect(open(bad, box)).rejects.toMatchObject({ kind: 'wrong-passphrase' })
  })

  it('detects a tampered header rather than deriving a different key', async () => {
    const k = await deriveKey('pw', salt, FAST)
    const box = await seal(k, 'secret')
    box[9] = (box[9]! ^ 0xff) & 0xff // flip a byte of the iteration count
    await expect(open(k, box)).rejects.toBeInstanceOf(CryptoError)
  })

  it('detects a tampered ciphertext', async () => {
    const k = await deriveKey('pw', salt, FAST)
    const box = await seal(k, 'secret secret secret')
    box[45] = (box[45]! ^ 0x01) & 0xff
    await expect(open(k, box)).rejects.toMatchObject({ kind: 'wrong-passphrase' })
  })

  it('refuses an envelope from a future version', async () => {
    const k = await deriveKey('pw', salt, FAST)
    const box = await seal(k, 'x')
    box[4] = 2
    expect(() => readHeader(box)).toThrow(/newer than this app/)
  })

  it('uses a fresh nonce every time', async () => {
    const k = await deriveKey('pw', salt, FAST)
    const nonces = new Set<string>()
    for (let i = 0; i < 50; i++) nonces.add(toBase64((await seal(k, 'same plaintext')).subarray(26, 38)))
    expect(nonces.size).toBe(50)
  })

  it('derives the same key from the same passphrase and salt', async () => {
    const a = await deriveKey('同一个密码', salt, FAST)
    const b = await deriveKey('同一个密码', salt, FAST)
    expect(a.fingerprint).toBe(b.fingerprint)
    expect(await open(b, await seal(a, 'shared'))).toBe('shared')
  })

  it('normalises the passphrase so two keyboards agree', async () => {
    // U+00E9 vs U+0065 U+0301 — the same character, composed differently.
    const a = await deriveKey('café', salt, FAST)
    const b = await deriveKey('café', salt, FAST)
    expect(a.fingerprint).toBe(b.fingerprint)
  })

  it('renders a fingerprint people can compare across devices', async () => {
    const k = await deriveKey('pw', salt, FAST)
    expect(formatFingerprint(k.fingerprint)).toMatch(/^[0-9A-F]{4}( · [0-9A-F]{4}){3}$/)
  })

  it('ships a real iteration count', () => {
    expect(DEFAULT_ITERATIONS).toBeGreaterThanOrEqual(600_000)
  })

  it('base64 survives a multi-megabyte blob', () => {
    const big = new Uint8Array(3_000_000).map((_, i) => i & 0xff)
    expect(Array.from(fromBase64(toBase64(big)).subarray(0, 4))).toEqual([0, 1, 2, 3])
    expect(fromBase64(toBase64(big)).length).toBe(big.length)
  })
})
