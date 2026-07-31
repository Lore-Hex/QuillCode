import Foundation
import QuillCodeCore

extension AgentRunner {
    func nextTextStreamingAction(
        from streamingLLM: any StreamingLLMClient,
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        await publishStreamingNotice(in: &thread, onProgress: onProgress)
        var stream = try await streamingLLM.actionTextStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        if let deadline = turnDeadlineSeconds {
            stream = AgentTurnDeadline.enforcing(seconds: deadline, on: stream)
        }
        do {
            return try await Self.collectStreamingAction(
                from: stream,
                thread: &thread,
                onProgress: onProgress
            )
        } catch let error where RetryClassifier.classify(error) != .none {
            // The stream died after it was obtained (mid-response transport reset). Mark it so the
            // action resolver can re-request; parse failures and cancellations classify `.none` and
            // pass through unchanged.
            throw AgentStreamInterruptedError(underlying: error)
        }
    }
}
