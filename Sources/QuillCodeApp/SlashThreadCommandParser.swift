import Foundation

enum SlashThreadCommandParser {
    static func parse(name: String, argument: String) -> SlashCommand? {
        switch name {
        case "new", "new-chat", "newchat":
            return .newChat
        case "compact", "compact-context", "context-compact":
            return .workspaceCommand("compact-context")
        case "rename", "rename-chat", "title":
            return parseRename(argument)
        case "duplicate", "duplicate-chat", "copy-chat":
            return .workspaceCommand("thread-duplicate")
        case "archive", "archive-chat":
            return .workspaceCommand("thread-archive")
        case "unarchive", "unarchive-chat":
            return .workspaceCommand("thread-unarchive")
        default:
            return nil
        }
    }

    private static func parseRename(_ argument: String) -> SlashCommand {
        argument.isEmpty
            ? .invalid("Usage: /rename New chat title")
            : .renameThread(argument)
    }
}
