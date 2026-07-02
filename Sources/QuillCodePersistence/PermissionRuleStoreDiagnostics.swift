import Foundation
import QuillCodeSafety

public enum PermissionRuleStoreError: Error, CustomStringConvertible {
    /// The on-disk file was written by a newer QuillCode. Appending would rewrite and downgrade it.
    case newerFileVersion(found: Int, supported: Int)
    /// The file contains otherwise-valid rules with match/decision values this build cannot represent.
    case unrepresentableRules(count: Int)

    public var description: String {
        switch self {
        case .newerFileVersion(let found, let supported):
            return PermissionRuleStoreDiagnostics.newerFormatOnSave(
                found: found,
                supported: supported
            )
        case .unrepresentableRules(let count):
            return PermissionRuleStoreDiagnostics.unrepresentableRulesOnSave(count)
        }
    }
}

enum PermissionRuleStoreDiagnostics {
    static func unreadableFile(_ fileName: String, error: Error) -> String {
        "Could not read permission rules file \(fileName): \(error.localizedDescription). " +
            "Asking for confirmation until it is readable."
    }

    static func invalidJSON(_ fileName: String) -> String {
        "Permission rules file \(fileName) is not valid JSON; " +
            "asking for confirmation until it is repaired."
    }

    static func newerFormatOnLoad(_ fileName: String, version: Int) -> String {
        "Permission rules file \(fileName) uses newer format version \(version); " +
            "asking for confirmation until this build is updated."
    }

    static func newerFormatOnSave(found: Int, supported: Int) -> String {
        "Permission rules file uses newer format version \(found) " +
            "(this build supports \(supported)); not overwriting it."
    }

    static func unrepresentableRulesOnSave(_ count: Int) -> String {
        "Permission rules file has \(count) rule(s) this build can't represent " +
            "(unknown match/decision); not overwriting it. " +
            "Update this build or repair the file first."
    }

    static func oversizedPattern(_ fileName: String) -> String {
        "Ignoring an oversized wildcard pattern in \(fileName) " +
            "(patterns are capped at \(PermissionWildcardPattern.maxPatternScalarCount) characters)."
    }

    static func malformedRules(_ count: Int, fileName: String) -> String {
        "Skipped \(count) malformed rule\(pluralSuffix(for: count)) in \(fileName)."
    }

    static func unrepresentableRules(_ count: Int, fileName: String) -> String {
        "\(count) rule\(pluralSuffix(for: count)) in \(fileName) use an unknown " +
            "match/decision this build can't represent; asking for confirmation until " +
            "this build is updated or the file is repaired."
    }

    static func tooManyRules(_ count: Int, fileName: String) -> String {
        "Permission rules file \(fileName) has \(count) rules; only the last " +
            "\(PermissionRuleTable.maxRuleCount) (highest priority) are used."
    }

    private static func pluralSuffix(for count: Int) -> String {
        count == 1 ? "" : "s"
    }
}
