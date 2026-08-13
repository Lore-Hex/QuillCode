import Foundation
import QuillCodeCore

struct WorkspaceAgentRunRelaunchReconciliation: Sendable, Hashable {
    var threads: [ChatThread]
    var changedThreadIDs: Set<UUID>
    var interruptedThreadIDs: Set<UUID>
}

/// Closes parent-chat work that belonged to a process which no longer exists.
///
/// A final assistant message or durable approval request is already a safe terminal boundary, so
/// those checkpoints are cleared silently. Every other checkpoint becomes a visible, retryable
/// interruption. An open tool receives a terminal event first so no transcript card stays Running.
enum WorkspaceAgentRunRelaunchReconciler {
    static let toolFailureSummary = "Interrupted when Quill Cowork closed"
    static let toolFailurePayloadJSON =
        #"{"ok":false,"error":"Interrupted when Quill Cowork closed before this tool finished."}"#
    static let recoveryMessage = WorkspaceRunFailureNoticePlanner.interruptedRelaunchDiagnostic

    static func reconcile(
        _ threads: [ChatThread],
        now: Date = Date()
    ) -> WorkspaceAgentRunRelaunchReconciliation {
        var reconciled = threads
        var changedThreadIDs = Set<UUID>()
        var interruptedThreadIDs = Set<UUID>()

        for index in reconciled.indices {
            guard let checkpoint = reconciled[index].activeRunCheckpoint else { continue }
            let disposition = disposition(of: reconciled[index], checkpoint: checkpoint)
            reconciled[index].activeRunCheckpoint = nil
            changedThreadIDs.insert(reconciled[index].id)

            guard disposition == .interrupted else { continue }
            if hasOpenTool(in: reconciled[index], checkpoint: checkpoint) {
                reconciled[index].events.append(ThreadEvent(
                    kind: .toolFailed,
                    createdAt: now,
                    summary: toolFailureSummary,
                    payloadJSON: toolFailurePayloadJSON
                ))
            }
            reconciled[index].events.append(ThreadEvent(
                kind: .notice,
                createdAt: now,
                summary: WorkspaceRunFailureNoticePlanner.interruptedRelaunchSummary
            ))
            reconciled[index].updatedAt = max(reconciled[index].updatedAt, now)
            interruptedThreadIDs.insert(reconciled[index].id)
        }

        return WorkspaceAgentRunRelaunchReconciliation(
            threads: reconciled,
            changedThreadIDs: changedThreadIDs,
            interruptedThreadIDs: interruptedThreadIDs
        )
    }

    private enum Disposition {
        case completed
        case approval
        case interrupted
    }

    private static func disposition(
        of thread: ChatThread,
        checkpoint: ThreadRunCheckpoint
    ) -> Disposition {
        let messageBoundary = min(checkpoint.messageCountAtStart, thread.messages.count)
        if thread.messages.dropFirst(messageBoundary).contains(where: { $0.role == .assistant }) {
            return .completed
        }
        if hasUndecidedApproval(in: thread, checkpoint: checkpoint) {
            return .approval
        }
        return .interrupted
    }

    private static func hasUndecidedApproval(
        in thread: ChatThread,
        checkpoint: ThreadRunCheckpoint
    ) -> Bool {
        let eventBoundary = min(checkpoint.eventCountAtStart, thread.events.count)
        var requestedIDs = Set<String>()
        var decidedIDs = Set<String>()
        for event in thread.events.dropFirst(eventBoundary) {
            switch event.kind {
            case .approvalRequested:
                if let request = decode(ApprovalRequest.self, event.payloadJSON) {
                    requestedIDs.insert(request.id)
                }
            case .approvalDecided:
                if let decision = decode(ApprovalDecision.self, event.payloadJSON) {
                    decidedIDs.insert(decision.requestID)
                }
            case .message, .messageFeedback, .toolQueued, .toolRunning, .toolProgress,
                 .toolCompleted, .toolFailed, .reviewComment, .notice:
                continue
            }
        }
        return !requestedIDs.subtracting(decidedIDs).isEmpty
    }

    private static func hasOpenTool(
        in thread: ChatThread,
        checkpoint: ThreadRunCheckpoint
    ) -> Bool {
        let eventBoundary = min(checkpoint.eventCountAtStart, thread.events.count)
        var isOpen = false
        for event in thread.events.dropFirst(eventBoundary) {
            switch event.kind {
            case .toolQueued, .toolRunning, .toolProgress:
                isOpen = true
            case .toolCompleted, .toolFailed, .approvalRequested:
                isOpen = false
            case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }
        return isOpen
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ payloadJSON: String?) -> Value? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
