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
        switch commandID {
        case "new-chat":
            return "New chat"
        case "search":
            return "Search"
        case "toggle-extensions":
            return "Plugins"
        case "toggle-automations":
            return "Automations"
        case "toggle-terminal":
            return "Terminal"
        case "toggle-browser":
            return "Browser"
        case "toggle-memories":
            return "Memories"
        case "toggle-activity":
            return "Activity"
        case "command-palette":
            return "Command palette"
        case "settings":
            return "Settings"
        default:
            return fallback
        }
    }

    static func systemImage(for commandID: String) -> String {
        switch commandID {
        case "new-chat":
            return "square.and.pencil"
        case "search":
            return "magnifyingglass"
        case "toggle-extensions":
            return "puzzlepiece.extension"
        case "toggle-automations":
            return "clock.arrow.circlepath"
        case "toggle-terminal":
            return "terminal"
        case "terminal-clear":
            return "clear"
        case "toggle-browser":
            return "globe"
        case "toggle-memories":
            return "brain.head.profile"
        case "toggle-activity":
            return "waveform.path.ecg"
        case "command-palette":
            return "command"
        case "settings":
            return "gearshape"
        default:
            return "circle"
        }
    }

    static func htmlIconToken(for commandID: String) -> String {
        switch commandID {
        case "new-chat":
            return "new"
        case "search":
            return "search"
        case "command-palette":
            return "command"
        case "toggle-extensions":
            return "plugins"
        case "toggle-automations":
            return "automations"
        case "toggle-terminal":
            return "terminal"
        case "toggle-browser":
            return "browser"
        case "toggle-memories":
            return "memories"
        case "toggle-activity":
            return "activity"
        default:
            return "command"
        }
    }

    static func htmlTestID(for commandID: String) -> String {
        switch commandID {
        case "new-chat":
            return "new-chat-button"
        case "search":
            return "sidebar-search-button"
        case "toggle-extensions":
            return "extensions-button"
        case "toggle-automations":
            return "automations-button"
        case "toggle-terminal":
            return "terminal-button"
        case "toggle-browser":
            return "browser-button"
        case "toggle-memories":
            return "memories-button"
        case "toggle-activity":
            return "activity-button"
        case "command-palette":
            return "command-palette-button"
        default:
            return "sidebar-command-button"
        }
    }
}
