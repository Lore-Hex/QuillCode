import Foundation
import QuillCodeCore

struct WorkspaceAgentSendProgressPlan: Sendable {
    var thread: ChatThread
    var composerIsSending: Bool
    var lastError: String?
    var agentStatus: String
}

enum WorkspaceAgentSendProgressPlanner {
    static func progress(
        thread: ChatThread,
        expectedThreadID: UUID
    ) -> WorkspaceAgentSendProgressPlan? {
        guard thread.id == expectedThreadID else { return nil }
        return WorkspaceAgentSendProgressPlan(
            thread: thread,
            composerIsSending: true,
            lastError: nil,
            agentStatus: WorkspaceAgentStatusBuilder.status(for: thread)
        )
    }
}
