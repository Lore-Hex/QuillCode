public enum AgentMode: String, Codable, Sendable, CaseIterable {
    case readOnly = "read-only"
    case review
    case auto
    // Appended so existing cases keep their discriminants. Menu order is set explicitly below.
    case plan

    public static let cycleOrder: [AgentMode] = [.auto, .plan, .review, .readOnly]
}
