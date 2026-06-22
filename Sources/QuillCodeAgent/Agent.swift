import Foundation
import QuillComputerUseKit
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

public enum AgentActionStreamCollector {
    public static func collectText(from stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var text = ""
        for try await chunk in stream {
            try Task.checkCancellation()
            text.append(chunk)
        }
        return text
    }

    public static func collect(
        from stream: AsyncThrowingStream<String, Error>,
        emptyError: @autoclosure () -> any Error
    ) async throws -> AgentAction {
        let text = try await collectText(from: stream)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw emptyError()
        }
        return try AgentActionJSONParser.parse(trimmed)
    }
}

public enum AgentActionStreamPreview {
    public static func visibleAssistantText(from rawActionText: String) -> String? {
        guard partialJSONStringValue(for: "type", in: rawActionText) == "say" else {
            return nil
        }
        return partialJSONStringValue(for: "text", in: rawActionText)
    }

    private static func partialJSONStringValue(for key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\"\(key)\""),
              let colonIndex = text[keyRange.upperBound...].firstIndex(of: ":")
        else {
            return nil
        }

        var index = text.index(after: colonIndex)
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "\"" else {
            return nil
        }

        index = text.index(after: index)
        var value = ""
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                return value
            }
            if character == "\\" {
                let decoded = decodeEscape(in: text, after: index)
                value.append(decoded.character)
                index = decoded.nextIndex
            } else {
                value.append(character)
                index = text.index(after: index)
            }
        }
        return value
    }

    private static func decodeEscape(in text: String, after slashIndex: String.Index) -> (character: Character, nextIndex: String.Index) {
        let escapeIndex = text.index(after: slashIndex)
        guard escapeIndex < text.endIndex else {
            return ("\\", escapeIndex)
        }

        let nextIndex = text.index(after: escapeIndex)
        switch text[escapeIndex] {
        case "\"":
            return ("\"", nextIndex)
        case "\\":
            return ("\\", nextIndex)
        case "/":
            return ("/", nextIndex)
        case "b":
            return ("\u{08}", nextIndex)
        case "f":
            return ("\u{0C}", nextIndex)
        case "n":
            return ("\n", nextIndex)
        case "r":
            return ("\r", nextIndex)
        case "t":
            return ("\t", nextIndex)
        case "u":
            return decodeUnicodeEscape(in: text, after: escapeIndex)
        default:
            return (text[escapeIndex], nextIndex)
        }
    }

    private static func decodeUnicodeEscape(in text: String, after unicodeMarkerIndex: String.Index) -> (character: Character, nextIndex: String.Index) {
        var index = text.index(after: unicodeMarkerIndex)
        var scalarText = ""
        for _ in 0..<4 {
            guard index < text.endIndex else {
                return ("u", index)
            }
            scalarText.append(text[index])
            index = text.index(after: index)
        }
        guard let value = UInt32(scalarText, radix: 16),
              let scalar = UnicodeScalar(value)
        else {
            return ("u", index)
        }
        return (Character(scalar), index)
    }
}

public struct MockLLMClient: LLMClient {
    public init() {}

    public func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        if let lastToolOutput = thread.messages.last(where: { $0.role == .tool })?.content,
           let feedback = try? JSONHelpers.decode(AgentToolFeedback.self, from: lastToolOutput) {
            return .say(AgentRunner.finalAnswer(
                for: feedback.toolCall,
                result: feedback.result,
                followUpReviewResult: feedback.followUpResult
            ))
        }

        let request = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = request.lowercased()

        if let command = Self.extractExplicitRunCommand(from: request), !command.isEmpty {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": command])
            ))
        }

        if let memory = Self.extractMemoryContent(from: request),
           tools.contains(where: { $0.name == ToolDefinition.memoryRemember.name }) {
            return .tool(.init(
                name: ToolDefinition.memoryRemember.name,
                argumentsJSON: ToolArguments.json(["content": memory])
            ))
        }

        if lower.contains("plan"),
           tools.contains(where: { $0.name == ToolDefinition.planUpdate.name }) {
            let update = AgentPlanUpdate(
                explanation: "Model-authored plan for the current request.",
                plan: [
                    AgentPlanItem(step: "Inspect current state", status: .completed),
                    AgentPlanItem(step: "Implement requested change", status: .inProgress),
                    AgentPlanItem(step: "Validate and summarize", status: .pending)
                ]
            )
            return .tool(.init(
                name: ToolDefinition.planUpdate.name,
                argumentsJSON: try JSONHelpers.encodePretty(update)
            ))
        }

        if lower.contains("whoami") {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "whoami"])
            ))
        }

        if lower.contains("openclaw") {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "command -v openclaw || which openclaw || echo 'not found'"
                ])
            ))
        }

        if Self.isBrowserInspectionRequest(lower), tools.contains(where: { $0.name == ToolDefinition.browserInspect.name }) {
            return .tool(.init(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"))
        }

        if lower.contains("disk") || lower.contains("storage") || lower.contains("how much hd") {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "df -h / /Quill 2>/dev/null || df -h /"
                ])
            ))
        }

        if (lower.contains("make") || lower.contains("create") || lower.contains("write")),
           lower.contains("file") {
            let content = lower.contains("hello world") ? "hello world\n" : "\(request)\n"
            if tools.contains(where: { $0.name == ToolDefinition.fileWrite.name }) {
                return .tool(.init(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "hello.txt",
                        "content": content
                    ])
                ))
            }
            if tools.contains(where: { $0.name == ToolDefinition.shellRun.name }) {
                let command = "printf %s \(Self.shellSingleQuoted(content)) > hello.txt"
                return .tool(.init(
                    name: ToolDefinition.shellRun.name,
                    argumentsJSON: ToolArguments.json(["cmd": command])
                ))
            }
            return .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "hello.txt",
                    "content": content
                ])
            ))
        }

        if lower.contains("git status") {
            return .tool(.init(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}"))
        }

        if lower.contains("git diff") {
            return .tool(.init(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"))
        }

        if Self.isPullRequestRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestCreate.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestArguments(from: request))
            ))
        }

        if lower.contains("commit") {
            return .tool(.init(
                name: ToolDefinition.gitCommit.name,
                argumentsJSON: ToolArguments.json([
                    "message": Self.extractCommitMessage(from: request) ?? "QuillCode changes"
                ])
            ))
        }

        if lower.contains("push") || lower.contains("publish branch") {
            return .tool(.init(
                name: ToolDefinition.gitPush.name,
                argumentsJSON: ToolArguments.json(Self.extractPushArguments(from: request))
            ))
        }

        return .say("I can inspect and edit this project, run shell commands, review git diffs, and use Computer Use as the platform backends come online.")
    }

    static func extractExplicitRunCommand(from request: String) -> String? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("run ") else { return nil }
        if let first = trimmed.firstIndex(of: "`"),
           let last = trimmed[trimmed.index(after: first)...].lastIndex(of: "`"),
           first < last {
            return String(trimmed[trimmed.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractMemoryContent(from request: String) -> String? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let markers = [
            "remember that ",
            "remember to ",
            "remember ",
            "please remember that ",
            "please remember to ",
            "please remember ",
            "memorize that ",
            "memorize "
        ]
        guard let marker = markers.first(where: { lower.hasPrefix($0) }) else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: marker.count)
        let content = String(trimmed[start...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    static func extractCommitMessage(from request: String) -> String? {
        if let first = request.firstIndex(of: "`"),
           let last = request[request.index(after: first)...].lastIndex(of: "`"),
           first < last {
            let quoted = String(request[request.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return quoted.isEmpty ? nil : quoted
        }

        let lower = request.lowercased()
        guard let range = lower.range(of: "message") else { return nil }
        var message = String(request[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix(":") {
            message.removeFirst()
            message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        message = message.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return message.isEmpty ? nil : message
    }

    static func extractPushArguments(from request: String) -> [String: String] {
        let tokens = request
            .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" && $0 != "_" && $0 != "." }
            .map(String.init)
        var arguments: [String: String] = [:]
        if let remoteIndex = tokens.firstIndex(where: { $0.lowercased() == "remote" }),
           tokens.indices.contains(tokens.index(after: remoteIndex)) {
            arguments["remote"] = tokens[tokens.index(after: remoteIndex)]
        }
        if let branchIndex = tokens.firstIndex(where: { $0.lowercased() == "branch" }),
           tokens.indices.contains(tokens.index(after: branchIndex)) {
            arguments["branch"] = tokens[tokens.index(after: branchIndex)]
        }
        return arguments
    }

    static func isPullRequestRequest(_ lowercasedRequest: String) -> Bool {
        if lowercasedRequest.contains("pull request") {
            return true
        }
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return tokens.contains("pr")
            && (tokens.contains("create") || tokens.contains("open") || tokens.contains("submit"))
    }

    static func isBrowserInspectionRequest(_ lowercasedRequest: String) -> Bool {
        let browserTerms = lowercasedRequest.contains("browser")
            || lowercasedRequest.contains("page")
            || lowercasedRequest.contains("preview")
            || lowercasedRequest.contains("localhost")
        let inspectionTerms = lowercasedRequest.contains("inspect")
            || lowercasedRequest.contains("look at")
            || lowercasedRequest.contains("what is on")
            || lowercasedRequest.contains("summarize")
            || lowercasedRequest.contains("snapshot")
        return browserTerms && inspectionTerms
    }

    static func extractPullRequestArguments(from request: String) -> [String: String] {
        var arguments: [String: String] = [:]
        arguments["title"] = extractPullRequestTitle(from: request) ?? "QuillCode changes"

        let tokens = request
            .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" && $0 != "_" && $0 != "." }
            .map(String.init)
        if let baseIndex = tokens.firstIndex(where: { $0.lowercased() == "base" }),
           tokens.indices.contains(tokens.index(after: baseIndex)) {
            arguments["base"] = tokens[tokens.index(after: baseIndex)]
        }
        if let headIndex = tokens.firstIndex(where: { $0.lowercased() == "head" }),
           tokens.indices.contains(tokens.index(after: headIndex)) {
            arguments["head"] = tokens[tokens.index(after: headIndex)]
        }
        return arguments
    }

    static func extractPullRequestTitle(from request: String) -> String? {
        if let first = request.firstIndex(of: "`"),
           let last = request[request.index(after: first)...].lastIndex(of: "`"),
           first < last {
            let quoted = String(request[request.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return quoted.isEmpty ? nil : quoted
        }

        let lower = request.lowercased()
        for marker in [" titled ", " title "] {
            guard let range = lower.range(of: marker) else { continue }
            var title = String(request[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if title.hasPrefix(":") {
                title.removeFirst()
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            title = trimTrailingPullRequestClauses(from: title)
            return title.isEmpty ? nil : title
        }
        return nil
    }

    private static func trimTrailingPullRequestClauses(from title: String) -> String {
        let lower = title.lowercased()
        let markers = [" base ", " head "]
        let end = markers
            .compactMap { lower.range(of: $0)?.lowerBound }
            .min() ?? title.endIndex
        return String(title[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
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
        var rawActionText = ""
        var lastVisibleText = ""
        for try await chunk in stream {
            try Task.checkCancellation()
            rawActionText.append(chunk)
            guard let visibleText = AgentActionStreamPreview.visibleAssistantText(from: rawActionText),
                  !visibleText.isEmpty,
                  visibleText != lastVisibleText
            else {
                continue
            }
            lastVisibleText = visibleText
            publishAssistantDraft(visibleText, in: &thread)
            await onProgress?(thread)
        }

        let trimmed = rawActionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.emptyStreamingResponse
        }
        return try AgentActionJSONParser.parse(trimmed)
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
        if !result.ok {
            let details = [result.error, result.stderr.trimmedNonEmpty]
                .compactMap { $0 }
                .joined(separator: "\n")
            if details.isEmpty {
                return "Command failed."
            }
            return "Command failed:\n\(Self.truncated(details))"
        }

        if call.name == ToolDefinition.fileWrite.name {
            if let path = Self.argument("path", in: call) {
                return "Wrote `\(path)`."
            }
            if let path = result.artifacts.first {
                return "Wrote `\(path)`."
            }
            return "Wrote the file."
        }

        if call.name == ToolDefinition.applyPatch.name {
            if let followUpReviewResult, !followUpReviewResult.ok {
                let details = [followUpReviewResult.error, followUpReviewResult.stderr.trimmedNonEmpty]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                if details.isEmpty {
                    return "Patch applied, but I could not refresh the review diff."
                }
                return "Patch applied, but I could not refresh the review diff:\n\(Self.truncated(details))"
            }
            return followUpReviewResult == nil
                ? "Patch applied."
                : "Patch applied. Review the resulting diff below."
        }

        if call.name == ToolDefinition.planUpdate.name {
            return "Updated the task plan."
        }

        if call.name == ToolDefinition.memoryRemember.name {
            if let output = try? JSONHelpers.decode(MemoryRememberToolOutput.self, from: result.stdout) {
                return "Saved memory: \(output.title). It will be included as background context in future turns."
            }
            return "Saved memory."
        }

        if call.name == ToolDefinition.shellRun.name,
           let command = Self.argument("cmd", in: call) {
            if let answer = shellAnswer(command: command, result: result) {
                return answer
            }
        }

        if call.name == ToolDefinition.browserInspect.name,
           let inspection = try? JSONHelpers.decode(BrowserInspectionToolOutput.self, from: result.stdout) {
            return browserInspectionAnswer(inspection)
        }

        if call.name == ToolDefinition.mcpReadResource.name {
            let output = result.stdout.trimmedNonEmpty
            return output.map { "MCP resource contents:\n\(Self.truncated($0))" }
                ?? "MCP resource read completed with no text content."
        }

        if call.name == ToolDefinition.mcpGetPrompt.name {
            let output = result.stdout.trimmedNonEmpty
            return output.map { "MCP prompt:\n\(Self.truncated($0))" }
                ?? "MCP prompt loaded."
        }

        if call.name == ToolDefinition.computerScreenshot.name,
           let screenshot = try? JSONHelpers.decode(ComputerScreenshotToolOutput.self, from: result.stdout) {
            return "Captured a screenshot (\(screenshot.width) x \(screenshot.height))."
        }

        if ToolDefinition.computerUseDefinitions.contains(where: { $0.name == call.name }) {
            let output = result.stdout.trimmedNonEmpty
            return output.map { "Computer Use completed: \($0)" } ?? "Computer Use action completed."
        }

        let output = [result.stdout, result.stderr]
            .compactMap(\.trimmedNonEmpty)
            .joined(separator: "\n")
        if output.isEmpty {
            return "Done."
        }
        return "Output:\n\(Self.truncated(output))"
    }

    private static func browserInspectionAnswer(_ inspection: BrowserInspectionToolOutput) -> String {
        var lines = [
            "Inspected `\(inspection.title)` at \(inspection.url).",
            "Inspection depth: \(inspection.inspectionDepth.label).",
            inspection.summary
        ]
        if !inspection.outline.isEmpty {
            lines.append("Outline: \(inspection.outline.prefix(5).joined(separator: "; ")).")
        }
        if let textSnippet = inspection.textSnippet?.trimmedNonEmpty {
            lines.append("Text: \(Self.truncated(textSnippet, maxCharacters: 320))")
        }
        if !inspection.comments.isEmpty {
            lines.append("Browser comments: \(inspection.comments.map(\.text).prefix(3).joined(separator: "; ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func shellAnswer(command: String, result: ToolResult) -> String? {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedCommand.lowercased()
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = stdout.isEmpty ? stderr : stdout

        if lower == "whoami" {
            guard !stdout.isEmpty else { return "The command ran, but did not print a user name." }
            return "You are `\(Self.firstLine(stdout))` in this workspace."
        }

        if lower.contains("openclaw") && (lower.contains("command -v") || lower.contains("which ")) {
            let firstLine = Self.firstLine(output)
            if firstLine.isEmpty || firstLine == "not found" {
                return "openclaw is not installed or is not on PATH."
            }
            return "openclaw is installed at `\(firstLine)`."
        }

        if lower.hasPrefix("df ") || lower.contains(" df ") || lower.contains("df -h") {
            guard !output.isEmpty else { return "Disk usage command completed with no output." }
            return "Disk usage:\n\(Self.truncated(output))"
        }

        return nil
    }

    private static func argument(_ key: String, in call: ToolCall) -> String? {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func truncated(_ text: String, maxCharacters: Int = 2_000) -> String {
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<end])\n\n[truncated in chat; full output is in the tool card]"
    }

    static func title(from userMessage: String) -> String {
        let words = userMessage.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "New chat" : words
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
