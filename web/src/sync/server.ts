import type { Event } from '../core/events'
import { merge } from '../core/events'
import { fromBase64, open, seal, toBase64, type VaultKey } from './crypto'
import type { Manifest } from './vault'

/**
 * Adapter B — a self-hosted sync server.
 *
 * Unlike the GitHub vault this needs no compare-and-swap: the server is an
 * append-only relay keyed by the client-generated event id, so two devices
 * writing at once simply both succeed and a retry after a dropped response
 * inserts nothing twice. Each event body is sealed individually, so the server
 * stores ciphertext and operating it grants no ability to read the ledger.
 */

export interface ServerConfig {
  baseUrl: string
  token: string
}

export interface ServerCursor {
  cursor: number
}

export class ServerError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly kind: 'auth' | 'network' | 'other',
  ) {
    super(message)
    this.name = 'ServerError'
  }
}

const trim = (u: string) => u.replace(/\/+$/, '')

async function call<T>(cfg: ServerConfig, path: string, init: RequestInit = {}): Promise<T> {
  let res: Response
  try {
    res = await fetch(`${trim(cfg.baseUrl)}${path}`, {
      ...init,
      headers: {
        accept: 'application/json',
        ...(cfg.token ? { authorization: `Bearer ${cfg.token}` } : {}),
        ...(init.body ? { 'content-type': 'application/json' } : {}),
        ...init.headers,
      },
    })
  } catch (e) {
    throw new ServerError(e instanceof Error ? e.message : '连接失败', 0, 'network')
  }
  if (res.status === 401) throw new ServerError('登录已过期，请重新登录', 401, 'auth')
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string }
    throw new ServerError(body.error ?? `服务器返回 ${res.status}`, res.status, 'other')
  }
  return (await res.json()) as T
}

export async function login(
  baseUrl: string,
  email: string,
  password: string,
  device: string,
  label: string,
): Promise<{ token: string; expiresAt: number; userId: string }> {
  return call({ baseUrl, token: '' }, '/api/login', {
    method: 'POST',
    body: JSON.stringify({ email, password, device, label }),
  })
}

export async function signup(
  baseUrl: string,
  email: string,
  password: string,
  code: string,
  device: string,
  label: string,
): Promise<{ token: string; expiresAt: number; userId: string }> {
  return call({ baseUrl, token: '' }, '/api/signup', {
    method: 'POST',
    body: JSON.stringify({ email, password, code, device, label }),
  })
}

export interface DeviceRow {
  ref: string
  device: string
  label: string
  createdAt: number
  seenAt: number
  current: boolean
}

export const listDevices = (cfg: ServerConfig) => call<{ devices: DeviceRow[] }>(cfg, '/api/devices')
export const revokeDevice = (cfg: ServerConfig, ref: string) =>
  call<{ ok: true }>(cfg, '/api/devices/revoke', { method: 'POST', body: JSON.stringify({ ref }) })

/**
 * The server stores the manifest as a normal event so the KDF parameters travel
 * with the log. It is the one event whose body is plaintext — it has to be
 * readable before a key exists.
 */
const MANIFEST_EVENT_ID = 'manifest'

export async function syncServer(
  cfg: ServerConfig,
  vk: VaultKey,
  local: readonly Event[],
  cursor: ServerCursor,
): Promise<{ merged: Event[]; cursor: ServerCursor; pulled: number; pushed: number }> {
  let at = cursor.cursor ?? 0
  let merged = [...local]
  let pulled = 0

  for (;;) {
    const page = await call<{ events: { id: string; hlc: string; body: string }[]; cursor: number; hasMore: boolean }>(
      cfg,
      `/api/pull?since=${at}&limit=500`,
    )
    const decoded: Event[] = []
    for (const row of page.events) {
      if (row.id === MANIFEST_EVENT_ID) continue
      try {
        decoded.push(JSON.parse(await open(vk, fromBase64(row.body))) as Event)
      } catch {
        // One unreadable row must not stop the sync: it is far more likely to be
        // an event written under a different passphrase than a real corruption,
        // and the rest of the log is still perfectly usable.
      }
    }
    pulled += decoded.length
    merged = merge(merged, decoded)
    at = page.cursor
    if (!page.hasMore) break
  }

  // Push everything we hold; the server discards ids it already has, so there
  // is no need to track which of ours it has seen.
  const payload = await Promise.all(
    merged.map(async (e) => ({ id: e.id, hlc: e.hlc, body: toBase64(await seal(vk, JSON.stringify(e))) })),
  )

  let pushed = 0
  for (let i = 0; i < payload.length; i += 500) {
    const res = await call<{ accepted: number; cursor: number }>(cfg, '/api/push', {
      method: 'POST',
      body: JSON.stringify({ events: payload.slice(i, i + 500) }),
    })
    pushed += res.accepted
    at = Math.max(at, res.cursor)
  }

  return { merged, cursor: { cursor: at }, pulled, pushed }
}

export async function readServerManifest(cfg: ServerConfig): Promise<Manifest | null> {
  const page = await call<{ events: { id: string; body: string }[] }>(cfg, '/api/pull?since=0&limit=1')
  const row = page.events.find((e) => e.id === MANIFEST_EVENT_ID)
  return row ? (JSON.parse(atob(row.body)) as Manifest) : null
}

export async function writeServerManifest(cfg: ServerConfig, m: Manifest): Promise<void> {
  await call(cfg, '/api/push', {
    method: 'POST',
    body: JSON.stringify({
      events: [{ id: MANIFEST_EVENT_ID, hlc: '0'.repeat(16) + '-0000-manifest', body: btoa(JSON.stringify(m)) }],
    }),
  })
}
