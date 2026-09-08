import SwiftUI

/// The shared parts every screen is printed from — the SwiftUI counterparts of
/// `web/src/ui/primitives.tsx`. Nothing here decides what a screen says; it
/// decides only how a card, a rule, a row, a button, a field and a sheet are
/// set. Colour, spacing, radius and duration come from `Tokens.swift`; the type
/// roles, the hairline, the card surface and the sheet's one shadow come from
/// `Theme.swift`, so a primitive and a screen cannot print the same thing two
/// different ways.
///
/// One deliberate omission: no primitive composes a money figure. DESIGN §3.6
/// gives that job to `MoneyView` and to nothing else, so every slot that shows
/// an amount here is a `@ViewBuilder` the caller fills.

// MARK: - Metrics neither the token file nor Theme emits

private enum SheetMetrics {
    /// §5.9 — the sheet is min(100%, 480) wide. 480 = 720 × ⅔.
    static let maxWidth: CGFloat = Layout.contentMax / 3 * 2
    /// §5.9 — dismissed past 88 of travel. 88 = 64 + 24.
    static let dismissTravel: CGFloat = Space.s10 + Space.s6
    /// §5.9 — …or past 600pt/s, which is a speed and so has no spacing step.
    static let dismissVelocity: CGFloat = 600
}

/// §8.2. The icon stroke and the live area: icons are drawn on a 24 grid with a
/// 20 live area, at stroke 1.5 with butt caps and mitre joins. The stroke is the
/// one number in the icon spec that is not a spacing step.
private let iconStroke: CGFloat = 1.5

/// §5.6 — the pressed primary bar composites its ground to 0.86 rather than
/// taking a second ink token, exactly as the web bar does.
private let pressedOpacity: Double = 0.86

/// §5.6 — the hold ring's unfilled track is the label colour at 0.4. It is the
/// only place in the product a colour is used at partial opacity.
private let ringTrackOpacity: Double = 0.4

// MARK: - Type

/// §5.6 and §5.7 set a few labels at a weight their type role does not carry: a
/// commit bar at 600, a flat action at 500, a chosen stamp at 600, the 冲 glyph
/// heavier than 必 and 想. Size, tracking, leading and the Dynamic Type cap all
/// still come from the role — the only thing restated here is the weight, which
/// is why this exists instead of a second scale.
private struct WeightedRole: ViewModifier {
    let role: TextRole
    let weight: Font.Weight
    let ink: Color
    var mono: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicType

    func body(content: Content) -> some View {
        let metrics = role.metrics
        let size = role.size(at: dynamicType)
        return content
            .font(.system(size: size, weight: weight, design: mono ? .monospaced : .default)
                .monospacedDigit())
            .kerning(metrics.tracking * size)
            .lineSpacing(max(0, size * (metrics.leading - 1.2)))
            .textCase(role == .label && S.locale == .en ? .uppercase : nil)
            .foregroundStyle(ink)
    }
}

private extension View {
    func typeRole(_ role: TextRole, weight: Font.Weight, ink: Color, mono: Bool = false) -> some View {
        modifier(WeightedRole(role: role, weight: weight, ink: ink, mono: mono))
    }
}

// MARK: - Motion

/// Reduced motion removes depictions, never mechanics (§6.6): a hold still takes
/// as long, a cooling arc still updates. Only the tween goes — a movement
/// collapses to the shortest fade the token file emits, and a rule that only
/// slides is given no animation at all.
private func eased(_ duration: Double, reduced: Bool) -> Animation? {
    reduced ? .linear(duration: Motion.rowFade) : Motion.ease(duration)
}

// MARK: - Card

/// §5.2. Surface, a hairline border, the card radius, and no shadow ever. A card
/// must not contain another card.
struct Card<Content: View>: View {
    var compact: Bool = false
    var sunken: Bool = false
    /// Focused or active. The border swaps to the state-bearing rule colour and
    /// nothing else changes — no lift, no scale, no fill (§2.1 R5).
    var active: Bool = false
    @ViewBuilder var content: Content

    @Environment(\.displayScale) private var displayScale

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(compact: compact, sunken: sunken)
            .overlay {
                if active {
                    // ink500 is the value --rule-active carries; the generated
                    // token file does not emit that role under its own name.
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Ink.ink500, lineWidth: Layout.hairline / max(displayScale, 1))
                }
            }
    }
}

// MARK: - RuleView

/// §2.3 and §4.6. `strong` is a structural divider; `broken` is 破版 — an
/// overspend lets the rule run past both edges of the content column. It is a
/// layout state, present on first paint, and it is never animated.
struct RuleView: View {
    var strong: Bool = false
    var broken: Bool = false

    init(strong: Bool = false, broken: Bool = false) {
        self.strong = strong
        self.broken = broken
    }

    var body: some View {
        Hairline(strong ? .strong : .regular)
            // The overhang is real above the content column and clipped by the
            // safe area below it, which is the intended accident.
            .padding(.horizontal, broken ? -Layout.gutter : 0)
    }
}

// MARK: - SectionHeader

/// §5.3 and §3.5. A label, at most one text action on the same baseline, 12 of
/// air, and the structural rule that opens the section.
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
                Text(title).textStyle(.label)
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

// MARK: - Buttons

/// A press is a change of ground or of composite, over `rowFade`, linear. No
/// scale, no ripple, no haptic — the keypad owns the only haptic in the app.
private struct BarPressStyle: ButtonStyle {
    var pressedGround: Color? = nil
    var pressedOpacity: Double = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? (pressedGround ?? .clear) : .clear)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.linear(duration: Motion.rowFade), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// §5.6, the primary bar: ink ground, paper label, 52 high, card radius.
///
/// `holdMs` turns it into the commit hold — pass `Rules.holdToSaveMs`. The ring
/// is an unfilled 1pt circle that fills strictly linearly and fires only on
/// completion: an eased timer lies about how much time is left. A release, or a
/// finger that slides off the bar, drops the arc to zero with no rewind and
/// nothing is saved. Under reduced motion the wait is unchanged and only its
/// depiction changes to a countdown, because the delay is the mechanic (§9.7).
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
    /// A hold that has completed must not restart under a finger that has not
    /// lifted yet, so the press is tracked apart from the timer.
    @State private var pressing = false
    @State private var barSize: CGSize = .zero

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
    private var labelInk: Color { disabled ? Ink.ink300 : Ink.accentOn }

    var body: some View {
        if held {
            bar
                .opacity(holding ? pressedOpacity : 1)
                .contentShape(Rectangle())
                .gesture(holdGesture, including: disabled ? .subviews : .all)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel ?? title)
                // VoiceOver cannot hold a finger down; activating the element
                // starts the same timer and commits when it elapses, so the
                // delay is kept rather than waived.
                .accessibilityValue(holding ? String(secondsLeft) : "")
                .accessibilityAddTraits(disabled ? [] : .isButton)
                .accessibilityAction { begin() }
                .onDisappear(perform: stop)
        } else {
            Button(action: action) { bar }
                .buttonStyle(BarPressStyle(pressedOpacity: pressedOpacity))
                .disabled(disabled)
                .accessibilityLabel(accessibilityLabel ?? title)
        }
    }

    private var bar: some View {
        Text(title)
            .typeRole(.body, weight: .semibold, ink: labelInk)
            .multilineTextAlignment(.center)
            .padding(.leading, Space.s4)
            // Room at the right end for the ring, which is centred 16 in.
            .padding(.trailing, held ? Space.s4 * 2 + Space.s6 : Space.s4)
            .frame(maxWidth: .infinity, minHeight: Theme.barHeight)
            .background(ground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .trailing) { ring }
            .background {
                // The gesture has to know when the finger has left the bar, and
                // only the layout knows how wide the bar came out.
                GeometryReader { geo in
                    Color.clear
                        .onAppear { barSize = geo.size }
                        .onChange(of: geo.size) { _, size in barSize = size }
                }
            }
    }

    @ViewBuilder
    private var ring: some View {
        if held && !disabled {
            Group {
                if reduceMotion {
                    Text(holding ? String(secondsLeft) : "")
                        .typeRole(.mono, weight: .regular, ink: labelInk, mono: true)
                        .frame(width: Space.s6, height: Space.s6)
                } else {
                    ZStack {
                        Circle()
                            .strokeBorder(labelInk.opacity(ringTrackOpacity), lineWidth: Layout.hairline)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(labelInk, style: StrokeStyle(lineWidth: Layout.hairline, lineCap: .butt))
                            // Twelve o'clock start, filling clockwise.
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

    /// A zero-distance drag rather than a `LongPressGesture`: the gesture must
    /// report the finger sliding off the bar, which a long press does not.
    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressing {
                    pressing = true
                    begin()
                } else if hold != nil, barSize != .zero,
                          !CGRect(origin: .zero, size: barSize).contains(value.location) {
                    stop()
                }
            }
            .onEnded { _ in
                pressing = false
                stop()
            }
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
                secondsLeft = Swift.max(1, Int(left.rounded(.up)))
                // The countdown is a second hand, so it is repainted ten times a
                // second and not once a frame.
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            hold = nil
            reset()
            action()
        }
    }

    private func stop() {
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

/// §5.6, the flat action (值 / 不值 / 记入账页 / 不买了). No ground, no border;
/// the word carries it, and a press is a change of ground only.
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
                .typeRole(.body, weight: .medium, ink: disabled ? Ink.ink300 : Ink.ink900)
                .padding(.horizontal, Space.s4)
                .frame(
                    maxWidth: fullWidth ? .infinity : nil,
                    minHeight: fullWidth ? Theme.barHeight : Layout.hitTarget
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken))
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// §5.6 and §2.5. Destructive is never red — red is rationed to three uses and a
/// delete is not one of them. A rule and a heavier label are the whole
/// difference between this and a flat action.
struct DangerButton: View {
    let title: String
    var fullWidth: Bool = true
    var disabled: Bool = false
    var accessibilityLabel: String? = nil
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

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
                .typeRole(.body, weight: .semibold, ink: disabled ? Ink.ink300 : Ink.ink900)
                .padding(.horizontal, Space.s4)
                .frame(
                    maxWidth: fullWidth ? .infinity : nil,
                    minHeight: fullWidth ? Theme.barHeight : Layout.hitTarget
                )
                .background(Ink.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(disabled ? Ink.rule : Ink.ink500,
                                      lineWidth: Layout.hairline / max(displayScale, 1))
                }
        }
        .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken))
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

// MARK: - SegmentedStamp

/// §5.7, the 记账印章. Selection is a 2pt rule sliding under the chosen word over
/// `stampSlide`: no fill, no colour, no capsule (§2.1 R5). The rule is exactly
/// as wide as the label it belongs to, which is why it is an overlay on the word
/// rather than a bar in the container.
///
/// There is no default selection, and `nil` is a real state the control can
/// hold: the commit bar stays disabled until a stamp is chosen, which is the
/// whole point of it. `onChange` fires on a repeat choice too, so a screen can
/// read a second tap on 想要 as an escalation to 冲动.
struct SegmentedStamp<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }

        init(value: Value, label: String) {
            self.value = value
            self.label = label
        }
    }

    let options: [Option]
    let selection: Value?
    var accessibilityLabel: String? = nil
    let onChange: (Value) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var stamp

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
        .background(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }

    private func segment(_ option: Option) -> some View {
        let chosen = option.value == selection
        return Button {
            // The selection is a slide and nothing else, so under reduced motion
            // it simply arrives: there is no fade to collapse it into.
            withAnimation(reduceMotion ? nil : Motion.ease(Motion.stampSlide)) {
                onChange(option.value)
            }
        } label: {
            Text(option.label)
                .typeRole(.body, weight: chosen ? .semibold : .medium,
                          ink: chosen ? Ink.ink900 : Ink.ink500)
                .frame(minHeight: Layout.hitTarget)
                .overlay(alignment: .bottom) {
                    if chosen {
                        Ink.ink900
                            .frame(height: Layout.hairline * 2)
                            .matchedGeometryEffect(id: "stamp.rule", in: stamp)
                    }
                }
                .frame(maxWidth: .infinity)
                // The hit area is the whole third; the pill radius is invisible
                // and exists only so a press has a sane shape (§5.7).
                .contentShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - SheetContainer

/// §5.9. The scrim, the one shadow, the sheet radius on the top corners only,
/// and the safe-area inset as padding rather than margin so a keypad's last row
/// sits flush to it.
///
/// It draws its own scrim, so present it as an overlay in a `ZStack`; inside a
/// `.sheet`, add `.presentationBackground(.clear)` so this geometry is the one
/// that shows. There is no blur anywhere — no `Material`, no `backdrop-filter` —
/// and that is the constraint that keeps both renderers identical (§2.7).
struct SheetContainer<Content: View>: View {
    var title: String? = nil
    var accessibilityLabel: String? = nil
    let onClose: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var veiled = false
    @State private var presented = false
    @State private var drag: CGFloat = 0
    @State private var leaving = false

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
                    .opacity(veiled ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: requestClose)
                    .accessibilityHidden(true)

                sheet(bottomInset: geo.safeAreaInsets.bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(accessibilityLabel ?? title ?? "")
        .onAppear {
            // A veil is not eased and a sheet is: linear for the scrim, the one
            // curve for the sheet (§6.3).
            withAnimation(.linear(duration: Motion.scrimFade)) { veiled = true }
            withAnimation(eased(Motion.sheetPresent, reduced: reduceMotion)) { presented = true }
        }
    }

    private func sheet(bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { head(title) }
            content
        }
        .padding(.top, Space.s8)
        .padding(.horizontal, Layout.gutter)
        // The inset is padding, not margin: the sheet's ground runs under it.
        .padding(.bottom, Space.s5 + bottomInset)
        .frame(maxWidth: SheetMetrics.maxWidth)
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
        .sheetElevation()
        .frame(maxWidth: .infinity)
        // Reduced motion keeps the fade and drops the translate (§6.6).
        .offset(y: (presented ? 0 : (reduceMotion ? 0 : Space.s6)) + drag)
        .opacity(presented ? 1 : 0)
        .gesture(dismissDrag)
    }

    private func head(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(title).textStyle(.label)
            Spacer(minLength: 0)
            // §5.9: a modal that is not the capture sheet gets a close control.
            // The capture sheet passes no title and so has none.
            Button(action: requestClose) {
                StrokeIcon(glyph: .xmark)
                    .stroke(style: StrokeStyle(lineWidth: iconStroke, lineCap: .butt, lineJoin: .miter))
                    .foregroundStyle(Ink.ink700)
                    .frame(width: Space.s5, height: Space.s5)
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

    /// 1:1 tracking down; dismissed past 88 of travel or 600pt/s of velocity,
    /// and returned with the sheet's own curve below either.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: Space.s2)
            .onChanged { value in drag = max(0, value.translation.height) }
            .onEnded { value in
                if value.translation.height > SheetMetrics.dismissTravel
                    || value.velocity.height > SheetMetrics.dismissVelocity {
                    requestClose()
                } else {
                    withAnimation(eased(Motion.sheetDismiss, reduced: reduceMotion)) { drag = 0 }
                }
            }
    }

    private func requestClose() {
        guard !leaving else { return }
        leaving = true
        withAnimation(.linear(duration: Motion.scrimFade)) { veiled = false }
        withAnimation(eased(Motion.sheetDismiss, reduced: reduceMotion)) {
            presented = false
            drag = 0
        }
        // The caller tears the sheet down; it waits out the exit first so the
        // dismissal is seen rather than cut.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Motion.sheetDismiss * 1000)))
            onClose()
        }
    }
}

// MARK: - LabelledField

/// A label over a sunken well with a bottom rule. The rule swaps to the
/// state-bearing colour while the cursor is in the field (§2.3); nothing else
/// moves — no fill, no lift, no ring.
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
    @Environment(\.displayScale) private var displayScale

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
            Text(label).textStyle(.label)

            HStack(spacing: Space.s2) {
                input
                    .textStyle(.body, mono: mono, ink: disabled ? Ink.ink300 : Ink.ink900)
                    .focused($focused)
                    .disabled(disabled)
                    .keyboardType(keyboard)
                    // A passphrase and a fingerprint are typed exactly; prose is
                    // not, so only the mono wells refuse the keyboard's help.
                    .textInputAutocapitalization(mono || secure ? .never : .sentences)
                    .autocorrectionDisabled(mono || secure)
                if let suffix {
                    Text(suffix).textStyle(.body, ink: Ink.ink500)
                }
            }
            .padding(.horizontal, Space.s3)
            .frame(minHeight: Layout.hitTarget)
            .background(Ink.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? Ink.ink500 : Ink.rule)
                    .frame(height: Layout.hairline / max(displayScale, 1))
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
        // R8: a placeholder is small text and takes ink500, never ink300.
        let prompt = Text(placeholder).foregroundStyle(Ink.ink500)
        if secure {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt, axis: .horizontal)
        }
    }
}

// MARK: - StepperField

/// Minus, the value, plus. The two icons are the only ones in this file and they
/// are drawn from the same 24-grid geometry as the web set — SF Symbols are
/// forbidden because they have no CSS equivalent (§8.1).
struct StepperField: View {
    let label: String
    @Binding var value: Int
    var step: Int = 1
    var min: Int? = nil
    var max: Int? = nil
    /// The printed form. A money stepper passes a formatter here rather than
    /// letting this view compose an amount (§3.6).
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
                .textStyle(.row, ink: Ink.ink900)
                .frame(maxWidth: .infinity, alignment: .trailing)
            key(.plus, label: S.t(.commonIncrease), disabled: value >= hi) { set(value + step) }
        }
        // One element with an adjustable action: a screen reader steps the value
        // rather than hunting for two 44-point squares.
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
                .frame(width: Space.s5, height: Space.s5)
                .frame(width: Layout.hitTarget, height: Layout.hitTarget)
                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        }
        .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken))
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

// MARK: - EmptyStateView

/// §5.11. A sentence, at most one further sentence, and at most one text link.
/// No illustration, no icon, no large glyph. It is offset from the top of the
/// content area rather than centred in it — a centred sentence reads as a
/// placeholder screen — and it is set in the same rhythm as a populated section,
/// so an empty state does not leave a hole in the page.
struct EmptyStateView<Action: View>: View {
    let title: String
    /// The derivation or the count beneath the title. Named with a trailing
    /// underscore because `body` is the view itself.
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
                .textStyle(.body, ink: Ink.ink700)
                .fixedSize(horizontal: false, vertical: true)
            if let body_ {
                Text(body_)
                    .textStyle(.body, ink: Ink.ink500)
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

// MARK: - ProgressRule

/// §5.10, the 心愿物 progress rule. A hairline with its achieved portion
/// overdrawn from the left. No cap, no radius, no track fill, no percentage
/// badge — the percentage belongs to the sentence above it, where it can be read
/// rather than estimated.
struct ProgressRule: View {
    let fraction: Double
    /// `nil` is the neutral mark, ink700. The four chromatic roles are the ones
    /// `MoneyView` names, because they are roles of the product and not of money.
    var tone: MoneyTone? = nil
    var accessibilityLabel: String? = nil

    @Environment(\.displayScale) private var displayScale

    init(fraction: Double, tone: MoneyTone? = nil, accessibilityLabel: String? = nil) {
        self.fraction = fraction
        self.tone = tone
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        let done = clamp01(fraction)
        return Rectangle()
            .fill(Ink.rule)
            .frame(height: Layout.hairline / max(displayScale, 1))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(tone?.ink ?? Ink.ink700)
                        .frame(width: geo.size.width * done)
                }
            }
            .accessibilityHidden(accessibilityLabel == nil)
            .accessibilityLabel(accessibilityLabel ?? "")
    }
}

// MARK: - DepletingRing

/// §5.10, the 冷静期弧. `fraction` is what remains; the ring runs no timer of its
/// own, because the caller repaints every visible arc once a minute on one
/// shared cadence, and that cadence is the whole animation.
///
/// It draws the track as well as the arc, which is this client's one departure
/// from the web ring: a bare arc with no companion circle reads as a stray mark
/// once it is nearly depleted, which is exactly the moment it matters most.
struct DepletingRing: View {
    let fraction: Double
    /// 18 in a ledger row's stamp slot, 32 on a 待购 row. 18 = 16 + 4/2.
    var size: CGFloat = Space.s4 + Space.s1 / 2
    var tone: MoneyTone? = .held
    var accessibilityLabel: String? = nil

    init(
        fraction: Double,
        size: CGFloat = Space.s4 + Space.s1 / 2,
        tone: MoneyTone? = .held,
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
            Circle().strokeBorder(Ink.rule, lineWidth: Layout.hairline)
            // Twelve o'clock start, depleting counter-clockwise: trimming the
            // tail and turning back a quarter puts the start at the top and
            // sends what is left the other way round.
            Circle()
                .trim(from: 1 - remaining, to: 1)
                .stroke(tone?.ink ?? Ink.ink700,
                        style: StrokeStyle(lineWidth: Layout.hairline, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .padding(Layout.hairline / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}

// MARK: - LedgerRow

/// §5.4, the most-used component in the product. Time in mono, category, payee,
/// the intent stamp, and the amount in the fixed 96 gutter so that a column of
/// figures reads as a column: the gutter never flexes, never shrinks and is
/// never ellipsised.
///
/// The amount is a slot rather than a `Fen` because §3.6 gives the composition
/// of a money figure to `MoneyView` and to nothing else. `spoken` is the row's
/// whole accessible name — one element per record, with 更正 and 冲销 folded into
/// it rather than left as further things to arrow past (§9.6).
struct LedgerRow<Amount: View>: View {
    let time: String
    let category: String
    let payee: String
    var intent: Intent? = nil
    /// A 冲销 parent: the amount is struck through and the reversal prints below.
    var struck: Bool = false
    /// The cooling arc takes the stamp slot while an entry is held (§5.4).
    var holdFraction: Double? = nil
    /// 更正 / 冲销 lines, printed under the row they correct. Parent and child
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
                    .buttonStyle(BarPressStyle(pressedGround: Ink.surfaceSunken))
            } else {
                line
            }
            ForEach(Array(subLines.enumerated()), id: \.offset) { _, sub in
                Text(sub)
                    .textStyle(.mono)
                    // Indented to the category column: a correction is filed
                    // under the line it corrects, not beside it.
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
    /// truncating (§5.4): the amount gutter is kept whole and the row grows.
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
        Text(time)
            .textStyle(.mono)
            .frame(width: Space.s8, alignment: .leading)
    }

    private var categoryText: some View {
        Text(category)
            .textStyle(.body)
            .lineLimit(1)
            // A category is at most five characters and is never truncated; the
            // note beside it is what gives way.
            .fixedSize(horizontal: true, vertical: false)
    }

    private var payeeText: some View {
        Text(payee)
            .textStyle(.body, ink: Ink.ink500)
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
            // 必 → 想 → 冲 is a value ramp, not a hue ramp (§2.6).
            Text(S.t(glyphKey(intent)))
                .typeRole(.mono, weight: intent.stampWeight, ink: intent.ink)
                .frame(width: Space.s4, alignment: .center)
        } else {
            Color.clear.frame(width: Space.s4, height: 0)
        }
    }

    private var amountSlot: some View {
        amount
            .strikethrough(struck, color: Ink.ink500)
            .frame(minWidth: Theme.amountGutter, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func glyphKey(_ intent: Intent) -> StringKey {
        switch intent {
        case .need: return .ledgerGlyphNeed
        case .want: return .ledgerGlyphWant
        case .impulse: return .ledgerGlyphImpulse
        }
    }
}

// MARK: - Icons

/// §8.2 and §8.3. Drawn from the same 24-grid `d` geometry as the web set, on
/// the 0.5 grid so a 1.5 stroke lands on pixel boundaries. Three of the fourteen
/// icons appear in this file; the rest belong to the screens that use them.
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

// MARK: - Shared

/// A fraction that arrives as a division by zero is 0, never a NaN that would
/// paint an arc of undefined length (§7.2).
private func clamp01(_ n: Double) -> Double {
    n.isFinite ? Swift.min(1, Swift.max(0, n)) : 0
}
