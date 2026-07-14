import Foundation
import QuillCodeCore

extension AgentRunner {
    func prepareToolCall(
        _ call: ToolCall,
        thread: inout ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentPreToolUseHookOutcome {
        guard let preToolUseHook else {
            return AgentPreToolUseHookOutcome(call: call)
        }
        try Task.checkCancellation()
        var outcome = try await preToolUseHook(call, thread, workspaceRoot)
        try Task.checkCancellation()
        if outcome.call.id != call.id || outcome.call.name != call.name {
            outcome.call = call
            outcome.notices.append("Ignored a tool hook rewrite that changed the tool identity.")
        }
        await appendHookEffects(
            contexts: outcome.additionalContexts,
            notices: outcome.notices,
            to: &thread,
            onProgress: onProgress
        )
        return outcome
    }

    func finishToolCall(
        _ call: ToolCall,
        executedResult: ToolResult,
        thread: inout ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> ToolResult {
        guard let postToolUseHook else { return executedResult }
        try Task.checkCancellation()
        let outcome = try await postToolUseHook(call, executedResult, thread, workspaceRoot)
        try Task.checkCancellation()
        await appendHookEffects(
            contexts: outcome.additionalContexts,
            notices: outcome.notices,
            to: &thread,
            onProgress: onProgress
        )
        return outcome.result
    }

    func resolvePermissionRequest(
        for call: ToolCall,
        approvalReason: String,
        thread: inout ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentPermissionRequestDecision {
        guard let permissionRequestHook else { return .noDecision }
        do {
            try Task.checkCancellation()
            let outcome = try await permissionRequestHook(
                call,
                approvalReason,
                thread,
                workspaceRoot
            )
            try Task.checkCancellation()
            await appendHookEffects(
                contexts: [],
                notices: outcome.notices,
                to: &thread,
                onProgress: onProgress
            )
            return outcome.decision
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await appendHookEffects(
                contexts: [],
                notices: ["Permission hook warning: \(error.localizedDescription) Normal approval is still required."],
                to: &thread,
                onProgress: onProgress
            )
            return .noDecision
        }
    }

    private func appendHookEffects(
        contexts: [String],
        notices: [String],
        to thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async {
        let contexts = contexts.filter { !$0.isEmpty }
        let notices = notices.filter { !$0.isEmpty }
        guard !contexts.isEmpty || !notices.isEmpty else { return }

        thread.messages.append(contentsOf: contexts.map { ChatMessage(role: .system, content: $0) })
        thread.events.append(contentsOf: notices.map { ThreadEvent(kind: .notice, summary: $0) })
        thread.updatedAt = Date()
        await onProgress?(thread)
    }
}
