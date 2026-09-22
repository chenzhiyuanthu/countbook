import { afterEach, describe, expect, it, vi } from 'vitest'
import { deriveKey, open, seal, toBase64, fromBase64 } from './crypto'
import { syncServer } from './server'
import type { Event } from '../core/events'

/**
 * The cursor race: a row another device inserts between this device's pull and
 * its push must be read on the next pass, not skipped because the push reply
 * named a head beyond it. Played against a fake server that does exactly that.
 */
const ev = (id: string, wall: number): Event =>
  ({ id, hlc: `${String(wall).padStart(16, '0')}-0000-${id.slice(0, 2)}`, dev: id.slice(0, 2), t: 'day.nospend', day: '2026-09-18', on: true }) as Event

describe('server sync cursor', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('never advances past a row it has not read, and reads its own rows once', async () => {
    const vk = await deriveKey('a passphrase', new Uint8Array(16), 1000)
    const sealed = async (e: Event) => ({ id: e.id, hlc: e.hlc, body: toBase64(await seal(vk, JSON.stringify(e))) })

    // Server log: seq 10 is already there; seq 11 arrives from another device
    // while we are pushing; our own push lands as seq 12.
    const rows: { seq: number; id: string; hlc: string; body: string }[] = [{ seq: 10, ...(await sealed(ev('aa-old', 1))) }]
    const foreign = await sealed(ev('bb-new', 2))
    const pulls: number[] = []

    vi.stubGlobal('fetch', async (url: string, init?: RequestInit) => {
      const u = new URL(url)
      if (u.pathname === '/api/pull') {
        const since = Number(u.searchParams.get('since'))
        pulls.push(since)
        const page = rows.filter((r) => r.seq > since)
        return Response.json({ events: page, cursor: page.length ? page[page.length - 1]!.seq : since, hasMore: false })
      }
      // push: the other device's row slips in first, then ours is inserted
      rows.push({ seq: 11, ...foreign })
      const body = JSON.parse(String(init?.body)) as { events: { id: string; hlc: string; body: string }[] }
      let accepted = 0
      for (const e of body.events) {
        if (!rows.some((r) => r.id === e.id)) {
          rows.push({ seq: 12, ...e })
          accepted++
        }
      }
      return Response.json({ accepted, duplicates: body.events.length - accepted, cursor: 12 })
    })

    const mine = ev('cc-mine', 3)
    const out = await syncServer({ baseUrl: 'https://x.test', token: 't' }, vk, [mine], { cursor: 0 })

    expect(pulls).toEqual([0, 10])
    expect(out.cursor.cursor).toBe(12)
    expect(out.merged.map((e) => e.id).sort()).toEqual(['aa-old', 'bb-new', 'cc-mine'])
    expect(out.pushed).toBe(1)

    // And the round trip is honest: what we read back is what was sealed.
    const back = JSON.parse(await open(vk, fromBase64(rows.find((r) => r.seq === 12)!.body))) as Event
    expect(back.id).toBe('cc-mine')

    // A second pass with nothing new pulls once, from 12, and pushes only duplicates.
    pulls.length = 0
    const again = await syncServer({ baseUrl: 'https://x.test', token: 't' }, vk, out.merged, out.cursor)
    expect(pulls).toEqual([12])
    expect(again.pushed).toBe(0)
    expect(again.cursor.cursor).toBe(12)
  })
})
