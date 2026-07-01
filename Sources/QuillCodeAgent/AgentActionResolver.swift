import Foundation
import QuillCodeCore

extension AgentRunner {
    func nextAction(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        if enablesImmediateActionPreflight,
           let action = AgentImmediateActionPlanner.action(for: userMessage, tools: tools) {
            return action
        }

        if let usageStreamingLLM = llm as? any UsageStreamingLLMClient {
            return try await nextUsageStreamingAction(
                from: usageStreamingLLM,
                thread: &thread,
                userMessage: userMessage,
                tools: tools,
                onProgress: onProgress
            )
        }

        if let streamingLLM = llm as? any StreamingLLMClient {
            return try await nextTextStreamingAction(
                from: streamingLLM,
                thread: &thread,
                userMessage: userMessage,
                tools: tools,
                onProgress: onProgress
            )
        }

        return try await llm.nextAction(thread: thread, userMessage: userMessage, tools: tools)
    }
}
