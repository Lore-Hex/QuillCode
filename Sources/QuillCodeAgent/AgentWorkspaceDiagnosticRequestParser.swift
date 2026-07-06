import QuillCodeCore
import QuillCodeTools

enum AgentWorkspaceDiagnosticRequestParser {
    static func toolCall(for request: String, tools: [ToolDefinition]) -> ToolCall? {
        let lower = request.lowercased()
        guard hasTool(ToolDefinition.shellRun.name, in: tools) else {
            return nil
        }

        if isCurrentDirectoryRequest(lower) {
            return shell("pwd")
        }
        return nil
    }

    private static func shell(_ command: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": command])
        )
    }

    private static func isCurrentDirectoryRequest(_ lower: String) -> Bool {
        let tokens = AgentRequestTextScanner.alphanumericWordTokens(in: lower)
        if lower.contains("current directory")
            || lower.contains("working directory")
            || lower.contains("current folder")
            || lower.contains("workspace path") {
            return true
        }
        return tokens.contains("pwd")
            || (tokens.contains("where") && tokens.contains("am") && tokens.contains("i"))
    }

    private static func hasTool(_ name: String, in tools: [ToolDefinition]) -> Bool {
        tools.contains { $0.name == name }
    }
}
