import QuillCodeAgent

/// Formats a retry event into the user-facing thread notice. Pure + testable. The wording leads with
/// "Self-healing" (house style — not "Fixing error") and names the cause so the row reads as reassuring
/// competence ("it handled a rate limit for you") rather than an alarm.
enum SelfHealingNoticePlanner {
    static func noticeSummary(attempt: Int, kind: TransientFailureClass) -> String {
        "Self-healing: retrying after a \(causeLabel(kind)) (attempt \(attempt))"
    }

    private static func causeLabel(_ kind: TransientFailureClass) -> String {
        switch kind {
        case .rateLimited:
            return "rate limit"
        case .serverOverloaded:
            return "server overload"
        case .transport:
            return "network error"
        case .none:
            return "transient error"
        }
    }
}
