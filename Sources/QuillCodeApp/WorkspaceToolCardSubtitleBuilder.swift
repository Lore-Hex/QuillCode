import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

enum WorkspaceToolCardSubtitleBuilder {
    private static let detailLimit = 72

    static func subtitle(stateLabel: String, toolName: String, inputJSON: String?) -> String {
        guard let detail = detail(toolName: toolName, inputJSON: inputJSON) else {
            return stateLabel
        }
        return "\(stateLabel) · \(detail)"
    }

    private static func detail(toolName: String, inputJSON: String?) -> String? {
        guard let inputJSON, let arguments = try? ToolArguments(inputJSON) else {
            return nil
        }

        // Match on the registered ToolDefinition names rather than string
        // literals so a renamed tool is a compile error instead of a silently
        // missing subtitle detail.
        switch toolName {
        case ToolDefinition.shellRun.name:
            return sanitized(arguments.string("cmd"))
        case ToolDefinition.fileRead.name, ToolDefinition.fileWrite.name,
             ToolDefinition.fileList.name,
             ToolDefinition.gitStage.name, ToolDefinition.gitRestore.name,
             ToolDefinition.gitStageHunk.name, ToolDefinition.gitRestoreHunk.name,
             ToolDefinition.gitPullRequestDiff.name, ToolDefinition.gitPullRequestReviewComment.name,
             ToolDefinition.gitWorktreeRemove.name:
            return sanitized(arguments.string("path"))
        case ToolDefinition.fileSearch.name:
            return sanitized(arguments.string("query"))
        case ToolDefinition.applyPatch.name:
            return "patch"
        case ToolDefinition.gitStatus.name:
            return nil
        case ToolDefinition.gitDiff.name:
            return arguments.bool("staged") == true ? "staged diff" : "working tree"
        case ToolDefinition.gitCommit.name:
            return sanitized(arguments.string("message"))
        case ToolDefinition.gitPush.name:
            return pushDetail(arguments)
        case ToolDefinition.gitPullRequestCreate.name:
            return sanitized(arguments.string("title"))
        case ToolDefinition.gitPullRequestView.name, ToolDefinition.gitPullRequestChecks.name,
             ToolDefinition.gitPullRequestCheckout.name, ToolDefinition.gitPullRequestReviewers.name,
             ToolDefinition.gitPullRequestLabels.name, ToolDefinition.gitPullRequestComment.name,
             ToolDefinition.gitPullRequestReview.name, ToolDefinition.gitPullRequestReviewReply.name,
             ToolDefinition.gitPullRequestReviewThreads.name, ToolDefinition.gitPullRequestMerge.name:
            return sanitized(arguments.string("selector"))
        case ToolDefinition.gitPullRequestReviewThread.name:
            return sanitized(arguments.string("action")) ?? sanitized(arguments.string("threadId"))
        case ToolDefinition.gitWorktreeCreate.name:
            return sanitized(arguments.string("branch")) ?? sanitized(arguments.string("path"))
        case ToolDefinition.planUpdate.name:
            return "plan"
        case ToolDefinition.handoffUpdate.name:
            return "handoff"
        case ToolDefinition.subagentsUpdate.name:
            return "subagents"
        case ToolDefinition.browserOpen.name:
            return sanitized(arguments.string("url"))
        case ToolDefinition.memoryRemember.name:
            return sanitized(arguments.string("content"))
        case ToolDefinition.mcpCall.name:
            return sanitized(arguments.string("toolName"))
        case ToolDefinition.mcpReadResource.name:
            return sanitized(arguments.string("resourceName"))
                ?? sanitized(arguments.string("name"))
                ?? sanitized(arguments.string("resourceURI"))
                ?? sanitized(arguments.string("uri"))
        case ToolDefinition.mcpGetPrompt.name:
            return sanitized(arguments.string("promptName")) ?? sanitized(arguments.string("name"))
        case ToolDefinition.computerClick.name, ToolDefinition.computerMove.name:
            return coordinateDetail(arguments, "x", "y")
        case ToolDefinition.computerScroll.name:
            return coordinateDetail(arguments, "dx", "dy")
        case ToolDefinition.computerType.name:
            return sanitized(arguments.string("text"))
        case ToolDefinition.computerKey.name:
            return sanitized(arguments.string("key"))
        default:
            return nil
        }
    }

    private static func coordinateDetail(_ arguments: ToolArguments, _ xKey: String, _ yKey: String) -> String? {
        let x = sanitized(arguments.string(xKey))
        let y = sanitized(arguments.string(yKey))
        switch (x, y) {
        case (.some(let x), .some(let y)):
            return "\(x), \(y)"
        case (.some(let x), nil):
            return x
        case (nil, .some(let y)):
            return y
        case (nil, nil):
            return nil
        }
    }

    private static func pushDetail(_ arguments: ToolArguments) -> String? {
        let remote = sanitized(arguments.string("remote"))
        let branch = sanitized(arguments.string("branch"))
        switch (remote, branch) {
        case (.some(let remote), .some(let branch)):
            return "\(remote)/\(branch)"
        case (.some(let remote), nil):
            return remote
        case (nil, .some(let branch)):
            return branch
        case (nil, nil):
            return nil
        }
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > detailLimit else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: detailLimit)
        return String(collapsed[..<end]) + "..."
    }
}
