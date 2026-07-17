import Foundation
import QuillCodeCore

public struct AutoReviewDenialsSurface: Codable, Sendable, Hashable {
    public var items: [AutoReviewDenialItemSurface]
    public var retryingRequestID: String?

    public init(items: [AutoReviewDenialItemSurface], retryingRequestID: String? = nil) {
        self.items = items
        self.retryingRequestID = retryingRequestID
    }
}

public struct AutoReviewDenialItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { requestID }
    public var requestID: String
    public var toolName: String
    public var actionSummary: String
    public var reason: String
    public var createdAt: Date
    public var riskLabel: String?
    public var authorizationLabel: String?
    public var retryState: AutoReviewDenialRetryState
    public var retryCommandID: String

    public var canRetry: Bool { retryState == .available }

    public init(
        requestID: String,
        toolName: String,
        actionSummary: String,
        reason: String,
        createdAt: Date,
        riskLabel: String? = nil,
        authorizationLabel: String? = nil,
        retryState: AutoReviewDenialRetryState,
        retryCommandID: String
    ) {
        self.requestID = requestID
        self.toolName = toolName
        self.actionSummary = actionSummary
        self.reason = reason
        self.createdAt = createdAt
        self.riskLabel = riskLabel
        self.authorizationLabel = authorizationLabel
        self.retryState = retryState
        self.retryCommandID = retryCommandID
    }
}

enum AutoReviewDenialsSurfaceBuilder {
    static func surface(
        thread: ChatThread?,
        workspaceRoot: URL?,
        retryingRequestID: String?
    ) -> AutoReviewDenialsSurface {
        guard let thread else {
            return AutoReviewDenialsSurface(items: [], retryingRequestID: retryingRequestID)
        }
        let records = AutoReviewDenialHistory.records(in: thread, workspaceRoot: workspaceRoot)
        return AutoReviewDenialsSurface(
            items: records.map(item),
            retryingRequestID: retryingRequestID
        )
    }

    private static func item(_ record: AutoReviewDenialRecord) -> AutoReviewDenialItemSurface {
        let telemetry = record.decision.reviewTelemetry ?? record.request.reviewTelemetry
        return AutoReviewDenialItemSurface(
            requestID: record.id,
            toolName: WorkspaceToolDisplayNameBuilder.displayName(for: record.request.toolCall.name),
            actionSummary: WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Denied",
                toolName: record.request.toolCall.name,
                inputJSON: record.request.toolCall.argumentsJSON
            ),
            reason: record.decision.rationale,
            createdAt: record.createdAt,
            riskLabel: telemetry?.riskLevel.map(label),
            authorizationLabel: telemetry?.userAuthorization.map(label),
            retryState: record.retryState,
            retryCommandID: WorkspaceCommandPlan.autoReviewDenialRetryCommandID(record.id)
        )
    }

    private static func label(_ risk: ApprovalRiskLevel) -> String {
        risk.rawValue.capitalized
    }

    private static func label(_ authorization: ApprovalUserAuthorization) -> String {
        switch authorization {
        case .explicit: "Explicit request"
        case .implicit: "Implied request"
        case .missing: "No request found"
        case .mismatched: "Request mismatch"
        case .unknown: "Unknown intent"
        }
    }
}
