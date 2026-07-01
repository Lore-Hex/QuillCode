import Foundation

struct StaticSafetyHardDenyRule: Sendable {
    private var matcher: StaticSafetyStringMatcher
    var rationale: String

    static func contains(_ pattern: String) -> StaticSafetyHardDenyRule {
        StaticSafetyHardDenyRule(
            matcher: .contains(pattern),
            rationale: "Auto mode blocks high-risk command pattern: \(pattern)."
        )
    }

    static func all(_ patterns: [String], rationale: String) -> StaticSafetyHardDenyRule {
        StaticSafetyHardDenyRule(matcher: .all(patterns), rationale: rationale)
    }

    func matches(_ haystack: String) -> Bool {
        matcher.matches(haystack)
    }
}

struct StaticSafetyIntentRule: Sendable {
    var requestTriggers: [String]
    var allowedToolNames: [String]

    func matches(request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(requestTriggers)
    }

    func allows(toolName: String) -> Bool {
        allowedToolNames.contains { toolName.contains($0) }
    }
}

enum StaticSafetyStringMatcher: Sendable {
    case contains(String)
    case all([String])

    func matches(_ haystack: String) -> Bool {
        switch self {
        case .contains(let pattern):
            return haystack.contains(pattern)
        case .all(let patterns):
            return patterns.allSatisfy { haystack.contains($0) }
        }
    }
}
