import Foundation

public enum ApprovalVerdict: String, Codable, Sendable {
    case approve
    case deny
    case clarify
}

public struct ApprovalRequest: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var scope: ApprovalRequestScope
    public var toolCall: ToolCall
    public var toolDefinition: ToolDefinition?
    public var reason: String
    public var recommendedVerdict: ApprovalVerdict?
    public var reviewTelemetry: ApprovalReviewTelemetry?
    /// Stable, presentation-safe identity for the exact reviewed action and its execution context.
    /// Nil preserves approval events written before Auto-review denial recovery existed.
    public var actionIdentity: ApprovalActionIdentity?
    /// Whether this is the first review or the one allowed retry of a prior Auto denial.
    public var reviewAttempt: ApprovalReviewAttempt

    public init(
        id: String = "approval-\(UUID().uuidString)",
        scope: ApprovalRequestScope = .tool,
        toolCall: ToolCall,
        toolDefinition: ToolDefinition?,
        reason: String,
        recommendedVerdict: ApprovalVerdict? = nil,
        reviewTelemetry: ApprovalReviewTelemetry? = nil,
        actionIdentity: ApprovalActionIdentity? = nil,
        reviewAttempt: ApprovalReviewAttempt = .initial
    ) {
        self.id = id
        self.scope = scope
        self.toolCall = toolCall
        self.toolDefinition = toolDefinition
        self.reason = reason
        self.recommendedVerdict = recommendedVerdict
        self.reviewTelemetry = reviewTelemetry
        self.actionIdentity = actionIdentity
        self.reviewAttempt = reviewAttempt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scope
        case toolCall
        case toolDefinition
        case reason
        case recommendedVerdict
        case reviewTelemetry
        case actionIdentity
        case reviewAttempt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            scope: try container.decodeIfPresent(ApprovalRequestScope.self, forKey: .scope) ?? .tool,
            toolCall: try container.decode(ToolCall.self, forKey: .toolCall),
            toolDefinition: try container.decodeIfPresent(ToolDefinition.self, forKey: .toolDefinition),
            reason: try container.decode(String.self, forKey: .reason),
            recommendedVerdict: try container.decodeIfPresent(ApprovalVerdict.self, forKey: .recommendedVerdict),
            reviewTelemetry: try container.decodeIfPresent(ApprovalReviewTelemetry.self, forKey: .reviewTelemetry),
            actionIdentity: try container.decodeIfPresent(ApprovalActionIdentity.self, forKey: .actionIdentity),
            reviewAttempt: try container.decodeIfPresent(ApprovalReviewAttempt.self, forKey: .reviewAttempt) ?? .initial
        )
    }
}

public struct ApprovalDecision: Codable, Sendable, Hashable {
    public var requestID: String
    public var verdict: ApprovalVerdict
    public var rationale: String
    public var reviewTelemetry: ApprovalReviewTelemetry?
    public var reviewOutcome: ApprovalReviewOutcome

    public init(
        requestID: String,
        verdict: ApprovalVerdict,
        rationale: String,
        reviewTelemetry: ApprovalReviewTelemetry? = nil,
        reviewOutcome: ApprovalReviewOutcome? = nil
    ) {
        self.requestID = requestID
        self.verdict = verdict
        self.rationale = rationale
        self.reviewTelemetry = reviewTelemetry
        self.reviewOutcome = reviewOutcome ?? ApprovalReviewOutcome(verdict: verdict)
    }

    private enum CodingKeys: String, CodingKey {
        case requestID
        case verdict
        case rationale
        case reviewTelemetry
        case reviewOutcome
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let verdict = try container.decode(ApprovalVerdict.self, forKey: .verdict)
        self.init(
            requestID: try container.decode(String.self, forKey: .requestID),
            verdict: verdict,
            rationale: try container.decode(String.self, forKey: .rationale),
            reviewTelemetry: try container.decodeIfPresent(ApprovalReviewTelemetry.self, forKey: .reviewTelemetry),
            reviewOutcome: try container.decodeIfPresent(ApprovalReviewOutcome.self, forKey: .reviewOutcome)
        )
    }
}

public enum ApprovalRequestScope: String, Codable, Sendable, Hashable {
    case tool
    case runSpendFuse = "run_spend_fuse"
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
    case explicitApprovalRequired = "explicit_approval_required"
}

public struct ApprovalReviewTelemetry: Codable, Sendable, Hashable {
    public var source: ApprovalReviewSource
    public var reviewerModel: String?
    public var attemptedModels: [String]
    public var fallbackReason: ApprovalReviewFallbackReason?
    public var errorSummary: String?
    public var riskLevel: ApprovalRiskLevel?
    public var userAuthorization: ApprovalUserAuthorization?

    public init(
        source: ApprovalReviewSource,
        reviewerModel: String? = nil,
        attemptedModels: [String] = [],
        fallbackReason: ApprovalReviewFallbackReason? = nil,
        errorSummary: String? = nil,
        riskLevel: ApprovalRiskLevel? = nil,
        userAuthorization: ApprovalUserAuthorization? = nil
    ) {
        self.source = source
        self.reviewerModel = reviewerModel
        self.attemptedModels = attemptedModels
        self.fallbackReason = fallbackReason
        self.errorSummary = errorSummary
        self.riskLevel = riskLevel
        self.userAuthorization = userAuthorization
    }
}
