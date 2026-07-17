import Foundation

/// Single source of truth for the `/incognito` command aliases, shared by the main slash parser and
/// the desktop composer coordinator (which must intercept `/incognito` before the busy follow-up
/// queue, exactly like `/side`). Keeping the alias set here prevents the two dispatch sites drifting.
public enum WorkspaceIncognitoSlash {
    public static let aliases: Set<String> = ["incognito", "incognito-chat", "private-chat"]

    /// True when `input` is a bare `/incognito` (or an alias) command with no trailing argument.
    public static func isIncognitoCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        let name = trimmed.dropFirst().split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return aliases.contains(name.lowercased())
    }
}
