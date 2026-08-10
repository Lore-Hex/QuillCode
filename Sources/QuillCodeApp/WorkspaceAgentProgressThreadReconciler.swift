import QuillCodeCore

/// Applies presentation-cadence agent snapshots without making the model retain the producer's
/// large transcript buffers. Agent histories normally append or update their current tail; the
/// identified-array reconciliation also handles truncation and structural replacement exactly.
enum WorkspaceAgentProgressThreadReconciler {
    static func reconcile(_ snapshot: ChatThread, into live: inout ChatThread) {
        precondition(snapshot.id == live.id)

        live.title = snapshot.title
        live.projectID = snapshot.projectID
        live.mode = snapshot.mode
        live.model = snapshot.model
        live.personality = snapshot.personality
        reconcile(snapshot.messages, into: &live.messages)
        reconcile(snapshot.modelContextItems, into: &live.modelContextItems)
        reconcile(snapshot.events, into: &live.events)
        reconcile(snapshot.subagentRuns, into: &live.subagentRuns)
        live.isPinned = snapshot.isPinned
        live.isArchived = snapshot.isArchived
        live.createdAt = snapshot.createdAt
        live.updatedAt = snapshot.updatedAt
        live.worktree = snapshot.worktree
        live.pullRequest = snapshot.pullRequest
        live.forkParentThreadID = snapshot.forkParentThreadID
        live.forkAnchorTurnMessageID = snapshot.forkAnchorTurnMessageID
        live.runtimeContext = snapshot.runtimeContext

        // instructions, memories, goal, drafts, attachments, and the follow-up queue are owned by
        // the live workspace model and may change after the agent captured its send-start snapshot.
    }

    private static func reconcile<Element>(
        _ snapshot: [Element],
        into live: inout [Element]
    ) where Element: Identifiable & Equatable, Element.ID: Equatable {
        let overlapCount = min(live.count, snapshot.count)
        for index in 0..<overlapCount {
            guard live[index].id == snapshot[index].id else {
                replaceDetached(&live, with: snapshot)
                return
            }
            if live[index] != snapshot[index] {
                live[index] = snapshot[index]
            }
        }

        if snapshot.count > live.count {
            live.append(contentsOf: snapshot[live.count...])
        } else if snapshot.count < live.count {
            live.removeLast(live.count - snapshot.count)
        }
    }

    private static func replaceDetached<Element>(_ live: inout [Element], with snapshot: [Element]) {
        live.removeAll(keepingCapacity: true)
        live.append(contentsOf: snapshot)
    }
}
