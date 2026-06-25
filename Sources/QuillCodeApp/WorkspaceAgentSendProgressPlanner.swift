import Foundation
import QuillCodeCore

struct WorkspaceAgentSendProgressPlan: Sendable {
    var thread: ChatThread
    var composer: ComposerState
    var lastError: String?
    var agentStatus: String
}

enum WorkspaceAgentSendProgressPlanner {
    static func progress(
        thread: ChatThread,
        expectedThreadID: UUID,
        composer: ComposerState
    ) -> WorkspaceAgentSendProgressPlan? {
        guard thread.id == expectedThreadID else { return nil }
        var nextComposer = composer
        nextComposer.isSending = true
        return WorkspaceAgentSendProgressPlan(
            thread: thread,
            composer: nextComposer,
            lastError: nil,
            agentStatus: WorkspaceAgentStatusBuilder.status(for: thread)
        )
    }
}
