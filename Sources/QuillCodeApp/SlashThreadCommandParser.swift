import Foundation

enum SlashThreadCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "new", "new-chat", "newchat",
             "clear", "clear-chat", "reset-chat",
             "undo", "revert", "revert-latest", "undo-edit",
             "compact", "compact-context", "context-compact",
             "rename", "rename-chat", "title",
             "duplicate", "duplicate-chat", "copy-chat",
             "archive", "archive-chat",
             "unarchive", "unarchive-chat":
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
        case "archive", "archive-chat":
            return .workspaceCommand("thread-archive")
        case "unarchive", "unarchive-chat":
            return .workspaceCommand("thread-unarchive")
        default:
            return .unknown(command)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
