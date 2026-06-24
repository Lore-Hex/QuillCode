struct QuillCodeSidebarCommandGroup: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var commandIDs: [String]
}

struct QuillCodeSidebarVisibleCommandGroup: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var commands: [WorkspaceCommandSurface]
}

private struct QuillCodeSidebarCommandMetadata: Sendable, Hashable {
    var title: String
    var htmlIconToken: String
    var htmlTestID: String
    var systemImageOverride: String?

    init(
        title: String,
        htmlIconToken: String = "command",
        htmlTestID: String = "sidebar-command-button",
        systemImageOverride: String? = nil
    ) {
        self.title = title
        self.htmlIconToken = htmlIconToken
        self.htmlTestID = htmlTestID
        self.systemImageOverride = systemImageOverride
    }
}

struct QuillCodeSidebarCommandPresentation: Sendable, Hashable {
    static let primaryCommandIDs = [
        "new-chat"
    ]

    static let utilityCommandGroups = [
        QuillCodeSidebarCommandGroup(
            id: "navigate",
            title: "Navigate",
            commandIDs: [
                "search",
                "command-palette"
            ]
        ),
        QuillCodeSidebarCommandGroup(
            id: "extensions",
            title: "Extensions",
            commandIDs: [
                "toggle-extensions"
            ]
        ),
        QuillCodeSidebarCommandGroup(
            id: "automate",
            title: "Automate",
            commandIDs: [
                "toggle-automations"
            ]
        ),
        QuillCodeSidebarCommandGroup(
            id: "workspace",
            title: "Workspace",
            commandIDs: [
                "toggle-terminal",
                "toggle-browser"
            ]
        ),
        QuillCodeSidebarCommandGroup(
            id: "context",
            title: "Context",
            commandIDs: [
                "toggle-memories",
                "toggle-activity"
            ]
        )
    ]

    static var utilityCommandIDs: [String] {
        utilityCommandGroups.flatMap(\.commandIDs)
    }

    private static let metadataByCommandID: [String: QuillCodeSidebarCommandMetadata] = [
        "new-chat": QuillCodeSidebarCommandMetadata(
            title: "New chat",
            htmlIconToken: "new",
            htmlTestID: "new-chat-button"
        ),
        "search": QuillCodeSidebarCommandMetadata(
            title: "Search",
            htmlIconToken: "search",
            htmlTestID: "sidebar-search-button"
        ),
        "command-palette": QuillCodeSidebarCommandMetadata(
            title: "Command palette",
            htmlIconToken: "command",
            htmlTestID: "command-palette-button"
        ),
        "toggle-extensions": QuillCodeSidebarCommandMetadata(
            title: "Plugins",
            htmlIconToken: "plugins",
            htmlTestID: "extensions-button"
        ),
        "toggle-automations": QuillCodeSidebarCommandMetadata(
            title: "Automations",
            htmlIconToken: "automations",
            htmlTestID: "automations-button"
        ),
        "toggle-terminal": QuillCodeSidebarCommandMetadata(
            title: "Terminal",
            htmlIconToken: "terminal",
            htmlTestID: "terminal-button"
        ),
        "toggle-browser": QuillCodeSidebarCommandMetadata(
            title: "Browser",
            htmlIconToken: "browser",
            htmlTestID: "browser-button"
        ),
        "toggle-memories": QuillCodeSidebarCommandMetadata(
            title: "Memories",
            htmlIconToken: "memories",
            htmlTestID: "memories-button"
        ),
        "toggle-activity": QuillCodeSidebarCommandMetadata(
            title: "Activity",
            htmlIconToken: "activity",
            htmlTestID: "activity-button",
            systemImageOverride: "waveform.path.ecg"
        ),
        "settings": QuillCodeSidebarCommandMetadata(title: "Settings")
    ]

    static func visibleUtilityCommandGroups(
        from commands: [WorkspaceCommandSurface]
    ) -> [QuillCodeSidebarVisibleCommandGroup] {
        utilityCommandGroups.compactMap { group in
            let visibleCommands = group.commandIDs.compactMap { commandID in
                commands.first { $0.id == commandID }
            }
            guard !visibleCommands.isEmpty else { return nil }
            return QuillCodeSidebarVisibleCommandGroup(
                id: group.id,
                title: group.title,
                commands: visibleCommands
            )
        }
    }

    static func displayTitle(for command: WorkspaceCommandSurface) -> String {
        displayTitle(command.id, fallback: command.title)
    }

    static func displayTitle(_ commandID: String, fallback: String) -> String {
        metadataByCommandID[commandID]?.title ?? fallback
    }

    static func systemImage(for commandID: String) -> String {
        if let override = metadataByCommandID[commandID]?.systemImageOverride {
            return override
        }
        return QuillCodeCommandIconCatalog.systemImage(for: commandID, fallback: "circle")
    }

    static func htmlIconToken(for commandID: String) -> String {
        metadataByCommandID[commandID]?.htmlIconToken ?? "command"
    }

    static func htmlTestID(for commandID: String) -> String {
        metadataByCommandID[commandID]?.htmlTestID ?? "sidebar-command-button"
    }
}
