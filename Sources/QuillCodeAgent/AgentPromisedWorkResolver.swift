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
        for _ in 0..<Self.promisedWorkCorrectionLimit {
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

            let correctionPrompt = AgentPromisedWorkGuard.correctionPrompt(
                for: correction,
                assistantText: text,
                userMessage: userMessage
            )
            retryThread.messages.append(.init(role: .assistant, content: text))
            retryThread.messages.append(.init(role: .user, content: correctionPrompt))
            retryThread.updatedAt = Date()
            candidate = try await llm.nextAction(
                thread: retryThread,
                userMessage: correctionPrompt,
                tools: tools
            )
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
        for _ in 0..<Self.promisedWorkCorrectionLimit {
            guard case .say(let text) = candidate else { return candidate }
            let missing = AgentDeliverableGate.missingDeliverables(
                in: userMessage,
                workspaceRoot: workspaceRoot
            )
            guard !missing.isEmpty else { return candidate }
            let correctionPrompt = AgentDeliverableGate.correctionPrompt(missing: missing)
            retryThread.messages.append(.init(role: .assistant, content: text))
            retryThread.messages.append(.init(role: .user, content: correctionPrompt))
            retryThread.updatedAt = Date()
            candidate = try await llm.nextAction(
                thread: retryThread,
                userMessage: correctionPrompt,
                tools: tools
            )
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
        for _ in 0..<Self.promisedWorkCorrectionLimit {
            guard case .say(let text) = candidate else { return candidate }
            let ungrounded = offenders(in: text)
            let correctionPrompt: String
            if !ungrounded.isEmpty {
                correctionPrompt = AgentCitationIntegrityGate.correctionPrompt(unfetched: ungrounded)
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
            candidate = try await llm.nextAction(
                thread: retryThread,
                userMessage: correctionPrompt,
                tools: tools
            )
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
}
