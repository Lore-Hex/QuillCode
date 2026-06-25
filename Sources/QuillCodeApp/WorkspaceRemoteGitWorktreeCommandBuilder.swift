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
        ToolDefinition.gitWorktreeOpen.name,
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
        case ToolDefinition.gitWorktreeOpen.name:
            let worktreePath = try WorkspaceRemoteProjectPath.worktreePath(
                try args.requiredString("path"),
                connection: connection
            )
            return WorkspaceRemoteGitWorktreePlan(
                command: openCommand(worktreePath: worktreePath),
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
            registeredWorktreeCheckCommand(),
            "git worktree remove\(forceFlag) -- \"$worktree\""
        ].joined(separator: " && ")
    }

    private static func openCommand(worktreePath: String) -> String {
        [
            "worktree=\(WorkspaceTerminalSessionAdapter.shellSingleQuoted(worktreePath))",
            registeredWorktreeCheckCommand(),
            "printf 'worktree %s\\n' \"$worktree\""
        ].joined(separator: " && ")
    }

    private static func registeredWorktreeCheckCommand() -> String {
        [
            "worktree_real=$(cd \"$worktree\" 2>/dev/null && pwd -P || printf '%s' \"$worktree\")",
            "git worktree list --porcelain | awk -v wanted=\"$worktree\" -v wanted_real=\"$worktree_real\" '$0 == \"worktree \" wanted || $0 == \"worktree \" wanted_real { found=1 } END { exit found ? 0 : 1 }' || { printf 'Git worktree is not registered: %s\\n' \"$worktree\" >&2; exit 1; }"
        ].joined(separator: " && ")
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(WorkspaceTerminalSessionAdapter.shellSingleQuoted).joined(separator: " ")
    }
}
