import Foundation
import QuillCodeCore

enum SlashCommand: Equatable {
    case help
    case status
    case newChat
    case mode(AgentMode)
    case model(String)
    case renameThread(String)
    case renameProject(String)
    case sshProject(String)
    case remember(String)
    case threadFollowUp(String)
    case workspaceSchedule(String)
    case workspaceCommand(String)
    case toolCall(ToolCall)
    case environmentAction(String?)
    case invalid(String)
    case unknown(String)
}

enum SlashCommandParser {
    static func parse(_ input: String) -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let commandText = String(trimmed.dropFirst())
        let parts = commandText.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let name = parts.first?.lowercased() else {
            return .help
        }
        let argument = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch name {
        case "?", "help":
            return .help
        case "status":
            return .status
        case "new", "new-chat", "newchat":
            return .newChat
        case "compact", "compact-context", "context-compact":
            return .workspaceCommand("compact-context")
        case "follow-up", "followup", "schedule", "remind":
            return argument.isEmpty
                ? .invalid("Usage: /follow-up in 30 minutes, /follow-up tomorrow at 9 AM, or /follow-up daily")
                : .threadFollowUp(argument)
        case "workspace-check", "workspacecheck", "workspace-schedule", "project-check", "repo-check":
            return argument.isEmpty
                ? .invalid("Usage: /workspace-check in 1 hour, /workspace-check tomorrow at 9 AM, or /workspace-check every 2 hours")
                : .workspaceSchedule(argument)
        case "rename", "rename-chat", "title":
            return argument.isEmpty ? .invalid("Usage: /rename New chat title") : .renameThread(argument)
        case "duplicate", "duplicate-chat", "copy-chat":
            return .workspaceCommand("thread-duplicate")
        case "archive", "archive-chat":
            return .workspaceCommand("thread-archive")
        case "unarchive", "unarchive-chat":
            return .workspaceCommand("thread-unarchive")
        case "project":
            return SlashProjectCommandParser.parse(argument)
        case "ssh", "remote":
            return argument.isEmpty ? .invalid("Usage: /ssh user@host:/absolute/path") : .sshProject(argument)
        case "terminal", "term", "shell":
            return parseTerminal(argument)
        case "browser", "preview":
            return .workspaceCommand("toggle-browser")
        case "memory", "memories":
            return .workspaceCommand("toggle-memories")
        case "remember":
            return argument.isEmpty ? .workspaceCommand("toggle-memories") : .remember(argument)
        case "worktree", "worktrees", "wt":
            return .workspaceCommand("git-worktree-list")
        case "pr", "pull-request", "pullrequest":
            return SlashPullRequestCommandParser.parse(argument)
        case "env", "environment", "local-env":
            return .environmentAction(argument.isEmpty ? nil : argument)
        case "mode":
            return parseMode(argument)
        case "model":
            guard !argument.isEmpty else {
                return .invalid("Usage: /model /synth or /model provider/model")
            }
            return .model(argument)
        default:
            return .unknown(name)
        }
    }

    private static func parseTerminal(_ argument: String) -> SlashCommand {
        guard !argument.isEmpty else {
            return .workspaceCommand("toggle-terminal")
        }
        switch argument.lowercased() {
        case "clear", "reset":
            return .workspaceCommand("terminal-clear")
        default:
            return .invalid("Usage: /terminal or /terminal clear")
        }
    }

    private static func parseMode(_ argument: String) -> SlashCommand {
        switch argument.lowercased() {
        case "auto":
            return .mode(.auto)
        case "review":
            return .mode(.review)
        case "read-only", "readonly", "read_only":
            return .mode(.readOnly)
        case "":
            return .invalid("Usage: /mode auto, /mode review, or /mode read-only")
        default:
            return .invalid("Unknown mode '\(argument)'. Use auto, review, or read-only.")
        }
    }
}
