import Foundation
import QuillCodeCore

extension AgentRunner {
    func nextUsageStreamingAction(
        from streamingLLM: any UsageStreamingLLMClient,
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        await publishStreamingNotice(in: &thread, onProgress: onProgress)
        let stream = try await streamingLLM.actionEventStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        return try await Self.collectStreamingAction(
            from: stream,
            thread: &thread,
            onProgress: onProgress
        )
    }
}
