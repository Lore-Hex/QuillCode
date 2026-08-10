import Foundation
import QuillCodeCore

enum AgentEmptyResponseRetryPolicy {
    case standard
    case afterSuccessfulTool

    var retryLimit: Int {
        switch self {
        case .standard:
            AgentRunner.emptyResponseRetryLimit
        case .afterSuccessfulTool:
            1
        }
    }

    func backoffSeconds(forAttempt attempt: Int) -> Int {
        switch self {
        case .standard:
            min(2 * (1 << (attempt - 1)), 12)
        case .afterSuccessfulTool:
            0
        }
    }
}

extension AgentRunner {
    /// `injectedCorrection` seeds the resolver's existing corrective seam for ONE sample: the
    /// prompt is delivered on the value-copy corrective thread (never the durable transcript) and
    /// the resulting action flows back through the caller's whole pipeline — promised-work guard,
    /// deliverable/citation/word-budget gates — exactly like any other action. The repeat nudge
    /// (Cline learning #2) uses it; splicing a raw sample in at the call site instead bypassed the
    /// streaming path, the promised-work guard, and put a user turn in the transcript.
    func nextAction(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?,
        injectedCorrection: String? = nil,
        reasoningBudgetPhase: AgentReasoningBudgetPhase = .startup,
        emptyResponseRetryPolicy: AgentEmptyResponseRetryPolicy = .standard,
        absoluteTurnDeadline: Date? = nil
    ) async throws -> AgentAction {
        if injectedCorrection == nil,
           enablesImmediateActionPreflight,
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
        var pendingCorrectionPrompt: String? = injectedCorrection
        let authoritativeCorrectionPrompt = injectedCorrection
        if let injectedCorrection {
            correctiveThread.messages.append(.init(role: .user, content: injectedCorrection))
            correctiveThread.updatedAt = Date()
        }
        var attempt = 0
        var emptyResponseAttempt = 0
        // F22: which client resolves this action. Flips to `fallbackLLM` (at most once) when the
        // primary exhausts the empty-response budget — a route-quality death an alternate model
        // reliably survives. The owning send loop promotes a successful fallback for later actions.
        var activeLLM: LLMClient = llm
        var usedFallback = false
        while true {
            var attemptRunner = self
            if let absoluteTurnDeadline {
                guard let deadlineSeconds = AgentBoundedRunFinalizationGate
                    .preFinalizationTurnDeadlineSeconds(
                        remainingSeconds: absoluteTurnDeadline.timeIntervalSinceNow,
                        configuredTurnDeadlineSeconds: turnDeadlineSeconds
                    )
                else {
                    // Throw outside the corrective catch below so the owning run loop can enter
                    // finalization instead of spending another retry beyond the reserved boundary.
                    throw AgentTurnDeadlineExceededError(seconds: 0)
                }
                attemptRunner.turnDeadlineSeconds = deadlineSeconds
            }
            do {
                if let correctionPrompt = pendingCorrectionPrompt {
                    return try await attemptRunner.performCorrectiveAttempt(
                        correctiveThread: correctiveThread,
                        correctionPrompt: correctionPrompt,
                        tools: tools,
                        thread: &thread,
                        onProgress: onProgress,
                        via: activeLLM,
                        reasoningBudgetPhase: reasoningBudgetPhase == .boundedFinalization
                            ? .boundedFinalization
                            : .correction
                    )
                }
                return try await attemptRunner.dispatchNextAction(
                    thread: &thread,
                    userMessage: userMessage,
                    tools: tools,
                    onProgress: onProgress,
                    via: activeLLM,
                    reasoningBudgetPhase: reasoningBudgetPhase
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
                try Task.checkCancellation()
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw TrustedRouterAgentError.emptyToolArguments(toolName)
                }
                attempt += 1
                let correctionPrompt = AgentCorrectionEscalation.escalated(
                    AgentMalformedActionGuard.emptyToolArgumentsCorrectionPrompt(
                        toolName: toolName,
                        userMessage: userMessage
                    ),
                    attempt: attempt - 1,
                    limit: Self.malformedActionCorrectionLimit,
                    alternatives: [
                        "emit the intended tool action with every required argument populated",
                        "if the intended action is impossible, return a say action that names the blocker",
                    ]
                )
                correctiveThread.messages.append(.init(
                    role: .assistant,
                    content: "{\"type\":\"tool\",\"name\":\"\(toolName)\",\"arguments\":{}}"
                ))
                correctiveThread.messages.append(.init(role: .user, content: correctionPrompt))
                correctiveThread.updatedAt = Date()
                pendingCorrectionPrompt = correctionPrompt
                thread.events.append(.init(
                    kind: .notice,
                    summary: "Self-healing: the model omitted arguments for \(toolName); asked it "
                        + "to re-emit the action (attempt \(attempt) of "
                        + "\(Self.malformedActionCorrectionLimit))."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
            } catch TrustedRouterAgentError.invalidActionJSON(let text) {
                // A consumer-side cancellation can surface as garbage/partial text — honor the stop
                // FIRST (even at budget exhaustion), so a user Stop is never recorded as a malformed-
                // model failure.
                try Task.checkCancellation()
                // Diagnosis tap: the self-healing notice does not persist the raw payload, so a
                // route-quality investigation (malformed action on nearly every turn) has nothing to
                // inspect. Opt-in via env var; appends the raw model text to the given file.
                if let logPath = ProcessInfo.processInfo.environment["QUILLCODE_DEBUG_MALFORMED_LOG"],
                   !logPath.isEmpty {
                    let entry = "=== MALFORMED ===\n\(text)\n=== END ===\n\n"
                    if let data = entry.data(using: .utf8) {
                        if let handle = FileHandle(forWritingAtPath: logPath) {
                            handle.seekToEndOfFile()
                            handle.write(data)
                            try? handle.close()
                        } else {
                            try? data.write(to: URL(fileURLWithPath: logPath))
                        }
                    }
                }
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw TrustedRouterAgentError.invalidActionJSON(text)
                }
                let isTruncatedFileWrite = AgentMalformedActionGuard.isTruncatedFileWriteAction(text)
                attempt += 1
                let correctionPrompt = AgentCorrectionEscalation.escalated(
                    AgentMalformedActionGuard.correctionPrompt(
                        malformedText: text,
                        userMessage: userMessage
                    ),
                    attempt: attempt - 1,
                    limit: Self.malformedActionCorrectionLimit,
                    alternatives: [
                        "respond with EXACTLY one JSON object — {\"type\":\"tool\",...} or {\"type\":\"say\",...} — and nothing else: no prose, no markdown, no code fences",
                        "if you cannot produce the intended action, respond {\"type\":\"say\",\"text\":\"<what blocked you>\"}",
                    ]
                )
                correctiveThread.messages.append(.init(
                    role: .assistant,
                    content: AgentMalformedActionGuard.correctiveAssistantEcho(for: text)
                ))
                correctiveThread.messages.append(.init(role: .user, content: correctionPrompt))
                correctiveThread.updatedAt = Date()
                pendingCorrectionPrompt = correctionPrompt
                thread.events.append(.init(
                    kind: .notice,
                    summary: isTruncatedFileWrite
                        ? "Self-healing: the model truncated a file write; asked it to re-emit a "
                            + "complete concise action (attempt \(attempt) of "
                            + "\(Self.malformedActionCorrectionLimit))."
                        : "Self-healing: the model returned a malformed action; asked it to re-emit "
                            + "(attempt \(attempt) of \(Self.malformedActionCorrectionLimit))."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
            } catch let overrun as AgentTurnDeadlineExceededError {
                // F20: a reasoner streamed thinking past the turn budget without ever completing an
                // action (no terminal say — the phrase guards cannot see this shape). Honor a stop
                // first, then spend a bounded corrective attempt telling the model to stop planning
                // and emit the next action grounded in the tool output it actually has.
                try Task.checkCancellation()
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw overrun
                }
                attempt += 1
                let correctionPrompt = authoritativeCorrectionPrompt == nil
                    ? AgentTurnDeadline.correctionPrompt
                    : AgentPreActionReasoningBudget.recoveryPrompt(
                        preserving: authoritativeCorrectionPrompt
                    )
                correctiveThread.messages.append(.init(role: .user, content: correctionPrompt))
                correctiveThread.updatedAt = Date()
                pendingCorrectionPrompt = correctionPrompt
                thread.events.append(.init(
                    kind: .notice,
                    summary: "Self-healing: the model reasoned past the turn deadline without acting; "
                        + "asked it to emit the next action "
                        + "(attempt \(attempt) of \(Self.malformedActionCorrectionLimit))."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
            } catch let overrun as AgentPreActionReasoningBudgetExceededError {
                try Task.checkCancellation()
                guard attempt < Self.malformedActionCorrectionLimit else {
                    if let fallback = fallbackLLM, !usedFallback {
                        usedFallback = true
                        activeLLM = fallback
                        // The new route has not consumed any semantic corrections for this step.
                        // Reset the local budget so a fast malformed/prose response can still be
                        // repaired into an action instead of inheriting the displaced route's
                        // exhausted reasoning attempts. `usedFallback` and the per-route limit keep
                        // the recovery bounded: there is still only one route switch.
                        attempt = 0
                        emptyResponseAttempt = 0
                        pendingCorrectionPrompt = AgentPreActionReasoningBudget.recoveryPrompt(
                            preserving: authoritativeCorrectionPrompt ?? pendingCorrectionPrompt
                        )
                        thread.events.append(.init(
                            kind: .notice,
                            summary: Self.reasoningFallbackSwitchNotice
                        ))
                        thread.updatedAt = Date()
                        await onProgress?(thread)
                        continue
                    }
                    throw overrun
                }
                attempt += 1
                let correctionPrompt = AgentPreActionReasoningBudget.recoveryPrompt(
                    preserving: authoritativeCorrectionPrompt ?? pendingCorrectionPrompt
                )
                correctiveThread.messages.append(.init(role: .user, content: correctionPrompt))
                correctiveThread.updatedAt = Date()
                pendingCorrectionPrompt = correctionPrompt
                thread.events.append(.init(
                    kind: .notice,
                    summary: "Self-healing: the model exhausted its pre-action reasoning budget; "
                        + "asked it to emit the next action "
                        + "(attempt \(attempt) of \(Self.malformedActionCorrectionLimit))."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
            } catch let reasoningOnly as AgentReasoningOnlyResponseError {
                try Task.checkCancellation()
                guard attempt < Self.malformedActionCorrectionLimit else {
                    throw reasoningOnly
                }
                attempt += 1
                let correctionPrompt = AgentPreActionReasoningBudget.recoveryPrompt(
                    preserving: authoritativeCorrectionPrompt ?? pendingCorrectionPrompt
                )
                correctiveThread.messages.append(.init(role: .user, content: correctionPrompt))
                correctiveThread.updatedAt = Date()
                pendingCorrectionPrompt = correctionPrompt
                thread.events.append(.init(
                    kind: .notice,
                    summary: "Self-healing: the model finished reasoning without an action; "
                        + "asked it to emit the next action "
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
                pendingCorrectionPrompt = authoritativeCorrectionPrompt
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
                guard emptyResponseAttempt < emptyResponseRetryPolicy.retryLimit else {
                    // F22: the primary cannot produce this step at all. Try the fallback model —
                    // once — with a fresh correction budget before declaring the run dead.
                    if let fallback = fallbackLLM, !usedFallback {
                        usedFallback = true
                        activeLLM = fallback
                        attempt = 0
                        emptyResponseAttempt = 0
                        pendingCorrectionPrompt = authoritativeCorrectionPrompt
                        thread.events.append(.init(
                            kind: .notice,
                            summary: Self.fallbackSwitchNotice
                        ))
                        thread.updatedAt = Date()
                        await onProgress?(thread)
                        continue
                    }
                    throw AgentError.emptyStreamingResponse
                }
                emptyResponseAttempt += 1
                let backoffSeconds = emptyResponseRetryPolicy.backoffSeconds(
                    forAttempt: emptyResponseAttempt
                )
                pendingCorrectionPrompt = authoritativeCorrectionPrompt
                thread.events.append(.init(
                    kind: .notice,
                    summary: backoffSeconds > 0
                        ? "Self-healing: the model returned an empty response; retrying after "
                            + "a \(backoffSeconds)-second backoff "
                            + "(attempt \(emptyResponseAttempt) of "
                            + "\(emptyResponseRetryPolicy.retryLimit))."
                        : "Self-healing: the model returned an empty response after a successful "
                            + "tool; retrying immediately once."
                ))
                thread.updatedAt = Date()
                await onProgress?(thread)
                if backoffSeconds > 0 {
                    try await emptyResponseRetrySleeper.sleep(.seconds(backoffSeconds))
                }
                try Task.checkCancellation()
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
        onProgress: AgentRunProgressHandler?,
        via llm: LLMClient,
        reasoningBudgetPhase: AgentReasoningBudgetPhase
    ) async throws -> AgentAction {
        var correctiveRun = AgentCorrectiveContext.projected(correctiveThread)
        let priorEventCount = correctiveRun.events.count
        let action = try await dispatchNextAction(
            thread: &correctiveRun,
            userMessage: correctionPrompt,
            tools: tools,
            onProgress: nil,
            via: llm,
            reasoningBudgetPhase: reasoningBudgetPhase
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
        onProgress: AgentRunProgressHandler?,
        via llm: LLMClient,
        reasoningBudgetPhase: AgentReasoningBudgetPhase
    ) async throws -> AgentAction {
        if let usageStreamingLLM = llm as? any UsageStreamingLLMClient {
            return try await nextUsageStreamingAction(
                from: usageStreamingLLM,
                thread: &thread,
                userMessage: userMessage,
                tools: tools,
                onProgress: onProgress,
                reasoningBudgetPhase: reasoningBudgetPhase
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
