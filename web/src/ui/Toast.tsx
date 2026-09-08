import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
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
  const action = toastState?.action

  // A toast that carries an action waits for its answer; a toast that only
  // reports something leaves on its own.
  useEffect(() => {
    if (id === undefined || action !== undefined) return
    const timer = window.setTimeout(dismissToast, DWELL_MS)
    return () => window.clearTimeout(timer)
  }, [id, action, dismissToast])

  useEffect(() => setDrag(0), [id])

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    // Capturing the pointer would retarget the click and swallow the press on
    // 撤销 or on the close control, so the body is draggable and they are not.
    if (e.target instanceof Element && e.target.closest('button')) return
    from.current = e.clientY
    e.currentTarget.setPointerCapture(e.pointerId)
  }

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (from.current === null) return
    setDrag(Math.max(0, e.clientY - from.current))
  }

  const onPointerUp = () => {
    if (from.current === null) return
    from.current = null
    if (drag > SWIPE_PX) dismissToast()
    else setDrag(0)
  }

  return (
    <div className="toast-slot" role="status" aria-live="polite">
      {toastState && (
        <div
          className="toast"
          key={toastState.id}
          // The drag tracks the finger 1:1; letting go hands the transition back
          // to CSS, which walks it home.
          style={drag > 0 ? { transform: `translateY(${drag}px)`, transition: 'none' } : undefined}
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
