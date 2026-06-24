import Foundation
import QuillCodeCore
import QuillCodeTools

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

        if let pullRequestToolCall = MockPullRequestIntentPlanner.toolCall(for: request, lowercasedRequest: lower) {
            return .tool(pullRequestToolCall)
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

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
