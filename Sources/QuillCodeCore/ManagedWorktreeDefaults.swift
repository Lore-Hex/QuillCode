import Foundation

/// Shared validation for the managed-worktree settings persisted in `AppConfig`.
public enum ManagedWorktreeDefaults {
    public static let retentionLimit = 15
    public static let maximumRetentionLimit = 1_000

    public static func normalizedRoot(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    /// `nil` disables automatic cleanup. Positive values are bounded to keep malformed config safe.
    public static func normalizedRetentionLimit(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return min(value, maximumRetentionLimit)
    }
}
