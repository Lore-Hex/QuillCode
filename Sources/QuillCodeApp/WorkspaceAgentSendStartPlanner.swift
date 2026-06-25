import Foundation
import QuillCodeCore

struct WorkspaceAgentSendStartPlan: Sendable {
    var prompt: String
    var thread: ChatThread
    var threadID: UUID
    var lifecycle: WorkspaceComposerSendLifecyclePlan
}

enum WorkspaceAgentSendStartPlanner {
    static func started(
        prompt: String,
        thread: ChatThread,
        composer: ComposerState
    ) -> WorkspaceAgentSendStartPlan {
        WorkspaceAgentSendStartPlan(
            prompt: prompt,
            thread: thread,
            threadID: thread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: composer)
        )
    }
}
