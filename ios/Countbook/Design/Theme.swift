import SwiftUI

// The vocabulary the rest of the app is written in: a type role per figure and
// per label, one hairline, one card surface, one content column. Nothing here
// decides what a screen says — only how it is printed. Every value comes from
// Tokens.swift; the only bare numbers are the two Dynamic Type caps, which are
// ratios rather than sizes, and they say so where they sit.

// MARK: - Type roles

/// The roles of DESIGN.md §3.3. `mono` is the timestamp/countdown face; the
/// rest map one-to-one onto the emitted `TypeScale` metrics.
enum TextRole: Sendable {
    case hero, screen, section, row, body, label, micro, mono
}

extension TypeScale.Metrics {
    /// The generated `Metrics` keeps its weight mapping private and only vends a
    /// font already fixed at the token size. Dynamic Type needs the size and the
    /// weight apart, so the mapping is restated here rather than in every caller.
    var fontWeight: Font.Weight {
        switch weight {
        case ...300: return .light
        case 301...400: return .regular
        case 401...500: return .medium
        case 501...600: return .semibold
        default: return .bold
        }
    }
}

extension TextRole {
    /// `label` carries two trackings: 0.14em opens Latin small caps and closes
    /// up Chinese into a smear, so the CJK variant is a separate token.
    @MainActor var metrics: TypeScale.Metrics {
        switch self {
        case .hero: return TypeScale.hero
        case .screen: return TypeScale.screen
        case .section: return TypeScale.section
        case .row: return TypeScale.row
        case .body: return TypeScale.body
        case .label: return S.locale == .en ? TypeScale.label : TypeScale.labelCJK
        case .micro: return TypeScale.micro
        case .mono: return Theme.mono
        }
    }

    /// The ink a role wears unless a call site names another. R8 (DESIGN.md
    /// §2.4) is why `micro` is ink500 and not ink300: 10pt is far below the
    /// 19pt large-text threshold.
    var ink: Color {
        switch self {
        case .hero, .screen, .section: return Ink.ink900
        case .row, .body: return Ink.ink700
        case .label, .micro, .mono: return Ink.ink500
        }
    }

    /// The UIKit style each role scales against (DESIGN.md §3.4).
    var textStyle: UIFont.TextStyle {
        switch self {
        case .hero: return .largeTitle
        case .screen: return .title1
        case .section: return .title2
        case .row, .body: return .body
        case .label, .micro: return .caption2
        case .mono: return .caption1
        }
    }

    /// A hero that scales freely swallows the screen. DESIGN.md §3.4's caps run
    /// about 1.45× at section size and above and about 1.7× below it; kept as
    /// ratios so that no point size is typed outside the token file.
    @MainActor var maximumSize: CGFloat {
        metrics.size * (metrics.size >= TypeScale.section.size ? 1.45 : 1.7)
    }

    /// The rendered point size at a given Dynamic Type setting.
    @MainActor func size(at dynamicType: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicType.contentSizeCategory)
        let scaled = UIFontMetrics(forTextStyle: textStyle)
            .scaledValue(for: metrics.size, compatibleWith: traits)
        return min(scaled, maximumSize)
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

private struct TextStyleModifier: ViewModifier {
    let role: TextRole
    let mono: Bool
    let ink: Color?

    @Environment(\.dynamicTypeSize) private var dynamicType

    func body(content: Content) -> some View {
        let metrics = role.metrics
        let size = role.size(at: dynamicType)
        return content
            // Every figure in this app is tabular: a column of amounts must line
            // up, and a digit that changes must not shift the ones beside it.
            .font(.system(size: size,
                          weight: metrics.fontWeight,
                          design: mono ? .monospaced : .default)
                .monospacedDigit())
            .kerning(metrics.tracking * size)
            .lineSpacing(max(0, size * (metrics.leading - 1.2)))
            // Chinese has no case to change; only the Latin label is capitalised.
            .textCase(role == .label && S.locale == .en ? .uppercase : nil)
            .foregroundStyle(ink ?? role.ink)
    }
}

extension View {
    /// Sets size, weight, tracking, leading, tabular figures and ink for one
    /// type role. Colour is part of the role, so pass `ink:` to change it — a
    /// `.foregroundStyle` applied *after* this modifier is further from the text
    /// and will not win.
    func textStyle(_ role: TextRole, mono: Bool = false, ink: Color? = nil) -> some View {
        modifier(TextStyleModifier(role: role, mono: mono, ink: ink))
    }
}

// MARK: - Hairlines

/// One device pixel, never one point: a 1pt rule on a 3× screen is a bar.
struct Hairline: View {
    enum Weight: Sendable {
        /// Row separators, card borders, chart baselines.
        case regular
        /// Section dividers, the rule under a screen header, the day rule.
        case strong
        /// 破版 — an overspend's rule runs past the content column.
        case broken
    }

    var weight: Weight = .regular

    // `UIScreen.main.scale` is wrong on an external display and deprecated in a
    // multi-scene app; the environment carries the scale of the screen this view
    // is actually on.
    @Environment(\.displayScale) private var displayScale

    init(_ weight: Weight = .regular) { self.weight = weight }

    var body: some View {
        Rectangle()
            .fill(colour)
            .frame(height: Layout.hairline / max(displayScale, 1))
            // The overhang is real above the content column and clipped by the
            // safe area below it, which is the intended accident. It is a layout
            // state and is never animated.
            .padding(.horizontal, weight == .broken ? -Layout.gutter : 0)
            .accessibilityHidden(true)
    }

    private var colour: Color {
        switch weight {
        case .regular: return Ink.rule
        case .strong: return Ink.ruleStrong
        case .broken: return Ink.figOver
        }
    }
}

// MARK: - Surfaces

private struct CardSurface: ViewModifier {
    let compact: Bool
    let sunken: Bool

    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return content
            .padding(compact ? Space.s4 : Space.s5)
            .background(sunken ? Ink.surfaceSunken : Ink.surface, in: shape)
            // Depth is value and rule weight, never blur: a card has a hairline
            // and a surface change, and no shadow at any elevation.
            .overlay {
                shape.strokeBorder(sunken ? Color.clear : Ink.rule,
                                   lineWidth: Layout.hairline / max(displayScale, 1))
            }
    }
}

private struct SheetElevation: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // The one shadow in the system. In dark it is invisible on #121211, so
        // the sheet's separation is carried by a rule and the scrim instead.
        if colorScheme == .dark {
            content
                .shadow(color: .black.opacity(0.5), radius: Elevation.sheet[0].radius, y: Elevation.sheet[0].y)
                .overlay(alignment: .top) { Hairline(.strong) }
        } else {
            content
                .shadow(color: .black.opacity(Elevation.sheet[0].opacity),
                        radius: Elevation.sheet[0].radius, y: Elevation.sheet[0].y)
                .shadow(color: .black.opacity(Elevation.sheet[1].opacity),
                        radius: Elevation.sheet[1].radius, y: Elevation.sheet[1].y)
        }
    }
}

extension View {
    /// The card of DESIGN.md §5.2: surface, one hairline border, card radius,
    /// no shadow. `compact` is the inside-a-sheet padding; `sunken` is the
    /// keypad ground and the disabled commit bar, which carry no border.
    func cardSurface(compact: Bool = false, sunken: Bool = false) -> some View {
        modifier(CardSurface(compact: compact, sunken: sunken))
    }

    /// The only shadow in the product. It belongs to the capture sheet and to
    /// modals; a card, a row, the tab bar, a toast and a chart never call this.
    func sheetElevation() -> some View {
        modifier(SheetElevation())
    }

    /// One column of paper, centred, never two: above `contentMax` the page
    /// gains margin rather than a second column.
    func contentColumn() -> some View {
        self
            .padding(.horizontal, Layout.gutter)
            .frame(maxWidth: Layout.contentMax)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Small shared parts

/// Constants DESIGN.md fixes but the token file does not emit, composed from
/// tokens rather than typed, so the two cannot disagree.
enum Theme {
    /// §4.1 — the right-aligned amount column, present on every list in the app.
    /// It is fixed and never flexes.
    static let amountGutter: CGFloat = Space.s10 + Space.s7

    /// §5.6 — the height of a primary bar and of a flat action.
    static let barHeight: CGFloat = Space.s8 + Space.s3

    /// §3.3 gives `--t-mono-row` as 12/450/1.20. The token file emits no mono
    /// role, so it is composed from the nearest emitted metrics: label's size,
    /// body's regular weight and zero tracking, row's leading.
    @MainActor static let mono = TypeScale.Metrics(
        size: TypeScale.label.size,
        weight: TypeScale.body.weight,
        tracking: TypeScale.body.tracking,
        leading: TypeScale.row.leading
    )
}

/// A stated fact: a word on the left, its figure right-aligned in the amount
/// gutter. VoiceOver reads the pair as one element, not as two fragments.
struct LabelRow<Value: View>: View {
    private let label: String
    private let value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label).textStyle(.body)
            Spacer(minLength: Space.s3)
            value.frame(minWidth: Theme.amountGutter, alignment: .trailing)
        }
        .padding(.vertical, Layout.rowPadY)
        .frame(minHeight: Layout.hitTarget)
        .accessibilityElement(children: .combine)
    }
}

extension LabelRow where Value == AnyView {
    init(_ label: String, value: String) {
        self.init(label) { AnyView(Text(value).textStyle(.row, ink: Ink.ink900)) }
    }
}

// MARK: - The stamp

extension Intent {
    /// 必要 → 想要 → 冲动 is a value ramp, not a hue ramp (DESIGN.md §2.6): the
    /// stamp darkens as the intent gets harder to defend, and reads down a
    /// column at a glance without spending any of the three chromatic roles.
    var ink: Color {
        switch self {
        case .need: return Ink.ink500
        case .want: return Ink.ink700
        case .impulse: return Ink.ink900
        }
    }

    /// 冲 additionally sets heavier than 必 and 想 — the one case the page is
    /// darkest about, without ever turning red.
    var stampWeight: Font.Weight {
        self == .impulse ? .semibold : .medium
    }

    var stampKey: StringKey {
        switch self {
        case .need: return .todayStampNeed
        case .want: return .todayStampWant
        case .impulse: return .todayStampImpulse
        }
    }
}
