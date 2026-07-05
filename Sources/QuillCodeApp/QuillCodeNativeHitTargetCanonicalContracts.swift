import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func persistentSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "composer.input",
                family: .composer,
                surface: "Composer",
                label: "Message",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .composerMessage,
                testID: "composer-input"
            ),
            contract(
                "composer.send",
                family: .composer,
                surface: "Composer",
                label: "Send message",
                kind: .icon,
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                testID: "send-button"
            ),
            contract(
                "composer.model-picker",
                family: .composer,
                surface: "Composer",
                label: "Model picker",
                kind: .capsule,
                minWidth: nil,
                testID: "model-picker-button"
            ),
            contract(
                "composer.mode-picker",
                family: .composer,
                surface: "Composer",
                label: "Mode picker",
                kind: .capsule,
                minWidth: nil,
                testID: "mode-picker-button"
            ),
            contract(
                "top-bar.overflow",
                family: .topBar,
                surface: "Top bar",
                label: "More workspace actions",
                kind: .icon,
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                testID: "top-bar-overflow"
            ),
            contract(
                "sidebar.tools-menu",
                family: .sidebar,
                surface: "Sidebar",
                label: "Tools",
                kind: .fullRow,
                minWidth: nil,
                testID: "sidebar-tools-button"
            ),
            contract(
                "project.clear",
                family: .sidebar,
                surface: "Project header",
                label: "Clear project",
                kind: .icon,
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                testID: "project-clear-button"
            ),
            contract(
                "workspace.chrome",
                family: .workspaceChrome,
                surface: "Workspace chrome",
                label: "Workspace command",
                kind: .fullRow,
                minWidth: nil,
                testID: "workspace-command"
            )
        ]
    }

    static func canonicalTransientSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        sidebarTransientContracts()
            + transcriptTransientContracts()
            + searchTransientContracts()
            + reviewTransientContracts()
            + secondaryPaneTransientContracts()
            + terminalTransientContracts()
            + browserTransientContracts()
            + extensionTransientContracts()
            + memoryTransientContracts()
            + automationTransientContracts()
            + menuBarTransientContracts()
    }
}
