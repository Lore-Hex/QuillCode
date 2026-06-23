import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceWorktreeToolCallPlanner {
    static func create(_ request: WorkspaceWorktreeCreateRequest) -> ToolCall {
        var arguments: [String: Any] = ["path": request.path]
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = request.base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            arguments["branch"] = branch
        }
        if !base.isEmpty {
            arguments["base"] = base
        }
        return ToolCall(
            name: ToolDefinition.gitWorktreeCreate.name,
            argumentsJSON: ToolArguments.json(arguments)
        )
    }

    static func remove(_ request: WorkspaceWorktreeRemoveRequest) -> ToolCall {
        ToolCall(
            name: ToolDefinition.gitWorktreeRemove.name,
            argumentsJSON: ToolArguments.json([
                "path": request.path,
                "force": request.force
            ])
        )
    }
}
