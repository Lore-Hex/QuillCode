import Foundation
import QuillCodeCore

public enum AgentAction: Sendable, Hashable {
    case say(String)
    case tool(ToolCall)
}

public protocol LLMClient: Sendable {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction
}

public protocol StreamingLLMClient: LLMClient {
    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error>
}

public protocol UsageStreamingLLMClient: StreamingLLMClient {
    func actionEventStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error>
}

public enum AgentError: Error, CustomStringConvertible {
    case emptyStreamingResponse
    case promisedWorkWithoutToolAction
    case tooManyToolSteps(Int)

    public var description: String {
        switch self {
        case .emptyStreamingResponse:
            return "The model stream finished without returning an action."
        case .promisedWorkWithoutToolAction:
            return "The model promised to perform work but did not return a tool action."
        case .tooManyToolSteps(let limit):
            return "The agent reached the tool-step limit (\(limit)) before returning a final answer."
        }
    }
}

/// Why an agent run ended — so a run that HIT its tool-step ceiling (and had a summary synthesized from
/// the last tool result) is no longer indistinguishable from a run the model genuinely finished. The
/// unattended-driving trust story needs "finished" to mean finished, not "gave up at the budget".
public enum AgentRunStopReason: Sendable, Hashable {
    /// The model returned a final answer (or a repeated-call was finalized) — a genuine finish.
    case finished
    /// The run exhausted `maxToolSteps` without the model returning a final answer; the summary is
    /// synthesized from the last tool result, not a real conclusion.
    case toolStepCeilingExhausted(limit: Int)
    /// The flail detector confirmed the run was busy-but-stuck — repeating the same action or failure
    /// with no workspace progress — even after a self-assessment nudge; the run was stopped to save
    /// the remaining budget. `reason` is the human-readable stuck reason.
    /// (Appended last: never insert enum cases mid-list — discriminants shift and stale incremental
    /// builds miscompile.)
    case flailDetected(reason: String)
}

public struct AgentRunResult: Sendable {
    public var thread: ChatThread
    public var toolResults: [ToolResult]
    public var stopReason: AgentRunStopReason

    public init(thread: ChatThread, toolResults: [ToolResult], stopReason: AgentRunStopReason = .finished) {
        self.thread = thread
        self.toolResults = toolResults
        self.stopReason = stopReason
    }
}

public struct AgentToolFeedback: Codable, Sendable, Hashable {
    public var toolCall: ToolCall
    public var result: ToolResult
    public var followUpResult: ToolResult?

    public init(toolCall: ToolCall, result: ToolResult, followUpResult: ToolResult? = nil) {
        self.toolCall = toolCall
        self.result = result
        self.followUpResult = followUpResult
    }
}

public typealias AgentRunProgressHandler = @Sendable (ChatThread) async -> Void
public typealias AgentToolExecutionOverride = @Sendable (ToolCall, URL) async -> ToolResult?
