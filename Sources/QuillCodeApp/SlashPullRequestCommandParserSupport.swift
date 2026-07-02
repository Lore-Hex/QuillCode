import Foundation
import QuillCodeCore
import QuillCodeTools

extension SlashPullRequestCommandParser {
    static func parseList(_ argument: String) -> SlashCommand {
        let usage = "Usage: /pr list [open|closed|merged|all] [limit]"
        var state: String?
        var limit: Int?
        let tokens = argument.split(whereSeparator: \.isWhitespace).map(String.init)
        var index = tokens.startIndex

        do {
            while index < tokens.endIndex {
                let token = tokens[index]
                let normalized = String(token.drop(while: { $0 == "-" }))
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")
                if normalized == "limit" || normalized == "l" {
                    index = tokens.index(after: index)
                    guard index < tokens.endIndex, limit == nil, let parsedLimit = Int(tokens[index]) else {
                        return .invalid(usage)
                    }
                    limit = parsedLimit
                } else if normalized.hasPrefix("limit=") {
                    guard limit == nil,
                          let parsedLimit = Int(token.split(separator: "=", maxSplits: 1).last ?? "") else {
                        return .invalid(usage)
                    }
                    limit = parsedLimit
                } else if normalized == "state" {
                    index = tokens.index(after: index)
                    guard index < tokens.endIndex, state == nil else {
                        return .invalid(usage)
                    }
                    state = try GitHubPullRequestInputValidator.safeListState(tokens[index])
                } else if normalized.hasPrefix("state=") {
                    guard state == nil else { return .invalid(usage) }
                    let rawState = String(token.split(separator: "=", maxSplits: 1).last ?? "")
                    state = try GitHubPullRequestInputValidator.safeListState(rawState)
                } else if let parsedLimit = Int(token) {
                    guard limit == nil else { return .invalid(usage) }
                    limit = parsedLimit
                } else {
                    guard state == nil else { return .invalid(usage) }
                    state = try GitHubPullRequestInputValidator.safeListState(token)
                }
                index = tokens.index(after: index)
            }
            _ = try GitHubPullRequestInputValidator.safeListLimit(limit)
        } catch {
            return .invalid(usage)
        }

        return pullRequestTool(
            .gitPullRequestList,
            arguments: compact(["state": state, "limit": limit])
        )
    }

    static func selectorAndBody(from argument: String) -> (selector: String?, body: String) {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace).first else {
            return (nil, "")
        }
        let firstToken = String(first)
        guard looksLikePullRequestSelector(firstToken) else {
            return (nil, trimmed)
        }
        let bodyStart = trimmed.index(trimmed.startIndex, offsetBy: firstToken.count)
        let body = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalizedPullRequestSelector(firstToken), body)
    }

    static func pullRequestLabels(from body: String) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains(",") {
            return trimmed.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func looksLikePullRequestSelector(_ token: String) -> Bool {
        let normalized = normalizedPullRequestSelector(token)
        guard !normalized.isEmpty else { return false }
        if normalized.allSatisfy(\.isNumber) {
            return true
        }
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return true
        }
        return normalized.contains("/") && !normalized.hasPrefix("-")
    }

    static func normalizedPullRequestSelector(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
    }

    static func pullRequestTool(_ definition: ToolDefinition, selector: String) -> SlashCommand {
        pullRequestTool(definition, arguments: compact(["selector": selector]))
    }

    static func pullRequestTool(_ definition: ToolDefinition, arguments: [String: Any]) -> SlashCommand {
        .toolCall(ToolCall(name: definition.name, argumentsJSON: ToolArguments.json(arguments)))
    }

    static func parseLifecycle(_ argument: String, action: String) -> SlashCommand {
        do {
            let selector = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try GitHubPullRequestInputValidator.safeSelector(selector)
            return pullRequestTool(
                .gitPullRequestLifecycle,
                arguments: compact([
                    "selector": selector,
                    "action": try GitHubPullRequestInputValidator.safeLifecycleAction(action)
                ])
            )
        } catch {
            return .invalid("Usage: /pr close|reopen [selector]")
        }
    }

    static func compact(_ values: [String: Any?]) -> [String: Any] {
        values.compactMapValues { value in
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return value
        }
    }
}
