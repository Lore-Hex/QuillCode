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
}
