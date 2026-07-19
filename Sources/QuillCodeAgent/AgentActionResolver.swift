import Foundation
import QuillCodeCore

extension AgentRunner {
    func nextAction(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        if enablesImmediateActionPreflight,
           let action = AgentImmediateActionPlanner.action(for: userMessage, tools: tools) {
            // The planner parsed this action from the user's own command. A user-authored file
            // write is not a model blind-overwrite, so record that target as known for this
            // thread before the read-before-write guard runs. LLM-produced actions below do not
            // get this marker.
            AgentImmediateActionWriteReadMarker.markIfNeeded(
                action,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
            return action
        }

        // Bounded recovery loop: one garbage response or a mid-stream transport reset must not kill
        // an unattended run. Corrective context lives ONLY on `correctiveThread` (a value copy, like
        // AgentPromisedWorkResolver's retryThread) so malformed text never persists in the durable
        // transcript; the durable thread gets only a Self-healing notice per attempt.
        var correctiveThread = thread
        var pendingCorrectionPrompt: String?
        var attempt = 0
        while true {
            do {
                if let correctionPrompt = pendingCorrectionPrompt {
                    // Corrective re-prompt: a plain (non-streaming) call is deliberate — the reply is
                    // one short action object, and the correction context stays off the real thread.
                    return try await llm.nextAction(
                        thread: correctiveThread,
                        userMessage: correctionPrompt,
                        tools: tools
                    )
                }
                return try await dispatchNextAction(
                    thread: &thread,
                    userMessage: userMessage,
                    tools: tools,
                    onProgress: onProgress
                )
            } catch TrustedRouterAgentError.emptyToolArguments(let toolName) {
                if let action = AgentImmediateActionPlanner.action(for: userMessage, tools: tools) {
                    AgentImmediateActionWriteReadMarker.markIfNeeded(
                        action,
                        thread: thread,
                        workspaceRoot: workspaceRoot
                    )
                    return action
                }
                throw TrustedRouterAgentError.emptyToolArguments(toolName)
            } catch TrustedRouterAgentError.invalidActionJSON(let text) {
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw TrustedRouterAgentError.invalidActionJSON(text)
                }
                // A consumer-side cancellation can surface as garbage/partial text — honor the stop
                // instead of re-prompting on a run the user just cancelled.
                try Task.checkCancellation()
                attempt += 1
                let correctionPrompt = AgentMalformedActionGuard.correctionPrompt(
                    malformedText: text,
                    userMessage: userMessage
                )
                correctiveThread.messages.append(.init(
                    role: .assistant,
                    content: String(text.prefix(AgentMalformedActionGuard.malformedTextEchoLimit))
                ))
                correctiveThread.messages.append(.init(role: .user, content: correctionPrompt))
                correctiveThread.updatedAt = Date()
                pendingCorrectionPrompt = correctionPrompt
                thread.events.append(.init(
                    kind: .notice,
                    summary: "Self-healing: the model returned a malformed action; asked it to re-emit "
                        + "(attempt \(attempt) of \(Self.malformedActionCorrectionLimit))."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
            } catch let interrupted as AgentStreamInterruptedError {
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw interrupted.underlying
                }
                try Task.checkCancellation()
                attempt += 1
                // A pure resample through the normal (streaming) path — no corrective context needed.
                pendingCorrectionPrompt = nil
                thread.events.append(.init(
                    kind: .notice,
                    summary: "Self-healing: the model stream was interrupted mid-response; retrying "
                        + "(attempt \(attempt) of \(Self.malformedActionCorrectionLimit))."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
            }
        }
    }

    /// The original resolution dispatch: usage-streaming, then text-streaming, then plain.
    private func dispatchNextAction(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        if let usageStreamingLLM = llm as? any UsageStreamingLLMClient {
            return try await nextUsageStreamingAction(
                from: usageStreamingLLM,
                thread: &thread,
                userMessage: userMessage,
                tools: tools,
                onProgress: onProgress
            )
        }

        if let streamingLLM = llm as? any StreamingLLMClient {
            return try await nextTextStreamingAction(
                from: streamingLLM,
                thread: &thread,
                userMessage: userMessage,
                tools: tools,
                onProgress: onProgress
            )
        }

        return try await llm.nextAction(thread: thread, userMessage: userMessage, tools: tools)
    }
}
