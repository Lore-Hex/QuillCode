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

        if request.containsAffirmedAny(["remember", "memorize"]) {
            return toolName.contains("memory")
        }
        if StaticSafetyPullRequestPolicy.requestMatches(request) {
            return StaticSafetyPullRequestPolicy.intentMatches(request: request, toolName: toolName)
        }
        if StaticSafetyDownloadPolicy.intentMatches(request: request, context: context) {
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

struct StaticSafetyRequest: Sendable {
    private let text: String

    init(_ text: String) {
        self.text = text.lowercased()
    }

    var significantWords: [String] {
        tokens
            .filter { $0.count >= 3 }
    }

    var requestedDownloadHosts: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return text
            .components(separatedBy: separators)
            .compactMap(Self.normalizedHostCandidate)
    }

    var requestedDownloadFileURLs: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return text
            .components(separatedBy: separators)
            .compactMap(Self.normalizedFileURLCandidate)
    }

    func containsAffirmedAny(_ phrases: [String]) -> Bool {
        phrases.contains { containsAffirmed($0) }
    }

    func containsToken(_ token: String) -> Bool {
        let normalized = token.lowercased()
        return tokens.contains { $0 == normalized }
    }

    private var tokens: [String] {
        indexedTokens.map(\.value)
    }

    private var indexedTokens: [IndexedToken] {
        Self.tokenizeWithClauseStarts(text)
    }

    private func containsAffirmed(_ phrase: String) -> Bool {
        guard text.contains(phrase.lowercased()) else {
            return false
        }
        let phraseTokens = Self.tokenize(phrase)
        guard !phraseTokens.isEmpty else {
            return false
        }
        let requestTokens = indexedTokens
        guard requestTokens.count >= phraseTokens.count else {
            return false
        }
        for start in 0...(requestTokens.count - phraseTokens.count) {
            let end = start + phraseTokens.count
            let tokenValues = requestTokens[start..<end].map(\.value)
            guard tokenValues == phraseTokens else {
                continue
            }
            if !hasNegationBefore(start, in: requestTokens) {
                return true
            }
        }
        return false
    }

    private func hasNegationBefore(_ index: Int, in tokens: [IndexedToken]) -> Bool {
        guard index > 0 else {
            return false
        }
        let clauseStart = stride(from: index, through: 0, by: -1)
            .first { tokens[$0].startsClause } ?? 0
        let start = max(clauseStart, index - 4)
        let prefix = tokens[start..<index].map(\.value)
        if prefix.contains(where: { ["dont", "never", "without"].contains($0) }) {
            return true
        }
        if prefix.last == "no" {
            return true
        }
        return containsAdjacent("do", "not", in: prefix)
            || containsAdjacent("does", "not", in: prefix)
            || containsAdjacent("did", "not", in: prefix)
    }

    private struct IndexedToken: Sendable {
        var value: String
        var startsClause: Bool
    }

    private func containsAdjacent(_ first: String, _ second: String, in tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }
        return zip(tokens, tokens.dropFirst()).contains { $0 == first && $1 == second }
    }

    private static func tokenize(_ value: String) -> [String] {
        tokenizeWithClauseStarts(value).map(\.value)
    }

    private static func tokenizeWithClauseStarts(_ value: String) -> [IndexedToken] {
        var tokens: [IndexedToken] = []
        var current = ""
        var nextStartsClause = true
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")

        func flushToken() {
            guard !current.isEmpty else {
                return
            }
            tokens.append(.init(value: current, startsClause: nextStartsClause))
            current = ""
            nextStartsClause = false
        }

        for character in normalized {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flushToken()
                if isClauseBoundary(character) {
                    nextStartsClause = true
                }
            }
        }
        flushToken()
        return tokens
    }

    private static func isClauseBoundary(_ character: Character) -> Bool {
        character == ";" || character == "." || character == "!" || character == "?" || character == "\n"
    }

    private static func normalizedHostCandidate(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: ",:;!?"))
        let lowerCandidate = candidate.lowercased()
        guard !lowerCandidate.hasPrefix("file://"),
              candidate.contains("."),
              !candidate.contains("@")
        else {
            return nil
        }
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let host = URL(string: candidate)?.host?.lowercased(),
              host.contains(".")
        else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func normalizedFileURLCandidate(_ value: String) -> String? {
        let candidate = value
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;!?"))
            .lowercased()
        return candidate.hasPrefix("file://") ? candidate : nil
    }
}

enum StaticSafetyDownloadPolicy {
    static func intentMatches(request: StaticSafetyRequest, context: SafetyContext) -> Bool {
        guard context.toolCall.name.contains("shell.run"),
              request.containsAffirmedAny(["download", "save", "fetch"]),
              let command = shellCommand(from: context.toolCall)
        else {
            return false
        }
        let lowerCommand = command.lowercased()
        guard containsDownloadSegment(lowerCommand),
              let outputPath = outputPath(from: lowerCommand),
              isWorkspaceRelativePath(outputPath),
              !lowerCommand.contains("|")
        else {
            return false
        }
        let requestedFileURLs = request.requestedDownloadFileURLs
        if !requestedFileURLs.isEmpty {
            return requestedFileURLs.contains { fileURL in
                lowerCommand.contains(fileURL)
            }
        }
        let requestedHosts = request.requestedDownloadHosts
        return requestedHosts.contains { host in
            lowerCommand.contains(host)
        }
    }

    private static func shellCommand(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("cmd")
    }

    private static func containsDownloadSegment(_ command: String) -> Bool {
        command
            .components(separatedBy: "&&")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { segment in
                segment.hasPrefix("curl ") || segment.hasPrefix("wget ")
            }
    }

    private static func outputPath(from command: String) -> String? {
        let patterns = [
            #"--output\s+('[^']+'|"[^"]+"|\S+)"#,
            #"\s-o\s+('[^']+'|"[^"]+"|\S+)"#,
            #">\s*('[^']+'|"[^"]+"|\S+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
                  let range = Range(match.range(at: 1), in: command)
            else {
                continue
            }
            return unquoted(String(command[range]))
        }
        return nil
    }

    private static func isWorkspaceRelativePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.hasPrefix("/")
            && !trimmed.hasPrefix("~")
            && !trimmed.contains("..")
    }

    private static func unquoted(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))
            || (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        return trimmed
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
        "review threads",
        "thread ids",
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
            requestTriggers: ["list", "show", "browse", "find", "unresolved", "thread ids", "comment ids"],
            allowedToolNames: ["git.pr.review_threads", "git.pr.view", "git.status"]
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

    static func requestMatches(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(requestTriggers)
            || (request.containsToken("pr") && specificRules.contains { $0.matches(request: request) })
    }

    static func intentMatches(request: StaticSafetyRequest, toolName: String) -> Bool {
        let matchingRules = specificRules.filter { $0.matches(request: request) }
        if !matchingRules.isEmpty {
            return matchingRules.contains { $0.allows(toolName: toolName) }
        }
        return defaultAllowedToolNames.contains { toolName.contains($0) }
    }
}
