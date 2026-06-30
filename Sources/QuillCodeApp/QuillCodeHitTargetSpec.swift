import SwiftUI

struct QuillCodeHitTargetSpec {
    enum Shape {
        case rectangle
        case rounded(CGFloat)
        case capsule
    }

    var kind: QuillCodeNativeHitTargetKind
    var action: String { kind.action.rawValue }
    var allowsNestedInteractiveChildren: Bool { kind.allowsNestedInteractiveChildren }
    var requiresUnblockedInterior: Bool { kind.requiresUnblockedInterior }
    var requiresTactileFeedback: Bool { kind.requiresTactileFeedback }
    var allowsTextSelection: Bool { kind.allowsTextSelection }
    var minWidth: CGFloat?
    var maxWidth: CGFloat?
    var width: CGFloat?
    var minHeight: CGFloat
    var height: CGFloat?
    var alignment: Alignment
    var shape: Shape

    private init(
        kind: QuillCodeNativeHitTargetKind,
        minWidth: CGFloat?,
        maxWidth: CGFloat?,
        width: CGFloat?,
        minHeight: CGFloat,
        height: CGFloat?,
        alignment: Alignment,
        shape: Shape
    ) {
        self.kind = kind
        self.minWidth = minWidth.map(Self.clampedDimension) ?? QuillCodeMetrics.minimumHitTarget
        self.maxWidth = maxWidth
        self.width = width.map(Self.clampedDimension)
        self.minHeight = Self.clampedDimension(minHeight)
        self.height = height.map(Self.clampedDimension)
        self.alignment = alignment
        self.shape = shape
    }

    var requiredMinWidth: CGFloat {
        width ?? minWidth ?? QuillCodeMetrics.minimumHitTarget
    }

    var requiredMinHeight: CGFloat {
        height ?? minHeight
    }

    private static func clampedDimension(_ value: CGFloat) -> CGFloat {
        max(value, QuillCodeMetrics.minimumHitTarget)
    }

    static func icon(
        size: CGFloat = QuillCodeMetrics.minimumHitTarget,
        radius: CGFloat = QuillCodeMetrics.iconControlRadius
    ) -> Self {
        Self(
            kind: .icon,
            minWidth: size,
            maxWidth: nil,
            width: size,
            minHeight: QuillCodeMetrics.minimumHitTarget,
            height: size,
            alignment: .center,
            shape: .rounded(radius)
        )
    }

    static func textButton(
        minWidth: CGFloat = QuillCodeMetrics.compactTextButtonMinWidth,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> Self {
        Self(
            kind: .textButton,
            minWidth: minWidth,
            maxWidth: nil,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(radius)
        )
    }

    static func formAction(
        minWidth: CGFloat = QuillCodeMetrics.compactFormActionMinWidth,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> Self {
        Self(
            kind: .formAction,
            minWidth: minWidth,
            maxWidth: nil,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(QuillCodeMetrics.minimumHitTarget / 2)
        )
    }

    static func textEntry(
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> Self {
        Self(
            kind: .textEntry,
            minWidth: minWidth,
            maxWidth: nil,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(radius)
        )
    }

    static func segmentedControl(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> Self {
        Self(
            kind: .segmentedControl,
            minWidth: nil,
            maxWidth: .infinity,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(QuillCodeMetrics.compactControlRadius)
        )
    }

    static func adjustableControl(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> Self {
        Self(
            kind: .adjustableControl,
            minWidth: nil,
            maxWidth: .infinity,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(QuillCodeMetrics.compactControlRadius)
        )
    }

    static func link(
        minWidth: CGFloat? = QuillCodeMetrics.compactTextButtonMinWidth,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> Self {
        Self(
            kind: .link,
            minWidth: minWidth,
            maxWidth: nil,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(radius)
        )
    }

    static func switchRow(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .leading
    ) -> Self {
        Self(
            kind: .switchRow,
            minWidth: nil,
            maxWidth: .infinity,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rectangle
        )
    }

    static func ownedGesture(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .leading,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> Self {
        Self(
            kind: .ownedGesture,
            minWidth: nil,
            maxWidth: .infinity,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(radius)
        )
    }

    static func fullRow(
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .leading,
        radius: CGFloat = QuillCodeMetrics.compactControlRadius
    ) -> Self {
        Self(
            kind: .fullRow,
            minWidth: nil,
            maxWidth: .infinity,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .rounded(radius)
        )
    }

    static func capsule(
        minWidth: CGFloat? = nil,
        minHeight: CGFloat = QuillCodeMetrics.minimumHitTarget,
        alignment: Alignment = .center
    ) -> Self {
        Self(
            kind: .capsule,
            minWidth: minWidth,
            maxWidth: nil,
            width: nil,
            minHeight: minHeight,
            height: nil,
            alignment: alignment,
            shape: .capsule
        )
    }
}
