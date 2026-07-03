import Foundation
import QuillCodeCore

extension AgentRunner {
    static func collectStreamingAction(
        from stream: AsyncThrowingStream<AgentTextStreamEvent, Error>,
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        var draftThread = thread
        var latestUsage: ModelTokenUsage?

        let action = try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: AgentError.emptyStreamingResponse,
            onVisibleAssistantText: { visibleText in
                publishAssistantDraft(visibleText, in: &draftThread)
                let publish = onProgress
                await publish?(draftThread)
            },
            onUsage: { usage in
                latestUsage = usage
            },
            onReasoning: { summary in
                publishReasoningSummary(summary, in: &draftThread)
                await onProgress?(draftThread)
            }
        )

        thread = draftThread
        if let latestUsage {
            thread.events.append(ModelTokenUsageEvent.event(usage: latestUsage, modelID: thread.model))
            thread.updatedAt = Date()
            await onProgress?(thread)
        }
        return action
    }
}
