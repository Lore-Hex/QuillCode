import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceWorktreeToolCallPlanner {
    static func list() -> ToolCall {
        ToolCall(name: ToolDefinition.gitWorktreeList.name, argumentsJSON: "{}")
    }

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
        if request.managed {
            arguments["managed"] = true
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

    static func open(_ request: WorkspaceWorktreeOpenRequest) -> ToolCall {
        ToolCall(
            name: ToolDefinition.gitWorktreeOpen.name,
            argumentsJSON: ToolArguments.json([
                "path": request.path.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        )
    }

    static func handoff(destination: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.gitWorktreeHandoff.name,
            argumentsJSON: ToolArguments.json(["destination": destination])
        )
    }

    static func createBranch(_ request: WorkspaceWorktreeCreateBranchRequest) -> ToolCall {
        ToolCall(
            name: ToolDefinition.gitWorktreeCreateBranch.name,
            argumentsJSON: ToolArguments.json([
                "branch": request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        )
    }

    static func prune(_ request: WorkspaceWorktreePruneRequest) -> ToolCall {
        ToolCall(
            name: ToolDefinition.gitWorktreePrune.name,
            argumentsJSON: ToolArguments.json([
                "dryRun": request.dryRun,
                "verbose": request.verbose
            ])
        )
    }
}
