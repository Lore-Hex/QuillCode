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
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async -> AgentPendingApproval {
        let text: String
        let request = ApprovalRequest(
            toolCall: call.redactedForTranscript(),
            toolDefinition: definition,
            reason: review.rationale,
            recommendedVerdict: review.verdict,
            reviewTelemetry: review.reviewTelemetry
        )
        let requestJSON = try? JSONHelpers.encodePretty(request)
        switch review.verdict {
        case .clarify:
            text = "I need a little more detail before running \(call.name): \(review.rationale)"
        case .deny:
            text = "I cannot run \(call.name): \(review.rationale)"
        case .approve:
            preconditionFailure("Approved reviews do not create approval requests")
        }
        thread.events.append(.init(
            kind: .approvalRequested,
            summary: "\(review.verdict.rawValue): \(review.rationale)",
            payloadJSON: requestJSON
        ))
        thread.messages.append(.init(role: .assistant, content: text))
        thread.events.append(.init(kind: .message, summary: text))
        thread.updatedAt = Date()
        await onProgress?(thread)
        return AgentPendingApproval(request: request, heldToolCall: call)
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
