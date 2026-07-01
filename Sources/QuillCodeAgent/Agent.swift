import Foundation
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools

public struct AgentRunner: Sendable {
    public static let streamingNotice = "Streaming model response"
    public static let defaultMaxToolSteps = 6
    static let promisedWorkCorrectionLimit = 2

    public var llm: LLMClient
    public var safety: SafetyReviewer
    public var baseToolDefinitions: [ToolDefinition]
    public var additionalToolDefinitions: [ToolDefinition]
    public var toolExecutionOverride: AgentToolExecutionOverride?
    public var maxToolSteps: Int
    public var enablesImmediateActionPreflight: Bool

    public init(
        llm: LLMClient = MockLLMClient(),
        safety: SafetyReviewer = AutoSafetyReviewer(),
        baseToolDefinitions: [ToolDefinition] = ToolRouter.definitions,
        additionalToolDefinitions: [ToolDefinition] = [],
        toolExecutionOverride: AgentToolExecutionOverride? = nil,
        maxToolSteps: Int = AgentRunner.defaultMaxToolSteps,
        enablesImmediateActionPreflight: Bool = false
    ) {
        self.llm = llm
        self.safety = safety
        self.baseToolDefinitions = baseToolDefinitions
        self.additionalToolDefinitions = additionalToolDefinitions
        self.toolExecutionOverride = toolExecutionOverride
        self.maxToolSteps = maxToolSteps
        self.enablesImmediateActionPreflight = enablesImmediateActionPreflight
    }

    public func send(
        _ userMessage: String,
        in thread: ChatThread,
        workspaceRoot: URL,
        recordUserMessage: Bool = true,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> AgentRunResult {
        var next = thread
        if recordUserMessage {
            next.messages.append(.init(role: .user, content: userMessage))
            next.events.append(.init(kind: .message, summary: userMessage))
            next.updatedAt = Date()
            if next.title == "New chat" {
                next.title = Self.title(from: userMessage)
            }
        }
        await onProgress?(next)

        do {
            try Task.checkCancellation()
            let tools = Self.mergedToolDefinitions(baseToolDefinitions, additionalToolDefinitions)
            var toolResults: [ToolResult] = []
            var lastExecutedCall: ToolCall?
            var lastCompletion: AgentToolStepCompletion?
            let limit = max(1, maxToolSteps)

            for _ in 0..<limit {
                let action = try await nextAction(
                    thread: &next,
                    userMessage: userMessage,
                    tools: tools,
                    onProgress: onProgress
                )
                let resolvedAction = try await actionByRetryingPromisedWorkIfNeeded(
                    action,
                    thread: next,
                    userMessage: userMessage,
                    tools: tools
                )
                try Task.checkCancellation()
                switch resolvedAction {
                case .say(let text):
                    appendAssistantMessage(text, to: &next)
                    await onProgress?(next)
                    return AgentRunResult(thread: next, toolResults: toolResults)
                case .tool(let call):
                    if let lastExecutedCall,
                       lastExecutedCall.name == call.name,
                       lastExecutedCall.argumentsJSON == call.argumentsJSON,
                       let lastCompletion {
                        appendAssistantMessage(Self.finalAnswer(
                            for: lastCompletion.call,
                            result: lastCompletion.result,
                            followUpReviewResult: lastCompletion.followUpReviewResult
                        ), to: &next)
                        await onProgress?(next)
                        return AgentRunResult(thread: next, toolResults: toolResults)
                    }

                    let step = try await runToolStep(
                        call,
                        userMessage: userMessage,
                        thread: &next,
                        workspaceRoot: workspaceRoot,
                        toolDefinitions: tools,
                        onProgress: onProgress
                    )
                    switch step {
                    case .blocked:
                        return AgentRunResult(thread: next, toolResults: toolResults)
                    case .completed(let completion):
                        toolResults.append(contentsOf: completion.toolResults)
                        lastExecutedCall = call
                        lastCompletion = completion
                        appendToolFeedback(completion, to: &next)
                    }
                }
            }

            if let lastCompletion {
                appendAssistantMessage(Self.finalAnswer(
                    for: lastCompletion.call,
                    result: lastCompletion.result,
                    followUpReviewResult: lastCompletion.followUpReviewResult
                ), to: &next)
            } else {
                let message = AgentError.tooManyToolSteps(limit).description
                next.messages.append(.init(role: .assistant, content: message))
                next.events.append(.init(kind: .message, summary: message))
                next.updatedAt = Date()
            }
            await onProgress?(next)
            return AgentRunResult(thread: next, toolResults: toolResults)
        } catch is CancellationError {
            AgentCancellationRecorder.recordCancelledRun(in: &next)
            await onProgress?(next)
            throw CancellationError()
        }
    }

    private func appendAssistantMessage(_ text: String, to thread: inout ChatThread) {
        if let lastIndex = thread.messages.indices.last,
           thread.messages[lastIndex].role == .assistant {
            thread.messages[lastIndex].content = text
        } else {
            thread.messages.append(.init(role: .assistant, content: text))
        }
        thread.events.append(.init(kind: .message, summary: text))
        thread.updatedAt = Date()
    }

    private static func mergedToolDefinitions(
        _ base: [ToolDefinition],
        _ additional: [ToolDefinition]
    ) -> [ToolDefinition] {
        var seen = Set<String>()
        var definitions: [ToolDefinition] = []
        for definition in base + additional {
            guard !seen.contains(definition.name) else { continue }
            seen.insert(definition.name)
            definitions.append(definition)
        }
        return definitions
    }

    static func finalAnswer(
        for call: ToolCall,
        result: ToolResult,
        followUpReviewResult: ToolResult? = nil
    ) -> String {
        AgentFinalAnswerBuilder.finalAnswer(
            for: call,
            result: result,
            followUpReviewResult: followUpReviewResult
        )
    }

    static func title(from userMessage: String) -> String {
        let words = userMessage.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "New chat" : words
    }
}
