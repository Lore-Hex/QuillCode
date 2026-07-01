import Foundation
import QuillCodeCore

/// Derives the `WorkspacePlanProgress` snapshot for the plan-progress rail from a thread's latest
/// authored plan. Pure: a function of (thread events, agent-status string) — no clock, no I/O — so it
/// is fully unit-testable and recomputes deterministically on every surface rebuild.
enum WorkspacePlanProgressBuilder {
    /// Entry point. Returns nil when there is no authored plan to show — callers treat nil as "render
    /// nothing", so a session with no plan looks byte-identical to today.
    static func progress(for thread: ChatThread?, agentStatus: String) -> WorkspacePlanProgress? {
        guard let thread, let update = PlanUpdateToolExecutor.latestUpdate(in: thread) else { return nil }
        return progress(from: update, agentStatus: agentStatus)
    }

    /// Pure core — the real unit-test target; takes an `AgentPlanUpdate` directly, no ChatThread needed.
    static func progress(from update: AgentPlanUpdate, agentStatus: String) -> WorkspacePlanProgress? {
        let plan = update.plan
        guard !plan.isEmpty else { return nil }

        let totalCount = plan.count
        let completedCount = plan.filter { $0.status == .completed }.count

        // The step to surface: the single in-progress item (≤1 by invariant), else the first pending
        // (next up), else the last item (everything done). Always clamped into 1...totalCount.
        let zeroBased = plan.firstIndex { $0.status == .inProgress }
            ?? plan.firstIndex { $0.status == .pending }
            ?? (totalCount - 1)
        let currentStepIndex = min(max(zeroBased + 1, 1), totalCount)
        let currentStepTitle = WorkspaceActivityText.boundedLine(plan[currentStepIndex - 1].step, limit: 80)

        let isRunning = AgentStatusClassifier.isActive(agentStatus)
        let isComplete = completedCount == totalCount

        // Fraction = completed/total, plus half a step of credit while a step is in progress (so a long
        // step reads as partway, never regressing), clamped, and forced to 1 when complete (defensive
        // against a stale lingering in-progress alongside all-completed). This reflects the plan's
        // AUTHORED state, independent of liveness — a frozen in-progress step still shows where it stalled.
        let hasInProgress = plan.contains { $0.status == .inProgress }
        let raw = isComplete ? 1.0 : (Double(completedCount) + (hasInProgress ? 0.5 : 0.0)) / Double(totalCount)
        let fraction = min(1.0, max(0.0, raw))

        return WorkspacePlanProgress(
            totalCount: totalCount,
            completedCount: completedCount,
            currentStepIndex: currentStepIndex,
            currentStepTitle: currentStepTitle,
            isRunning: isRunning,
            isComplete: isComplete,
            fraction: fraction,
            stepCounterLabel: "\(currentStepIndex)/\(totalCount)"
        )
    }
}
