import Foundation
import QuillCodeCore

struct StaticSafetyPolicy: Sendable {
    private let hardDenyRules: [StaticSafetyHardDenyRule]
    private let intentRules: [StaticSafetyIntentRule]

    init(
        hardDenyRules: [StaticSafetyHardDenyRule] = StaticSafetyPolicy.defaultHardDenyRules,
        intentRules: [StaticSafetyIntentRule] = StaticSafetyPolicy.defaultIntentRules
    ) {
        self.hardDenyRules = hardDenyRules
        self.intentRules = intentRules
    }

    func hardDenyReason(_ context: SafetyContext) -> String? {
        let haystack = normalizedHaystack(for: context)
        guard let rule = hardDenyRules.first(where: { $0.matches(haystack) }) else {
            return nil
        }
        return rule.rationale
    }

    func userIntentMatches(_ context: SafetyContext) -> Bool {
        let request = StaticSafetyRequest(context.userMessage)
        let toolName = context.toolCall.name

        if request.containsAny(["remember", "memorize"]) {
            return toolName.contains("memory")
        }
        if request.containsAny(["run", "execute"]) {
            return true
        }
        if request.containsAny(StaticSafetyPullRequestPolicy.requestTriggers) {
            return StaticSafetyPullRequestPolicy.intentMatches(request: request, toolName: toolName)
        }
        if let rule = intentRules.first(where: { $0.matches(request: request) }) {
            return rule.allows(toolName: toolName)
        }
        if toolName.contains("computer"),
           request.containsAny(StaticSafetyPolicy.computerUseTriggers) {
            return true
        }
        if request.containsAny(StaticSafetyPolicy.commonDiagnosticTriggers) {
            return true
        }
        return request.significantWords.contains { word in
            context.toolCall.argumentsJSON.lowercased().contains(word)
        }
    }

    private func normalizedHaystack(for context: SafetyContext) -> String {
        "\(context.toolCall.name) \(context.toolCall.argumentsJSON)"
            .lowercased()
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private static let defaultHardDenyRules: [StaticSafetyHardDenyRule] = [
        .all(
            ["curl ", "| sh"],
            rationale: "Auto mode blocks piping remote downloads into a shell."
        ),
        .all(
            ["curl ", "| bash"],
            rationale: "Auto mode blocks piping remote downloads into a shell."
        ),
        .contains("rm -rf /"),
        .contains("mkfs"),
        .contains("dd if="),
        .contains("security find-generic-password"),
        .contains("cat ~/.ssh"),
        .contains("aws_secret_access_key"),
        .contains("chmod -r 777 /"),
        .contains(":(){")
    ]

    private static let defaultIntentRules: [StaticSafetyIntentRule] = [
        .init(
            requestTriggers: ["make", "create", "write"],
            allowedToolNames: ["file", "shell", "git.worktree"]
        ),
        .init(
            requestTriggers: ["commit"],
            allowedToolNames: ["git.commit", "git.stage", "git.status", "git.diff"]
        ),
        .init(
            requestTriggers: ["push", "publish branch"],
            allowedToolNames: ["git.push", "git.status"]
        ),
        .init(
            requestTriggers: ["worktree"],
            allowedToolNames: ["git.worktree", "git.status", "git.diff"]
        )
    ]

    private static let computerUseTriggers = [
        "screenshot",
        "screen",
        "click",
        "type",
        "scroll",
        "cursor",
        "mouse",
        "press",
        "key"
    ]

    private static let commonDiagnosticTriggers = [
        "openclaw",
        "whoami",
        "disk",
        "storage"
    ]
}

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
        request.containsAny(requestTriggers)
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

struct StaticSafetyRequest: Sendable {
    private let text: String

    init(_ text: String) {
        self.text = text.lowercased()
    }

    var significantWords: [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    func containsAny(_ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}

enum StaticSafetyPullRequestPolicy {
    static let requestTriggers = [
        "pull request",
        "open pr",
        "open a pr",
        "create pr",
        "create a pr",
        "submit pr",
        "submit a pr",
        "checkout pr",
        "check out pr",
        "switch to pr",
        "merge pr",
        "automerge pr",
        "auto merge pr",
        "inline comment",
        "review thread",
        "resolve thread",
        "unresolve thread"
    ]

    private static let specificRules: [StaticSafetyIntentRule] = [
        .init(
            requestTriggers: ["checkout", "check out", "switch"],
            allowedToolNames: ["git.pr.checkout", "git.status"]
        ),
        .init(
            requestTriggers: ["reviewer", "reviewers", "request review from"],
            allowedToolNames: ["git.pr.reviewers", "git.status"]
        ),
        .init(
            requestTriggers: ["label", "labels", "unlabel"],
            allowedToolNames: ["git.pr.labels", "git.status"]
        ),
        .init(
            requestTriggers: ["merge", "automerge"],
            allowedToolNames: ["git.pr.merge", "git.pr.checks", "git.status"]
        ),
        .init(
            requestTriggers: ["resolve", "unresolve", "reopen"],
            allowedToolNames: ["git.pr.review_thread", "git.status"]
        ),
        .init(
            requestTriggers: ["approve", "request changes", "needs changes", "review"],
            allowedToolNames: ["git.pr.review", "git.status"]
        ),
        .init(
            requestTriggers: ["comment", "reply"],
            allowedToolNames: ["git.pr.comment", "git.pr.review_comment", "git.pr.review_reply"]
        ),
        .init(
            requestTriggers: ["check", "ci", "status"],
            allowedToolNames: ["git.pr.checks", "git.status"]
        ),
        .init(
            requestTriggers: ["view", "show", "inspect", "read"],
            allowedToolNames: ["git.pr.view", "git.status"]
        )
    ]

    private static let defaultAllowedToolNames = [
        "git.pr.create",
        "git.pr.comment",
        "git.push",
        "git.status"
    ]

    static func intentMatches(request: StaticSafetyRequest, toolName: String) -> Bool {
        if let rule = specificRules.first(where: { $0.matches(request: request) }) {
            return rule.allows(toolName: toolName)
        }
        return defaultAllowedToolNames.contains { toolName.contains($0) }
    }
}
