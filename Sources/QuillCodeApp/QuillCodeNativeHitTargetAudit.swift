import Foundation

public enum QuillCodeNativeHitTargetKind: String, Codable, Sendable, Hashable, CaseIterable {
    case icon
    case textButton
    case formAction
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

extension QuillCodeNativeHitTargetKind {
    var action: QuillCodeNativeHitTargetAction {
        switch self {
        case .textEntry:
            return .textInput
        case .adjustableControl:
            return .adjust
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
    public var label: String
    public var kind: QuillCodeNativeHitTargetKind
    public var minWidth: Double?
    public var minHeight: Double
    public var action: QuillCodeNativeHitTargetAction
    public var allowsNestedInteractiveChildren: Bool
    public var requiresUnblockedInterior: Bool
    public var source: String

    public init(
        id: String,
        family: QuillCodeInteractionSurfaceFamily,
        surface: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double?,
        minHeight: Double = Double(QuillCodeMetrics.minimumHitTarget),
        source: String
    ) {
        self.id = id
        self.family = family
        self.surface = surface
        self.label = label
        self.kind = kind
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.action = kind.action
        self.allowsNestedInteractiveChildren = kind.allowsNestedInteractiveChildren
        self.requiresUnblockedInterior = kind.requiresUnblockedInterior
        self.source = source
    }

    public var dictionary: [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "family": family.rawValue,
            "surface": surface,
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
        return value
    }

    public var validationIssues: [String] {
        var issues: [String] = []
        if minHeight < Double(QuillCodeMetrics.minimumHitTarget) {
            issues.append("\(id) minHeight \(minHeight) is below \(QuillCodeMetrics.minimumHitTarget)")
        }
        if let minWidth, minWidth < Double(QuillCodeMetrics.minimumHitTarget) {
            issues.append("\(id) minWidth \(minWidth) is below \(QuillCodeMetrics.minimumHitTarget)")
        }
        if allowsNestedInteractiveChildren {
            issues.append("\(id) allows nested interactive children; split the parent target or make the children decorative")
        }
        return issues
    }
}

public struct QuillCodeNativeHitTargetAuditReport: Codable, Sendable, Hashable {
    public var minimumHitTarget: Double
    public var pressScale: Double
    public var designSystemContracts: [QuillCodeNativeHitTargetContract]
    public var surfaceContracts: [QuillCodeNativeHitTargetContract]
    public var missingDesignKinds: [String]
    public var coveredSurfaceFamilies: [String]
    public var missingSurfaceFamilies: [String]
    public var missingRequiredCommandIDs: [String]
    public var validationIssues: [String]

    public var isValid: Bool {
        missingDesignKinds.isEmpty
            && missingSurfaceFamilies.isEmpty
            && missingRequiredCommandIDs.isEmpty
            && validationIssues.isEmpty
    }

    public var dictionary: [String: Any] {
        [
            "minimumHitTarget": minimumHitTarget,
            "pressScale": pressScale,
            "isValid": isValid,
            "designSystemContracts": designSystemContracts.map(\.dictionary),
            "surfaceContracts": surfaceContracts.map(\.dictionary),
            "missingDesignKinds": missingDesignKinds,
            "coveredSurfaceFamilies": coveredSurfaceFamilies,
            "missingSurfaceFamilies": missingSurfaceFamilies,
            "missingRequiredCommandIDs": missingRequiredCommandIDs,
            "validationIssues": validationIssues
        ]
    }
}

public enum QuillCodeNativeHitTargetAudit {
    public static let requiredCommandIDs = [
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

    public static var designSystemContracts: [QuillCodeNativeHitTargetContract] {
        [
            contract("design.icon", family: .designSystem, surface: "Design system", label: "Icon button", kind: .icon, minWidth: 44),
            contract("design.text-button", family: .designSystem, surface: "Design system", label: "Text button", kind: .textButton, minWidth: 72),
            contract("design.form-action", family: .designSystem, surface: "Design system", label: "Form action", kind: .formAction, minWidth: 56),
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
        let designKinds = Set(designContracts.map(\.kind))
        let missingKinds = QuillCodeNativeHitTargetKind.allCases
            .filter { !designKinds.contains($0) }
            .map(\.rawValue)
        let coveredFamilies = Set((designContracts + surfaceContracts).map(\.family))
        let missingFamilies = requiredSurfaceFamilies
            .filter { !coveredFamilies.contains($0) }
            .map(\.rawValue)
            .sorted()
        let validationIssues = (designContracts + surfaceContracts).flatMap(\.validationIssues)

        return QuillCodeNativeHitTargetAuditReport(
            minimumHitTarget: Double(QuillCodeMetrics.minimumHitTarget),
            pressScale: Double(QuillCodeMetrics.pressScale),
            designSystemContracts: designContracts,
            surfaceContracts: surfaceContracts,
            missingDesignKinds: missingKinds,
            coveredSurfaceFamilies: coveredFamilies.map(\.rawValue).sorted(),
            missingSurfaceFamilies: missingFamilies,
            missingRequiredCommandIDs: missingCommandIDs,
            validationIssues: validationIssues
        )
    }

    private static func surfaceContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts = persistentSurfaceContracts()
        contracts.append(contentsOf: canonicalTransientSurfaceContracts())
        contracts.append(contentsOf: commandContracts(from: surface.commands))
        contracts.append(contentsOf: conditionalPaneContracts(for: surface))
        return contracts
    }

    private static func persistentSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract("composer.input", family: .composer, surface: "Composer", label: "Message", kind: .textEntry, minWidth: nil),
            contract("composer.send", family: .composer, surface: "Composer", label: "Send message", kind: .icon, minWidth: 44),
            contract("composer.model-picker", family: .composer, surface: "Composer", label: "Model picker", kind: .capsule, minWidth: nil),
            contract("composer.mode-picker", family: .composer, surface: "Composer", label: "Mode picker", kind: .capsule, minWidth: nil),
            contract("top-bar.overflow", family: .topBar, surface: "Top bar", label: "More workspace actions", kind: .icon, minWidth: 44),
            contract("sidebar.tools-menu", family: .sidebar, surface: "Sidebar", label: "Tools", kind: .fullRow, minWidth: nil),
            contract("workspace.chrome", family: .workspaceChrome, surface: "Workspace chrome", label: "Workspace command", kind: .fullRow, minWidth: nil)
        ]
    }

    private static func canonicalTransientSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract("sidebar.thread-row", family: .sidebarThreadList, surface: "Sidebar thread list", label: "Thread row", kind: .fullRow, minWidth: nil),
            contract("sidebar.thread-action", family: .sidebarThreadList, surface: "Sidebar thread list", label: "Thread row action", kind: .icon, minWidth: 44),
            contract("transcript.message-action", family: .transcript, surface: "Transcript", label: "Message action", kind: .icon, minWidth: 44),
            contract("transcript.tool-card", family: .toolCard, surface: "Tool card", label: "Tool details", kind: .fullRow, minWidth: nil),
            contract("transcript.tool-card-action", family: .toolCard, surface: "Tool card", label: "Tool action", kind: .textButton, minWidth: 72),
            contract("transcript.context-banner-action", family: .contextBanner, surface: "Context banner", label: "Context action", kind: .textButton, minWidth: 72),
            contract("command-palette.input", family: .commandPalette, surface: "Command palette", label: "Command search", kind: .textEntry, minWidth: nil),
            contract("command-palette.result", family: .commandPalette, surface: "Command palette", label: "Command result", kind: .fullRow, minWidth: nil),
            contract("search.input", family: .search, surface: "Search", label: "Search chats", kind: .textEntry, minWidth: nil),
            contract("search.result", family: .search, surface: "Search", label: "Search result", kind: .fullRow, minWidth: nil),
            contract("settings.text-entry", family: .settings, surface: "Settings", label: "Settings text entry", kind: .textEntry, minWidth: nil),
            contract("settings.action", family: .settings, surface: "Settings", label: "Settings action", kind: .formAction, minWidth: 72),
            contract("model-picker.option", family: .modelPicker, surface: "Model picker", label: "Model option", kind: .fullRow, minWidth: nil),
            contract("model-picker.option-action", family: .modelPicker, surface: "Model picker", label: "Model option action", kind: .icon, minWidth: 44),
            contract("review.file-row", family: .review, surface: "Review", label: "Review file", kind: .fullRow, minWidth: nil),
            contract("review.action", family: .review, surface: "Review", label: "Review action", kind: .formAction, minWidth: 72),
            contract("secondary-pane.tab", family: .secondaryPane, surface: "Secondary pane", label: "Pane tab", kind: .capsule, minWidth: 72),
            contract("terminal.family-entry", family: .terminal, surface: "Terminal", label: "Terminal command", kind: .textEntry, minWidth: nil),
            contract("browser.family-entry", family: .browser, surface: "Browser", label: "Browser address", kind: .textEntry, minWidth: nil),
            contract("extensions.family-entry", family: .extensions, surface: "Extensions", label: "Extension action", kind: .formAction, minWidth: 74),
            contract("memories.family-entry", family: .memories, surface: "Memories", label: "Add memory", kind: .formAction, minWidth: 56),
            contract("automations.family-entry", family: .automations, surface: "Automations", label: "Create automation", kind: .formAction, minWidth: 90),
            contract("menu-bar.action", family: .menuBar, surface: "Menu bar", label: "Menu bar action", kind: .fullRow, minWidth: nil)
        ]
    }

    private static func commandContracts(from commands: [WorkspaceCommandSurface]) -> [QuillCodeNativeHitTargetContract] {
        let commandByID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
        return requiredCommandIDs.compactMap { commandID in
            guard let command = commandByID[commandID] else { return nil }
            return commandContract(command)
        }
    }

    private static func commandContract(_ command: WorkspaceCommandSurface) -> QuillCodeNativeHitTargetContract {
        let kind: QuillCodeNativeHitTargetKind
        let surface: String
        switch command.id {
        case "new-chat", "search", "toggle-extensions", "toggle-automations":
            kind = .fullRow
            surface = "Sidebar primary"
        case "toggle-terminal", "toggle-browser", "toggle-memories", "toggle-activity", "command-palette":
            kind = .fullRow
            surface = "Sidebar tools"
        case "keyboard-shortcuts", "settings":
            kind = .fullRow
            surface = "Top bar overflow"
        default:
            kind = .textButton
            surface = "Workspace command"
        }
        return contract(
            "command.\(command.id)",
            family: commandFamily(command.id),
            surface: surface,
            label: command.title,
            kind: kind,
            minWidth: nil,
            source: "WorkspaceCommandSurface"
        )
    }

    private static func commandFamily(_ commandID: String) -> QuillCodeInteractionSurfaceFamily {
        switch commandID {
        case "new-chat", "search", "toggle-extensions", "toggle-automations",
            "toggle-terminal", "toggle-browser", "toggle-memories", "toggle-activity":
            return .sidebar
        case "keyboard-shortcuts", "settings":
            return .topBar
        default:
            return .workspaceChrome
        }
    }

    private static func conditionalPaneContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts: [QuillCodeNativeHitTargetContract] = []

        if surface.terminal.isVisible {
            contracts.append(contract("terminal.command", family: .terminal, surface: "Terminal", label: "Terminal command", kind: .textEntry, minWidth: nil))
            contracts.append(contract("terminal.run", family: .terminal, surface: "Terminal", label: surface.terminal.commandActionTitle, kind: .textButton, minWidth: 64))
            contracts.append(contract("terminal.clear", family: .terminal, surface: "Terminal", label: "Clear", kind: .textButton, minWidth: 56))
        }

        if surface.browser.isVisible {
            contracts.append(contract("browser.address", family: .browser, surface: "Browser", label: "Browser address", kind: .textEntry, minWidth: nil))
            contracts.append(contract("browser.open", family: .browser, surface: "Browser", label: "Open", kind: .textButton, minWidth: 64))
            contracts.append(contract("browser.new-tab", family: .browser, surface: "Browser", label: "New tab", kind: .icon, minWidth: 44))
            contracts.append(contract("browser.comment", family: .browser, surface: "Browser", label: "Browser comment", kind: .textEntry, minWidth: nil))
            contracts.append(contract("browser.add-comment", family: .browser, surface: "Browser", label: "Add comment", kind: .textButton, minWidth: 92))
        }

        if surface.extensions.isVisible {
            if surface.extensions.items.contains(where: { item in
                item.installCommandID != nil || item.updateCommandID != nil || item.startCommandID != nil || item.stopCommandID != nil
            }) {
                contracts.append(contract("extensions.action", family: .extensions, surface: "Extensions", label: "Extension action", kind: .formAction, minWidth: 74))
            }
            if surface.extensions.items.contains(where: { !$0.resourceActions.isEmpty || !$0.promptActions.isEmpty }) {
                contracts.append(contract("extensions.mcp-reference", family: .extensions, surface: "Extensions", label: "MCP resource or prompt action", kind: .capsule, minWidth: 96))
            }
        }

        if surface.memories.isVisible {
            contracts.append(contract("memories.add", family: .memories, surface: "Memories", label: "Add memory", kind: .formAction, minWidth: 56))
            if surface.memories.items.contains(where: { $0.canEdit }) {
                contracts.append(contract("memories.edit", family: .memories, surface: "Memories", label: "Edit memory", kind: .icon, minWidth: 44))
            }
            if surface.memories.items.contains(where: { $0.canDelete }) {
                contracts.append(contract("memories.delete", family: .memories, surface: "Memories", label: "Forget memory", kind: .icon, minWidth: 44))
            }
        }

        if surface.automations.isVisible {
            if surface.automations.createThreadFollowUpCommand != nil || surface.automations.createWorkspaceScheduleCommand != nil {
                contracts.append(contract("automations.create", family: .automations, surface: "Automations", label: "Create automation", kind: .formAction, minWidth: 90))
            }
            if surface.automations.workflows.contains(where: { $0.runCommandID != nil }) {
                contracts.append(contract("automations.run", family: .automations, surface: "Automations", label: "Run automation", kind: .formAction, minWidth: 56))
            }
            if surface.automations.workflows.contains(where: { $0.primaryCommandID != nil }) {
                contracts.append(contract("automations.primary", family: .automations, surface: "Automations", label: "Pause or resume automation", kind: .formAction, minWidth: 56))
            }
            if surface.automations.workflows.contains(where: { $0.deleteCommandID != nil }) {
                contracts.append(contract("automations.delete", family: .automations, surface: "Automations", label: "Delete automation", kind: .formAction, minWidth: 56))
            }
        }

        if surface.transcript.thinking?.traceLines.isEmpty == false {
            contracts.append(contract("transcript.thinking-trace", family: .transcript, surface: "Transcript", label: "Thinking trace", kind: .capsule, minWidth: 96))
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
            source: source
        )
    }
}
