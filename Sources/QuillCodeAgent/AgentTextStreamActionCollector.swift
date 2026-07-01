import Foundation
import QuillCodeCore

extension AgentRunner {
    static func collectStreamingAction(
        from stream: AsyncThrowingStream<String, Error>,
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        var draftThread = thread
        let action = try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: AgentError.emptyStreamingResponse,
            onVisibleAssistantText: { visibleText in
                publishAssistantDraft(visibleText, in: &draftThread)
                await onProgress?(draftThread)
            }
        )
        thread = draftThread
        return action
    }
}
