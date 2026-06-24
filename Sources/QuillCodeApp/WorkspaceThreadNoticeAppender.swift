import QuillCodeCore

enum WorkspaceThreadNoticeAppender {
    static func appendNotice(_ summary: String, to thread: inout ChatThread) {
        thread.events.append(ThreadEvent(kind: .notice, summary: summary))
    }

    static func appendAssistantNotice(_ text: String, to thread: inout ChatThread) {
        thread.messages.append(ChatMessage(role: .assistant, content: text))
        thread.events.append(ThreadEvent(kind: .message, summary: text))
    }
}
