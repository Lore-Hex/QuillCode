import QuillCodeCore

struct WorkspaceComposerCancellationPlanner {
    static let stoppedSummary = "Stopped by user"
    static let stoppedPayloadJSON = #"{"ok":false,"error":"Stopped by user"}"#

    static func applyCancelledSend(userPrompt: String, to thread: inout ChatThread) {
        if thread.messages.isEmpty && thread.title == "New chat" {
            thread.title = WorkspaceThreadSeedBuilder.title(fromUserPrompt: userPrompt)
        }
        if !thread.messages.contains(where: { $0.role == .user && $0.content == userPrompt }) {
            thread.messages.append(ChatMessage(role: .user, content: userPrompt))
        }
        if shouldAppendToolFailure(after: thread.events.last) {
            thread.events.append(ThreadEvent(
                kind: .toolFailed,
                summary: stoppedSummary,
                payloadJSON: stoppedPayloadJSON
            ))
        }
        if shouldAppendNotice(after: thread.events.last) {
            thread.events.append(ThreadEvent(kind: .notice, summary: stoppedSummary))
        }
    }

    private static func shouldAppendToolFailure(after event: ThreadEvent?) -> Bool {
        event?.kind == .toolQueued || event?.kind == .toolRunning
    }

    private static func shouldAppendNotice(after event: ThreadEvent?) -> Bool {
        event?.kind != .notice || event?.summary != stoppedSummary
    }
}
