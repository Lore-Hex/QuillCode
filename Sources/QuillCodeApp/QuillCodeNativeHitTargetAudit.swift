import Foundation

public enum QuillCodeNativeHitTargetKind: String, Codable, Sendable, Hashable, CaseIterable {
    case icon
    case textButton
    case formAction
    case textEntry
    case segmentedControl
    case switchRow
    case fullRow
    case capsule
}

public struct QuillCodeNativeHitTargetContract: Codable, Sendable, Hashable {
    public var id: String
    public var surface: String
    public var label: String
    public var kind: QuillCodeNativeHitTargetKind
    public var minWidth: Double?
    public var minHeight: Double
    public var source: String

    public init(
        id: String,
        surface: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double?,
        minHeight: Double = Double(QuillCodeMetrics.minimumHitTarget),
        source: String
    ) {
        self.id = id
        self.surface = surface
        self.label = label
        self.kind = kind
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.source = source
    }

    public var dictionary: [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "surface": surface,
            "label": label,
            "kind": kind.rawValue,
            "minHeight": minHeight,
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
        return issues
    }
}

public struct QuillCodeNativeHitTargetAuditReport: Codable, Sendable, Hashable {
    public var minimumHitTarget: Double
    public var pressScale: Double
    public var designSystemContracts: [QuillCodeNativeHitTargetContract]
    public var surfaceContracts: [QuillCodeNativeHitTargetContract]
    public var missingDesignKinds: [String]
    public var missingRequiredCommandIDs: [String]
    public var validationIssues: [String]

    public var isValid: Bool {
        missingDesignKinds.isEmpty && missingRequiredCommandIDs.isEmpty && validationIssues.isEmpty
    }

    public var dictionary: [String: Any] {
        [
            "minimumHitTarget": minimumHitTarget,
            "pressScale": pressScale,
            "isValid": isValid,
            "designSystemContracts": designSystemContracts.map(\.dictionary),
            "surfaceContracts": surfaceContracts.map(\.dictionary),
            "missingDesignKinds": missingDesignKinds,
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

    public static var designSystemContracts: [QuillCodeNativeHitTargetContract] {
        [
            contract("design.icon", surface: "Design system", label: "Icon button", kind: .icon, minWidth: 44),
            contract("design.text-button", surface: "Design system", label: "Text button", kind: .textButton, minWidth: 72),
            contract("design.form-action", surface: "Design system", label: "Form action", kind: .formAction, minWidth: 56),
            contract("design.text-entry", surface: "Design system", label: "Text entry", kind: .textEntry, minWidth: nil),
            contract("design.segmented-control", surface: "Design system", label: "Segmented control", kind: .segmentedControl, minWidth: nil),
            contract("design.switch-row", surface: "Design system", label: "Switch row", kind: .switchRow, minWidth: nil),
            contract("design.full-row", surface: "Design system", label: "Full row button", kind: .fullRow, minWidth: nil),
            contract("design.capsule", surface: "Design system", label: "Capsule button", kind: .capsule, minWidth: nil)
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
        let validationIssues = (designContracts + surfaceContracts).flatMap(\.validationIssues)

        return QuillCodeNativeHitTargetAuditReport(
            minimumHitTarget: Double(QuillCodeMetrics.minimumHitTarget),
            pressScale: Double(QuillCodeMetrics.pressScale),
            designSystemContracts: designContracts,
            surfaceContracts: surfaceContracts,
            missingDesignKinds: missingKinds,
            missingRequiredCommandIDs: missingCommandIDs,
            validationIssues: validationIssues
        )
    }

    private static func surfaceContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts = persistentSurfaceContracts()
        contracts.append(contentsOf: commandContracts(from: surface.commands))
        contracts.append(contentsOf: conditionalPaneContracts(for: surface))
        return contracts
    }

    private static func persistentSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract("composer.input", surface: "Composer", label: "Message", kind: .textEntry, minWidth: nil),
            contract("composer.send", surface: "Composer", label: "Send message", kind: .icon, minWidth: 44),
            contract("composer.model-picker", surface: "Composer", label: "Model picker", kind: .capsule, minWidth: nil),
            contract("composer.mode-picker", surface: "Composer", label: "Mode picker", kind: .capsule, minWidth: nil),
            contract("top-bar.overflow", surface: "Top bar", label: "More workspace actions", kind: .icon, minWidth: 44),
            contract("sidebar.tools-menu", surface: "Sidebar", label: "Tools", kind: .fullRow, minWidth: nil)
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
            surface: surface,
            label: command.title,
            kind: kind,
            minWidth: nil,
            source: "WorkspaceCommandSurface"
        )
    }

    private static func conditionalPaneContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts: [QuillCodeNativeHitTargetContract] = []

        if surface.terminal.isVisible {
            contracts.append(contract("terminal.command", surface: "Terminal", label: "Terminal command", kind: .textEntry, minWidth: nil))
            contracts.append(contract("terminal.run", surface: "Terminal", label: surface.terminal.commandActionTitle, kind: .textButton, minWidth: 64))
            contracts.append(contract("terminal.clear", surface: "Terminal", label: "Clear", kind: .textButton, minWidth: 56))
        }

        if surface.browser.isVisible {
            contracts.append(contract("browser.address", surface: "Browser", label: "Browser address", kind: .textEntry, minWidth: nil))
            contracts.append(contract("browser.open", surface: "Browser", label: "Open", kind: .textButton, minWidth: 64))
            contracts.append(contract("browser.new-tab", surface: "Browser", label: "New tab", kind: .icon, minWidth: 44))
            contracts.append(contract("browser.comment", surface: "Browser", label: "Browser comment", kind: .textEntry, minWidth: nil))
            contracts.append(contract("browser.add-comment", surface: "Browser", label: "Add comment", kind: .textButton, minWidth: 92))
        }

        if surface.extensions.isVisible {
            if surface.extensions.items.contains(where: { item in
                item.installCommandID != nil || item.updateCommandID != nil || item.startCommandID != nil || item.stopCommandID != nil
            }) {
                contracts.append(contract("extensions.action", surface: "Extensions", label: "Extension action", kind: .formAction, minWidth: 74))
            }
            if surface.extensions.items.contains(where: { !$0.resourceActions.isEmpty || !$0.promptActions.isEmpty }) {
                contracts.append(contract("extensions.mcp-reference", surface: "Extensions", label: "MCP resource or prompt action", kind: .capsule, minWidth: 96))
            }
        }

        if surface.memories.isVisible {
            contracts.append(contract("memories.add", surface: "Memories", label: "Add memory", kind: .formAction, minWidth: 56))
            if surface.memories.items.contains(where: { $0.canEdit }) {
                contracts.append(contract("memories.edit", surface: "Memories", label: "Edit memory", kind: .icon, minWidth: 44))
            }
            if surface.memories.items.contains(where: { $0.canDelete }) {
                contracts.append(contract("memories.delete", surface: "Memories", label: "Forget memory", kind: .icon, minWidth: 44))
            }
        }

        if surface.automations.isVisible {
            if surface.automations.createThreadFollowUpCommand != nil || surface.automations.createWorkspaceScheduleCommand != nil {
                contracts.append(contract("automations.create", surface: "Automations", label: "Create automation", kind: .formAction, minWidth: 90))
            }
            if surface.automations.workflows.contains(where: { $0.runCommandID != nil }) {
                contracts.append(contract("automations.run", surface: "Automations", label: "Run automation", kind: .formAction, minWidth: 56))
            }
            if surface.automations.workflows.contains(where: { $0.primaryCommandID != nil }) {
                contracts.append(contract("automations.primary", surface: "Automations", label: "Pause or resume automation", kind: .formAction, minWidth: 56))
            }
            if surface.automations.workflows.contains(where: { $0.deleteCommandID != nil }) {
                contracts.append(contract("automations.delete", surface: "Automations", label: "Delete automation", kind: .formAction, minWidth: 56))
            }
        }

        return contracts
    }

    private static func contract(
        _ id: String,
        surface: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double?,
        minHeight: Double = Double(QuillCodeMetrics.minimumHitTarget),
        source: String = "SwiftUI"
    ) -> QuillCodeNativeHitTargetContract {
        QuillCodeNativeHitTargetContract(
            id: id,
            surface: surface,
            label: label,
            kind: kind,
            minWidth: minWidth,
            minHeight: minHeight,
            source: source
        )
    }
}
