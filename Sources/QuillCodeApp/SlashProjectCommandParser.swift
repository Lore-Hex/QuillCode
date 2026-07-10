import Foundation

enum SlashProjectCommandParser {
    private static let usage = """
    Usage: /project open, /project new, /project refresh, /project init, /project top, \
    /project up, /project down, /project bottom, /project list, /project rename Name, or /project remove
    """

    static func parse(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let subcommand = parts.first?.lowercased() else {
            return .invalid(usage)
        }

        let value = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch subcommand {
        case "open", "add":
            return .workspaceCommand("add-project")
        case "list", "ls", "show":
            return .projectList
        case "new", "new-chat", "chat":
            return .workspaceCommand("project-new-chat")
        case "refresh", "reload", "context":
            return .workspaceCommand("project-refresh-context")
        case "init", "initialize", "agents", "agents.md":
            return .workspaceCommand("project-init")
        case "top", "move-top", "move-to-top":
            return .workspaceCommand("project-move-to-top")
        case "up", "move-up":
            return .workspaceCommand("project-move-up")
        case "down", "move-down":
            return .workspaceCommand("project-move-down")
        case "bottom", "move-bottom", "move-to-bottom":
            return .workspaceCommand("project-move-to-bottom")
        case "rename", "title":
            return value.isEmpty ? .invalid("Usage: /project rename Project name") : .renameProject(value)
        case "remove", "forget", "delete":
            return .workspaceCommand("project-remove")
        default:
            return .invalid(
                "Unknown project command '\(subcommand)'. Use open, new, refresh, init, top, up, down, bottom, list, rename, or remove."
            )
        }
    }
}
