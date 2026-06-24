import Foundation

enum SlashTerminalCommandParser {
    static func parse(_ argument: String) -> SlashCommand {
        let command = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return .workspaceCommand("toggle-terminal")
        }

        switch command.lowercased() {
        case "clear", "reset":
            return .workspaceCommand("terminal-clear")
        default:
            return .invalid("Usage: /terminal or /terminal clear")
        }
    }
}
