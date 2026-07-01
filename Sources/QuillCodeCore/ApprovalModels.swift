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

    public init(
        id: String = "approval-\(UUID().uuidString)",
        toolCall: ToolCall,
        toolDefinition: ToolDefinition?,
        reason: String,
        recommendedVerdict: ApprovalVerdict? = nil
    ) {
        self.id = id
        self.toolCall = toolCall
        self.toolDefinition = toolDefinition
        self.reason = reason
        self.recommendedVerdict = recommendedVerdict
    }
}

public struct ApprovalDecision: Codable, Sendable, Hashable {
    public var requestID: String
    public var verdict: ApprovalVerdict
    public var rationale: String

    public init(requestID: String, verdict: ApprovalVerdict, rationale: String) {
        self.requestID = requestID
        self.verdict = verdict
        self.rationale = rationale
    }
}
