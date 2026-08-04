import Foundation

/// Failure-count-aware escalation for corrective re-prompts (Cline learning #1,
/// docs/CLINE_TOOL_LEARNINGS.md).
///
/// Every corrective loop in the runner used to send the SAME text on each attempt — a model that
/// ignored the first correction saw nothing new and usually repeated itself. Cline's standout
/// tool-feedback pattern escalates instead: early attempts diagnose and suggest; the final
/// budgeted attempt switches to a directive form that forbids repeating the response and offers
/// an explicit, numbered choice of ways out. The correction must teach an alternative, never
/// just restate the rule.
enum AgentCorrectionEscalation {
    /// Wraps `base` with the final-attempt directive once the loop reaches its last budgeted
    /// attempt. `attempt` is 0-based; earlier attempts pass `base` through unchanged so the
    /// first correction stays diagnostic.
    static func escalated(
        _ base: String,
        attempt: Int,
        limit: Int,
        alternatives: [String]
    ) -> String {
        guard limit > 1, attempt >= limit - 1 else { return base }
        let numbered = alternatives.enumerated()
            .map { "(\($0.offset + 1)) \($0.element)" }
            .joined(separator: " ")
        return """
        FINAL ATTEMPT (\(attempt + 1) of \(limit)): your previous response ignored this same \
        correction. Do NOT repeat that response. You must now do exactly ONE of the following: \
        \(numbered)

        \(base)
        """
    }
}
