import SwiftUI

public enum QuillCodeMetrics {
    public static let minimumHitTarget: CGFloat = 44
    public static let compactTextButtonMinWidth: CGFloat = 72
    public static let compactFormActionMinWidth: CGFloat = 56
    public static let compactControlRadius: CGFloat = 9
    public static let iconControlRadius: CGFloat = 10
    public static let minimumTargetClearance: CGFloat = 8
    public static let controlClusterSpacing: CGFloat = 10
    public static let denseControlClusterSpacing: CGFloat = 8
    public static let topBarHeight: CGFloat = 44
    public static let topBarTokenBudgetMinWidth: CGFloat = 226
    public static let topBarTokenBudgetMaxWidth: CGFloat = 286
    public static let topBarTokenBudgetHorizontalPadding: CGFloat = 12
    public static let topBarTokenBudgetVerticalPadding: CGFloat = 8
    public static let sidebarWidth: CGFloat = 280
    public static let sidebarLeadingInset: CGFloat = 14
    public static let sidebarTrailingInset: CGFloat = 14
    public static let sidebarVerticalInset: CGFloat = 12
    public static let sidebarSectionSpacing: CGFloat = 10
    public static let composerSurfaceRadius: CGFloat = 12
    public static let composerControlRadius: CGFloat = 10
    public static let toolCardMinimumHeight: CGFloat = 74
    public static let compactToolCardMinimumHeight: CGFloat = 58
    public static let toolCardHeaderHeight: CGFloat = 44
    public static let toolCardRawDetailsMaxHeight: CGFloat = 240
    public static let toolCardRadius: CGFloat = 20
    public static let pressScale: CGFloat = 0.96
}

enum QuillCodePalette {
    static let background = Color(red: 0.03, green: 0.06, blue: 0.08)
    static let sidebar = Color(red: 0.07, green: 0.10, blue: 0.12)
    static let panel = Color(red: 0.10, green: 0.15, blue: 0.18)
    static let selection = Color.white.opacity(0.08)
    static let text = Color(red: 0.93, green: 0.97, blue: 0.98)
    static let muted = Color(red: 0.62, green: 0.69, blue: 0.72)
    static let blue = Color(red: 0.25, green: 0.72, blue: 0.91)
    static let green = Color(red: 0.32, green: 0.82, blue: 0.45)
    static let red = Color(red: 1.0, green: 0.36, blue: 0.32)
    static let yellow = Color(red: 0.97, green: 0.72, blue: 0.31)
    static let coral = Color(red: 0.82, green: 0.42, blue: 0.37)
    static let purple = Color(red: 0.58, green: 0.50, blue: 0.96)
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

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                minWidth: QuillCodeMetrics.minimumHitTarget,
                minHeight: QuillCodeMetrics.minimumHitTarget
            )
            .contentShape(Rectangle())
            .scaleEffect(!reduceMotion && configuration.isPressed ? QuillCodeMetrics.pressScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
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
