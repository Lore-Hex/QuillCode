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
        let router = toolRouter(workspaceRoot: workspaceRoot, threadID: thread.id)
        let definition = toolDefinitions.first { $0.name == call.name }

        guard let definition else {
            await appendQueuedEvent(for: call, to: &thread, onProgress: onProgress)
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

        let preHook = try await prepareToolCall(
            call,
            thread: &thread,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        )
        let effectiveCall = preHook.call
        await appendQueuedEvent(for: effectiveCall, to: &thread, onProgress: onProgress)

        if let reason = preHook.blockedReason {
            let result = ToolResult(ok: false, error: reason)
            await appendResultEvent(
                for: effectiveCall,
                result: result,
                publishProgress: true,
                to: &thread,
                onProgress: onProgress
            )
            return .completed(AgentToolStepCompletion(
                call: effectiveCall,
                result: result,
                followUpReviewResult: nil,
                toolResults: [result]
            ))
        }

        try Task.checkCancellation()
        let review = await safety.review(.init(
            mode: thread.mode,
            userMessage: userMessage,
            toolCall: effectiveCall,
            toolDefinition: definition,
            recentMessages: thread.messages,
            workspaceRoot: workspaceRoot
        ))
        try Task.checkCancellation()

        if review.verdict == .deny {
            let pendingApproval = await appendBlockedReview(
                review,
                for: effectiveCall,
                definition: definition,
                to: &thread,
                onProgress: onProgress
            )
            return .blocked(pendingApproval)
        }

        if review.verdict == .clarify {
            switch try await resolvePermissionRequest(
                for: effectiveCall,
                approvalReason: review.rationale,
                thread: &thread,
                workspaceRoot: workspaceRoot,
                onProgress: onProgress
            ) {
            case .allow:
                break
            case .noDecision:
                let pendingApproval = await appendBlockedReview(
                    review,
                    for: effectiveCall,
                    definition: definition,
                    to: &thread,
                    onProgress: onProgress
                )
                return .blocked(pendingApproval)
            case .deny(let reason):
                let result = ToolResult(ok: false, error: reason)
                await appendResultEvent(
                    for: effectiveCall,
                    result: result,
                    publishProgress: true,
                    to: &thread,
                    onProgress: onProgress
                )
                return .completed(AgentToolStepCompletion(
                    call: effectiveCall,
                    result: result,
                    followUpReviewResult: nil,
                    toolResults: [result]
                ))
            }
        }

        let result = try await executeApprovedTool(
            effectiveCall,
            router: router,
            workspaceRoot: workspaceRoot,
            thread: &thread,
            onProgress: onProgress
        )
        let followUpReviewResult = try await runFollowUpReviewIfNeeded(
            after: effectiveCall,
            result: result,
            router: router,
            workspaceRoot: workspaceRoot,
            thread: &thread,
            onProgress: onProgress
        )
        let toolResults = followUpReviewResult.map { [result, $0] } ?? [result]

        thread.updatedAt = Date()
        return .completed(AgentToolStepCompletion(
            call: effectiveCall,
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

    /// Executes the exact call released by a durable approval gate. The caller must first validate
    /// and persist the matching approval decision. No queued event is added because the original
    /// blocked step already recorded it; running/result events and model-facing tool feedback use
    /// the same path as an uninterrupted agent run.
    public func executeApprovedToolCall(
        _ call: ToolCall,
        in thread: ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> AgentApprovedToolExecution {
        var next = thread
        let definitions = Self.mergedToolDefinitions(baseToolDefinitions, additionalToolDefinitions)
        let router = ToolRouter(workspaceRoot: workspaceRoot, editGuard: .session(for: next.id), lsp: lsp)

        guard definitions.contains(where: { $0.name == call.name }) else {
            let result = ToolResult(ok: false, error: "Tool is not available in this workspace: \(call.name)")
            await appendResultEvent(
                for: call,
                result: result,
                unavailable: true,
                publishProgress: true,
                to: &next,
                onProgress: onProgress
            )
            return AgentApprovedToolExecution(thread: next, toolResults: [result])
        }

        let result = try await executeApprovedTool(
            call,
            router: router,
            workspaceRoot: workspaceRoot,
            thread: &next,
            onProgress: onProgress
        )
        let followUp = try await runFollowUpReviewIfNeeded(
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
            followUpReviewResult: followUp,
            toolResults: followUp.map { [result, $0] } ?? [result]
        )
        appendToolFeedback(completion, to: &next)
        await onProgress?(next)
        return AgentApprovedToolExecution(thread: next, toolResults: completion.toolResults)
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
        let executedResult: ToolResult
        if let execution = await threadToolExecutionOverride?(
            call,
            workspaceRoot,
            thread,
            onProgress
        ) {
            thread = execution.thread
            executedResult = execution.result
        } else if let searchResult = await webSearchResult(for: call) {
            executedResult = searchResult
        } else if let overrideResult = await toolExecutionOverride?(call, workspaceRoot) {
            executedResult = overrideResult
        } else {
            executedResult = router.execute(call)
        }
        try Task.checkCancellation()
        let result = try await finishToolCall(
            call,
            executedResult: executedResult,
            thread: &thread,
            workspaceRoot: workspaceRoot,
            onProgress: onProgress
        )
        await appendResultEvent(for: call, result: result, to: &thread, onProgress: onProgress)
        return result
    }

    private func toolRouter(workspaceRoot: URL, threadID: UUID) -> ToolRouter {
        ToolRouter(
            workspaceRoot: workspaceRoot,
            editGuard: .session(for: threadID),
            skill: skillResolver.map { SkillLoadToolExecutor(resolver: $0) },
            lsp: lsp
        )
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

}
