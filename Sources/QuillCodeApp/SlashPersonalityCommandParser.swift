import QuillCodeCore

enum SlashPersonalityCommandParser {
    static let usage = "Usage: /personality friendly|pragmatic|none"

    static func parse(_ argument: String) -> SlashCommand {
        guard let personality = QuillCodePersonality.parse(argument) else {
            return .invalid(usage)
        }
        return .personality(personality)
    }
}
