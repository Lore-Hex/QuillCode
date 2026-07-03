import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitBasicCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitFetch.name,
        ToolDefinition.gitPull.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitCommit.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
        case ToolDefinition.gitStatus.name:
            return "git status --short --branch"
        case ToolDefinition.gitDiff.name:
            return args.bool("staged") == true ? "git diff --staged" : "git diff"
        case ToolDefinition.gitFetch.name:
            return try fetchCommand(arguments: args)
        case ToolDefinition.gitPull.name:
            return try pullCommand(arguments: args)
        case ToolDefinition.gitStage.name:
            let path = try WorkspaceRemoteProjectPath.relativePath(try args.requiredString("path"))
            return "git add -- \(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(path))"
        case ToolDefinition.gitRestore.name:
            let path = try WorkspaceRemoteProjectPath.relativePath(try args.requiredString("path"))
            let stagedFlag = args.bool("staged") == true ? " --staged" : ""
            return "git restore\(stagedFlag) -- \(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(path))"
        case ToolDefinition.gitCommit.name:
            let message = try args.requiredString("message").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                throw GitToolError.emptyCommitMessage
            }
            return "git commit -m \(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(message))"
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    private static func fetchCommand(arguments args: ToolArguments) throws -> String {
        try remoteGitCommand(GitFetchOptions(
            remote: args.string("remote"),
            prune: args.bool("prune") == true
        ).gitArguments)
    }

    private static func pullCommand(arguments args: ToolArguments) throws -> String {
        try remoteGitCommand(GitPullOptions(
            remote: args.string("remote"),
            branch: args.string("branch"),
            ffOnly: args.bool("ffOnly") ?? true
        ).gitArguments)
    }

    private static func remoteGitCommand(_ arguments: [String]) -> String {
        (["git"] + arguments).enumerated()
            .map { index, argument in
                index <= 1 || argument.hasPrefix("-")
                    ? argument
                    : WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(argument)
            }
            .joined(separator: " ")
    }
}
