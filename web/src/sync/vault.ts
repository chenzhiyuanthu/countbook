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

/** Version tokens per shard path, persisted locally so the next sync is a diff. */
export type Cursor = Record<string, string>

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
  /** path -> version token, for everything under vault/s/. */
  listShards(): Promise<Cursor>
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
 * Pull what changed, merge, push what is ours. A conflicting write is not an
 * error condition to report — it just means another device wrote first, so we
 * re-read that shard, merge again (union is idempotent, so this always
 * converges) and retry.
 */
export async function syncVault(
  store: VaultStore,
  vk: VaultKey,
  local: readonly Event[],
  cursor: Cursor,
  maxRetries = 5,
): Promise<SyncOutcome> {
  const remoteTokens = await store.listShards()
  let merged = [...local]
  let pulled = 0

  for (const [path, token] of Object.entries(remoteTokens)) {
    const month = monthFromShardPath(path)
    if (!month || cursor[path] === token) continue
    const events = await decodeShard(vk, await store.readShard(month))
    pulled += events.length
    merged = merge(merged, events)
  }

  const next: Cursor = { ...cursor, ...remoteTokens }
  const byShard = groupByShard(merged)
  let pushed = 0

  for (const [month, events] of byShard) {
    const path = shardPath(month)
    const remoteToken = remoteTokens[path] ?? null
    // Nothing new for this month: the remote token is current and we pulled it.
    const knownIds = new Set(events.map((e) => e.id))
    if (remoteToken && next[path] === remoteToken && knownIds.size === events.length) {
      const localOnly = events.filter((e) => !local.some((l) => l.id === e.id))
      if (localOnly.length === 0 && cursor[path] === remoteToken) continue
    }

    let attempt = 0
    let expected = remoteToken
    let toWrite = events
    for (;;) {
      try {
        next[path] = await store.writeShard(month, await encodeShard(vk, toWrite), expected)
        pushed += toWrite.length
        break
      } catch (err) {
        if (!(err instanceof ConflictError) || ++attempt > maxRetries) throw err
        // Someone else wrote this month while we were sealing it. Take their
        // version, union it with ours, and try again — union is idempotent, so
        // this terminates as soon as we win a race.
        const fresh = await store.listShards()
        expected = fresh[path] ?? null
        toWrite = merge(toWrite, expected ? await decodeShard(vk, await store.readShard(month)) : [])
        merged = merge(merged, toWrite)
      }
    }
  }

  return { merged, cursor: next, pulled, pushed }
}
