import Foundation

public struct QuillCodeNativeSurfaceTargetPolicy: Codable, Sendable, Hashable {
    public var family: QuillCodeInteractionSurfaceFamily
    public var requiredKinds: [QuillCodeNativeHitTargetKind]
    public var requiredActions: [QuillCodeNativeHitTargetAction]
    public var requiredFocusTargets: [QuillCodeNativeFocusTarget]
    public var allowedKinds: [QuillCodeNativeHitTargetKind]
    public var allowedActions: [QuillCodeNativeHitTargetAction]
    public var allowedFocusTargets: [QuillCodeNativeFocusTarget]

    public init(
        family: QuillCodeInteractionSurfaceFamily,
        requiredKinds: [QuillCodeNativeHitTargetKind],
        requiredActions: [QuillCodeNativeHitTargetAction] = [],
        requiredFocusTargets: [QuillCodeNativeFocusTarget] = [],
        allowedKinds: [QuillCodeNativeHitTargetKind]? = nil,
        allowedActions: [QuillCodeNativeHitTargetAction]? = nil,
        allowedFocusTargets: [QuillCodeNativeFocusTarget]? = nil
    ) {
        self.family = family
        self.requiredKinds = requiredKinds
        self.requiredActions = requiredActions
        self.requiredFocusTargets = requiredFocusTargets
        self.allowedKinds = allowedKinds ?? requiredKinds
        self.allowedActions = allowedActions ?? requiredActions
        self.allowedFocusTargets = allowedFocusTargets ?? requiredFocusTargets
    }

    public var dictionary: [String: Any] {
        [
            "family": family.rawValue,
            "requiredKinds": requiredKinds.map(\.rawValue),
            "requiredActions": requiredActions.map(\.rawValue),
            "requiredFocusTargets": requiredFocusTargets.map(\.rawValue),
            "allowedKinds": allowedKinds.map(\.rawValue),
            "allowedActions": allowedActions.map(\.rawValue),
            "allowedFocusTargets": allowedFocusTargets.map(\.rawValue)
        ]
    }
}
