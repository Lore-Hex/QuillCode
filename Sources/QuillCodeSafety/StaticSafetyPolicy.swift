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
        // Check the horizontal-collapsed haystack (spaces/tabs collapsed, newlines preserved — the
        // form the permission-rule subject also produces) AND a fully-collapsed haystack (newlines
        // and CR ALSO folded to a space). The second variant closes any newline-split asymmetry:
        // a dangerous token spelled `rm -rf\n/` can never dodge the floor even though the subject
        // preserves newlines. The floor being strictly MORE aggressive than the subject is the
        // safe direction — over-catching here only forces an extra ask/deny.
        let haystacks = normalizedHaystacks(for: context)
        guard let rule = hardDenyRules.first(where: { rule in
            haystacks.contains { rule.matches($0) }
        }) else {
            return nil
        }
        return rule.rationale
    }

    func userIntentMatches(_ context: SafetyContext) -> Bool {
        let request = StaticSafetyRequest(context.userMessage)
        let toolName = context.toolCall.name

        if request.containsAffirmedAny(["remember", "memorize"]) {
            return toolName.contains("memory")
        }
        if StaticSafetyPullRequestPolicy.requestMatches(request) {
            return StaticSafetyPullRequestPolicy.intentMatches(request: request, toolName: toolName)
        }
        if StaticSafetyDownloadPolicy.intentMatches(request: request, context: context) {
            return true
        }
        if StaticSafetyReadOnlyShellPolicy.intentMatches(request: request, context: context) {
            return true
        }
        if intentRules.contains(where: { $0.matches(request: request) && $0.allows(toolName: toolName) }) {
            return true
        }
        if toolName.contains("computer"),
           request.containsAffirmedAny(StaticSafetyPolicy.computerUseTriggers) {
            return true
        }
        guard context.toolDefinition?.risk == .read else {
            return false
        }
        return request.significantWords.contains { word in
            context.toolCall.argumentsJSON.lowercased().contains(word)
        }
    }

    private func normalizedHaystacks(for context: SafetyContext) -> [String] {
        // Match against the decoded argument values, not the raw JSON wire form. The tool executor
        // runs decoded arguments, so the hard-deny list should inspect the same value.
        let arguments = Self.decodedArgumentText(context.toolCall.argumentsJSON)
            ?? context.toolCall.argumentsJSON.replacingOccurrences(of: "\\/", with: "/")
        let base = "\(context.toolCall.name) \(arguments)"
        // Variant 1: collapse horizontal whitespace only (newlines preserved) — the SAME form the
        // permission-rule subject produces (see PermissionRuleSubject.normalizedCommand).
        // Variant 2: also fold newlines/CR to a space, so a token split across a newline can't dodge
        // the floor. De-duplicated when they coincide.
        let horizontal = Self.collapseWhitespace(base, foldNewlines: false).lowercased()
        let full = Self.collapseWhitespace(base, foldNewlines: true).lowercased()
        return horizontal == full ? [horizontal] : [horizontal, full]
    }

    static func collapseHorizontalWhitespace(_ text: String) -> String {
        collapseWhitespace(text, foldNewlines: false)
    }

    /// Collapses runs of whitespace to a single space. When `foldNewlines` is false, newlines and
    /// carriage returns are preserved verbatim (only spaces/tabs collapse); when true, they too are
    /// treated as whitespace and folded.
    static func collapseWhitespace(_ text: String, foldNewlines: Bool) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var pendingSpace = false
        var sawNonSpace = false
        for scalar in text.unicodeScalars {
            let isNewline = scalar == "\n" || scalar == "\r"
            if isNewline && !foldNewlines {
                pendingSpace = false
                output.unicodeScalars.append(scalar)
                sawNonSpace = false
                continue
            }
            if scalar == " " || scalar == "\t" || isNewline {
                pendingSpace = true
                continue
            }
            if pendingSpace && sawNonSpace {
                output.unicodeScalars.append(" ")
            }
            pendingSpace = false
            sawNonSpace = true
            output.unicodeScalars.append(scalar)
        }
        return output
    }

    private static func decodedArgumentText(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            return nil
        }
        var parts: [String] = []
        collectStrings(from: object, into: &parts)
        return parts.joined(separator: " ")
    }

    private static func collectStrings(from object: Any, into parts: inout [String]) {
        switch object {
        case let string as String:
            parts.append(string)
        case let dictionary as [String: Any]:
            for (key, value) in dictionary {
                parts.append(key)
                collectStrings(from: value, into: &parts)
            }
        case let array as [Any]:
            for value in array {
                collectStrings(from: value, into: &parts)
            }
        default:
            break
        }
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
            requestTriggers: ["run", "execute"],
            allowedToolNames: ["shell.run"]
        ),
        .init(
            requestTriggers: ["mcp"],
            allowedToolNames: ["mcp.call"]
        ),
        .init(
            requestTriggers: commonDiagnosticTriggers,
            allowedToolNames: ["shell.run"]
        ),
        .init(
            requestTriggers: ["apply patch", "apply this patch", "patch"],
            allowedToolNames: ["apply_patch"]
        ),
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
        "hd",
        "openclaw",
        "whoami",
        "disk",
        "storage"
    ]
}
