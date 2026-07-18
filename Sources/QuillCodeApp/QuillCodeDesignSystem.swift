import SwiftUI

public enum QuillCodeMetrics {
    public static let minimumHitTarget: CGFloat = 40
    public static let compactTextButtonMinWidth: CGFloat = 66
    public static let compactFormActionMinWidth: CGFloat = 52
    public static let compactControlRadius: CGFloat = 7
    public static let iconControlRadius: CGFloat = 10
    public static let minimumTargetClearance: CGFloat = 8
    public static let controlClusterSpacing: CGFloat = 8
    public static let denseControlClusterSpacing: CGFloat = 6
    public static let topBarHorizontalPadding: CGFloat = 8
    public static let topBarHeight: CGFloat = 40
    public static let topBarNavigationLeadingPadding: CGFloat = 76
    public static let topBarTokenBudgetHorizontalPadding: CGFloat = 9
    public static let topBarTokenBudgetVerticalPadding: CGFloat = 3
    public static let sidebarWidth: CGFloat = 296
    public static let sidebarLeadingInset: CGFloat = 10
    public static let sidebarTrailingInset: CGFloat = 10
    public static let sidebarVerticalInset: CGFloat = 7
    public static let sidebarSectionSpacing: CGFloat = 5
    public static let sidebarControlSpacing: CGFloat = 3
    public static let sidebarInteractionRowHeight: CGFloat = 32
    public static let sidebarIconTargetSize: CGFloat = 32
    public static let sidebarVisibleRowHeight: CGFloat = 25
    public static let sidebarVisibleRowHorizontalPadding: CGFloat = 11
    public static let sidebarVisibleRowRadius: CGFloat = 6
    public static let commandPaletteRowHorizontalPadding: CGFloat = 10
    public static let commandPaletteRowVerticalPadding: CGFloat = 7
    public static let commandPaletteRowRadius: CGFloat = 9
    public static let composerSurfaceRadius: CGFloat = 12
    public static let composerControlRadius: CGFloat = 10
    public static let messageBubbleRadius: CGFloat = 12
    public static let toolCardMinimumHeight: CGFloat = 74
    public static let compactToolCardMinimumHeight: CGFloat = 58
    public static let toolCardHeaderHeight: CGFloat = 44
    public static let toolCardRawDetailsMaxHeight: CGFloat = 240
    public static let toolCardRadius: CGFloat = 12
    public static let settingsCardRadius: CGFloat = 12
    public static let dialogRadius: CGFloat = 10
    public static let pressScale: CGFloat = 0.96
}

enum QuillCodePalette {
    // Refined dark ramp (Codex/Fable): a cool near-black base with clearly STEPPED elevation — bg →
    // sidebar → panel → panel2 → panel3 — so the rail, content, and cards read as distinct planes
    // instead of one flat murk, with hairlines (line / lineStrong) that are actually visible. Cyan is
    // the interactive accent (CLI: cyan = selection/status/input), purple = agent, green/red =
    // additions/deletions. Mirrors the DOM surface :root tokens in E2E/harness/index.html — keep the two
    // in sync so the native macOS surface and the HTML harness stay pixel-comparable.
    static let background = Color(red: 0.059, green: 0.063, blue: 0.071)   // #0f1012 — deepest plane
    static let sidebar = Color(red: 0.078, green: 0.082, blue: 0.094)      // #141518 — rail
    static let panel = Color(red: 0.098, green: 0.106, blue: 0.122)        // #191b1f — main content
    static let panel2 = Color(red: 0.129, green: 0.141, blue: 0.161)       // #212429 — cards, inputs
    static let panel3 = Color(red: 0.165, green: 0.180, blue: 0.204)       // #2a2e34 — nested chips
    static let line = Color(red: 0.169, green: 0.184, blue: 0.212)         // #2b2f36 — hairline
    static let lineStrong = Color(red: 0.227, green: 0.247, blue: 0.278)   // #3a3f47 — emphasized border
    static let selection = Color.white.opacity(0.08)
    static let text = Color(red: 0.925, green: 0.933, blue: 0.941)         // #eceef0
    static let muted = Color(red: 0.604, green: 0.631, blue: 0.671)        // #9aa1ab
    static let faint = Color(red: 0.416, green: 0.439, blue: 0.471)        // #6a7078 — tertiary/disabled
    static let blue = Color(red: 0.271, green: 0.784, blue: 0.902)         // #45c8e6 (cyan accent)
    // Own-message bubble: a soft, muted teal (a quieter, grayer sibling of the accent) — NOT the old
    // blue→coral gradient, and not a barely-there tint. Reads as "mine" on the right without shouting.
    // Solid (not an opacity tint) so it renders identically over any backdrop, and kept just saturated
    // enough to carry the transcript's cyan accent.
    static let userBubble = Color(red: 0.227, green: 0.435, blue: 0.533)   // #3a6f88 (soft muted teal)
    static let userBubbleBorder = Color(red: 0.337, green: 0.569, blue: 0.659) // #5691a8
    static let green = Color(red: 0.275, green: 0.753, blue: 0.478)        // #46c07a
    static let red = Color(red: 0.937, green: 0.357, blue: 0.322)          // #ef5b52
    static let yellow = Color(red: 0.878, green: 0.667, blue: 0.302)       // #e0aa4d
    static let coral = Color(red: 0.820, green: 0.420, blue: 0.370)
    static let purple = Color(red: 0.769, green: 0.541, blue: 0.965)       // #c48af6 (agent)

    /// Confidential-mode ramp: the SAME stepped elevation as the neutral ramp, shifted to a deep
    /// violet cast so the mode is unmistakable at a glance — Chrome-incognito style, where the whole
    /// chrome changes, not just a banner. Mirrors the harness/DOM `[data-confidential="true"]` token
    /// overrides in E2E/harness/index.html — keep the two in sync.
    enum Confidential {
        static let background = Color(red: 0.071, green: 0.059, blue: 0.110)   // #12101c — deepest plane
        static let panel = Color(red: 0.098, green: 0.082, blue: 0.153)        // #191527 — main content
        static let panel2 = Color(red: 0.133, green: 0.110, blue: 0.200)       // #221c33 — cards, inputs
        static let panel3 = Color(red: 0.173, green: 0.141, blue: 0.251)       // #2c2440 — nested chips
        static let line = Color(red: 0.204, green: 0.165, blue: 0.302)         // #342a4d — hairline
        static let lineStrong = Color(red: 0.275, green: 0.227, blue: 0.400)   // #463a66 — emphasized
        static let userBubble = Color(red: 0.357, green: 0.290, blue: 0.561)   // #5b4a8f — violet "mine"
        static let userBubbleBorder = Color(red: 0.478, green: 0.396, blue: 0.722) // #7a65b8
        /// The banner band + hero-icon tint: the agent purple at surface strength.
        static let bandFill = QuillCodePalette.purple.opacity(0.14)
    }
}

/// True while the selected thread is a confidential chat, so the views that paint the workspace
/// planes (transcript, composer, banner, bubbles) can swap to the violet confidential ramp without
/// threading a flag through every initializer.
private struct QuillCodeConfidentialAppearanceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var quillCodeConfidentialAppearance: Bool {
        get { self[QuillCodeConfidentialAppearanceKey.self] }
        set { self[QuillCodeConfidentialAppearanceKey.self] = newValue }
    }
}

func quillCodeWithAnimation(_ animation: Animation, reduceMotion: Bool, _ updates: () -> Void) {
    if reduceMotion {
        updates()
    } else {
        withAnimation(animation, updates)
    }
}

public struct QuillCodePressableButtonStyle: ButtonStyle {
    private let enforcesMinimumHitTarget: Bool

    public init(enforcesMinimumHitTarget: Bool = true) {
        self.enforcesMinimumHitTarget = enforcesMinimumHitTarget
    }

    public func makeBody(configuration: Configuration) -> some View {
        QuillCodePressableButtonBody(
            configuration: configuration,
            enforcesMinimumHitTarget: enforcesMinimumHitTarget
        )
    }
}

/// Owns the hover state a `ButtonStyle` struct can't hold. Gives every pressable control real life:
/// a subtle brighten + lift on hover, a snappy spring depress with a press-in dim, and the
/// pointing-hand cursor — so a capsule reads as a button, not an inert label.
private struct QuillCodePressableButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let enforcesMinimumHitTarget: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .quillCodeOptionalPressableFrame(enforcesMinimumHitTarget: enforcesMinimumHitTarget)
            .contentShape(Rectangle())
            .brightness(brightness)
            .scaleEffect(scale)
            .quillCodePointingHandCursor()
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovering)
            .animation(
                reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }

    private var brightness: Double {
        guard !reduceMotion else { return 0 }
        if configuration.isPressed { return -0.05 }
        return isHovering ? 0.06 : 0
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        if configuration.isPressed { return QuillCodeMetrics.pressScale }
        return isHovering ? 1.015 : 1
    }
}

private extension View {
    /// The pointing-hand cursor on hover, so affordance-y controls signal clickability. macOS 15+
    /// only (SwiftUI `pointerStyle`); older systems keep the default cursor rather than reaching for
    /// AppKit's push/pop, which is easy to leak.
    @ViewBuilder
    func quillCodePointingHandCursor() -> some View {
        if #available(macOS 15.0, *) {
            self.pointerStyle(.link)
        } else {
            self
        }
    }
}

private extension View {
    @ViewBuilder
    func quillCodeOptionalPressableFrame(enforcesMinimumHitTarget: Bool) -> some View {
        if enforcesMinimumHitTarget {
            frame(
                minWidth: QuillCodeMetrics.minimumHitTarget,
                minHeight: QuillCodeMetrics.minimumHitTarget
            )
        } else {
            self
        }
    }
}

public struct QuillCodeActionButtonStyle: ButtonStyle {
    public enum Tone {
        case primary
        case secondary
        case destructive
    }

    private let tone: Tone
    private let minWidth: CGFloat
    private let minHeight: CGFloat
    private let radius: CGFloat
    private let alignment: Alignment

    public init(
        _ tone: Tone = .secondary,
        minWidth: CGFloat = QuillCodeMetrics.compactTextButtonMinWidth,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius,
        alignment: Alignment = .center
    ) {
        self.tone = tone
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.radius = radius
        self.alignment = alignment
    }

    public func makeBody(configuration: Configuration) -> some View {
        QuillCodeActionButtonBody(
            configuration: configuration,
            tone: tone,
            minWidth: minWidth,
            minHeight: minHeight,
            radius: radius,
            alignment: alignment
        )
    }
}

/// Hover-aware body for `QuillCodeActionButtonStyle`: raises the secondary/destructive tint and
/// lightens the stroke on hover, brightens on hover / dims on press, and springs the depress — the
/// life the `ButtonStyle` struct can't express without owning state.
private struct QuillCodeActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tone: QuillCodeActionButtonStyle.Tone
    let minWidth: CGFloat
    let minHeight: CGFloat
    let radius: CGFloat
    let alignment: Alignment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth, minHeight: minHeight, alignment: alignment)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .brightness(brightness)
            .scaleEffect(!reduceMotion && configuration.isPressed ? QuillCodeMetrics.pressScale : 1)
            .opacity(isEnabled ? 1 : 0.48)
            .quillCodePointingHandCursor()
            .onHover { isHovering = isEnabled && $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovering)
            .animation(
                reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }

    private var brightness: Double {
        guard !reduceMotion, isEnabled else { return 0 }
        if configuration.isPressed { return -0.05 }
        return isHovering ? 0.05 : 0
    }

    private var foregroundColor: Color {
        guard isEnabled else { return QuillCodePalette.muted }
        switch tone {
        case .primary:
            return .white
        case .secondary:
            return QuillCodePalette.blue
        case .destructive:
            return QuillCodePalette.red
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return QuillCodePalette.selection.opacity(0.26) }
        switch tone {
        case .primary:
            return QuillCodePalette.blue
        case .secondary:
            return QuillCodePalette.blue.opacity(isHovering ? 0.22 : 0.14)
        case .destructive:
            return QuillCodePalette.red.opacity(isHovering ? 0.22 : 0.14)
        }
    }

    private var strokeColor: Color {
        guard isEnabled else { return Color.white.opacity(0.06) }
        switch tone {
        case .primary:
            return Color.white.opacity(isHovering ? 0.28 : 0.18)
        case .secondary:
            return QuillCodePalette.blue.opacity(isHovering ? 0.40 : 0.24)
        case .destructive:
            return QuillCodePalette.red.opacity(isHovering ? 0.40 : 0.24)
        }
    }
}

extension View {
    func quillCodeSurface(
        fill: Color,
        radius: CGFloat,
        stroke: Color = QuillCodePalette.line,
        shadow: Bool
    ) -> some View {
        modifier(QuillCodeSurfaceModifier(
            fill: fill,
            radius: radius,
            stroke: stroke,
            shadow: shadow
        ))
    }

    func quillCodeImageOutline(radius: CGFloat) -> some View {
        modifier(QuillCodeImageOutlineModifier(radius: radius))
    }

    func quillCodeSettingsCard(tint: Color = QuillCodePalette.blue) -> some View {
        modifier(QuillCodeSettingsCardModifier(tint: tint))
    }
}

private struct QuillCodeSurfaceModifier: ViewModifier {
    var fill: Color
    var radius: CGFloat
    var stroke: Color
    var shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(
                color: shadow ? Color.black.opacity(0.28) : .clear,
                radius: shadow ? 10 : 0,
                x: 0,
                y: shadow ? 4 : 0
            )
    }
}

private struct QuillCodeImageOutlineModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct QuillCodeSettingsCardModifier: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: QuillCodeMetrics.settingsCardRadius, style: .continuous)
                    .fill(QuillCodePalette.panel.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: QuillCodeMetrics.settingsCardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: QuillCodeMetrics.settingsCardRadius, style: .continuous)
                    .fill(tint.opacity(0.70))
                    .frame(width: 2)
                    .padding(.vertical, 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.settingsCardRadius, style: .continuous))
    }
}
