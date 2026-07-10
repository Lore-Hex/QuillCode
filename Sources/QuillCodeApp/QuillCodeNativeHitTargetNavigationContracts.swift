import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func sidebarTransientContracts() -> [QuillCodeNativeHitTargetContract] {
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
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                testID: "sidebar-thread-action"
            )
        ]
    }

    static func transcriptTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "transcript.message-action",
                family: .transcript,
                surface: "Transcript",
                label: "Message action",
                kind: .icon,
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
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

    static func searchTransientContracts() -> [QuillCodeNativeHitTargetContract] {
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
                "shortcuts.search",
                family: .search,
                surface: "Keyboard shortcuts",
                label: "Search shortcuts",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .shortcutsSearch,
                testID: "quillcode-shortcuts-search-input"
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
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                testID: "model-picker-option-action"
            )
        ]
    }
}
