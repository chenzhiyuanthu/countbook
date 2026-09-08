import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'

// The theme is read before React mounts so the first painted frame is already
// the right colour — a white flash on a dark phone is the cheapest tell that
// something is a web page.
try {
  const stored = localStorage.getItem('countbook.theme')
  const theme = stored ? (JSON.parse(stored) as string) : 'system'
  if (theme === 'light' || theme === 'dark') document.documentElement.setAttribute('data-theme', theme)
} catch {
  /* private mode; the default is correct anyway */
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    void navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`).catch(() => {
      /* offline support is a bonus, never a requirement */
    })
  })
}
