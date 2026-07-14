import Foundation
import QuillCodeCore
import QuillCodeTools

extension WorkspaceAgentSendSession {
    func completed(thread: ChatThread) -> WorkspaceAgentSendSessionResult {
        WorkspaceAgentSendSessionResult(
            thread: thread,
            savedMemory: WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)
        )
    }

    func appendHookContexts(
        _ contexts: [ProjectRunHookContext],
        to thread: inout ChatThread
    ) {
        guard !contexts.isEmpty else { return }
        let content = contexts.map { context in
            "Standard plugin hook context from \(context.hook.title):\n\(context.content)"
        }.joined(separator: "\n\n")
        thread.messages.append(ChatMessage(role: .system, content: content))
        thread.updatedAt = Date()
    }

    func appendUserTurn(_ prompt: String, to thread: inout ChatThread) {
        thread.messages.append(ChatMessage(role: .user, content: prompt))
        thread.events.append(ThreadEvent(kind: .message, summary: prompt))
        thread.updatedAt = Date()
        if thread.title == "New chat" {
            thread.title = WorkspaceThreadSeedBuilder.title(fromUserPrompt: prompt)
        }
    }

    func appendAssistantMessage(_ message: String, to thread: inout ChatThread) {
        thread.messages.append(ChatMessage(role: .assistant, content: message))
        thread.events.append(ThreadEvent(kind: .message, summary: message))
        thread.updatedAt = Date()
    }
}
