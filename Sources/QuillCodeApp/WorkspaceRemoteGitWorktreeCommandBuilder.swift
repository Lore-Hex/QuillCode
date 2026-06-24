import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteGitWorktreePlan: Sendable, Hashable {
    var command: String
    var artifacts: [String]
}

enum WorkspaceRemoteGitWorktreeCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitWorktreeList.name,
        ToolDefinition.gitWorktreeCreate.name,
        ToolDefinition.gitWorktreeRemove.name
    ]

    static func plan(
        for call: ToolCall,
        arguments args: ToolArguments,
        connection: ProjectConnection
    ) throws -> WorkspaceRemoteGitWorktreePlan {
        switch call.name {
        case ToolDefinition.gitWorktreeList.name:
            return WorkspaceRemoteGitWorktreePlan(command: "git worktree list --porcelain", artifacts: [])
        case ToolDefinition.gitWorktreeCreate.name:
            let worktreePath = try WorkspaceRemoteProjectPath.worktreePath(
                try args.requiredString("path"),
                connection: connection
            )
            return WorkspaceRemoteGitWorktreePlan(
                command: try createCommand(
                    worktreePath: worktreePath,
                    branch: args.string("branch"),
                    base: args.string("base")
                ),
                artifacts: [
                    WorkspaceRemoteProjectPath.artifactPath(
                        connection: connection,
                        absolutePath: worktreePath
                    )
                ]
            )
        case ToolDefinition.gitWorktreeRemove.name:
            let worktreePath = try WorkspaceRemoteProjectPath.worktreePath(
                try args.requiredString("path"),
                connection: connection
            )
            return WorkspaceRemoteGitWorktreePlan(
                command: removeCommand(
                    worktreePath: worktreePath,
                    force: args.bool("force") ?? false
                ),
                artifacts: []
            )
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    private static func createCommand(
        worktreePath: String,
        branch: String?,
        base: String?
    ) throws -> String {
        var arguments = ["git", "worktree", "add"]
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            arguments += ["-b", try GitInputValidator.safeName(branch)]
        }
        arguments.append(worktreePath)
        if let base = GitInputValidator.trimmedNonEmpty(base) {
            arguments.append(try GitInputValidator.safeName(base))
        }
        return shellCommand(arguments)
    }

    private static func removeCommand(worktreePath: String, force: Bool) -> String {
        let forceFlag = force ? " --force" : ""
        return [
            "worktree=\(WorkspaceTerminalSessionAdapter.shellSingleQuoted(worktreePath))",
            "git worktree list --porcelain | grep -F -x -- \"worktree $worktree\" >/dev/null || { printf 'Git worktree is not registered: %s\\n' \"$worktree\" >&2; exit 1; }",
            "git worktree remove\(forceFlag) -- \"$worktree\""
        ].joined(separator: " && ")
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(WorkspaceTerminalSessionAdapter.shellSingleQuoted).joined(separator: " ")
    }
}
