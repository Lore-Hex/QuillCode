import Foundation

/// Single source of truth for the `/confidential` command aliases, shared by the main slash parser and
/// the desktop composer coordinator (which must intercept `/confidential` before the busy follow-up
/// queue, exactly like `/side`). Keeping the alias set here prevents the two dispatch sites drifting.
public enum WorkspaceConfidentialSlash {
    /// "incognito" is the feature's pre-rename name, kept as a hidden legacy alias so existing muscle
    /// memory (and old notes/scripts) still lands in a confidential chat instead of an error.
    public static let aliases: Set<String> = [
        "confidential", "confidential-chat", "private-chat", "incognito", "incognito-chat"
    ]

    /// True when `input` is a bare `/confidential` (or an alias) command with no trailing argument.
    public static func isConfidentialCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        let name = trimmed.dropFirst().split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return aliases.contains(name.lowercased())
    }
}
