import Foundation

enum SlashWorkspaceCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "stop", "cancel", "abort",
             "retry", "rerun", "again",
             "back", "previous", "prev",
             "forward", "next",
             "search", "find",
             "focus", "composer", "input",
             "sidebar", "toggle-sidebar",
             "copy", "copy-conversation",
             "export", "export-markdown", "export-conversation-markdown",
             "settings", "preferences", "prefs",
             "shortcuts", "keyboard-shortcuts", "keys",
             "commands", "command-palette", "palette",
             "extensions", "plugins", "skills",
             "automations", "activity",
             "browser", "preview",
             "review", "diff", "changes",
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
        case "stop", "cancel", "abort":
            return .workspaceCommand("stop-all")
        case "retry", "rerun", "again":
            return .workspaceCommand("retry-last-turn")
        case "back", "previous", "prev":
            return .workspaceCommand("workspace-back")
        case "forward", "next":
            return .workspaceCommand("workspace-forward")
        case "focus", "composer", "input":
            return .workspaceCommand("focus-composer")
        case "sidebar", "toggle-sidebar":
            return .workspaceCommand("toggle-sidebar")
        case "copy", "copy-conversation":
            return .workspaceCommand("copy-conversation")
        case "export", "export-markdown", "export-conversation-markdown":
            return .workspaceCommand("export-conversation-markdown")
        case "search":
            return .workspaceCommand("search")
        case "find":
            return .workspaceCommand("find-in-chat")
        case "settings", "preferences", "prefs":
            return .workspaceCommand("settings")
        case "shortcuts", "keyboard-shortcuts", "keys":
            return .workspaceCommand("keyboard-shortcuts")
        case "commands", "command-palette", "palette":
            return .workspaceCommand("command-palette")
        case "extensions", "plugins", "skills":
            return .workspaceCommand("toggle-extensions")
        case "automations":
            return .workspaceCommand("toggle-automations")
        case "activity":
            return .workspaceCommand("toggle-activity")
        case "browser", "preview":
            return .workspaceCommand("toggle-browser")
        case "review", "diff", "changes":
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
