# 据实 · Countbook — implementation contract (web)

Read this before writing any file under `web/src/ui/` or `web/src/screens/`.
`docs/DESIGN.md` says what things look like, `docs/SCREENS.md` says what is on
each screen and what it says, `docs/PRODUCT.md` says what the rules are. This
file says what already exists and how to call it, so that files written
independently compose without a conflict.

## Ground rules

- **TypeScript, strict.** `noUncheckedIndexedAccess` is on: `arr[i]` is `T |
  undefined`, so use `arr[i]!` only where the index is provably in range.
  `verbatimModuleSyntax` is on: type-only imports must say `import type`.
- **No new dependencies.** React 19 and the standard library, nothing else. No
  chart library, no icon library, no CSS framework, no date library.
- **No hard-coded colours, sizes, radii, durations.** They exist once, in
  `design/tokens.json`, generated into `web/src/styles/tokens.css` as custom
  properties (`var(--c-ink900)`, `var(--s-4)`, `var(--r-card)`, `var(--d-sheet-present)`,
  `var(--ease)`). If a value you need is missing, use the closest existing token
  rather than inventing a literal.
- **Each component owns a sibling `.css` file** imported from its `.tsx`. Class
  names are namespaced to the component (`.today__hero`, `.keypad__key`) so two
  files written independently cannot collide. Shared helpers already exist in
  `web/src/styles/base.css`: `.column .scroll .row .card .rule .stack .section
  .t-hero .t-screen .t-section .t-row .t-body .t-label .t-micro .t-mono
  .ink-900 .ink-700 .ink-500 .ink-300 .fig-over .fig-held .fig-spared
  .fig-regret .sr-only`.
- **Chinese first.** Never write a user-facing string inline — call `t('key')`.
  If a key is missing from `web/src/app/i18n.ts`, add it there in the same
  `['中文', 'English']` shape.
- **The clerk's voice.** State the fact. No praise, no scolding, no exclamation
  marks, no emoji anywhere in the product.
- Comments explain *why*, never *what*. Do not narrate the code.

## What already exists

### `web/src/core/` — pure domain logic, fully tested. Do not modify.

```ts
// money.ts
type Fen = number                       // integer 分; never a float
parts(fen, currency?) -> { sign, symbol, int, frac }   // for the split rendering
format(fen, currency?) -> string        // '−¥84.20'   (U+2212, exported as MINUS)
formatYuan(fen) -> string               // '¥1,238'    (no 分, for chart labels)
parse(input) -> Fen | null
divideRemainderLast(total, n) -> { per, last }

// date.ts   Day = 'YYYY-MM-DD', Month = 'YYYY-MM' — always local civil dates
toDay(Date) fromDay(Day) monthOf(Day) daysInMonth(Month) dayOfMonth(Month, n)
addDays(Day, n) addCalendarMonths(Day, n) addMonths(Month, n) diffDays(a, b)
weekdayOf(Day) isWeekend(Day) allDaysOf(Month) daysRemainingInMonth(Day)
lastNDays(Day, n)

// types.ts
Intent = 'need' | 'want' | 'impulse'    // 必要 / 想要 / 冲动
Entry Category Wish Sub SubStatus StandardRevision Settings Ledger Correction Voidance

// compute.ts — every formula the product prints
available(L, today, nowMs) -> { perDay, standard, spent, fixedRemaining, remaining, daysLeft, recoveryDays }
leak(L, today)             -> { count, sum, divisor, equivalent, byMerchant }
regret(L, today, minSample?) -> { month, year, judged, notWorth, rate?, pending }
regretByCategory(L, today) -> ranked by amount, not by rate
commitWarning(L, today, categoryId, amount) -> string | null   // the save-button suffix
deviationByCategory(L, month, nowMs) -> { categoryId, spent, standard, delta }[]
monthStrip(L, month, today, nowMs)   -> { bars, dailyStandard, max }
streak(L, today, nowMs) -> number
coolingDays(priceFen) -> 1..14
wishStats(L, today, nowMs) -> { abstainedYear, abstainedAll, cooling, ready }
subViews(L, today) -> { rows: { sub, annual, paidSoFar, perUse? }[], annual, perDay }
savedByCancelling(L, today) -> Fen
detectRecurring(L, today) -> Detected[]
hourScatter(L, today, days?) -> { hour, count, sum }[]
regretAsWishObject(L, regretYear) -> { name, fraction } | null
proposeStandard(L, today) -> { monthlyFen, perCategory } | null
reckoningQueue(L, today, maxCards?) -> EffectiveEntry[]
effective(L) -> Map<id, EffectiveEntry>   // EffectiveEntry = Entry & { effective, correction?, voidance? }
standardAt(L, atMs) -> { monthlyFen, perCategory }
```

### `web/src/app/store.tsx`

```ts
const { ready, ledger, events, today, now, t, locale,
        commit, absorb, undo, replaceAll, toast, toastState, dismissToast } = useStore()
```

- `ledger: Ledger` is the folded state — the only thing to read.
- `commit(payload) -> eventId` appends one event. Payload variants are the
  `Payload` union in `web/src/core/events.ts`; the envelope (id, HLC, device) is
  added for you. **Never mutate the ledger; always commit an event.**
- `undo(eventId)` drops an event committed moments ago on this device — used by
  the undo toast, never for anything a sync could already have carried away.
- `toast(message, { label, run }?)` shows the one toast slot.
- `today: Day` and `now: number` are refreshed on a timer and on focus. Use them
  instead of calling `Date.now()` in a component, so renders stay pure.

### `web/src/app/sync.tsx`

```ts
const { phase, config, fingerprint, message, lastSyncedAt,
        connectGitHub, connectServer, unlock, disconnect, syncNow } = useSync()
// phase: 'off' | 'locked' | 'idle' | 'syncing' | 'offline' | 'error'
```

### `web/src/app/i18n.ts`

`t(key, vars?)` — `vars` fills `{name}` placeholders. Add keys here, in order,
in the `['中文','English']` shape. `WEEKDAYS[locale]` is the day-name table.

## File ownership

Write only the files listed for your task. If you need something from another
agent's file, code against the signature written here and do not create it.

| Path | Exports |
|---|---|
| `web/src/ui/Money.tsx` | `Money`, `MoneyText` |
| `web/src/ui/primitives.tsx` | `Card` `Row` `Rule` `Label` `Button` `Segmented` `Sheet` `Field` `Stepper` `EmptyState` `ProgressRule` `Ring` |
| `web/src/ui/TabBar.tsx` | `TabBar`, `TabId` |
| `web/src/ui/Toast.tsx` | `Toast` |
| `web/src/ui/CaptureButton.tsx` | `CaptureButton` |
| `web/src/ui/charts.tsx` | `MonthStrip` `DeviationBars` `RegretBlocks` `AnnualBar` `HourScatter` `YearLedger` |
| `web/src/screens/Today.tsx` | default `Today({ onCapture, onReckon })` |
| `web/src/screens/Capture.tsx` | default `Capture({ onClose })` |
| `web/src/screens/Ledger.tsx` | default `Ledger()` |
| `web/src/screens/Report.tsx` | default `Report()` |
| `web/src/screens/Wants.tsx` | default `Wants({ onCapture })` |
| `web/src/screens/Settings.tsx` | default `Settings()` |
| `web/src/screens/Reckoning.tsx` | default `Reckoning({ onClose })` |

## Component signatures other files rely on

```tsx
// Money.tsx — the ONLY place the three-part ¥ / integer / 分 treatment exists.
// Renders <span class="money"> with the 分 at reduced size and ink-300, tabular
// figures, and the complete formatted string as aria-label.
<Money fen={12640} size="hero" | "screen" | "section" | "row" | "body" tone?="over"|"held"|"spared"|"regret" currency?="CNY" />
MoneyText(fen, currency?) -> string    // plain string, for aria and exports

// primitives.tsx
<Card>…</Card>
<Row left={ReactNode} right={ReactNode} sub={ReactNode} onClick?={()=>void} />
<Rule strong?={boolean} broken?={boolean} />          // broken = 破版, an overspend
<Label>…</Label>                                       // 11px caps, ink-500
<Button variant="primary"|"quiet"|"danger" onClick fullWidth? disabled? holdMs?>…</Button>
   // holdMs turns it into a press-and-hold with a 1px ring filling linearly
<Segmented options={{value,label}[]} value onChange />  // the 2px rule slides, 180ms
<Sheet onClose title?>…</Sheet>                        // scrim + the one shadow
<Field label value onChange placeholder? type? suffix? mono? />
<EmptyState title body? action? />
<ProgressRule fraction tone? />                        // 1px rule, partly inked
<Ring fraction size? tone? />                          // 1px depleting arc

// charts.tsx — hand-authored SVG only. Geometry constants come from
// docs/DESIGN.md §7. Every chart prints its number as text somewhere.
<MonthStrip data={monthStrip(...)} onScrub?={(day|null)=>void} />
<DeviationBars rows={deviationByCategory(...)} nameOf={(id)=>string} />
<RegretBlocks judged={number} notWorth={number} />
<AnnualBar rows={{label, annual}[]} />
<HourScatter data={hourScatter(...)} />
<YearLedger months={{month, spent, standard}[]} />
```
