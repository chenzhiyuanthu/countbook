import SwiftUI

/// The shared parts every screen is printed from — the SwiftUI counterparts of
/// `web/src/ui/primitives.tsx`. Nothing here decides what a screen says; it
/// decides only how a card, a rule, a row, a button, a field and a sheet are
/// set. Colour, spacing, radius and duration come from `Tokens.swift`.
///
/// One deliberate omission: no primitive composes a money figure. DESIGN §3.6
/// gives that job to `MoneyText` and to nothing else, so every slot that shows
/// an amount here is a `@ViewBuilder` the caller fills.

// ── metrics the token file does not emit ─────────────────────────────

/// Two DESIGN.md constants `design/tokens.json` has no field for, expressed as
/// sums of tokens rather than as literals so they move if the scale moves.
enum ListMetrics {
    /// §4.1 `--gutter-amount`. The amount column is a column: the same width on
    /// every list in the app, never flexing, never truncating. 96 = 64 + 32.
    static let amountColumn: CGFloat = Space.s10 + Space.s7
    /// §5.6. The bar height for every full-width button. 52 = 40 + 12.
    static let barHeight: CGFloat = Space.s8 + Space.s3
    /// §5.9. Sheet width is min(100%, 480). 480 = 720 × 2/3.
    static let sheetWidth: CGFloat = Layout.contentMax / 3 * 2
    /// §4.6 `--breakout`. The 破版 overhang past both edges of the column.
    static let breakout: CGFloat = Space.s5
}

/// §8.2. The icon stroke, the one geometry constant in the icon spec that is
/// not a spacing step. Icons are drawn on a 24 grid with a 20 live area.
private let iconStroke: CGFloat = 1.5

/// The five ink roles a mark may take. Selection, sign and state are never
/// carried by colour (§2.1 R4, R5); this exists so the three chromatic roles
/// are named once and cannot be spelled by hand at a call site.
enum FigureTone: Sendable {
    case neutral, over, held, spared, regret

    var color: Color {
        switch self {
        case .neutral: return Ink.ink700
        case .over: return Ink.figOver
        case .held: return Ink.figHeld
        case .spared: return Ink.figSpared
        case .regret: return Ink.figRegret
        }
    }
}

// ── type ─────────────────────────────────────────────────────────────

/// §3.4. The ratios in the scale are fixed; the base scales with Dynamic Type,
/// capped per token so the layout survives `.accessibility5`. One ScaledMetric
/// against `.body` drives every token, which is what keeps the ratios fixed —
/// per-token text styles would drift apart from each other at large sizes.
private struct TypeStyle: ViewModifier {
    let base: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let leading: CGFloat
    let cap: CGFloat
    let mono: Bool

    @ScaledMetric(relativeTo: .body) private var ratio: CGFloat = 100

    func body(content: Content) -> some View {
        let size = min(base * ratio / 100, cap)
        return content
            .font(.system(size: size, weight: weight, design: mono ? .monospaced : .default)
                .monospacedDigit())
            .kerning(tracking * size)
            .lineSpacing(max(0, size * (leading - 1.2)))
    }
}

private extension View {
    func typeStyle(
        _ metrics: TypeScale.Metrics,
        weight: Font.Weight,
        cap: CGFloat,
        mono: Bool = false
    ) -> some View {
        modifier(TypeStyle(
            base: metrics.size, weight: weight, tracking: metrics.tracking,
            leading: metrics.leading, cap: cap, mono: mono
        ))
    }
}

/// §3.4's caps, as rendered points.
private enum Cap {
    static let row: CGFloat = 28
    static let body: CGFloat = 26
    static let label: CGFloat = 18
    static let micro: CGFloat = 16
    static let mono: CGFloat = 20
}

// ── hairlines ────────────────────────────────────────────────────────

/// One device pixel, not one point. `UIScreen.main.scale` is wrong on an
/// external display and deprecated under multiple scenes, so the scale comes
/// from the environment. Increased contrast restores a full point (§2.8).
private struct HairlineWidth: DynamicProperty {
    @Environment(\.displayScale) private var scale
    @Environment(\.colorSchemeContrast) private var contrast

    var value: CGFloat { contrast == .increased ? Layout.hairline : Layout.hairline / max(scale, 1) }
}

// ── motion ───────────────────────────────────────────────────────────

/// Reduced motion removes depictions, never mechanics: a hold still takes as
/// long, a cooling arc still updates. Only the tween goes (§6.6).
private func eased(_ duration: Double, reduced: Bool) -> Animation? {
    reduced ? nil : Motion.ease(duration)
}

// ── Card ─────────────────────────────────────────────────────────────

/// §5.2. Surface, a hairline border, the card radius, and no shadow ever. A
/// card must not contain another card.
struct Card<Content: View>: View {
    var compact: Bool = false
    var sunken: Bool = false
    /// Focused or active. The border swaps to the state-bearing rule colour and
    /// nothing else changes — no lift, no scale, no fill (§2.1 R5).
    var active: Bool = false
    @ViewBuilder var content: Content

    private var hairline = HairlineWidth()

    init(
        compact: Bool = false,
        sunken: Bool = false,
        active: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.compact = compact
        self.sunken = sunken
        self.active = active
        self.content = content()
    }

    var body: some View {
        content
            .padding(compact ? Space.s4 : Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sunken ? Ink.surfaceSunken : Ink.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                if !sunken {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        // ink-500 is the value --rule-active carries; the token
                        // file does not emit that role under its own name.
                        .strokeBorder(active ? Ink.ink500 : Ink.rule, lineWidth: hairline.value)
                }
            }
    }
}

// ── RuleView ─────────────────────────────────────────────────────────

/// §2.3 and §4.6. `strong` is a structural divider; `broken` is 破版 — an
/// overspend lets the rule run past both edges of the content column. It is a
/// layout state, present on first paint, and it is never animated.
struct RuleView: View {
    var strong: Bool = false
    var broken: Bool = false

    private var hairline = HairlineWidth()

    init(strong: Bool = false, broken: Bool = false) {
        self.strong = strong
        self.broken = broken
    }

    var body: some View {
        Rectangle()
            .fill(strong ? Ink.ruleStrong : Ink.rule)
            .frame(height: hairline.value)
            .padding(.horizontal, broken ? -ListMetrics.breakout : 0)
            .accessibilityHidden(true)
    }
}

// ── SectionHeader ────────────────────────────────────────────────────

/// §5.3. A label, an optional text action on the same baseline, 12 of air, and
/// the rule that opens the section.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(title)
                    .typeStyle(TypeScale.labelCJK, weight: .semibold, cap: Cap.label)
                    .foregroundStyle(Ink.ink500)
                Spacer(minLength: 0)
                trailing
            }
            RuleView(strong: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

// ── buttons ──────────────────────────────────────────────────────────

/// A press is a change of ground, over `rowFade`, linear. No scale, no ripple.
/// The token file emits no 90ms step, so the nearest one is used.
private struct BarPressStyle: ButtonStyle {
    let pressedGround: Color?
    let pressedOpacity: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? (pressedGround ?? .clear) : .clear)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.linear(duration: Motion.rowFade), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// §5.6, the primary bar. Ink ground, paper label, 52 high.
///
/// `holdMs` turns it into the commit hold: an unfilled ring that fills strictly
/// linearly and fires only on completion. An eased timer lies about how much
/// time is left, so the fill has no curve, and a release before the end drops
/// the arc to zero with no rewind — nothing is saved. Under reduced motion the
/// wait is unchanged and only its depiction becomes a countdown (§5.6, §9.7).
struct PrimaryButton: View {
    let title: String
    var holdMs: Int? = nil
    var disabled: Bool = false
    var accessibilityLabel: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: CGFloat = 0
    @State private var secondsLeft: Int = 0
    @State private var holding = false
    @State private var hold: Task<Void, Never>?

    init(
        _ title: String,
        holdMs: Int? = nil,
        disabled: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.holdMs = holdMs
        self.disabled = disabled
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    private var held: Bool { (holdMs ?? 0) > 0 }
    private var ground: Color { disabled ? Ink.surfaceSunken : Ink.accentInk }
    private var label: Color { disabled ? Ink.ink300 : Ink.accentOn }

    var body: some View {
        if held {
            bar
                .contentShape(Rectangle())
                .gesture(holdGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel ?? title)
                .accessibilityValue(holding ? String(secondsLeft) : "")
                .accessibilityAddTraits(disabled ? [] : .isButton)
                .accessibilityAction { begin() }
                .onDisappear(perform: cancel)
        } else {
            Button(action: action) { bar }
                .buttonStyle(BarPressStyle(pressedGround: nil, pressedOpacity: 0.86))
                .disabled(disabled)
                .accessibilityLabel(accessibilityLabel ?? title)
        }
    }

    private var bar: some View {
        Text(title)
            .typeStyle(TypeScale.body, weight: .semibold, cap: Cap.body)
            .foregroundStyle(label)
            .multilineTextAlignment(.center)
            // Room at the right end for the ring, which is centred 16 in.
            .padding(.horizontal, held ? Space.s4 * 2 + Space.s6 : Space.s4)
            .frame(maxWidth: .infinity, minHeight: ListMetrics.barHeight)
            .background(ground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .trailing) { ring }
            .opacity(holding ? 0.86 : 1)
    }

    @ViewBuilder
    private var ring: some View {
        if held && !disabled {
            Group {
                if reduceMotion {
                    Text(holding ? String(secondsLeft) : "")
                        .typeStyle(TypeScale.label, weight: .regular, cap: Cap.mono, mono: true)
                        .foregroundStyle(label)
                        .frame(width: Space.s6, height: Space.s6)
                } else {
                    ZStack {
                        Circle().strokeBorder(label.opacity(0.4), lineWidth: Layout.hairline)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(label, style: StrokeStyle(lineWidth: Layout.hairline, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .padding(Layout.hairline / 2)
                    }
                    .frame(width: Space.s6, height: Space.s6)
                }
            }
            .padding(.trailing, Space.s4)
            .accessibilityHidden(true)
        }
    }

    /// A zero-distance drag rather than a long press: the gesture must report
    /// the finger leaving the bar, which `LongPressGesture` does not.
    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !holding {
                    begin()
                } else if !bounds.contains(value.location) {
                    cancel()
                }
            }
            .onEnded { _ in cancel() }
    }

    /// The bar's own rectangle, in its local space; the drag reports locations
    /// outside it once the finger has moved away.
    private var bounds: CGRect {
        CGRect(x: 0, y: 0, width: .greatestFiniteMagnitude, height: ListMetrics.barHeight)
    }

    private func begin() {
        guard !disabled, hold == nil, let ms = holdMs, ms > 0 else { return }
        holding = true
        secondsLeft = Int((Double(ms) / 1000).rounded(.up))
        if !reduceMotion {
            withAnimation(.linear(duration: Double(ms) / 1000)) { progress = 1 }
        }
        hold = Task { @MainActor in
            let end = Date().addingTimeInterval(Double(ms) / 1000)
            while !Task.isCancelled {
                let left = end.timeIntervalSinceNow
                if left <= 0 { break }
                secondsLeft = max(1, Int(left.rounded(.up)))
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            hold = nil
            reset()
            action()
        }
    }

    private func cancel() {
        guard hold != nil || holding else { return }
        hold?.cancel()
        hold = nil
        reset()
    }

    private func reset() {
        holding = false
        // Instant, not a rewind: the arc reports elapsed time and there is none.
        withAnimation(.linear(duration: 0)) { progress = 0 }
    }
}

/// §5.6, the flat action. No ground, no border; the word carries it.
struct QuietButton: View {
    let title: String
    var fullWidth: Bool = false
    var disabled: Bool = false
    var accessibilityLabel: String? = nil
    let action: () -> Void

    init(
        _ title: String,
        fullWidth: Bool = false,
        disabled: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.fullWidth = fullWidth
        self.disabled = disabled
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(TypeScale.body, weight: .medium, cap: Cap.body)
                .foregroundStyle(disabled ? Ink.ink300 : Ink.ink900)
                .padding(.horizontal, Space.s4)
                .frame(
                    maxWidth: fullWidth ? .infinity : nil,
                    minHeight: fullWidth ? ListMetrics.barHeight : Layout.hitTarget
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken, pressedOpacity: 1))
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// §5.6 and §2.5. Destructive is never red — red is rationed to three uses and
/// a delete is not one of them. The weight of the border and the label is the
/// whole difference.
struct DangerButton: View {
    let title: String
    var fullWidth: Bool = true
    var disabled: Bool = false
    var accessibilityLabel: String? = nil
    let action: () -> Void

    private var hairline = HairlineWidth()

    init(
        _ title: String,
        fullWidth: Bool = true,
        disabled: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.fullWidth = fullWidth
        self.disabled = disabled
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(TypeScale.body, weight: .semibold, cap: Cap.body)
                .foregroundStyle(disabled ? Ink.ink300 : Ink.ink900)
                .padding(.horizontal, Space.s4)
                .frame(
                    maxWidth: fullWidth ? .infinity : nil,
                    minHeight: fullWidth ? ListMetrics.barHeight : Layout.hitTarget
                )
                .background(Ink.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(disabled ? Ink.rule : Ink.ink500, lineWidth: hairline.value)
                }
        }
        .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken, pressedOpacity: 1))
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

// ── SegmentedStamp ───────────────────────────────────────────────────

/// §5.7, the 记账印章. Selection is a 2pt rule sliding under the chosen word:
/// no fill, no colour, no capsule (§2.1 R5). It has no default selection, and
/// `nil` is a real state the container can hold — the commit bar stays disabled
/// until a stamp is chosen, which is the whole point of the control.
///
/// `onChange` fires on a repeat choice too, so a screen can read a second tap
/// on 想要 as an escalation to 冲动.
struct SegmentedStamp<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        /// Ink weight per §2.6: 必要 → 想要 → 冲动 is a value ramp, not a hue ramp.
        var id: Value { value }
    }

    let options: [Option]
    let selection: Value?
    let onChange: (Value) -> Void
    var accessibilityLabel: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var stamp
    private var hairline = HairlineWidth()

    init(
        options: [Option],
        selection: Value?,
        accessibilityLabel: String? = nil,
        onChange: @escaping (Value) -> Void
    ) {
        self.options = options
        self.selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        // Behind the segments, so the 2pt selection rule prints over it.
        .background(alignment: .bottom) {
            Rectangle().fill(Ink.rule).frame(height: hairline.value)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }

    private func segment(_ option: Option) -> some View {
        let chosen = option.value == selection
        return Button {
            withAnimation(eased(Motion.stampSlide, reduced: reduceMotion)) { onChange(option.value) }
        } label: {
            Text(option.label)
                .typeStyle(TypeScale.body, weight: chosen ? .semibold : .medium, cap: Cap.body)
                .foregroundStyle(chosen ? Ink.ink900 : Ink.ink500)
                // The frame keeps the width of the word, so the rule beneath is
                // exactly as wide as the label it belongs to.
                .frame(minHeight: Layout.hitTarget)
                .overlay(alignment: .bottom) {
                    if chosen {
                        Ink.ink900
                            .frame(height: Layout.hairline * 2)
                            .matchedGeometryEffect(id: "stamp.rule", in: stamp)
                    }
                }
                .frame(maxWidth: .infinity)
                // The hit area is the whole third, radius pill and invisible.
                .contentShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

// ── SheetContainer ───────────────────────────────────────────────────

/// §5.9. The scrim, the one shadow, the sheet radius on the top corners only,
/// and the safe-area inset as padding rather than margin so the last row of a
/// keypad sits flush to it.
///
/// It draws its own scrim, so present it as an overlay in a `ZStack`. Inside a
/// `.sheet`, add `.presentationBackground(.clear)` so this geometry is the one
/// that shows. There is no blur anywhere: no `Material`, no `backdrop-filter`
/// — that is the constraint that keeps both renderers identical (§2.7).
struct SheetContainer<Content: View>: View {
    var title: String? = nil
    var accessibilityLabel: String? = nil
    let onClose: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown = false
    @State private var drag: CGFloat = 0
    @State private var leaving = false

    private var hairline = HairlineWidth()

    init(
        title: String? = nil,
        accessibilityLabel: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Ink.scrim
                    .opacity(shown ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: requestClose)
                    .accessibilityHidden(true)

                sheet(bottomInset: geo.safeAreaInsets.bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .onAppear {
            // Linear for the veil, eased for the sheet (§6.3).
            withAnimation(.linear(duration: Motion.scrimFade)) { shown = true }
        }
    }

    private func sheet(bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { head(title) }
            content
        }
        .padding(.top, Space.s8)
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, Space.s5 + bottomInset)
        .frame(maxWidth: ListMetrics.sheetWidth)
        .background(Ink.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Radius.sheet,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Radius.sheet,
                style: .continuous
            )
        )
        // A black shadow on graphite is invisible; in dark the sheet is
        // separated by a rule and by the scrim instead (§4.5).
        .overlay(alignment: .top) {
            if scheme == .dark {
                Rectangle().fill(Ink.ruleStrong).frame(height: hairline.value)
            }
        }
        .shadow(
            color: .black.opacity(scheme == .dark ? 0.5 : Elevation.sheet[0].opacity),
            radius: Elevation.sheet[0].radius,
            y: Elevation.sheet[0].y
        )
        .shadow(
            color: .black.opacity(scheme == .dark ? 0 : Elevation.sheet[1].opacity),
            radius: Elevation.sheet[1].radius,
            y: Elevation.sheet[1].y
        )
        .frame(maxWidth: .infinity)
        .offset(y: shown && !leaving ? drag : Space.s6)
        .opacity(shown && !leaving ? 1 : 0)
        .gesture(dismissDrag)
    }

    private func head(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(title)
                .typeStyle(TypeScale.labelCJK, weight: .semibold, cap: Cap.label)
                .foregroundStyle(Ink.ink500)
            Spacer(minLength: 0)
            Button(action: requestClose) {
                StrokeIcon(glyph: .xmark)
                    .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
                    .foregroundStyle(Ink.ink700)
                    .frame(width: Space.s6, height: Space.s6)
                    .frame(width: Layout.hitTarget, height: Layout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(S.t(.commonClose))
            .padding(.trailing, -Space.s3)
            .padding(.top, -Space.s3)
        }
        .padding(.bottom, Space.s4)
    }

    /// 1:1 tracking down; dismissed past 88 of travel or 600pt/s of velocity.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: Space.s2)
            .onChanged { value in drag = max(0, value.translation.height) }
            .onEnded { value in
                let far = value.translation.height > Space.s10 + Space.s6
                let fast = value.velocity.height > 600
                if far || fast {
                    requestClose()
                } else {
                    withAnimation(eased(Motion.sheetDismiss, reduced: reduceMotion)) { drag = 0 }
                }
            }
    }

    private func requestClose() {
        guard !leaving else { return }
        leaving = true
        withAnimation(eased(Motion.sheetDismiss, reduced: reduceMotion)) { shown = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Motion.sheetDismiss * 1000)))
            onClose()
        }
    }
}

// ── LabelledField ────────────────────────────────────────────────────

/// A label over a sunken well with a bottom rule. The rule swaps to the
/// state-bearing colour while the cursor is in the field; nothing else moves.
struct LabelledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var mono: Bool = false
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var suffix: String? = nil
    var disabled: Bool = false
    var maxLength: Int? = nil

    @FocusState private var focused: Bool
    private var hairline = HairlineWidth()

    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        mono: Bool = false,
        secure: Bool = false,
        keyboard: UIKeyboardType = .default,
        suffix: String? = nil,
        disabled: Bool = false,
        maxLength: Int? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.mono = mono
        self.secure = secure
        self.keyboard = keyboard
        self.suffix = suffix
        self.disabled = disabled
        self.maxLength = maxLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .typeStyle(TypeScale.labelCJK, weight: .semibold, cap: Cap.label)
                .foregroundStyle(Ink.ink500)

            HStack(spacing: Space.s2) {
                input
                    .typeStyle(TypeScale.body, weight: .regular, cap: Cap.body, mono: mono)
                    .foregroundStyle(disabled ? Ink.ink300 : Ink.ink900)
                    .focused($focused)
                    .disabled(disabled)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let suffix {
                    Text(suffix)
                        .typeStyle(TypeScale.body, weight: .regular, cap: Cap.body)
                        .foregroundStyle(Ink.ink500)
                }
            }
            .padding(.horizontal, Space.s3)
            .frame(minHeight: Layout.hitTarget)
            .background(Ink.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? Ink.ink500 : Ink.rule)
                    .frame(height: hairline.value)
            }
        }
        .onChange(of: text) { _, next in
            guard let maxLength, next.count > maxLength else { return }
            text = String(next.prefix(maxLength))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var input: some View {
        let prompt = Text(placeholder).foregroundStyle(Ink.ink500)
        if secure {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt, axis: .horizontal)
        }
    }
}

// ── StepperField ─────────────────────────────────────────────────────

/// Minus, the value, plus. The two icons are the only ones here, and they are
/// drawn from the same 24-grid geometry as the web set — SF Symbols are
/// forbidden because they have no CSS equivalent (§8.1).
struct StepperField: View {
    let label: String
    @Binding var value: Int
    var step: Int = 1
    var min: Int? = nil
    var max: Int? = nil
    /// The printed form. A money stepper passes a formatter here rather than
    /// letting this view compose an amount.
    var format: ((Int) -> String)? = nil

    init(
        label: String,
        value: Binding<Int>,
        step: Int = 1,
        min: Int? = nil,
        max: Int? = nil,
        format: ((Int) -> String)? = nil
    ) {
        self.label = label
        self._value = value
        self.step = step
        self.min = min
        self.max = max
        self.format = format
    }

    private var lo: Int { min ?? Int.min }
    private var hi: Int { max ?? Int.max }
    private var shown: String { format?(value) ?? String(value) }

    var body: some View {
        HStack(spacing: Space.s2) {
            key(.minus, label: S.t(.commonDecrease), disabled: value <= lo) { set(value - step) }
            Text(shown)
                .typeStyle(TypeScale.row, weight: .medium, cap: Cap.row)
                .foregroundStyle(Ink.ink900)
                .frame(maxWidth: .infinity, alignment: .trailing)
            key(.plus, label: S.t(.commonIncrease), disabled: value >= hi) { set(value + step) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(shown)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            @unknown default: break
            }
        }
    }

    private func set(_ next: Int) {
        let bounded = Swift.min(hi, Swift.max(lo, next))
        guard bounded != value else { return }
        value = bounded
    }

    private func key(
        _ glyph: StrokeIcon.Glyph,
        label: String,
        disabled: Bool,
        run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            StrokeIcon(glyph: glyph)
                .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
                .foregroundStyle(disabled ? Ink.ink300 : Ink.ink700)
                .frame(width: Space.s6, height: Space.s6)
                .frame(width: Layout.hitTarget, height: Layout.hitTarget)
                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        }
        .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken, pressedOpacity: 1))
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

// ── EmptyStateView ───────────────────────────────────────────────────

/// §5.11. A sentence and, at most, one text link. No illustration, no icon, no
/// large glyph. Offset from the top of the content area rather than centred in
/// it, and set in the same rhythm as a populated section, so an empty state
/// does not leave a hole in the page.
struct EmptyStateView<Action: View>: View {
    let title: String
    var body_: String?
    @ViewBuilder var action: Action

    init(title: String, body: String? = nil, @ViewBuilder action: () -> Action) {
        self.title = title
        self.body_ = body
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .typeStyle(TypeScale.body, weight: .regular, cap: Cap.body)
                .foregroundStyle(Ink.ink700)
                .fixedSize(horizontal: false, vertical: true)
            if let body_ {
                Text(body_)
                    .typeStyle(TypeScale.body, weight: .regular, cap: Cap.body)
                    .foregroundStyle(Ink.ink500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action.padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.s9)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(title: String, body: String? = nil) {
        self.init(title: title, body: body) { EmptyView() }
    }
}

// ── ProgressRule ─────────────────────────────────────────────────────

/// §5.10. A 1px rule with its achieved portion overdrawn. No cap, no radius, no
/// track fill, no percentage badge — the percentage belongs to the sentence
/// above it, where it can be read.
struct ProgressRule: View {
    let fraction: Double
    var tone: FigureTone = .neutral
    var accessibilityLabel: String? = nil

    private var hairline = HairlineWidth()

    init(fraction: Double, tone: FigureTone = .neutral, accessibilityLabel: String? = nil) {
        self.fraction = fraction
        self.tone = tone
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        let done = clamp01(fraction)
        return Rectangle()
            .fill(Ink.rule)
            .frame(height: hairline.value)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().fill(tone.color).frame(width: geo.size.width * done)
                }
            }
            .accessibilityHidden(accessibilityLabel == nil)
            .accessibilityLabel(accessibilityLabel ?? "")
    }
}

// ── DepletingRing ────────────────────────────────────────────────────

/// §5.10, the 冷静期弧. `fraction` is what remains, and the ring runs no timer
/// of its own: the caller repaints it once a minute, which is the whole cadence.
///
/// It draws the track as well as the arc. A bare arc with no companion ring
/// reads as a stray mark once it is nearly depleted — which is exactly the
/// moment it matters most.
struct DepletingRing: View {
    let fraction: Double
    var size: CGFloat = Space.s4 + Space.s1 / 2
    var tone: FigureTone = .held
    var accessibilityLabel: String? = nil

    init(
        fraction: Double,
        size: CGFloat = Space.s4 + Space.s1 / 2,
        tone: FigureTone = .held,
        accessibilityLabel: String? = nil
    ) {
        self.fraction = fraction
        self.size = size
        self.tone = tone
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        let remaining = clamp01(fraction)
        return ZStack {
            Circle()
                .strokeBorder(Ink.rule, lineWidth: Layout.hairline)
            // Twelve o'clock start, depleting counter-clockwise: trimming the
            // tail and rotating a quarter turn back puts the start at the top
            // and sends the remainder the other way round.
            Circle()
                .trim(from: 1 - remaining, to: 1)
                .stroke(tone.color, style: StrokeStyle(lineWidth: Layout.hairline, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .padding(Layout.hairline / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}

// ── LedgerRow ────────────────────────────────────────────────────────

/// §5.4, the most-used component in the product. Time in mono, category, payee,
/// the intent stamp, and the amount in the fixed 96 gutter so a column of
/// figures reads as a column.
///
/// The amount is a slot rather than a `Fen`, because DESIGN §3.6 gives the
/// composition of a money figure to `MoneyText` and to nothing else. `spoken`
/// is the row's whole accessible name — one element per record, with 更正 and
/// 冲销 folded into it rather than left as a second thing to arrow past (§9.6).
struct LedgerRow<Amount: View>: View {
    let time: String
    let category: String
    let payee: String
    var intent: Intent? = nil
    /// A 冲销 parent: the amount is struck through, the reversal prints beneath.
    var struck: Bool = false
    /// The cooling arc takes the stamp slot while an entry is held (§5.4).
    var holdFraction: Double? = nil
    /// 更正 / 冲销 lines, printed under the row they correct; parent and child
    /// share one hairline, because the pair is one record.
    var subLines: [String] = []
    let spoken: String
    var onTap: (() -> Void)? = nil
    @ViewBuilder var amount: Amount

    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        time: String,
        category: String,
        payee: String,
        intent: Intent? = nil,
        struck: Bool = false,
        holdFraction: Double? = nil,
        subLines: [String] = [],
        spoken: String,
        onTap: (() -> Void)? = nil,
        @ViewBuilder amount: () -> Amount
    ) {
        self.time = time
        self.category = category
        self.payee = payee
        self.intent = intent
        self.struck = struck
        self.holdFraction = holdFraction
        self.subLines = subLines
        self.spoken = spoken
        self.onTap = onTap
        self.amount = amount()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onTap {
                Button(action: onTap) { line }
                    .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken, pressedOpacity: 1))
            } else {
                line
            }
            ForEach(Array(subLines.enumerated()), id: \.offset) { _, sub in
                Text(sub)
                    .typeStyle(TypeScale.label, weight: .regular, cap: Cap.mono, mono: true)
                    .foregroundStyle(Ink.ink500)
                    .padding(.leading, Space.s8 + Space.s3)
                    .padding(.bottom, Space.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            RuleView()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    /// At accessibility sizes the row reflows to two lines rather than
    /// truncating: the amount gutter is never shrunk and never ellipsised.
    private var stacked: Bool { typeSize >= .accessibility1 }

    @ViewBuilder
    private var line: some View {
        if stacked {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    categoryText
                    Spacer(minLength: Space.s2)
                    amountSlot
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    timeText
                    payeeText
                    stampSlot
                }
            }
            .padding(.vertical, Layout.rowPadY)
            .frame(minHeight: Space.s10, alignment: .leading)
            .contentShape(Rectangle())
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                timeText
                categoryText
                payeeText
                stampSlot
                amountSlot
            }
            .padding(.vertical, Layout.rowPadY)
            .frame(minHeight: Layout.hitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private var timeText: some View {
        // The scale has no mono token; §5.4 sets the row timestamp at the label
        // size with no tracking, which is what the web row renders too.
        Text(time)
            .typeStyle(TypeScale.label, weight: .regular, cap: Cap.mono, mono: true)
            .foregroundStyle(Ink.ink500)
            .frame(width: Space.s8, alignment: .leading)
    }

    private var categoryText: some View {
        Text(category)
            .typeStyle(TypeScale.body, weight: .regular, cap: Cap.body)
            .foregroundStyle(Ink.ink700)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var payeeText: some View {
        Text(payee)
            .typeStyle(TypeScale.body, weight: .regular, cap: Cap.body)
            .foregroundStyle(Ink.ink500)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stampSlot: some View {
        if let holdFraction {
            DepletingRing(fraction: holdFraction)
                .frame(width: Space.s4, alignment: .center)
        } else if let intent {
            Text(S.t(glyphKey(intent)))
                .typeStyle(TypeScale.label, weight: intent == .impulse ? .semibold : .medium, cap: Cap.mono)
                .foregroundStyle(stampInk(intent))
                .frame(width: Space.s4, alignment: .center)
        } else {
            Color.clear.frame(width: Space.s4, height: 0)
        }
    }

    private var amountSlot: some View {
        amount
            .strikethrough(struck, color: Ink.ink500)
            .frame(minWidth: ListMetrics.amountColumn, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// §2.6. 必要 → 想要 → 冲动 is a value ramp, not a hue ramp: it reads at a
    /// glance down a column and costs no chroma.
    private func stampInk(_ intent: Intent) -> Color {
        switch intent {
        case .need: return Ink.ink500
        case .want: return Ink.ink700
        case .impulse: return Ink.ink900
        }
    }

    private func glyphKey(_ intent: Intent) -> StringKey {
        switch intent {
        case .need: return .ledgerGlyphNeed
        case .want: return .ledgerGlyphWant
        case .impulse: return .ledgerGlyphImpulse
        }
    }
}

// ── icons ────────────────────────────────────────────────────────────

/// §8.2. Drawn from the same 24-grid `d` geometry as the web set, on the 0.5
/// grid so a 1.5 stroke lands on pixel boundaries. Two of the fourteen icons
/// appear in this file; the rest belong to the screens that use them.
private struct StrokeIcon: Shape {
    enum Glyph { case xmark, plus, minus }

    let glyph: Glyph

    func path(in rect: CGRect) -> Path {
        let unit = Swift.min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        switch glyph {
        case .xmark:
            path.move(to: point(6, 6)); path.addLine(to: point(18, 18))
            path.move(to: point(18, 6)); path.addLine(to: point(6, 18))
        case .plus:
            path.move(to: point(12, 5)); path.addLine(to: point(12, 19))
            path.move(to: point(5, 12)); path.addLine(to: point(19, 12))
        case .minus:
            path.move(to: point(5, 12)); path.addLine(to: point(19, 12))
        }
        return path
    }
}

// ── shared ───────────────────────────────────────────────────────────

private func clamp01(_ n: Double) -> Double {
    n.isFinite ? Swift.min(1, Swift.max(0, n)) : 0
}
