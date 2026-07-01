import Foundation

public struct QuillCodeNativeHitTargetContract: Codable, Sendable, Hashable {
    public var id: String
    public var family: QuillCodeInteractionSurfaceFamily
    public var surface: String
    public var collisionScope: String
    public var label: String
    public var kind: QuillCodeNativeHitTargetKind
    public var minWidth: Double?
    public var minHeight: Double
    public var action: QuillCodeNativeHitTargetAction
    public var allowsNestedInteractiveChildren: Bool
    public var requiresUnblockedInterior: Bool
    public var requiresTactileFeedback: Bool
    public var allowsTextSelection: Bool
    public var source: String
    public var focusTarget: QuillCodeNativeFocusTarget?
    public var testID: String?
    public var commandID: String?

    public init(
        id: String,
        family: QuillCodeInteractionSurfaceFamily,
        surface: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double?,
        minHeight: Double = Double(QuillCodeMetrics.minimumHitTarget),
        collisionScope: String? = nil,
        focusTarget: QuillCodeNativeFocusTarget? = nil,
        testID: String? = nil,
        commandID: String? = nil,
        source: String
    ) {
        self.id = id
        self.family = family
        self.surface = surface
        self.collisionScope = collisionScope
            ?? Self.defaultCollisionScope(family: family, surface: surface)
        self.label = label
        self.kind = kind
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.action = kind.action
        self.allowsNestedInteractiveChildren = kind.allowsNestedInteractiveChildren
        self.requiresUnblockedInterior = kind.requiresUnblockedInterior
        self.requiresTactileFeedback = kind.requiresTactileFeedback
        self.allowsTextSelection = kind.allowsTextSelection
        self.source = source
        self.focusTarget = focusTarget
        self.testID = testID
        self.commandID = commandID
    }

    public var dictionary: [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "family": family.rawValue,
            "surface": surface,
            "collisionScope": collisionScope,
            "label": label,
            "kind": kind.rawValue,
            "action": action.rawValue,
            "allowsNestedInteractiveChildren": allowsNestedInteractiveChildren,
            "allowsTextSelection": allowsTextSelection,
            "minHeight": minHeight,
            "requiresTactileFeedback": requiresTactileFeedback,
            "requiresUnblockedInterior": requiresUnblockedInterior,
            "source": source
        ]
        if let minWidth {
            value["minWidth"] = minWidth
        }
        if let focusTarget {
            value["focusTarget"] = focusTarget.rawValue
        }
        if let testID {
            value["testID"] = testID
        }
        if let commandID {
            value["commandID"] = commandID
        }
        return value
    }

    public var validationIssues: [String] {
        var issues: [String] = []
        appendRequiredTextIssues(to: &issues)
        appendGeometryIssues(to: &issues)
        appendPolicyIssues(to: &issues)
        appendStableSelectorIssues(to: &issues)
        return issues
    }

    private func appendRequiredTextIssues(to issues: inout [String]) {
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("hit target contract has an empty id")
        }
        if surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("\(id) has an empty surface label")
        }
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("\(id) has an empty accessible label")
        }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("\(id) has an empty source")
        }
        if collisionScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("\(id) has an empty collision scope")
        }
    }

    private func appendGeometryIssues(to issues: inout [String]) {
        if kind == .icon && minWidth == nil {
            issues.append("\(id) icon target should declare an explicit minimum width")
        }
        if minHeight < Double(QuillCodeMetrics.minimumHitTarget) {
            issues.append("\(id) minHeight \(minHeight) is below \(QuillCodeMetrics.minimumHitTarget)")
        }
        if let minWidth, minWidth < Double(QuillCodeMetrics.minimumHitTarget) {
            issues.append("\(id) minWidth \(minWidth) is below \(QuillCodeMetrics.minimumHitTarget)")
        }
    }

    private func appendPolicyIssues(to issues: inout [String]) {
        if allowsNestedInteractiveChildren {
            issues.append(
                "\(id) allows nested interactive children; split the parent target or make the children decorative"
            )
        }
        if requiresTactileFeedback != kind.requiresTactileFeedback {
            issues.append("\(id) tactile-feedback policy does not match \(kind.rawValue)")
        }
        if allowsTextSelection != kind.allowsTextSelection {
            issues.append("\(id) text-selection policy does not match \(kind.rawValue)")
        }
        if kind == .textEntry && family != .designSystem && focusTarget == nil {
            issues.append("\(id) text entry does not declare a focus target")
        }
    }

    private func appendStableSelectorIssues(to issues: inout [String]) {
        if let testID, testID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("\(id) has an empty test id")
        }
        if let commandID, commandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("\(id) has an empty command id")
        }
        if family != .designSystem,
           focusTarget == nil,
           testID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           commandID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append("\(id) does not declare a stable test id, command id, or focus target")
        }
    }

    private static func defaultCollisionScope(
        family: QuillCodeInteractionSurfaceFamily,
        surface: String
    ) -> String {
        let normalizedSurface = surface
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        guard !normalizedSurface.isEmpty else {
            return family.rawValue
        }
        return "\(family.rawValue):\(normalizedSurface)"
    }
}
