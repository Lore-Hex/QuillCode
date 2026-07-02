import QuillCodeSafety

/// Result of loading a per-project permission rule file. Loading never throws and never crashes on
/// a bad file: a corrupt or newer-versioned file degrades to an empty table plus diagnostics.
///
/// `degraded` is the fail-safe signal for the review path: an existing file that could not be read
/// as intended sets it, so a persisted deny cannot accidentally become "no rules".
public struct PermissionRuleLoadResult: Sendable {
    public var table: PermissionRuleTable
    public var degraded: Bool
    public var diagnostics: [String]

    public init(
        table: PermissionRuleTable = PermissionRuleTable(),
        degraded: Bool = false,
        diagnostics: [String] = []
    ) {
        self.table = table
        self.degraded = degraded
        self.diagnostics = diagnostics
    }
}

public enum PermissionRuleStoreError: Error, CustomStringConvertible {
    /// The on-disk file was written by a newer QuillCode. Appending would rewrite and downgrade it.
    case newerFileVersion(found: Int, supported: Int)
    /// The file contains otherwise structured rules this build cannot represent.
    case unrepresentableRules(count: Int)

    public var description: String {
        switch self {
        case .newerFileVersion(let found, let supported):
            return Self.newerFileVersionDescription(found: found, supported: supported)
        case .unrepresentableRules(let count):
            return Self.unrepresentableRulesDescription(count: count)
        }
    }

    private static func newerFileVersionDescription(found: Int, supported: Int) -> String {
        "Permission rules file uses newer format version \(found) " +
            "(this build supports \(supported)); not overwriting it."
    }

    private static func unrepresentableRulesDescription(count: Int) -> String {
        "Permission rules file has \(count) rule(s) this build can't represent " +
            "(unknown match/decision); not overwriting it. " +
            "Update this build or repair the file first."
    }
}
