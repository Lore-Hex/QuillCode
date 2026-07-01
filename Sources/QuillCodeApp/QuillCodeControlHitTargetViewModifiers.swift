import SwiftUI

extension View {
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
