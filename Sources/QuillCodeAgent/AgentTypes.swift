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
    case flailDetected(reason: String)
    /// The run crossed its configured spend fuse and paused until the user approves continuing.
    /// (Appended last: never insert enum cases mid-list — discriminants shift and stale incremental
    /// builds miscompile.)
    case spendFuseApprovalRequired(totalUSD: Double, fuseUSD: Double)
    /// A safety review paused on a concrete approval request. The exact held call is carried
    /// separately by `AgentRunResult.pendingApproval`; keeping only the opaque request id here
    /// prevents stop-reason surfaces from accidentally exposing tool arguments.
    case approvalRequired(requestID: String)
    /// Auto review denied too many actions in one turn. The agent is stopped before it can keep
    /// probing equivalent workarounds and the user can inspect exact denials through `/approve`.
    case autoReviewCircuitBreaker(reason: String)
}

/// Private continuation material for an agent run that stopped at an approval gate.
///
/// `request.toolCall` is safe for transcript/UI presentation and may have redacted arguments.
/// `heldToolCall` is the exact executable call and must only be persisted in a private run store.
/// Spend-fuse approvals do not hold a tool, so `heldToolCall` is nil for that scope.
public struct AgentPendingApproval: Codable, Sendable, Hashable {
    public var request: ApprovalRequest
    public var heldToolCall: ToolCall?

    public init(request: ApprovalRequest, heldToolCall: ToolCall? = nil) {
        self.request = request
        self.heldToolCall = heldToolCall
    }
}

public enum AgentApprovalResumeError: Error, LocalizedError, Sendable, Hashable {
    case requestNotPending(String)
    case missingHeldTool(String)
    case mismatchedHeldTool(String)

    public var errorDescription: String? {
        switch self {
        case .requestNotPending:
            return "This approval was already handled or is no longer pending."
        case .missingHeldTool(let name):
            return "The exact held call for \(name) is unavailable, so it was not replayed."
        case .mismatchedHeldTool(let name):
            return "The held call for \(name) no longer matches the approval request, so it was not replayed."
        }
    }
}

public struct AgentRunResult: Sendable {
    public var thread: ChatThread
    public var toolResults: [ToolResult]
    public var stopReason: AgentRunStopReason
    public var pendingApproval: AgentPendingApproval?

    /// Compatibility accessor for callers that only need the exact held call. The complete
    /// in-memory continuation is `pendingApproval`; durable callers must move this call into a
    /// protected payload store rather than serializing it with the transcript.
    public var pendingApprovalToolCall: ToolCall? { pendingApproval?.heldToolCall }

    public init(
        thread: ChatThread,
        toolResults: [ToolResult],
        stopReason: AgentRunStopReason = .finished,
        pendingApproval: AgentPendingApproval? = nil
    ) {
        self.thread = thread
        self.toolResults = toolResults
        self.stopReason = stopReason
        self.pendingApproval = pendingApproval
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

public enum AgentStreamingToolExecutionEvent: Sendable, Hashable {
    case progress(ToolExecutionProgress)
    case result(ToolResult)
}

/// Optional streaming execution path for tools that can report progress before their final result.
/// Returning nil leaves the call to the ordinary override/router path.
public typealias AgentStreamingToolExecutionOverride = @Sendable (
    ToolCall,
    URL
) -> AsyncThrowingStream<AgentStreamingToolExecutionEvent, Error>?

/// Result of a tool that owns durable thread state in addition to ordinary tool output. Delegated
/// runs use this boundary to attach child manifests to the parent thread while workers are running,
/// without teaching the generic agent loop about the scheduler's persistence model.
public struct AgentThreadToolExecution: Sendable {
    public var thread: ChatThread
    public var result: ToolResult

    public init(thread: ChatThread, result: ToolResult) {
        self.thread = thread
        self.result = result
    }
}

public typealias AgentThreadToolExecutionOverride = @Sendable (
    ToolCall,
    URL,
    ChatThread,
    AgentRunProgressHandler?
) async -> AgentThreadToolExecution?
public typealias AgentToolFeedbackAttachmentProvider = @Sendable (
    ToolCall,
    ToolResult
) -> [ChatAttachment]
