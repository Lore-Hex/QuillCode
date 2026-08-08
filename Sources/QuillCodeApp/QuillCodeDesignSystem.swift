import SwiftUI

public enum QuillCodeMetrics {
    public static let minimumHitTarget: CGFloat = 40
    public static let compactTextButtonMinWidth: CGFloat = 66
    public static let compactFormActionMinWidth: CGFloat = 52
    public static let compactControlRadius: CGFloat = 2
    public static let iconControlRadius: CGFloat = 2
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
    public static let sidebarVisibleRowRadius: CGFloat = 2
    public static let commandPaletteRowHorizontalPadding: CGFloat = 10
    public static let commandPaletteRowVerticalPadding: CGFloat = 7
    public static let commandPaletteRowRadius: CGFloat = 4
    public static let composerSurfaceRadius: CGFloat = 4
    public static let composerControlRadius: CGFloat = 2
    public static let messageBubbleRadius: CGFloat = 4
    public static let toolCardMinimumHeight: CGFloat = 74
    public static let compactToolCardMinimumHeight: CGFloat = 58
    public static let toolCardHeaderHeight: CGFloat = 44
    public static let toolCardRawDetailsMaxHeight: CGFloat = 240
    public static let toolCardRadius: CGFloat = 4
    public static let settingsCardRadius: CGFloat = 4
    public static let dialogRadius: CGFloat = 4
    public static let pressScale: CGFloat = 1
}

public enum QuillCodeCharterTheme {
    public static let page = Color(red: 0.039, green: 0.055, blue: 0.043)
    public static let card = Color(red: 0.051, green: 0.071, blue: 0.055)
    public static let raised = Color(red: 0.071, green: 0.094, blue: 0.075)
    public static let hover = Color(red: 0.094, green: 0.125, blue: 0.098)
    public static let line = Color(red: 0.125, green: 0.149, blue: 0.122)
    public static let lineStrong = Color(red: 0.227, green: 0.259, blue: 0.227)
    public static let ivory = Color(red: 0.929, green: 0.910, blue: 0.859)
    public static let body = Color(red: 0.675, green: 0.710, blue: 0.643)
    public static let muted = Color(red: 0.514, green: 0.561, blue: 0.502)
    public static let sage = Color(red: 0.663, green: 0.804, blue: 0.725)
    public static let sageBright = Color(red: 0.776, green: 0.886, blue: 0.827)
    public static let clay = Color(red: 0.812, green: 0.604, blue: 0.549)
    public static let gold = Color(red: 0.827, green: 0.718, blue: 0.475)
}

enum QuillCodePalette {
    // Charter: warm green-black planes, ivory text, sage interaction, and restrained semantic color.
    static let background = QuillCodeCharterTheme.page                    // #0a0e0b
    static let sidebar = QuillCodeCharterTheme.card                       // #0d120e
    static let panel = QuillCodeCharterTheme.card                         // #0d120e
    static let panel2 = QuillCodeCharterTheme.raised                      // #121813
    static let panel3 = QuillCodeCharterTheme.hover                       // #182019
    static let line = QuillCodeCharterTheme.line                          // #20261f
    static let lineStrong = QuillCodeCharterTheme.lineStrong              // #3a423a
    static let selection = panel3
    static let text = QuillCodeCharterTheme.ivory                         // #ede8db
    static let body = QuillCodeCharterTheme.body                          // #acb5a4
    static let muted = QuillCodeCharterTheme.muted                        // #838f80
    static let faint = Color(red: 0.349, green: 0.380, blue: 0.310)        // #59614f
    static let blue = QuillCodeCharterTheme.sage                          // #a9cdb9, sage accent
    static let userBubble = Color(red: 0.125, green: 0.188, blue: 0.153)   // sage-tinted message plane
    static let userBubbleBorder = Color(red: 0.337, green: 0.408, blue: 0.361) // #56685c
    static let green = QuillCodeCharterTheme.sageBright                   // #c6e2d3
    static let red = QuillCodeCharterTheme.clay                           // #cf9a8c
    static let yellow = QuillCodeCharterTheme.gold                        // #d3b779
    static let coral = red
    static let purple = Color(red: 0.651, green: 0.608, blue: 0.714)

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

/// Owns the hover state a `ButtonStyle` struct cannot hold. Charter controls brighten subtly on
/// hover and move down one pixel on press without spring or scale motion.
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
            .offset(y: !reduceMotion && configuration.isPressed ? 1 : 0)
            .quillCodePointingHandCursor()
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var brightness: Double {
        guard !reduceMotion else { return 0 }
        if configuration.isPressed { return -0.05 }
        return isHovering ? 0.04 : 0
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

struct QuillCodeTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 9)
            .frame(minHeight: 36)
            .foregroundStyle(QuillCodePalette.text)
            .background(QuillCodePalette.panel2)
            .overlay(
                RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                    .stroke(QuillCodePalette.lineStrong, lineWidth: 1)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
            )
    }
}

/// Hover-aware body for the shared Charter button treatments.
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
            .offset(y: !reduceMotion && configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.48)
            .quillCodePointingHandCursor()
            .onHover { isHovering = isEnabled && $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
            return QuillCodePalette.background
        case .secondary:
            return QuillCodePalette.text
        case .destructive:
            return QuillCodePalette.red
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return QuillCodePalette.selection.opacity(0.26) }
        switch tone {
        case .primary:
            return QuillCodePalette.text
        case .secondary:
            return isHovering ? QuillCodePalette.panel3 : .clear
        case .destructive:
            return QuillCodePalette.red.opacity(isHovering ? 0.22 : 0.14)
        }
    }

    private var strokeColor: Color {
        guard isEnabled else { return Color.white.opacity(0.06) }
        switch tone {
        case .primary:
            return QuillCodePalette.text
        case .secondary:
            return isHovering ? QuillCodePalette.text.opacity(0.45) : QuillCodePalette.lineStrong
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
                    .stroke(QuillCodePalette.lineStrong, lineWidth: 1)
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
                    .stroke(QuillCodePalette.line, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(tint.opacity(0.70))
                    .frame(width: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.settingsCardRadius, style: .continuous))
    }
}
