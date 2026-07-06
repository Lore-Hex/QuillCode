import SwiftUI

public enum QuillCodeMetrics {
    public static let minimumHitTarget: CGFloat = 40
    public static let compactTextButtonMinWidth: CGFloat = 66
    public static let compactFormActionMinWidth: CGFloat = 52
    public static let compactControlRadius: CGFloat = 9
    public static let iconControlRadius: CGFloat = 10
    public static let minimumTargetClearance: CGFloat = 8
    public static let controlClusterSpacing: CGFloat = 8
    public static let denseControlClusterSpacing: CGFloat = 6
    public static let topBarHorizontalPadding: CGFloat = 8
    public static let topBarHeight: CGFloat = 40
    public static let topBarNavigationLeadingPadding: CGFloat = 76
    public static let topBarTokenBudgetMinWidth: CGFloat = 360
    public static let topBarTokenBudgetMaxWidth: CGFloat = 480
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
    public static let composerSurfaceRadius: CGFloat = 12
    public static let composerControlRadius: CGFloat = 10
    public static let toolCardMinimumHeight: CGFloat = 74
    public static let compactToolCardMinimumHeight: CGFloat = 58
    public static let toolCardHeaderHeight: CGFloat = 44
    public static let toolCardRawDetailsMaxHeight: CGFloat = 240
    public static let toolCardRadius: CGFloat = 20
    public static let settingsCardRadius: CGFloat = 12
    public static let dialogRadius: CGFloat = 16
    public static let pressScale: CGFloat = 0.96
}

enum QuillCodePalette {
    // Codex palette — ChatGPT-dark neutral grays (not near-black) with a cyan interactive accent, the
    // way Codex itself uses color (CLI: cyan = selection/status/input, magenta = agent, green/red =
    // additions/deletions). Mirrors the DOM surface :root tokens in E2E/harness/index.html.
    static let background = Color(red: 0.090, green: 0.090, blue: 0.090)   // #171717
    static let sidebar = Color(red: 0.110, green: 0.110, blue: 0.110)      // #1c1c1c
    static let panel = Color(red: 0.129, green: 0.129, blue: 0.129)        // #212121
    static let selection = Color.white.opacity(0.08)
    static let text = Color(red: 0.925, green: 0.925, blue: 0.925)         // #ececec
    static let muted = Color(red: 0.608, green: 0.608, blue: 0.608)        // #9b9b9b
    static let blue = Color(red: 0.239, green: 0.788, blue: 0.902)         // #3dc9e6 (Codex cyan)
    static let green = Color(red: 0.247, green: 0.725, blue: 0.420)        // #3fb96b
    static let red = Color(red: 0.941, green: 0.341, blue: 0.298)          // #f0574c
    static let yellow = Color(red: 0.851, green: 0.643, blue: 0.255)       // #d9a441
    static let coral = Color(red: 0.820, green: 0.420, blue: 0.370)
    static let purple = Color(red: 0.753, green: 0.486, blue: 0.961)       // #c07cf5 (agent/Codex)
}

func quillCodeWithAnimation(_ animation: Animation, reduceMotion: Bool, _ updates: () -> Void) {
    if reduceMotion {
        updates()
    } else {
        withAnimation(animation, updates)
    }
}

public struct QuillCodePressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let enforcesMinimumHitTarget: Bool

    public init(enforcesMinimumHitTarget: Bool = true) {
        self.enforcesMinimumHitTarget = enforcesMinimumHitTarget
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .quillCodeOptionalPressableFrame(enforcesMinimumHitTarget: enforcesMinimumHitTarget)
            .contentShape(Rectangle())
            .scaleEffect(!reduceMotion && configuration.isPressed ? QuillCodeMetrics.pressScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

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
            .scaleEffect(!reduceMotion && configuration.isPressed ? QuillCodeMetrics.pressScale : 1)
            .opacity(isEnabled ? 1 : 0.48)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
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
            return QuillCodePalette.blue.opacity(0.14)
        case .destructive:
            return QuillCodePalette.red.opacity(0.14)
        }
    }

    private var strokeColor: Color {
        guard isEnabled else { return Color.white.opacity(0.06) }
        switch tone {
        case .primary:
            return Color.white.opacity(0.18)
        case .secondary:
            return QuillCodePalette.blue.opacity(0.24)
        case .destructive:
            return QuillCodePalette.red.opacity(0.24)
        }
    }
}

extension View {
    func quillCodeSurface(
        fill: Color,
        radius: CGFloat,
        stroke: Color = Color.white.opacity(0.08),
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
                color: shadow ? Color.black.opacity(0.18) : .clear,
                radius: shadow ? 18 : 0,
                x: 0,
                y: shadow ? 10 : 0
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
