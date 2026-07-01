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
        let stream = try await streamingLLM.actionTextStream(
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
