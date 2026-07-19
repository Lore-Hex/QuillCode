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
                    return try await performCorrectiveAttempt(
                        correctiveThread: correctiveThread,
                        correctionPrompt: correctionPrompt,
                        tools: tools,
                        thread: &thread,
                        onProgress: onProgress
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
                // A consumer-side cancellation can surface as garbage/partial text — honor the stop
                // FIRST (even at budget exhaustion), so a user Stop is never recorded as a malformed-
                // model failure.
                try Task.checkCancellation()
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw TrustedRouterAgentError.invalidActionJSON(text)
                }
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
                // Honor a stop before the exhaustion guard — see the invalidActionJSON arm.
                try Task.checkCancellation()
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw interrupted.underlying
                }
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
            } catch AgentError.emptyStreamingResponse {
                // A clean-but-empty stream: either a user Stop before the first token (the consumer
                // cancel makes the iterator end normally with no text — honor it as a stop, never a
                // failure), or a gateway tearing the stream down before any content (empty 200 body,
                // immediate [DONE]) — the streaming twin of TrustedRouterAgentError.emptyResponse,
                // which the transport classifier already deems "worth one more try".
                try Task.checkCancellation()
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw AgentError.emptyStreamingResponse
                }
                attempt += 1
                pendingCorrectionPrompt = nil
                thread.events.append(.init(
                    kind: .notice,
                    summary: "Self-healing: the model returned an empty response; retrying "
                        + "(attempt \(attempt) of \(Self.malformedActionCorrectionLimit))."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
            }
        }
    }

    /// Runs a corrective re-prompt through the normal (streaming) dispatch against a scratch copy of
    /// the corrective thread, then harvests the events the run appended (the "Model token usage"
    /// accounting event, the streaming notice) onto the durable thread — so corrective attempts are
    /// never invisible to the spend fuse/ledger/token chip. The correction context itself stays off
    /// the durable transcript, and `onProgress` is withheld from the scratch run so the transient
    /// corrective messages never flash into the UI.
    private func performCorrectiveAttempt(
        correctiveThread: ChatThread,
        correctionPrompt: String,
        tools: [ToolDefinition],
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        var correctiveRun = correctiveThread
        let priorEventCount = correctiveRun.events.count
        let action = try await dispatchNextAction(
            thread: &correctiveRun,
            userMessage: correctionPrompt,
            tools: tools,
            onProgress: nil
        )
        if correctiveRun.events.count > priorEventCount {
            thread.events.append(contentsOf: correctiveRun.events[priorEventCount...])
            thread.updatedAt = Date()
            await onProgress?(thread)
        }
        return action
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
