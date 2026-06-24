import Foundation

enum SlashRemoteProjectCommandParser {
    private static let usage = "Usage: /ssh user@host:/absolute/path"

    static func parse(_ argument: String) -> SlashCommand {
        let address = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? .invalid(usage) : .sshProject(address)
    }
}
