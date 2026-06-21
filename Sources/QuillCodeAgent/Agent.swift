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

public struct MockLLMClient: LLMClient {
    public init() {}

    public func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        let request = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = request.lowercased()

        if let command = Self.extractExplicitRunCommand(from: request), !command.isEmpty {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": command])
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
}

public struct AgentRunResult: Sendable {
    public var thread: ChatThread
    public var toolResults: [ToolResult]

    public init(thread: ChatThread, toolResults: [ToolResult]) {
        self.thread = thread
        self.toolResults = toolResults
    }
}

public typealias AgentRunProgressHandler = @Sendable (ChatThread) async -> Void

public struct AgentRunner: Sendable {
    public var llm: LLMClient
    public var safety: SafetyReviewer

    public init(
        llm: LLMClient = MockLLMClient(),
        safety: SafetyReviewer = AutoSafetyReviewer()
    ) {
        self.llm = llm
        self.safety = safety
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
        let tools = ToolRouter.definitions
        let action = try await llm.nextAction(thread: next, userMessage: userMessage, tools: tools)
        try Task.checkCancellation()
        switch action {
        case .say(let text):
            next.messages.append(.init(role: .assistant, content: text))
            next.events.append(.init(kind: .message, summary: text))
            next.updatedAt = Date()
            await onProgress?(next)
            return AgentRunResult(thread: next, toolResults: [])
        case .tool(let call):
            return try await runTool(
                call,
                userMessage: userMessage,
                thread: next,
                workspaceRoot: workspaceRoot,
                onProgress: onProgress
            )
        }
    }

    private func runTool(
        _ call: ToolCall,
        userMessage: String,
        thread: ChatThread,
        workspaceRoot: URL,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentRunResult {
        var next = thread
        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let definition = router.definition(named: call.name)
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? call.argumentsJSON
        next.events.append(.init(
            kind: .toolQueued,
            summary: "\(call.name) queued",
            payloadJSON: callJSON
        ))
        next.updatedAt = Date()
        await onProgress?(next)

        try Task.checkCancellation()
        let review = await safety.review(.init(
            mode: next.mode,
            userMessage: userMessage,
            toolCall: call,
            toolDefinition: definition,
            recentMessages: next.messages
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
            next.events.append(.init(
                kind: .approvalRequested,
                summary: "\(review.verdict.rawValue): \(review.rationale)"
            ))
            next.messages.append(.init(role: .assistant, content: text))
            next.events.append(.init(kind: .message, summary: text))
            next.updatedAt = Date()
            await onProgress?(next)
            return AgentRunResult(thread: next, toolResults: [])
        }

        next.events.append(.init(kind: .toolRunning, summary: "\(call.name) running"))
        next.updatedAt = Date()
        await onProgress?(next)
        try Task.checkCancellation()
        let result = router.execute(call)
        try Task.checkCancellation()
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        next.events.append(.init(
            kind: result.ok ? .toolCompleted : .toolFailed,
            summary: result.ok ? "\(call.name) completed" : "\(call.name) failed",
            payloadJSON: resultJSON
        ))
        var toolResults = [result]
        var patchReviewResult: ToolResult?
        if call.name == ToolDefinition.applyPatch.name, result.ok {
            let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
            let diffCallJSON = (try? JSONHelpers.encodePretty(diffCall)) ?? diffCall.argumentsJSON
            next.events.append(.init(
                kind: .toolQueued,
                summary: "\(diffCall.name) queued",
                payloadJSON: diffCallJSON
            ))
            next.updatedAt = Date()
            await onProgress?(next)

            next.events.append(.init(kind: .toolRunning, summary: "\(diffCall.name) running"))
            next.updatedAt = Date()
            await onProgress?(next)

            try Task.checkCancellation()
            let diffResult = router.execute(diffCall)
            try Task.checkCancellation()
            let diffResultJSON = (try? JSONHelpers.encodePretty(diffResult)) ?? "{}"
            next.events.append(.init(
                kind: diffResult.ok ? .toolCompleted : .toolFailed,
                summary: diffResult.ok ? "\(diffCall.name) completed" : "\(diffCall.name) failed",
                payloadJSON: diffResultJSON
            ))
            patchReviewResult = diffResult
            toolResults.append(diffResult)
        }
        let finalAnswer = Self.finalAnswer(
            for: call,
            result: result,
            followUpReviewResult: patchReviewResult
        )
        next.messages.append(.init(role: .assistant, content: finalAnswer))
        next.events.append(.init(kind: .message, summary: finalAnswer))
        next.updatedAt = Date()
        await onProgress?(next)
        return AgentRunResult(thread: next, toolResults: toolResults)
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

        if call.name == ToolDefinition.shellRun.name,
           let command = Self.argument("cmd", in: call) {
            if let answer = shellAnswer(command: command, result: result) {
                return answer
            }
        }

        let output = [result.stdout, result.stderr]
            .compactMap(\.trimmedNonEmpty)
            .joined(separator: "\n")
        if output.isEmpty {
            return "Done."
        }
        return "Output:\n\(Self.truncated(output))"
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
