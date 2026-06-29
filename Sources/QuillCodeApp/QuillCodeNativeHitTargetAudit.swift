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
            "minHeight": minHeight,
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
    public var selectorKind: QuillCodeNativeHitTargetProbeSelectorKind
    public var selector: String
    public var requiredMinWidth: Double
    public var requiredMinHeight: Double
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
        selectorKind: QuillCodeNativeHitTargetProbeSelectorKind,
        selector: String,
        requiredMinWidth: Double,
        requiredMinHeight: Double,
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
        self.selectorKind = selectorKind
        self.selector = selector
        self.requiredMinWidth = requiredMinWidth
        self.requiredMinHeight = requiredMinHeight
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
            "requiresUnblockedInterior": requiresUnblockedInterior,
            "selectorKind": selectorKind.rawValue,
            "selector": selector,
            "requiredMinWidth": requiredMinWidth,
            "requiredMinHeight": requiredMinHeight,
            "samplePoints": samplePoints.map(\.dictionary)
        ]
    }
}

public struct QuillCodeNativeHitTargetAuditReport: Codable, Sendable, Hashable {
    public var minimumHitTarget: Double
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

public enum QuillCodeNativeHitTargetAudit {
    public static let requiredCommandIDs = [
        "add-project",
        "new-chat",
        "search",
        "toggle-extensions",
        "toggle-automations",
        "toggle-terminal",
        "toggle-browser",
        "toggle-memories",
        "toggle-activity",
        "command-palette",
        "keyboard-shortcuts",
        "settings"
    ]

    public static let requiredSurfaceFamilies = QuillCodeInteractionSurfaceFamily.allCases
    public static let requiredFocusTargets = QuillCodeNativeFocusTarget.allCases
    public static let requiredSurfacePolicies: [QuillCodeNativeSurfaceTargetPolicy] = [
        policy(.designSystem, kinds: QuillCodeNativeHitTargetKind.allCases, actions: QuillCodeNativeHitTargetAction.allCases),
        policy(.workspaceChrome, kinds: [.fullRow], actions: [.press]),
        policy(.sidebar, kinds: [.fullRow], actions: [.press], allowedKinds: [.fullRow, .icon]),
        policy(.sidebarThreadList, kinds: [.fullRow, .icon], actions: [.press]),
        policy(.topBar, kinds: [.icon, .fullRow], actions: [.press]),
        policy(.composer, kinds: [.textEntry, .icon, .capsule], actions: [.textInput, .press], focusTargets: [.composerMessage]),
        policy(.transcript, kinds: [.icon, .link], actions: [.press, .link], allowedKinds: [.icon, .link, .capsule]),
        policy(.toolCard, kinds: [.fullRow, .textButton], actions: [.press]),
        policy(.contextBanner, kinds: [.textButton], actions: [.press]),
        policy(.commandPalette, kinds: [.textEntry, .fullRow], actions: [.textInput, .press], focusTargets: [.commandPaletteSearch]),
        policy(.search, kinds: [.textEntry, .fullRow], actions: [.textInput, .press], focusTargets: [.searchChats]),
        policy(.settings, kinds: [.textEntry, .formAction], actions: [.textInput, .press], focusTargets: [.settingsTrustedRouterBaseURL]),
        policy(.modelPicker, kinds: [.textEntry, .fullRow, .icon], actions: [.textInput, .press], focusTargets: [.modelPickerSearch]),
        policy(.review, kinds: [.textEntry, .segmentedControl, .fullRow, .formAction], actions: [.textInput, .press], focusTargets: [.reviewBody, .reviewThreadReply]),
        policy(.secondaryPane, kinds: [.capsule], actions: [.press]),
        policy(.terminal, kinds: [.textEntry, .textButton], actions: [.textInput, .press], focusTargets: [.terminalCommand]),
        policy(.browser, kinds: [.textEntry, .textButton, .icon], actions: [.textInput, .press], focusTargets: [.browserAddress, .browserComment]),
        policy(.extensions, kinds: [.formAction, .capsule], actions: [.press]),
        policy(.memories, kinds: [.formAction, .icon], actions: [.press]),
        policy(.automations, kinds: [.formAction], actions: [.press]),
        policy(.menuBar, kinds: [.fullRow], actions: [.press])
    ]

    public static var designSystemContracts: [QuillCodeNativeHitTargetContract] {
        [
            contract("design.icon", family: .designSystem, surface: "Design system", label: "Icon button", kind: .icon, minWidth: 44),
            contract("design.text-button", family: .designSystem, surface: "Design system", label: "Text button", kind: .textButton, minWidth: 72),
            contract("design.form-action", family: .designSystem, surface: "Design system", label: "Form action", kind: .formAction, minWidth: 56),
            contract("design.link", family: .designSystem, surface: "Design system", label: "Link", kind: .link, minWidth: 72),
            contract("design.text-entry", family: .designSystem, surface: "Design system", label: "Text entry", kind: .textEntry, minWidth: nil),
            contract("design.segmented-control", family: .designSystem, surface: "Design system", label: "Segmented control", kind: .segmentedControl, minWidth: nil),
            contract("design.adjustable-control", family: .designSystem, surface: "Design system", label: "Adjustable control", kind: .adjustableControl, minWidth: nil),
            contract("design.switch-row", family: .designSystem, surface: "Design system", label: "Switch row", kind: .switchRow, minWidth: nil),
            contract("design.owned-gesture", family: .designSystem, surface: "Design system", label: "Owned gesture target", kind: .ownedGesture, minWidth: nil),
            contract("design.full-row", family: .designSystem, surface: "Design system", label: "Full row button", kind: .fullRow, minWidth: nil),
            contract("design.capsule", family: .designSystem, surface: "Design system", label: "Capsule button", kind: .capsule, minWidth: nil)
        ]
    }

    public static func report(for surface: WorkspaceSurface) -> QuillCodeNativeHitTargetAuditReport {
        let commandIDs = Set(surface.commands.map(\.id))
        let missingCommandIDs = requiredCommandIDs.filter { !commandIDs.contains($0) }
        let surfaceContracts = self.surfaceContracts(for: surface)
        let designContracts = designSystemContracts
        let clickProbes = clickProbes(for: surfaceContracts)
        let designKinds = Set(designContracts.map(\.kind))
        let missingKinds = QuillCodeNativeHitTargetKind.allCases
            .filter { !designKinds.contains($0) }
            .map(\.rawValue)
        let coveredFamilies = Set((designContracts + surfaceContracts).map(\.family))
        let missingFamilies = requiredSurfaceFamilies
            .filter { !coveredFamilies.contains($0) }
            .map(\.rawValue)
            .sorted()
        let allContracts = designContracts + surfaceContracts
        let missingSurfaceKinds = missingRequiredSurfaceKinds(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let missingSurfaceActions = missingRequiredSurfaceActions(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let coveredFocusTargets = Set(surfaceContracts.compactMap(\.focusTarget))
        let missingFocusTargets = requiredFocusTargets
            .filter { !coveredFocusTargets.contains($0) }
            .map(\.rawValue)
            .sorted()
        let missingSurfaceFocusTargets = missingRequiredSurfaceFocusTargets(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let unexpectedSurfaceKinds = unexpectedSurfaceKinds(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let unexpectedSurfaceActions = unexpectedSurfaceActions(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let unexpectedSurfaceFocusTargets = unexpectedSurfaceFocusTargets(
            policies: requiredSurfacePolicies,
            contracts: allContracts
        )
        let duplicateContractIDs = duplicateIDs(in: allContracts.map(\.id))
        let validationIssues = allContracts.flatMap(\.validationIssues)
        let missingClickProbeContractIDs = missingClickProbeContractIDs(
            contracts: surfaceContracts,
            probes: clickProbes
        )
        let clickProbeValidationIssues = validateClickProbes(
            contracts: surfaceContracts,
            probes: clickProbes
        )

        return QuillCodeNativeHitTargetAuditReport(
            minimumHitTarget: Double(QuillCodeMetrics.minimumHitTarget),
            pressScale: Double(QuillCodeMetrics.pressScale),
            surfacePolicies: requiredSurfacePolicies,
            designSystemContracts: designContracts,
            surfaceContracts: surfaceContracts,
            clickProbes: clickProbes,
            missingDesignKinds: missingKinds,
            coveredSurfaceFamilies: coveredFamilies.map(\.rawValue).sorted(),
            missingSurfaceFamilies: missingFamilies,
            missingRequiredSurfaceKinds: missingSurfaceKinds,
            coveredFocusTargets: coveredFocusTargets.map(\.rawValue).sorted(),
            missingRequiredFocusTargets: missingFocusTargets,
            missingRequiredSurfaceActions: missingSurfaceActions,
            missingRequiredSurfaceFocusTargets: missingSurfaceFocusTargets,
            unexpectedSurfaceKinds: unexpectedSurfaceKinds,
            unexpectedSurfaceActions: unexpectedSurfaceActions,
            unexpectedSurfaceFocusTargets: unexpectedSurfaceFocusTargets,
            missingRequiredCommandIDs: missingCommandIDs,
            missingClickProbeContractIDs: missingClickProbeContractIDs,
            clickProbeValidationIssues: clickProbeValidationIssues,
            duplicateContractIDs: duplicateContractIDs,
            validationIssues: validationIssues
        )
    }

    private static func policy(
        _ family: QuillCodeInteractionSurfaceFamily,
        kinds: [QuillCodeNativeHitTargetKind],
        actions: [QuillCodeNativeHitTargetAction] = [],
        focusTargets: [QuillCodeNativeFocusTarget] = [],
        allowedKinds: [QuillCodeNativeHitTargetKind]? = nil,
        allowedActions: [QuillCodeNativeHitTargetAction]? = nil,
        allowedFocusTargets: [QuillCodeNativeFocusTarget]? = nil
    ) -> QuillCodeNativeSurfaceTargetPolicy {
        QuillCodeNativeSurfaceTargetPolicy(
            family: family,
            requiredKinds: kinds,
            requiredActions: actions,
            requiredFocusTargets: focusTargets,
            allowedKinds: allowedKinds,
            allowedActions: allowedActions,
            allowedFocusTargets: allowedFocusTargets
        )
    }

    private static func missingRequiredSurfaceKinds(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        let contractsByFamily = Dictionary(grouping: contracts, by: \.family)
        return policies.flatMap { policy in
            let coveredKinds = Set(contractsByFamily[policy.family, default: []].map(\.kind))
            return policy.requiredKinds.compactMap { kind in
                coveredKinds.contains(kind) ? nil : "\(policy.family.rawValue):\(kind.rawValue)"
            }
        }
        .sorted()
    }

    private static func missingRequiredSurfaceActions(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        let contractsByFamily = Dictionary(grouping: contracts, by: \.family)
        return policies.flatMap { policy in
            let coveredActions = Set(contractsByFamily[policy.family, default: []].map(\.action))
            return policy.requiredActions.compactMap { action in
                coveredActions.contains(action) ? nil : "\(policy.family.rawValue):\(action.rawValue)"
            }
        }
        .sorted()
    }

    private static func missingRequiredSurfaceFocusTargets(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        let contractsByFamily = Dictionary(grouping: contracts, by: \.family)
        return policies.flatMap { policy in
            let coveredFocusTargets = Set(contractsByFamily[policy.family, default: []].compactMap(\.focusTarget))
            return policy.requiredFocusTargets.compactMap { focusTarget in
                coveredFocusTargets.contains(focusTarget) ? nil : "\(policy.family.rawValue):\(focusTarget.rawValue)"
            }
        }
        .sorted()
    }

    private static func unexpectedSurfaceKinds(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        unexpectedPolicyValues(
            policies: policies,
            contracts: contracts,
            allowedValues: \.allowedKinds,
            contractValue: { $0.kind },
            valueDescription: \.rawValue
        )
    }

    private static func unexpectedSurfaceActions(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        unexpectedPolicyValues(
            policies: policies,
            contracts: contracts,
            allowedValues: \.allowedActions,
            contractValue: { $0.action },
            valueDescription: \.rawValue
        )
    }

    private static func unexpectedSurfaceFocusTargets(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract]
    ) -> [String] {
        unexpectedPolicyValues(
            policies: policies,
            contracts: contracts,
            allowedValues: \.allowedFocusTargets,
            contractValue: \.focusTarget,
            valueDescription: \.rawValue
        )
    }

    private static func unexpectedPolicyValues<Value: Hashable>(
        policies: [QuillCodeNativeSurfaceTargetPolicy],
        contracts: [QuillCodeNativeHitTargetContract],
        allowedValues: (QuillCodeNativeSurfaceTargetPolicy) -> [Value],
        contractValue: (QuillCodeNativeHitTargetContract) -> Value?,
        valueDescription: (Value) -> String
    ) -> [String] {
        let allowedValuesByFamily = Dictionary(
            uniqueKeysWithValues: policies.map { ($0.family, Set(allowedValues($0))) }
        )
        return contracts.compactMap { contract in
            guard let value = contractValue(contract),
                  let allowedValues = allowedValuesByFamily[contract.family],
                  !allowedValues.contains(value)
            else { return nil }
            return "\(contract.family.rawValue):\(contract.id):\(valueDescription(value))"
        }
        .sorted()
    }

    private static func duplicateIDs(in ids: [String]) -> [String] {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for id in ids {
            guard !seen.insert(id).inserted else { continue }
            duplicates.insert(id)
        }
        return duplicates.sorted()
    }

    private static func missingClickProbeContractIDs(
        contracts: [QuillCodeNativeHitTargetContract],
        probes: [QuillCodeNativeHitTargetProbe]
    ) -> [String] {
        let probedContractIDs = Set(probes.map(\.contractID))
        return contracts
            .map(\.id)
            .filter { !probedContractIDs.contains($0) }
            .sorted()
    }

    public static func validateClickProbes(
        contracts: [QuillCodeNativeHitTargetContract],
        probes: [QuillCodeNativeHitTargetProbe]
    ) -> [String] {
        let contractsByID = Dictionary(
            contracts.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seenProbeIDs: Set<String> = []
        var issues: [String] = []

        for probe in probes {
            let contractID = probe.contractID.trimmingCharacters(in: .whitespacesAndNewlines)
            if contractID.isEmpty {
                issues.append("click probe has an empty contract id")
                continue
            }
            guard seenProbeIDs.insert(contractID).inserted else {
                issues.append("\(contractID) has duplicate click probes")
                continue
            }
            guard let contract = contractsByID[contractID] else {
                issues.append("\(contractID) click probe does not match a surface contract")
                continue
            }

            issues.append(contentsOf: selectorValidationIssues(probe: probe, contract: contract))
            issues.append(contentsOf: semanticValidationIssues(probe: probe, contract: contract))
            issues.append(contentsOf: dimensionValidationIssues(probe: probe))
            issues.append(contentsOf: samplePointValidationIssues(probe: probe))
        }

        return issues.sorted()
    }

    private static func selectorValidationIssues(
        probe: QuillCodeNativeHitTargetProbe,
        contract: QuillCodeNativeHitTargetContract
    ) -> [String] {
        let expectedSelector: String?
        switch probe.selectorKind {
        case .testID:
            expectedSelector = contract.testID
        case .commandID:
            expectedSelector = contract.commandID
        case .focusTarget:
            expectedSelector = contract.focusTarget?.rawValue
        }

        let selector = probe.selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if selector.isEmpty {
            return ["\(probe.contractID) click probe has an empty selector"]
        }
        if selector != expectedSelector {
            return ["\(probe.contractID) click probe selector \(selector) does not match \(probe.selectorKind.rawValue) contract selector"]
        }
        return []
    }

    private static func semanticValidationIssues(
        probe: QuillCodeNativeHitTargetProbe,
        contract: QuillCodeNativeHitTargetContract
    ) -> [String] {
        var issues: [String] = []
        if probe.kind != contract.kind {
            issues.append("\(probe.contractID) click probe kind \(probe.kind.rawValue) does not match \(contract.kind.rawValue)")
        }
        if probe.action != contract.action {
            issues.append("\(probe.contractID) click probe action \(probe.action.rawValue) does not match \(contract.action.rawValue)")
        }
        if probe.family != contract.family {
            issues.append("\(probe.contractID) click probe family \(probe.family.rawValue) does not match \(contract.family.rawValue)")
        }
        if probe.collisionScope != contract.collisionScope {
            issues.append("\(probe.contractID) click probe collision scope does not match contract")
        }
        if probe.allowsNestedInteractiveChildren != contract.allowsNestedInteractiveChildren {
            issues.append("\(probe.contractID) click probe nested-child policy does not match contract")
        }
        if probe.requiresUnblockedInterior != contract.requiresUnblockedInterior {
            issues.append("\(probe.contractID) click probe interior-blocking policy does not match contract")
        }
        return issues
    }

    private static func dimensionValidationIssues(
        probe: QuillCodeNativeHitTargetProbe
    ) -> [String] {
        var issues: [String] = []
        let minimum = Double(QuillCodeMetrics.minimumHitTarget)
        if probe.requiredMinWidth < minimum {
            issues.append("\(probe.contractID) click probe requiredMinWidth \(probe.requiredMinWidth) is below \(minimum)")
        }
        if probe.requiredMinHeight < minimum {
            issues.append("\(probe.contractID) click probe requiredMinHeight \(probe.requiredMinHeight) is below \(minimum)")
        }
        return issues
    }

    private static func samplePointValidationIssues(
        probe: QuillCodeNativeHitTargetProbe
    ) -> [String] {
        var issues: [String] = []
        let pointNames = Set(probe.samplePoints.map(\.name))
        let missingPointNames = requiredClickSamplePointNames
            .filter { !pointNames.contains($0) }
            .sorted()
        if !missingPointNames.isEmpty {
            issues.append("\(probe.contractID) click probe is missing sample points: \(missingPointNames.joined(separator: ", "))")
        }
        for point in probe.samplePoints {
            let pointName = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if pointName.isEmpty {
                issues.append("\(probe.contractID) click probe has an unnamed sample point")
            } else if let expectedPoint = expectedClickSamplePointsByName[pointName] {
                if !point.x.isNearlyEqual(to: expectedPoint.x) || !point.y.isNearlyEqual(to: expectedPoint.y) {
                    issues.append("\(probe.contractID) click probe sample point \(point.name) has unexpected coordinates")
                }
            } else {
                issues.append("\(probe.contractID) click probe has unknown sample point \(point.name)")
            }
            if point.x <= 0 || point.x >= 1 || point.y <= 0 || point.y >= 1 {
                issues.append("\(probe.contractID) click probe sample point \(point.name) is outside the target interior")
            }
        }
        return issues
    }

    private static func clickProbes(
        for contracts: [QuillCodeNativeHitTargetContract]
    ) -> [QuillCodeNativeHitTargetProbe] {
        contracts.compactMap { contract in
            guard let selector = probeSelector(for: contract) else { return nil }
            return QuillCodeNativeHitTargetProbe(
                contractID: contract.id,
                family: contract.family,
                collisionScope: contract.collisionScope,
                label: contract.label,
                kind: contract.kind,
                action: contract.action,
                allowsNestedInteractiveChildren: contract.allowsNestedInteractiveChildren,
                requiresUnblockedInterior: contract.requiresUnblockedInterior,
                selectorKind: selector.kind,
                selector: selector.value,
                requiredMinWidth: max(
                    contract.minWidth ?? Double(QuillCodeMetrics.minimumHitTarget),
                    Double(QuillCodeMetrics.minimumHitTarget)
                ),
                requiredMinHeight: max(
                    contract.minHeight,
                    Double(QuillCodeMetrics.minimumHitTarget)
                ),
                samplePoints: normalizedClickSamplePoints
            )
        }
        .sorted { lhs, rhs in
            lhs.contractID < rhs.contractID
        }
    }

    private static func probeSelector(
        for contract: QuillCodeNativeHitTargetContract
    ) -> (kind: QuillCodeNativeHitTargetProbeSelectorKind, value: String)? {
        if let testID = contract.testID?.trimmingCharacters(in: .whitespacesAndNewlines), !testID.isEmpty {
            return (.testID, testID)
        }
        if let commandID = contract.commandID?.trimmingCharacters(in: .whitespacesAndNewlines), !commandID.isEmpty {
            return (.commandID, commandID)
        }
        if let focusTarget = contract.focusTarget {
            return (.focusTarget, focusTarget.rawValue)
        }
        return nil
    }

    private static let requiredClickSamplePointNames: Set<String> = [
        "center",
        "leading-interior",
        "trailing-interior",
        "top-interior",
        "bottom-interior"
    ]

    private static let normalizedClickSamplePoints: [QuillCodeNativeHitTargetProbePoint] = [
        QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "leading-interior", x: 0.18, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "trailing-interior", x: 0.82, y: 0.5),
        QuillCodeNativeHitTargetProbePoint(name: "top-interior", x: 0.5, y: 0.18),
        QuillCodeNativeHitTargetProbePoint(name: "bottom-interior", x: 0.5, y: 0.82)
    ]

    private static let expectedClickSamplePointsByName = Dictionary(
        uniqueKeysWithValues: normalizedClickSamplePoints.map { ($0.name, $0) }
    )

    private static func surfaceContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts = persistentSurfaceContracts()
        contracts.append(contentsOf: canonicalTransientSurfaceContracts())
        contracts.append(contentsOf: commandContracts(from: surface.commands))
        contracts.append(contentsOf: conditionalPaneContracts(for: surface))
        return contracts
    }

    private static func persistentSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract("composer.input", family: .composer, surface: "Composer", label: "Message", kind: .textEntry, minWidth: nil, focusTarget: .composerMessage, testID: "composer-input"),
            contract("composer.send", family: .composer, surface: "Composer", label: "Send message", kind: .icon, minWidth: 44, testID: "send-button"),
            contract("composer.model-picker", family: .composer, surface: "Composer", label: "Model picker", kind: .capsule, minWidth: nil, testID: "model-picker-button"),
            contract("composer.mode-picker", family: .composer, surface: "Composer", label: "Mode picker", kind: .capsule, minWidth: nil, testID: "mode-picker-button"),
            contract("top-bar.overflow", family: .topBar, surface: "Top bar", label: "More workspace actions", kind: .icon, minWidth: 44, testID: "top-bar-overflow"),
            contract("sidebar.tools-menu", family: .sidebar, surface: "Sidebar", label: "Tools", kind: .fullRow, minWidth: nil, testID: "sidebar-tools-button"),
            contract("project.clear", family: .sidebar, surface: "Project header", label: "Clear project", kind: .icon, minWidth: 44, testID: "project-clear-button"),
            contract("workspace.chrome", family: .workspaceChrome, surface: "Workspace chrome", label: "Workspace command", kind: .fullRow, minWidth: nil, testID: "workspace-command")
        ]
    }

    private static func canonicalTransientSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract("sidebar.thread-row", family: .sidebarThreadList, surface: "Sidebar thread list", label: "Thread row", kind: .fullRow, minWidth: nil, testID: "sidebar-item"),
            contract("sidebar.thread-action", family: .sidebarThreadList, surface: "Sidebar thread list", label: "Thread row action", kind: .icon, minWidth: 44, testID: "sidebar-thread-action"),
            contract("transcript.message-action", family: .transcript, surface: "Transcript", label: "Message action", kind: .icon, minWidth: 44, testID: "message-action"),
            contract("transcript.artifact-link", family: .transcript, surface: "Transcript", label: "Artifact link", kind: .link, minWidth: 96, testID: "tool-card-artifact"),
            contract("transcript.tool-card", family: .toolCard, surface: "Tool card", label: "Tool details", kind: .fullRow, minWidth: nil, testID: "tool-card-details"),
            contract("transcript.tool-card-action", family: .toolCard, surface: "Tool card", label: "Tool action", kind: .textButton, minWidth: 72, testID: "tool-card-action"),
            contract("transcript.context-banner-action", family: .contextBanner, surface: "Context banner", label: "Context action", kind: .textButton, minWidth: 72, testID: "context-banner-action"),
            contract("command-palette.input", family: .commandPalette, surface: "Command palette", label: "Command search", kind: .textEntry, minWidth: nil, focusTarget: .commandPaletteSearch, testID: "command-palette-input"),
            contract("command-palette.result", family: .commandPalette, surface: "Command palette", label: "Command result", kind: .fullRow, minWidth: nil, testID: "command-palette-result"),
            contract("search.input", family: .search, surface: "Search", label: "Search chats", kind: .textEntry, minWidth: nil, focusTarget: .searchChats, testID: "search-input"),
            contract("search.result", family: .search, surface: "Search", label: "Search result", kind: .fullRow, minWidth: nil, testID: "search-result"),
            contract("settings.text-entry", family: .settings, surface: "Settings", label: "Settings text entry", kind: .textEntry, minWidth: nil, focusTarget: .settingsTrustedRouterBaseURL, testID: "settings-text-entry"),
            contract("settings.action", family: .settings, surface: "Settings", label: "Settings action", kind: .formAction, minWidth: 72, testID: "settings-action"),
            contract("model-picker.search", family: .modelPicker, surface: "Model picker", label: "Model search", kind: .textEntry, minWidth: nil, focusTarget: .modelPickerSearch, testID: "model-picker-search"),
            contract("model-picker.option", family: .modelPicker, surface: "Model picker", label: "Model option", kind: .fullRow, minWidth: nil, testID: "model-picker-option"),
            contract("model-picker.option-action", family: .modelPicker, surface: "Model picker", label: "Model option action", kind: .icon, minWidth: 44, testID: "model-picker-option-action"),
            contract("review.body", family: .review, surface: "Review", label: "Review body", kind: .textEntry, minWidth: nil, focusTarget: .reviewBody, testID: "review-body"),
            contract("review.thread-reply", family: .review, surface: "Review", label: "Review thread reply", kind: .textEntry, minWidth: nil, focusTarget: .reviewThreadReply, testID: "pr-review-thread-reply-input"),
            contract("review.mode", family: .review, surface: "Review", label: "Review mode", kind: .segmentedControl, minWidth: nil, testID: "review-mode"),
            contract("review.file-row", family: .review, surface: "Review", label: "Review file", kind: .fullRow, minWidth: nil, testID: "review-file"),
            contract("review.action", family: .review, surface: "Review", label: "Review action", kind: .formAction, minWidth: 72, testID: "review-action"),
            contract("secondary-pane.tab", family: .secondaryPane, surface: "Secondary pane", label: "Pane tab", kind: .capsule, minWidth: 72, testID: "secondary-pane-tab"),
            contract("terminal.family-entry", family: .terminal, surface: "Terminal", label: "Terminal command", kind: .textEntry, minWidth: nil, focusTarget: .terminalCommand, testID: "terminal-command"),
            contract("terminal.family-action", family: .terminal, surface: "Terminal", label: "Terminal action", kind: .textButton, minWidth: 64, testID: "terminal-action"),
            contract("browser.family-entry", family: .browser, surface: "Browser", label: "Browser address", kind: .textEntry, minWidth: nil, focusTarget: .browserAddress, testID: "browser-address"),
            contract("browser.family-action", family: .browser, surface: "Browser", label: "Browser action", kind: .textButton, minWidth: 64, testID: "browser-action"),
            contract("browser.family-icon", family: .browser, surface: "Browser", label: "Browser icon action", kind: .icon, minWidth: 44, testID: "browser-icon-action"),
            contract("browser.comment-entry", family: .browser, surface: "Browser", label: "Browser comment", kind: .textEntry, minWidth: nil, focusTarget: .browserComment, testID: "browser-comment-input"),
            contract("extensions.family-entry", family: .extensions, surface: "Extensions", label: "Extension action", kind: .formAction, minWidth: 74, testID: "extension-action"),
            contract("extensions.reference-action", family: .extensions, surface: "Extensions", label: "MCP resource or prompt action", kind: .capsule, minWidth: 96, testID: "extension-reference-action"),
            contract("memories.family-entry", family: .memories, surface: "Memories", label: "Add memory", kind: .formAction, minWidth: 56, testID: "memory-add"),
            contract("memories.item-action", family: .memories, surface: "Memories", label: "Memory row action", kind: .icon, minWidth: 44, testID: "memory-row-action"),
            contract("automations.family-entry", family: .automations, surface: "Automations", label: "Create automation", kind: .formAction, minWidth: 90, testID: "automation-create"),
            contract("menu-bar.action", family: .menuBar, surface: "Menu bar", label: "Menu bar action", kind: .fullRow, minWidth: nil, testID: "menu-bar-action")
        ]
    }

    private static func commandContracts(from commands: [WorkspaceCommandSurface]) -> [QuillCodeNativeHitTargetContract] {
        commands.map { command in
            commandContract(command)
        }
    }

    private static func commandContract(_ command: WorkspaceCommandSurface) -> QuillCodeNativeHitTargetContract {
        let kind: QuillCodeNativeHitTargetKind
        let surface: String
        let minWidth: Double?
        switch command.id {
        case "add-project":
            kind = .icon
            surface = "Project header"
            minWidth = 44
        case "new-chat", "search", "toggle-extensions", "toggle-automations":
            kind = .fullRow
            surface = "Sidebar primary"
            minWidth = nil
        case "toggle-terminal", "toggle-browser", "toggle-memories", "toggle-activity", "command-palette":
            kind = .fullRow
            surface = "Sidebar tools"
            minWidth = nil
        case "computer-use-setup", "keyboard-shortcuts", "settings", "disconnect-all":
            kind = .fullRow
            surface = "Top bar overflow"
            minWidth = nil
        default:
            kind = .fullRow
            surface = "Command palette"
            minWidth = nil
        }
        return contract(
            "command.\(command.id)",
            family: commandFamily(command.id),
            surface: surface,
            label: command.title,
            kind: kind,
            minWidth: minWidth,
            commandID: command.id,
            source: "WorkspaceCommandSurface"
        )
    }

    private static func commandFamily(_ commandID: String) -> QuillCodeInteractionSurfaceFamily {
        switch commandID {
        case "add-project", "new-chat", "search", "toggle-extensions", "toggle-automations",
            "toggle-terminal", "toggle-browser", "toggle-memories", "toggle-activity":
            return .sidebar
        case "computer-use-setup", "keyboard-shortcuts", "settings", "disconnect-all":
            return .topBar
        default:
            return .commandPalette
        }
    }

    private static func conditionalPaneContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts: [QuillCodeNativeHitTargetContract] = []

        if surface.terminal.isVisible {
            contracts.append(contract("terminal.command", family: .terminal, surface: "Terminal", label: "Terminal command", kind: .textEntry, minWidth: nil, focusTarget: .terminalCommand, testID: "terminal-command"))
            contracts.append(contract("terminal.run", family: .terminal, surface: "Terminal", label: surface.terminal.commandActionTitle, kind: .textButton, minWidth: 64, testID: "terminal-run"))
            contracts.append(contract("terminal.clear", family: .terminal, surface: "Terminal", label: "Clear", kind: .textButton, minWidth: 56, testID: "terminal-clear"))
        }

        if surface.browser.isVisible {
            contracts.append(contract("browser.address", family: .browser, surface: "Browser", label: "Browser address", kind: .textEntry, minWidth: nil, focusTarget: .browserAddress, testID: "browser-address"))
            contracts.append(contract("browser.open", family: .browser, surface: "Browser", label: "Open", kind: .textButton, minWidth: 64, testID: "browser-open"))
            contracts.append(contract("browser.new-tab", family: .browser, surface: "Browser", label: "New tab", kind: .icon, minWidth: 44, testID: "browser-new-tab"))
            contracts.append(contract("browser.comment", family: .browser, surface: "Browser", label: "Browser comment", kind: .textEntry, minWidth: nil, focusTarget: .browserComment, testID: "browser-comment-input"))
            contracts.append(contract("browser.add-comment", family: .browser, surface: "Browser", label: "Add comment", kind: .textButton, minWidth: 92, testID: "browser-add-comment"))
        }

        if surface.extensions.isVisible {
            if surface.extensions.items.contains(where: { item in
                item.installCommandID != nil || item.updateCommandID != nil || item.startCommandID != nil || item.stopCommandID != nil
            }) {
                contracts.append(contract("extensions.action", family: .extensions, surface: "Extensions", label: "Extension action", kind: .formAction, minWidth: 74, testID: "extension-action"))
            }
            if surface.extensions.items.contains(where: { !$0.resourceActions.isEmpty || !$0.promptActions.isEmpty }) {
                contracts.append(contract("extensions.mcp-reference", family: .extensions, surface: "Extensions", label: "MCP resource or prompt action", kind: .capsule, minWidth: 96, testID: "extension-reference-action"))
            }
        }

        if surface.memories.isVisible {
            contracts.append(contract("memories.add", family: .memories, surface: "Memories", label: "Add memory", kind: .formAction, minWidth: 56, testID: "memory-add"))
            if surface.memories.items.contains(where: { $0.canEdit }) {
                contracts.append(contract("memories.edit", family: .memories, surface: "Memories", label: "Edit memory", kind: .icon, minWidth: 44, testID: "memory-edit"))
            }
            if surface.memories.items.contains(where: { $0.canDelete }) {
                contracts.append(contract("memories.delete", family: .memories, surface: "Memories", label: "Forget memory", kind: .icon, minWidth: 44, testID: "memory-delete"))
            }
        }

        if surface.automations.isVisible {
            if surface.automations.createThreadFollowUpCommand != nil || surface.automations.createWorkspaceScheduleCommand != nil {
                contracts.append(contract("automations.create", family: .automations, surface: "Automations", label: "Create automation", kind: .formAction, minWidth: 90, testID: "automation-create"))
            }
            if surface.automations.workflows.contains(where: { $0.runCommandID != nil }) {
                contracts.append(contract("automations.run", family: .automations, surface: "Automations", label: "Run automation", kind: .formAction, minWidth: 56, testID: "automation-run"))
            }
            if surface.automations.workflows.contains(where: { $0.primaryCommandID != nil }) {
                contracts.append(contract("automations.primary", family: .automations, surface: "Automations", label: "Pause or resume automation", kind: .formAction, minWidth: 56, testID: "automation-primary-action"))
            }
            if surface.automations.workflows.contains(where: { $0.deleteCommandID != nil }) {
                contracts.append(contract("automations.delete", family: .automations, surface: "Automations", label: "Delete automation", kind: .formAction, minWidth: 56, testID: "automation-delete"))
            }
        }

        if surface.transcript.thinking?.traceLines.isEmpty == false {
            contracts.append(contract("transcript.thinking-trace", family: .transcript, surface: "Transcript", label: "Thinking trace", kind: .capsule, minWidth: 96, testID: "thinking-trace"))
        }

        return contracts
    }

    private static func contract(
        _ id: String,
        family: QuillCodeInteractionSurfaceFamily,
        surface: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double?,
        minHeight: Double = Double(QuillCodeMetrics.minimumHitTarget),
        focusTarget: QuillCodeNativeFocusTarget? = nil,
        testID: String? = nil,
        commandID: String? = nil,
        source: String = "SwiftUI"
    ) -> QuillCodeNativeHitTargetContract {
        QuillCodeNativeHitTargetContract(
            id: id,
            family: family,
            surface: surface,
            label: label,
            kind: kind,
            minWidth: minWidth,
            minHeight: minHeight,
            focusTarget: focusTarget,
            testID: normalizedNativeTestID(testID),
            commandID: commandID,
            source: source
        )
    }

    private static func normalizedNativeTestID(_ testID: String?) -> String? {
        guard let testID else { return nil }
        let trimmed = testID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return testID }
        return trimmed.hasPrefix("quillcode-") ? trimmed : "quillcode-\(trimmed)"
    }
}

private extension Double {
    func isNearlyEqual(to other: Double) -> Bool {
        abs(self - other) <= 1e-9
    }
}
