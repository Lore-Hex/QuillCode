import Foundation
import QuillCodeCore

extension AgentRunner {
    func actionByRetryingPromisedWorkIfNeeded(
        _ action: AgentAction,
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        var candidate = action
        var retryThread = thread
        for attempt in 0..<Self.promisedWorkCorrectionLimit {
            guard case .say(let text) = candidate,
                  let correction = AgentPromisedWorkGuard.correctionNeeded(for: text, tools: tools)
            else {
                return candidate
            }

            // Local recovery only applies to promised work (an embedded tool action, or the
            // immediate-action planner re-deriving the user's ask). A deferral has no embedded
            // action to recover — it must be re-driven by the model.
            if correction == .promisedWork {
                if let recovered = Self.recoveredPromisedWorkAction(from: text, tools: tools) {
                    return recovered
                }
                if let recovered = Self.recoveredPromisedUserIntentAction(
                    from: userMessage,
                    tools: tools
                ) {
                    return recovered
                }
            }

            let correctionPrompt = AgentCorrectionEscalation.escalated(
                AgentPromisedWorkGuard.correctionPrompt(
                    for: correction,
                    assistantText: text,
                    userMessage: userMessage
                ),
                attempt: attempt,
                limit: Self.promisedWorkCorrectionLimit,
                alternatives: [
                    "emit the promised tool call as your next action, with no prose around it",
                    "if the work is already complete, state the concrete result plainly in past tense",
                    "if you are blocked, write exactly what you did and what blocked you",
                ]
            )
            retryThread.messages.append(.init(role: .assistant, content: text))
            retryThread.messages.append(.init(role: .user, content: correctionPrompt))
            retryThread.updatedAt = Date()
            guard let sampled = try await correctiveSample(
                thread: retryThread,
                prompt: correctionPrompt,
                tools: tools
            ) else { continue }
            candidate = sampled
        }

        // Budget spent. Only unmet promised work is a hard failure — a model that keeps ASKING
        // (deferral) after being nudged to continue probably genuinely needs input, so that say is
        // allowed through rather than turned into an error.
        if case .say(let text) = candidate,
           let correction = AgentPromisedWorkGuard.correctionNeeded(for: text, tools: tools),
           correction.isHardFailure {
            throw AgentError.promisedWorkWithoutToolAction
        }
        return candidate
    }

    /// Shape-5 enforcement (F23): a terminal say while a task-named CREATED file is missing on
    /// disk gets a bounded corrective re-prompt to write it — the mechanical backstop behind the
    /// "deliverables go to disk" prompt guidance, which a bare "Done." sails straight past. Runs
    /// the fix loop only for says, only when file tools are available, and hard-fails honestly if
    /// the model still won't produce the artifact (the correction's escape hatch — "write what
    /// blocked you" — means persistent refusal is model failure, not a legitimate outcome).
    func actionByRequiringNamedDeliverables(
        _ action: AgentAction,
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        workspaceRoot: URL
    ) async throws -> AgentAction {
        guard tools.contains(where: { $0.name == "host.file.write" }) else { return action }
        var candidate = action
        var retryThread = thread
        for attempt in 0..<Self.promisedWorkCorrectionLimit {
            guard case .say(let text) = candidate else { return candidate }
            let missing = AgentDeliverableGate.missingDeliverables(
                in: userMessage,
                workspaceRoot: workspaceRoot
            )
            guard !missing.isEmpty else { return candidate }
            let correctionPrompt = AgentCorrectionEscalation.escalated(
                AgentDeliverableGate.correctionPrompt(missing: missing),
                attempt: attempt,
                limit: Self.promisedWorkCorrectionLimit,
                alternatives: [
                    "create the named file NOW with host.file.write (path + full content)",
                    "if genuinely blocked, write exactly what you did and what blocked you — do not promise future work",
                ]
            )
            retryThread.messages.append(.init(role: .assistant, content: text))
            retryThread.messages.append(.init(role: .user, content: correctionPrompt))
            retryThread.updatedAt = Date()
            guard let sampled = try await correctiveSample(
                thread: retryThread,
                prompt: correctionPrompt,
                tools: tools
            ) else { continue }
            candidate = sampled
        }
        if case .say = candidate {
            let stillMissing = AgentDeliverableGate.missingDeliverables(
                in: userMessage,
                workspaceRoot: workspaceRoot
            )
            if let first = stillMissing.first {
                throw AgentError.missingNamedDeliverable(first)
            }
        }
        return candidate
    }

    /// F29 — a terminal say may not cite markdown-linked URLs the run never successfully fetched.
    /// The corrective loop gives the model a bounded chance to fetch or remove each link; a tool
    /// action from the corrective sample flows back into the run loop like any other step.
    /// Persistent refusal does NOT hard-fail the run: the say passes through with a visible
    /// integrity notice appended, so a rare false positive degrades to a note, never a dead run.
    func actionByRequiringCitationIntegrity(
        _ action: AgentAction,
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        workspaceRoot: URL,
        groundedURLs: Set<String>,
        writtenWorkspacePaths: Set<String>
    ) async throws -> AgentAction {
        var candidate = action
        var retryThread = thread
        func offenders(in text: String) -> [String] {
            AgentCitationIntegrityGate.ungroundedCitations(
                sayText: text,
                userMessage: userMessage,
                workspaceRoot: workspaceRoot,
                groundedURLs: groundedURLs,
                writtenWorkspacePaths: writtenWorkspacePaths
            )
        }
        for attempt in 0..<Self.promisedWorkCorrectionLimit {
            guard case .say(let text) = candidate else { return candidate }
            let ungrounded = offenders(in: text)
            let correctionPrompt: String
            if !ungrounded.isEmpty {
                correctionPrompt = AgentCorrectionEscalation.escalated(
                    AgentCitationIntegrityGate.correctionPrompt(unfetched: ungrounded),
                    attempt: attempt,
                    limit: Self.promisedWorkCorrectionLimit,
                    alternatives: [
                        "call host.web.fetch on each listed URL now and keep only the ones that succeed",
                        "remove the listed links and mark those claims 'unverified' in the deliverable file and your answer",
                    ]
                )
            } else if let promise = AgentPromisedWorkGuard.correctionNeeded(for: text, tools: tools) {
                // A corrective sample can dodge the gate with a link-free promise ("I'll fetch it
                // now") — no offenders, so it would pass, and the promised-work guard upstream has
                // already run. Re-screen promises here within the same budget (proven live by a
                // review probe: the run ended on exactly that bare promise).
                correctionPrompt = AgentPromisedWorkGuard.correctionPrompt(
                    for: promise,
                    assistantText: text,
                    userMessage: userMessage
                )
            } else {
                return candidate
            }
            retryThread.messages.append(.init(role: .assistant, content: text))
            retryThread.messages.append(.init(role: .user, content: correctionPrompt))
            retryThread.updatedAt = Date()
            guard let sampled = try await correctiveSample(
                thread: retryThread,
                prompt: correctionPrompt,
                tools: tools
            ) else { continue }
            candidate = sampled
        }
        if case .say(let text) = candidate {
            let ungrounded = offenders(in: text)
            if !ungrounded.isEmpty {
                return .say(text + "\n\n" + AgentCitationIntegrityGate.integrityNotice(unfetched: ungrounded))
            }
        }
        return candidate
    }

    private static func recoveredPromisedWorkAction(
        from text: String,
        tools: [ToolDefinition]
    ) -> AgentAction? {
        guard let action = try? AgentActionJSONParser.parse(text),
              case .tool(let call) = action,
              tools.contains(where: { $0.name == call.name })
        else {
            return nil
        }
        return action
    }

    private static func recoveredPromisedUserIntentAction(
        from userMessage: String,
        tools: [ToolDefinition]
    ) -> AgentAction? {
        AgentImmediateActionPlanner.action(for: userMessage, tools: tools)
    }

    /// F31: gate corrective samples call the raw LLM client, which throws on a malformed or
    /// empty response — with no recovery arm around these calls, ONE thinking-only sample killed
    /// an otherwise-finished research run (live: the deliverable gate's corrective after a
    /// misnamed deliverable; TrustedRouterAgentError.invalidActionJSON propagated straight out of
    /// send()). The main resolver's malformed-recovery loop does not cover these paths — the
    /// F25 lesson applied to sampling: every model-sampling path needs bounded tolerance, not
    /// just the main action loop. A bad sample returns nil, consuming the attempt; the caller's
    /// loop re-prompts (escalated on the final attempt) or falls through to the gate's terminal
    /// behavior (hard fail / integrity notice / budget-spent tail). Transport and cancellation
    /// errors still propagate.
    private func correctiveSample(
        thread: ChatThread,
        prompt: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction? {
        do {
            return try await llm.nextAction(thread: thread, userMessage: prompt, tools: tools)
        } catch TrustedRouterAgentError.invalidActionJSON, TrustedRouterAgentError.emptyResponse,
                TrustedRouterAgentError.emptyToolArguments {
            return nil
        }
    }

}
