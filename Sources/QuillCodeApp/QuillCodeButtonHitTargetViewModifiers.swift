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

    public func quillCodeSidebarRowChrome(
        background: Color = .clear,
        alignment: Alignment = .leading
    ) -> some View {
        modifier(QuillCodeSidebarRowChromeModifier(
            background: background,
            alignment: alignment
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

private struct QuillCodeSidebarRowChromeModifier: ViewModifier {
    var background: Color
    var alignment: Alignment

    func body(content: Content) -> some View {
        ZStack(alignment: alignment) {
            content
                .padding(.horizontal, QuillCodeMetrics.sidebarVisibleRowHorizontalPadding)
                .frame(
                    maxWidth: .infinity,
                    minHeight: QuillCodeMetrics.sidebarVisibleRowHeight,
                    alignment: alignment
                )
                .background(background)
                .clipShape(RoundedRectangle(
                    cornerRadius: QuillCodeMetrics.sidebarVisibleRowRadius,
                    style: .continuous
                ))
        }
        .frame(
            maxWidth: .infinity,
            minHeight: QuillCodeMetrics.minimumHitTarget,
            alignment: alignment
        )
        .contentShape(RoundedRectangle(
            cornerRadius: QuillCodeMetrics.sidebarVisibleRowRadius,
            style: .continuous
        ))
    }
}
