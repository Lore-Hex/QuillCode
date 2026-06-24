import Foundation
import QuillCodeCore

enum SlashModeCommandParser {
    static func parse(_ argument: String) -> SlashCommand {
        let mode = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode.lowercased() {
        case "auto":
            return .mode(.auto)
        case "review":
            return .mode(.review)
        case "read-only", "readonly", "read_only":
            return .mode(.readOnly)
        case "":
            return .invalid("Usage: /mode auto, /mode review, or /mode read-only")
        default:
            return .invalid("Unknown mode '\(mode)'. Use auto, review, or read-only.")
        }
    }
}
