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
        attachments: [ChatAttachment] = [],
        thread: ChatThread,
        composer: ComposerState
    ) -> WorkspaceAgentSendStartPlan {
        var startedThread = thread
        appendUserTurn(prompt, attachments: attachments, to: &startedThread)
        return WorkspaceAgentSendStartPlan(
            prompt: prompt,
            thread: startedThread,
            threadID: startedThread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: composer)
        )
    }

    private static func appendUserTurn(
        _ prompt: String,
        attachments: [ChatAttachment],
        to thread: inout ChatThread
    ) {
        thread.messages.append(ChatMessage(role: .user, content: prompt, attachments: attachments))
        let summary = prompt.isEmpty
            ? "Attached \(attachments.count) image\(attachments.count == 1 ? "" : "s")"
            : prompt
        thread.events.append(ThreadEvent(kind: .message, summary: summary))
        thread.updatedAt = Date()
        if thread.title == "New chat" {
            thread.title = prompt.isEmpty
                ? "Image: \(attachments.first?.displayName ?? "attachment")"
                : WorkspaceThreadSeedBuilder.title(fromUserPrompt: prompt)
        }
    }
}
