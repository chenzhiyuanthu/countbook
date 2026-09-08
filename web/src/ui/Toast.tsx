import { useEffect, useRef, useState } from 'react'
import { useStore } from '../app/store'
import { Icon } from './icons'
import './Toast.css'

/** Long enough to read one line and reach for 撤销, short enough to leave. */
const DWELL_MS = 5000
/** A downward drag past this many pixels is a dismissal, not a fidget. */
const SWIPE_PX = 24

export function Toast() {
  const { toastState, dismissToast, t } = useStore()
  const [drag, setDrag] = useState(0)
  const from = useRef<number | null>(null)
  const id = toastState?.id
  const hasAction = toastState?.action !== undefined

  // A toast that carries an action waits for an answer; a toast that only
  // reports something leaves on its own.
  useEffect(() => {
    if (id === undefined || hasAction) return
    const timer = window.setTimeout(dismissToast, DWELL_MS)
    return () => window.clearTimeout(timer)
  }, [id, hasAction, dismissToast])

  useEffect(() => setDrag(0), [id])

  const onPointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    from.current = e.clientY
    e.currentTarget.setPointerCapture(e.pointerId)
  }

  const onPointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (from.current === null) return
    setDrag(Math.max(0, e.clientY - from.current))
  }

  const onPointerUp = () => {
    if (from.current === null) return
    from.current = null
    if (drag > SWIPE_PX) dismissToast()
    else setDrag(0)
  }

  const action = toastState?.action

  return (
    <div className="toast-slot" role="status" aria-live="polite">
      {toastState && (
        <div
          className="toast"
          key={toastState.id}
          style={drag > 0 ? { transform: `translateY(${drag}px)` } : undefined}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
        >
          <span className="toast__message">{toastState.message}</span>
          {action && (
            <button
              type="button"
              className="toast__action"
              onClick={() => {
                action.run()
                dismissToast()
              }}
            >
              {action.label}
            </button>
          )}
          <button
            type="button"
            className="toast__close"
            aria-label={t('common.close')}
            onClick={dismissToast}
          >
            <Icon name="xmark" />
          </button>
        </div>
      )}
    </div>
  )
}
