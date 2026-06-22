import Foundation
import QuillCodeCore

public struct SafetyContext: Sendable {
    public var mode: AgentMode
    public var userMessage: String
    public var toolCall: ToolCall
    public var toolDefinition: ToolDefinition?
    public var recentMessages: [ChatMessage]

    public init(
        mode: AgentMode,
        userMessage: String,
        toolCall: ToolCall,
        toolDefinition: ToolDefinition?,
        recentMessages: [ChatMessage]
    ) {
        self.mode = mode
        self.userMessage = userMessage
        self.toolCall = toolCall
        self.toolDefinition = toolDefinition
        self.recentMessages = recentMessages
    }
}

public struct SafetyReview: Codable, Sendable, Hashable {
    public var verdict: ApprovalVerdict
    public var rationale: String
    public var reviewerModel: String?
    public var userIntentMatched: Bool

    public init(
        verdict: ApprovalVerdict,
        rationale: String,
        reviewerModel: String? = nil,
        userIntentMatched: Bool = false
    ) {
        self.verdict = verdict
        self.rationale = rationale
        self.reviewerModel = reviewerModel
        self.userIntentMatched = userIntentMatched
    }
}

public protocol SafetyReviewer: Sendable {
    func review(_ context: SafetyContext) async -> SafetyReview
}

public protocol SafetyModelClient: Sendable {
    func review(prompt: String, model: String) async throws -> String
}

public struct StaticSafetyReviewer: SafetyReviewer {
    public init() {}

    public func review(_ context: SafetyContext) async -> SafetyReview {
        switch context.mode {
        case .readOnly:
            if context.toolDefinition?.risk == .read {
                return lowRiskReview(context)
            }
            return SafetyReview(
                verdict: .deny,
                rationale: "Read-only mode blocks file writes, shell mutations, and destructive tools."
            )
        case .review:
            if context.toolDefinition?.risk == .read {
                return lowRiskReview(context)
            }
            return SafetyReview(
                verdict: .clarify,
                rationale: "Review mode requires explicit approval before this tool runs.",
                userIntentMatched: userIntentMatches(context)
            )
        case .auto:
            if let hardDeny = hardDenyReason(context) {
                return SafetyReview(verdict: .deny, rationale: hardDeny)
            }
            if context.toolDefinition?.risk == .read || userIntentMatches(context) {
                return lowRiskReview(context)
            }
            return SafetyReview(
                verdict: .clarify,
                rationale: "The requested tool action does not clearly match the latest user message."
            )
        }
    }

    public func hardDenyReason(_ context: SafetyContext) -> String? {
        let haystack = "\(context.toolCall.name) \(context.toolCall.argumentsJSON)"
            .lowercased()
            .replacingOccurrences(of: "\\/", with: "/")
        let blocked = [
            "rm -rf /",
            "mkfs",
            "dd if=",
            "security find-generic-password",
            "cat ~/.ssh",
            "aws_secret_access_key",
            "chmod -r 777 /",
            ":(){"
        ]
        if haystack.contains("curl ") && haystack.contains("| sh") {
            return "Auto mode blocks piping remote downloads into a shell."
        }
        if haystack.contains("curl ") && haystack.contains("| bash") {
            return "Auto mode blocks piping remote downloads into a shell."
        }
        if let match = blocked.first(where: { haystack.contains($0) }) {
            return "Auto mode blocks high-risk command pattern: \(match)."
        }
        return nil
    }

    public func userIntentMatches(_ context: SafetyContext) -> Bool {
        let user = context.userMessage.lowercased()
        let args = context.toolCall.argumentsJSON.lowercased()
        if user.contains("remember") || user.contains("memorize") {
            return context.toolCall.name.contains("memory")
        }
        if user.contains("run") || user.contains("execute") {
            return true
        }
        if user.contains("pull request")
            || user.contains("open pr")
            || user.contains("open a pr")
            || user.contains("create pr")
            || user.contains("create a pr")
            || user.contains("submit pr")
            || user.contains("submit a pr")
            || user.contains("checkout pr")
            || user.contains("check out pr")
            || user.contains("switch to pr")
            || user.contains("merge pr")
            || user.contains("automerge pr")
            || user.contains("auto merge pr") {
            if user.contains("checkout") || user.contains("check out") || user.contains("switch") {
                return context.toolCall.name.contains("git.pr.checkout")
                    || context.toolCall.name.contains("git.status")
            }
            if user.contains("reviewer")
                || user.contains("reviewers")
                || user.contains("request review from") {
                return context.toolCall.name.contains("git.pr.reviewers")
                    || context.toolCall.name.contains("git.status")
            }
            if user.contains("merge") || user.contains("automerge") {
                return context.toolCall.name.contains("git.pr.merge")
                    || context.toolCall.name.contains("git.pr.checks")
                    || context.toolCall.name.contains("git.status")
            }
            if user.contains("approve")
                || user.contains("request changes")
                || user.contains("needs changes")
                || user.contains("review") {
                return context.toolCall.name.contains("git.pr.review")
                    || context.toolCall.name.contains("git.status")
            }
            if user.contains("comment") || user.contains("reply") {
                return context.toolCall.name.contains("git.pr.comment")
            }
            if user.contains("check") || user.contains("ci") || user.contains("status") {
                return context.toolCall.name.contains("git.pr.checks")
                    || context.toolCall.name.contains("git.status")
            }
            if user.contains("view")
                || user.contains("show")
                || user.contains("inspect")
                || user.contains("read") {
                return context.toolCall.name.contains("git.pr.view")
                    || context.toolCall.name.contains("git.status")
            }
            return context.toolCall.name.contains("git.pr.create")
                || context.toolCall.name.contains("git.pr.comment")
                || context.toolCall.name.contains("git.push")
                || context.toolCall.name.contains("git.status")
        }
        if user.contains("make") || user.contains("create") || user.contains("write") {
            return context.toolCall.name.contains("file")
                || context.toolCall.name.contains("shell")
                || context.toolCall.name.contains("git.worktree")
        }
        if user.contains("commit") {
            return context.toolCall.name.contains("git.commit")
                || context.toolCall.name.contains("git.stage")
                || context.toolCall.name.contains("git.status")
                || context.toolCall.name.contains("git.diff")
        }
        if user.contains("push") || user.contains("publish branch") {
            return context.toolCall.name.contains("git.push")
                || context.toolCall.name.contains("git.status")
        }
        if user.contains("worktree") {
            return context.toolCall.name.contains("git.worktree")
                || context.toolCall.name.contains("git.status")
                || context.toolCall.name.contains("git.diff")
        }
        if context.toolCall.name.contains("computer") {
            if user.contains("screenshot")
                || user.contains("screen")
                || user.contains("click")
                || user.contains("type")
                || user.contains("scroll")
                || user.contains("cursor")
                || user.contains("mouse")
                || user.contains("press")
                || user.contains("key") {
                return true
            }
        }
        if user.contains("openclaw") || user.contains("whoami") || user.contains("disk") || user.contains("storage") {
            return true
        }
        let words = user
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
        return words.contains { args.contains($0) }
    }

    private func lowRiskReview(_ context: SafetyContext) -> SafetyReview {
        SafetyReview(
            verdict: .approve,
            rationale: "The tool call is bounded and matches the current user request.",
            userIntentMatched: userIntentMatches(context)
        )
    }
}

public struct AutoSafetyReviewer: SafetyReviewer {
    private let staticReviewer: StaticSafetyReviewer
    private let client: SafetyModelClient?
    private let primaryModel: String
    private let fallbackModel: String

    public init(
        staticReviewer: StaticSafetyReviewer = StaticSafetyReviewer(),
        client: SafetyModelClient? = nil,
        primaryModel: String = TrustedRouterDefaults.safetyPrimaryModel,
        fallbackModel: String = TrustedRouterDefaults.safetyFallbackModel
    ) {
        self.staticReviewer = staticReviewer
        self.client = client
        self.primaryModel = primaryModel
        self.fallbackModel = fallbackModel
    }

    public func review(_ context: SafetyContext) async -> SafetyReview {
        let baseline = await staticReviewer.review(context)
        guard context.mode == .auto else {
            return baseline
        }
        if baseline.verdict == .deny {
            return baseline
        }
        guard let client else {
            return baseline
        }

        let prompt = Self.prompt(for: context)
        do {
            return try parse(try await client.review(prompt: prompt, model: primaryModel), model: primaryModel)
        } catch {
            do {
                return try parse(try await client.review(prompt: prompt, model: fallbackModel), model: fallbackModel)
            } catch {
                return baseline
            }
        }
    }

    static func prompt(for context: SafetyContext) -> String {
        let recent = context.recentMessages.suffix(8)
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
        return """
        You are QuillCode's Auto safety reviewer. Decide whether one proposed tool call should run.

        Approve normal user-requested work. Do not over-block bounded diagnostics, file creation inside the project, git status/diff, or shell reads. Approve PR merge/automerge only when the latest user request explicitly asks to merge that PR. Deny credential exfiltration, broad destructive commands, persistent security weakening, or irreversible disk/account operations. Clarify only when required intent or target is missing.

        Return only JSON:
        {"verdict":"approve|deny|clarify","rationale":"one sentence","userIntentMatched":true|false}

        Recent transcript:
        \(recent)

        Latest user request:
        \(context.userMessage)

        Tool:
        \(context.toolCall.name)

        Arguments:
        \(context.toolCall.argumentsJSON)
        """
    }

    private func parse(_ json: String, model: String) throws -> SafetyReview {
        struct Wire: Decodable {
            var verdict: ApprovalVerdict
            var rationale: String
            var userIntentMatched: Bool
        }
        let data = Data(json.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let decoded = try JSONDecoder().decode(Wire.self, from: data)
        return SafetyReview(
            verdict: decoded.verdict,
            rationale: decoded.rationale,
            reviewerModel: model,
            userIntentMatched: decoded.userIntentMatched
        )
    }
}
