import Foundation
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools

enum AgentToolStep: Sendable {
    case completed(AgentToolStepCompletion)
    case blocked
}

struct AgentToolStepCompletion: Sendable {
    var call: ToolCall
    var result: ToolResult
    var followUpReviewResult: ToolResult?
    var toolResults: [ToolResult]
}

extension AgentRunner {
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
        let router = ToolRouter(workspaceRoot: workspaceRoot, editGuard: .session(for: thread.id))
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
            await appendBlockedReview(
                review,
                for: call,
                definition: definition,
                to: &thread,
                onProgress: onProgress
            )
            return .blocked
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
        thread.messages.append(.init(role: .tool, content: content))
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
    ) async {
        let text: String
        let request = ApprovalRequest(
            toolCall: call.redactedForTranscript(),
            toolDefinition: definition,
            reason: review.rationale,
            recommendedVerdict: review.verdict
        )
        let requestJSON = try? JSONHelpers.encodePretty(request)
        switch review.verdict {
        case .clarify:
            text = "I need a little more detail before running \(call.name): \(review.rationale)"
        case .deny:
            text = "I cannot run \(call.name): \(review.rationale)"
        case .approve:
            return
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
