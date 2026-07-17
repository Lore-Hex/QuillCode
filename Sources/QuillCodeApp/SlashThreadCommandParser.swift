import Foundation

enum SlashThreadCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case let confidential where WorkspaceConfidentialSlash.aliases.contains(confidential):
            return true
        case "new", "new-chat", "newchat",
             "clear", "clear-chat", "reset-chat",
             "undo", "revert", "revert-latest", "undo-edit",
             "compact", "compact-context", "context-compact",
             "rename", "rename-chat", "title",
             "duplicate", "duplicate-chat", "copy-chat",
             "new-worktree", "worktree-chat", "worktree-thread",
             "fork", "fork-last", "fork-from-last",
             "fork-summary", "fork-with-summary",
             "fork-full", "fork-full-context",
             "pin", "pin-chat",
             "unpin", "unpin-chat",
             "archive", "archive-chat",
             "unarchive", "unarchive-chat",
             "delete", "delete-chat", "remove-chat":
            return true
        default:
            return false
        }
    }

    static func parse(name: String, argument: String) -> SlashCommand {
        let command = normalizedName(name)
        let value = argument.trimmingCharacters(in: .whitespacesAndNewlines)

        switch command {
        case "new", "new-chat", "newchat":
            return .newChat
        case let confidential where WorkspaceConfidentialSlash.aliases.contains(confidential):
            return .workspaceCommand("new-confidential-chat")
        case "clear", "clear-chat", "reset-chat":
            return .workspaceCommand("thread-clear")
        case "undo", "revert", "revert-latest", "undo-edit":
            return .workspaceCommand("thread-revert-latest")
        case "compact", "compact-context", "context-compact":
            return .workspaceCommand("compact-context")
        case "rename", "rename-chat", "title":
            return value.isEmpty ? .invalid("Usage: /rename New chat title") : .renameThread(value)
        case "duplicate", "duplicate-chat", "copy-chat":
            return .workspaceCommand("thread-duplicate")
        case "new-worktree", "worktree-chat", "worktree-thread":
            return .workspaceCommand("thread-new-worktree")
        case "fork":
            return parseFork(argument: value)
        case "fork-last", "fork-from-last":
            return .workspaceCommand("fork-from-last")
        case "fork-summary", "fork-with-summary":
            return .workspaceCommand("fork-with-summary")
        case "fork-full", "fork-full-context":
            return .workspaceCommand("fork-full-context")
        case "pin", "pin-chat":
            return .workspaceCommand("thread-pin")
        case "unpin", "unpin-chat":
            return .workspaceCommand("thread-unpin")
        case "archive", "archive-chat":
            return .workspaceCommand("thread-archive")
        case "unarchive", "unarchive-chat":
            return .workspaceCommand("thread-unarchive")
        case "delete", "delete-chat", "remove-chat":
            return .workspaceCommand("thread-delete")
        default:
            return .unknown(command)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func parseFork(argument: String) -> SlashCommand {
        switch normalizedName(argument) {
        case "", "last", "latest", "latest-turn", "from-last":
            return .workspaceCommand("fork-from-last")
        case "summary", "summarized", "summarized-context", "compact":
            return .workspaceCommand("fork-with-summary")
        case "full", "full-context", "all":
            return .workspaceCommand("fork-full-context")
        default:
            return .invalid("Usage: /fork [last|summary|full]")
        }
    }
}
