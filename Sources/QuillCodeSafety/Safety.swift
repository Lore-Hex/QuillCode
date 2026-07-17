import Foundation
import QuillCodeCore

public struct SafetyContext: Sendable {
    public var mode: AgentMode
    public var userMessage: String
    public var toolCall: ToolCall
    public var toolDefinition: ToolDefinition?
    public var recentMessages: [ChatMessage]
    /// The workspace the tool call will run in. Persisted permission rules are per-workspace, so
    /// the rule-gated reviewer needs it to load the right table and to normalize path resources.
    /// Nil (the default) means "no workspace known" and disables rule evaluation only.
    public var workspaceRoot: URL?
    /// A narrowly scoped marker for the one user-requested retry of an exact prior denial.
    /// Reviewers still evaluate the action normally and may deny it again.
    public var reviewAttempt: ApprovalReviewAttempt

    public init(
        mode: AgentMode,
        userMessage: String,
        toolCall: ToolCall,
        toolDefinition: ToolDefinition?,
        recentMessages: [ChatMessage],
        workspaceRoot: URL? = nil,
        reviewAttempt: ApprovalReviewAttempt = .initial
    ) {
        self.mode = mode
        self.userMessage = userMessage
        self.toolCall = toolCall
        self.toolDefinition = toolDefinition
        self.recentMessages = recentMessages
        self.workspaceRoot = workspaceRoot
        self.reviewAttempt = reviewAttempt
    }
}

public struct SafetyReview: Codable, Sendable, Hashable {
    public var verdict: ApprovalVerdict
    public var rationale: String
    public var reviewerModel: String?
    public var userIntentMatched: Bool
    public var reviewTelemetry: ApprovalReviewTelemetry?
    public var reviewOutcome: ApprovalReviewOutcome
    public var riskLevel: ApprovalRiskLevel
    public var userAuthorization: ApprovalUserAuthorization

    public init(
        verdict: ApprovalVerdict,
        rationale: String,
        reviewerModel: String? = nil,
        userIntentMatched: Bool = false,
        reviewTelemetry: ApprovalReviewTelemetry? = nil,
        reviewOutcome: ApprovalReviewOutcome? = nil,
        riskLevel: ApprovalRiskLevel = .unknown,
        userAuthorization: ApprovalUserAuthorization = .unknown
    ) {
        self.verdict = verdict
        self.rationale = rationale
        self.reviewerModel = reviewerModel
        self.userIntentMatched = userIntentMatched
        self.reviewTelemetry = reviewTelemetry
        self.reviewOutcome = reviewOutcome ?? ApprovalReviewOutcome(verdict: verdict)
        self.riskLevel = riskLevel
        self.userAuthorization = userAuthorization
    }
}

public extension SafetyReview {
    func withReviewTelemetry(_ telemetry: ApprovalReviewTelemetry) -> SafetyReview {
        var copy = self
        var enrichedTelemetry = telemetry
        if enrichedTelemetry.riskLevel == nil {
            enrichedTelemetry.riskLevel = copy.riskLevel
        }
        if enrichedTelemetry.userAuthorization == nil {
            enrichedTelemetry.userAuthorization = copy.userAuthorization
        }
        copy.reviewTelemetry = enrichedTelemetry
        if copy.reviewerModel == nil {
            copy.reviewerModel = enrichedTelemetry.reviewerModel
        }
        return copy
    }
}

public protocol SafetyReviewer: Sendable {
    func review(_ context: SafetyContext) async -> SafetyReview
}

public protocol SafetyModelClient: Sendable {
    func review(prompt: String, model: String) async throws -> String
}

enum ExplicitApprovalPolicy {
    static let workflowRecordingStartTool = "host.workflow.record.start"

    static func review(for context: SafetyContext) -> SafetyReview? {
        guard context.toolCall.name == workflowRecordingStartTool,
              context.mode == .auto || context.mode == .review || context.mode == .plan
        else {
            return nil
        }
        return SafetyReview(
            verdict: .clarify,
            rationale: "Workflow recording captures screenshots and typed text across applications. That content is "
                + "sent to TrustedRouter to create the skill. Password fields are redacted. "
                + "One explicit confirmation is required.",
            userIntentMatched: true
        ).withReviewTelemetry(.init(
            source: .staticPolicy,
            fallbackReason: .explicitApprovalRequired
        ))
    }
}

public struct StaticSafetyReviewer: SafetyReviewer {
    private let policy = StaticSafetyPolicy()

    public init() {}

    public func review(_ context: SafetyContext) async -> SafetyReview {
        if let explicitReview = ExplicitApprovalPolicy.review(for: context) {
            return explicitReview
        }
        let review: SafetyReview = switch context.mode {
        case .readOnly:
            if context.toolDefinition?.risk == .read {
                lowRiskReview(context)
            } else {
                SafetyReview(
                    verdict: .deny,
                    rationale: "Read-only mode blocks file writes, shell mutations, and destructive tools."
                )
            }
        case .review:
            if context.toolDefinition?.risk == .read {
                lowRiskReview(context)
            } else {
                SafetyReview(
                    verdict: .clarify,
                    rationale: "Review mode requires explicit approval before this tool runs.",
                    userIntentMatched: userIntentMatches(context)
                )
            }
        case .plan:
            // Plan mode investigates read-only and proposes a plan; every mutating tool is
            // blocked until the user approves it (which applies that step and starts executing).
            // It returns `.clarify`, NOT `.deny`: the agent loop blocks on any non-`.approve`
            // verdict either way, but `.deny` is the hard "no approval possible" signal (e.g.
            // `rm -rf /`) that suppresses the approve button — a plan block must stay approvable.
            if context.toolDefinition?.risk == .read {
                lowRiskReview(context)
            } else {
                SafetyReview(
                    verdict: .clarify,
                    rationale: "Planning — approve the proposed change to apply it and start executing.",
                    userIntentMatched: userIntentMatches(context)
                )
            }
        case .auto:
            if let hardDeny = hardDenyReason(context) {
                SafetyReview(verdict: .deny, rationale: hardDeny)
            } else if context.toolDefinition?.risk == .read || userIntentMatches(context) {
                lowRiskReview(context)
            } else {
                SafetyReview(
                    verdict: .clarify,
                    rationale: "The requested tool action does not clearly match the latest user message."
                )
            }
        }
        return review.withReviewTelemetry(.init(source: .staticPolicy))
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
        if let explicitReview = ExplicitApprovalPolicy.review(for: context) {
            return explicitReview
        }
        let baseline = await staticReviewer.review(context)
        guard context.mode == .auto else {
            return baseline.withReviewTelemetry(.init(
                source: .staticPolicy,
                fallbackReason: .nonAutoMode
            ))
        }
        if baseline.verdict == .deny {
            return baseline.withReviewTelemetry(.init(
                source: .staticPolicy,
                fallbackReason: .staticDenied
            ))
        }
        guard let client else {
            return baseline.withReviewTelemetry(.init(
                source: .staticPolicy,
                fallbackReason: .missingReviewerClient
            ))
        }

        let prompt = Self.prompt(for: context)
        do {
            return try parse(
                try await client.review(prompt: prompt, model: primaryModel),
                model: primaryModel
            ).withReviewTelemetry(.init(
                source: .primaryModel,
                reviewerModel: primaryModel,
                attemptedModels: [primaryModel]
            ))
        } catch let primaryError {
            do {
                return try parse(
                    try await client.review(prompt: prompt, model: fallbackModel),
                    model: fallbackModel
                ).withReviewTelemetry(.init(
                    source: .fallbackModel,
                    reviewerModel: fallbackModel,
                    attemptedModels: [primaryModel, fallbackModel],
                    fallbackReason: .primaryModelFailed,
                    errorSummary: Self.errorSummary(primaryError)
                ))
            } catch let fallbackError {
                return baseline.withReviewTelemetry(.init(
                    source: .staticPolicy,
                    attemptedModels: [primaryModel, fallbackModel],
                    fallbackReason: .allModelsFailed,
                    errorSummary: Self.combinedErrorSummary(primary: primaryError, fallback: fallbackError)
                ))
            }
        }
    }

    static func prompt(for context: SafetyContext) -> String {
        let recent = context.recentMessages.suffix(8)
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
        let retryGuidance: String
        if context.reviewAttempt.kind == .denialOverride,
           let deniedRequestID = context.reviewAttempt.retryOfRequestID {
            retryGuidance = """

            Developer-scoped denial retry:
            - The user selected the exact denied action \(deniedRequestID) from Auto-review Denials.
            - This marker authorizes one new review, not automatic execution and not a workaround.
            - Approve only if policy permits this exact action. Deny again when policy disallows an override.
            """
        } else {
            retryGuidance = ""
        }
        return """
        You are QuillCode's Auto safety reviewer. Decide whether one proposed tool call should run.

        Classify only this tool call:
        - approve: the latest user request clearly asked for this target and the action is bounded, reversible, or read-only. Do not over-block diagnostics, project-local file creation, git status/diff, or shell reads.
        - clarify: required arguments are missing or empty, the target is ambiguous, or the call does not clearly match the latest user request.
        - deny: the call exfiltrates credentials, adds unrelated extra actions, performs broad destructive work, weakens security persistently, or makes irreversible disk/account changes.

        Approve PR merge/automerge only when the latest user request explicitly asks to merge that PR. If a shell command chains unrelated work beyond the request, deny or clarify even when its first command is safe.

        Return only JSON:
        {"verdict":"approve|deny|clarify","rationale":"one sentence","userIntentMatched":true|false,"riskLevel":"low|medium|high|critical","userAuthorization":"explicit|implicit|missing|mismatched"}
        \(retryGuidance)

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
            var riskLevel: ApprovalRiskLevel?
            var userAuthorization: ApprovalUserAuthorization?
        }
        let data = Data(Self.reviewJSONPayload(from: json).utf8)
        let decoded = try JSONDecoder().decode(Wire.self, from: data)
        return SafetyReview(
            verdict: decoded.verdict,
            rationale: decoded.rationale,
            reviewerModel: model,
            userIntentMatched: decoded.userIntentMatched,
            riskLevel: decoded.riskLevel ?? .unknown,
            userAuthorization: decoded.userAuthorization ?? (decoded.userIntentMatched ? .implicit : .missing)
        )
    }

    private static func reviewJSONPayload(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }

        var lines = trimmed.components(separatedBy: .newlines)
        guard
            let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            first == "```" || first.lowercased() == "```json",
            let last = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
            last == "```"
        else {
            return trimmed
        }

        lines.removeFirst()
        lines.removeLast()
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func combinedErrorSummary(primary: Error, fallback: Error) -> String {
        "primary: \(errorSummary(primary)); fallback: \(errorSummary(fallback))"
    }

    private static func errorSummary(_ error: Error) -> String {
        let singleLine = String(describing: error)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(180))
    }
}
