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
                  AgentPromisedWorkGuard.shouldRequestCorrection(for: text, tools: tools)
            else {
                return candidate
            }

            if let recovered = Self.recoveredPromisedWorkAction(from: text, tools: tools) {
                return recovered
            }

            let correctionPrompt = AgentPromisedWorkGuard.correctionPrompt(
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

        if case .say(let text) = candidate,
           AgentPromisedWorkGuard.shouldRequestCorrection(for: text, tools: tools) {
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
}
