enum SlashEnvironmentCommandParser {
    private static let aliases: Set<String> = [
        "env",
        "environment",
        "local-env"
    ]

    static func supports(_ command: String) -> Bool {
        aliases.contains(command)
    }

    static func parse(_ argument: String) -> SlashCommand {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        return .environmentAction(trimmed.isEmpty ? nil : trimmed)
    }
}
