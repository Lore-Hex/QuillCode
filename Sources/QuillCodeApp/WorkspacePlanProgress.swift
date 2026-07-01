import Foundation

/// A compact, glanceable snapshot of how far the current run has gotten through its authored plan —
/// the model behind the always-visible plan-progress rail. Placement-agnostic: it is a plain
/// Codable/Sendable value so it can ride any surface (composer / transcript / top bar); the placement
/// owns visibility + dimming policy, this stays a dumb, total function of the plan.
public struct WorkspacePlanProgress: Codable, Sendable, Hashable {
    /// Number of steps in the plan (1...12; the invariant is enforced upstream by PlanUpdateToolExecutor).
    public var totalCount: Int
    /// Steps marked `.completed`.
    public var completedCount: Int
    /// 1-based index of the step to surface (the in-progress step, else the next pending, else the last).
    public var currentStepIndex: Int
    /// Text of the surfaced step, bounded for a single-line display.
    public var currentStepTitle: String
    /// Whether the agent is actively working (shared `AgentStatusClassifier`, so it can't drift from the
    /// Activity pane's notion of "running").
    public var isRunning: Bool
    /// Whether every step is completed.
    public var isComplete: Bool
    /// Bar fill, 0...1. Monotone in completed count, with a half-step of credit while a step is in
    /// progress so a long step reads as "partway" rather than stalled.
    public var fraction: Double
    /// Pre-formatted "k/N" step counter, e.g. "3/7".
    public var stepCounterLabel: String

    public init(
        totalCount: Int,
        completedCount: Int,
        currentStepIndex: Int,
        currentStepTitle: String,
        isRunning: Bool,
        isComplete: Bool,
        fraction: Double,
        stepCounterLabel: String
    ) {
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.currentStepIndex = currentStepIndex
        self.currentStepTitle = currentStepTitle
        self.isRunning = isRunning
        self.isComplete = isComplete
        self.fraction = fraction
        self.stepCounterLabel = stepCounterLabel
    }
}
