import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from 'react'
import type { Event } from '../core/events'
import { deviceId } from '../core/id'
import {
  deriveKey, formatFingerprint, fromBase64, importKeyMaterial, toBase64, type VaultKey,
} from '../sync/crypto'
import { GitHubStore, type GitHubConfig } from '../sync/github'
import { syncServer, type ServerConfig, type ServerCursor } from '../sync/server'
import { syncVault, type Cursor, type Manifest } from '../sync/vault'
import { KEYS, lsGet, lsRemove, lsSet } from './db'
import { useStore } from './store'

/**
 * The sync state machine. Sync is always an enhancement: the app is fully
 * usable with it off, every write lands locally first, and a failure is a line
 * of status text rather than a blocked screen.
 */

export type SyncPhase = 'off' | 'locked' | 'idle' | 'syncing' | 'offline' | 'error'

export type SyncConfig =
  | ({ kind: 'github' } & GitHubConfig)
  | ({ kind: 'server'; email: string } & ServerConfig)

interface Remembered {
  raw: string
  salt: string
  iterations: number
  fingerprint: string
}

export interface SyncApi {
  phase: SyncPhase
  config: SyncConfig | null
  fingerprint: string | null
  message: string
  lastSyncedAt: number | null
  connectGitHub: (cfg: GitHubConfig, passphrase: string, remember: boolean) => Promise<void>
  connectServer: (cfg: ServerConfig & { email: string }, passphrase: string, remember: boolean) => Promise<void>
  unlock: (passphrase: string) => Promise<void>
  disconnect: () => void
  syncNow: () => Promise<void>
}

const Ctx = createContext<SyncApi | null>(null)

export function useSync(): SyncApi {
  const s = useContext(Ctx)
  if (!s) throw new Error('useSync outside SyncProvider')
  return s
}

const CONFIG_KEY = KEYS.sync
const CURSOR_KEY = KEYS.cursor
const REMEMBER_KEY = 'countbook.key'
const LAST_KEY = 'countbook.lastSync'

export function SyncProvider({ children }: { children: ReactNode }) {
  const { events, absorb, ready } = useStore()
  const [config, setConfig] = useState<SyncConfig | null>(() => lsGet<SyncConfig | null>(CONFIG_KEY, null))
  const [phase, setPhase] = useState<SyncPhase>('off')
  const [message, setMessage] = useState('')
  const [lastSyncedAt, setLastSyncedAt] = useState<number | null>(() => lsGet<number | null>(LAST_KEY, null))
  const [key, setKey] = useState<VaultKey | null>(null)

  // The event list changes on every keystroke in a note field; sync reads it
  // through a ref so a re-render never restarts an in-flight sync.
  const eventsRef = useRef(events)
  eventsRef.current = events
  const running = useRef(false)
  const queued = useRef(false)

  /* ── key handling ─────────────────────────────────────────────────── */

  useEffect(() => {
    if (!config) {
      setPhase('off')
      return
    }
    const remembered = lsGet<Remembered | null>(REMEMBER_KEY, null)
    if (!remembered) {
      setPhase('locked')
      return
    }
    void importKeyMaterial(fromBase64(remembered.raw), fromBase64(remembered.salt), remembered.iterations)
      .then((vk) => {
        setKey(vk)
        setPhase('idle')
      })
      .catch(() => setPhase('locked'))
  }, [config])

  const remember = useCallback((vk: VaultKey) => {
    lsSet(REMEMBER_KEY, {
      raw: toBase64(vk.raw),
      salt: toBase64(vk.salt),
      iterations: vk.iterations,
      fingerprint: vk.fingerprint,
    } satisfies Remembered)
  }, [])

  /* ── the sync run ─────────────────────────────────────────────────── */

  const run = useCallback(
    async (cfg: SyncConfig, vk: VaultKey) => {
      if (running.current) {
        queued.current = true
        return
      }
      running.current = true
      setPhase('syncing')
      try {
        let merged: Event[]
        if (cfg.kind === 'github') {
          const store = new GitHubStore(cfg)
          const cursor = lsGet<Cursor>(CURSOR_KEY, {})
          const out = await syncVault(store, vk, eventsRef.current, cursor)
          lsSet(CURSOR_KEY, out.cursor)
          merged = out.merged
        } else {
          const cursor = lsGet<ServerCursor>(CURSOR_KEY, { cursor: 0 })
          const out = await syncServer(cfg, vk, eventsRef.current, cursor)
          lsSet(CURSOR_KEY, out.cursor)
          merged = out.merged
        }
        absorb(merged)
        const at = Date.now()
        setLastSyncedAt(at)
        lsSet(LAST_KEY, at)
        setMessage('')
        setPhase('idle')
      } catch (err) {
        const text = err instanceof Error ? err.message : String(err)
        // A dead network is a normal state on a phone, not a failure worth
        // colouring red.
        const offline = !navigator.onLine || /Failed to fetch|NetworkError|连接失败/i.test(text)
        setMessage(text)
        setPhase(offline ? 'offline' : 'error')
      } finally {
        running.current = false
        if (queued.current) {
          queued.current = false
          void run(cfg, vk)
        }
      }
    },
    [absorb],
  )

  const syncNow = useCallback(async () => {
    if (config && key) await run(config, key)
  }, [config, key, run])

  /* ── triggers ─────────────────────────────────────────────────────── */

  useEffect(() => {
    if (!ready || !config || !key) return
    void run(config, key)
  }, [ready, config, key, run])

  useEffect(() => {
    if (!config || !key) return
    // Debounced: a burst of edits produces one sync, not one per keystroke.
    const t = setTimeout(() => void run(config, key), 4000)
    return () => clearTimeout(t)
  }, [events.length, config, key, run])

  useEffect(() => {
    if (!config || !key) return
    const onFocus = () => document.visibilityState === 'visible' && void run(config, key)
    const onOnline = () => void run(config, key)
    document.addEventListener('visibilitychange', onFocus)
    window.addEventListener('online', onOnline)
    const id = setInterval(onOnline, 5 * 60_000)
    return () => {
      document.removeEventListener('visibilitychange', onFocus)
      window.removeEventListener('online', onOnline)
      clearInterval(id)
    }
  }, [config, key, run])

  /* ── connecting ───────────────────────────────────────────────────── */

  /**
   * Establish the key against the vault's manifest. A vault that already exists
   * dictates the salt and iteration count, so a second device deriving from the
   * same passphrase lands on the same key; a fingerprint mismatch means the
   * passphrase is wrong and is reported as such before anything is written.
   */
  const establish = useCallback(
    async (
      passphrase: string,
      readManifest: () => Promise<Manifest | null>,
      writeManifest: (m: Manifest) => Promise<void>,
    ): Promise<VaultKey> => {
      const existing = await readManifest()
      if (existing) {
        const vk = await deriveKey(passphrase, fromBase64(existing.kdf.salt), existing.kdf.iterations)
        if (vk.fingerprint !== existing.fingerprint) {
          throw new Error('口令打不开这个仓库 · That passphrase does not open this vault')
        }
        return vk
      }
      const vk = await deriveKey(passphrase)
      await writeManifest({
        v: 1,
        kdf: { name: 'PBKDF2-SHA256', iterations: vk.iterations, salt: toBase64(vk.salt) },
        fingerprint: vk.fingerprint,
        updatedAt: Date.now(),
        app: 'countbook/1.0',
      })
      return vk
    },
    [],
  )

  const connectGitHub = useCallback(
    async (cfg: GitHubConfig, passphrase: string, keep: boolean) => {
      setPhase('syncing')
      setMessage('')
      try {
        const store = new GitHubStore(cfg)
        const check = await store.verify()
        if (!check.ok) throw new Error(check.error)
        await store.listShards() // primes the SHA table the manifest write needs
        const vk = await establish(passphrase, () => store.readManifest(), (m) => store.writeManifest(m))
        const next: SyncConfig = { kind: 'github', ...cfg }
        lsSet(CONFIG_KEY, next)
        lsRemove(CURSOR_KEY)
        if (keep) remember(vk)
        setConfig(next)
        setKey(vk)
        await run(next, vk)
      } catch (err) {
        setMessage(err instanceof Error ? err.message : String(err))
        setPhase('error')
        throw err
      }
    },
    [establish, remember, run],
  )

  const connectServer = useCallback(
    async (cfg: ServerConfig & { email: string }, passphrase: string, keep: boolean) => {
      setPhase('syncing')
      setMessage('')
      try {
        const { readServerManifest, writeServerManifest } = await import('../sync/server')
        const vk = await establish(
          passphrase,
          () => readServerManifest(cfg),
          (m) => writeServerManifest(cfg, m),
        )
        const next: SyncConfig = { kind: 'server', ...cfg }
        lsSet(CONFIG_KEY, next)
        lsRemove(CURSOR_KEY)
        if (keep) remember(vk)
        setConfig(next)
        setKey(vk)
        await run(next, vk)
      } catch (err) {
        setMessage(err instanceof Error ? err.message : String(err))
        setPhase('error')
        throw err
      }
    },
    [establish, remember, run],
  )

  const unlock = useCallback(
    async (passphrase: string) => {
      if (!config) return
      const manifest =
        config.kind === 'github'
          ? await new GitHubStore(config).readManifest()
          : await (await import('../sync/server')).readServerManifest(config)
      if (!manifest) throw new Error('这个仓库还没有初始化')
      const vk = await deriveKey(passphrase, fromBase64(manifest.kdf.salt), manifest.kdf.iterations)
      if (vk.fingerprint !== manifest.fingerprint) throw new Error('口令打不开这个仓库')
      remember(vk)
      setKey(vk)
      setPhase('idle')
      await run(config, vk)
    },
    [config, remember, run],
  )

  const disconnect = useCallback(() => {
    lsRemove(CONFIG_KEY)
    lsRemove(CURSOR_KEY)
    lsRemove(REMEMBER_KEY)
    lsRemove(LAST_KEY)
    setConfig(null)
    setKey(null)
    setLastSyncedAt(null)
    setPhase('off')
    setMessage('')
  }, [])

  const value = useMemo<SyncApi>(
    () => ({
      phase,
      config,
      fingerprint: key ? formatFingerprint(key.fingerprint) : null,
      message,
      lastSyncedAt,
      connectGitHub,
      connectServer,
      unlock,
      disconnect,
      syncNow,
    }),
    [phase, config, key, message, lastSyncedAt, connectGitHub, connectServer, unlock, disconnect, syncNow],
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export const thisDeviceLabel = (): string => {
  const ua = navigator.userAgent
  if (/iPhone/.test(ua)) return 'iPhone'
  if (/iPad/.test(ua)) return 'iPad'
  if (/Macintosh/.test(ua)) return 'Mac'
  if (/Android/.test(ua)) return 'Android'
  if (/Windows/.test(ua)) return 'Windows'
  return 'Web'
}

export const thisDeviceId = deviceId
