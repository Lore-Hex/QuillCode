import SwiftUI

extension View {
    func quillCodeInteractiveTarget(_ spec: QuillCodeHitTargetSpec) -> some View {
        modifier(QuillCodeHitTargetModifier(spec: spec))
    }
}

private struct QuillCodeHitTargetModifier: ViewModifier {
    var spec: QuillCodeHitTargetSpec

    func body(content: Content) -> some View {
        shaped(content)
    }

    @ViewBuilder
    private func shaped(_ content: Content) -> some View {
        switch spec.shape {
        case .rectangle:
            framed(content)
                .contentShape(Rectangle())
        case .rounded(let radius):
            framed(content)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            framed(content)
                .contentShape(Capsule())
        }
    }

    private func framed(_ content: Content) -> some View {
        content.frame(
            minWidth: requiredMinWidth,
            maxWidth: spec.maxWidth,
            minHeight: requiredMinHeight,
            alignment: spec.alignment
        )
        .frame(width: width, height: height, alignment: spec.alignment)
    }

    private var requiredMinWidth: CGFloat {
        max(spec.requiredMinWidth, QuillCodeMetrics.minimumHitTarget)
    }

    private var requiredMinHeight: CGFloat {
        max(spec.requiredMinHeight, QuillCodeMetrics.minimumHitTarget)
    }

    private var width: CGFloat? {
        spec.width.map { max($0, QuillCodeMetrics.minimumHitTarget) }
    }

    private var height: CGFloat? {
        spec.height.map { max($0, QuillCodeMetrics.minimumHitTarget) }
    }
}

struct QuillCodePlatformMenuItemTargetModifier: ViewModifier {
    var reason: String

    func body(content: Content) -> some View {
        _ = reason
        return content
    }
}
