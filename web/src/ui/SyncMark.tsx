import { useStore } from '../app/store'
import { useSync } from '../app/sync'
import { Checkmark, ExclamationMark } from './icons'
import './SyncMark.css'

/**
 * One line, top right, on every screen: whether what was written here has
 * reached the server. It is the only place the app answers that question
 * without being asked, because a ledger that quietly stops syncing is a ledger
 * with two truths. The green is figSpared — the one colour the token set has
 * for "kept safe" — and it is the only time it is spent on anything but money.
 * With sync off the line is absent, not "off": sync is an enhancement.
 */
export function SyncMark({ onOpen }: { onOpen: () => void }) {
  const { t } = useStore()
  const { phase, config, pending, authExpired } = useSync()
  if (phase === 'off' || !config) return null

  const [tone, text, glyph]: [string, string, 'check' | 'bang' | null] =
    phase === 'locked' || authExpired
      ? ['alert', t('sync.mark.relogin'), 'bang']
      : phase === 'syncing'
        ? ['quiet', t('sync.syncing'), null]
        : phase === 'offline'
          ? ['quiet', t('sync.mark.offline'), null]
          : phase === 'error'
            ? ['alert', t('sync.mark.error'), 'bang']
            : pending
              ? ['held', t('sync.mark.pending'), null]
              : ['ok', t('sync.synced'), 'check']

  return (
    <div className="syncmark column">
      <button
        type="button"
        className={`syncmark__btn t-label syncmark--${tone}`}
        onClick={onOpen}
        aria-label={`${text} · ${t('sync.mark.open')}`}
        aria-live="polite"
      >
        {glyph === 'check' ? <Checkmark size={12} /> : glyph === 'bang' ? <ExclamationMark size={12} /> : null}
        <span>{text}</span>
      </button>
    </div>
  )
}
