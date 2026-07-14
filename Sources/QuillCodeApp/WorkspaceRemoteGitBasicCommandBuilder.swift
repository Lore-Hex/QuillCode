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
        ToolDefinition.gitBranchList.name,
        ToolDefinition.gitBranchSwitch.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitCommit.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
        case ToolDefinition.gitStatus.name:
            return "git status --short --branch"
        case ToolDefinition.gitDiff.name:
            return try diffCommand(arguments: args)
        case ToolDefinition.gitFetch.name:
            return try fetchCommand(arguments: args)
        case ToolDefinition.gitPull.name:
            return try pullCommand(arguments: args)
        case ToolDefinition.gitBranchList.name:
            let allFlag = args.bool("includeRemote") == false ? "" : " --all"
            return "git branch\(allFlag) --format='%(HEAD)%09%(refname:short)%09%(upstream:short)'"
        case ToolDefinition.gitBranchSwitch.name:
            let branch = try GitInputValidator.safeName(try args.requiredString("branch"))
            let create = args.bool("create") == true
            let startPoint = try GitInputValidator.trimmedNonEmpty(args.string("startPoint")).map(GitInputValidator.safeName)
            guard create || startPoint == nil else {
                throw GitToolError.branchStartPointRequiresCreate
            }
            if create {
                let quotedBranch = WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(branch)
                if let startPoint {
                    return "git switch -c \(quotedBranch) \(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(startPoint))"
                }
                return "git switch -c \(quotedBranch)"
            }
            return "git switch \(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(branch))"
        case ToolDefinition.gitStage.name:
            return "git add -- \(try quotedPaths(arguments: args))"
        case ToolDefinition.gitRestore.name:
            let stagedFlag = args.bool("staged") == true ? " --staged" : ""
            return "git restore\(stagedFlag) -- \(try quotedPaths(arguments: args))"
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

    private static func diffCommand(arguments args: ToolArguments) throws -> String {
        try remoteGitCommand(GitDiffOptions(
            staged: args.bool("staged") == true,
            commit: args.string("commit"),
            baseBranch: args.string("baseBranch")
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

    private static func quotedPaths(arguments args: ToolArguments) throws -> String {
        let rawPaths: [String]
        if let paths = args.stringArray("paths") {
            rawPaths = paths
        } else {
            rawPaths = [try args.requiredString("path")]
        }
        guard !rawPaths.isEmpty else { throw GitToolError.emptyPath }
        var seen: Set<String> = []
        return try rawPaths
            .map(WorkspaceRemoteProjectPath.relativePath)
            .filter { seen.insert($0).inserted }
            .map(WorkspaceRemoteShellCommandFormatter.shellSingleQuoted)
            .joined(separator: " ")
    }
}
