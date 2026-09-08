import type { Event } from '../core/events'
import { merge } from '../core/events'
import { decode } from '../core/hlc'
import { fromBase64, open, seal, toBase64, type VaultKey } from './crypto'

/**
 * The vault is the encrypted form of the event log, shaped so that syncing is
 * incremental and a conflict is small.
 *
 * The log is sharded by the calendar month an event was created in. A device
 * only fetches shards whose version token has changed, and only rewrites the
 * shards it has new events for — so a year of history costs one small write a
 * day, and two devices editing different months never contend at all.
 *
 *   vault/manifest.json          plaintext: KDF parameters and key fingerprint
 *   vault/s/2026-09.cbk          base64 of one AES-256-GCM envelope
 */

export const MANIFEST_PATH = 'vault/manifest.json'
export const shardPath = (month: string) => `vault/s/${month}.cbk`
export const monthFromShardPath = (p: string) => /vault\/s\/(\d{4}-\d{2})\.cbk$/.exec(p)?.[1] ?? null

export interface Manifest {
  v: 1
  kdf: { name: 'PBKDF2-SHA256'; iterations: number; salt: string }
  /** Hex of SHA-256(key)[0..8). Lets a device reject a wrong passphrase before downloading anything. */
  fingerprint: string
  updatedAt: number
  app: string
}

/** The month an event belongs to, taken from its HLC's wall time. */
export const shardOf = (e: Event): string => {
  const d = new Date(decode(e.hlc).wall)
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
}

export function groupByShard(events: readonly Event[]): Map<string, Event[]> {
  const out = new Map<string, Event[]>()
  for (const e of events) {
    const m = shardOf(e)
    out.set(m, [...(out.get(m) ?? []), e])
  }
  return out
}

export async function encodeShard(vk: VaultKey, events: readonly Event[]): Promise<string> {
  return toBase64(await seal(vk, JSON.stringify(events)))
}

export async function decodeShard(vk: VaultKey, body: string): Promise<Event[]> {
  const json = await open(vk, fromBase64(body))
  const parsed: unknown = JSON.parse(json)
  return Array.isArray(parsed) ? (parsed as Event[]) : []
}

/**
 * What this device believes about the remote, persisted between syncs.
 *
 * `shas` is the remote blob version of each shard as of the last successful
 * sync. `digests` is what *we* held in that shard at the same moment. Both are
 * needed: the sha alone says whether the remote moved, and only the digest says
 * whether we have anything new to send — without it a device cannot tell
 * "already in sync" from "my local copy was cleared".
 */
export interface Cursor {
  shas: Record<string, string>
  digests: Record<string, string>
}

export const emptyCursor = (): Cursor => ({ shas: {}, digests: {} })

/** Order-independent summary of which events we hold for one shard. */
export function digestOf(events: readonly Event[]): string {
  const ids = events.map((e) => e.id).sort()
  let h = 0
  for (const id of ids) {
    for (let i = 0; i < id.length; i++) h = (Math.imul(h, 31) + id.charCodeAt(i)) | 0
  }
  return `${ids.length}:${(h >>> 0).toString(36)}`
}

export interface SyncOutcome {
  merged: Event[]
  cursor: Cursor
  pulled: number
  pushed: number
}

/**
 * A store the sync engine can drive. Both transports implement it: a private
 * GitHub repository, and a self-hosted server. Keeping the CAS loop in one
 * place is what makes the two interchangeable — a device can move from one to
 * the other and the merge is still the same merge.
 */
export interface VaultStore {
  readonly kind: 'github' | 'server'
  describe(): string
  readManifest(): Promise<Manifest | null>
  writeManifest(m: Manifest): Promise<void>
  /** Shard path -> remote version token, for everything under vault/s/. */
  listShards(): Promise<Record<string, string>>
  readShard(month: string): Promise<string>
  /** Returns the new token. Throws ConflictError if `expected` is stale. */
  writeShard(month: string, body: string, expected: string | null): Promise<string>
}

export class ConflictError extends Error {
  constructor() {
    super('shard changed underneath us')
    this.name = 'ConflictError'
  }
}

/**
 * Pull what changed, merge, push what is ours.
 *
 * The invariant that makes this safe: a shard is only ever written by a device
 * that holds everything already in it. Writing replaces the whole shard, so a
 * device that skipped the pull — because its cursor said it was current — and
 * then wrote from a partial local log would silently delete the other device's
 * entries. The cursor's sha can be stale (GitHub's tree endpoint is a replica
 * and lags a commit by a second or two), so being "current" is never taken on
 * trust before an overwrite: any shard about to be written is read first.
 *
 * A conflicting write is not an error to report. It means another device wrote
 * first, so we take their version, union it with ours — union is idempotent, so
 * this converges — and try again.
 */
export async function syncVault(
  store: VaultStore,
  vk: VaultKey,
  local: readonly Event[],
  cursor: Cursor,
  maxRetries = 5,
): Promise<SyncOutcome> {
  const remote = await store.listShards()
  const held = new Set<string>() // shards whose remote contents are merged in
  let merged = [...local]
  let pulled = 0

  for (const [path, sha] of Object.entries(remote)) {
    const month = monthFromShardPath(path)
    if (!month || cursor.shas[path] === sha) continue
    const before = merged.length
    merged = merge(merged, await decodeShard(vk, await store.readShard(month)))
    pulled += merged.length - before
    held.add(path)
  }

  const next: Cursor = { shas: { ...cursor.shas, ...remote }, digests: { ...cursor.digests } }
  let pushed = 0

  for (const month of [...groupByShard(merged).keys()]) {
    const path = shardPath(month)
    const remoteSha = remote[path] ?? null
    const mine = groupByShard(merged).get(month) ?? []

    // Neither side has moved since the last sync of this shard.
    if (remoteSha && cursor.shas[path] === remoteSha && cursor.digests[path] === digestOf(mine)) {
      next.digests[path] = digestOf(mine)
      continue
    }

    if (remoteSha && !held.has(path)) {
      const before = merged.length
      merged = merge(merged, await decodeShard(vk, await store.readShard(month)))
      pulled += merged.length - before
      held.add(path)
    }

    let toWrite = groupByShard(merged).get(month) ?? []
    // The extra read may have shown that they already had everything we hold.
    if (remoteSha && cursor.shas[path] === remoteSha && cursor.digests[path] === digestOf(toWrite)) {
      next.digests[path] = digestOf(toWrite)
      continue
    }

    let expected = remoteSha
    for (let attempt = 0; ; attempt++) {
      try {
        next.shas[path] = await store.writeShard(month, await encodeShard(vk, toWrite), expected)
        next.digests[path] = digestOf(toWrite)
        pushed += toWrite.length
        break
      } catch (err) {
        if (!(err instanceof ConflictError) || attempt >= maxRetries) throw err
        const fresh = await store.listShards()
        expected = fresh[path] ?? null
        if (expected) merged = merge(merged, await decodeShard(vk, await store.readShard(month)))
        toWrite = groupByShard(merged).get(month) ?? toWrite
      }
    }
  }

  return { merged, cursor: next, pulled, pushed }
}
