import Foundation

enum SlashProjectCommandParser {
    private static let usage = "Usage: /project new, /project refresh, /project rename Name, or /project remove"

    static func parse(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let subcommand = parts.first?.lowercased() else {
            return .invalid(usage)
        }

        let value = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch subcommand {
        case "new", "new-chat", "chat":
            return .workspaceCommand("project-new-chat")
        case "refresh", "reload", "context":
            return .workspaceCommand("project-refresh-context")
        case "rename", "title":
            return value.isEmpty ? .invalid("Usage: /project rename Project name") : .renameProject(value)
        case "remove", "forget", "delete":
            return .workspaceCommand("project-remove")
        default:
            return .invalid("Unknown project command '\(subcommand)'. Use new, refresh, rename, or remove.")
        }
    }
}
