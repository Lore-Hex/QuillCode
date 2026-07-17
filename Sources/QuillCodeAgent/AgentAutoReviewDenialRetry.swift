import Foundation
import QuillCodeCore
import QuillCodeSafety

public struct AgentAutoReviewRetryResult: Sendable {
    public var thread: ChatThread
    public var review: SafetyReview
    public var retryRequestID: String
    public var toolResults: [ToolResult]

    public var didExecute: Bool { review.reviewOutcome == .approved }

    public init(
        thread: ChatThread,
        review: SafetyReview,
        retryRequestID: String,
        toolResults: [ToolResult]
    ) {
        self.thread = thread
        self.review = review
        self.retryRequestID = retryRequestID
        self.toolResults = toolResults
    }
}

public enum AgentAutoReviewRetryError: Error, LocalizedError, Sendable, Hashable {
    case denialNotFound
    case retryConsumed
    case replayUnavailable
    case contextChanged
    case toolUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .denialNotFound:
            "This Auto-review denial is no longer available."
        case .retryConsumed:
            "The one exact retry for this denied action was already used."
        case .replayUnavailable:
            "This action contained private or redacted arguments and cannot be replayed safely."
        case .contextChanged:
            "The task, workspace, or mode changed. Return to the original context to retry this action."
        case .toolUnavailable(let name):
            "The tool needed for this action is no longer available: \(name)."
        }
    }
}

public extension AgentRunner {
    /// Re-reviews and, only when approved, executes one exact Auto-review denial.
    ///
    /// The retry is reconstructed from presentation-safe durable events, bound to its original
    /// turn/workspace/mode, and consumed by persisting a new approval request before execution.
    /// No private held payload is required and redacted calls are deliberately not replayable.
    func retryAutoReviewDenial(
        requestID: String,
        in thread: ChatThread,
        workspaceRoot: URL,
        userMessage: String,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> AgentAutoReviewRetryResult {
        let records = AutoReviewDenialHistory.records(in: thread, workspaceRoot: workspaceRoot)
        guard let record = records.first(where: { $0.id == requestID }) else {
            let allRecords = AutoReviewDenialHistory.records(in: thread)
            guard let unscoped = allRecords.first(where: { $0.id == requestID }) else {
                throw AgentAutoReviewRetryError.denialNotFound
            }
            throw retryError(for: unscoped.retryState, defaultingToContextChanged: true)
        }
        guard record.retryState == .available else {
            throw retryError(for: record.retryState)
        }
        guard let identity = record.request.actionIdentity, identity.isReplayable else {
            throw AgentAutoReviewRetryError.replayUnavailable
        }

        let call = ToolCall(
            name: record.request.toolCall.name,
            argumentsJSON: record.request.toolCall.argumentsJSON
        )
        guard identity.matches(call: call, thread: thread, workspaceRoot: workspaceRoot) else {
            throw AgentAutoReviewRetryError.contextChanged
        }

        let definitions = hostToolAccessScope.adapting(
            Self.mergedToolDefinitions(baseToolDefinitions, additionalToolDefinitions)
        )
        guard let definition = definitions.first(where: { $0.name == call.name }) else {
            throw AgentAutoReviewRetryError.toolUnavailable(call.name)
        }

        var next = thread
        let attempt = ApprovalReviewAttempt.denialOverride(requestID: requestID)
        await appendQueuedEvent(for: call, to: &next, onProgress: onProgress)
        let review = await safety.review(SafetyContext(
            mode: next.mode,
            userMessage: userMessage,
            toolCall: call,
            toolDefinition: definition,
            recentMessages: next.messages,
            workspaceRoot: workspaceRoot,
            reviewAttempt: attempt
        ))
        try Task.checkCancellation()

        let retryRequest = makeApprovalRequest(
            review,
            for: call,
            definition: definition,
            reviewAttempt: attempt,
            workspaceRoot: workspaceRoot,
            thread: next
        )
        appendApprovalRequest(
            retryRequest,
            summary: "Auto review: exact retry of \(requestID)",
            to: &next
        )
        await onProgress?(next)
        appendApprovalDecision(review, requestID: retryRequest.id, to: &next)
        await onProgress?(next)

        guard review.reviewOutcome == .approved else {
            return AgentAutoReviewRetryResult(
                thread: next,
                review: review,
                retryRequestID: retryRequest.id,
                toolResults: []
            )
        }

        let execution = try await executeApprovedToolCall(
            call,
            in: next,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        )
        return AgentAutoReviewRetryResult(
            thread: execution.thread,
            review: review,
            retryRequestID: retryRequest.id,
            toolResults: execution.toolResults
        )
    }

    private func retryError(
        for state: AutoReviewDenialRetryState,
        defaultingToContextChanged: Bool = false
    ) -> AgentAutoReviewRetryError {
        switch state {
        case .available:
            defaultingToContextChanged ? .contextChanged : .denialNotFound
        case .consumed:
            .retryConsumed
        case .unavailable:
            .replayUnavailable
        case .contextChanged:
            .contextChanged
        }
    }
}
