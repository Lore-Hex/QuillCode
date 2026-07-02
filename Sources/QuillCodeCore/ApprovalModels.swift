import Foundation

public enum ApprovalVerdict: String, Codable, Sendable {
    case approve
    case deny
    case clarify
}

public struct ApprovalRequest: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var toolCall: ToolCall
    public var toolDefinition: ToolDefinition?
    public var reason: String
    public var recommendedVerdict: ApprovalVerdict?
    public var reviewTelemetry: ApprovalReviewTelemetry?

    public init(
        id: String = "approval-\(UUID().uuidString)",
        toolCall: ToolCall,
        toolDefinition: ToolDefinition?,
        reason: String,
        recommendedVerdict: ApprovalVerdict? = nil,
        reviewTelemetry: ApprovalReviewTelemetry? = nil
    ) {
        self.id = id
        self.toolCall = toolCall
        self.toolDefinition = toolDefinition
        self.reason = reason
        self.recommendedVerdict = recommendedVerdict
        self.reviewTelemetry = reviewTelemetry
    }
}

public struct ApprovalDecision: Codable, Sendable, Hashable {
    public var requestID: String
    public var verdict: ApprovalVerdict
    public var rationale: String
    public var reviewTelemetry: ApprovalReviewTelemetry?

    public init(
        requestID: String,
        verdict: ApprovalVerdict,
        rationale: String,
        reviewTelemetry: ApprovalReviewTelemetry? = nil
    ) {
        self.requestID = requestID
        self.verdict = verdict
        self.rationale = rationale
        self.reviewTelemetry = reviewTelemetry
    }
}

public enum ApprovalReviewSource: String, Codable, Sendable, Hashable {
    case staticPolicy = "static_policy"
    case primaryModel = "primary_model"
    case fallbackModel = "fallback_model"
    case permissionRule = "permission_rule"
}

public enum ApprovalReviewFallbackReason: String, Codable, Sendable, Hashable {
    case nonAutoMode = "non_auto_mode"
    case staticDenied = "static_denied"
    case missingReviewerClient = "missing_reviewer_client"
    case primaryModelFailed = "primary_model_failed"
    case allModelsFailed = "all_models_failed"
    case permissionRulesUnavailable = "permission_rules_unavailable"
    case permissionRuleDenied = "permission_rule_denied"
    case permissionRuleAllowed = "permission_rule_allowed"
    case permissionRuleAsked = "permission_rule_asked"
}

public struct ApprovalReviewTelemetry: Codable, Sendable, Hashable {
    public var source: ApprovalReviewSource
    public var reviewerModel: String?
    public var attemptedModels: [String]
    public var fallbackReason: ApprovalReviewFallbackReason?
    public var errorSummary: String?

    public init(
        source: ApprovalReviewSource,
        reviewerModel: String? = nil,
        attemptedModels: [String] = [],
        fallbackReason: ApprovalReviewFallbackReason? = nil,
        errorSummary: String? = nil
    ) {
        self.source = source
        self.reviewerModel = reviewerModel
        self.attemptedModels = attemptedModels
        self.fallbackReason = fallbackReason
        self.errorSummary = errorSummary
    }
}
