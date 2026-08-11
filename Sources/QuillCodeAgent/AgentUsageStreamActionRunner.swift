import Foundation
import QuillCodeCore

extension AgentRunner {
    func nextUsageStreamingAction(
        from streamingLLM: any UsageStreamingLLMClient,
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?,
        reasoningBudgetPhase: AgentReasoningBudgetPhase
    ) async throws -> AgentAction {
        await publishStreamingNotice(in: &thread, onProgress: onProgress)
        var stream = try await streamingLLM.actionEventStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        let routedModelID = routedModelIDIfSupported(streamingLLM, fallback: thread.model)
        if let deadline = turnDeadlineSeconds {
            stream = AgentTurnDeadline.enforcing(seconds: deadline, on: stream)
        }
        let reasoningLimit: Int? = switch reasoningBudgetPhase {
        case .startup, .checkpoint:
            preActionReasoningCharacterLimit
        case .synthesis, .boundedFinalization:
            interActionReasoningCharacterLimit
        case .correction:
            preActionReasoningCharacterLimit.map {
                routedModelID == TrustedRouterChatParameters.deepSeekV4Flash0731Model
                    ? min($0, AgentPreActionReasoningBudget.deepSeekV4Flash0731SynthesisCharacterLimit)
                    : min($0, Self.correctiveActionReasoningCharacterLimit)
            }
        }
        if let reasoningLimit {
            stream = AgentPreActionReasoningBudget.enforcing(
                maximumCharacters: max(
                    1,
                    AgentPreActionReasoningBudget.effectiveMaximumCharacters(
                        configured: reasoningLimit,
                        modelID: routedModelID,
                        phase: reasoningBudgetPhase
                    )
                ),
                on: stream
            )
        }
        do {
            return try await Self.collectStreamingAction(
                from: stream,
                thread: &thread,
                modelID: routedModelID,
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
