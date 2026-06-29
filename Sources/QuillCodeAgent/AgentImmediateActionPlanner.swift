import Foundation
import QuillCodeCore
import QuillCodeTools

enum AgentImmediateActionPlanner {
    static func action(for userMessage: String, tools: [ToolDefinition]) -> AgentAction? {
        let request = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return nil }

        let lower = request.lowercased()

        if let command = AgentShellCommandRecovery.explicitCommand(from: request),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell(command)
        }

        if lower.contains("whoami"),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell("whoami")
        }

        if isOpenClawAvailabilityRequest(lower),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell("command -v openclaw || which openclaw || echo 'not found'")
        }

        if let downloadCommand = MockLLMClient.downloadCommand(from: request, lowercasedRequest: lower),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell(downloadCommand)
        }

        if isDiskUsageRequest(lower),
           hasTool(ToolDefinition.shellRun.name, in: tools) {
            return shell("df -h / /Quill 2>/dev/null || df -h /")
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
