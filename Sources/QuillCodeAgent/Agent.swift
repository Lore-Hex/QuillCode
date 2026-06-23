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

public enum AgentError: Error, CustomStringConvertible {
    case emptyStreamingResponse
    case tooManyToolSteps(Int)

    public var description: String {
        switch self {
        case .emptyStreamingResponse:
            return "The model stream finished without returning an action."
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

    public var llm: LLMClient
    public var safety: SafetyReviewer
    public var baseToolDefinitions: [ToolDefinition]
    public var additionalToolDefinitions: [ToolDefinition]
    public var toolExecutionOverride: AgentToolExecutionOverride?
    public var maxToolSteps: Int

    public init(
        llm: LLMClient = MockLLMClient(),
        safety: SafetyReviewer = AutoSafetyReviewer(),
        baseToolDefinitions: [ToolDefinition] = ToolRouter.definitions,
        additionalToolDefinitions: [ToolDefinition] = [],
        toolExecutionOverride: AgentToolExecutionOverride? = nil,
        maxToolSteps: Int = AgentRunner.defaultMaxToolSteps
    ) {
        self.llm = llm
        self.safety = safety
        self.baseToolDefinitions = baseToolDefinitions
        self.additionalToolDefinitions = additionalToolDefinitions
        self.toolExecutionOverride = toolExecutionOverride
        self.maxToolSteps = maxToolSteps
    }

    public func send(
        _ userMessage: String,
        in thread: ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler? = nil
    ) async throws -> AgentRunResult {
        var next = thread
        next.messages.append(.init(role: .user, content: userMessage))
        next.events.append(.init(kind: .message, summary: userMessage))
        next.updatedAt = Date()
        if next.title == "New chat" {
            next.title = Self.title(from: userMessage)
        }
        await onProgress?(next)

        try Task.checkCancellation()
        let tools = Self.mergedToolDefinitions(baseToolDefinitions, additionalToolDefinitions)
        var toolResults: [ToolResult] = []
        var lastExecutedCall: ToolCall?
        var lastCompletion: ToolStepCompletion?
        let limit = max(1, maxToolSteps)

        for _ in 0..<limit {
            let action = try await nextAction(
                thread: &next,
                userMessage: userMessage,
                tools: tools,
                onProgress: onProgress
            )
            try Task.checkCancellation()
            switch action {
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
    }

    private func nextAction(
        thread: inout ChatThread,
        userMessage: String,
        tools: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
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

    private static func publishAssistantDraft(_ text: String, in thread: inout ChatThread) {
        if let lastIndex = thread.messages.indices.last,
           thread.messages[lastIndex].role == .assistant {
            thread.messages[lastIndex].content = text
        } else {
            thread.messages.append(.init(role: .assistant, content: text))
        }
        thread.updatedAt = Date()
    }

    private enum ToolStep {
        case completed(ToolStepCompletion)
        case blocked
    }

    private struct ToolStepCompletion {
        var call: ToolCall
        var result: ToolResult
        var followUpReviewResult: ToolResult?
        var toolResults: [ToolResult]
    }

    private func runToolStep(
        _ call: ToolCall,
        userMessage: String,
        thread: inout ChatThread,
        workspaceRoot: URL,
        toolDefinitions: [ToolDefinition],
        onProgress: AgentRunProgressHandler?
    ) async throws -> ToolStep {
        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let definition = toolDefinitions.first { $0.name == call.name }
        let transcriptCall = call.redactedForTranscript()
        let callJSON = (try? JSONHelpers.encodePretty(transcriptCall)) ?? transcriptCall.argumentsJSON
        thread.events.append(.init(
            kind: .toolQueued,
            summary: "\(call.name) queued",
            payloadJSON: callJSON
        ))
        thread.updatedAt = Date()
        await onProgress?(thread)

        guard let definition else {
            let result = ToolResult(
                ok: false,
                error: "Tool is not available in this workspace: \(call.name)"
            )
            let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
            thread.events.append(.init(
                kind: .toolFailed,
                summary: "\(call.name) unavailable",
                payloadJSON: resultJSON
            ))
            thread.updatedAt = Date()
            await onProgress?(thread)
            return .completed(ToolStepCompletion(
                call: call,
                result: result,
                followUpReviewResult: nil,
                toolResults: [result]
            ))
        }

        try Task.checkCancellation()
        let review = await safety.review(.init(
            mode: thread.mode,
            userMessage: userMessage,
            toolCall: call,
            toolDefinition: definition,
            recentMessages: thread.messages
        ))
        try Task.checkCancellation()

        if review.verdict != .approve {
            let text: String
            switch review.verdict {
            case .clarify:
                text = "I need a little more detail before running \(call.name): \(review.rationale)"
            case .deny:
                text = "I cannot run \(call.name): \(review.rationale)"
            case .approve:
                text = ""
            }
            thread.events.append(.init(
                kind: .approvalRequested,
                summary: "\(review.verdict.rawValue): \(review.rationale)"
            ))
            thread.messages.append(.init(role: .assistant, content: text))
            thread.events.append(.init(kind: .message, summary: text))
            thread.updatedAt = Date()
            await onProgress?(thread)
            return .blocked
        }

        thread.events.append(.init(kind: .toolRunning, summary: "\(call.name) running"))
        thread.updatedAt = Date()
        await onProgress?(thread)
        try Task.checkCancellation()
        let result = await toolExecutionOverride?(call, workspaceRoot) ?? router.execute(call)
        try Task.checkCancellation()
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        thread.events.append(.init(
            kind: result.ok ? .toolCompleted : .toolFailed,
            summary: result.ok ? "\(call.name) completed" : "\(call.name) failed",
            payloadJSON: resultJSON
        ))
        var toolResults = [result]
        var patchReviewResult: ToolResult?
        if call.name == ToolDefinition.applyPatch.name, result.ok {
            let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
            let diffCallJSON = (try? JSONHelpers.encodePretty(diffCall.redactedForTranscript()))
                ?? diffCall.argumentsJSON
            thread.events.append(.init(
                kind: .toolQueued,
                summary: "\(diffCall.name) queued",
                payloadJSON: diffCallJSON
            ))
            thread.updatedAt = Date()
            await onProgress?(thread)

            thread.events.append(.init(kind: .toolRunning, summary: "\(diffCall.name) running"))
            thread.updatedAt = Date()
            await onProgress?(thread)

            try Task.checkCancellation()
            let diffResult = await toolExecutionOverride?(diffCall, workspaceRoot) ?? router.execute(diffCall)
            try Task.checkCancellation()
            let diffResultJSON = (try? JSONHelpers.encodePretty(diffResult)) ?? "{}"
            thread.events.append(.init(
                kind: diffResult.ok ? .toolCompleted : .toolFailed,
                summary: diffResult.ok ? "\(diffCall.name) completed" : "\(diffCall.name) failed",
                payloadJSON: diffResultJSON
            ))
            patchReviewResult = diffResult
            toolResults.append(diffResult)
        }
        thread.updatedAt = Date()
        return .completed(ToolStepCompletion(
            call: call,
            result: result,
            followUpReviewResult: patchReviewResult,
            toolResults: toolResults
        ))
    }

    private func appendToolFeedback(_ completion: ToolStepCompletion, to thread: inout ChatThread) {
        let feedback = AgentToolFeedback(
            toolCall: completion.call,
            result: completion.result,
            followUpResult: completion.followUpReviewResult
        )
        let content = (try? JSONHelpers.encodePretty(feedback)) ?? "{}"
        thread.messages.append(.init(role: .tool, content: content))
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
