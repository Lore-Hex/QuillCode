import Foundation
import QuillCodeCore

public struct WorkspaceSubagentTranscriptSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var workerID: String
    public var title: String
    public var role: String
    public var objective: String
    public var status: SubagentStatus
    public var statusLabel: String { status.label }
    public var summary: String?
    public var transcript: TranscriptSurface

    init(
        parentThreadID: UUID,
        run: SubagentRunRecord,
        worker: SubagentWorkerRecord,
        thread: ChatThread
    ) {
        id = "\(parentThreadID.uuidString):\(run.id.uuidString):\(worker.id)"
        workerID = worker.id
        title = worker.name
        role = worker.role
        objective = run.objective
        status = worker.status
        summary = worker.summary

        let builder = WorkspaceTranscriptSurfaceBuilder(thread: thread, allowsRevert: false)
        transcript = TranscriptSurface(
            messages: builder.messageSurfaces(),
            toolCards: builder.toolCards().map {
                Self.contextualized($0, parentThreadID: parentThreadID, run: run, worker: worker)
            },
            timelineItems: builder.timelineItems().map { item in
                guard var card = item.toolCard else { return item }
                card = Self.contextualized(
                    card,
                    parentThreadID: parentThreadID,
                    run: run,
                    worker: worker
                )
                return .toolCard(card)
            },
            emptyStarterActions: []
        )
    }

    private static func contextualized(
        _ card: ToolCardState,
        parentThreadID: UUID,
        run: SubagentRunRecord,
        worker: SubagentWorkerRecord
    ) -> ToolCardState {
        var card = card
        // A child transcript has no independent composer, so Edit and persistent-rule actions are
        // intentionally withheld. Run and Skip are complete, unambiguous decisions that can be
        // resumed against the exact child snapshot after relaunch.
        card.actions = card.actions.compactMap { action in
            guard action.kind == .approve || action.kind == .deny else { return nil }
            guard let pending = worker.pendingApproval, pending.requestID == action.requestID else { return nil }
            var action = action
            action.subagentTarget = WorkspaceSubagentApprovalTarget(
                parentThreadID: parentThreadID,
                runID: run.id,
                workerID: worker.id,
                generation: pending.generation
            )
            action.id = "\(action.id)-subagent-\(worker.id)-\(pending.generation)"
            return action
        }
        return card
    }
}
