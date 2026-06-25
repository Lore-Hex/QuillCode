import Foundation

enum SlashWorkspaceCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "browser", "preview",
             "worktree", "worktrees", "wt":
            return true
        default:
            return false
        }
    }

    static func parse(name: String, argument: String = "") -> SlashCommand {
        switch normalizedName(name) {
        case "browser", "preview":
            return .workspaceCommand("toggle-browser")
        case "worktree", "worktrees", "wt":
            return SlashWorktreeCommandParser.parse(argument)
        default:
            return .unknown(normalizedName(name))
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
