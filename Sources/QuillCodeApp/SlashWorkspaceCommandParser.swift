import Foundation

enum SlashWorkspaceCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "browser", "preview",
             "diff", "changes",
             "git-status", "gitstatus",
             "git",
             "init", "init-project",
             "branch", "branches",
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
        case "diff", "changes":
            return .workspaceCommand("git-diff")
        case "git-status", "gitstatus":
            return .workspaceCommand("git-status")
        case "git":
            return SlashGitCommandParser.parse(argument)
        case "init", "init-project":
            return .workspaceCommand("project-init")
        case "branch", "branches":
            return SlashBranchCommandParser.parse(argument)
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
