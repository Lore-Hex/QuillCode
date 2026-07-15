import Foundation

enum SlashWorkspaceCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "stop", "cancel", "abort",
             "retry", "rerun", "again",
             "disconnect", "disconnect-all",
             "back", "previous", "prev",
             "forward", "next",
             "history",
             "search", "find",
             "focus", "composer", "input",
             "sidebar", "toggle-sidebar",
             "copy", "copy-conversation",
             "export", "export-markdown", "export-conversation-markdown",
             "settings", "preferences", "prefs",
             "computer-use",
             "shortcuts", "keyboard-shortcuts", "keys",
             "commands", "command-palette", "palette",
             "extensions", "plugins", "skills", "hooks",
             "automations", "activity",
             "browser", "preview", "browser-session", "session",
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
        case "disconnect", "disconnect-all":
            return .workspaceCommand("disconnect-all")
        case "back", "previous", "prev":
            return .workspaceCommand("workspace-back")
        case "forward", "next":
            return .workspaceCommand("workspace-forward")
        case "history":
            return parseHistory(argument)
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
        case "computer-use":
            return .workspaceCommand("computer-use-setup")
        case "shortcuts", "keyboard-shortcuts", "keys":
            return .workspaceCommand("keyboard-shortcuts")
        case "commands", "command-palette", "palette":
            return .workspaceCommand("command-palette")
        case "extensions", "plugins":
            return .workspaceCommand("toggle-extensions")
        case "skills":
            return .workspaceCommand("show-skills")
        case "hooks":
            return .workspaceCommand("show-hooks")
        case "automations":
            return .workspaceCommand("toggle-automations")
        case "activity":
            return .workspaceCommand("toggle-activity")
        case "browser", "preview":
            return parseBrowser(argument)
        case "browser-session", "session":
            return parseBrowserSession(argument)
        case "review":
            return .workspaceCommand("code-review")
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

    private static func parseHistory(_ argument: String) -> SlashCommand {
        switch normalizedName(argument) {
        case "back", "previous", "prev":
            return .workspaceCommand("workspace-back")
        case "forward", "next":
            return .workspaceCommand("workspace-forward")
        default:
            return .invalid("Try /history back or /history forward.")
        }
    }

    private static func parseBrowser(_ argument: String) -> SlashCommand {
        let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return .workspaceCommand("toggle-browser")
        }
        return .browserOpen(target)
    }

    private static func parseBrowserSession(_ argument: String) -> SlashCommand {
        let target = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        return .browserSession(target.isEmpty ? nil : target)
    }
}
