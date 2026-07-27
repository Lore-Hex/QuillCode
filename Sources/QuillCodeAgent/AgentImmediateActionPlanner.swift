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

    /// Whether the message reads as a multi-step task rather than a terse command. Four signals,
    /// each learned from a live hijack:
    /// - two or more enumerated step markers (`(1) …`, `1. …`, `1) …`);
    /// - two or more " then " connectors ("clone X, then list Y, then read Z");
    /// - an " and <action verb>" continuation ("Read notes.md AND TURN it into a PRD…" — the
    ///   preflight answered the read and ended the run with the task untouched);
    /// - sheer length: nobody types a 200-character message to run one terse command, and every
    ///   hijacked prompt was long. The cap ends the class the marker heuristics can't enumerate.
    /// A single "(1)" citation, "run tests then commit", or "list files and folders" never matches.
    static func isMultiStepTaskPrompt(_ request: String) -> Bool {
        if request.count > terseCommandCharacterLimit { return true }
        if enumeratedStepMarkerCount(in: request) >= 2 { return true }
        let lower = request.lowercased()
        if thenConnectorCount(in: lower) >= 2 { return true }
        return containsAndActionContinuation(in: lower)
    }

    /// Terse one-shot commands ("run whoami", "list files in src", "download https://…") fit well
    /// under this; multi-clause task prompts do not.
    static let terseCommandCharacterLimit = 180

    private static func containsAndActionContinuation(in lower: String) -> Bool {
        var searchStart = lower.startIndex
        while let range = lower.range(of: " and ", range: searchStart..<lower.endIndex) {
            searchStart = range.upperBound
            let following = lower[range.upperBound...]
            let nextWord = following
                .split(whereSeparator: { !$0.isLetter })
                .first
                .map(String.init) ?? ""
            if Self.continuationActionVerbs.contains(nextWord) { return true }
        }
        return false
    }

    /// Verbs that, after " and ", signal a SECOND requested action (not a noun list like
    /// "files and folders"). Result-presentation verbs ("and report the output", "and tell me its
    /// content") are deliberately absent: they ask for the FIRST action's result, which the
    /// immediate answer already provides.
    private static let continuationActionVerbs: Set<String> = [
        "turn", "write", "create", "make", "run", "fix", "update", "summarize",
        "produce", "generate", "draft", "convert", "then", "read", "list",
        "delete", "rename", "move", "install", "build", "test", "commit", "push", "open",
    ]

    private static func thenConnectorCount(in lower: String) -> Int {
        var count = 0
        var searchStart = lower.startIndex
        while let range = lower.range(of: " then ", range: searchStart..<lower.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
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
