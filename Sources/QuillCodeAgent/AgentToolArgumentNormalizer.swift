import Foundation
import QuillComputerUseKit
import QuillCodeCore
import QuillCodeTools

enum AgentToolArgumentNormalizer {
    static func canonicalArguments(
        for toolName: String,
        in object: [String: Any],
        sourceText: String
    ) -> [String: Any] {
        var arguments = argumentObject(for: toolName, in: object)
        normalizeArguments(&arguments, for: toolName, topLevelObject: object)
        repairEmptyShellCommandIfNeeded(&arguments, toolName: toolName, sourceText: sourceText)
        return arguments
    }

    static func hasMinimumRequiredArguments(for toolName: String, arguments: [String: Any]) -> Bool {
        guard requiresNonEmptyArguments(toolName) else {
            return true
        }
        guard !arguments.isEmpty else {
            return false
        }
        if toolName == ToolDefinition.shellRun.name {
            return stringValue(in: arguments, keys: ["cmd"]) != nil
        }
        return true
    }

    private static func normalizeArguments(
        _ arguments: inout [String: Any],
        for toolName: String,
        topLevelObject: [String: Any]
    ) {
        switch toolName {
        case ToolDefinition.shellRun.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "cmd",
                aliases: ["command", "shellCommand", "shell_command", "script"],
                topLevelObject: topLevelObject
            )
        case ToolDefinition.fileWrite.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "path",
                aliases: ["file", "filename", "fileName", "filepath", "filePath"],
                topLevelObject: topLevelObject
            )
            normalizeStringArgument(
                &arguments,
                canonicalKey: "content",
                aliases: ["text", "contents", "body"],
                topLevelObject: topLevelObject
            )
        case ToolDefinition.fileRead.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "path",
                aliases: ["file", "filename", "fileName", "filepath", "filePath"],
                topLevelObject: topLevelObject
            )
        case ToolDefinition.applyPatch.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "patch",
                aliases: ["diff"],
                topLevelObject: topLevelObject
            )
        case ToolDefinition.memoryRemember.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "content",
                aliases: ["memory", "note", "text"],
                topLevelObject: topLevelObject
            )
        case ToolDefinition.gitPullRequestCreate.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "title",
                aliases: ["name", "subject"],
                topLevelObject: topLevelObject
            )
        case ToolDefinition.gitPullRequestView.name,
            ToolDefinition.gitPullRequestChecks.name,
            ToolDefinition.gitPullRequestDiff.name,
            ToolDefinition.gitPullRequestCheckout.name,
            ToolDefinition.gitPullRequestReviewers.name,
            ToolDefinition.gitPullRequestLabels.name,
            ToolDefinition.gitPullRequestComment.name,
            ToolDefinition.gitPullRequestReview.name,
            ToolDefinition.gitPullRequestMerge.name:
            normalizePullRequestArguments(&arguments, for: toolName, topLevelObject: topLevelObject)
        case ToolDefinition.gitWorktreeCreate.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "path",
                aliases: ["folder", "directory"],
                topLevelObject: topLevelObject
            )
        default:
            break
        }
    }

    private static func normalizePullRequestArguments(
        _ arguments: inout [String: Any],
        for toolName: String,
        topLevelObject: [String: Any]
    ) {
        normalizeStringArgument(
            &arguments,
            canonicalKey: "selector",
            aliases: ["number", "pr", "pullRequest", "pull_request", "url", "branch"],
            topLevelObject: topLevelObject
        )

        if toolName == ToolDefinition.gitPullRequestComment.name
            || toolName == ToolDefinition.gitPullRequestReview.name {
            normalizeStringArgument(
                &arguments,
                canonicalKey: "body",
                aliases: ["comment", "message", "text", "content"],
                topLevelObject: topLevelObject
            )
        }
        if toolName == ToolDefinition.gitPullRequestReviewers.name {
            normalizePullRequestReviewerArguments(&arguments, topLevelObject: topLevelObject)
        }
        if toolName == ToolDefinition.gitPullRequestLabels.name {
            normalizePullRequestLabelArguments(&arguments, topLevelObject: topLevelObject)
        }
        if toolName == ToolDefinition.gitPullRequestReview.name {
            normalizeStringArgument(
                &arguments,
                canonicalKey: "action",
                aliases: ["review", "verdict", "decision"],
                topLevelObject: topLevelObject
            )
        }
        if toolName == ToolDefinition.gitPullRequestMerge.name {
            normalizeStringArgument(
                &arguments,
                canonicalKey: "method",
                aliases: ["strategy", "mergeMethod", "merge_method"],
                topLevelObject: topLevelObject
            )
        }
        if toolName == ToolDefinition.gitPullRequestCheckout.name {
            normalizeStringArgument(
                &arguments,
                canonicalKey: "branch",
                aliases: ["localBranch", "local_branch", "checkoutBranch", "checkout_branch"],
                topLevelObject: topLevelObject
            )
        }
    }

    private static func normalizePullRequestReviewerArguments(
        _ arguments: inout [String: Any],
        topLevelObject: [String: Any]
    ) {
        normalizeValueArgument(
            &arguments,
            canonicalKey: "add",
            aliases: [
                "reviewers",
                "reviewer",
                "addReviewers",
                "add_reviewers",
                "requestReviewers",
                "request_reviewers"
            ],
            topLevelObject: topLevelObject
        )
        normalizeValueArgument(
            &arguments,
            canonicalKey: "remove",
            aliases: [
                "removeReviewers",
                "remove_reviewers",
                "unrequestReviewers",
                "unrequest_reviewers"
            ],
            topLevelObject: topLevelObject
        )
    }

    private static func normalizePullRequestLabelArguments(
        _ arguments: inout [String: Any],
        topLevelObject: [String: Any]
    ) {
        normalizeValueArgument(
            &arguments,
            canonicalKey: "add",
            aliases: [
                "labels",
                "label",
                "addLabels",
                "add_labels",
                "applyLabels",
                "apply_labels"
            ],
            topLevelObject: topLevelObject
        )
        normalizeValueArgument(
            &arguments,
            canonicalKey: "remove",
            aliases: [
                "removeLabels",
                "remove_labels",
                "deleteLabels",
                "delete_labels"
            ],
            topLevelObject: topLevelObject
        )
    }

    private static func repairEmptyShellCommandIfNeeded(
        _ arguments: inout [String: Any],
        toolName: String,
        sourceText: String
    ) {
        guard toolName == ToolDefinition.shellRun.name,
              arguments["cmd"] == nil,
              let recoveredCommand = AgentShellCommandRecovery.explicitCommand(from: sourceText)
        else {
            return
        }
        arguments["cmd"] = recoveredCommand
    }

    private static func argumentObject(for toolName: String, in object: [String: Any]) -> [String: Any] {
        if let arguments = object["arguments"] as? [String: Any] {
            return arguments
        }
        if let arguments = object["args"] as? [String: Any] {
            return arguments
        }
        if toolName == ToolDefinition.shellRun.name,
           let command = stringValue(in: object, keys: ["arguments", "args"]) {
            return ["cmd": command]
        }
        return [:]
    }

    private static func normalizeValueArgument(
        _ arguments: inout [String: Any],
        canonicalKey: String,
        aliases: [String],
        topLevelObject: [String: Any]
    ) {
        let keys = [canonicalKey] + aliases
        let value = supportedArgumentValue(in: arguments, keys: keys)
            ?? supportedArgumentValue(in: topLevelObject, keys: keys)
        for alias in aliases {
            arguments.removeValue(forKey: alias)
        }
        if let value {
            arguments[canonicalKey] = value
        }
    }

    private static func supportedArgumentValue(in object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = object[key] as? [String] {
                let nonEmptyValues = value
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !nonEmptyValues.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func normalizeStringArgument(
        _ arguments: inout [String: Any],
        canonicalKey: String,
        aliases: [String],
        topLevelObject: [String: Any]
    ) {
        let keys = [canonicalKey] + aliases
        let value = stringValue(in: arguments, keys: keys)
            ?? stringValue(in: topLevelObject, keys: keys)
        for alias in aliases {
            arguments.removeValue(forKey: alias)
        }
        if let value {
            arguments[canonicalKey] = value
        }
    }

    private static func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func requiresNonEmptyArguments(_ toolName: String) -> Bool {
        switch toolName {
        case ToolDefinition.gitStatus.name,
            ToolDefinition.gitDiff.name,
            ToolDefinition.gitPullRequestView.name,
            ToolDefinition.gitPullRequestChecks.name,
            ToolDefinition.gitPullRequestCheckout.name,
            ToolDefinition.gitPullRequestMerge.name,
            ToolDefinition.gitWorktreeList.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.computerScreenshot.name:
            return false
        default:
            return true
        }
    }
}
