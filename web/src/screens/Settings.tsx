import { useCallback, useEffect, useMemo, useState } from 'react'
import type { ChangeEvent, ReactNode } from 'react'
import { useStore } from '../app/store'
import { thisDeviceId, thisDeviceLabel, useSync } from '../app/sync'
import { WEEKDAYS } from '../app/i18n'
import { proposeStandard, standardAt } from '../core/compute'
import { addDays, diffDays, toDay } from '../core/date'
import { merge } from '../core/events'
import type { Event } from '../core/events'
import { newId } from '../core/id'
import { format, parse } from '../core/money'
import type { Fen } from '../core/money'
import type { Category, Settings as SettingsShape } from '../core/types'
import { TOKEN_URL } from '../sync/github'
import { listDevices, login, revokeDevice, signup } from '../sync/server'
import type { DeviceRow, ServerConfig } from '../sync/server'
import { Button, Field, Label, Rule, Segmented, Stepper } from '../ui/primitives'
import { Money } from '../ui/Money'
import './Settings.css'

/** Matches web/package.json; printed so a bug report can name a build. */
const APP_VERSION = '1.0.0'
/** The vault is only as strong as the passphrase, and this is the floor. */
const MIN_PASSPHRASE = 8
/** proposeStandard needs a 30-day span inside its 90-day window. */
const PROPOSAL_DAYS = 30
const DEFAULT_BRANCH = 'main'
/** SCREENS.md B8: the save receipt is a line that stands for three seconds. */
const SAVED_NOTE_MS = 3000

const yuan = (fen: Fen): string => (fen / 100).toFixed(2)
const pad = (n: number): string => String(n).padStart(2, '0')

const stamp = (ms: number): string => {
  const d = new Date(ms)
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

const reason = (err: unknown): string => (err instanceof Error ? err.message : String(err))

const sameAmounts = (a: Record<string, Fen>, b: Record<string, Fen>): boolean => {
  const ka = Object.keys(a)
  const kb = Object.keys(b)
  return ka.length === kb.length && ka.every((k) => a[k] === b[k])
}

function Section({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="settings__section">
      <div className="settings__head">
        <Label>{title}</Label>
        {action ?? null}
      </div>
      <Rule strong />
      {children}
    </section>
  )
}

/** A text action that still occupies a full hit target without a box around it. */
function LinkButton({
  children, onClick, ariaLabel, disabled,
}: {
  children: ReactNode
  onClick: () => void
  ariaLabel?: string
  disabled?: boolean
}) {
  return (
    <button
      type="button"
      className="settings__link t-body"
      onClick={onClick}
      aria-label={ariaLabel}
      disabled={disabled}
    >
      {children}
    </button>
  )
}

/* ── 标准线 ──────────────────────────────────────────────────────────── */

function StandardSection() {
  const { t, ledger, today, now, commit } = useStore()
  const settings = ledger.settings
  const current = useMemo(() => standardAt(ledger, now), [ledger, now])
  const proposal = useMemo(() => proposeStandard(ledger, today), [ledger, today])

  const categories = useMemo(
    () =>
      [...ledger.categories.values()]
        .filter((c) => c.kind === 'spend' && !c.archived)
        .sort((a, b) => a.order - b.order),
    [ledger.categories],
  )

  const [monthly, setMonthly] = useState(() => (current.monthlyFen ? yuan(current.monthlyFen) : ''))
  const [per, setPer] = useState<Record<string, string>>(() => {
    const seed: Record<string, string> = {}
    for (const [id, fen] of Object.entries(current.perCategory)) if (fen > 0) seed[id] = yuan(fen)
    return seed
  })
  const [leak, setLeak] = useState(() => yuan(settings.leakCeilingFen))
  const [cooling, setCooling] = useState(() => yuan(settings.coolingFloorFen))
  const [weekday, setWeekday] = useState(settings.reckoningWeekday)
  const [hour, setHour] = useState(settings.reckoningHour)
  const [logged, setLogged] = useState(false)

  // The line only appears for the three seconds after a save; it is a receipt,
  // not a permanent piece of the page.
  useEffect(() => {
    if (!logged) return
    const id = window.setTimeout(() => setLogged(false), SAVED_NOTE_MS)
    return () => window.clearTimeout(id)
  }, [logged])

  const monthlyFen = parse(monthly)
  const leakFen = parse(leak)
  const coolingFen = parse(cooling)

  const perFen: Record<string, Fen> = {}
  let perValid = true
  for (const c of categories) {
    const raw = (per[c.id] ?? '').trim()
    if (!raw) continue
    const v = parse(raw)
    if (v === null) perValid = false
    else if (v > 0) perFen[c.id] = v
  }

  const allocated = Object.values(perFen).reduce((a, b) => a + b, 0)
  const unallocated = (monthlyFen ?? 0) - allocated

  const standardChanged =
    monthlyFen !== null && (monthlyFen !== current.monthlyFen || !sameAmounts(perFen, current.perCategory))
  const thresholdsChanged =
    (leakFen !== null && leakFen !== settings.leakCeilingFen) ||
    (coolingFen !== null && coolingFen !== settings.coolingFloorFen) ||
    weekday !== settings.reckoningWeekday ||
    hour !== settings.reckoningHour

  const canSave =
    monthlyFen !== null && monthlyFen > 0 && perValid && leakFen !== null && coolingFen !== null &&
    (standardChanged || thresholdsChanged)

  const save = () => {
    if (monthlyFen === null || leakFen === null || coolingFen === null) return
    if (thresholdsChanged) {
      const patch: Partial<SettingsShape> = {
        leakCeilingFen: leakFen,
        coolingFloorFen: coolingFen,
        reckoningWeekday: weekday,
        reckoningHour: hour,
      }
      commit({ t: 'settings.patch', patch })
    }
    // A threshold is part of the line you are measured against, so changing one
    // is dated in the same log a standard change is (PRODUCT.md AC-15.3).
    commit(
      standardChanged
        ? { t: 'standard.set', monthlyFen, perCategory: perFen }
        : { t: 'standard.set', monthlyFen, perCategory: perFen, reason: t('settings.thresholds') },
    )
    setLogged(true)
  }

  const gateDays = useMemo(() => {
    if (proposal) return 0
    const since = addDays(today, -90)
    let first: string | null = null
    for (const e of ledger.entries.values()) {
      if (e.kind !== 'spend' || e.day < since || e.day > today) continue
      if (first === null || e.day < first) first = e.day
    }
    return first === null ? PROPOSAL_DAYS : Math.max(1, PROPOSAL_DAYS - diffDays(first, today))
  }, [proposal, ledger.entries, today])

  const revisions = useMemo(() => [...ledger.standards].reverse(), [ledger.standards])

  return (
    <Section title={t('standard.title')}>
      {current.monthlyFen === 0 ? <p className="t-body settings__hint">{t('standard.empty')}</p> : null}

      <div className="settings__stack">
        <Field
          label={t('standard.monthly')}
          value={monthly}
          onChange={setMonthly}
          type="number"
          mono
          suffix={t('settings.yuan')}
        />
        {proposal ? (
          <div className="settings__propose">
            <span className="t-label ink-300">{t('standard.propose', { amount: format(proposal.monthlyFen) })}</span>
            <LinkButton onClick={() => setMonthly(yuan(proposal.monthlyFen))}>{t('standard.accept')}</LinkButton>
          </div>
        ) : (
          <p className="t-label ink-300">{t('standard.proposeGate', { n: gateDays })}</p>
        )}
      </div>

      <div className="settings__block">
        <Label>{t('standard.perCategory')}</Label>
        <ul>
          {categories.map((c) => {
            const name = c.nameEn && ledger.settings.locale === 'en' ? c.nameEn : c.name
            const suggested = proposal?.perCategory[c.id]
            return (
              <li className="settings__cat" key={c.id}>
                <label className="settings__cat-line">
                  <span className="t-body settings__cat-name">{name}</span>
                  <input
                    className="settings__amount t-row"
                    type="text"
                    inputMode="decimal"
                    value={per[c.id] ?? ''}
                    placeholder={t('standard.unset')}
                    onChange={(e) => setPer((prev) => ({ ...prev, [c.id]: e.target.value }))}
                  />
                </label>
                {suggested !== undefined && suggested > 0 ? (
                  <div className="settings__propose">
                    <span className="t-label ink-300">{t('standard.suggest', { amount: format(suggested) })}</span>
                    <LinkButton
                      ariaLabel={`${name} · ${t('standard.accept')}`}
                      onClick={() => setPer((prev) => ({ ...prev, [c.id]: yuan(suggested) }))}
                    >
                      {t('standard.accept')}
                    </LinkButton>
                  </div>
                ) : null}
              </li>
            )
          })}
        </ul>
        <p className={`t-label ${unallocated < 0 ? 'fig-over' : 'ink-500'}`}>
          {unallocated < 0
            ? t('standard.allocOver', { a: format(allocated), b: format(-unallocated) })
            : t('standard.alloc', { a: format(allocated), b: format(monthlyFen ?? 0) })}
        </p>
      </div>

      <div className="settings__block">
        <Label>{t('settings.thresholds')}</Label>
        <div className="settings__stack">
          <Field
            label={t('settings.leakCeiling')}
            value={leak}
            onChange={setLeak}
            type="number"
            mono
            suffix={t('settings.yuan')}
          />
          <p className="t-label ink-500">{t('settings.leakCeilingHint')}</p>
          <Field
            label={t('settings.coolingFloor')}
            value={cooling}
            onChange={setCooling}
            type="number"
            mono
            suffix={t('settings.yuan')}
          />
          <p className="t-label ink-500">{t('settings.coolingFloorHint')}</p>
          <div className="settings__row">
            <span className="t-body">{t('settings.reckoningDay')}</span>
            <Stepper
              label={t('settings.reckoningDay')}
              value={weekday}
              onChange={setWeekday}
              min={0}
              max={6}
              format={(n) => WEEKDAYS[ledger.settings.locale][n] ?? String(n)}
            />
          </div>
          <div className="settings__row">
            <span className="t-body">{t('settings.reckoningHour')}</span>
            <Stepper
              label={t('settings.reckoningHour')}
              value={hour}
              onChange={setHour}
              min={0}
              max={23}
              format={(n) => `${pad(n)}:00`}
            />
          </div>
        </div>
      </div>

      <div className="settings__block">
        <Label>{t('standard.revisions')}</Label>
        {revisions.length === 0 ? (
          <p className="t-body ink-500">{t('standard.revisionsEmpty')}</p>
        ) : (
          <ul>
            {revisions.map((r) => (
              <li className="settings__revision" key={r.id}>
                <span className="t-mono t-label ink-500">{toDay(new Date(r.at))}</span>
                <Money fen={r.monthlyFen} size="row" />
                {r.reason ? <span className="t-label ink-500">{r.reason}</span> : null}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="settings__actions">
        <Button variant="primary" fullWidth disabled={!canSave} onClick={save}>
          {t('standard.save')}
        </Button>
      </div>
      {logged ? <p className="t-label ink-500">{t('standard.saved')}</p> : null}
    </Section>
  )
}

/* ── 心愿物 ──────────────────────────────────────────────────────────── */

function WishSection() {
  const { t, ledger, commit } = useStore()
  const wish = ledger.settings.wishObject
  const [name, setName] = useState(wish?.name ?? '')
  const [price, setPrice] = useState(wish && wish.priceFen > 0 ? yuan(wish.priceFen) : '')

  const priceFen = parse(price)
  const trimmed = name.trim()
  const changed = trimmed !== (wish?.name ?? '') || priceFen !== (wish?.priceFen ?? null)
  const canSave = trimmed.length > 0 && priceFen !== null && priceFen > 0 && changed

  return (
    <Section title={t('settings.wishObject')}>
      <p className="t-body ink-500">{t('settings.wishObjectHint')}</p>
      <div className="settings__stack">
        <Field label={t('settings.wishName')} value={name} onChange={setName} maxLength={12} />
        <Field
          label={t('settings.wishPrice')}
          value={price}
          onChange={setPrice}
          type="number"
          mono
          suffix={t('settings.yuan')}
        />
      </div>
      <div className="settings__actions">
        <Button
          onClick={() => {
            if (priceFen === null) return
            commit({ t: 'settings.patch', patch: { wishObject: { name: trimmed, priceFen } } })
          }}
          disabled={!canSave}
        >
          {t('common.save')}
        </Button>
        {wish && wish.priceFen > 0 ? (
          <Button
            variant="danger"
            onClick={() => {
              // Cleared by writing an empty object rather than dropping the key:
              // an undefined field does not survive JSON on its way to another
              // device, and a clear that only works locally is a lie.
              commit({ t: 'settings.patch', patch: { wishObject: { name: '', priceFen: 0 } } })
              setName('')
              setPrice('')
            }}
          >
            {t('common.delete')}
          </Button>
        ) : null}
      </div>
    </Section>
  )
}

/* ── 显示 ────────────────────────────────────────────────────────────── */

function DisplaySection() {
  const { t, ledger, commit } = useStore()
  const settings = ledger.settings
  return (
    <Section title={t('settings.appearance')}>
      <div className="settings__stack">
        <div>
          <Label>{t('settings.appearance')}</Label>
          <Segmented
            ariaLabel={t('settings.appearance')}
            value={settings.theme}
            onChange={(theme) => commit({ t: 'settings.patch', patch: { theme } })}
            options={[
              { value: 'system', label: t('settings.theme.system') },
              { value: 'light', label: t('settings.theme.light') },
              { value: 'dark', label: t('settings.theme.dark') },
            ]}
          />
        </div>
        <div>
          <Label>{t('settings.language')}</Label>
          <Segmented
            ariaLabel={t('settings.language')}
            value={settings.locale}
            onChange={(locale) => commit({ t: 'settings.patch', patch: { locale } })}
            options={[
              { value: 'zh-CN', label: '简体中文' },
              { value: 'en', label: 'English' },
            ]}
          />
        </div>
      </div>
    </Section>
  )
}

/* ── 分类 ────────────────────────────────────────────────────────────── */

function CategoriesSection() {
  const { t, ledger, commit, locale } = useStore()
  const [kind, setKind] = useState<'spend' | 'income'>('spend')
  const [drafts, setDrafts] = useState<Record<string, string>>({})
  const [added, setAdded] = useState('')

  const labelOf = useCallback((c: Category) => (locale === 'en' ? c.nameEn : c.name), [locale])

  const rows = useMemo(
    () => [...ledger.categories.values()].filter((c) => c.kind === kind).sort((a, b) => a.order - b.order),
    [ledger.categories, kind],
  )

  // A category that has never been used can be deleted outright; one that has
  // been is archived instead, so an old row keeps its name.
  const used = useMemo(() => {
    const s = new Set<string>()
    for (const e of ledger.entries.values()) s.add(e.categoryId)
    for (const sub of ledger.subs.values()) s.add(sub.categoryId)
    return s
  }, [ledger.entries, ledger.subs])

  const rename = (c: Category) => {
    const next = (drafts[c.id] ?? '').trim()
    setDrafts((prev) => {
      const rest = { ...prev }
      delete rest[c.id]
      return rest
    })
    if (!next || next === labelOf(c)) return
    commit({ t: 'category.upsert', category: locale === 'en' ? { ...c, nameEn: next } : { ...c, name: next } })
  }

  const add = () => {
    const name = added.trim()
    if (!name) return
    const order = rows.reduce((a, c) => Math.max(a, c.order), -1) + 1
    commit({ t: 'category.upsert', category: { id: newId(), name, nameEn: name, kind, order } })
    setAdded('')
  }

  return (
    <Section title={t('settings.categories')}>
      <Segmented
        ariaLabel={t('settings.categories')}
        value={kind}
        onChange={setKind}
        options={[
          { value: 'spend', label: t('capture.spend') },
          { value: 'income', label: t('capture.income') },
        ]}
      />
      <ul>
        {rows.map((c) => (
          <li className="settings__row" key={c.id}>
            <input
              className="settings__name t-body"
              type="text"
              value={drafts[c.id] ?? labelOf(c)}
              aria-label={t('settings.categoryName')}
              onChange={(e) => setDrafts((prev) => ({ ...prev, [c.id]: e.target.value }))}
              onBlur={() => rename(c)}
            />
            <span className="settings__actions">
              <LinkButton
                ariaLabel={`${labelOf(c)} · ${c.archived ? t('settings.categoryRestore') : t('settings.categoryArchive')}`}
                onClick={() => commit({ t: 'category.upsert', category: { ...c, archived: !c.archived } })}
              >
                {c.archived ? t('settings.categoryRestore') : t('settings.categoryArchive')}
              </LinkButton>
              {used.has(c.id) ? null : (
                <LinkButton
                  ariaLabel={`${labelOf(c)} · ${t('common.delete')}`}
                  onClick={() => commit({ t: 'category.remove', target: c.id })}
                >
                  {t('common.delete')}
                </LinkButton>
              )}
            </span>
          </li>
        ))}
      </ul>
      <div className="settings__stack">
        <Field label={t('settings.categoryAdd')} value={added} onChange={setAdded} maxLength={8} />
        <div className="settings__actions">
          <Button onClick={add} disabled={!added.trim()}>
            {t('settings.categoryAdd')}
          </Button>
        </div>
      </div>
    </Section>
  )
}

/* ── 设备与同步 ──────────────────────────────────────────────────────── */

function SyncSection() {
  const { t } = useStore()
  const { phase, config, fingerprint, message, lastSyncedAt, syncNow, disconnect, unlock } = useSync()

  if (phase === 'off' || !config) {
    return (
      <Section title={t('sync.title')}>
        <p className="t-body ink-700">{t('sync.offNote')}</p>
        <ConnectForms />
      </Section>
    )
  }

  if (phase === 'locked') {
    return (
      <Section title={t('sync.title')}>
        <p className="t-body ink-700">{t('sync.locked')}</p>
        <UnlockForm onUnlock={unlock} />
        <div className="settings__actions">
          <Button variant="danger" onClick={disconnect}>
            {t('sync.disconnect')}
          </Button>
        </div>
      </Section>
    )
  }

  // One word, never a spinner (SCREENS.md Y8); the timestamp is its own line.
  const state =
    phase === 'syncing'
      ? t('sync.syncing')
      : phase === 'offline'
        ? t('sync.offline')
        : phase === 'error'
          ? t('sync.error', { message })
          : t('sync.synced')

  return (
    <Section title={t('sync.title')} action={<span className="t-mono t-label ink-700">{state}</span>}>
      <div className="settings__row">
        <span className="t-body">{config.kind === 'github' ? t('sync.github') : t('sync.server')}</span>
        <span className="t-mono t-label ink-500">
          {config.kind === 'github' ? `${config.owner}/${config.repo}` : config.email}
        </span>
      </div>
      {lastSyncedAt ? (
        <p className="t-mono t-label ink-500">{t('sync.lastSeen', { time: stamp(lastSyncedAt) })}</p>
      ) : null}

      <div className="settings__actions">
        <Button onClick={() => void syncNow()} disabled={phase === 'syncing'}>
          {t('sync.now')}
        </Button>
      </div>

      {fingerprint ? <Fingerprint value={fingerprint} /> : null}
      {config.kind === 'server' ? <Devices cfg={config} /> : null}

      <div className="settings__block">
        <p className="t-body ink-500">{t('sync.disconnectHint')}</p>
        <div className="settings__actions">
          <Button variant="danger" onClick={disconnect}>
            {t('sync.disconnect')}
          </Button>
        </div>
      </div>
    </Section>
  )
}

function Fingerprint({ value }: { value: string }) {
  const { t, toast } = useStore()
  return (
    <div className="settings__block">
      <Label>{t('sync.fingerprint')}</Label>
      <button
        type="button"
        className="settings__fingerprint t-mono t-row"
        aria-label={`${t('sync.fingerprint')} ${value}`}
        onClick={() => void navigator.clipboard?.writeText(value).then(() => toast(t('sync.copied')))}
      >
        {value}
      </button>
      <p className="t-label ink-500">{t('sync.fingerprintHint')}</p>
    </div>
  )
}

function Devices({ cfg }: { cfg: ServerConfig }) {
  const { t } = useStore()
  const [rows, setRows] = useState<DeviceRow[]>([])
  const [error, setError] = useState('')
  const [pending, setPending] = useState<string | null>(null)

  const load = useCallback(() => {
    listDevices(cfg)
      .then((r) => setRows(r.devices))
      .catch((e: unknown) => setError(reason(e)))
  }, [cfg])

  useEffect(load, [load])

  const revoke = (ref: string) => {
    setPending(null)
    revokeDevice(cfg, ref)
      .then(load)
      .catch((e: unknown) => setError(reason(e)))
  }

  if (!rows.length) return error ? <p className="t-label ink-500">{error}</p> : null

  return (
    <div className="settings__block">
      <Label>{t('sync.devices')}</Label>
      <ul>
        {rows.map((d) => (
          <li className="settings__device" key={d.ref}>
            <span className="t-body">{d.label || d.device}</span>
            <span className="t-mono t-label ink-500">
              {d.current ? t('sync.thisDevice') : stamp(d.seenAt)}
            </span>
            {d.current ? null : pending === d.ref ? (
              <span className="settings__actions">
                <span className="t-label ink-500">{t('sync.revokeConfirm')}</span>
                <LinkButton onClick={() => revoke(d.ref)}>{t('common.confirm')}</LinkButton>
                <LinkButton onClick={() => setPending(null)}>{t('common.cancel')}</LinkButton>
              </span>
            ) : (
              <LinkButton
                ariaLabel={`${d.label || d.device} · ${t('sync.revoke')}`}
                onClick={() => setPending(d.ref)}
              >
                {t('sync.revoke')}
              </LinkButton>
            )}
          </li>
        ))}
      </ul>
      {error ? <p className="t-label ink-500">{error}</p> : null}
    </div>
  )
}

function UnlockForm({ onUnlock }: { onUnlock: (passphrase: string) => Promise<void> }) {
  const { t } = useStore()
  const [pass, setPass] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const submit = () => {
    setBusy(true)
    setError('')
    onUnlock(pass)
      .catch((e: unknown) => setError(reason(e)))
      .finally(() => setBusy(false))
  }

  return (
    <div className="settings__stack">
      <Field label={t('sync.passphrase')} value={pass} onChange={setPass} type="password" />
      {error ? <p className="t-body ink-700">{error}</p> : null}
      <div className="settings__actions">
        <Button variant="primary" onClick={submit} disabled={busy || pass.length < MIN_PASSPHRASE}>
          {busy ? t('sync.connecting') : t('sync.unlock')}
        </Button>
      </div>
    </div>
  )
}

/** The passphrase pair, shared by both adapters: typed twice, never sent. */
function PassphrasePair({
  pass, again, onPass, onAgain,
}: {
  pass: string
  again: string
  onPass: (v: string) => void
  onAgain: (v: string) => void
}) {
  const { t } = useStore()
  const problem =
    pass.length > 0 && pass.length < MIN_PASSPHRASE
      ? t('sync.passphraseShort')
      : again.length > 0 && pass !== again
        ? t('sync.passphraseMismatch')
        : ''
  return (
    <>
      <Field label={t('sync.passphrase')} value={pass} onChange={onPass} type="password" />
      <Field label={t('sync.passphraseAgain')} value={again} onChange={onAgain} type="password" />
      <p className="t-body ink-500">{t('sync.passphraseHint')}</p>
      {problem ? <p className="t-body ink-700">{problem}</p> : null}
    </>
  )
}

function ConnectForms() {
  const { t } = useStore()
  const [kind, setKind] = useState<'github' | 'server'>('github')
  return (
    <div className="settings__block">
      <Label>{t('sync.choose')}</Label>
      <Segmented
        ariaLabel={t('sync.choose')}
        value={kind}
        onChange={setKind}
        options={[
          { value: 'github', label: t('sync.github') },
          { value: 'server', label: t('sync.server') },
        ]}
      />
      {kind === 'github' ? <GitHubForm /> : <ServerForm />}
    </div>
  )
}

function GitHubForm() {
  const { t } = useStore()
  const { connectGitHub } = useSync()
  const [owner, setOwner] = useState('')
  const [repo, setRepo] = useState('')
  const [branch, setBranch] = useState(DEFAULT_BRANCH)
  const [token, setToken] = useState('')
  const [pass, setPass] = useState('')
  const [again, setAgain] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const ready =
    owner.trim().length > 0 && repo.trim().length > 0 && token.trim().length > 0 &&
    pass.length >= MIN_PASSPHRASE && pass === again

  const submit = () => {
    setBusy(true)
    setError('')
    connectGitHub(
      { owner: owner.trim(), repo: repo.trim(), branch: branch.trim() || DEFAULT_BRANCH, token: token.trim() },
      pass,
      true,
    )
      .catch((e: unknown) => setError(reason(e)))
      .finally(() => setBusy(false))
  }

  return (
    <div className="settings__stack">
      <p className="t-body ink-500">{t('sync.githubHint')}</p>
      <Field label={t('sync.owner')} value={owner} onChange={setOwner} mono />
      <Field label={t('sync.repo')} value={repo} onChange={setRepo} mono />
      <Field label={t('sync.branch')} value={branch} onChange={setBranch} mono />
      <Field label={t('sync.token')} value={token} onChange={setToken} type="password" mono />
      <a className="t-body settings__external" href={TOKEN_URL} target="_blank" rel="noreferrer">
        {t('sync.tokenHelp')}
      </a>
      <PassphrasePair pass={pass} again={again} onPass={setPass} onAgain={setAgain} />
      {error ? <p className="t-body ink-700">{error}</p> : null}
      <div className="settings__actions">
        <Button variant="primary" fullWidth onClick={submit} disabled={busy || !ready}>
          {busy ? t('sync.connecting') : t('sync.connect')}
        </Button>
      </div>
    </div>
  )
}

function ServerForm() {
  const { t } = useStore()
  const { connectServer } = useSync()
  const [mode, setMode] = useState<'login' | 'signup'>('login')
  const [url, setUrl] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [code, setCode] = useState('')
  const [pass, setPass] = useState('')
  const [again, setAgain] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const ready =
    url.trim().length > 0 && email.trim().length > 0 && password.length > 0 &&
    pass.length >= MIN_PASSPHRASE && pass === again

  const submit = () => {
    setBusy(true)
    setError('')
    const base = url.trim().replace(/\/+$/, '')
    const account = email.trim()
    const auth =
      mode === 'signup'
        ? signup(base, account, password, code.trim(), thisDeviceId(), thisDeviceLabel())
        : login(base, account, password, thisDeviceId(), thisDeviceLabel())
    auth
      .then((session) => connectServer({ baseUrl: base, token: session.token, email: account }, pass, true))
      .catch((e: unknown) => setError(reason(e)))
      .finally(() => setBusy(false))
  }

  return (
    <div className="settings__stack">
      <p className="t-body ink-500">{t('sync.serverHint')}</p>
      <Segmented
        ariaLabel={t('sync.server')}
        value={mode}
        onChange={setMode}
        options={[
          { value: 'login', label: t('sync.login') },
          { value: 'signup', label: t('sync.signup') },
        ]}
      />
      <Field label={t('sync.serverUrl')} value={url} onChange={setUrl} mono placeholder="https://" />
      <Field label={t('sync.email')} value={email} onChange={setEmail} mono />
      <Field label={t('sync.password')} value={password} onChange={setPassword} type="password" />
      {mode === 'signup' ? <Field label={t('sync.code')} value={code} onChange={setCode} mono /> : null}
      <PassphrasePair pass={pass} again={again} onPass={setPass} onAgain={setAgain} />
      {error ? <p className="t-body ink-700">{error}</p> : null}
      <div className="settings__actions">
        <Button variant="primary" fullWidth onClick={submit} disabled={busy || !ready}>
          {busy ? t('sync.connecting') : mode === 'signup' ? t('sync.signup') : t('sync.login')}
        </Button>
      </div>
    </div>
  )
}

/* ── 数据 ────────────────────────────────────────────────────────────── */

interface Bundle {
  app: string
  schemaVersion: number
  exportedAt: string
  currency: string
  settings: SettingsShape
  events: Event[]
}

/**
 * What travels is the event log, not a snapshot: corrections, voidances and
 * verdicts are events, so a log restores the ledger down to the day a figure
 * was changed, which a snapshot cannot.
 */
function readBundle(text: string): Event[] | null {
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch {
    return null
  }
  if (typeof data !== 'object' || data === null) return null
  const bundle = data as Record<string, unknown>
  if (bundle['app'] !== 'countbook' || !Array.isArray(bundle['events'])) return null
  const out: Event[] = []
  for (const raw of bundle['events'] as unknown[]) {
    if (typeof raw !== 'object' || raw === null) return null
    const e = raw as Record<string, unknown>
    if (
      typeof e['id'] !== 'string' || typeof e['hlc'] !== 'string' ||
      typeof e['dev'] !== 'string' || typeof e['t'] !== 'string'
    ) {
      return null
    }
    out.push(raw as Event)
  }
  return out
}

function DataSection() {
  const { t, events, ledger, today, replaceAll, toast } = useStore()
  const [error, setError] = useState('')

  const exportAll = () => {
    const bundle: Bundle = {
      app: 'countbook',
      schemaVersion: 1,
      exportedAt: new Date().toISOString(),
      currency: ledger.settings.currency,
      settings: ledger.settings,
      events,
    }
    const url = URL.createObjectURL(new Blob([JSON.stringify(bundle)], { type: 'application/json' }))
    const a = document.createElement('a')
    a.href = url
    a.download = `countbook-${today}.json`
    a.click()
    // Safari cancels a download whose blob URL is revoked in the same task.
    window.setTimeout(() => URL.revokeObjectURL(url))
  }

  const onFile = (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setError('')
    void file.text().then((text) => {
      const incoming = readBundle(text)
      if (!incoming) {
        setError(t('settings.importInvalid'))
        return
      }
      // Merge, never replace: a backup restored onto a device that has kept
      // recording must not delete what was recorded since the backup.
      const merged = merge(events, incoming)
      const gained = merged.length - events.length
      replaceAll(merged)
      toast(t('settings.importSummary', { n: gained, skip: incoming.length - gained }))
    })
  }

  return (
    <Section title={t('settings.data')}>
      <div className="settings__actions">
        <Button onClick={exportAll}>{t('settings.export')}</Button>
        <label className="settings__file t-body">
          <span>{t('settings.import')}</span>
          <input type="file" accept="application/json,.json" onChange={onFile} />
        </label>
      </div>
      <p className="t-label ink-500">{t('settings.exportHint', { n: events.length })}</p>
      {error ? <p className="t-body ink-700">{error}</p> : null}
    </Section>
  )
}

/* ── the screen ──────────────────────────────────────────────────────── */

export default function Settings() {
  const { t } = useStore()
  return (
    <div className="column settings">
      <h1 className="t-label settings__title">{t('settings.title')}</h1>
      <StandardSection />
      <WishSection />
      <SyncSection />
      <CategoriesSection />
      <DisplaySection />
      <DataSection />
      <p className="t-micro settings__about">{t('settings.version', { version: APP_VERSION })}</p>
    </div>
  )
}
