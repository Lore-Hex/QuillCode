import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func conditionalPaneContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts: [QuillCodeNativeHitTargetContract] = []
        contracts.append(contentsOf: terminalContracts(for: surface.terminal))
        contracts.append(contentsOf: browserContracts(for: surface.browser))
        contracts.append(contentsOf: extensionContracts(for: surface.extensions))
        contracts.append(contentsOf: memoryContracts(for: surface.memories))
        contracts.append(contentsOf: automationContracts(for: surface.automations))
        contracts.append(contentsOf: transcriptContracts(for: surface.transcript))
        return contracts
    }

    private static func terminalContracts(
        for surface: TerminalSurface
    ) -> [QuillCodeNativeHitTargetContract] {
        guard surface.isVisible else { return [] }
        return [
            contract(
                "terminal.command",
                family: .terminal,
                surface: "Terminal",
                label: "Terminal command",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .terminalCommand,
                testID: "terminal-command"
            ),
            contract(
                "terminal.run",
                family: .terminal,
                surface: "Terminal",
                label: surface.commandActionTitle,
                kind: .textButton,
                minWidth: 64,
                testID: "terminal-run"
            ),
            contract(
                "terminal.clear",
                family: .terminal,
                surface: "Terminal",
                label: "Clear",
                kind: .textButton,
                minWidth: 56,
                testID: "terminal-clear"
            )
        ]
    }

    private static func browserContracts(
        for surface: BrowserSurface
    ) -> [QuillCodeNativeHitTargetContract] {
        guard surface.isVisible else { return [] }
        return [
            contract(
                "browser.address",
                family: .browser,
                surface: "Browser",
                label: "Browser address",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .browserAddress,
                testID: "browser-address"
            ),
            contract(
                "browser.open",
                family: .browser,
                surface: "Browser",
                label: "Open",
                kind: .textButton,
                minWidth: 64,
                testID: "browser-open"
            ),
            contract(
                "browser.new-tab",
                family: .browser,
                surface: "Browser",
                label: "New tab",
                kind: .icon,
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                testID: "browser-new-tab"
            ),
            contract(
                "browser.comment",
                family: .browser,
                surface: "Browser",
                label: "Browser comment",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .browserComment,
                testID: "browser-comment-input"
            ),
            contract(
                "browser.add-comment",
                family: .browser,
                surface: "Browser",
                label: "Add comment",
                kind: .textButton,
                minWidth: 92,
                testID: "browser-add-comment"
            )
        ]
    }

    private static func extensionContracts(
        for surface: WorkspaceExtensionsSurface
    ) -> [QuillCodeNativeHitTargetContract] {
        guard surface.isVisible else { return [] }

        var contracts: [QuillCodeNativeHitTargetContract] = []
        if surface.items.contains(where: hasExtensionLifecycleAction) {
            contracts.append(
                contract(
                    "extensions.action",
                    family: .extensions,
                    surface: "Extensions",
                    label: "Extension action",
                    kind: .formAction,
                    minWidth: 74,
                    testID: "extension-action"
                )
            )
        }
        if surface.items.contains(where: hasExtensionReferenceAction) {
            contracts.append(
                contract(
                    "extensions.mcp-reference",
                    family: .extensions,
                    surface: "Extensions",
                    label: "MCP resource or prompt action",
                    kind: .capsule,
                    minWidth: 96,
                    testID: "extension-reference-action"
                )
            )
        }
        return contracts
    }

    private static func memoryContracts(
        for surface: WorkspaceMemoriesSurface
    ) -> [QuillCodeNativeHitTargetContract] {
        guard surface.isVisible else { return [] }

        var contracts = [
            contract(
                "memories.add",
                family: .memories,
                surface: "Memories",
                label: "Add memory",
                kind: .formAction,
                minWidth: 56,
                testID: "memory-add"
            )
        ]
        if surface.items.contains(where: { $0.canEdit }) {
            contracts.append(
                contract(
                    "memories.edit",
                    family: .memories,
                    surface: "Memories",
                    label: "Edit memory",
                    kind: .icon,
                    minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                    testID: "memory-edit"
                )
            )
        }
        if surface.items.contains(where: { $0.canDelete }) {
            contracts.append(
                contract(
                    "memories.delete",
                    family: .memories,
                    surface: "Memories",
                    label: "Forget memory",
                    kind: .icon,
                    minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                    testID: "memory-delete"
                )
            )
        }
        if !surface.conflicts.isEmpty {
            contracts.append(
                contract(
                    "memories.conflict-edit",
                    family: .memories,
                    surface: "Memories",
                    label: "Edit conflicting memory",
                    kind: .formAction,
                    minWidth: 112,
                    testID: "memory-conflict-edit"
                )
            )
        }
        if !surface.redactionReviews.isEmpty {
            contracts.append(
                contract(
                    "memories.redaction-add",
                    family: .memories,
                    surface: "Memories",
                    label: "Add safe memory",
                    kind: .formAction,
                    minWidth: 112,
                    testID: "memory-redaction-add"
                )
            )
        }
        return contracts
    }

    private static func automationContracts(
        for surface: WorkspaceAutomationsSurface
    ) -> [QuillCodeNativeHitTargetContract] {
        guard surface.isVisible else { return [] }

        var contracts: [QuillCodeNativeHitTargetContract] = []
        if surface.createThreadFollowUpCommand != nil
            || surface.createWorkspaceScheduleCommand != nil
            || surface.createMonitorCommand != nil {
            contracts.append(
                contract(
                    "automations.create",
                    family: .automations,
                    surface: "Automations",
                    label: "Create automation",
                    kind: .formAction,
                    minWidth: 90,
                    testID: "automation-create"
                )
            )
        }
        if surface.workflows.contains(where: { $0.runCommandID != nil }) {
            contracts.append(
                automationWorkflowContract(
                    "automations.run",
                    label: "Run automation",
                    testID: "automation-run"
                )
            )
        }
        if surface.workflows.contains(where: { $0.primaryCommandID != nil }) {
            contracts.append(
                automationWorkflowContract(
                    "automations.primary",
                    label: "Pause or resume automation",
                    testID: "automation-primary-action"
                )
            )
        }
        if surface.workflows.contains(where: { $0.deleteCommandID != nil }) {
            contracts.append(
                automationWorkflowContract(
                    "automations.delete",
                    label: "Delete automation",
                    testID: "automation-delete"
                )
            )
        }
        return contracts
    }

    private static func transcriptContracts(
        for surface: TranscriptSurface
    ) -> [QuillCodeNativeHitTargetContract] {
        guard surface.thinking?.traceLines.isEmpty == false else { return [] }
        return [
            contract(
                "transcript.thinking-trace",
                family: .transcript,
                surface: "Transcript",
                label: "Thinking trace",
                kind: .capsule,
                minWidth: 96,
                testID: "thinking-trace"
            )
        ]
    }

    private static func automationWorkflowContract(
        _ id: String,
        label: String,
        testID: String
    ) -> QuillCodeNativeHitTargetContract {
        contract(
            id,
            family: .automations,
            surface: "Automations",
            label: label,
            kind: .formAction,
            minWidth: 56,
            testID: testID
        )
    }

    private static func hasExtensionLifecycleAction(_ item: ProjectExtensionManifestSurface) -> Bool {
        item.installCommandID != nil
            || item.updateCommandID != nil
            || item.startCommandID != nil
            || item.stopCommandID != nil
    }

    private static func hasExtensionReferenceAction(_ item: ProjectExtensionManifestSurface) -> Bool {
        !item.resourceActions.isEmpty || !item.promptActions.isEmpty
    }
}
