import QuillCodeCore
import QuillCodeTools

enum AgentGitReadRequestParser {
    static func toolCall(for request: String, tools: [ToolDefinition]) -> ToolCall? {
        let lower = request.lowercased()
        if isDiffRequest(lower),
           hasTool(ToolDefinition.gitDiff.name, in: tools) {
            return ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        }
        if isStatusRequest(lower),
           hasTool(ToolDefinition.gitStatus.name, in: tools) {
            return ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}")
        }
        if isBranchListRequest(lower),
           hasTool(ToolDefinition.gitBranchList.name, in: tools) {
            return ToolCall(name: ToolDefinition.gitBranchList.name, argumentsJSON: "{}")
        }
        return nil
    }

    private static func isDiffRequest(_ lower: String) -> Bool {
        let tokens = AgentRequestTextScanner.alphanumericWordTokens(in: lower)
        if lower.contains("git diff") || lower.contains("what changed") || lower.contains("what has changed") {
            return true
        }
        if lower.contains("show me the changes") || lower.contains("show changes") {
            return true
        }
        if tokens.contains("diff") && (tokens.contains("git") || tokens.contains("changes")) {
            return true
        }
        return tokens.contains("review") && tokens.contains("changes")
    }

    private static func isStatusRequest(_ lower: String) -> Bool {
        let tokens = AgentRequestTextScanner.alphanumericWordTokens(in: lower)
        if lower.contains("git status") || lower.contains("repo status") || lower.contains("repository status") {
            return true
        }
        if lower.contains("working tree status") || lower.contains("working directory status") {
            return true
        }
        return tokens.contains("status") && (tokens.contains("git") || tokens.contains("repo"))
    }

    private static func isBranchListRequest(_ lower: String) -> Bool {
        let tokens = AgentRequestTextScanner.alphanumericWordTokens(in: lower)
        if lower.contains("git branch") || lower.contains("list branches") || lower.contains("show branches") {
            return true
        }
        return tokens.contains("branches") && (tokens.contains("git") || tokens.contains("repo"))
    }

    private static func hasTool(_ name: String, in tools: [ToolDefinition]) -> Bool {
        tools.contains { $0.name == name }
    }
}
