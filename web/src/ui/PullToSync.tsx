import { useEffect, useRef, useState, type RefObject } from 'react'
import { useStore } from '../app/store'
import { useSync } from '../app/sync'
import './PullToSync.css'

/** Past this many pixels of pull the release is a request, not a fidget. */
const THRESHOLD = 64
/** The strip never grows past this; the finger can, the page does not follow. */
const MAX = 96
/** Drag is halved so the strip feels attached to the finger, not glued to it. */
const DAMPING = 0.5

/**
 * Pull the top of the scroller down to read the whole log again. It is the
 * one gesture in the product, and it only exists where there is a remote to
 * read from; it does nothing else and shows nothing else. Mirrors the
 * `.refreshable` on every iOS screen (SyncMark.swift, `syncRefresh`).
 *
 * Touch only: on a desktop the page has a keyboard, a Settings button and no
 * finger, and a wheel is never a pull.
 */
export function PullToSync({ scroller }: { scroller: RefObject<HTMLElement | null> }) {
  const { t } = useStore()
  const { config, phase, resync } = useSync()
  const [pull, setPull] = useState(0)
  const [busy, setBusy] = useState(false)
  const start = useRef<number | null>(null)
  const armed = config !== null

  useEffect(() => {
    const el = scroller.current
    if (!el || !armed) return

    const onStart = (e: TouchEvent) => {
      // Only a pull that begins at the very top is a pull; anywhere else it is a scroll.
      start.current = el.scrollTop <= 0 && !busy ? (e.touches[0]?.clientY ?? null) : null
    }
    const onMove = (e: TouchEvent) => {
      if (start.current === null) return
      const dy = (e.touches[0]?.clientY ?? start.current) - start.current
      if (dy <= 0 || el.scrollTop > 0) {
        setPull(0)
        return
      }
      setPull(Math.min(MAX, dy * DAMPING))
    }
    const onEnd = () => {
      if (start.current === null) return
      start.current = null
      setPull((p) => {
        if (p < THRESHOLD) return 0
        setBusy(true)
        void resync().finally(() => {
          setBusy(false)
          setPull(0)
        })
        return THRESHOLD
      })
    }

    el.addEventListener('touchstart', onStart, { passive: true })
    el.addEventListener('touchmove', onMove, { passive: true })
    el.addEventListener('touchend', onEnd)
    el.addEventListener('touchcancel', onEnd)
    return () => {
      el.removeEventListener('touchstart', onStart)
      el.removeEventListener('touchmove', onMove)
      el.removeEventListener('touchend', onEnd)
      el.removeEventListener('touchcancel', onEnd)
    }
  }, [scroller, armed, busy, resync])

  if (!armed || (pull === 0 && !busy)) return null

  const label = busy || phase === 'syncing'
    ? t('sync.syncing')
    : pull >= THRESHOLD
      ? t('sync.pullRelease')
      : t('sync.pullDown')

  return (
    <div className="pullsync" style={{ height: busy ? THRESHOLD : pull }} aria-hidden={!busy}>
      <span className="t-label ink-500">{label}</span>
    </div>
  )
}
