import Foundation
import QuillCodeCore

extension AgentRunner {
    func publishStreamingNotice(
        in thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async {
        thread.events.append(.init(kind: .notice, summary: Self.streamingNotice))
        thread.updatedAt = Date()
        await onProgress?(thread)
    }

    static func publishAssistantDraft(_ text: String, in thread: inout ChatThread) {
        if let lastIndex = thread.messages.indices.last,
           thread.messages[lastIndex].role == .assistant {
            thread.messages[lastIndex].content = text
        } else {
            thread.messages.append(.init(role: .assistant, content: text))
        }
        thread.updatedAt = Date()
    }

    static func publishReasoningSummary(_ summary: String, in thread: inout ChatThread) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let notice = "Thinking: \(trimmed)"
        guard thread.events.last?.kind != .notice || thread.events.last?.summary != notice else {
            return
        }
        thread.events.append(.init(kind: .notice, summary: notice))
        thread.updatedAt = Date()
    }
}
