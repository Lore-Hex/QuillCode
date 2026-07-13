import Foundation
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools

enum AgentToolStep: Sendable {
    case completed(AgentToolStepCompletion)
    case blocked(AgentPendingApproval)
}

struct AgentToolStepCompletion: Sendable {
    var call: ToolCall
    var result: ToolResult
    var followUpReviewResult: ToolResult?
    var toolResults: [ToolResult]
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

            let router = ToolRouter(
                workspaceRoot: workspaceRoot,
                editGuard: .session(for: next.id),
                lsp: lsp
            )
            let result = try await executeApprovedTool(
                call,
                router: router,
                workspaceRoot: workspaceRoot,
                thread: &next,
                onProgress: onProgress
            )
            let followUpReviewResult = try await runFollowUpReviewIfNeeded(
                after: call,
                result: result,
                router: router,
                workspaceRoot: workspaceRoot,
                thread: &next,
                onProgress: onProgress
            )
            let completion = AgentToolStepCompletion(
                call: call,
                result: result,
                followUpReviewResult: followUpReviewResult,
                toolResults: followUpReviewResult.map { [result, $0] } ?? [result]
            )
            appendToolFeedback(completion, to: &next)
            resumedToolResults = completion.toolResults
            await onProgress?(next)
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

    func runToolStep(
        _ call: ToolCall,
        userMessage: String,
        thread: inout ChatThread,
        workspaceRoot: URL,
        toolDefinitions: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentToolStep {
        // The edit guard is scoped to THIS thread's model context: only files whose content
        // entered this thread (read or written here) may be overwritten/patched here.
        let router = ToolRouter(workspaceRoot: workspaceRoot, editGuard: .session(for: thread.id), lsp: lsp)
        let definition = toolDefinitions.first { $0.name == call.name }
        await appendQueuedEvent(for: call, to: &thread, onProgress: onProgress)

        guard let definition else {
            let result = ToolResult(
                ok: false,
                error: "Tool is not available in this workspace: \(call.name)"
            )
            await appendResultEvent(
                for: call,
                result: result,
                unavailable: true,
                publishProgress: true,
                to: &thread,
                onProgress: onProgress
            )
            return .completed(AgentToolStepCompletion(
                call: call,
                result: result,
                followUpReviewResult: nil,
                toolResults: [result]
            ))
        }

        try Task.checkCancellation()
        let review = await safety.review(.init(
            mode: thread.mode,
            userMessage: userMessage,
            toolCall: call,
            toolDefinition: definition,
            recentMessages: thread.messages,
            workspaceRoot: workspaceRoot
        ))
        try Task.checkCancellation()

        if review.verdict != .approve {
            let pendingApproval = await appendBlockedReview(
                review,
                for: call,
                definition: definition,
                to: &thread,
                onProgress: onProgress
            )
            return .blocked(pendingApproval)
        }

        let result = try await executeApprovedTool(
            call,
            router: router,
            workspaceRoot: workspaceRoot,
            thread: &thread,
            onProgress: onProgress
        )
        let followUpReviewResult = try await runFollowUpReviewIfNeeded(
            after: call,
            result: result,
            router: router,
            workspaceRoot: workspaceRoot,
            thread: &thread,
            onProgress: onProgress
        )
        let toolResults = followUpReviewResult.map { [result, $0] } ?? [result]

        thread.updatedAt = Date()
        return .completed(AgentToolStepCompletion(
            call: call,
            result: result,
            followUpReviewResult: followUpReviewResult,
            toolResults: toolResults
        ))
    }

    func appendToolFeedback(_ completion: AgentToolStepCompletion, to thread: inout ChatThread) {
        let feedback = AgentToolFeedback(
            toolCall: completion.call,
            result: completion.result,
            followUpResult: completion.followUpReviewResult
        )
        let content = (try? JSONHelpers.encodePretty(feedback)) ?? "{}"
        let attachments = toolFeedbackAttachmentProvider?(
            completion.call,
            completion.result
        ) ?? []
        thread.messages.append(.init(
            role: .tool,
            content: content,
            attachments: attachments
        ))
        thread.updatedAt = Date()
    }

    private func executeApprovedTool(
        _ call: ToolCall,
        router: ToolRouter,
        workspaceRoot: URL,
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> ToolResult {
        await appendRunningEvent(for: call, to: &thread, onProgress: onProgress)
        try Task.checkCancellation()
        let result: ToolResult
        if let searchResult = await webSearchResult(for: call) {
            result = searchResult
        } else if let overrideResult = await toolExecutionOverride?(call, workspaceRoot) {
            result = overrideResult
        } else {
            result = router.execute(call)
        }
        try Task.checkCancellation()
        await appendResultEvent(for: call, result: result, to: &thread, onProgress: onProgress)
        return result
    }

    /// Dispatch `host.web.search` to the injected TrustedRouter-backed client. Returns nil for
    /// every other tool (so the normal override/router path runs) and nil when no search client is
    /// wired (so the router's own "not available" message is used). This is the single place the
    /// async, credential-bearing search executor is invoked, shared by the CLI and desktop loops.
    private func webSearchResult(for call: ToolCall) async -> ToolResult? {
        guard call.name == ToolDefinition.webSearch.name, let webSearch else { return nil }
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let query = try args.requiredString("query")
            return await WebSearchToolExecutor(client: webSearch)
                .search(query: query, maxResults: args.int("maxResults"))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func runFollowUpReviewIfNeeded(
        after call: ToolCall,
        result: ToolResult,
        router: ToolRouter,
        workspaceRoot: URL,
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> ToolResult? {
        guard call.name == ToolDefinition.applyPatch.name, result.ok else {
            return nil
        }

        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        await appendQueuedEvent(for: diffCall, to: &thread, onProgress: onProgress)
        return try await executeApprovedTool(
            diffCall,
            router: router,
            workspaceRoot: workspaceRoot,
            thread: &thread,
            onProgress: onProgress
        )
    }

    private func appendQueuedEvent(
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

    private func appendRunningEvent(
        for call: ToolCall,
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async {
        thread.events.append(.init(kind: .toolRunning, summary: "\(call.name) running"))
        thread.updatedAt = Date()
        await onProgress?(thread)
    }

    private func appendResultEvent(
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

    private func appendBlockedReview(
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
