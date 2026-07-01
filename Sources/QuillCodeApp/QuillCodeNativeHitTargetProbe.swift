import Foundation

public enum QuillCodeNativeHitTargetProbeSelectorKind: String, Codable, Sendable, Hashable {
    case commandID = "command-id"
    case focusTarget = "focus-target"
    case testID = "test-id"
}

public struct QuillCodeNativeHitTargetProbePoint: Codable, Sendable, Hashable {
    public var name: String
    public var x: Double
    public var y: Double

    public init(name: String, x: Double, y: Double) {
        self.name = name
        self.x = x
        self.y = y
    }

    public var dictionary: [String: Any] {
        [
            "name": name,
            "x": x,
            "y": y
        ]
    }
}

public struct QuillCodeNativeHitTargetProbe: Codable, Sendable, Hashable {
    public var contractID: String
    public var family: QuillCodeInteractionSurfaceFamily
    public var collisionScope: String
    public var label: String
    public var kind: QuillCodeNativeHitTargetKind
    public var action: QuillCodeNativeHitTargetAction
    public var allowsNestedInteractiveChildren: Bool
    public var requiresUnblockedInterior: Bool
    public var requiresTactileFeedback: Bool
    public var allowsTextSelection: Bool
    public var selectorKind: QuillCodeNativeHitTargetProbeSelectorKind
    public var selector: String
    public var requiredMinWidth: Double
    public var requiredMinHeight: Double
    public var requiredPeerClearance: Double
    public var samplePoints: [QuillCodeNativeHitTargetProbePoint]

    public init(
        contractID: String,
        family: QuillCodeInteractionSurfaceFamily,
        collisionScope: String = "",
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        action: QuillCodeNativeHitTargetAction,
        allowsNestedInteractiveChildren: Bool,
        requiresUnblockedInterior: Bool,
        requiresTactileFeedback: Bool,
        allowsTextSelection: Bool,
        selectorKind: QuillCodeNativeHitTargetProbeSelectorKind,
        selector: String,
        requiredMinWidth: Double,
        requiredMinHeight: Double,
        requiredPeerClearance: Double = Double(QuillCodeMetrics.minimumTargetClearance),
        samplePoints: [QuillCodeNativeHitTargetProbePoint]
    ) {
        self.contractID = contractID
        self.family = family
        self.collisionScope = collisionScope
        self.label = label
        self.kind = kind
        self.action = action
        self.allowsNestedInteractiveChildren = allowsNestedInteractiveChildren
        self.requiresUnblockedInterior = requiresUnblockedInterior
        self.requiresTactileFeedback = requiresTactileFeedback
        self.allowsTextSelection = allowsTextSelection
        self.selectorKind = selectorKind
        self.selector = selector
        self.requiredMinWidth = requiredMinWidth
        self.requiredMinHeight = requiredMinHeight
        self.requiredPeerClearance = requiredPeerClearance
        self.samplePoints = samplePoints
    }

    public var dictionary: [String: Any] {
        [
            "contractID": contractID,
            "family": family.rawValue,
            "collisionScope": collisionScope,
            "label": label,
            "kind": kind.rawValue,
            "action": action.rawValue,
            "allowsNestedInteractiveChildren": allowsNestedInteractiveChildren,
            "allowsTextSelection": allowsTextSelection,
            "requiresUnblockedInterior": requiresUnblockedInterior,
            "requiresTactileFeedback": requiresTactileFeedback,
            "selectorKind": selectorKind.rawValue,
            "selector": selector,
            "requiredMinWidth": requiredMinWidth,
            "requiredMinHeight": requiredMinHeight,
            "requiredPeerClearance": requiredPeerClearance,
            "samplePoints": samplePoints.map(\.dictionary)
        ]
    }
}
