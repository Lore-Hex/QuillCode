import Foundation
import QuillCodeCore
import QuillCodeTools

public struct MockLLMClient: LLMClient {
    public init() {}

    public func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        if let reviewAction = MockCodeReviewPlanner.action(
            thread: thread,
            prompt: userMessage,
            tools: tools
        ) {
            return reviewAction
        }
        if thread.messages.last?.role == .tool,
           let lastToolOutput = thread.messages.last?.content,
           let feedback = try? JSONHelpers.decode(AgentToolFeedback.self, from: lastToolOutput) {
            return .say(AgentRunner.finalAnswer(
                for: feedback.toolCall,
                result: feedback.result,
                followUpReviewResult: feedback.followUpResult
            ))
        }

        let rawRequest = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if AgentActionIntentSegments.isOnlyNegatedActionRequest(rawRequest) {
            return .say("Okay, I won't take that action.")
        }
        let actionableSegments = AgentActionIntentSegments.actionableSegments(in: rawRequest)
        let request = actionableSegments.first(where: AgentActionIntentSegments.containsActionIntent)
            ?? actionableSegments.first
            ?? rawRequest
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

        if lower.contains("handoff"),
           tools.contains(where: { $0.name == ToolDefinition.handoffUpdate.name }) {
            let update = AgentHandoffUpdate(
                summary: "Current task state is ready for continuation.",
                nextSteps: ["Review the latest tool output", "Continue from the Activity pane"]
            )
            return .tool(.init(
                name: ToolDefinition.handoffUpdate.name,
                argumentsJSON: try JSONHelpers.encodePretty(update)
            ))
        }

        if Self.isSubagentRunRequest(lower),
           tools.contains(where: { $0.name == ToolDefinition.subagentsRun.name }) {
            return .tool(.init(
                name: ToolDefinition.subagentsRun.name,
                argumentsJSON: ToolArguments.json([
                    "objective": "Coordinate parallel review of the current task.",
                    "workers": [
                        [
                            "name": "Explorer",
                            "role": "Map the code and identify relevant files."
                        ],
                        [
                            "name": "Verifier",
                            "role": "Run focused validation and report failures."
                        ]
                    ]
                ])
            ))
        }

        if let pullRequestToolCall = MockPullRequestIntentPlanner.toolCall(for: request, lowercasedRequest: lower) {
            return .tool(pullRequestToolCall)
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

        if let downloadCommand = AgentDownloadRequestParser.shellCommand(from: request),
           tools.contains(where: { $0.name == ToolDefinition.shellRun.name }) {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": downloadCommand])
            ))
        }

        if let browserTarget = MockBrowserIntentPlanner.openTarget(from: request, lowercasedRequest: lower),
           tools.contains(where: { $0.name == ToolDefinition.browserOpen.name }) {
            return .tool(.init(
                name: ToolDefinition.browserOpen.name,
                argumentsJSON: ToolArguments.json(["url": browserTarget])
            ))
        }

        if MockBrowserIntentPlanner.isInspectionRequest(lower),
           tools.contains(where: { $0.name == ToolDefinition.browserInspect.name }) {
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

        if let fileWrite = AgentFileWriteRequestParser.request(from: request) {
            if tools.contains(where: { $0.name == ToolDefinition.fileWrite.name }) {
                return .tool(.init(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json(fileWrite.arguments)
                ))
            }
            if tools.contains(where: { $0.name == ToolDefinition.shellRun.name }) {
                let parent = Self.parentDirectory(for: fileWrite.path)
                let command = [
                    "mkdir -p \(Self.shellSingleQuoted(parent))",
                    "printf %s \(Self.shellSingleQuoted(fileWrite.content)) > \(Self.shellSingleQuoted(fileWrite.path))"
                ].joined(separator: " && ")
                return .tool(.init(
                    name: ToolDefinition.shellRun.name,
                    argumentsJSON: ToolArguments.json(["cmd": command])
                ))
            }
            return .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json(fileWrite.arguments)
            ))
        }

        if let fileReadPath = AgentFileReadRequestParser.path(from: request),
           tools.contains(where: { $0.name == ToolDefinition.fileRead.name }) {
            return .tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": fileReadPath])
            ))
        }

        if let fileList = AgentFileListRequestParser.request(from: request),
           tools.contains(where: { $0.name == ToolDefinition.fileList.name }) {
            return .tool(.init(
                name: ToolDefinition.fileList.name,
                argumentsJSON: ToolArguments.json(fileList.arguments)
            ))
        }

        if let fileSearch = AgentFileSearchRequestParser.request(from: request),
           tools.contains(where: { $0.name == ToolDefinition.fileSearch.name }) {
            return .tool(.init(
                name: ToolDefinition.fileSearch.name,
                argumentsJSON: ToolArguments.json(fileSearch.arguments)
            ))
        }

        if let gitReadCall = AgentGitReadRequestParser.toolCall(for: request, tools: tools) {
            return .tool(gitReadCall)
        }

        if lower.contains("git fetch") || lower.contains("fetch latest") || lower.contains("fetch remote") {
            return .tool(.init(
                name: ToolDefinition.gitFetch.name,
                argumentsJSON: ToolArguments.json(Self.extractFetchArguments(from: request))
            ))
        }

        if lower.contains("git pull")
            || lower.contains("pull latest")
            || lower.contains("pull from")
            || lower.contains("sync branch")
            || lower.contains("sync latest") {
            return .tool(.init(
                name: ToolDefinition.gitPull.name,
                argumentsJSON: ToolArguments.json(Self.extractPullArguments(from: request))
            ))
        }

        if let branchArguments = AgentGitBranchMutationRequestParser.arguments(from: request),
           tools.contains(where: { $0.name == ToolDefinition.gitBranchSwitch.name }) {
            return .tool(.init(
                name: ToolDefinition.gitBranchSwitch.name,
                argumentsJSON: ToolArguments.json(branchArguments)
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

    private static func isSubagentRunRequest(_ lowercasedRequest: String) -> Bool {
        let mentionsDelegation = lowercasedRequest.contains("subagent")
            || lowercasedRequest.contains("parallel agent")
        let actionVerbs = ["use", "delegate", "ask", "have", "spawn", "run", "launch", "start", "progress"]
        return mentionsDelegation && actionVerbs.contains(where: lowercasedRequest.contains)
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

    static func extractFetchArguments(from request: String) -> [String: Any] {
        let tokens = gitSyncTokens(from: request)
        var arguments: [String: Any] = [:]
        if tokens.contains(where: { $0.lowercased() == "--prune" || $0.lowercased() == "prune" }) {
            arguments["prune"] = true
        }
        if let remote = token(afterAnyOf: ["remote", "from"], in: tokens) {
            arguments["remote"] = remote
        }
        return arguments
    }

    static func extractPullArguments(from request: String) -> [String: Any] {
        let tokens = gitSyncTokens(from: request)
        var arguments: [String: Any] = ["ffOnly": true]
        if tokens.contains(where: { $0.lowercased() == "--no-ff-only" || $0.lowercased() == "--merge" }) {
            arguments["ffOnly"] = false
        }
        if let remote = token(afterAnyOf: ["remote", "from"], in: tokens) {
            arguments["remote"] = remote
        }
        if let branch = token(afterAnyOf: ["branch"], in: tokens) {
            arguments["branch"] = branch
        }
        return arguments
    }

    private static func gitSyncTokens(from request: String) -> [String] {
        request
            .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" && $0 != "_" && $0 != "." }
            .map(String.init)
    }

    private static func token(afterAnyOf markers: [String], in tokens: [String]) -> String? {
        let markers = Set(markers.map { $0.lowercased() })
        for index in tokens.indices where markers.contains(tokens[index].lowercased()) {
            let nextIndex = tokens.index(after: index)
            guard tokens.indices.contains(nextIndex), !tokens[nextIndex].hasPrefix("-") else {
                continue
            }
            return tokens[nextIndex]
        }
        return nil
    }

    private static func parentDirectory(for path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        let parent = path[..<slash]
        return parent.isEmpty ? "." : String(parent)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
