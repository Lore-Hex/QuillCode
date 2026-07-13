import Foundation
import QuillCodeCore
import QuillCodeSafety

/// Result of executing a tool whose approval decision has already been recorded by the caller.
/// Durable delegated workers use this narrow continuation API to preserve normal tool routing and
/// transcript feedback while intentionally skipping a second review.
public struct AgentApprovedToolExecution: Sendable {
    public var thread: ChatThread
    public var toolResults: [ToolResult]

    public init(thread: ChatThread, toolResults: [ToolResult]) {
        self.thread = thread
        self.toolResults = toolResults
    }
}

extension AgentRunner {
    /// Continues the exact run that paused at `pending`, after an explicit user approval.
    ///
    /// The decision is recorded before execution, the original unredacted call is executed once,
    /// its normal tool feedback is appended, and the same thread resumes without another user
    /// message. Callers should persist each `onProgress` snapshot so a relaunch never falls back to
    /// the redacted presentation payload.
    public func resumeApproved(
        _ pending: AgentPendingApproval,
        in thread: ChatThread,
        workspaceRoot: URL,
        userMessage: String,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> AgentRunResult {
        try validatePendingApproval(pending, in: thread)

        var next = thread
        let decision = ApprovalDecision(
            requestID: pending.request.id,
            verdict: .approve,
            rationale: "Approved delegated worker action.",
            reviewTelemetry: pending.request.reviewTelemetry
        )
        next.events.append(.init(
            kind: .approvalDecided,
            summary: "approve: \(decision.rationale)",
            payloadJSON: try? JSONHelpers.encodePretty(decision)
        ))
        next.updatedAt = Date()
        await onProgress?(next)

        var resumedToolResults: [ToolResult] = []
        if pending.request.scope == .tool {
            guard let call = pending.heldToolCall else {
                throw AgentApprovalResumeError.missingHeldTool(pending.request.toolCall.name)
            }
            guard call.id == pending.request.toolCall.id,
                  call.name == pending.request.toolCall.name else {
                throw AgentApprovalResumeError.mismatchedHeldTool(pending.request.toolCall.name)
            }
            let execution = try await executeApprovedToolCall(
                call,
                in: next,
                workspaceRoot: workspaceRoot,
                onProgress: onProgress
            )
            next = execution.thread
            resumedToolResults = execution.toolResults
        }

        let continuation = try await send(
            userMessage,
            in: next,
            workspaceRoot: workspaceRoot,
            recordUserMessage: false,
            onProgress: onProgress
        )
        return AgentRunResult(
            thread: continuation.thread,
            toolResults: resumedToolResults + continuation.toolResults,
            stopReason: continuation.stopReason,
            pendingApproval: continuation.pendingApproval
        )
    }

    private func validatePendingApproval(
        _ pending: AgentPendingApproval,
        in thread: ChatThread
    ) throws {
        let hasRequest = thread.events.contains { event in
            guard event.kind == .approvalRequested,
                  let payloadJSON = event.payloadJSON,
                  let request = try? JSONHelpers.decode(ApprovalRequest.self, from: payloadJSON)
            else { return false }
            return request == pending.request
        }
        let hasDecision = thread.events.contains { event in
            guard event.kind == .approvalDecided,
                  let payloadJSON = event.payloadJSON,
                  let decision = try? JSONHelpers.decode(ApprovalDecision.self, from: payloadJSON)
            else { return false }
            return decision.requestID == pending.request.id
        }
        guard hasRequest, !hasDecision else {
            throw AgentApprovalResumeError.requestNotPending(pending.request.id)
        }
    }
}
