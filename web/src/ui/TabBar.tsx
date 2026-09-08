import { useLayoutEffect, useMemo, useRef, useState } from 'react'
import { useStore } from '../app/store'
import type { StringKey } from '../app/i18n'
import { reckoningQueue } from '../core/compute'
import './TabBar.css'

export type TabId = 'today' | 'ledger' | 'report' | 'wants' | 'settings'

const TABS: readonly { readonly id: TabId; readonly key: StringKey }[] = [
  { id: 'today', key: 'tab.today' },
  { id: 'ledger', key: 'tab.ledger' },
  { id: 'report', key: 'tab.report' },
  { id: 'wants', key: 'tab.wants' },
  { id: 'settings', key: 'tab.settings' },
]

interface Indicator {
  left: number
  width: number
}

export function TabBar({ current, onChange }: { current: TabId; onChange: (id: TabId) => void }) {
  const { t, ledger, today } = useStore()
  const rowRef = useRef<HTMLUListElement>(null)
  const [rule, setRule] = useState<Indicator | null>(null)

  // The selection rule is exactly as wide as the word above it, so its position
  // is measured rather than assumed: 今日 and Settings are not the same width.
  useLayoutEffect(() => {
    const row = rowRef.current
    if (!row) return
    const measure = () => {
      const label = row.querySelector<HTMLElement>(`[data-tab="${current}"] .tabbar__label`)
      if (!label) return
      const box = label.getBoundingClientRect()
      const frame = row.getBoundingClientRect()
      setRule({ left: box.left - frame.left, width: box.width })
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(row)
    return () => observer.disconnect()
  }, [current])

  // The only notification affordance in the product: a pending reckoning makes
  // the 报告 word take full ink while it is still unselected. No badge, no dot.
  const pending = useMemo(
    () => reckoningQueue(ledger, today).length > 0,
    [ledger, today],
  )

  return (
    <nav className="tabbar" aria-label={t('tab.nav')}>
      <ul className="tabbar__row" ref={rowRef}>
        {rule && (
          <li
            className="tabbar__rule"
            aria-hidden="true"
            style={{ transform: `translateX(${rule.left}px)`, width: `${rule.width}px` }}
          />
        )}
        {TABS.map((tab) => {
          const active = tab.id === current
          const heavy = active || (tab.id === 'report' && pending)
          return (
            <li className="tabbar__cell" key={tab.id} data-tab={tab.id}>
              <button
                type="button"
                className="tabbar__tab"
                aria-current={active ? 'page' : undefined}
                onClick={() => onChange(tab.id)}
              >
                <span className={`tabbar__label t-label${heavy ? ' tabbar__label--heavy' : ''}`}>
                  {t(tab.key)}
                </span>
              </button>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
