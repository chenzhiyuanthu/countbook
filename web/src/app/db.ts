/**
 * Local persistence. The event log lives in IndexedDB rather than localStorage
 * because localStorage's ~5 MB ceiling is a real limit for a ledger kept for
 * years, and hitting it throws in the middle of a save — the one moment the app
 * must not fail. Small scalars (cursor, credentials, preferences) stay in
 * localStorage, where synchronous reads keep the first paint immediate.
 */

const DB_NAME = 'countbook'
const DB_VERSION = 1
const STORE = 'kv'

let handle: Promise<IDBDatabase> | null = null

function db(): Promise<IDBDatabase> {
  handle ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE)) req.result.createObjectStore(STORE)
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
  return handle
}

export async function idbGet<T>(key: string): Promise<T | undefined> {
  const conn = await db()
  return new Promise((resolve, reject) => {
    const req = conn.transaction(STORE, 'readonly').objectStore(STORE).get(key)
    req.onsuccess = () => resolve(req.result as T | undefined)
    req.onerror = () => reject(req.error)
  })
}

export async function idbSet(key: string, value: unknown): Promise<void> {
  const conn = await db()
  return new Promise((resolve, reject) => {
    const tx = conn.transaction(STORE, 'readwrite')
    tx.objectStore(STORE).put(value, key)
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
}

/** localStorage can throw in private browsing; a preference is never worth a crash. */
export function lsGet<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key)
    return raw === null ? fallback : (JSON.parse(raw) as T)
  } catch {
    return fallback
  }
}

export function lsSet(key: string, value: unknown): void {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    /* quota or private mode — the event log is the durable copy, not this */
  }
}

export function lsRemove(key: string): void {
  try {
    localStorage.removeItem(key)
  } catch {
    /* as above */
  }
}

export const KEYS = {
  events: 'countbook.events',
  cursor: 'countbook.cursor',
  sync: 'countbook.sync',
  device: 'countbook.device',
  theme: 'countbook.theme',
  passphraseHint: 'countbook.fingerprint',
} as const
