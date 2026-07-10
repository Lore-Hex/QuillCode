import Foundation
import QuillCodeCore

enum WorkspaceThreadGoalMutation: Equatable {
    case unchanged
    case replace(ThreadGoal?)
}

struct WorkspaceThreadGoalOutcome: Equatable {
    var mutation: WorkspaceThreadGoalMutation
    var assistantText: String
}

enum WorkspaceThreadGoalEngine {
    static func apply(
        _ request: WorkspaceThreadGoalRequest,
        to currentGoal: ThreadGoal?,
        now: Date = Date()
    ) -> WorkspaceThreadGoalOutcome {
        switch request {
        case .show:
            return WorkspaceThreadGoalOutcome(
                mutation: .unchanged,
                assistantText: statusText(for: currentGoal)
            )
        case .set(let objective):
            guard let goal = ThreadGoal(objective: objective, createdAt: now, updatedAt: now) else {
                return WorkspaceThreadGoalOutcome(mutation: .unchanged, assistantText: SlashGoalCommandParser.usage)
            }
            return WorkspaceThreadGoalOutcome(
                mutation: .replace(goal),
                assistantText: "Goal started: \(goal.objective)"
            )
        case .complete:
            guard let currentGoal else { return missingGoalOutcome }
            guard currentGoal.status != .completed else {
                return WorkspaceThreadGoalOutcome(
                    mutation: .unchanged,
                    assistantText: "Goal is already complete: \(currentGoal.objective)"
                )
            }
            let goal = currentGoal.updating(status: .completed, at: now)
            return WorkspaceThreadGoalOutcome(
                mutation: .replace(goal),
                assistantText: "Goal completed: \(goal.objective)"
            )
        case .block(let reason):
            guard let currentGoal else { return missingGoalOutcome }
            let goal = currentGoal.updating(status: .blocked, blocker: reason, at: now)
            return WorkspaceThreadGoalOutcome(
                mutation: .replace(goal),
                assistantText: "Goal blocked: \(goal.objective)\nBlocker: \(reason)"
            )
        case .resume:
            guard let currentGoal else { return missingGoalOutcome }
            guard currentGoal.status != .active else {
                return WorkspaceThreadGoalOutcome(
                    mutation: .unchanged,
                    assistantText: "Goal is already active: \(currentGoal.objective)"
                )
            }
            let goal = currentGoal.updating(status: .active, at: now)
            return WorkspaceThreadGoalOutcome(
                mutation: .replace(goal),
                assistantText: "Goal resumed: \(goal.objective)"
            )
        case .clear:
            guard currentGoal != nil else { return missingGoalOutcome }
            return WorkspaceThreadGoalOutcome(
                mutation: .replace(nil),
                assistantText: "Cleared this chat's durable goal."
            )
        }
    }

    static func statusText(for goal: ThreadGoal?) -> String {
        guard let goal else {
            return "No durable goal is attached to this chat. Start one with `/goal objective`."
        }
        var lines = [
            "Goal: \(goal.objective)",
            "Status: \(statusLabel(goal.status))"
        ]
        if let blocker = goal.blocker {
            lines.append("Blocker: \(blocker)")
        }
        return lines.joined(separator: "\n")
    }

    private static var missingGoalOutcome: WorkspaceThreadGoalOutcome {
        WorkspaceThreadGoalOutcome(
            mutation: .unchanged,
            assistantText: "No durable goal is attached to this chat. Start one with `/goal objective`."
        )
    }

    private static func statusLabel(_ status: ThreadGoalStatus) -> String {
        switch status {
        case .active: "Active"
        case .blocked: "Blocked"
        case .completed: "Completed"
        }
    }
}
