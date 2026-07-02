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
        guard let command = value.firstTokenSplit else {
            return .environmentAction(nil)
        }

        if command.token.caseInsensitiveCompare("schedule") == .orderedSame {
            let trimmed = command.remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .invalid("Usage: /env schedule Action name in 30 minutes")
            }
            return .environmentSchedule(trimmed)
        }

        return .environmentAction(value)
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    var firstTokenSplit: (token: String, remainder: String)? {
        guard let tokenRange = rangeOfNonWhitespace else { return nil }
        let token = String(self[tokenRange])
        let remainder = String(self[tokenRange.upperBound...])
        return (token, remainder)
    }

    private var rangeOfNonWhitespace: Range<String.Index>? {
        guard let start = firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let end = self[start...].firstIndex(where: \.isWhitespace) ?? endIndex
        return start..<end
    }
}
