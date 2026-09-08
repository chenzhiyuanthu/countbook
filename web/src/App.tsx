import { lazy, Suspense, useEffect, useState } from 'react'
import { StoreProvider, useStore } from './app/store'
import { SyncProvider } from './app/sync'
import { TabBar, type TabId } from './ui/TabBar'
import { Toast } from './ui/Toast'
import { CaptureButton } from './ui/CaptureButton'
import Today from './screens/Today'
import './styles/base.css'
import './App.css'

// Only Today is on the critical path; the rest arrive as they are opened, which
// keeps the first paint of the standing figure immediate.
const Ledger = lazy(() => import('./screens/Ledger'))
const Report = lazy(() => import('./screens/Report'))
const Wants = lazy(() => import('./screens/Wants'))
const Settings = lazy(() => import('./screens/Settings'))
const Capture = lazy(() => import('./screens/Capture'))
const Reckoning = lazy(() => import('./screens/Reckoning'))

// The 记 button is offered only where logging a purchase is a plausible next
// action. On a report, a wishlist or a settings page it is an obstruction: it
// would sit over a figure that the reader came to read.
const CAPTURE_TABS: readonly TabId[] = ['today', 'ledger']

function Shell() {
  const { ready, t, ledger, today, now } = useStore()
  const [tab, setTab] = useState<TabId>('today')
  const [capturing, setCapturing] = useState(false)
  const [reckoning, setReckoning] = useState(false)

  // The reckoning is offered, never forced: it appears on its day and can be
  // dismissed, because a modal that blocks the ledger would make people stop
  // opening the app on Sundays.
  useEffect(() => {
    if (!ready) return
    const d = new Date(now)
    const due =
      d.getDay() === ledger.settings.reckoningWeekday && d.getHours() >= ledger.settings.reckoningHour
    const seen = sessionStorage.getItem('countbook.reckoned') === today
    if (due && !seen) setReckoning(true)
  }, [ready, now, today, ledger.settings.reckoningWeekday, ledger.settings.reckoningHour])

  if (!ready) {
    return (
      <div className="app app--booting">
        <span className="t-label">{t('common.loading')}</span>
      </div>
    )
  }

  const capturable = CAPTURE_TABS.includes(tab)

  return (
    <div className="app">
      <main className={`scroll${capturable ? ' scroll--capture' : ''}`} id="main">
        <Suspense fallback={<div className="screen-fallback" />}>
          {tab === 'today' && <Today onCapture={() => setCapturing(true)} onReckon={() => setReckoning(true)} />}
          {tab === 'ledger' && <Ledger />}
          {tab === 'report' && <Report />}
          {tab === 'wants' && <Wants onCapture={() => setCapturing(true)} />}
          {tab === 'settings' && <Settings />}
        </Suspense>
      </main>

      {capturable && <CaptureButton onClick={() => setCapturing(true)} label={t('capture.title')} />}
      <TabBar current={tab} onChange={setTab} />

      <Suspense fallback={null}>
        {capturing && <Capture onClose={() => setCapturing(false)} />}
        {reckoning && (
          <Reckoning
            onClose={() => {
              sessionStorage.setItem('countbook.reckoned', today)
              setReckoning(false)
            }}
          />
        )}
      </Suspense>

      <Toast />
    </div>
  )
}

export default function App() {
  return (
    <StoreProvider>
      <SyncProvider>
        <Shell />
      </SyncProvider>
    </StoreProvider>
  )
}
