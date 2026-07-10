import Foundation
import QuillCodeCore

enum WorkspaceRetryPlanner {
    static func canRetryLastUserTurn(
        in thread: ChatThread?,
        isSending: Bool
    ) -> Bool {
        guard !isSending else { return false }
        return retryMessage(in: thread) != nil
    }

    static func retryDraft(in thread: ChatThread?) -> String? {
        retryMessage(in: thread)?.content
    }

    static func retryMessage(in thread: ChatThread?) -> ChatMessage? {
        latestUserMessage(in: thread?.messages)
    }

    private static func latestUserMessage(in messages: [ChatMessage]?) -> ChatMessage? {
        messages?.last {
            $0.role == .user
                && (!$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.attachments.isEmpty)
        }
    }
}
