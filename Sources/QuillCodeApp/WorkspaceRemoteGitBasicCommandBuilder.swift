import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitBasicCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
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
}
