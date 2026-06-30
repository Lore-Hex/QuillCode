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
    private let policy = StaticSafetyPolicy()

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
        case .plan:
            // Plan mode investigates read-only and proposes a plan; every mutating tool is
            // blocked until the user approves it (which applies that step and starts executing).
            // It returns `.clarify`, NOT `.deny`: the agent loop blocks on any non-`.approve`
            // verdict either way, but `.deny` is the hard "no approval possible" signal (e.g.
            // `rm -rf /`) that suppresses the approve button — a plan block must stay approvable.
            if context.toolDefinition?.risk == .read {
                return lowRiskReview(context)
            }
            return SafetyReview(
                verdict: .clarify,
                rationale: "Planning — approve the proposed change to apply it and start executing.",
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
        policy.hardDenyReason(context)
    }

    public func userIntentMatches(_ context: SafetyContext) -> Bool {
        policy.userIntentMatches(context)
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
