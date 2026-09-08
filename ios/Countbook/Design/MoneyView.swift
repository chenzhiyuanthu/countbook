import SwiftUI

/// The type role an amount is set in. Maps one-to-one onto `TextRole`, and is a
/// separate type so a call site cannot ask for an amount at label size.
enum MoneySize: Sendable {
    case hero, screen, section, row, body

    var textRole: TextRole {
        switch self {
        case .hero: return .hero
        case .screen: return .screen
        case .section: return .section
        case .row: return .row
        case .body: return .body
        }
    }

    /// R8 (DESIGN.md §2.4): ink300 needs a rendered size of at least 19pt, which
    /// is true at section size and above and false below it.
    var isLarge: Bool {
        switch self {
        case .hero, .screen, .section: return true
        case .row, .body: return false
        }
    }
}

/// The four figures that are allowed to leave the ink greys. There is no fifth,
/// and none of them means "negative" — sign is carried by U+2212 alone.
enum MoneyTone: Sendable {
    /// Over standard, or an allowance below zero.
    case over
    /// Held in a cooling period.
    case held
    /// Money not spent.
    case spared
    /// 后悔金额 — lead grey, the absence of a chromatic role rather than one more.
    case regret

    var ink: Color {
        switch self {
        case .over: return Ink.figOver
        case .held: return Ink.figHeld
        case .spared: return Ink.figSpared
        case .regret: return Ink.figRegret
        }
    }
}

/// DESIGN.md §3.6.1–2. These ratios are the composition itself rather than
/// values that belong in the token file, and this is the one file in the iOS
/// client where they may appear.
private enum Composition {
    /// The ¥ mark, relative to the figure size.
    static let mark: CGFloat = 0.44
    static let markTracking: CGFloat = 0.08
    /// The 分, relative to the figure size.
    static let fraction: CGFloat = 0.56
    /// The fraction's minimum box, in units of its own digit advance, so
    /// integer digits align down a column whether an amount ends .00 or .40.
    /// A minimum rather than a fixed size: the advance below is nominal, and a
    /// figure must overflow its box before it is allowed to lose a digit.
    static let fractionBox: CGFloat = 2.6
    /// SF Pro's tabular digit advance, in em.
    static let digitAdvance: CGFloat = 0.6
}

/// The three-part ¥ / 元 / 分 composition, and the only place in the app an
/// amount is typeset. Splitting a figure into parts is what lets the 分 set
/// smaller and lighter than the 元 — and it is also what would silently break
/// VoiceOver, so that is closed here rather than at each of thirty call sites.
struct MoneyView: View {
    let fen: Fen
    var size: MoneySize = .row
    var tone: MoneyTone?
    var currency: String = "CNY"
    /// §3.6.5 — the month-strip readout drops the 分 because it changes thirty
    /// times per drag and a jittering fraction is noise. Nowhere else.
    var showsFraction: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let part = parts(fen, currency: currency)
        let role = size.textRole
        let point = role.size(at: dynamicType)
        let weight = role.metrics.fontWeight
        let ink = tone?.ink ?? role.ink

        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // The sign belongs to the figure and takes its ink; the currency
            // mark is a unit and stays at ink300 whatever the figure means.
            (Text(part.sign).foregroundStyle(ink)
                + Text(part.symbol).foregroundStyle(Ink.ink300))
                .font(.system(size: point * Composition.mark, weight: weight).monospacedDigit())
                .kerning(point * Composition.mark * Composition.markTracking)

            Text(part.int)
                .font(.system(size: point, weight: weight).monospacedDigit())
                .foregroundStyle(ink)
                .settles(fen, reduced: reduceMotion)

            if showsFraction {
                // Baseline-aligned, never superscripted, in a fixed box.
                Text(verbatim: ".\(part.frac)")
                    .font(.system(size: point * Composition.fraction, weight: weight).monospacedDigit())
                    .foregroundStyle(fractionInk)
                    .settles(fen, reduced: reduceMotion)
                    // The box is a floor, not a ceiling. As a fixed width it
                    // truncated every row figure to "¥86…": SF Pro's digit
                    // advance runs wider than 0.6em at row size, and a
                    // hard-clipped frame ellipsises rather than overflowing.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: point * Composition.fraction
                           * Composition.fractionBox * Composition.digitAdvance,
                           alignment: .leading)
            }
        }
        .lineLimit(1)
        // The amount gutter is never truncated, never shrunk, never ellipsised.
        .fixedSize(horizontal: true, vertical: false)
        .animation(reduceMotion ? nil : Motion.ease(Motion.figureSettle), value: fen)
        // One number, not four fragments: the parts are a typographic device and
        // have nothing to say to a screen reader.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(format(fen, currency: currency))
    }

    /// R8 again, plus its suspension: a reader who has asked for high contrast
    /// has said legibility outranks hierarchy, so the 分 takes ink500 at every
    /// size rather than ink300 at the large ones.
    private var fractionInk: Color {
        if contrast == .increased { return Ink.ink500 }
        return size.isLarge ? Ink.ink300 : Ink.ink500
    }
}

private extension View {
    /// figureSettle (DESIGN.md §6.3/§6.4): only the digits that changed move.
    /// `.numericText` performs the per-digit crossfade natively; the 18ms stagger
    /// is native to it and is not separately configurable, which is an accepted
    /// divergence from the web and is not to be hand-rolled back.
    ///
    /// The `Double` here is an animation hint, not an amount — no money path
    /// passes through it.
    func settles(_ fen: Fen, reduced: Bool) -> some View {
        contentTransition(reduced ? .identity : .numericText(value: Double(fen)))
    }
}
