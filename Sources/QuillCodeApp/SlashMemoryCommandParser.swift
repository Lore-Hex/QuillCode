import Foundation

enum SlashMemoryCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "memory", "memories", "remember", "remember-edit", "memory-edit",
             "forget", "forget-memory", "remember-delete", "memory-delete":
            return true
        default:
            return false
        }
    }

    static func parse(name: String, argument: String) -> SlashCommand {
        let command = normalizedName(name)
        let value = argument.trimmingCharacters(in: .whitespacesAndNewlines)

        switch command {
        case "memory", "memories":
            return .workspaceCommand("toggle-memories")
        case "remember":
            return value.isEmpty ? .workspaceCommand("toggle-memories") : .remember(value)
        case "remember-edit", "memory-edit":
            return parseEdit(value)
        case "forget", "forget-memory", "remember-delete", "memory-delete":
            return parseDelete(value)
        default:
            return .unknown(command)
        }
    }

    private static func parseEdit(_ value: String) -> SlashCommand {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let firstNewline = normalized.firstIndex(of: "\n") else {
            return .invalid("Use `/remember-edit memory-id` followed by the revised memory on the next line.")
        }
        let id = String(normalized[..<firstNewline]).trimmingCharacters(in: .whitespacesAndNewlines)
        let content = String(normalized[normalized.index(after: firstNewline)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !content.isEmpty else {
            return .invalid("Use `/remember-edit memory-id` followed by the revised memory on the next line.")
        }
        return .editMemory(id: id, content: content)
    }

    private static func parseDelete(_ value: String) -> SlashCommand {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return .invalid("Use `/forget memory-id` to remove a memory.")
        }
        return .deleteMemory(id: id)
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
