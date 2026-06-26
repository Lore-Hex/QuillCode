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
        var startedThread = thread
        appendUserTurn(prompt, to: &startedThread)
        return WorkspaceAgentSendStartPlan(
            prompt: prompt,
            thread: startedThread,
            threadID: startedThread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: composer)
        )
    }

    private static func appendUserTurn(_ prompt: String, to thread: inout ChatThread) {
        thread.messages.append(ChatMessage(role: .user, content: prompt))
        thread.events.append(ThreadEvent(kind: .message, summary: prompt))
        thread.updatedAt = Date()
        if thread.title == "New chat" {
            thread.title = WorkspaceThreadSeedBuilder.title(fromUserPrompt: prompt)
        }
    }
}
