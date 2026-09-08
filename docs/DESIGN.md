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

