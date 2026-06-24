import Foundation

enum SlashEnvironmentCommandParser {
    static func supports(_ name: String) -> Bool {
        switch normalizedName(name) {
        case "env", "environment", "local-env":
            return true
        default:
            return false
        }
    }

    static func parse(_ argument: String) -> SlashCommand {
        let value = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        return .environmentAction(value.isEmpty ? nil : value)
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
