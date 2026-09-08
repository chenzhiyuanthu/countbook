import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from 'react'
import type { Event, Payload } from '../core/events'
import { merge, sort } from '../core/events'
import { fold } from '../core/fold'
import { Clock } from '../core/hlc'
import { deviceId, newId } from '../core/id'
import { toDay } from '../core/date'
import type { Ledger } from '../core/types'
import { makeT, type Locale, type T } from './i18n'
import { idbGet, idbSet, KEYS, lsGet, lsSet } from './db'

/**
 * One store for the whole app. Everything the UI shows is derived from the
 * event log by `fold`, so there is no second source of truth to keep in step
 * and no possibility of the screen disagreeing with the ledger.
 */

export interface Store {
  ready: boolean
  ledger: Ledger
  events: Event[]
  today: string
  now: number
  t: T
  locale: Locale
  /** Append an event. Returns its id so a caller can undo exactly this one. */
  commit: (payload: Payload) => string
  /** Fold in events that arrived from another device. */
  absorb: (incoming: Event[]) => void
  undo: (eventId: string) => void
  replaceAll: (events: Event[]) => void
  toast: (message: string, action?: { label: string; run: () => void }) => void
  toastState: ToastState | null
  dismissToast: () => void
}

export interface ToastState {
  id: number
  message: string
  action?: { label: string; run: () => void }
}

const Ctx = createContext<Store | null>(null)

export function useStore(): Store {
  const s = useContext(Ctx)
  if (!s) throw new Error('useStore outside StoreProvider')
  return s
}

export function StoreProvider({ children }: { children: ReactNode }) {
  const [events, setEvents] = useState<Event[]>([])
  const [ready, setReady] = useState(false)
  const [toastState, setToastState] = useState<ToastState | null>(null)
  // The date only matters to the day, so re-render on a timer rather than
  // reading the clock inside render, which would make components impure.
  const [now, setNow] = useState(() => Date.now())

  const clock = useRef<Clock | null>(null)
  clock.current ??= new Clock(deviceId())

  useEffect(() => {
    let alive = true
    void (async () => {
      const stored = (await idbGet<Event[]>(KEYS.events)) ?? lsGet<Event[]>(KEYS.events, [])
      if (!alive) return
      const loaded = sort([...stored])
      for (const e of loaded) clock.current?.observe(e.hlc)
      setEvents(loaded)
      setReady(true)
    })()
    return () => {
      alive = false
    }
  }, [])

  // Persist after paint, not during it: saving is never allowed to make an
  // entry feel slow.
  const persist = useCallback((next: Event[]) => {
    queueMicrotask(() => void idbSet(KEYS.events, next).catch(() => lsSet(KEYS.events, next)))
  }, [])

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30_000)
    const onVisible = () => document.visibilityState === 'visible' && setNow(Date.now())
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      clearInterval(id)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [])

  const commit = useCallback(
    (payload: Payload): string => {
      const id = newId()
      const event = { id, hlc: clock.current!.next(), dev: deviceId(), ...payload } as Event
      setEvents((prev) => {
        const next = sort([...prev, event])
        persist(next)
        return next
      })
      return id
    },
    [persist],
  )

  const absorb = useCallback(
    (incoming: Event[]) => {
      if (!incoming.length) return
      for (const e of incoming) clock.current?.observe(e.hlc)
      setEvents((prev) => {
        const next = merge(prev, incoming)
        if (next.length === prev.length) return prev
        persist(next)
        return next
      })
    },
    [persist],
  )

  /**
   * Undo removes the event outright rather than appending a compensating one.
   * It is only ever offered for something committed seconds ago on this device,
   * so no other device can have seen it, and a log without the mistake is
   * cleaner than a log with a mistake and its retraction.
   */
  const undo = useCallback(
    (eventId: string) => {
      setEvents((prev) => {
        const next = prev.filter((e) => e.id !== eventId)
        persist(next)
        return next
      })
    },
    [persist],
  )

  const replaceAll = useCallback(
    (next: Event[]) => {
      const sorted = sort([...next])
      for (const e of sorted) clock.current?.observe(e.hlc)
      setEvents(sorted)
      persist(sorted)
    },
    [persist],
  )

  const toast = useCallback((message: string, action?: { label: string; run: () => void }) => {
    setToastState({ id: Date.now(), message, ...(action ? { action } : {}) })
  }, [])

  const ledger = useMemo(() => fold(events), [events])
  const locale = ledger.settings.locale
  const t = useMemo(() => makeT(locale), [locale])
  const today = useMemo(() => toDay(new Date(now)), [now])

  // The theme is applied to the document rather than to a React tree so the
  // browser chrome (scrollbars, form controls, the address bar) follows it too.
  useEffect(() => {
    const theme = ledger.settings.theme
    const root = document.documentElement
    if (theme === 'system') root.removeAttribute('data-theme')
    else root.setAttribute('data-theme', theme)
    lsSet(KEYS.theme, theme)
  }, [ledger.settings.theme])

  useEffect(() => {
    document.documentElement.lang = locale === 'en' ? 'en' : 'zh-CN'
  }, [locale])

  const value = useMemo<Store>(
    () => ({
      ready, ledger, events, today, now, t, locale,
      commit, absorb, undo, replaceAll,
      toast, toastState, dismissToast: () => setToastState(null),
    }),
    [ready, ledger, events, today, now, t, locale, commit, absorb, undo, replaceAll, toast, toastState],
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}
