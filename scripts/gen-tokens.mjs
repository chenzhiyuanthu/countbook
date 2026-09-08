#!/usr/bin/env node
// design/tokens.json is the only place a hex value, a metric or a duration is
// written. This generates the web custom properties and the Swift theme from it,
// so the two platforms cannot drift.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const T = JSON.parse(readFileSync(resolve(root, 'design/tokens.json'), 'utf8'))

const BANNER = (target) =>
  `/* GENERATED FROM design/tokens.json — DO NOT EDIT.\n   Regenerate with \`node scripts/gen-tokens.mjs\`.\n   ${target} */\n`

const kebab = (s) => s.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()
const colorEntries = Object.entries(T.color).filter(([k]) => !k.startsWith('$'))

/* ── web ─────────────────────────────────────────────────────────────── */

const cssVar = (name, value) => `  --${name}: ${value};`

const light = colorEntries.map(([k, v]) => cssVar(`c-${kebab(k)}`, v.light))
const dark = colorEntries.map(([k, v]) => cssVar(`c-${kebab(k)}`, v.dark))

const space = Object.entries(T.space)
  .filter(([k]) => !k.startsWith('$'))
  .map(([k, v]) => cssVar(`s-${k}`, `${v}px`))

const radius = Object.entries(T.radius)
  .filter(([k]) => !k.startsWith('$'))
  .map(([k, v]) => cssVar(`r-${kebab(k)}`, `${v.web}px`))

// Type sizes are emitted in rem against a 16px root: browser zoom and the OS
// text-size setting then scale the whole scale, which hard px would defeat.
const type = Object.entries(T.type)
  .filter(([k]) => !k.startsWith('$'))
  .flatMap(([k, v]) => [
    cssVar(`t-${kebab(k)}-size`, `${(v.size / 16).toFixed(4).replace(/0+$/, '')}rem`),
    cssVar(`t-${kebab(k)}-weight`, String(v.weight)),
    cssVar(`t-${kebab(k)}-tracking`, `${v.tracking}em`),
    cssVar(`t-${kebab(k)}-leading`, String(v.leading)),
  ])

const [e0, e1, e2, e3] = T.motion.ease
const motion = [
  cssVar('ease', `cubic-bezier(${e0}, ${e1}, ${e2}, ${e3})`),
  ...Object.entries(T.motion)
    .filter(([k]) => !k.startsWith('$') && k !== 'ease')
    .map(([k, v]) => cssVar(`d-${kebab(k)}`, `${v}ms`)),
]

const layout = Object.entries(T.layout)
  .filter(([k]) => !k.startsWith('$'))
  .map(([k, v]) => cssVar(`l-${kebab(k)}`, `${v}px`))

const css = `${BANNER('web/src/styles/tokens.css')}
:root {
  color-scheme: light dark;

  /* colour — light */
${light.join('\n')}

  /* space */
${space.join('\n')}

  /* radius (web values: circular corners read heavier than iOS continuous ones) */
${radius.join('\n')}

  /* type */
${type.join('\n')}

  /* motion */
${motion.join('\n')}

  /* layout */
${layout.join('\n')}

  /* elevation — the only shadow in the system */
  --e-sheet: ${T.elevation.sheet.web};

  /* families — no webfont, no CDN request */
  --f-sans: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", system-ui,
    "Segoe UI Variable", "Segoe UI", Roboto, "PingFang SC", "HarmonyOS Sans SC",
    "Source Han Sans SC", "Noto Sans SC", "Microsoft YaHei", sans-serif;
  --f-mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
}

:root[data-theme="dark"] {
${dark.join('\n')}
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
${dark.map((l) => '  ' + l).join('\n')}
  }
}
`

/* ── iOS ─────────────────────────────────────────────────────────────── */

const hexToSwift = (hex) => {
  const m = /^#([0-9a-f]{6})$/i.exec(hex.trim())
  if (m) {
    const n = parseInt(m[1], 16)
    const f = (x) => (x / 255).toFixed(4)
    return `Color(red: ${f((n >> 16) & 255)}, green: ${f((n >> 8) & 255)}, blue: ${f(n & 255)})`
  }
  const rgba = /^rgba\(([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\)$/.exec(hex.trim())
  if (rgba) {
    const f = (x) => (Number(x) / 255).toFixed(4)
    return `Color(red: ${f(rgba[1])}, green: ${f(rgba[2])}, blue: ${f(rgba[3])}).opacity(${Number(rgba[4])})`
  }
  throw new Error(`unsupported colour literal: ${hex}`)
}

const swiftColors = colorEntries
  .map(([k, v]) => {
    const doc = v.use ? `    /// ${v.use}\n` : ''
    return `${doc}    static let ${k} = dynamic(light: ${hexToSwift(v.light)}, dark: ${hexToSwift(v.dark)})`
  })
  .join('\n')

const swiftSpace = Object.entries(T.space)
  .filter(([k]) => !k.startsWith('$'))
  .map(([k, v]) => `    static let s${k}: CGFloat = ${v}`)
  .join('\n')

const swiftRadius = Object.entries(T.radius)
  .filter(([k]) => !k.startsWith('$'))
  .map(([k, v]) => `    static let ${k}: CGFloat = ${v.ios}`)
  .join('\n')

const swiftType = Object.entries(T.type)
  .filter(([k]) => !k.startsWith('$'))
  .map(
    ([k, v]) =>
      `    static let ${k} = Metrics(size: ${v.size}, weight: ${v.weight}, tracking: ${v.tracking}, leading: ${v.leading})`,
  )
  .join('\n')

const swiftMotion = Object.entries(T.motion)
  .filter(([k]) => !k.startsWith('$') && k !== 'ease')
  .map(([k, v]) => `    static let ${k}: Double = ${(v / 1000).toFixed(3)}`)
  .join('\n')

const swiftLayout = Object.entries(T.layout)
  .filter(([k]) => !k.startsWith('$'))
  .map(([k, v]) => `    static let ${k}: CGFloat = ${v}`)
  .join('\n')

const swiftRules = Object.entries(T.rule)
  .filter(([k]) => !k.startsWith('$'))
  .map(([k, v]) => `    static let ${k} = ${v}`)
  .join('\n')

const swift = `${BANNER('ios/Countbook/Design/Tokens.swift')}
import SwiftUI

// A resolved-per-appearance colour: SwiftUI has no literal for "this hex in
// light, that hex in dark", so each token wraps a UIColor trait resolver.
private func dynamic(light: Color, dark: Color) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
}

enum Ink {
${swiftColors}
}

enum Space {
${swiftSpace}
}

enum Radius {
${swiftRadius}
}

enum TypeScale {
    struct Metrics {
        let size: CGFloat
        let weight: Int
        let tracking: CGFloat
        let leading: CGFloat

        var font: Font { .system(size: size, weight: swiftWeight) }
        /// Tracking is expressed in em in the token file; SwiftUI wants points.
        var kerning: CGFloat { tracking * size }
        var lineSpacing: CGFloat { max(0, size * (leading - 1.2)) }

        private var swiftWeight: Font.Weight {
            switch weight {
            case ...300: return .light
            case 301...400: return .regular
            case 401...500: return .medium
            case 501...600: return .semibold
            default: return .bold
            }
        }
    }

${swiftType}
}

enum Motion {
    /// The one curve. No springs, no overshoot, anywhere.
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(${e0}, ${e1}, ${e2}, ${e3}, duration: duration)
    }

${swiftMotion}
}

enum Layout {
${swiftLayout}

    /// One device pixel, not one point.
    static var hairlineWidth: CGFloat { 1 / max(UIScreen.main.scale, 1) }
}

enum Elevation {
    struct Layer { let opacity: Double; let radius: CGFloat; let y: CGFloat }
    static let sheet: [Layer] = [
${T.elevation.sheet.ios.map((l) => `        Layer(opacity: ${l.opacity}, radius: ${l.radius}, y: ${l.y})`).join(',\n')}
    ]
}

/// Product constants the interface prints verbatim, kept beside the design
/// values so the two cannot disagree.
enum Rules {
${swiftRules}
}
`

const write = (rel, body) => {
  const p = resolve(root, rel)
  mkdirSync(dirname(p), { recursive: true })
  writeFileSync(p, body)
  console.log(`  ${rel}  ${body.split('\n').length} lines`)
}

console.log('generated from design/tokens.json:')
write('web/src/styles/tokens.css', css)
write('ios/Countbook/Design/Tokens.swift', swift)
