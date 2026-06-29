import Foundation
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools

public enum AgentAction: Sendable, Hashable {
    case say(String)
    case tool(ToolCall)
}

public protocol LLMClient: Sendable {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction
}

public protocol StreamingLLMClient: LLMClient {
    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error>
}

public protocol UsageStreamingLLMClient: StreamingLLMClient {
    func actionEventStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error>
}

public enum AgentError: Error, CustomStringConvertible {
    case emptyStreamingResponse
    case promisedWorkWithoutToolAction
    case tooManyToolSteps(Int)

    public var description: String {
        switch self {
        case .emptyStreamingResponse:
            return "The model stream finished without returning an action."
        case .promisedWorkWithoutToolAction:
            return "The model promised to perform work but did not return a tool action."
        case .tooManyToolSteps(let limit):
            return "The agent reached the tool-step limit (\(limit)) before returning a final answer."
        }
    }
}

public struct AgentRunResult: Sendable {
    public var thread: ChatThread
    public var toolResults: [ToolResult]

    public init(thread: ChatThread, toolResults: [ToolResult]) {
        self.thread = thread
        self.toolResults = toolResults
    }
}

public struct AgentToolFeedback: Codable, Sendable, Hashable {
    public var toolCall: ToolCall
    public var result: ToolResult
    public var followUpResult: ToolResult?

    public init(toolCall: ToolCall, result: ToolResult, followUpResult: ToolResult? = nil) {
        self.toolCall = toolCall
        self.result = result
        self.followUpResult = followUpResult
    }
}

public typealias AgentRunProgressHandler = @Sendable (ChatThread) async -> Void
public typealias AgentToolExecutionOverride = @Sendable (ToolCall, URL) async -> ToolResult?

public struct AgentRunner: Sendable {
    public static let streamingNotice = "Streaming model response"
    public static let defaultMaxToolSteps = 6
    private static let promisedWorkCorrectionLimit = 2

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

    private func actionByRetryingPromisedWorkIfNeeded(
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

    private func nextAction(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        if enablesImmediateActionPreflight,
           let action = AgentImmediateActionPlanner.action(for: userMessage, tools: tools) {
            return action
        }

        if let usageStreamingLLM = llm as? any UsageStreamingLLMClient {
            thread.events.append(.init(kind: .notice, summary: Self.streamingNotice))
            thread.updatedAt = Date()
            await onProgress?(thread)

            let stream = try await usageStreamingLLM.actionEventStream(
                thread: thread,
                userMessage: userMessage,
                tools: tools
            )
            return try await Self.collectStreamingAction(
                from: stream,
                thread: &thread,
                onProgress: onProgress
            )
        }

        guard let streamingLLM = llm as? any StreamingLLMClient else {
            return try await llm.nextAction(thread: thread, userMessage: userMessage, tools: tools)
        }

        thread.events.append(.init(kind: .notice, summary: Self.streamingNotice))
        thread.updatedAt = Date()
        await onProgress?(thread)

        let stream = try await streamingLLM.actionTextStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        return try await Self.collectStreamingAction(
            from: stream,
            thread: &thread,
            onProgress: onProgress
        )
    }

    static func collectStreamingAction(from stream: AsyncThrowingStream<String, Error>) async throws -> AgentAction {
        try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: AgentError.emptyStreamingResponse
        )
    }

    private static func collectStreamingAction(
        from stream: AsyncThrowingStream<String, Error>,
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        var draftThread = thread
        let action = try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: AgentError.emptyStreamingResponse,
            onVisibleAssistantText: { visibleText in
                publishAssistantDraft(visibleText, in: &draftThread)
                await onProgress?(draftThread)
            }
        )
        thread = draftThread
        return action
    }

    private static func collectStreamingAction(
        from stream: AsyncThrowingStream<AgentTextStreamEvent, Error>,
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        var draftThread = thread
        var latestUsage: ModelTokenUsage?

        let action = try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: AgentError.emptyStreamingResponse,
            onVisibleAssistantText: { visibleText in
                publishAssistantDraft(visibleText, in: &draftThread)
                await onProgress?(draftThread)
            },
            onUsage: { usage in
                latestUsage = usage
            },
            onReasoning: { summary in
                publishReasoningSummary(summary, in: &draftThread)
                await onProgress?(draftThread)
            }
        )

        thread = draftThread
        if let latestUsage {
            thread.events.append(ModelTokenUsageEvent.event(usage: latestUsage))
            thread.updatedAt = Date()
            await onProgress?(thread)
        }
        return action
    }

    private static func publishAssistantDraft(_ text: String, in thread: inout ChatThread) {
        if let lastIndex = thread.messages.indices.last,
           thread.messages[lastIndex].role == .assistant {
            thread.messages[lastIndex].content = text
        } else {
            thread.messages.append(.init(role: .assistant, content: text))
        }
        thread.updatedAt = Date()
    }

    private static func publishReasoningSummary(_ summary: String, in thread: inout ChatThread) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let notice = "Thinking: \(trimmed)"
        guard thread.events.last?.kind != .notice || thread.events.last?.summary != notice else {
            return
        }
        thread.events.append(.init(kind: .notice, summary: notice))
        thread.updatedAt = Date()
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
