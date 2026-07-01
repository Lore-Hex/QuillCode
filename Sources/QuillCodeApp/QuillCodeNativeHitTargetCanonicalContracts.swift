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
                minWidth: 44,
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
                minWidth: 44,
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
                minWidth: 44,
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

    private static func sidebarTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "sidebar.thread-row",
                family: .sidebarThreadList,
                surface: "Sidebar thread list",
                label: "Thread row",
                kind: .fullRow,
                minWidth: nil,
                testID: "sidebar-item"
            ),
            contract(
                "sidebar.thread-action",
                family: .sidebarThreadList,
                surface: "Sidebar thread list",
                label: "Thread row action",
                kind: .icon,
                minWidth: 44,
                testID: "sidebar-thread-action"
            )
        ]
    }

    private static func transcriptTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "transcript.message-action",
                family: .transcript,
                surface: "Transcript",
                label: "Message action",
                kind: .icon,
                minWidth: 44,
                testID: "message-action"
            ),
            contract(
                "transcript.artifact-link",
                family: .transcript,
                surface: "Transcript",
                label: "Artifact link",
                kind: .link,
                minWidth: 96,
                testID: "tool-card-artifact"
            ),
            contract(
                "transcript.tool-card",
                family: .toolCard,
                surface: "Tool card",
                label: "Tool details",
                kind: .fullRow,
                minWidth: nil,
                testID: "tool-card-details"
            ),
            contract(
                "transcript.tool-card-action",
                family: .toolCard,
                surface: "Tool card",
                label: "Tool action",
                kind: .textButton,
                minWidth: 72,
                testID: "tool-card-action"
            ),
            contract(
                "transcript.context-banner-action",
                family: .contextBanner,
                surface: "Context banner",
                label: "Context action",
                kind: .textButton,
                minWidth: 72,
                testID: "context-banner-action"
            )
        ]
    }

    private static func searchTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "command-palette.input",
                family: .commandPalette,
                surface: "Command palette",
                label: "Command search",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .commandPaletteSearch,
                testID: "command-palette-input"
            ),
            contract(
                "command-palette.result",
                family: .commandPalette,
                surface: "Command palette",
                label: "Command result",
                kind: .fullRow,
                minWidth: nil,
                testID: "command-palette-result"
            ),
            contract(
                "search.input",
                family: .search,
                surface: "Search",
                label: "Search chats",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .searchChats,
                testID: "search-input"
            ),
            contract(
                "search.result",
                family: .search,
                surface: "Search",
                label: "Search result",
                kind: .fullRow,
                minWidth: nil,
                testID: "search-result"
            ),
            contract(
                "settings.text-entry",
                family: .settings,
                surface: "Settings",
                label: "Settings text entry",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .settingsTrustedRouterBaseURL,
                testID: "settings-text-entry"
            ),
            contract(
                "settings.action",
                family: .settings,
                surface: "Settings",
                label: "Settings action",
                kind: .formAction,
                minWidth: 72,
                testID: "settings-action"
            ),
            contract(
                "model-picker.search",
                family: .modelPicker,
                surface: "Model picker",
                label: "Model search",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .modelPickerSearch,
                testID: "model-picker-search"
            ),
            contract(
                "model-picker.option",
                family: .modelPicker,
                surface: "Model picker",
                label: "Model option",
                kind: .fullRow,
                minWidth: nil,
                testID: "model-picker-option"
            ),
            contract(
                "model-picker.option-action",
                family: .modelPicker,
                surface: "Model picker",
                label: "Model option action",
                kind: .icon,
                minWidth: 44,
                testID: "model-picker-option-action"
            )
        ]
    }

    private static func reviewTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "review.body",
                family: .review,
                surface: "Review",
                label: "Review body",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .reviewBody,
                testID: "review-body"
            ),
            contract(
                "review.thread-reply",
                family: .review,
                surface: "Review",
                label: "Review thread reply",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .reviewThreadReply,
                testID: "pr-review-thread-reply-input"
            ),
            contract(
                "review.mode",
                family: .review,
                surface: "Review",
                label: "Review mode",
                kind: .segmentedControl,
                minWidth: nil,
                testID: "review-mode"
            ),
            contract(
                "review.file-row",
                family: .review,
                surface: "Review",
                label: "Review file",
                kind: .fullRow,
                minWidth: nil,
                testID: "review-file"
            ),
            contract(
                "review.action",
                family: .review,
                surface: "Review",
                label: "Review action",
                kind: .formAction,
                minWidth: 72,
                testID: "review-action"
            )
        ]
    }

    private static func secondaryPaneTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "secondary-pane.tab",
                family: .secondaryPane,
                surface: "Secondary pane",
                label: "Pane tab",
                kind: .capsule,
                minWidth: 72,
                testID: "secondary-pane-tab"
            )
        ]
    }

    private static func terminalTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "terminal.family-entry",
                family: .terminal,
                surface: "Terminal",
                label: "Terminal command",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .terminalCommand,
                testID: "terminal-command"
            ),
            contract(
                "terminal.family-action",
                family: .terminal,
                surface: "Terminal",
                label: "Terminal action",
                kind: .textButton,
                minWidth: 64,
                testID: "terminal-action"
            )
        ]
    }

    private static func browserTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "browser.family-entry",
                family: .browser,
                surface: "Browser",
                label: "Browser address",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .browserAddress,
                testID: "browser-address"
            ),
            contract(
                "browser.family-action",
                family: .browser,
                surface: "Browser",
                label: "Browser action",
                kind: .textButton,
                minWidth: 64,
                testID: "browser-action"
            ),
            contract(
                "browser.family-icon",
                family: .browser,
                surface: "Browser",
                label: "Browser icon action",
                kind: .icon,
                minWidth: 44,
                testID: "browser-icon-action"
            ),
            contract(
                "browser.comment-entry",
                family: .browser,
                surface: "Browser",
                label: "Browser comment",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .browserComment,
                testID: "browser-comment-input"
            )
        ]
    }

    private static func extensionTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "extensions.family-entry",
                family: .extensions,
                surface: "Extensions",
                label: "Extension action",
                kind: .formAction,
                minWidth: 74,
                testID: "extension-action"
            ),
            contract(
                "extensions.reference-action",
                family: .extensions,
                surface: "Extensions",
                label: "MCP resource or prompt action",
                kind: .capsule,
                minWidth: 96,
                testID: "extension-reference-action"
            )
        ]
    }

    private static func memoryTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "memories.family-entry",
                family: .memories,
                surface: "Memories",
                label: "Add memory",
                kind: .formAction,
                minWidth: 56,
                testID: "memory-add"
            ),
            contract(
                "memories.item-action",
                family: .memories,
                surface: "Memories",
                label: "Memory row action",
                kind: .icon,
                minWidth: 44,
                testID: "memory-row-action"
            )
        ]
    }

    private static func automationTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "automations.family-entry",
                family: .automations,
                surface: "Automations",
                label: "Create automation",
                kind: .formAction,
                minWidth: 90,
                testID: "automation-create"
            )
        ]
    }

    private static func menuBarTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "menu-bar.action",
                family: .menuBar,
                surface: "Menu bar",
                label: "Menu bar action",
                kind: .fullRow,
                minWidth: nil,
                testID: "menu-bar-action"
            )
        ]
    }
}
