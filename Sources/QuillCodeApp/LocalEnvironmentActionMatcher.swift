import Foundation
import QuillCodeCore

enum LocalEnvironmentActionMatcher {
    static func action(withID id: String, in actions: [LocalEnvironmentAction]) -> LocalEnvironmentAction? {
        actions.first { $0.id == id }
    }

    static func action(matching query: String, in actions: [LocalEnvironmentAction]) -> LocalEnvironmentAction? {
        let normalizedQuery = normalizedActionName(query)
        return actions.first { action in
            action.id.caseInsensitiveCompare(query) == .orderedSame
                || action.title.caseInsensitiveCompare(query) == .orderedSame
                || action.relativePath.caseInsensitiveCompare(query) == .orderedSame
                || normalizedActionName(action.title) == normalizedQuery
                || normalizedActionName(action.relativePath) == normalizedQuery
        }
    }

    static func normalizedActionName(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// The project action that IS the verification command for the green gate — identified purely by a
    /// naming CONVENTION on the actions the user already authored (no metadata-schema change). Precedence:
    /// an exact id match on "verify" / "test" / "check" (in that order), then a title match in the same
    /// order; first-wins on a tie (preserving the user's authored order). nil when nothing matches, in
    /// which case the gate is a no-op.
    static func verificationAction(in actions: [LocalEnvironmentAction]) -> LocalEnvironmentAction? {
        let conventionNames = ["verify", "test", "check"]
        for name in conventionNames {
            if let action = actions.first(where: { normalizedActionName($0.id) == name }) {
                return action
            }
        }
        for name in conventionNames {
            if let action = actions.first(where: { normalizedActionName($0.title) == name }) {
                return action
            }
        }
        return nil
    }
}
