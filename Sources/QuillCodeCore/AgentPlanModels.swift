public enum AgentPlanItemStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case completed

    public var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .inProgress:
            return "Running"
        case .completed:
            return "Done"
        }
    }
}

public struct AgentPlanItem: Codable, Sendable, Hashable {
    public var step: String
    public var status: AgentPlanItemStatus
    public var detail: String?

    public init(step: String, status: AgentPlanItemStatus, detail: String? = nil) {
        self.step = step
        self.status = status
        self.detail = detail
    }
}

public struct AgentPlanUpdate: Codable, Sendable, Hashable {
    public var explanation: String?
    public var plan: [AgentPlanItem]

    public init(explanation: String? = nil, plan: [AgentPlanItem]) {
        self.explanation = explanation
        self.plan = plan
    }
}

public struct AgentHandoffUpdate: Codable, Sendable, Hashable {
    public var summary: String
    public var nextSteps: [String]

    public init(summary: String, nextSteps: [String] = []) {
        self.summary = summary
        self.nextSteps = nextSteps
    }
}
