import Foundation

enum SlashMemoryCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "memory", "memories", "remember":
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
        default:
            return .unknown(command)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
