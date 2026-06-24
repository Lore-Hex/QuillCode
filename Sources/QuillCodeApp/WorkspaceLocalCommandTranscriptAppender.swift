import QuillCodeCore

enum WorkspaceLocalCommandTranscriptAppender {
    static func append(_ transcript: WorkspaceLocalCommandTranscript, to thread: inout ChatThread) {
        if thread.messages.isEmpty && thread.title == "New chat" {
            thread.title = transcript.title
        }
        thread.messages.append(ChatMessage(role: .user, content: transcript.userText))
        thread.messages.append(ChatMessage(role: .assistant, content: transcript.assistantText))
    }
}
