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
        ToolDefinition.gitWorktreeRemove.name,
        ToolDefinition.gitWorktreePrune.name
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
            return try planWithWorktreeArtifact(args: args, connection: connection) { worktreePath in
                try createCommand(
                    worktreePath: worktreePath,
                    branch: args.string("branch"),
                    base: args.string("base")
                )
            }
        case ToolDefinition.gitWorktreeOpen.name:
            return try planWithWorktreeArtifact(args: args, connection: connection, command: openCommand)
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
        case ToolDefinition.gitWorktreePrune.name:
            return WorkspaceRemoteGitWorktreePlan(
                command: pruneCommand(
                    dryRun: args.bool("dryRun") ?? false,
                    verbose: args.bool("verbose") ?? false
                ),
                artifacts: []
            )
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    private static func planWithWorktreeArtifact(
        args: ToolArguments,
        connection: ProjectConnection,
        command: (String) throws -> String
    ) throws -> WorkspaceRemoteGitWorktreePlan {
        let worktreePath = try WorkspaceRemoteProjectPath.worktreePath(
            try args.requiredString("path"),
            connection: connection
        )
        return WorkspaceRemoteGitWorktreePlan(
            command: try command(worktreePath),
            artifacts: [
                WorkspaceRemoteProjectPath.artifactPath(
                    connection: connection,
                    absolutePath: worktreePath
                )
            ]
        )
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
        return WorkspaceRemoteShellCommandFormatter.command(arguments)
    }

    private static func removeCommand(worktreePath: String, force: Bool) -> String {
        let forceFlag = force ? " --force" : ""
        return [
            "worktree=\(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(worktreePath))",
            registeredWorktreeCheckCommand(),
            "git worktree remove\(forceFlag) -- \"$worktree\""
        ].joined(separator: " && ")
    }

    private static func pruneCommand(dryRun: Bool, verbose: Bool) -> String {
        var arguments = ["git", "worktree", "prune"]
        if dryRun {
            arguments.append("--dry-run")
        }
        if verbose {
            arguments.append("--verbose")
        }
        return WorkspaceRemoteShellCommandFormatter.command(arguments)
    }

    private static func openCommand(worktreePath: String) -> String {
        [
            "worktree=\(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(worktreePath))",
            registeredWorktreeCheckCommand(),
            "printf 'worktree %s\\n' \"$worktree\""
        ].joined(separator: " && ")
    }

    private static func registeredWorktreeCheckCommand() -> String {
        let listCommand = "git worktree list --porcelain"
        return [
            "worktree_real=$(cd \"$worktree\" 2>/dev/null && pwd -P || printf '%s' \"$worktree\")",
            "\(listCommand) | \(registeredWorktreeAwkCommand()) || \(unregisteredWorktreeFailureCommand())"
        ].joined(separator: " && ")
    }

    private static func registeredWorktreeAwkCommand() -> String {
        let program = "$0 == \"worktree \" wanted || $0 == \"worktree \" wanted_real { found=1 } " +
            "END { exit found ? 0 : 1 }"
        return "awk -v wanted=\"$worktree\" -v wanted_real=\"$worktree_real\" '\(program)'"
    }

    private static func unregisteredWorktreeFailureCommand() -> String {
        "{ printf 'Git worktree is not registered: %s\\n' \"$worktree\" >&2; exit 1; }"
    }
}
