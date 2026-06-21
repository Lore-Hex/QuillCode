import Foundation
import QuillCodeCore

enum SlashCommand: Equatable {
    case help
    case status
    case newChat
    case mode(AgentMode)
    case model(String)
    case workspaceCommand(String)
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
        case "terminal", "term", "shell":
            return .workspaceCommand("toggle-terminal")
        case "browser", "preview":
            return .workspaceCommand("toggle-browser")
        case "memory", "memories", "remember":
            return .workspaceCommand("toggle-memories")
        case "worktree", "worktrees", "wt":
            return .workspaceCommand("git-worktree-list")
        case "pr", "pull-request", "pullrequest":
            return .workspaceCommand("git-pr-create")
        case "env", "environment", "local-env":
            return .environmentAction(argument.isEmpty ? nil : argument)
        case "mode":
            return parseMode(argument)
        case "model":
            guard !argument.isEmpty else {
                return .invalid("Usage: /model provider/model")
            }
            return .model(argument)
        default:
            return .unknown(name)
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
