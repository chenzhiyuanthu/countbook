/* GENERATED FROM design/tokens.json — DO NOT EDIT.
   Regenerate with `node scripts/gen-tokens.mjs`.
   ios/Countbook/Design/Tokens.swift */

import SwiftUI

// A resolved-per-appearance colour: SwiftUI has no literal for "this hex in
// light, that hex in dark", so each token wraps a UIColor trait resolver.
private func dynamic(light: Color, dark: Color) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
}

enum Ink {
    /// app ground — 宣纸
    static let paper = dynamic(light: Color(red: 0.9569, green: 0.9373, blue: 0.8902), dark: Color(red: 0.0784, green: 0.0745, blue: 0.0588))
    /// cards, sheets, rows, the tab bar
    static let surface = dynamic(light: Color(red: 0.9804, green: 0.9686, blue: 0.9373), dark: Color(red: 0.1098, green: 0.1020, blue: 0.0824))
    /// keypad, inset wells, table headers
    static let surfaceSunken = dynamic(light: Color(red: 0.9255, green: 0.9020, blue: 0.8471), dark: Color(red: 0.0588, green: 0.0549, blue: 0.0431))
    /// hero + section figures, primary text
    static let ink900 = dynamic(light: Color(red: 0.1137, green: 0.1059, blue: 0.0902), dark: Color(red: 0.9490, green: 0.9294, blue: 0.8863))
    /// body text, row figures
    static let ink700 = dynamic(light: Color(red: 0.2314, green: 0.2196, blue: 0.1882), dark: Color(red: 0.7961, green: 0.7725, blue: 0.7176))
    /// labels, secondary rows, section marks
    static let ink500 = dynamic(light: Color(red: 0.4275, green: 0.4039, blue: 0.3490), dark: Color(red: 0.5569, green: 0.5333, blue: 0.4784))
    /// units, 分, timestamps, placeholders, resting tab marks
    static let ink300 = dynamic(light: Color(red: 0.6392, green: 0.6157, blue: 0.5569), dark: Color(red: 0.3804, green: 0.3608, blue: 0.3216))
    /// hairlines
    static let rule = dynamic(light: Color(red: 0.8667, green: 0.8392, blue: 0.7765), dark: Color(red: 0.1725, green: 0.1608, blue: 0.1451))
    /// section rules, focused card borders
    static let ruleStrong = dynamic(light: Color(red: 0.7882, green: 0.7608, blue: 0.6980), dark: Color(red: 0.2431, green: 0.2275, blue: 0.2000))
    /// 朱砂 — negative 今日可用, category above standard, the stamps
    static let figOver = dynamic(light: Color(red: 0.7176, green: 0.2078, blue: 0.1686), dark: Color(red: 0.8863, green: 0.3804, blue: 0.3098))
    /// ONLY: cooling period, pending sync
    static let figHeld = dynamic(light: Color(red: 0.6039, green: 0.4157, blue: 0.1098), dark: Color(red: 0.8235, green: 0.6510, blue: 0.2902))
    /// 青绿 — a gain, 已放弃 / 已省 totals, a confirmed sync
    static let figSpared = dynamic(light: Color(red: 0.1725, green: 0.4314, blue: 0.3098), dark: Color(red: 0.4353, green: 0.7451, blue: 0.6039))
    /// ONLY: 后悔金额 — dead lead, never urgent
    static let figRegret = dynamic(light: Color(red: 0.3412, green: 0.3255, blue: 0.2902), dark: Color(red: 0.6039, green: 0.5882, blue: 0.5490))
    /// modal scrim, no blur
    static let scrim = dynamic(light: Color(red: 0.1137, green: 0.1059, blue: 0.0902).opacity(0.3), dark: Color(red: 0.0000, green: 0.0000, blue: 0.0000).opacity(0.5))
    /// the 记 button fill — the one seal on the page
    static let accentInk = dynamic(light: Color(red: 0.7176, green: 0.2078, blue: 0.1686), dark: Color(red: 0.8863, green: 0.3804, blue: 0.3098))
    /// text on the 记 button
    static let accentOn = dynamic(light: Color(red: 1.0000, green: 1.0000, blue: 1.0000), dark: Color(red: 0.0784, green: 0.0745, blue: 0.0588))
    /// 靛青 — the selected rule, the standard line, the active tab
    static let indigo = dynamic(light: Color(red: 0.1333, green: 0.2471, blue: 0.3882), dark: Color(red: 0.4784, green: 0.5922, blue: 0.7412))
    /// the 今日可用 ground: the ledger cover
    static let indigoGround = dynamic(light: Color(red: 0.1333, green: 0.2471, blue: 0.3882), dark: Color(red: 0.1059, green: 0.1804, blue: 0.2784))
    /// figure and title on the indigo ground
    static let onIndigo = dynamic(light: Color(red: 0.9569, green: 0.9373, blue: 0.8902), dark: Color(red: 0.9333, green: 0.9490, blue: 0.9686))
    /// provenance line on the indigo ground
    static let onIndigoMuted = dynamic(light: Color(red: 0.7843, green: 0.8275, blue: 0.8863), dark: Color(red: 0.6235, green: 0.6902, blue: 0.7765))
    /// a negative figure on the indigo ground
    static let overOnIndigo = dynamic(light: Color(red: 0.9451, green: 0.7255, blue: 0.6627), dark: Color(red: 0.9451, green: 0.6549, blue: 0.6039))
    /// the month strip: a day under the line
    static let bar = dynamic(light: Color(red: 0.6627, green: 0.7137, blue: 0.7843), dark: Color(red: 0.2431, green: 0.3059, blue: 0.3882))
}

enum Space {
    static let s0: CGFloat = 0
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
    static let s8: CGFloat = 40
    static let s9: CGFloat = 48
    static let s10: CGFloat = 64
}

enum Radius {
    static let field: CGFloat = 8
    static let card: CGFloat = 10
    static let sheet: CGFloat = 16
    static let pill: CGFloat = 999
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

    static let hero = Metrics(size: 64, weight: 400, tracking: -0.02, leading: 1.02)
    static let screen = Metrics(size: 44, weight: 400, tracking: -0.02, leading: 1.06)
    static let section = Metrics(size: 34, weight: 400, tracking: -0.015, leading: 1.12)
    static let row = Metrics(size: 17, weight: 500, tracking: 0, leading: 1.3)
    static let body = Metrics(size: 15, weight: 400, tracking: 0, leading: 1.53)
    static let label = Metrics(size: 11, weight: 600, tracking: 0.14, leading: 1.4)
    static let labelCJK = Metrics(size: 11, weight: 600, tracking: 0.08, leading: 1.4)
    static let micro = Metrics(size: 10, weight: 500, tracking: 0.06, leading: 1.4)
}

enum Motion {
    /// The one curve. No springs, no overshoot, anywhere.
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.32, 0.08, 0.24, 1, duration: duration)
    }

    static let figureSettle: Double = 0.220
    static let figureStagger: Double = 0.018
    static let sheetPresent: Double = 0.280
    static let sheetDismiss: Double = 0.200
    static let stampSlide: Double = 0.180
    static let rowPrint: Double = 0.240
    static let rowFade: Double = 0.120
    static let verdictSwipe: Double = 0.260
    static let scrimFade: Double = 0.200
}

enum Layout {
    static let contentMax: CGFloat = 720
    static let gutter: CGFloat = 20
    static let hitTarget: CGFloat = 44
    static let rowPadY: CGFloat = 14
    static let hairline: CGFloat = 1

    /// One device pixel, not one point.
    static var hairlineWidth: CGFloat { 1 / max(UIScreen.main.scale, 1) }
}

enum Elevation {
    struct Layer { let opacity: Double; let radius: CGFloat; let y: CGFloat }
    static let sheet: [Layer] = [
        Layer(opacity: 0.04, radius: 1, y: 1),
        Layer(opacity: 0.16, radius: 16, y: 12)
    ]
}

/// Product constants the interface prints verbatim, kept beside the design
/// values so the two cannot disagree.
enum Rules {
    static let leakCeilingFen = 3000
    static let coolingFloorFen = 30000
    static let coolingDaysMin = 1
    static let coolingDaysMax = 14
    static let coolingFenPerDay = 10000
    static let reckoningWeekday = 0
    static let reckoningHour = 20
    static let reckoningMaxCards = 12
    static let deferralLimit = 3
    static let minJudgedForRegretRate = 30
}
