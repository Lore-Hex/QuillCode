import Foundation
import QuillCodeCore

extension AgentRunner {
    func nextAction(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        if enablesImmediateActionPreflight,
           let action = AgentImmediateActionPlanner.action(for: userMessage, tools: tools) {
            // The planner parsed this action from the user's own command. A user-authored file
            // write is not a model blind-overwrite, so record that target as known for this
            // thread before the read-before-write guard runs. LLM-produced actions below do not
            // get this marker.
            AgentImmediateActionWriteReadMarker.markIfNeeded(
                action,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
            return action
        }

        do {
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
        } catch TrustedRouterAgentError.emptyToolArguments(let toolName) {
            if let action = AgentImmediateActionPlanner.action(for: userMessage, tools: tools) {
                AgentImmediateActionWriteReadMarker.markIfNeeded(
                    action,
                    thread: thread,
                    workspaceRoot: workspaceRoot
                )
                return action
            }
            throw TrustedRouterAgentError.emptyToolArguments(toolName)
        }
    }
}
