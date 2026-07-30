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
