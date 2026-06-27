import Foundation
import QuillCodeCore

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
        if toolName == ToolDefinition.browserOpen.name {
            return stringValue(in: arguments, keys: ["url"]) != nil
        }
        return true
    }

    private static func normalizeArguments(
        _ arguments: inout [String: Any],
        for toolName: String,
        topLevelObject: [String: Any]
    ) {
        for rule in AgentToolArgumentNormalizationRules.matching(toolName) {
            apply(rule, to: &arguments, topLevelObject: topLevelObject)
        }
    }

    private static func apply(
        _ rule: AgentToolArgumentNormalizationRule,
        to arguments: inout [String: Any],
        topLevelObject: [String: Any]
    ) {
        for normalization in rule.stringArguments {
            normalizeStringArgument(
                &arguments,
                canonicalKey: normalization.canonicalKey,
                aliases: normalization.aliases,
                topLevelObject: topLevelObject
            )
        }
        for normalization in rule.valueArguments {
            normalizeValueArgument(
                &arguments,
                canonicalKey: normalization.canonicalKey,
                aliases: normalization.aliases,
                topLevelObject: topLevelObject
            )
        }
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
                    return nonEmptyValues
                }
            }
            if let value = object[key] as? Int {
                return value
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
            ToolDefinition.gitPullRequestReviewThreads.name,
            ToolDefinition.gitPullRequestMerge.name,
            ToolDefinition.gitWorktreeList.name,
            ToolDefinition.gitWorktreePrune.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.computerScreenshot.name:
            return false
        default:
            return true
        }
    }
}
