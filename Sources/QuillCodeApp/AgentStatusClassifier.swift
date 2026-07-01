import Foundation

/// The single source of truth for "is the agent actively working right now", derived from the
/// free-form agent-status label (Running / Streaming / Queued / Terminal / Idle / Failed / …).
///
/// Two surfaces need this same judgement — the Activity pane's plan status and the composer
/// plan-progress strip — and before this they each had their own copy of the predicate, which is
/// exactly how a run's liveness silently drifts between surfaces. Routing both through one classifier
/// keeps them in lockstep. (The top bar's status *tone* is a separate visual mapping and intentionally
/// stays independent.)
public enum AgentStatusClassifier {
    public static func isActive(_ agentStatus: String) -> Bool {
        let normalized = agentStatus.lowercased()
        return normalized.contains("running")
            || normalized.contains("streaming")
            || normalized.contains("queued")
            || normalized.contains("terminal")
    }
}
