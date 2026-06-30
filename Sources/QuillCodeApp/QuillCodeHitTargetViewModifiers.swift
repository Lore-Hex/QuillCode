import SwiftUI

extension View {
    fileprivate func quillCodeInteractiveTarget(_ spec: QuillCodeHitTargetSpec) -> some View {
        modifier(QuillCodeHitTargetModifier(spec: spec))
    }

    public func quillCodeTextButtonTarget(
        minWidth: CGFloat = QuillCodeMetrics.compactTextButtonMinWidth,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> some View {
        quillCodeInteractiveTarget(.textButton(
            minWidth: minWidth,
            minHeight: minHeight,
            alignment: alignment,
            radius: radius
        ))
    }

    public func quillCodeFormActionTarget(
        minWidth: CGFloat = QuillCodeMetrics.compactFormActionMinWidth,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> some View {
        quillCodeInteractiveTarget(.formAction(
            minWidth: minWidth,
            minHeight: minHeight,
            alignment: alignment
        ))
    }

    public func quillCodeTextEntryTarget(
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> some View {
        quillCodeInteractiveTarget(.textEntry(
            minWidth: minWidth,
            minHeight: minHeight,
            alignment: alignment,
            radius: radius
        ))
    }

    public func quillCodeSegmentedControlTarget(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> some View {
        quillCodeInteractiveTarget(.segmentedControl(
            minHeight: minHeight,
            alignment: alignment
        ))
    }

    public func quillCodeAdjustableControlTarget(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> some View {
        quillCodeInteractiveTarget(.adjustableControl(
            minHeight: minHeight,
            alignment: alignment
        ))
    }

    public func quillCodeLinkTarget(
        minWidth: CGFloat? = QuillCodeMetrics.compactTextButtonMinWidth,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> some View {
        quillCodeInteractiveTarget(.link(
            minWidth: minWidth,
            minHeight: minHeight,
            alignment: alignment,
            radius: radius
        ))
    }

    public func quillCodeSwitchRowTarget(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .leading
    ) -> some View {
        quillCodeInteractiveTarget(.switchRow(
            minHeight: minHeight,
            alignment: alignment
        ))
    }

    public func quillCodeOwnedGestureTarget(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .leading,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> some View {
        quillCodeInteractiveTarget(.ownedGesture(
            minHeight: minHeight,
            alignment: alignment,
            radius: radius
        ))
        .accessibilityAddTraits(.isButton)
    }

    public func quillCodeIconButtonTarget(
        size: CGFloat = QuillCodeMetrics.minimumHitTarget,
        radius: CGFloat = QuillCodeMetrics.iconControlRadius
    ) -> some View {
        quillCodeInteractiveTarget(.icon(size: size, radius: radius))
    }

    public func quillCodeFullRowButtonTarget(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .leading,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> some View {
        quillCodeInteractiveTarget(.fullRow(
            minHeight: minHeight,
            alignment: alignment,
            radius: radius
        ))
    }

    public func quillCodeCapsuleButtonTarget(
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> some View {
        quillCodeInteractiveTarget(.capsule(
            minWidth: minWidth,
            minHeight: minHeight,
            alignment: alignment
        ))
    }

    public func quillCodeDecorativeIconFrame(
        size: CGFloat = QuillCodeMetrics.minimumHitTarget
    ) -> some View {
        frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    public func quillCodePlatformMenuItemTarget(reason: String) -> some View {
        modifier(QuillCodePlatformMenuItemTargetModifier(reason: reason))
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

private struct QuillCodePlatformMenuItemTargetModifier: ViewModifier {
    var reason: String

    func body(content: Content) -> some View {
        _ = reason
        return content
    }
}
