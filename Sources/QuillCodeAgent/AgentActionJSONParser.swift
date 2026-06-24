import Foundation
import QuillComputerUseKit
import QuillCodeCore
import QuillCodeTools

public enum AgentActionJSONParser {
    public static func parse(_ text: String) throws -> AgentAction {
        let trimmed = AgentActionJSONExtractor.strippedFences(
            from: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard let object = AgentActionJSONExtractor.actionObject(in: trimmed, looksLikeAction: looksLikeActionObject) else {
            if let recovered = AgentShellCommandRecovery.recoveredAction(from: trimmed) {
                return recovered
            }
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
        let rawType = (object["type"] as? String) ?? (toolName(in: object) == nil ? nil : "tool")
        guard let type = rawType?.lowercased() else {
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
        switch type {
        case "say":
            return .say(stringValue(in: object, keys: ["text", "message", "content"]) ?? "")
        case "tool", "tool_call", "call_tool":
            guard let name = toolName(in: object) else {
                throw TrustedRouterAgentError.invalidActionJSON(text)
            }
            var arguments = canonicalArguments(for: name, in: object)
            if name == ToolDefinition.shellRun.name,
               arguments["cmd"] == nil,
               let recoveredCommand = AgentShellCommandRecovery.explicitCommand(from: trimmed) {
                arguments["cmd"] = recoveredCommand
            }
            if arguments.isEmpty && Self.requiresNonEmptyArguments(name) {
                throw TrustedRouterAgentError.emptyToolArguments(name)
            }
            if name == "host.shell.run" {
                let cmd = arguments["cmd"] as? String
                guard cmd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    throw TrustedRouterAgentError.emptyToolArguments(name)
                }
            }
            let argumentsData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
            return .tool(.init(name: name, argumentsJSON: String(decoding: argumentsData, as: UTF8.self)))
        default:
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
    }

    private static func looksLikeActionObject(_ object: [String: Any]) -> Bool {
        object["type"] is String || toolName(in: object) != nil
    }

    private static func toolName(in object: [String: Any]) -> String? {
        stringValue(in: object, keys: ["name", "tool", "toolName", "tool_name"])
    }

    private static func canonicalArguments(for toolName: String, in object: [String: Any]) -> [String: Any] {
        var arguments = argumentObject(for: toolName, in: object)
        switch toolName {
        case ToolDefinition.shellRun.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "cmd",
                aliases: ["command", "shellCommand", "shell_command", "script"],
                topLevelObject: object
            )
        case ToolDefinition.fileWrite.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "path",
                aliases: ["file", "filename", "fileName", "filepath", "filePath"],
                topLevelObject: object
            )
            normalizeStringArgument(
                &arguments,
                canonicalKey: "content",
                aliases: ["text", "contents", "body"],
                topLevelObject: object
            )
        case ToolDefinition.fileRead.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "path",
                aliases: ["file", "filename", "fileName", "filepath", "filePath"],
                topLevelObject: object
            )
        case ToolDefinition.applyPatch.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "patch",
                aliases: ["diff"],
                topLevelObject: object
            )
        case ToolDefinition.memoryRemember.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "content",
                aliases: ["memory", "note", "text"],
                topLevelObject: object
            )
        case ToolDefinition.gitPullRequestCreate.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "title",
                aliases: ["name", "subject"],
                topLevelObject: object
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
            normalizeStringArgument(
                &arguments,
                canonicalKey: "selector",
                aliases: ["number", "pr", "pullRequest", "pull_request", "url", "branch"],
                topLevelObject: object
            )
            if toolName == ToolDefinition.gitPullRequestComment.name
                || toolName == ToolDefinition.gitPullRequestReview.name {
                normalizeStringArgument(
                    &arguments,
                    canonicalKey: "body",
                    aliases: ["comment", "message", "text", "content"],
                    topLevelObject: object
                )
            }
            if toolName == ToolDefinition.gitPullRequestReviewers.name {
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
                    topLevelObject: object
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
                    topLevelObject: object
                )
            }
            if toolName == ToolDefinition.gitPullRequestLabels.name {
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
                    topLevelObject: object
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
                    topLevelObject: object
                )
            }
            if toolName == ToolDefinition.gitPullRequestReview.name {
                normalizeStringArgument(
                    &arguments,
                    canonicalKey: "action",
                    aliases: ["review", "verdict", "decision"],
                    topLevelObject: object
                )
            }
            if toolName == ToolDefinition.gitPullRequestMerge.name {
                normalizeStringArgument(
                    &arguments,
                    canonicalKey: "method",
                    aliases: ["strategy", "mergeMethod", "merge_method"],
                    topLevelObject: object
                )
            }
            if toolName == ToolDefinition.gitPullRequestCheckout.name {
                normalizeStringArgument(
                    &arguments,
                    canonicalKey: "branch",
                    aliases: ["localBranch", "local_branch", "checkoutBranch", "checkout_branch"],
                    topLevelObject: object
                )
            }
        case ToolDefinition.gitWorktreeCreate.name:
            normalizeStringArgument(
                &arguments,
                canonicalKey: "path",
                aliases: ["folder", "directory"],
                topLevelObject: object
            )
        default:
            break
        }
        return arguments
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
