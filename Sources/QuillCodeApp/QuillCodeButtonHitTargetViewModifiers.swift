import SwiftUI

extension View {
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
}
