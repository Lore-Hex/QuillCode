import Foundation

public enum QuillCodeNativeHitTargetKind: String, Codable, Sendable, Hashable, CaseIterable {
    case icon
    case textButton
    case formAction
    case link
    case textEntry
    case segmentedControl
    case adjustableControl
    case switchRow
    case ownedGesture
    case fullRow
    case capsule
}
public enum QuillCodeNativeHitTargetAction: String, Codable, Sendable, Hashable, CaseIterable {
    case adjust
    case link
    case ownedGesture = "owned-gesture"
    case press
    case textInput = "text-input"
}

public enum QuillCodeNativeFocusTarget: String, Codable, Sendable, Hashable, CaseIterable {
    case browserAddress = "browser.address"
    case browserComment = "browser.comment"
    case commandPaletteSearch = "command-palette.search"
    case composerMessage = "composer.message"
    case modelPickerSearch = "model-picker.search"
    case reviewBody = "review.body"
    case reviewThreadReply = "review.thread-reply"
    case searchChats = "search.chats"
    case settingsTrustedRouterBaseURL = "settings.trustedrouter-base-url"
    case terminalCommand = "terminal.command"
}

extension QuillCodeNativeHitTargetKind {
    public var renderedKind: String {
        switch self {
        case .icon:
            return "icon"
        case .textButton:
            return "text"
        case .formAction:
            return "form-action"
        case .link:
            return "link"
        case .textEntry:
            return "text-entry"
        case .segmentedControl:
            return "segmented"
        case .adjustableControl:
            return "adjustable"
        case .switchRow:
            return "switch-row"
        case .ownedGesture:
            return "owned"
        case .fullRow:
            return "row"
        case .capsule:
            return "capsule"
        }
    }

    public var renderedClassName: String {
        "hit-target-\(renderedKind)"
    }

    var action: QuillCodeNativeHitTargetAction {
        switch self {
        case .textEntry:
            return .textInput
        case .adjustableControl:
            return .adjust
        case .link:
            return .link
        case .ownedGesture:
            return .ownedGesture
        case .icon, .textButton, .formAction, .segmentedControl, .switchRow, .fullRow, .capsule:
            return .press
        }
    }

    var allowsNestedInteractiveChildren: Bool { false }

    var requiresUnblockedInterior: Bool { true }

    var requiresTactileFeedback: Bool {
        self != .textEntry
    }

    var allowsTextSelection: Bool {
        self == .textEntry
    }
}

public enum QuillCodeInteractionSurfaceFamily: String, Codable, Sendable, Hashable, CaseIterable {
    case designSystem = "design-system"
    case workspaceChrome = "workspace-chrome"
    case sidebar
    case sidebarThreadList = "sidebar-thread-list"
    case topBar = "top-bar"
    case composer
    case transcript
    case toolCard = "tool-card"
    case contextBanner = "context-banner"
    case commandPalette = "command-palette"
    case search
    case settings
    case modelPicker = "model-picker"
    case review
    case secondaryPane = "secondary-pane"
    case terminal
    case browser
    case extensions
    case memories
    case automations
    case menuBar = "menu-bar"
}

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
        if kind == .icon && minWidth == nil {
            issues.append("\(id) icon target should declare an explicit minimum width")
        }
        if minHeight < Double(QuillCodeMetrics.minimumHitTarget) {
            issues.append("\(id) minHeight \(minHeight) is below \(QuillCodeMetrics.minimumHitTarget)")
        }
        if let minWidth, minWidth < Double(QuillCodeMetrics.minimumHitTarget) {
            issues.append("\(id) minWidth \(minWidth) is below \(QuillCodeMetrics.minimumHitTarget)")
        }
        if allowsNestedInteractiveChildren {
            issues.append("\(id) allows nested interactive children; split the parent target or make the children decorative")
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
        return issues
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

public struct QuillCodeNativeHitTargetAuditReport: Codable, Sendable, Hashable {
    public var minimumHitTarget: Double
    public var minimumTargetClearance: Double
    public var pressScale: Double
    public var surfacePolicies: [QuillCodeNativeSurfaceTargetPolicy]
    public var designSystemContracts: [QuillCodeNativeHitTargetContract]
    public var surfaceContracts: [QuillCodeNativeHitTargetContract]
    public var clickProbes: [QuillCodeNativeHitTargetProbe]
    public var missingDesignKinds: [String]
    public var coveredSurfaceFamilies: [String]
    public var missingSurfaceFamilies: [String]
    public var missingRequiredSurfaceKinds: [String]
    public var coveredFocusTargets: [String]
    public var missingRequiredFocusTargets: [String]
    public var missingRequiredSurfaceActions: [String]
    public var missingRequiredSurfaceFocusTargets: [String]
    public var unexpectedSurfaceKinds: [String]
    public var unexpectedSurfaceActions: [String]
    public var unexpectedSurfaceFocusTargets: [String]
    public var missingRequiredCommandIDs: [String]
    public var missingClickProbeContractIDs: [String]
    public var clickProbeValidationIssues: [String]
    public var duplicateContractIDs: [String]
    public var validationIssues: [String]

    public var isValid: Bool {
        missingDesignKinds.isEmpty
            && missingSurfaceFamilies.isEmpty
            && missingRequiredSurfaceKinds.isEmpty
            && missingRequiredFocusTargets.isEmpty
            && missingRequiredSurfaceActions.isEmpty
            && missingRequiredSurfaceFocusTargets.isEmpty
            && unexpectedSurfaceKinds.isEmpty
            && unexpectedSurfaceActions.isEmpty
            && unexpectedSurfaceFocusTargets.isEmpty
            && missingRequiredCommandIDs.isEmpty
            && missingClickProbeContractIDs.isEmpty
            && clickProbeValidationIssues.isEmpty
            && duplicateContractIDs.isEmpty
            && validationIssues.isEmpty
    }

    public var dictionary: [String: Any] {
        [
            "minimumHitTarget": minimumHitTarget,
            "minimumTargetClearance": minimumTargetClearance,
            "pressScale": pressScale,
            "isValid": isValid,
            "surfacePolicies": surfacePolicies.map(\.dictionary),
            "designSystemContracts": designSystemContracts.map(\.dictionary),
            "surfaceContracts": surfaceContracts.map(\.dictionary),
            "clickProbes": clickProbes.map(\.dictionary),
            "missingDesignKinds": missingDesignKinds,
            "coveredSurfaceFamilies": coveredSurfaceFamilies,
            "missingSurfaceFamilies": missingSurfaceFamilies,
            "missingRequiredSurfaceKinds": missingRequiredSurfaceKinds,
            "coveredFocusTargets": coveredFocusTargets,
            "missingRequiredFocusTargets": missingRequiredFocusTargets,
            "missingRequiredSurfaceActions": missingRequiredSurfaceActions,
            "missingRequiredSurfaceFocusTargets": missingRequiredSurfaceFocusTargets,
            "unexpectedSurfaceKinds": unexpectedSurfaceKinds,
            "unexpectedSurfaceActions": unexpectedSurfaceActions,
            "unexpectedSurfaceFocusTargets": unexpectedSurfaceFocusTargets,
            "missingRequiredCommandIDs": missingRequiredCommandIDs,
            "missingClickProbeContractIDs": missingClickProbeContractIDs,
            "clickProbeValidationIssues": clickProbeValidationIssues,
            "duplicateContractIDs": duplicateContractIDs,
            "validationIssues": validationIssues
        ]
    }
}
