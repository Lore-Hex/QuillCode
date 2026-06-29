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
        if isFileListingRequest(lower) {
            return shell("ls -la")
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
        let tokens = tokenizeWords(lower)
        if lower.contains("current directory")
            || lower.contains("working directory")
            || lower.contains("current folder")
            || lower.contains("workspace path") {
            return true
        }
        return tokens.contains("pwd")
            || (tokens.contains("where") && tokens.contains("am") && tokens.contains("i"))
    }

    private static func isFileListingRequest(_ lower: String) -> Bool {
        let tokens = tokenizeWords(lower)
        if lower.contains("list files")
            || lower.contains("list the files")
            || lower.contains("show files")
            || lower.contains("show the files") {
            return true
        }

        let asksForFiles = tokens.contains("files") || tokens.contains("folder") || tokens.contains("directory")
        let asksForListing = tokens.contains("list") || tokens.contains("show") || tokens.contains("what")
        let scopesWorkspace = tokens.contains("here")
            || tokens.contains("workspace")
            || tokens.contains("project")
            || tokens.contains("repo")
            || tokens.contains("directory")
            || tokens.contains("folder")

        return asksForFiles && asksForListing && scopesWorkspace
    }

    private static func tokenizeWords(_ lower: String) -> Set<String> {
        Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private static func hasTool(_ name: String, in tools: [ToolDefinition]) -> Bool {
        tools.contains { $0.name == name }
    }
}
