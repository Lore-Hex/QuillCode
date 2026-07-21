import Foundation
import QuillCodeCore
import QuillCodeTools

enum AgentImmediateActionPlanner {
    static func action(for userMessage: String, tools: [ToolDefinition]) -> AgentAction? {
        let request = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return nil }
        // The preflight exists for TERSE single commands ("run whoami", "list files in src") where
        // skipping a model round-trip is pure win. A multi-step task prompt is model territory:
        // parsing one clause out of "(1) clone … (2) list the repository's top-level directory …"
        // hijacked the whole run with `host.file.list {"path": "order"}` (the word after "in" in
        // "do these in order") and the task never reached the model. Enumerated steps → no preflight.
        guard !isMultiStepTaskPrompt(request) else { return nil }

        for segment in AgentActionIntentSegments.actionableSegments(in: request) {
            if let action = action(forSegment: segment, tools: tools) {
                return action
            }
        }
        return nil
    }

    /// Whether the message reads as an enumerated multi-step task: two or more step markers in the
    /// `(1) …`, `1. …`, or `1) …` styles. Deliberately narrow — a single "(1)" citation or an
    /// ordinary short command never matches.
    static func isMultiStepTaskPrompt(_ request: String) -> Bool {
        enumeratedStepMarkerCount(in: request) >= 2
    }

    private static func enumeratedStepMarkerCount(in request: String) -> Int {
        let patterns = [
            #"\(\d{1,2}\)\s"#,       // (1) clone …
            #"(?m)^\s*\d{1,2}[.)]\s"# // 1. clone … / 2) list …
        ]
        var count = 0
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(request.startIndex..<request.endIndex, in: request)
            count += regex.numberOfMatches(in: request, range: range)
        }
        return count
    }

    private static func action(forSegment request: String, tools: [ToolDefinition]) -> AgentAction? {
        let lower = request.lowercased()

        if let gitReadCall = AgentGitReadRequestParser.toolCall(for: request, tools: tools) {
            return .tool(gitReadCall)
        }

        if let gitBranchMutationCall = AgentGitBranchMutationRequestParser.toolCall(for: request, tools: tools) {
            return .tool(gitBranchMutationCall)
        }

        if let workspaceDiagnostic = AgentWorkspaceDiagnosticRequestParser.toolCall(for: request, tools: tools) {
            return .tool(workspaceDiagnostic)
        }

        if lower.contains("whoami"),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell("whoami")
        }

        if isOpenClawAvailabilityRequest(lower),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell("command -v openclaw || which openclaw || echo 'not found'")
        }

        if let downloadCommand = AgentDownloadRequestParser.shellCommand(from: request),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell(downloadCommand)
        }

        if isDiskUsageRequest(lower),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell("df -h / /Quill 2>/dev/null || df -h /")
        }

        if let command = AgentShellCommandRecovery.explicitCommand(from: request),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell(command)
        }

        if let fileWrite = AgentFileWriteRequestParser.request(from: request),
           hasTool(ToolDefinition.fileWrite.name, in: tools) {
            return .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json(fileWrite.arguments)
            ))
        }

        if let fileReadPath = AgentFileReadRequestParser.path(from: request),
           hasTool(ToolDefinition.fileRead.name, in: tools) {
            return .tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": fileReadPath])
            ))
        }

        if let fileList = AgentFileListRequestParser.request(from: request),
           hasTool(ToolDefinition.fileList.name, in: tools) {
            return .tool(.init(
                name: ToolDefinition.fileList.name,
                argumentsJSON: ToolArguments.json(fileList.arguments)
            ))
        }

        if let fileSearch = AgentFileSearchRequestParser.request(from: request),
           hasTool(ToolDefinition.fileSearch.name, in: tools) {
            return .tool(.init(
                name: ToolDefinition.fileSearch.name,
                argumentsJSON: ToolArguments.json(fileSearch.arguments)
            ))
        }

        return nil
    }

    private static func shell(_ command: String) -> AgentAction {
        .tool(.init(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": command])
        ))
    }

    private static func hasTool(_ name: String, in tools: [ToolDefinition]) -> Bool {
        tools.contains { $0.name == name }
    }

    private static func isOpenClawAvailabilityRequest(_ lower: String) -> Bool {
        guard lower.contains("openclaw") else { return false }
        return [
            "do you have",
            "is openclaw installed",
            "openclaw installed",
            "have openclaw",
            "check openclaw",
            "find openclaw",
            "which openclaw",
            "command -v openclaw"
        ].contains { lower.contains($0) }
    }

    private static func isDiskUsageRequest(_ lower: String) -> Bool {
        lower.contains("how much hd")
            || lower.contains("disk usage")
            || lower.contains("storage usage")
            || (lower.contains("how much") && (lower.contains("disk") || lower.contains("storage")))
    }

}
