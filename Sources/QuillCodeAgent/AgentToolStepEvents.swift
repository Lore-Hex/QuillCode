import Foundation
import QuillCodeCore
import QuillCodeSafety

extension AgentRunner {
    func appendQueuedEvent(
        for call: ToolCall,
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async {
        let transcriptCall = call.redactedForTranscript()
        let callJSON = (try? JSONHelpers.encodePretty(transcriptCall)) ?? transcriptCall.argumentsJSON
        thread.events.append(.init(
            kind: .toolQueued,
            summary: "\(call.name) queued",
            payloadJSON: callJSON
        ))
        thread.updatedAt = Date()
        await onProgress?(thread)
    }

    func appendRunningEvent(
        for call: ToolCall,
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async {
        thread.events.append(.init(kind: .toolRunning, summary: "\(call.name) running"))
        thread.updatedAt = Date()
        await onProgress?(thread)
    }

    func recordToolProgress(
        _ progress: ToolExecutionProgress,
        for call: ToolCall,
        in thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async {
        let payload = ToolProgressEventPayload(toolCallID: call.id, progress: progress)
        let payloadJSON = try? JSONHelpers.encodePretty(payload)
        let event = ThreadEvent(
            kind: .toolProgress,
            summary: progress.message ?? "\(call.name) in progress",
            payloadJSON: payloadJSON
        )

        if let lastIndex = thread.events.indices.last,
           thread.events[lastIndex].kind == .toolProgress,
           let existingJSON = thread.events[lastIndex].payloadJSON,
           let existing = try? JSONHelpers.decode(ToolProgressEventPayload.self, from: existingJSON),
           existing.toolCallID == call.id {
            thread.events[lastIndex] = event
        } else {
            thread.events.append(event)
        }
        thread.updatedAt = Date()
        await onProgress?(thread)
    }

    func appendResultEvent(
        for call: ToolCall,
        result: ToolResult,
        unavailable: Bool = false,
        publishProgress: Bool = false,
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async {
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        thread.events.append(.init(
            kind: result.ok ? .toolCompleted : .toolFailed,
            summary: toolResultSummary(for: call, result: result, unavailable: unavailable),
            payloadJSON: resultJSON
        ))
        thread.updatedAt = Date()
        if publishProgress {
            await onProgress?(thread)
        }
    }

    func appendBlockedReview(
        _ review: SafetyReview,
        for call: ToolCall,
        definition: ToolDefinition?,
        reviewAttempt: ApprovalReviewAttempt = .initial,
        workspaceRoot: URL,
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async -> AgentPendingApproval {
        let text: String
        let request = makeApprovalRequest(
            review,
            for: call,
            definition: definition,
            reviewAttempt: reviewAttempt,
            workspaceRoot: workspaceRoot,
            thread: thread
        )
        switch review.verdict {
        case .clarify:
            text = "I need a little more detail before running \(call.name): \(review.rationale)"
        case .deny:
            text = "I cannot run \(call.name): \(review.rationale)"
        case .approve:
            preconditionFailure("Approved reviews do not create approval requests")
        }
        appendApprovalRequest(
            request,
            summary: "\(review.verdict.rawValue): \(review.rationale)",
            to: &thread
        )
        thread.messages.append(.init(role: .assistant, content: text))
        thread.events.append(.init(kind: .message, summary: text))
        thread.updatedAt = Date()
        await onProgress?(thread)
        return AgentPendingApproval(request: request, heldToolCall: call)
    }

    func appendDeniedAutoReview(
        _ review: SafetyReview,
        for call: ToolCall,
        definition: ToolDefinition?,
        reviewAttempt: ApprovalReviewAttempt,
        workspaceRoot: URL,
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async -> ToolResult {
        let request = makeApprovalRequest(
            review,
            for: call,
            definition: definition,
            reviewAttempt: reviewAttempt,
            workspaceRoot: workspaceRoot,
            thread: thread
        )
        appendApprovalRequest(request, summary: "Auto review: denied \(call.name)", to: &thread)
        appendApprovalDecision(review, requestID: request.id, to: &thread)
        thread.updatedAt = Date()
        await onProgress?(thread)

        return ToolResult(
            ok: false,
            error: """
            Auto review denied this exact action: \(review.rationale)
            Do not retry, disguise, split, or circumvent the denied action. Choose a materially safer \
            alternative that still serves the request. If none exists, explain the blocker and ask the user.
            """
        )
    }

    func makeApprovalRequest(
        _ review: SafetyReview,
        for call: ToolCall,
        definition: ToolDefinition?,
        reviewAttempt: ApprovalReviewAttempt,
        workspaceRoot: URL,
        thread: ChatThread
    ) -> ApprovalRequest {
        let presentedCall = call.redactedForTranscript()
        return ApprovalRequest(
            toolCall: presentedCall,
            toolDefinition: definition,
            reason: review.rationale,
            recommendedVerdict: review.verdict,
            reviewTelemetry: review.reviewTelemetry,
            actionIdentity: ApprovalActionIdentity.make(
                executableCall: call,
                presentedCall: presentedCall,
                thread: thread,
                workspaceRoot: workspaceRoot
            ),
            reviewAttempt: reviewAttempt
        )
    }

    func appendApprovalRequest(
        _ request: ApprovalRequest,
        summary: String,
        to thread: inout ChatThread
    ) {
        thread.events.append(.init(
            kind: .approvalRequested,
            summary: summary,
            payloadJSON: try? JSONHelpers.encodePretty(request)
        ))
        thread.updatedAt = Date()
    }

    func appendApprovalDecision(
        _ review: SafetyReview,
        requestID: String,
        to thread: inout ChatThread
    ) {
        let decision = ApprovalDecision(
            requestID: requestID,
            verdict: review.verdict,
            rationale: review.rationale,
            reviewTelemetry: review.reviewTelemetry,
            reviewOutcome: review.reviewOutcome
        )
        thread.events.append(.init(
            kind: .approvalDecided,
            summary: "\(review.reviewOutcome.displayLabel.lowercased()): \(review.rationale)",
            payloadJSON: try? JSONHelpers.encodePretty(decision)
        ))
        thread.updatedAt = Date()
    }

    private func toolResultSummary(
        for call: ToolCall,
        result: ToolResult,
        unavailable: Bool
    ) -> String {
        if unavailable {
            return "\(call.name) unavailable"
        }
        return result.ok ? "\(call.name) completed" : "\(call.name) failed"
    }
}
