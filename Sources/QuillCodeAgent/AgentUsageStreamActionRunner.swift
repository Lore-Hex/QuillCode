import Foundation
import QuillCodeCore

extension AgentRunner {
    func nextUsageStreamingAction(
        from streamingLLM: any UsageStreamingLLMClient,
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?,
        enforcePreActionReasoningBudget: Bool
    ) async throws -> AgentAction {
        await publishStreamingNotice(in: &thread, onProgress: onProgress)
        var stream = try await streamingLLM.actionEventStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        if let deadline = turnDeadlineSeconds {
            stream = AgentTurnDeadline.enforcing(seconds: deadline, on: stream)
        }
        if enforcePreActionReasoningBudget, let limit = preActionReasoningCharacterLimit {
            stream = AgentPreActionReasoningBudget.enforcing(
                maximumCharacters: max(1, limit),
                on: stream
            )
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
