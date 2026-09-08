# 据实 · Countbook Design System

**Version** 1.0 · **Status** Normative · **Applies to** `web/` (Vite + React 19 + hand-written CSS) and `ios/` (SwiftUI, iOS 17+, zero third-party packages)

This document is the single normative source for the visual and interaction system of 据实 (Countbook / 花得值). It is written so that a web engineer authoring CSS custom properties and an iOS engineer authoring a SwiftUI theme file, working independently and without seeing each other's screens, produce results that are **visually identical when placed side by side at the same physical size**.

Where the two platforms cannot be made identical, this document says so explicitly, states the calibrated compensation, and states the residual difference. Nothing is left to taste at implementation time.

---

## 0. How this document is used

### 0.1 The token pipeline is mandatory

No hex value, spacing value, radius, duration, easing curve, or chart geometry constant may be typed into a `.css`, `.ts`, or `.swift` file by hand. Every one of them exists exactly once, in JSON, and is generated into both platforms.

```
tokens/
  color.json        # palette, light + dark + high-contrast
  type.json         # scale, stacks, features
  space.json        # spacing, radii, hairlines, elevation
  motion.json       # durations, curves, named transitions
  geometry.json     # chart + component geometry constants
  fixtures/         # cross-platform test vectors (§7.9)
scripts/
  gen-tokens.mjs    # tokens/*.json -> both targets
```

Generated outputs (both are **build artefacts, committed, never hand-edited** — CI fails if `gen-tokens` produces a diff):

| Target | Path | Shape |
| --- | --- | --- |
| Web | `web/src/styles/tokens.css` | `:root { --token: value }`, plus `@media (prefers-color-scheme: dark)`, `[data-theme]` overrides, `@media (prefers-contrast: more)` |
| Web | `web/src/styles/tokens.ts` | `export const token = { ... } as const` for values JS must read (chart geometry, durations) |
| iOS | `ios/Countbook/Design/Tokens.swift` | `enum Palette`, `enum Metric`, `enum Motion`, `enum Geometry` |

The generator emits a header banner `// GENERATED FROM tokens/*.json — DO NOT EDIT` into every output.

### 0.2 Reading the metrics

- Web values are **CSS px** (device-independent pixels). iOS values are **points (pt)**. At the design's reference density these are the same unit and the same physical size; a value written `16` means `16px` on web and `16pt` on iOS unless the table gives two columns.
- Where the two platforms need **different numbers to look the same** (corner radii, shadow blur), the table has a **Web** column and an **iOS** column and they differ deliberately. Never "harmonise" them.
- All colour is written as 6-digit sRGB hex, uppercase, no alpha. Alpha appears only in the two scrim/shadow definitions and is given as a decimal.
- Money is always integer 分 (`Int64` / `number` constrained to safe integers). No float ever reaches the render layer. Formatting happens once, in the Money primitive (§3.6).

### 0.3 Conformance language

**MUST** / **MUST NOT** are enforceable in code review and, where marked, by a lint rule or a fixture test. **SHOULD** indicates a default that may be overridden only with a comment naming the screen and the reason.

---

## 1. Design principles

1. **The app reports; it never editorialises.** Every string is a clerk's string — a figure, a date, a count, a derivation. No praise, no warning, no exclamation mark, no "great job", no "careful!"; if a number is bad, the number is allowed to be bad and is not accompanied by commentary.
2. **Colour is a scarce resource with exactly three meanings, and one of them is withheld.** Red oxide means *live and actionable*, brass means *held*, pine means *money not spent* — and 后悔 is deliberately given no colour at all, because a figure that never earns ink is more damning than one that shouts.
3. **Depth is value and rule weight, never blur.** One shadow exists in the entire system and it belongs to the capture sheet; everything else is separated by a one-device-pixel hairline and a change of surface value, because that is the only depth model that survives translation between CSS and SwiftUI unchanged.
4. **Friction is placed before money moves, never after.** The want list's cooling period and the three-second hold on a commit that is already over standard are the only delays the product is permitted to introduce; the logging path itself must stay under six seconds or every downstream mechanic starves.
5. **A figure is typography before it is data.** Tabular lining figures, a fixed 96 amount gutter, U+2212 for negatives, and the three-part ¥/元/分 composition are not decoration — they are what makes a column of money readable as a column, and they are non-negotiable on both platforms.
6. **The record defends itself against its owner.** Closed months append 更正 and 冲销 rather than mutating; standard revisions are dated and permanent; a zero-spend day counts only when explicitly claimed — the interface exists to make retroactive self-flattery visible, not impossible.
7. **Restraint is the argument, so any ornament is a bug.** No gradient, no glass, no glow, no emoji, no illustration, no rounded bar cap, no icon where a word will do, no spinner, no confetti, no congratulation — if an element cannot justify itself as information, it is deleted rather than toned down.

---

## 2. Colour

### 2.1 Rules that govern the whole palette

- **R1 — Three chromatic roles, no fourth.** `fig-over`, `fig-held`, `fig-spared`. A fourth hue MUST NOT be introduced for any reason, including error, success, brand, or category identity.
- **R2 — At most one chromatic figure per screen.** If a screen would show two, the lower-priority one renders in `ink-900`. Priority: `fig-over` > `fig-held` > `fig-spared`.
- **R3 — Regret is colourless.** 后悔金额 renders in `fig-regret`, a cool lead grey that appears nowhere else in the product. It is not a chromatic role; it is the absence of one.
- **R4 — Sign is never carried by colour.** A negative figure is negative because it begins with U+2212, not because it is red. `fig-over` marks *over standard / negative allowance*, which is a semantic state, not an arithmetic sign. Income and refunds render in `ink-900` with a leading U+002B.
- **R5 — Selection, focus and active states are carried by rule weight, rule colour, and font weight — never by fill.** No component in this system has a filled selected state except the primary commit bar, which is `ink-900` at rest.
- **R6 — Category has no colour.** Categories are text labels. There is no category palette, no chart legend colour, and no coloured dot anywhere in the product.
- **R7 — Charts use `ink-700` for the neutral mark and `fig-over` for the over-standard mark. Nothing else.** The single exception is the cooling arc (`fig-held`) and the spared total (`fig-spared`).

### 2.2 Grounds and surfaces (3 elevations)

| Token | Light | Dark | Usage rule |
| --- | --- | --- | --- |
| `--paper` | `#F7F6F3` | `#121211` | Elevation 0. The page ground. The scroll background of every screen. Warm paper in light; graphite, never black, in dark. |
| `--surface` | `#FFFFFF` | `#1A1A18` | Elevation 1. Cards, the capture sheet, modals, the tab bar, sticky headers. Anything that sits *on* the page. |
| `--surface-sunken` | `#F1EFEA` | `#0E0E0D` | Elevation −1. Input wells, the keypad ground, the closed-month 结 block, the disabled commit bar, chart plot areas that need to recede. Never used for text-bearing cards. |

Elevation is expressed **only** by these three values plus hairlines. There is no elevation 2. If a surface needs to sit above `--surface`, it is a sheet and it gets the one shadow (§4.5).

### 2.3 Hairlines and rules

| Token | Light | Dark | Contrast vs `--surface` | Usage rule |
| --- | --- | --- | --- | --- |
| `--rule` | `#E2DFD8` | `#2B2A27` | 1.33 : 1 / 1.21 : 1 | Default hairline. Row separators, card borders at rest, chart baselines, field underlines. Decorative separation only — it MUST NOT be the sole carrier of any state or boundary that the user must perceive to operate the app. |
| `--rule-strong` | `#C9C5BB` | `#3D3B36` | 1.72 : 1 / 1.56 : 1 | Structural rules: section dividers, the rule under a screen header, the day-section rule in the ledger, the standard line in the month strip. Still decorative. |
| `--rule-active` | `#6E6C64` | `#8C897F` | 5.26 : 1 / 4.98 : 1 | **State-bearing** rules only: focused card border, selected category box, the field a cursor is in. Meets 1.4.11 non-text contrast (≥3:1) so state is perceivable. |
| `--rule-stamp` | `#111110` | `#F2F0EA` | 18.89 : 1 / 15.29 : 1 | The 2px sliding selection rule under the chosen 记账印章 segment, the active tab rule, and the 存入账页 hold ring. Always `ink-900`. |

`--rule` and `--rule-strong` sit far below 3:1 and this is **intentional and permitted**, because they never carry information alone: every row they separate also has vertical spacing and a distinct baseline grid, and every card they bound also has a surface-value change. The moment a rule carries state, it becomes `--rule-active`. This distinction is the fix for the known dark-mode contrast risk; it MUST be respected.

### 2.4 Ink (text at 3 emphases + 1 sub-emphasis)

| Token | Light | Dark | Light ratios (paper / surface / sunken) | Dark ratios (paper / surface / sunken) | Usage rule |
| --- | --- | --- | --- | --- | --- |
| `--ink-900` | `#111110` | `#F2F0EA` | 17.48 / 18.89 / 16.44 | 16.45 / 15.29 / 16.95 | Hero and screen figures, the 元 integer part of every amount, primary row text, the commit bar's ground, the active tab label. **AAA everywhere.** |
| `--ink-700` | `#35342F` | `#C9C6BE` | 11.54 / 12.47 / 10.85 | 10.98 / 10.21 / 11.32 | Body copy, category names, chart neutral marks, note text that is not truncated. **AAA everywhere.** |
| `--ink-500` | `#6E6C64` | `#8C897F` | 4.87 / 5.26 / 4.58 | 5.36 / 4.98 / 5.52 | Labels, secondary metadata, 更正/冲销 rows, the 分 part at row scale and below, inactive tab labels. **AA (≥4.5:1) everywhere at any size.** |
| `--ink-300` | `#8A877F` | `#6E6B63` | 3.32 / 3.59 / 3.12 | 3.52 / 3.28 / 3.63 | Units, timestamps, placeholder text, the 分 part **at ≥19px rendered size only**, ¥ marks, weekend ticks. **Passes AA for large text (≥3:1) but NOT for small text.** Governed by R8 below. |

> **R8 — the `--ink-300` size rule (enforced by lint).** `--ink-300` may only be applied to text whose **rendered** size is ≥ 19px (large-text threshold: 18.66px), **or** to text whose full meaning is duplicated in the accessible name of an ancestor element (the 分 fragment inside `<Money>`, the ¥ mark, the weekend tick's date). Everywhere else — small timestamps, placeholders, micro labels — use `--ink-500`.
>
> **Consequence for the money composition:** at `fig-hero` (64) the 分 renders at 35.8px → `--ink-300`. At `fig-screen` (44) → 24.6px → `--ink-300`. At `fig-section` (34) → 19.0px → `--ink-300`. At `fig-row` (17) → 9.5px → **`--ink-500`**. The `<Money>` primitive selects the tone from its size token automatically (§3.6.4); implementers MUST NOT set it manually.

The original 1.0 draft value for light `--ink-300` was `#A5A29A` (2.36 : 1). It has been darkened to `#8A877F` to clear 3:1 on every ground. Dark `--ink-300` was `#605D56` (2.65 : 1 on surface) and is now `#6E6B63`.

### 2.5 The three chromatic roles

| Token | Light | Dark | Light ratios (paper / surface) | Dark ratios (paper / surface) | Usage rule — exhaustive |
| --- | --- | --- | --- | --- | --- |
| `--fig-over` | `#A32A22` | `#E0655A` | 6.67 / 7.21 | 5.51 / 5.13 | Red oxide. **Exactly three uses.** (1) The 今日可用 hero when it is negative. (2) A category bar extending right of the zero rule in 偏差条, and a month-strip day bar above the standard line. (3) The 不值 squares in the 后悔率 block and the hairline a 不值 verdict leaves behind. **It MUST NOT be used for 后悔金额, for errors, for delete, or for any alert.** |
| `--fig-held` | `#8A6A1F` | `#D2A64A` | 4.67 / 5.05 | 8.30 / 7.71 | Dark brass. **Exactly three uses.** (1) The depleting 冷静期弧 and its mono countdown. (2) The 挂起 N 天 primary action label when the capture sheet substitutes it. (3) The single-word sync state 待同步. Never on `--surface-sunken` (4.39 : 1); if a held figure must sit in a well, the well becomes `--surface`. |
| `--fig-spared` | `#2E5D4B` | `#6FA98A` | 6.98 / 7.54 | 6.89 / 6.41 | Deep pine. **Exactly two uses.** (1) 本年已放弃 on the want list and each row's abstained price in the archive. (2) The running 已省 figure under a cancelled subscription. It is the only green in the product and it never appears on 今日 or 报告. |
| `--fig-regret` | `#5B5F64` | `#939AA1` | 5.95 / 6.43 | 6.59 / 6.12 | Lead grey — cool, unlike every other grey in the system, which is warm. **Exactly one use:** 本月后悔 and 本年后悔 in the 报告 header, and the wish-object conversion line beneath them. It appears on no other screen and in no other component. Its coolness against the warm ink greys is the entire point; do not "match" it to `--ink-500`. |

### 2.6 Money sign, need/want/impulse triad, and semantic aliases

Colour does not encode sign or intent. Both are encoded typographically. These tokens exist so the intent is named in one place and so a future maintainer cannot "just add a colour".

| Token | Light | Dark | Usage rule |
| --- | --- | --- | --- |
| `--money-debit` | `#111110` (= ink-900) | `#F2F0EA` | Every outgoing amount. No prefix glyph. |
| `--money-credit` | `#111110` (= ink-900) | `#F2F0EA` | Income, refunds, and 冲销 reversals. Rendered with a leading U+002B and a hair space; **no colour change**. |
| `--money-negative` | `#A32A22` (= fig-over) | `#E0655A` | Reserved alias for a negative *allowance*, i.e. 今日可用 < 0. Not for negative amounts generally. |
| `--stamp-need` (必要) | `#6E6C64` (= ink-500) | `#8C897F` | The 必 glyph in a ledger row, and the 必要 segment label when unselected. Lightest of the three — necessity is the quiet case. |
| `--stamp-want` (想要) | `#35342F` (= ink-700) | `#C9C6BE` | The 想 glyph and the 想要 label. |
| `--stamp-impulse` (冲动) | `#111110` (= ink-900) | `#F2F0EA` | The 冲 glyph and the 冲动 label. Heaviest ink of the three — impulse is the case the page is darkest about, without ever turning red. |
| `--stamp-rule` | `#111110` | `#F2F0EA` | The 2px selection rule (alias of `--rule-stamp`). |

The triad is therefore a **value ramp, not a hue ramp**: 必要 → 想要 → 冲动 reads as progressively darker ink in a ledger column, which is legible at a glance down a page and costs no chroma. The 冲动 glyph additionally sets at weight 600 where 必/想 set at 500.

### 2.7 Scrim, and the absence of overlays

| Token | Light | Dark | Definition |
| --- | --- | --- | --- |
| `--scrim` | `rgba(17, 17, 16, 0.28)` | `rgba(0, 0, 0, 0.48)` | Behind the capture sheet and modals. **No blur.** `backdrop-filter` MUST NOT appear in the codebase; `.ultraThinMaterial` and every other `Material` MUST NOT appear in the SwiftUI codebase. This is the constraint that keeps both renderers identical. |

Dark mode raises scrim opacity because a 0.28 scrim over `#121211` is imperceptible.

### 2.8 High-contrast set

Emitted under `@media (prefers-contrast: more)` on web and selected by `UITraitCollection.accessibilityContrast == .high` on iOS. Only these tokens change; everything else is inherited.

| Token | Light HC | Dark HC | Light ratio (surface) | Dark ratio (surface) |
| --- | --- | --- | --- | --- |
| `--ink-300` | `#6B675F` | `#949186` | 5.63 | 5.52 |
| `--rule` | `#8F8B81` | `#706E67` | 3.40 | 3.42 |
| `--rule-strong` | `#6E6A60` | `#8C897F` | 5.39 | 4.98 |
| `--fig-over` | `#8E1F18` | `#EC9089` | 8.90 | 7.40 |
| `--fig-held` | `#6F5412` | `#E2BC6A` | 7.11 | 9.66 |
| `--fig-spared` | `#22493A` | `#8FC4A8` | 10.09 | 8.82 |
| `--fig-regret` | `#4A4E53` | `#AAB0B7` | 8.38 | 7.97 |
| `--hairline-w` | `1px` (the 0.5px override is disabled) | `1px` | — | — |

In HC mode the 分 tone rule (R8) is suspended: the 分 renders in `--ink-500` at every size, because HC users have told the OS that hierarchy matters less than legibility.

### 2.9 Contrast conformance summary

| Pairing | Light | Dark | Verdict |
| --- | --- | --- | --- |
| `ink-900` on all three grounds | 16.44 – 18.89 | 15.29 – 16.95 | AAA |
| `ink-700` on all three grounds | 10.85 – 12.47 | 10.21 – 11.32 | AAA |
| `ink-500` on all three grounds | 4.58 – 5.26 | 4.98 – 5.52 | AA at any size |
| `ink-300` on all three grounds | 3.12 – 3.59 | 3.28 – 3.63 | AA **large text only** — gated by R8 |
| `fig-over` on paper / surface | 6.67 / 7.21 | 5.51 / 5.13 | AA at any size |
| `fig-held` on paper / surface | 4.67 / 5.05 | 8.30 / 7.71 | AA at any size (sunken 4.39 — forbidden, see §2.5) |
| `fig-spared` on paper / surface | 6.98 / 7.54 | 6.89 / 6.41 | AA at any size |
| `fig-regret` on paper / surface | 5.95 / 6.43 | 6.59 / 6.12 | AA at any size |
| `rule-active` on surface | 5.26 | 4.98 | Passes 1.4.11 (≥3:1) |
| `paper` text on `ink-900` commit bar | 17.48 | 16.45 | AAA |

Known and accepted: `--rule` and `--rule-strong` do not meet 3:1 and MUST NOT carry state (§2.3). HC mode brings both to ≥3.4:1.

### 2.10 Generated form

```css
/* web/src/styles/tokens.css — GENERATED */
:root {
  --paper:#F7F6F3; --surface:#FFFFFF; --surface-sunken:#F1EFEA;
  --ink-900:#111110; --ink-700:#35342F; --ink-500:#6E6C64; --ink-300:#8A877F;
  --rule:#E2DFD8; --rule-strong:#C9C5BB; --rule-active:#6E6C64; --rule-stamp:#111110;
  --fig-over:#A32A22; --fig-held:#8A6A1F; --fig-spared:#2E5D4B; --fig-regret:#5B5F64;
  --scrim:rgba(17,17,16,.28);
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { /* dark values */ } }
:root[data-theme="dark"] { /* dark values */ }
@media (prefers-contrast: more) { :root { /* HC values */ } }
```

```swift
// ios/Countbook/Design/Tokens.swift — GENERATED
enum Palette {
    static let paper        = Color(light: 0xF7F6F3, dark: 0x121211, lightHC: 0xF7F6F3, darkHC: 0x121211)
    static let surface      = Color(light: 0xFFFFFF, dark: 0x1A1A18, lightHC: 0xFFFFFF, darkHC: 0x1A1A18)
    static let surfaceSunken = Color(light: 0xF1EFEA, dark: 0x0E0E0D, lightHC: 0xF1EFEA, darkHC: 0x0E0E0D)
    static let ink900 = Color(light: 0x111110, dark: 0xF2F0EA, lightHC: 0x111110, darkHC: 0xF2F0EA)
    static let ink700 = Color(light: 0x35342F, dark: 0xC9C6BE, lightHC: 0x35342F, darkHC: 0xC9C6BE)
    static let ink500 = Color(light: 0x6E6C64, dark: 0x8C897F, lightHC: 0x6E6C64, darkHC: 0x8C897F)
    static let ink300 = Color(light: 0x8A877F, dark: 0x6E6B63, lightHC: 0x6B675F, darkHC: 0x949186)
    static let rule       = Color(light: 0xE2DFD8, dark: 0x2B2A27, lightHC: 0x8F8B81, darkHC: 0x706E67)
    static let ruleStrong = Color(light: 0xC9C5BB, dark: 0x3D3B36, lightHC: 0x6E6A60, darkHC: 0x8C897F)
    static let ruleActive = Color(light: 0x6E6C64, dark: 0x8C897F, lightHC: 0x6E6C64, darkHC: 0x8C897F)
    static let figOver   = Color(light: 0xA32A22, dark: 0xE0655A, lightHC: 0x8E1F18, darkHC: 0xEC9089)
    static let figHeld   = Color(light: 0x8A6A1F, dark: 0xD2A64A, lightHC: 0x6F5412, darkHC: 0xE2BC6A)
    static let figSpared = Color(light: 0x2E5D4B, dark: 0x6FA98A, lightHC: 0x22493A, darkHC: 0x8FC4A8)
    static let figRegret = Color(light: 0x5B5F64, dark: 0x939AA1, lightHC: 0x4A4E53, darkHC: 0xAAB0B7)
}

extension Color {
    init(light: UInt32, dark: UInt32, lightHC: UInt32, darkHC: UInt32) {
        self.init(UIColor { t in
            let hc = t.accessibilityContrast == .high
            let isDark = t.userInterfaceStyle == .dark
            let v = isDark ? (hc ? darkHC : dark) : (hc ? lightHC : light)
            return UIColor(red: CGFloat((v >> 16) & 0xFF)/255,
                           green: CGFloat((v >> 8) & 0xFF)/255,
                           blue: CGFloat(v & 0xFF)/255, alpha: 1)
        })
    }
}
```

sRGB is assumed on both platforms. `UIColor(red:green:blue:)` is device-RGB, which on all iOS displays in the sRGB colour space resolves to sRGB; do **not** use `Color(.displayP3, ...)`.

---

## 3. Typography

### 3.1 Font stacks — zero webfonts, zero CDN requests

**Web.** Three stacks. They are declared once as custom properties and never re-declared.

```css
:root {
  --font-sans:
    -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display",
    "Helvetica Neue", system-ui, "Segoe UI Variable Text", "Segoe UI", Roboto,
    "PingFang SC", "Hiragino Sans GB", "HarmonyOS Sans SC", "Source Han Sans SC",
    "Noto Sans SC", "Microsoft YaHei", "微软雅黑", "Heiti SC", sans-serif;

  --font-mono:
    ui-monospace, "SF Mono", SFMono-Regular, Menlo, Monaco,
    "Cascadia Mono", Consolas, "Liberation Mono",
    "Noto Sans Mono CJK SC", monospace;

  /* Figures only. Identical to --font-sans minus the CJK faces, so that a
     digit is never resolved from a CJK font with non-tabular numerals. */
  --font-fig:
    -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue",
    system-ui, "Segoe UI Variable Display", "Segoe UI", Roboto,
    "Helvetica", "Arial", sans-serif;
}
```

**Why `--font-fig` exists.** Microsoft YaHei and several Noto CJK builds ship proportional, non-lining digits with a heavy colour that destroys a money column. Latin digits MUST never fall through to a CJK face. Every element that renders a figure (`.fig`, `.fig-hero`, `.fig-row`, chart labels, countdowns) sets `font-family: var(--font-fig)` explicitly. This is the primary mitigation for the known "typography degrades off Apple platforms" risk.

**Web metric overrides.** Two `@supports`/UA-independent adjustments, generated from `type.json`:

```css
/* Non-Apple platforms render the Light (300) face heavier and taller. */
@supports not (font: -apple-system-body) {
  :root { --fig-weight-light: 250; --fig-track-hero: -0.025em; --lh-tighten: -0.02; }
}
```
If a Light face is unavailable the browser falls back to Regular. **Synthetic (faux) weights MUST be disabled**: `font-synthesis: none` is set on `:root`. A missing Light face degrades to Regular, which is acceptable; a smeared synthetic Light is not.

**iOS.** SwiftUI resolves the same faces natively.

```swift
enum Face {
    /// Body & labels: SF Pro Text below 20pt, SF Pro Display at and above.
    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    /// Figures: identical family; the distinction on web is a fallback guard
    /// that iOS does not need, because SF always wins for Latin digits.
    static func fig(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
```
CJK glyphs resolve to PingFang SC automatically for a zh-Hans locale; no font declaration is needed or permitted.

### 3.2 Numeral rules (normative)

Every figure in the product — money, counts, percentages, countdowns, dates, times, chart labels — MUST render with tabular lining figures.

**Web** (applied by the `.fig`, `.mono` and `.tnum` classes; also set globally on `:root` so a missed class still degrades correctly):
```css
.fig, .mono, .tnum, table, time {
  font-variant-numeric: tabular-nums lining-nums;
  font-feature-settings: "tnum" 1, "lnum" 1, "kern" 1;
  font-variant-ligatures: none;
}
```

**iOS**: `.monospacedDigit()` on every `Text` that contains a figure. `Font.system(...).monospacedDigit()` is baked into `Face.fig` and `Face.mono` so it cannot be forgotten.

Additional numeral rules:

- **Negative sign.** U+2212 MINUS SIGN (`−`). Hyphen-minus and parentheses MUST NOT be used. The Money primitive is the only place that emits it.
- **Positive sign.** U+002B, used only for credits, followed by U+200A HAIR SPACE.
- **Currency mark.** U+00A5 (`¥`), half-width. The full-width `￥` U+FFE5 MUST NOT be used — it inherits CJK metrics and breaks the gutter.
- **Grouping.** U+002C every three integer digits. No grouping below 10,000 分 boundaries is special-cased; grouping applies to the 元 integer string only.
- **Percentages.** One decimal place, `22.5%`, U+0025 at 0.72× in `--ink-500`.
- **Dates.** `MM-DD` in mono, `2026-03-14` where the year is needed, `03-14 · 周五` in section rules. ISO order always; never `14/03`.
- **Times.** 24-hour `20:41` in mono, `--ink-300` at ≥19px or `--ink-500` below.

### 3.3 Type scale

Base for the web rem scale is `16px` (`html { font-size: 100% }` — never overridden, so user browser font size is respected). Each token is emitted in **both** px (for reference) and rem (for use). Line-heights are unitless.

| Token | px | rem | Weight | Line-height | Tracking | Family | Use |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `--t-fig-hero` | 64 | 4.000 | 300 | 1.00 | −0.02em | fig | 今日可用. One per screen, one screen only (今日). |
| `--t-fig-screen` | 44 | 2.750 | 300 | 1.05 | −0.02em | fig | Capture-sheet amount display; the amount on a 周日审判 card. |
| `--t-fig-section` | 34 | 2.125 | 400 | 1.10 | −0.015em | fig | 订阅 年化 header; 本月/本年后悔; 本年已放弃; month total in 账页. |
| `--t-fig-row` | 17 | 1.0625 | 500 | 1.20 | 0 | fig | Every amount in every list row, in the 96 gutter. |
| `--t-fig-inline` | 13 | 0.8125 | 500 | 1.30 | 0 | fig | Amounts inside prose lines (subscription rows, the wish-object line). |
| `--t-body` | 15 | 0.9375 | 400 | 1.53 | 0 | sans | Paragraphs, notes, empty-state copy, category names in the capture grid. |
| `--t-body-sm` | 13 | 0.8125 | 400 | 1.45 | 0 | sans | Secondary row text, note text in ledger rows, card sub-lines. |
| `--t-label` | 11 | 0.6875 | 600 | 1.20 | 0.14em (Latin) / 0.08em (CJK) | sans | Section labels, the provenance line, tab labels, table column heads. Latin is uppercased; **CJK is never case-transformed.** |
| `--t-micro` | 10 | 0.6250 | 500 | 1.30 | 0.06em | sans | Chart tick labels, the 已付…（自 2022-01) parenthetical, footnotes. Always `--ink-500` (R8). |
| `--t-mono-row` | 12 | 0.7500 | 450 | 1.20 | 0 | mono | Ledger row timestamps, countdowns, sync times, key fingerprint, 更正 rows. |
| `--t-mono-micro` | 10 | 0.6250 | 500 | 1.20 | 0.02em | mono | Verdict progress `3 / 11`, storage figures, IDs. |
| `--t-stamp` | 12 | 0.7500 | 500 / 600 | 1.00 | 0.02em | sans | The single-character 必 / 想 / 冲 glyph. 600 for 冲 only (§2.6). |

**Tracking on CJK.** Letter-spacing on Chinese text creates uneven optical gaps and MUST NOT exceed 0.08em. The `--t-label` token therefore carries two tracking values; the generator emits `.label:lang(zh) { letter-spacing:.08em; text-transform:none }` and `.label:lang(en) { letter-spacing:.14em; text-transform:uppercase }`. On iOS this is `.tracking(locale.isCJK ? 0.08 * size : 0.14 * size)` plus `.textCase(locale.isCJK ? nil : .uppercase)`.

**Weight availability.** 300 exists in SF Pro, Segoe UI Light, Roboto Light and PingFang SC Light. 450 does not exist as a static face; on web it resolves to 400 unless a variable face is present, and on iOS `Font.Weight(rawValue:)` is not public — `--t-mono-row` therefore maps to `.regular` on iOS and `font-weight: 450` on web, which is a deliberate, imperceptible 0-to-half-step difference on a 12px mono timestamp. This is the only intentional weight divergence in the system.

### 3.4 Dynamic Type and the responsive scale

Hard pixel values are inaccessible. The **ratios** above are fixed; the **base** scales.

**iOS.** Every token maps to a `UIFont.TextStyle` for metric scaling, with a cap so the hero cannot destroy the layout.

| Token | TextStyle | `maximumPointSize` |
| --- | --- | --- |
| `--t-fig-hero` | `.largeTitle` | 86 (1.34×) |
| `--t-fig-screen` | `.title1` | 62 (1.41×) |
| `--t-fig-section` | `.title2` | 50 |
| `--t-fig-row` | `.body` | 28 |
| `--t-fig-inline` | `.subheadline` | 22 |
| `--t-body` | `.body` | 26 |
| `--t-body-sm` | `.footnote` | 22 |
| `--t-label` | `.caption2` | 18 |
| `--t-micro` | `.caption2` | 16 |
| `--t-mono-row` | `.caption1` | 20 |
| `--t-mono-micro` | `.caption2` | 16 |
| `--t-stamp` | `.caption1` | 20 |

```swift
struct ScaledFont: ViewModifier {
    let size: CGFloat, weight: Font.Weight, style: Font.TextStyle, cap: CGFloat, mono: Bool
    @Environment(\.sizeCategory) private var cat
    func body(content: Content) -> some View {
        content.font(.system(size: min(UIFontMetrics(forTextStyle: style.uiKit)
                        .scaledValue(for: size), cap),
                      weight: weight, design: mono ? .monospaced : .default)
                .monospacedDigit())
    }
}
```

At `.accessibilityExtraExtraExtraLarge` the ledger row switches from single-line to a two-line stacked layout (§5.4) rather than truncating the amount. The amount gutter is never truncated, never shrunk, never ellipsised.

**Web.** All sizes in rem so the browser's base size is honoured. The hero additionally clamps against viewport width so a 360px phone does not overflow:

```css
.fig-hero { font-size: clamp(2.75rem, 2.1rem + 3.2vw, 4rem); }
```
At the 720 content column this resolves to exactly 4rem. Below 380px it floors at 2.75rem, which equals `--t-fig-screen` — the hero never becomes smaller than a screen figure.

### 3.5 Vertical rhythm

The baseline grid is **4**. Every line box's computed height rounds to a multiple of 4 at the default size. Section spacing is 32; the rule that opens a section sits 32 below the previous section's last baseline and 12 above the section label.

### 3.6 The Money primitive — the only place a money figure is composed

This is the single most-specified component in the system, because (a) it is the signature typographic move and (b) per-part markup is the system's largest accessibility hazard. It exists **exactly once per platform** and no other code may compose an amount.

- Web: `web/src/design/Money.tsx` → `<Money fen={123840} size="hero" />`
- iOS: `ios/Countbook/Design/MoneyText.swift` → `MoneyText(fen: 123_840, size: .hero)`

Both consume the same formatter, `formatFen(fen, opts) -> MoneyParts`, which lives in `packages/money` (TS) and `Money.swift` (Swift) and is covered by a shared fixture file (§7.9).

#### 3.6.1 Composition

A money figure is **three baseline-aligned parts**, never a single string:

| Part | Content | Size | Colour | Spacing |
| --- | --- | --- | --- | --- |
| Mark | `¥` (U+00A5), preceded by `−` U+2212 or `+` U+002B when signed | **0.44×** the figure size | `--ink-300` (mark) / figure colour (sign) | 0.08em trailing space |
| Integer | 元, grouped with `,` | **1.00×** | figure colour (`--ink-900`, or `--fig-over` / `--fig-held` / `--fig-spared` / `--fig-regret` per role) | — |
| Fraction | `.` + two 分 digits | **0.56×** | `--ink-300` at ≥19px rendered, else `--ink-500` (R8) | fixed advance, see below |

The fraction is **baseline-aligned, not superscripted**. `vertical-align` and `baselineOffset` MUST both be zero.

#### 3.6.2 The fixed fraction advance

The fraction occupies a fixed `2.6ch` box, left-aligned, so that integer digits align down a ledger column regardless of whether an amount ends in `.00` or `.40`.

```css
.fig { font-family: var(--font-fig); font-variant-numeric: tabular-nums lining-nums;
       font-feature-settings:"tnum" 1,"lnum" 1; white-space: nowrap; }
.fig > i { font-style: normal; font-size: .44em; color: var(--ink-300); letter-spacing: .08em; }
.fig > b { font-weight: inherit; font-size: .56em; color: var(--fig-fraction, var(--ink-300));
           display: inline-block; width: 2.6ch; text-align: left; }
```
`ch` resolves against the *fraction's own* font-size, which is what makes 2.6ch equal to two tabular digits plus a period plus a hair of trailing air.

SwiftUI equivalent:
```swift
HStack(alignment: .firstTextBaseline, spacing: 0) {
    Text(parts.mark).font(Face.fig(size * 0.44, weight)).foregroundStyle(Palette.ink300)
        .padding(.trailing, size * 0.44 * 0.08)
    Text(parts.integer).font(Face.fig(size, weight)).foregroundStyle(roleColor)
    Text(parts.fraction).font(Face.fig(size * 0.56, weight)).foregroundStyle(fractionColor)
        .frame(width: size * 0.56 * 2.6 * Metric.digitAdvanceRatio, alignment: .leading)
}
```
`Metric.digitAdvanceRatio = 0.6` — SF Pro's tabular digit advance is 0.60 em. This constant is generated from `type.json` and is the only place the em-to-ch conversion is expressed.

**Verification.** A snapshot fixture renders `¥1,238.40`, `¥1,238.00`, `¥8.05`, `−¥84.20`, `¥0.00`, `¥1,234,567.89` at each size on both platforms; the integer part's left edge in the right-aligned gutter must match to ≤0.5px between renders of different fractions.

#### 3.6.3 Accessibility of the composed figure

This is mandatory, not optional. Split markup makes an amount unreadable to a screen reader and unselectable to a mouse; both are closed here and nowhere else.

**Web:**
```tsx
<span className="fig" role="text" aria-label={parts.spoken}>
  <i aria-hidden="true">¥</i>{parts.integer}<b aria-hidden="true">.40</b>
</span>
```
- `parts.spoken` is the full localised string: `"负八十四元二角"` is **wrong**; the spoken form is `"−84.20 元"` rendered as `"负 84.20 元"` in zh-CN and `"minus 84 point 20 yuan"` in en. The formatter owns this.
- A `::selection`-safe copy path is provided by a `copy` event handler on `.fig` that writes `parts.plain` (`-84.20`) to the clipboard, because copying the split DOM yields `¥84.40`-style garbage. This handler lives in the Money component only.
- `user-select: all` is set on `.fig` so a single click/tap selects the whole figure rather than a fragment.

**iOS:**
```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(parts.spoken)
.accessibilityValue("")     // never speak the fragments
```
A `UIAccessibilityCustomAction` is **not** added; the row that contains the figure owns actions.

A unit test asserts that every `.fig` node in a rendered snapshot has a non-empty `aria-label`, and an XCTest asserts every `MoneyText` exposes exactly one accessibility element. CI fails otherwise.

#### 3.6.4 Role colouring API

`<Money>` accepts `role` ∈ `debit | credit | allowance | held | spared | regret | neutral`. The component maps role → integer colour and derives the fraction colour from the size token per R8. **Call sites never pass a colour.** This is what keeps the three-colours-three-meanings rule mechanically true.

#### 3.6.5 Compact form

In one place only — the month-strip header readout that follows the cursor — an amount may render without its fraction (`¥312`), because it changes 30 times per drag and a jittering fraction is noise. The Money component exposes `fraction="hide"` for this and the `aria-label` still contains the full amount.

---

## 4. Space, radii, hairlines, elevation

### 4.1 Spacing scale

Base unit **4**. Only these values may be used for margin, padding, or gap. Arbitrary values are a lint error.

| Token | Value | Typical use |
| --- | --- | --- |
| `--s-0` | 0 | Reset. |
| `--s-1` | 4 | Glyph-to-text gap; the gap between a stamp glyph and the amount gutter. |
| `--s-2` | 8 | Label-to-figure; chip inner horizontal padding. |
| `--s-3` | 12 | Field inner padding; gap between section label and its rule. |
| `--s-4` | 16 | Card inner padding (compact); gap between stacked rows in a card. |
| `--s-5` | 20 | **Screen gutter, phone.** Card inner padding (default). |
| `--s-6` | 24 | Gap between a header block and the first rule. |
| `--s-7` | 32 | **Section spacing.** Screen gutter, ≥600px. |
| `--s-8` | 40 | Space above a screen's first section; sheet top padding. |
| `--s-9` | 56 | Space above a footer block; empty-state top offset. |
| `--s-10` | 72 | Space reserved above the tab bar on scroll-to-end. |

Derived layout constants:

| Token | Web | iOS | Definition |
| --- | --- | --- | --- |
| `--gutter` | 20 (<600px) / 32 (≥600px) | 20 (compact) / 32 (regular) | Horizontal screen inset. |
| `--content-max` | 720 | 720 | Max content column width; centred on `--paper`. Above 720 the page does **not** switch to a multi-column layout — it stays one column with more paper. |
| `--gutter-amount` | 96 | 96 | The right-aligned amount column, present on **every** list in the app. Fixed; never flexes. |
| `--row-pad-y` | 14 | 14 | Ledger row vertical padding (row height = 14 + content + 14). |
| `--row-min-h` | 44 | 44 | Minimum row height (also the minimum hit target). |
| `--tabbar-h` | 49 | 49 | Excluding safe-area inset. |
| `--header-h` | 52 | 52 | Sticky screen header. |
| `--breakout` | 20 | 20 | The 破版 overhang (§4.6). |

### 4.2 Radii — different numbers, identical appearance

Web draws **circular** corners; iOS 17 `RoundedRectangle(cornerRadius:style:.continuous)` draws a **squircle**, which reads roughly 10 % lighter at the same numeric radius. The token file therefore carries two values per role, chosen so the rendered corners match. **These values MUST NOT be reconciled.**

| Role | Web (circular) | iOS (continuous) | Applies to |
| --- | --- | --- | --- |
| `--r-none` | 0 | 0 | Every rule, every ledger row, every chart mark, every bar, every hairline, the 结 seal block. **The default.** |
| `--r-field` | 7 | 8 | Text field wells, the note input, the search field's tappable area. |
| `--r-card` | 9 | 10 | Cards, the keypad key hit area, the toast. |
| `--r-sheet` | 14 | 16 | The capture sheet and every modal — **top corners only**; bottom corners are 0 and run under the safe area. |
| `--r-pill` | 999 | 999 | The three 记账印章 segment **hit areas only**, which are themselves unfilled and invisible. The 记 button (a true circle, d=56) also uses this. |

iOS MUST pass `style: .continuous` everywhere; `.circular` on iOS is a bug. Web MUST NOT attempt to emulate a squircle with SVG masks or `corner-shape` — the 1–2px difference is below the perceptual threshold at these radii and the emulation is not worth a repaint cost.

### 4.3 Hairlines

One device pixel, on both platforms, at every density.

**Web:**
```css
:root { --hairline-w: 1px; }
@media (min-resolution: 2dppx) { :root { --hairline-w: 0.5px; } }
@media (min-resolution: 3dppx) { :root { --hairline-w: 0.34px; } }
@media (prefers-contrast: more) { :root { --hairline-w: 1px; } }

.rule { border-bottom: var(--hairline-w) solid var(--rule); }
```
**Known failure and its guard.** Sub-pixel borders disappear at some Windows/Chromium zoom steps and on some Android WebViews. Guard: hairlines are drawn as a `background-image: linear-gradient(var(--rule), var(--rule))` with `background-size: 100% var(--hairline-w)` and `background-repeat: no-repeat` on the class `.rule--critical`, which composites more reliably than a fractional border. Use `.rule--critical` for the four rules that carry structure: the tab bar's top rule, the screen header's bottom rule, the ledger day-section rule, and the chart baseline. Everything else uses the border form. In HC mode all hairlines are a full 1px.

**iOS:**
```swift
struct Hairline: View {
    @Environment(\.displayScale) private var scale
    var color: Color = Palette.rule
    var body: some View { Rectangle().fill(color).frame(height: 1 / scale) }
}
```
`UIScreen.main.scale` MUST NOT be used (it is wrong on external displays and deprecated in a multi-scene app). Vertical hairlines use `.frame(width: 1 / scale)`.

**Rule weights.** Only three exist: `1/scale` (hairline), `1` (chart strokes, the cooling arc, the hold ring, the wish progress rule), `2` (the 印章 selection rule, the active tab rule, the error left-rule). No other stroke width may appear.

### 4.4 Chart stroke crispness

Web: every `<svg>` that draws bars or rules sets `shape-rendering="crispEdges"` on the bar/rule groups (never on text, never on the cooling arc, which needs `geometricPrecision`). All bar `x`/`width` values are rounded to whole device pixels by the geometry module before they reach the DOM.

iOS: bar `Path`s are constructed with `x` values passed through `round(_ * displayScale) / displayScale`, using the same rounding helper as the arc. The shared geometry module returns **normalised** coordinates; pixel-snapping happens at the render layer on each platform, using the identical rounding rule (`round-half-away-from-zero`).

### 4.5 Elevation — exactly one shadow

There is one shadow in the design system. It belongs to the capture sheet and to modals. Cards, rows, the tab bar, buttons, chips, toasts and charts have **no shadow**.

**Web:**
```css
--shadow-sheet:
  0 1px 2px rgba(17,17,16,.04),
  0 12px 32px -8px rgba(17,17,16,.16);
```

**iOS:**
```swift
.shadow(color: .black.opacity(0.04), radius: 1,  y: 1)
.shadow(color: .black.opacity(0.16), radius: 16, y: 12)
```

**Calibration note (read before "fixing" the numbers).** CSS blur radius ≈ 2 × Core Graphics shadow radius, hence `32 → 16` and `2 → 1`. CSS's negative spread (`-8`) has no SwiftUI analogue; it tightens the CSS shadow's footprint. Rather than emulate it, the iOS opacity stays at the same 0.16 and the radius is set to 16 (not 12), which measured within 2 % of the CSS render at the sheet's 16pt corner. Do not change one platform without re-measuring the other against `docs/fixtures/sheet-shadow.png`.

**Dark mode.** A black shadow on `#121211` is invisible. In dark, both platforms drop the shadow to `0 1px 2px rgba(0,0,0,.5)` / `.shadow(color:.black.opacity(0.5), radius:1, y:1)` **and add a top hairline** `--rule-strong` across the sheet's top edge. The sheet's separation in dark is carried by the rule and by the scrim, not by the shadow.

### 4.6 破版 — the margin break, the one composition event

The product has exactly one visual event, and it is not a colour.

**Rule.** When a figure is over its standard, the **rule or bar beneath it** — not the figure — extends `--breakout` (20) past both edges of the content column, clipped only by the safe area. Everything else on the page stays inside the column. The page appears to have been printed slightly wrong.

**Where it may occur (exhaustive):**
1. The hairline directly under the 今日可用 hero, when the allowance is negative.
2. The month strip's baseline rule, when the month-to-date total is above the pro-rated standard.
3. The 偏差条 zero rule, on the report, when the month total is above standard.

At most **one** breakout per screen; if two conditions are true, only (1) renders.

**Web:**
```css
.breakout {
  margin-inline: calc(-1 * var(--breakout));
  padding-inline: max(0px, env(safe-area-inset-left)) max(0px, env(safe-area-inset-right));
}
/* Above the content column the page has spare paper; the overhang is real.
   Below it, the viewport clips — which is the intended accident. */
.screen { overflow-x: clip; }
```
**iOS:**
```swift
.padding(.horizontal, -Metric.breakout)
.clipped()                       // container is inset by the safe area
```

The breakout is **not animated**. It is a layout state, present on first paint of the over condition. Animating it would turn an accident into an effect.

### 4.7 Hatch — the non-colour over-channel

For the segment of any track that extends past its standard, a 45° hatch is drawn *in addition to* `--fig-over`, so that the over state survives monochrome rendering, colour-blindness, and print.

- Geometry (shared constant `hatch`): angle 45°, period 4, stroke 1, colour = the mark's own colour at 100 % (never a tint).
- Web: an `<svg><defs><pattern id="hatch" width="4" height="4" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="4" stroke-width="1"/></pattern>` defined **once** in a hidden root SVG sprite and referenced by `fill="url(#hatch)"`.
- iOS: `Canvas` draws parallel `Path` lines at 45° with a 4pt period, clipped to the segment rect. A shared helper `hatchLines(in: CGRect, period: 4)` is generated from the same constant.

Hatch appears on: the over portion of a month-strip day bar, the over portion of a deviation bar, and the over portion of the year-ledger row. Nowhere else.

---

## 5. Components

Every component below is specified as: purpose, exact metrics, states, and the two implementations. Where a metric is not stated, it inherits from §4.

### 5.1 Navigation

#### 5.1.1 Tab bar (phone / narrow web, <720px)

- Height **49** + bottom safe-area inset. Ground `--surface`. A `.rule--critical` hairline across the top in `--rule-strong`.
- Five items, equal width: **今日 · 账页 · 待购 · 报告 · 设置**. **Text labels only — there are no tab icons.** This is a system rule, not an omission.
- Label: `--t-label`, `--ink-500`, weight 500 at rest; `--ink-900`, weight 600 when active.
- Active indicator: a **2 × label-width** rule in `--rule-stamp`, positioned at the **top** edge of the active cell, 0 offset from the tab bar's top hairline, horizontally centred on the label. It slides between cells with `stampSlide` (§6).
- Hit target: full cell, minimum 49 × 64.
- No badges, no dots, no counts. A pending 周日审判 is surfaced by the 报告 tab's label switching to `--ink-900` weight 600 while inactive — the same treatment as active, minus the rule. That is the only notification affordance in the product.

Web: `position: fixed; inset-inline: 0; bottom: 0; padding-bottom: env(safe-area-inset-bottom)`.
iOS: a custom `HStack` in a `safeAreaInset(edge: .bottom)`. `TabView`'s default chrome MUST be replaced, because it forces SF Symbols and a system material.

#### 5.1.2 Top rail (web ≥720px)

The same five words, `--t-label`, laid out left-aligned in a 52-high header on `--paper`, separated by `--s-6`, with the 2px `--rule-stamp` beneath the active word. A `.rule--critical` hairline runs across the full viewport width beneath the rail. The tab bar is not rendered at this width.

#### 5.1.3 Screen header

- Height **52**, ground `--paper` (it is part of the page, not a bar), sticky.
- Left: screen title in `--t-label`. Right: at most one text action (`导出`, `编辑`), `--t-body-sm`, `--ink-700`. **No icon buttons in the header** except back (§8).
- Bottom: `.rule--critical` hairline in `--rule-strong`, full content width.
- On scroll past 8px, no shadow, no blur, no material appears — the header simply keeps its hairline. This is the whole scroll treatment.

### 5.2 Card

- Ground `--surface`; border `--hairline-w` solid `--rule`; radius `--r-card` (9 web / 10 iOS); **no shadow, ever**.
- Padding `--s-5` (20). Compact variant `--s-4` (16), used only inside sheets.
- Vertical gap between stacked cards: `--s-4` (16).
- **Active / focused**: border colour swaps `--rule` → `--rule-active`. Nothing else changes — no lift, no scale, no fill.
- **Sunken variant** (`--surface-sunken`, no border) is used only for the keypad ground and the disabled commit bar.
- A card MUST NOT contain another card.

### 5.3 List section and day rule

- Section label: `--t-label`, `--ink-500`, `--s-3` (12) above its rule.
- Day rule in 账页: a full-width row, height 28, containing `03-14 · 周五` in `--t-mono-row` `--ink-500` on the left and the day total (`<Money size="row" role="neutral">`) right-aligned in the 96 gutter, with a `--rule-strong` hairline along its bottom edge.
- Month header: month name `--t-label`, total at `--t-fig-section`, standard beneath at `--t-micro`, and — for a sealed month — the 结 block: a 20 × 20 `--surface-sunken` square, `--r-none`, containing the character 结 at `--t-stamp` in `--ink-500`, letterpressed by a 1px inset `--rule-strong` top/left border only.

### 5.4 Ledger row (the transaction row)

The most-used component in the product. Single line at default type size.

```
┌ 20 ──┬─────────────────────────────────────────────┬──── 96 ────┬ 20 ┐
│      │ 08:41   餐饮   星巴克 拿铁             冲    │    ¥38.00  │    │
└──────┴─────────────────────────────────────────────┴────────────┴────┘
```

| Element | Metric | Type | Colour |
| --- | --- | --- | --- |
| Row box | min-height 44; padding 14 top/bottom, `--gutter` left, 0 right (the gutter absorbs it) | — | ground `--paper`; `--surface` inside a card |
| Time | fixed width 40, left | `--t-mono-row` | `--ink-500` (R8: 12px < 19px) |
| Gap | 12 | | |
| Category | intrinsic, max 5 CJK chars, no truncation | `--t-body` | `--ink-700` |
| Gap | 10 | | |
| Note | flex 1, single line, `text-overflow: ellipsis` | `--t-body-sm` | `--ink-500` |
| Stamp glyph | fixed width 16, centred | `--t-stamp` | `--stamp-need` / `--stamp-want` / `--stamp-impulse` |
| Gap | 8 | | |
| Amount | fixed 96, right-aligned, `<Money size="row">` | `--t-fig-row` | `--money-debit` (or `--fig-over` never — amounts are never red) |
| Separator | bottom `--hairline-w` `--rule`, inset 0 left, 0 right (full bleed inside the gutter) | | |

States:

- **Pressed** (iOS) / `:active` (web): ground → `--surface-sunken`, 100ms, no scale.
- **Focus-visible** (web keyboard): a 2px `--rule-stamp` outline, offset 2, radius 0.
- **Selected** (multi-select in export): a 2px `--rule-stamp` rule down the **left** edge, inset 0. No fill, no checkbox tick until the row is selected, at which point the ✓ icon appears in the stamp slot in `--ink-900`.
- **Correction child** (`更正`): rendered as a second line directly beneath its parent, indented to the category column, `--t-mono-row`, `--ink-500`: `更正 · 原 ¥288.00 → ¥88.00 · 事由：点错了`. `→` is U+2192. It has no separator of its own; parent and child share one hairline beneath the pair.
- **Reversal** (`冲销`): identical treatment, prefix 冲销, and the parent's amount gets a `text-decoration: line-through` at 1px `--ink-300` (iOS: `.strikethrough(true, color: Palette.ink300)`).
- **Held** (in cooling): the amount renders `role="held"`, and the cooling arc (§5.10) sits in the stamp slot instead of a glyph.
- **Large Dynamic Type** (≥ `.accessibility1` / web ≥ 1.6× base): the row becomes two lines — line 1 category + amount, line 2 time + note + stamp — and min-height becomes 64. The 96 gutter is retained.

Swipe / long-press actions: **iOS** `swipeActions` with text labels only (`更正`, `冲销`), `--surface-sunken` ground, `--ink-900` label — no coloured destructive red, no trash icon. **Web** has no swipe; a long-press (500ms) or right-click opens the same two-item menu.

### 5.5 Amount display (capture sheet)

- Right-aligned, `--t-fig-screen` (44), `<Money size="screen">`, sitting on `--surface` with `--s-5` gutters and 24 top padding, 20 bottom.
- Empty state shows `¥0.00` in `--ink-300` (44 × 0.44 = 19.4px mark, 44 integer — integer in `--ink-300` too, which is the one case the integer is not `--ink-900`).
- A 1px `--rule-active` caret, 24 high, blinks at 1.06s (`steps(2)`), positioned after the last entered digit. Reduced motion: solid, no blink.
- Above it, `--t-label` `--ink-500`: the live consequence line — `记入后 今日可用 ¥58.40`, updating with `figureSettle` on every keypress. If the result is negative it renders in `--fig-over` and the words do not change.

### 5.6 Buttons

Four variants. There are no others. All are full-width bars or plain text; there are no small filled buttons anywhere in the product.

| Variant | Metrics | Rest | Pressed | Disabled |
| --- | --- | --- | --- | --- |
| **Primary bar** (存入账页) | full width of gutter box, height **52**, radius `--r-card`, label `--t-body` weight 600 | ground `--ink-900`, label `--paper` | ground opacity 0.86 (composite, not a new token), 100ms | ground `--surface-sunken`, label `--ink-300`, no border, `pointer-events:none` / `.disabled(true)` |
| **Held bar** (挂起 N 天) | identical box | ground `--surface`, 1px border `--fig-held`, label `--fig-held` weight 600 | ground `--surface-sunken` | n/a |
| **Flat action** (值 / 不值 / 记入账页 / 不买了) | height 52, no ground, no border; two of them sit side by side separated by a full-height 1px `--rule` | label `--t-body` weight 500 `--ink-900` | ground `--surface-sunken` | label `--ink-300` |
| **Text link** (仍要立即记入, 跳过, 导出本页) | inline, 44 min hit height via padding | `--t-body-sm`, `--ink-700`, 1px `--rule-active` underline at 2 offset | underline → `--ink-900` | `--ink-300`, no underline |

**The mutating primary label.** When the entry's category has a regret rate > 40 % over ≥ 30 judged entries **and** the amount exceeds that category's trailing median, the primary bar's label becomes:

`存入账页 · 这类你 62% 判过不值`

Same bar, same colour, same height; the label is `--t-body` with the clause after the `·` at weight 400 rather than 600. No dialog, no colour, no delay. If the sample gate (§7.8) is unmet, the label does not change.

**The 3-second hold ring.** When (a) the amount is ≥ the cooling threshold, or (b) 今日可用 is already negative, the primary bar requires a 3,000ms press-and-hold.

- Ring: an **unfilled 1px circle, diameter 24**, centred 16 from the bar's right edge, stroke `--paper` at 0.4 opacity over the `--ink-900` ground.
- Fill: a second 1px arc in `--paper`, starting at −90°, sweeping clockwise, **strictly linear, no easing**, completing at exactly 3,000ms. An eased timer lies about time.
- Release before completion: the arc drops to 0 instantly (no rewind animation) and nothing is saved.
- Reduced motion: the ring is replaced by a mono countdown `3 · 2 · 1` in `--t-mono-row`; the 3,000ms duration is **unchanged**, because the delay is the mechanic and only its depiction is animation.
- Web: `pointerdown` → `requestAnimationFrame` loop writing `stroke-dashoffset`; `pointercancel`/`pointerup` aborts. iOS: `LongPressGesture(minimumDuration: 3)` with a parallel `TimelineView(.animation)` driving the arc.

### 5.7 Chip / segmented control — 记账印章

The mandatory intent stamp. Three segments: **必要 · 想要 · 冲动**.

- Container: full gutter width, height **44**, ground transparent, a `--hairline-w` `--rule` line along its **bottom** edge only. No box, no fill, no pill outline.
- Segments: equal thirds, label `--t-body` weight 500, centred. Rest colour `--ink-500`; selected `--ink-900` weight 600.
- Selection indicator: a **2 × 100 %-of-label-width** rule in `--rule-stamp`, sitting **on** the bottom hairline (it overlaps it), centred under the selected label. It slides with `stampSlide` (180ms).
- Hit area: the full third, 44 high, with `--r-pill` on the *hit area only* (invisible; it exists so a tap ripple-free press state has a sane shape on iOS).
- **No default selection.** The container renders with no rule until a choice is made. `存入账页` is disabled until then.
- Escalation: a second tap on an already-selected 想要 escalates to 冲动 and slides the rule; a small `--t-micro` `--ink-500` line beneath reads `冷静期 8 天` when escalation changes the cooling tier.

**Filter chips** elsewhere in the app (ledger filters) are **not** chips: they are words in `--t-body-sm` with a 1px `--rule-active` underline when active and no underline when not. No pills anywhere.

### 5.8 Numeric keypad

- Ground `--surface-sunken`, full bleed to the sheet edges, no radius of its own.
- Grid **3 columns × 4 rows**, keys separated by `--hairline-w` `--rule` lines drawn as grid gaps (`gap: var(--hairline-w); background: var(--rule)` with each key on `--surface-sunken` — the classic hairline-grid technique; on iOS, a `Grid` with `Hairline` dividers).
- Key height **56** at default type; width = (sheet width − 2 × hairline) / 3.
- Layout:

```
1   2   3
4   5   6
7   8   9
.   0   ⌫
```
`.` is the 分 separator key, labelled `.` at `--t-fig-row`; it is disabled once a decimal exists. `⌫` is the `delete.backward` icon (§8) at 20 × 20, `--ink-900`.
- Digit label: `--t-fig-screen` at 0.61× → **27**, weight 400, `--font-fig`, `--ink-900`.
- Press state: key ground → `--surface`, 90ms, no scale, no ripple, no haptic on web; iOS fires `UIImpactFeedbackGenerator(style: .light)` once per keypress and nowhere else in the app.
- Long-press `⌫` (400ms) clears the whole amount, once, with no repeat-accelerate.
- Keyboard support (web): `0–9`, `.`, `Backspace`, `Enter` (commit if enabled). The keypad is `role="group"` with `aria-label="金额键盘"`; each key is a `<button>`.

### 5.9 Sheet / modal

- Presented from the bottom. Width = min(100 %, 480) centred; on web ≥720 it is a centred 480-wide sheet with the same bottom-anchored geometry (it does not become a dialog box).
- Ground `--surface`, radius `--r-sheet` **top corners only**, bottom corners 0.
- Shadow `--shadow-sheet` (§4.5). Scrim `--scrim`, no blur, tap-to-dismiss.
- Top padding `--s-8` (40) — there is **no grabber handle**, no title bar, and no close button on the capture sheet; dismissal is scrim tap, downward drag, or `Esc`. A modal that is not the capture sheet gets a `xmark` icon button at top-right, 44 × 44, `--ink-700`.
- Drag-to-dismiss: 1:1 tracking, threshold 88 or velocity > 600pt/s; below threshold it returns with `sheetPresent`'s curve at 200ms. Web implements this with pointer events on the sheet's top 64 (plus the whole sheet when the content is scrolled to top).
- Bottom inset: `env(safe-area-inset-bottom)` / `.safeAreaInset`. The keypad's last row sits flush to it with the inset as padding, not margin.
- Focus trap (web) and `.accessibilityAddTraits(.isModal)` (iOS) are mandatory.

### 5.10 Progress meters — there are exactly two, and neither is a bar

**冷静期弧 (cooling arc).** The only continuous animation in the product.
- Diameter **18** in a row's stamp slot; **32** on the 待购 row; 1px stroke, **butt cap**, `--fig-held`.
- Track: none. There is no unfilled companion ring — the arc simply shortens. (The 3-second hold ring is the one place a track exists, and that track is the same colour at 0.4 opacity on a dark ground.)
- Start at −90° (12 o'clock), depleting **counter-clockwise**. Remaining sweep = `360 × remaining / total`.
- **Repaint cadence: once per minute.** Not per frame. Web uses a single `setInterval(60_000)` shared by all visible arcs, aligned to the wall-clock minute; iOS uses `TimelineView(.periodic(from: .now, by: 60))`. Under `prefers-reduced-motion` the arc still updates (it is information, not motion) but the value transition is instant.
- Accompanied always by a mono countdown `还有 6 天 04:12` in `--t-mono-row` `--fig-held`.

**心愿物 progress rule.** Under 本年后悔.
- A 1px full-width `--rule` line; the achieved portion overdrawn in 1px `--fig-regret` from the left.
- Height 1. No cap, no radius, no track fill, no percentage badge. The percentage is in the sentence above it: `已经买得起「换相机」的 23%`.

**No rings, no donuts, no percentage circles anywhere else.** Budget consumption is expressed by the 今日可用 figure and the month strip, never by a ring.

### 5.11 Empty states

An empty state is a sentence and, at most, one text link. No illustration, no icon, no large glyph.

- Vertically offset `--s-9` (56) from the top of the content area, **not** centred in the viewport (centring reads as a placeholder screen).
- Line 1: `--t-body`, `--ink-700`, one sentence, factual: `本月还没有记录。`
- Line 2 (optional): `--t-body-sm`, `--ink-500`, the derivation or the count: `需要再记 24 笔才能生成后悔率。`
- Line 3 (optional): a single text link.
- Charts that lack sample render their empty state **in place of the chart**, at the chart's own height, so the page does not reflow when data arrives (§7.8).

### 5.12 Toast

Used for exactly one thing: **undo after a delete**, plus the save-and-stay confirmation on long-press commit.

- Bottom-anchored, 16 above the tab bar, gutter-inset, height 44, ground `--ink-900`, radius `--r-card`, label `--paper` `--t-body-sm`, action `撤销` right-aligned `--paper` weight 600 with a 1px `--paper`@0.5 underline.
- Duration **4,000ms**, no progress indicator, no dismiss button; swipe-down or tap-outside dismisses.
- One at a time; a second toast replaces the first with no exit animation.
- `role="status"` `aria-live="polite"` on web; `.accessibilityAddTraits(.updatesFrequently)` plus an `AccessibilityNotification.announcement` on iOS.
- The toast is the **only** element in the product with an inverted ground.

### 5.13 The 记 button

- A **56 diameter** circle, ground `--ink-900`, containing the character **记** at 22/500 in `--paper`. Not a plus, not an icon.
- Position: 20 from the right gutter, 16 above the tab bar (so 65 + safe area from the bottom edge).
- No shadow. It sits on `--paper`; the contrast of ink on paper is the separation.
- Press: ground opacity 0.86, 100ms, no scale.
- Hit target 56 × 56 (exceeds 44).
- `aria-label="记一笔"` / `.accessibilityLabel("记一笔")`.

### 5.14 The 周日审判 card

- Full-screen, ground `--paper`, content column 720 max, gutter `--s-5`.
- Top-right: mono progress `3 / 11` in `--t-mono-micro` `--ink-500`.
- Card body (not a `Card` — no border, no ground): amount `<Money size="screen">` at `--t-fig-screen`; beneath at 12 gap, `--t-body` `--ink-700` category; `--t-body-sm` `--ink-500` note; `--t-mono-row` `--ink-300` date + `· 7 天前`.
- If the entry carried a self-written reason, it is quoted verbatim beneath, in `--t-body` `--ink-700`, inside CJK corner brackets `「…」`, with a 2px `--rule` rule down the left edge inset 12. Max 20 characters, never truncated.
- Actions: two **flat actions** side by side, 值 / 不值, height 52, separated by a full-height 1px `--rule`, with a `--rule-strong` hairline above them.
- Verdict animation: `verdictSwipe` (§6). 不值 leaves a 1px `--fig-over` hairline in the position the card occupied; it persists until the deck ends.
- Deferral: `稍后` as a text link, **capped at 3 deferrals per entry**. On the fourth encounter the entry auto-records `worthIt = false` with reason `未敢面对`, and the card displays this as a statement before advancing.

---

## 6. Motion

### 6.1 Curves — there is one, plus linear

| Token | CSS | SwiftUI | Use |
| --- | --- | --- | --- |
| `--ease` | `cubic-bezier(0.32, 0.08, 0.24, 1)` | `.timingCurve(0.32, 0.08, 0.24, 1, duration: d)` | **Everything** that is not a timer or a scrim. |
| `--ease-linear` | `linear` | `.linear(duration: d)` | The 3-second hold ring, the cooling arc, the scrim fade. Timers and veils must not be eased. |

**No springs. No bounce. No overshoot.** `.spring`, `.interactiveSpring`, `.bouncy`, `.snappy`, and CSS `linear()` spring approximations MUST NOT appear in the codebase. A lint rule and a Swift grep in CI enforce this.

### 6.2 Durations

| Token | ms | Use |
| --- | --- | --- |
| `--d-instant` | 90 | Key press states, row press states. |
| `--d-quick` | 120 | Row content fade-in; label swaps. |
| `--d-base` | 180 | The stamp rule slide; tab rule slide; chip underline. |
| `--d-settle` | 220 | `figureSettle` per-digit transition. |
| `--d-print` | 240 | `rowPrint` hairline draw. |
| `--d-verdict` | 260 | Verdict card translate-out. |
| `--d-sheet` | 280 | Sheet present. |
| `--d-scrim` | 200 | Scrim fade in; also sheet dismiss. |
| `--d-hold` | 3000 | The commit hold ring. Not a visual duration — a mechanic. |
| `--d-toast` | 4000 | Toast dwell. |
| `--d-arc` | 60000 | Cooling arc repaint interval. |

### 6.3 Named transitions

| Name | What moves | Spec | Curve / duration |
| --- | --- | --- | --- |
| `figureSettle` | Hero, screen and section figures on value change | **Only the digits that changed** translate Y +6 → 0 and cross-fade 0 → 1; staggered **18ms right-to-left** (least-significant digit first). Unchanged digits do not move. | `--ease` / `--d-settle` |
| `sheetPresent` | Capture sheet & modals | translateY 24 → 0, opacity 0 → 1 | `--ease` / `--d-sheet` |
| `scrimFade` | Sheet scrim | opacity 0 → 0.28 (0 → 0.48 dark) | `--ease-linear` / `--d-scrim` |
| `sheetDismiss` | Sheet & scrim out | translateY 0 → 24, opacity → 0 | `--ease` / `--d-scrim` |
| `stampSlide` | The 2px selection rule, in the stamp row and the tab bar | translateX + width interpolation | `--ease` / `--d-base` |
| `rowPrint` | A newly saved ledger row | (1) the row's bottom hairline `scaleX 0 → 1`, `transform-origin: left`, 0 → 240ms; (2) row content opacity 0 → 1, **starting at 160ms**, over 120ms | `--ease` / `--d-print` + `--d-quick` |
| `verdictSwipe` | 周日审判 card | translateX ±120 and opacity 1 → 0; 值 goes left, 不值 goes right | `--ease` / `--d-verdict` |
| `holdRing` | The 3s commit ring | `stroke-dashoffset` full → 0 | `--ease-linear` / `--d-hold` |
| `coolArc` | Cooling arc | value step, no tween | none / repaint every `--d-arc` |
| `chartReveal` | Any chart entering the viewport or changing dataset | opacity 0 → 1 only. **Never grow-from-baseline, never draw-on, never stagger.** | `--ease` / `--d-quick` |
| `rowPress` | Ledger row / keypad key | ground colour change | `--ease-linear` / `--d-instant` |
| `toastIn` / `toastOut` | Toast | translateY 8 → 0 + opacity | `--ease` / `--d-base` |

Nothing else in the product animates. Screen-to-screen navigation uses the platform default push/pop on iOS and an **instant** swap on web (no page transition) — a page transition on a statement is theatre.

### 6.4 `figureSettle` implementation

**Web.** The figure is rendered as per-character spans by the Money component when `animate` is true. On value change, a diff between the previous and next character arrays marks changed indices; changed spans get a keyframe:

```css
@keyframes settle { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
.fig .d.changed { animation: settle var(--d-settle) var(--ease) both; }
```
with `animation-delay: calc(var(--i) * 18ms)` where `--i` counts from the right. The outgoing character is not animated out; it is replaced at frame 0. `will-change` MUST NOT be set (it pins layers on low-end Android); `transform` and `opacity` alone are enough.

**iOS.**
```swift
Text(parts.integer)
    .contentTransition(.numericText(value: Double(fen)))
    .animation(.timingCurve(0.32, 0.08, 0.24, 1, duration: 0.22), value: fen)
```
`.numericText` performs the per-digit crossfade natively and matches the web behaviour closely enough that the two were judged identical side by side. The 18ms stagger is native to `.numericText`'s implementation and is not separately configurable — this is an accepted, imperceptible divergence and is documented here so nobody "fixes" it by hand-rolling digit views.

### 6.5 The signature moment (normative sequence)

Saving an entry. Timings are from the moment the commit resolves (t = 0).

| t (ms) | Event |
| --- | --- |
| 0 | Sheet begins `sheetDismiss` (translateY 0 → 24, opacity → 0, 200ms). Scrim begins fading (200ms linear). |
| 0 | The ledger's new-row hairline begins `rowPrint` phase 1 (`scaleX 0 → 1` from the left, 240ms). It starts **while the sheet is still leaving**. |
| 0 | 今日可用 begins `figureSettle` (220ms, 18ms stagger right-to-left). |
| 160 | Row content begins fading in over 120ms. |
| 200 | Sheet and scrim are gone. |
| 240 | Hairline complete. |
| 280 | Row content complete. Sequence ends. |

**Nothing bounces. Nothing turns green. No 已保存 toast. No haptic.** If the allowance crosses zero, the hero simply arrives in `--fig-over` at the end of its settle, and the hairline beneath it takes the 破版 breakout on the same frame — with no animation of the breakout itself.

### 6.6 Reduced motion

`@media (prefers-reduced-motion: reduce)` / `UIAccessibility.isReduceMotionEnabled` collapses **every** transition above to a single `opacity` change over 100ms, with these exceptions:

- `holdRing` keeps its full 3,000ms duration and is rendered as a mono countdown (§5.6).
- `coolArc` keeps updating; only tweening (which it never had) is removed.
- Sheet presentation loses its translate but keeps the 100ms fade; scrim still appears.
- `rowPrint` becomes: the completed row fades in over 100ms, hairline already drawn.

---

## 7. Data visualisation

### 7.1 Global chart rules

1. **The number is always printed as text somewhere in or beside the chart.** A chart never carries a value that cannot be read as type.
2. **No legends.** Labels are inline, attached to their mark.
3. **No gridlines**, except the single standard line where the form defines one.
4. **No rounded caps.** `stroke-linecap: butt` / `.butt`. No `cornerRadius` on any mark.
5. **No shadows, no gradients, no fills other than solid ink or the 45° hatch.**
6. **No tooltips.** Interaction is a single full-height 1px `--rule-active` hairline that follows the pointer/finger while the chart's **header text is replaced** by the value under the cursor. On release the header returns after 400ms.
7. **No animation on entry except `chartReveal`** (opacity, 120ms).
8. **Two tick labels maximum per axis**, one at each extreme, `--t-micro` `--ink-500`.
9. **Colour:** neutral mark `--ink-700`; over-standard mark `--fig-over` **plus hatch**; cooling `--fig-held`; spared `--fig-spared`. Nothing else. Category never carries colour.
10. **Sample gating** (§7.8) applies to every derived chart.

### 7.2 The shared geometry module

All seven forms are laid out by **pure functions returning normalised coordinates in [0, 1]**, implemented twice and proven identical by fixtures.

- TS: `packages/geometry/src/*.ts`, no imports, no `Math.random`, no `Date`.
- Swift: `ios/Countbook/Design/Geometry.swift`, same function names, same argument order.
- Constants: `tokens/geometry.json`, generated into both.
- **Rounding contract:** every returned scalar passes through `q4(x) = round(x * 10000) / 10000` with **round-half-away-from-zero**. Swift's `rounded(.toNearestOrAwayFromZero)`; JS uses an explicit helper, because `Math.round(-0.5)` is `-0` in JS and `-1` in Swift — this is the exact class of bug the fixtures exist to catch.
- Division by zero returns `0`, never `NaN`/`inf`. Empty input returns an empty array.

```
deviationLayout(rows: [{actualFen, standardFen}], opts) -> [{ i, x0, x1, over }]
monthStripLayout(dailyFen: [Int], standardPerDayFen: Int, opts) -> { bars: [{x, w, y, h, over, overY, overH}], standardY }
yearLedgerLayout(rows) -> [{ i, x0, x1, over }]        // delegates to deviationLayout
regretBlockLayout(count: Int, badIndices: Set, cols: Int) -> [{ col, row, bad }]
annualBarSegments(valuesFen: [Int]) -> [{ x0, x1 }]
coolArcSweep(remainingMs, totalMs) -> { startDeg, endDeg }
hourScatterLayout(buckets: [Int](24), maxDot: Int) -> [{ col, row }]
hatchLines(w, h, period) -> [{ x0, y0, x1, y1 }]
```

`x`, `y`, `w`, `h` are fractions of the plot box. Render layers multiply by their own pixel box and pixel-snap (§4.4).

### 7.3 偏差条 — Deviation Bars *(primary report chart)*

**Argument:** distance from a self-set standard, not an absolute total.

| Constant | Value |
| --- | --- |
| `deviation.barHeight` | 6 |
| `deviation.rowHeight` | 34 |
| `deviation.zeroRuleWidth` | 1 |
| `deviation.minBarLength` | 2 |
| `deviation.labelGap` | 10 |

- Plot box spans the content column minus the 96 amount gutter. A single **vertical 1px `--rule-strong` rule at the horizontal centre** is zero.
- Each category is one row: name left-aligned `--t-body` `--ink-700`; the bar; the deviation figure right-aligned in the 96 gutter (`<Money size="row" role={over ? "allowance" : "neutral"}>` with an explicit `+`/`−`).
- Bar: 6 tall, butt caps, `--r-none`. Left of zero = `--ink-700` (under standard). Right of zero = `--fig-over` **plus hatch**.
- Scale: symmetric, `maxAbs = max(|deviation|)` across rows, so the largest bar touches the plot edge. Never a per-row scale.
- **Ordering: by 后悔金额 descending**, not by deviation, not by name. Categories with no judged entries sort last, by deviation descending.
- Ticks: two only — `−¥{maxAbs}` at the left edge, `+¥{maxAbs}` at the right, `--t-micro` `--ink-500`.
- 破版: if the month total is over standard, the zero rule (and only the zero rule) breaks the column (§4.6).

**SVG:**
```html
<svg viewBox="0 0 W H" role="img" aria-label="…" shape-rendering="crispEdges">
  <g fill="var(--ink-700)"><rect x="…" y="…" width="…" height="6"/></g>
  <g fill="var(--fig-over)"><rect …/><rect … fill="url(#hatch)"/></g>
  <line x1="W/2" y1="0" x2="W/2" y2="H" stroke="var(--rule-strong)" stroke-width="1"/>
</svg>
```
**SwiftUI:**
```swift
Canvas { ctx, size in
    for b in deviationLayout(rows, opts) {
        let r = CGRect(x: b.x0 * size.width, y: …, width: (b.x1 - b.x0) * size.width, height: 6)
        ctx.fill(Path(r), with: .color(b.over ? Palette.figOver : Palette.ink700))
        if b.over { ctx.fill(hatchPath(in: r), with: .color(Palette.figOver)) }
    }
    ctx.stroke(Path { $0.move(to: .init(x: size.width/2, y: 0)); $0.addLine(to: .init(x: size.width/2, y: size.height)) },
               with: .color(Palette.ruleStrong), lineWidth: 1/scale)
}
```

### 7.4 月度日柱 — Month Strip

**Argument:** which days broke the line.

| Constant | Value |
| --- | --- |
| `monthStrip.barWidth` | 3 |
| `monthStrip.barGap` | 2 |
| `monthStrip.height` | 96 |
| `monthStrip.weekendTick` | 3 (below baseline, 3 gap) |

- 28–31 bars, 3 wide, 2 gap, drawn **up from a baseline rule** (`.rule--critical`, `--rule-strong`).
- A **second 1px hairline** runs horizontally at the daily-standard height in `--rule-strong`. Bars above it are drawn in two pieces: the portion below the line in `--ink-700`, the portion above in `--fig-over` + hatch — so an overspend day **visibly breaks the line**.
- Weekend days get a 3-tall `--ink-300` tick below the baseline.
- Today's bar carries a 1px `--rule-active` vertical rule the full plot height behind it.
- Scale: `maxHeight` maps to `max(maxDaily, standardPerDay × 1.6)`, so the standard line never sits at the very top.
- Interaction: a single full-height 1px `--rule-active` hairline follows the pointer; the section header text is replaced by `03-14 · ¥312` (`<Money fraction="hide">`). Touch target is the full column (5 wide) with a 44-high hit strip.
- 破版: if the month-to-date total is over the pro-rated standard, the **baseline** breaks the column.

### 7.5 年账页 — Year Ledger

Twelve stacked deviation rows, `deviation.rowHeight` 28 instead of 34, month label in `--t-mono-row` `--ink-500` (`01`…`12`), amount in the 96 gutter. Reuses `deviationLayout` verbatim. Reads as a printed page; no chart chrome at all beyond the shared zero rule.

### 7.6 后悔率 — Regret Block

| Constant | Value |
| --- | --- |
| `regret.unit` | 8 |
| `regret.gap` | 3 |
| `regret.cols` | `floor((plotWidth + gap) / (unit + gap))`, min 12 |

- One 8 × 8 square per **judged** entry, wrapping left-to-right, top-to-bottom. `--r-none`.
- 值 → `--ink-900`. 不值 → `--fig-over` **plus hatch** (so 22.5 % is legible in greyscale).
- **Ordering:** chronological, oldest first. Not sorted by verdict — clustering the red would be editorialising.
- Caption beneath, `--t-body-sm`: `已判 40 · 不值 9 · 22.5%`. No legend; 9 red in 40 needs none.
- Accessibility: the whole block is one element with `aria-label` / `accessibilityLabel` = the caption. Individual squares are `aria-hidden`.

### 7.7 Remaining forms

**订阅年化条 — Subscription Annual Bar.** One horizontal bar, height 14, full content width, `--r-none`, segmented **by 1px `--paper` gaps** (not by colour), fills alternating `--ink-700` / `--ink-500` in rank order. Each segment is tied by a 1px `--rule` **leader line** dropping to a ranked label column beneath (`名称 · ¥300/年`, `--t-micro`). Segments below `annualBar.minSegment` (3) are merged into a final `其他` segment. Ranked by annual cost descending, always.

**冷静期弧 — Cooling Arc.** Specified in §5.10. Geometry from `coolArcSweep`. `stroke-linecap: butt`, `geometricPrecision` (not `crispEdges`).

**时段散点 — Hour Scatter.** 24 columns (00–23), column width 3, gap 2; each entry in that hour is a 3 × 3 `--ink-700` square stacked upward with 2 gap, max 10 rows then a `+n` in `--t-micro`. Entries stamped 冲动 render `--fig-over` + hatch. Two ticks only: `00` and `23`. Purpose: expose late-night ordering. Height 96.

**Interaction hairline** is shared by the month strip and the hour scatter, and is the only interactive chart affordance in the product.

### 7.8 Sample gating

A derived statistic MUST NOT render until it has enough sample, and MUST state the shortfall instead.

| Statistic | Minimum sample | Copy when unmet |
| --- | --- | --- |
| 后悔率 (any) and the Regret Block | 30 judged entries | `需要再判 24 笔才能给出后悔率。` |
| The mutating primary button label | 30 judged entries **in that category** | (label simply does not change) |
| 小额漏水 equivalence divisor | 20 above-threshold entries in the trailing 90 days | `¥1,238 · 大额中位数样本不足，暂不换算。` |
| Median standard proposal | 30 days of data | `再记 12 天可给出建议标准。` |
| Deviation bars | 1 full closed month, or ≥ 14 days elapsed in the open month | `本月还需 6 天数据。` |
| Hour scatter | 40 entries | `需要再记 13 笔。` |

The empty state occupies the chart's exact height (§5.11) so the page does not reflow when the gate opens.

### 7.9 Cross-platform fixtures (the only thing keeping seven charts identical)

`tokens/fixtures/geometry/*.json`, each `{ "fn": "monthStripLayout", "args": [...], "expect": [...] }`.

- TS: a Vitest suite iterating every fixture, asserting deep equality on the `q4`-quantised output.
- Swift: an XCTest that loads the **same JSON files** from the repo (added as a test resource, not copied) and asserts the same equality.
- CI runs both. A geometry change that does not update both is a red build.
- Required fixtures at minimum: empty input; single element; all-zero; a negative deviation larger than any positive; a day exactly equal to the standard (must render **under**, not over — the comparison is `>` strictly); a 31-day month; a 28-day month; `-0.5` and `0.5` rounding cases; a subscription list where two segments fall below `minSegment`.

---

## 8. Iconography

### 8.1 The governing rule: a word beats an icon

This product has **no icon library, no CDN, and almost no icons**. Wherever a label can be a word, it is a word: tabs are words, categories are words, filters are underlined words, row actions are words, sync state is a word, the 记 button is a character. An icon is permitted only where it replaces a word that would be *longer than the control* (back, close, delete-key) or where it is a standard affordance the user reads pre-attentively (chevron, search).

**SF Symbols MUST NOT be used**, despite being a system framework. The reason is not licensing — it is that SF Symbols have no CSS equivalent, so any screen containing one is guaranteed to differ between platforms. Both platforms draw the same hand-authored geometry.

### 8.2 Authoring spec

- Grid **24 × 24**; live area **20 × 20**, centred, so every icon has a 2 margin.
- Stroke **1.5**, `stroke-linecap: butt`, `stroke-linejoin: miter`, `miterlimit 4`. **No fills** except `checkmark`'s optional filled variant (unused) and the `ellipsis` dots.
- All coordinates on the 0.5 grid so a 1.5 stroke lands on pixel boundaries at 1×.
- Optical size: rendered at **20 × 20** in row/header contexts, **24 × 24** in the keypad.
- Colour: `currentColor` on web / `.foregroundStyle` on iOS. Icons never carry a colour of their own.
- Source of truth: `tokens/icons.json` → `{ name, viewBox, paths: [d] }`, generated into `web/src/design/icons.tsx` (a React map of `<path d>`) and `ios/Countbook/Design/Icons.swift` (a `Path` builder per icon, from the **same** `d` strings, parsed by a tiny hand-written SVG-path subset parser supporting `M L H V A Z` only).
- Web ships them as inline `<svg>` in a single `Icon` component. **No sprite sheet fetched over the network, no icon font, no `<img>`.**

### 8.3 The complete icon set — 14 icons, and no more

Adding a fifteenth requires an amendment to this document.

| # | Name | Geometry (24 grid) | Where it appears |
| --- | --- | --- | --- |
| 1 | `chevron.right` | polyline 9,5 → 15.5,12 → 9,19 | Row disclosure in 设置 and 订阅; the "more" affordance on the 小额漏水 strip. |
| 2 | `chevron.left` | mirror of #1 | Back, in the screen header, at 44 × 44, `--ink-700`. iOS uses this in a custom back button, **not** the system chevron. |
| 3 | `chevron.up` | polyline 5,15 → 12,8.5 → 19,15 | Stepper increment in the standard editor; collapsing a report section. |
| 4 | `chevron.down` | mirror of #3 | Stepper decrement; expanding a report section; the month picker in 账页. |
| 5 | `xmark` | two lines 6,6 → 18,18 and 18,6 → 6,18 | Modal close (never on the capture sheet); clearing the search field. |
| 6 | `delete.backward` | pentagon 9,4 → 21,4 → 21,20 → 9,20 → 3,12 Z, plus an inner ✕ from 12,9 → 17,15 and 17,9 → 12,15 | The keypad's ⌫ key. Only place it appears. |
| 7 | `magnifyingglass` | circle c(10.5,10.5) r 6.5 + line 15.2,15.2 → 20,20 | The ledger search field's leading affordance. |
| 8 | `checkmark` | polyline 5,12.5 → 10,17.5 → 19.5,6.5 | Selected row in multi-select; a confirmed 保留 on an unclaimed subscription; the 已判 marker on a reviewed entry in 账页. |
| 9 | `ellipsis` | three 2×2 squares (`--r-none`) at x 5.5, 11, 16.5, y 11 | Row overflow menu on 订阅 and 待购 (web only; iOS uses swipe actions). |
| 10 | `plus` | lines 12,5 → 12,19 and 5,12 → 19,12 | Add a want (待购), add a subscription, add a 心愿物. **Never for 记一笔** — that is the 记 character button. |
| 11 | `minus` | line 5,12 → 19,12 | Stepper decrement in compact contexts; removing a per-category standard. |
| 12 | `tray.arrow.down` | tray: 4,14 → 4,19 → 20,19 → 20,14; arrow: 12,5 → 12,14 with head 8.5,10.5 → 12,14 → 15.5,10.5 | 导出账页 (CSV / JSON) in 设置. |
| 13 | `square.and.arrow.up` | box open at top: 5,10 → 5,20 → 19,20 → 19,10; arrow 12,16 → 12,4 with head 8.5,7.5 → 12,4 → 15.5,7.5 | 导出本页 on the report (PNG / print). |
| 14 | `exclamationmark` | line 12,5 → 12,14.5 plus a 2 × 2 square at 11,17.5 | The **only** error affordance: sync failure, a passphrase mismatch, a write failure. It renders in `--ink-900`, **not** in `--fig-over`, next to a 2px `--ink-900` left rule on the message row — because red is rationed to three uses and an error is not one of them. |

### 8.4 Things that look like icons but are not

| Thing | What it actually is |
| --- | --- |
| The 记 button | The character 记 in `--font-sans` at 22/500. |
| The stamp glyphs 必 / 想 / 冲 | Characters at `--t-stamp`. |
| The 结 seal | The character 结 in a 20 × 20 `--surface-sunken` block with a 1px inset top/left `--rule-strong` border. |
| The cooling arc | A chart mark (§5.10). |
| The sync state | The words 已同步 / 待同步 / 离线, `--t-mono-row`. There is **no** sync icon and **no spinner anywhere in the product**. |
| The key fingerprint | Four mono hex quads: `4F2A · 91C7 · 0B3E · D845`, `--t-mono-row` `--ink-700`, separated by U+00B7 with hair spaces. |
| Category identity | Text. There is no category icon grid. |

---

## 9. Accessibility

Accessibility is not a pass at the end; three of this system's core decisions (R8, the Money primitive, `--rule-active`) exist because of it.

### 9.1 Contrast

See §2.9 for the full table. Enforced by a build-time script `scripts/check-contrast.mjs` that reads `tokens/color.json`, computes every declared pairing, and fails CI on a regression. The script also asserts the R8 pairing set: every token/size pairing declared in `tokens/type.json` must clear 4.5:1 below 19px and 3:1 at or above.

### 9.2 Focus

- **Visible focus is mandatory on web.** `:focus-visible` → `outline: 2px solid var(--rule-stamp); outline-offset: 2px; border-radius: 0`. The outline is `--ink-900` (or `--ink-900` inverted to `--paper` on the commit bar and the toast). It is never removed, never replaced by a colour change alone, and never `outline: none`.
- Focus order follows DOM order; the capture sheet traps focus and returns it to the 记 button on dismiss.
- Skip link: a visually-hidden `跳到主要内容` as the first focusable element on every page.
- iOS: keyboard focus (hardware keyboard / Full Keyboard Access) uses the system focus ring; `@AccessibilityFocusState` moves VoiceOver focus to the sheet's amount display on present and back to the 记 button on dismiss.

### 9.3 Hit targets

- **Minimum 44 × 44** for every interactive element, on both platforms, with no exceptions granted.
- Where the visual element is smaller than 44 (the stamp segment's 2px rule, the chip underline, the chart's per-day column at 5 wide), the hit area is expanded with transparent padding — web via `::after { position:absolute; inset:-Npx }` on a `position:relative` parent, iOS via `.contentShape(Rectangle())` on a padded frame.
- Adjacent targets are separated by ≥ 4 of dead space, except the two flat verdict actions, which share a rule and are 52 tall and half the screen wide.

### 9.4 Dynamic Type and zoom

- iOS supports the full range through `.accessibility5`, with per-token caps (§3.4) and the ledger row's two-line reflow at `.accessibility1`.
- Web supports browser zoom to 200 % and OS font-size changes; all sizes are rem, the hero clamps, and the layout is single-column, so 200 % zoom produces no horizontal scroll at 320px viewport width — asserted by a Playwright test.
- The 96 amount gutter scales with the root font size (`--gutter-amount: 6rem`), so it never truncates a figure at large type.
- **Text is never rendered as an image**, including on the 导出本页 path, which produces real text in the print stylesheet and only rasterises for the PNG variant.

### 9.5 Reduced motion, reduced transparency, increased contrast

- Reduced motion: §6.6.
- Reduced transparency: the system has no transparency to reduce (no blur, no material). The scrim remains — it is opacity, not translucency of content, and is required for modality.
- Increased contrast: the HC token set (§2.8) plus 1px hairlines plus the suspension of R8's `--ink-300` fraction tone.
- `prefers-reduced-data` (web): no effect — the app already fetches nothing.

### 9.6 Screen readers

- **Money** is the critical case and is fully specified in §3.6.3. Every figure exposes one element with a complete spoken label; fragments are hidden.
- **Ledger rows** are a single accessibility element whose label is `08:41 餐饮 星巴克拿铁 冲动 38.20 元`, with 更正/冲销 children folded into the same label (`已更正，原 288 元`). Actions (更正, 冲销) are exposed as `UIAccessibilityCustomAction` / an ARIA menu on the row.
- **Charts** are `role="img"` with a label that is the chart's own printed caption, plus a visually-hidden `<table>` alternative for the deviation chart and the month strip (`aria-describedby`). iOS uses `.accessibilityChartDescriptor` where available and a plain label otherwise.
- **Live regions:** the 今日可用 hero is `aria-live="polite"` and announces only the final settled value, not each digit. iOS posts a single `AccessibilityNotification.announcement` after the settle completes. The toast is `role="status"`.
- **Language:** `<html lang="zh-CN">`; English strings are wrapped in `lang="en"` so a screen reader switches voice. On iOS, `.accessibilityLanguage("zh-Hans")` is set on the root and overridden per-string.
- **State without colour:** every state carried by `--fig-over` is also carried by a word or the hatch. An over-standard bar has an explicit `+` sign on its figure; a negative allowance has a U+2212; a 不值 square is hatched. No information is conveyed by hue alone anywhere in the product (WCAG 1.4.1).

### 9.7 Motion-sensitive and timing-sensitive mechanics

- The **3-second hold** is a timed interaction. WCAG 2.2.1 requires that timing be adjustable or essential. It is declared **essential** (the delay is the mechanic) and is documented in 设置 with an explicit off switch: `提交前的 3 秒等待` — turning it off is a `StandardRevision`-logged change, so the record shows the user disabled it and when.
- The **cooling period** is not an interaction timeout; nothing is lost by waiting. No accommodation is required, and the 仍要立即记入 escape is always present.
- The **toast** dwells 4,000ms, above the 20,000ms threshold exemption; it is also non-essential (delete is always undoable from the ledger's 冲销 history), and it is re-shown on focus for keyboard users.

---

## Appendix A — Implementation checklist

A change is complete when all of these are true.

- [ ] No hex, duration, easing, radius, spacing or chart constant appears outside `tokens/*.json`.
- [ ] `pnpm gen:tokens` produces no diff.
- [ ] `scripts/check-contrast.mjs` passes.
- [ ] Geometry fixtures pass in **both** Vitest and XCTest.
- [ ] No `backdrop-filter`, no `Material`, no `blur`, no `spring`, no `gradient`, no `box-shadow` other than `--shadow-sheet`, no `will-change`, no SF Symbol, no webfont, no network request for an asset.
- [ ] Every money figure goes through `<Money>` / `MoneyText`.
- [ ] Every `--ink-300` usage satisfies R8.
- [ ] Every state carried by `--fig-over` is also carried by a glyph, word, or hatch.
- [ ] At most one chromatic figure per screen; at most one 破版 per screen.
- [ ] Capture path median measured under 6 seconds and 6 taps in the instrumented build.

## Appendix B — Divergences accepted between platforms

These are the only known differences. Each is deliberate; none may be "fixed" without amending this document.

| # | Divergence | Reason |
| --- | --- | --- |
| 1 | Corner radii differ numerically (14/9/7 web vs 16/10/8 iOS) | Circular vs continuous corners; the numbers differ so the appearance matches. |
| 2 | `--t-mono-row` is weight 450 on web, `.regular` on iOS | No public 450 weight in SwiftUI; the difference is a half-step on a 12px timestamp. |
| 3 | `figureSettle`'s 18ms stagger is explicit on web, native inside `.numericText` on iOS | Hand-rolling digit views on iOS would cost more than the imperceptible timing difference. |
| 4 | The sheet shadow uses radius 16 on iOS against CSS's 32/−8 | CSS negative spread has no SwiftUI analogue; 16 was measured as the closest match. |
| 5 | Haptics on iOS keypad only; none on web | Web has no equivalent; the haptic is not load-bearing. |
| 6 | Swipe row actions on iOS; long-press/right-click menu on web | Platform convention; the same two actions, the same labels. |
| 7 | Cooling-period notification is a local notification on iOS, a service-worker check on next open on web | Documented product risk; web surfaces unlocked items pinned to the top of 待购 instead. |
| 8 | Web adds a `copy` handler and `user-select: all` on `.fig` | iOS has no equivalent selection problem. |

## Appendix C — Amendment record

| Date | Change | By |
| --- | --- | --- |
| 2026-09-08 | v1.0 — initial system. `--ink-300` darkened from `#A5A29A`/`#605D56` for 3:1; `--rule-active` introduced so state-bearing rules meet 1.4.11; `--fig-regret` added so red carries exactly one meaning; radius mapping table adopted; hatch added as the non-colour over-channel. | Design |