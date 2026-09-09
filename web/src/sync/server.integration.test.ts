import { beforeAll, describe, expect, it } from 'vitest'
import { webcrypto } from 'node:crypto'
import type { Event } from '../core/events'
import { encode } from '../core/hlc'
import { deriveKey, fromBase64, toBase64, type VaultKey } from './crypto'
import { login, readServerManifest, signup, syncServer, writeServerManifest, type ServerConfig } from './server'
import type { Manifest } from './vault'

/**
 * Drives the real self-hosted server over HTTPS, exactly as the app does:
 * signup, derive the vault key from the account password, push an encrypted
 * event, and confirm a second device logs in and reads it back decrypted.
 *
 * Skipped unless COUNTBOOK_SERVER is set, so the normal run stays offline:
 *
 *   COUNTBOOK_SERVER=https://43-162-121-196.sslip.io npm run --prefix web test
 */

if (!globalThis.crypto) Object.defineProperty(globalThis, 'crypto', { value: webcrypto })

const SERVER = process.env.COUNTBOOK_SERVER ?? ''
const CODE = process.env.COUNTBOOK_SIGNUP_CODE ?? ''
const live = Boolean(SERVER)

const ev = (id: string, wall: number, note: string): Event => ({
  id,
  hlc: encode({ wall, counter: 0, device: 'devA' }),
  dev: 'devA',
  t: 'entry.add',
  entry: {
    id: `entry-${id}`, kind: 'spend', amount: 4200, currency: 'CNY', categoryId: 'food',
    intent: 'want', note, merchant: '测试', day: '2026-09-09', createdAt: wall,
  },
})

/** Establish the manifest the way the app's sync provider does. */
async function establish(cfg: ServerConfig, password: string): Promise<VaultKey> {
  const existing = await readServerManifest(cfg)
  if (existing) {
    const vk = await deriveKey(password, fromBase64(existing.kdf.salt), existing.kdf.iterations)
    if (vk.fingerprint !== existing.fingerprint) throw new Error('wrong password')
    return vk
  }
  const vk = await deriveKey(password)
  const m: Manifest = {
    v: 1, kdf: { name: 'PBKDF2-SHA256', iterations: vk.iterations, salt: toBase64(vk.salt) },
    fingerprint: vk.fingerprint, updatedAt: 1_760_000_000_000, app: 'countbook/test',
  }
  await writeServerManifest(cfg, m)
  return vk
}

describe.runIf(live)('self-hosted server, against the live HTTPS endpoint', () => {
  const email = `e2e-${Date.now()}@countbook.local`
  const password = 'e2e-verify-password-123'
  let tokenA = ''

  beforeAll(async () => {
    // First account on a fresh box is free; a later run needs the code.
    const res = await signup(SERVER, email, password, CODE, 'devA', 'Device A').catch(async (e: unknown) => {
      // If this account somehow exists, just log in.
      if (String(e).includes('email_taken')) return login(SERVER, email, password, 'devA', 'Device A')
      throw e
    })
    tokenA = res.token
    expect(tokenA.length).toBeGreaterThan(20)
  })

  it('device A pushes an encrypted event; device B logs in and reads it back', async () => {
    const cfgA: ServerConfig = { baseUrl: SERVER, token: tokenA }
    const keyA = await establish(cfgA, password)

    const wall = Date.now()
    const mine = ev(`s${wall}`, wall, 'from device A')
    const outA = await syncServer(cfgA, keyA, [mine], { cursor: 0 })
    expect(outA.pushed).toBeGreaterThanOrEqual(1)

    // Device B: a separate login (a second device on the same account), an
    // empty local log, and only the password to work from.
    const sessionB = await login(SERVER, email, password, 'devB', 'Device B')
    const cfgB: ServerConfig = { baseUrl: SERVER, token: sessionB.token }
    const keyB = await establish(cfgB, password)
    expect(keyB.fingerprint).toBe(keyA.fingerprint) // same password → same vault key

    const outB = await syncServer(cfgB, keyB, [], { cursor: 0 })
    const got = outB.merged.find((e) => e.id === mine.id)
    expect(got, 'device B did not receive the event').toBeTruthy()
    // Decrypted AND decoded into the same domain object.
    expect(got?.t).toBe('entry.add')
    if (got?.t === 'entry.add') {
      expect(got.entry.amount).toBe(4200)
      expect(got.entry.note).toBe('from device A')
    }
  }, 30_000)

  it('a wrong password cannot open the vault', async () => {
    const session = await login(SERVER, email, 'the-wrong-password', 'devC', 'Device C').catch(() => null)
    // Login itself must fail on a bad password.
    expect(session).toBeNull()
  })
})
