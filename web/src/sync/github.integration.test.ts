import { beforeAll, describe, expect, it } from 'vitest'
import { webcrypto } from 'node:crypto'
import type { Event } from '../core/events'
import { encode } from '../core/hlc'
import { deriveKey, type VaultKey } from './crypto'
import { GitHubStore } from './github'
import { emptyCursor, syncVault, type Cursor } from './vault'

/**
 * Drives the real GitHub API against a real private repository. Skipped unless
 * a token is supplied, so `npm test` stays offline and fast:
 *
 *   COUNTBOOK_GH_TOKEN=$(gh auth token) COUNTBOOK_GH_REPO=owner/repo npm run --prefix web test
 *
 * This is the one test that can catch a CORS rule, an API version change, a
 * base64 layer or a compare-and-swap semantic that the unit tests cannot.
 */

if (!globalThis.crypto) Object.defineProperty(globalThis, 'crypto', { value: webcrypto })

const TOKEN = process.env.COUNTBOOK_GH_TOKEN ?? ''
const [OWNER = '', REPO = ''] = (process.env.COUNTBOOK_GH_REPO ?? '').split('/')
const live = Boolean(TOKEN && OWNER && REPO)

const ev = (id: string, wall: number, dev: string, note: string): Event => ({
  id,
  hlc: encode({ wall, counter: 0, device: dev }),
  dev,
  t: 'entry.add',
  entry: {
    id: `entry-${id}`,
    kind: 'spend',
    amount: 12_640,
    currency: 'CNY',
    categoryId: 'food',
    intent: 'want',
    note,
    merchant: '测试',
    day: '2026-09-08',
    createdAt: wall,
  },
})

describe.runIf(live)('GitHub vault, against the live API', () => {
  let key: VaultKey
  let store: GitHubStore

  beforeAll(async () => {
    key = await deriveKey('integration-test-passphrase', new Uint8Array(16).fill(3), 1000)
    store = new GitHubStore({ owner: OWNER, repo: REPO, branch: 'main', token: TOKEN })
  })

  it('reports what the token can actually do', async () => {
    const check = await store.verify()
    expect(check).toMatchObject({ ok: true })
  })

  it('writes a manifest and reads it back', async () => {
    await store.listShards()
    await store.writeManifest({
      v: 1,
      kdf: { name: 'PBKDF2-SHA256', iterations: key.iterations, salt: 'AwMDAwMDAwMDAwMDAwMDAw' },
      fingerprint: key.fingerprint,
      updatedAt: 1_760_000_000_000,
      app: 'countbook/test',
    })
    const back = await store.readManifest()
    expect(back?.fingerprint).toBe(key.fingerprint)
  })

  it('round-trips an encrypted shard and pulls it back on a second device', async () => {
    const wall = Date.now()
    const deviceA = [ev('a1', wall, 'aaaa', 'from A')]

    const first = await syncVault(store, key, deviceA, emptyCursor())
    expect(first.pushed).toBeGreaterThanOrEqual(1)

    // A different store instance with an empty cursor is exactly a second
    // device seeing this vault for the first time.
    const fresh = new GitHubStore({ owner: OWNER, repo: REPO, branch: 'main', token: TOKEN })
    const second = await syncVault(fresh, key, [], emptyCursor())
    expect(second.merged.map((e) => e.id)).toContain('a1')
    expect(second.merged.find((e) => e.id === 'a1')).toMatchObject({ t: 'entry.add' })
  })

  it('converges when two devices write the same month at once', async () => {
    const wall = Date.now()
    const a = new GitHubStore({ owner: OWNER, repo: REPO, branch: 'main', token: TOKEN })
    const b = new GitHubStore({ owner: OWNER, repo: REPO, branch: 'main', token: TOKEN })

    // Both read the same starting state, then both write — the second write's
    // compare-and-swap must fail and be retried against the winner's version.
    const cursorA: Cursor = { shas: await a.listShards(), digests: {} }
    const cursorB: Cursor = { shas: await b.listShards(), digests: {} }

    await syncVault(a, key, [ev(`x${wall}`, wall, 'aaaa', 'A wins the race')], cursorA)
    const outB = await syncVault(b, key, [ev(`y${wall}`, wall + 1, 'bbbb', 'B retries')], cursorB)

    const ids = outB.merged.map((e) => e.id)
    expect(ids).toContain(`x${wall}`)
    expect(ids).toContain(`y${wall}`)

    // And a third device sees both without either having been lost.
    const c = new GitHubStore({ owner: OWNER, repo: REPO, branch: 'main', token: TOKEN })
    const outC = await syncVault(c, key, [], emptyCursor())
    expect(outC.merged.map((e) => e.id)).toEqual(expect.arrayContaining([`x${wall}`, `y${wall}`]))
  }, 60_000)
})
