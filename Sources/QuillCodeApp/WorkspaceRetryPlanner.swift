import Foundation
import QuillCodeCore

enum WorkspaceRetryPlanner {
    static func canRetryLastUserTurn(
        in thread: ChatThread?,
        isSending: Bool
    ) -> Bool {
        guard !isSending else { return false }
        return retryDraft(in: thread) != nil
    }

    static func retryDraft(in thread: ChatThread?) -> String? {
        latestUserMessage(in: thread?.messages)?.content
    }

    private static func latestUserMessage(in messages: [ChatMessage]?) -> ChatMessage? {
        messages?.last {
            $0.role == .user
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
