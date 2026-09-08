import { useStore } from '../app/store'
import './CaptureButton.css'

/**
 * The one primary action in the app: a circle of ink with the character 记 in
 * it. Not a plus, not an icon, no shadow — it is a stamp, and it reads as one.
 */
export function CaptureButton({ onClick, label }: { onClick: () => void; label: string }) {
  const { t } = useStore()
  return (
    <button type="button" className="capture-button" onClick={onClick} aria-label={label}>
      <span className="capture-button__mark" aria-hidden="true">
        {t('capture.mark')}
      </span>
    </button>
  )
}
